import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

from torch.nn import Linear, BatchNorm1d
from models.layers.quantisation.observer import Observer, FakeQuantize, quantize_tensor


class MyPointNetConv(nn.Module):
    def __init__(
        self,
        input_dim: int,
        output_dim: int,
        bias: bool = False,
        num_bits: int = 8,
        first_layer: bool = False,
        input_bits: int = 8,  # kept for API compatibility (unused)
        cfg = None,
    ):
        super(MyPointNetConv, self).__init__()

        self.cfg = cfg

        self.input_dim = int(input_dim)
        self.output_dim = int(output_dim)
        self.bias = bool(bias)
        self.num_bits = int(num_bits)
        self.first_layer = bool(first_layer)

        # Number of bits for quantization scales (FPGA export)
        self.num_bits_obs = 32
        self._Q = float(2 ** self.num_bits_obs)

        # Layers
        self.linear = Linear(self.input_dim, self.output_dim, bias=self.bias)
        self.norm = BatchNorm1d(self.output_dim)
        self.global_nn = None

        self.reset_parameters()

        # Modes
        self.register_buffer("calib_mode", torch.tensor(False, requires_grad=False))
        self.register_buffer("quantize_mode", torch.tensor(False, requires_grad=False))

        # Observers
        self.observer_input = Observer(num_bits=self.num_bits)
        self.observer_weight = Observer(num_bits=self.num_bits)
        self.observer_output = Observer(num_bits=self.num_bits)

        # Quant parameters
        self.register_buffer("m", torch.tensor(1.0, requires_grad=False))
        self.register_buffer("qscale_in", torch.tensor(1.0, requires_grad=False))
        self.register_buffer("qscale_w", torch.tensor(1.0, requires_grad=False))
        self.register_buffer("qscale_out", torch.tensor(1.0, requires_grad=False))
        self.register_buffer("qscale_m", torch.tensor(1.0, requires_grad=False))
        self.register_buffer("num_bits_model", torch.tensor(self.num_bits, requires_grad=False))
        self.register_buffer("num_bits_scale", torch.tensor(self.num_bits_obs, requires_grad=False))

        # Created in quantize()
        self.qlinear = None

    def reset_parameters(self):
        self.linear.reset_parameters()
        self.norm.reset_parameters()

    def forward(self, x: torch.Tensor, pos: torch.Tensor, edge_index: torch.Tensor) -> torch.Tensor:
        out = self.message(x, pos, edge_index)
        return out

    def message(self, x: torch.Tensor, pos: torch.Tensor, edge_index: torch.Tensor) -> torch.Tensor:
        if self.calib_mode.item() and not self.quantize_mode.item():
            return self.message_calib(x, pos, edge_index)
        elif self.quantize_mode.item():
            return self.message_quant(x, pos, edge_index)
        elif not self.calib_mode.item() and not self.quantize_mode.item():
            return self.message_float(x, pos, edge_index)
        else:
            raise ValueError("Invalid mode")

    def message_float(self, x: torch.Tensor, pos: torch.Tensor, edge_index: torch.Tensor) -> torch.Tensor:
        # gather messages
        pos_i = pos[edge_index[:, 0]]
        pos_j = pos[edge_index[:, 1]]
        x_j = x[edge_index[:, 1]]
        msg = torch.cat((x_j, pos_j - pos_i), dim=1)

        # linear + BN
        msg = self.linear(msg)
        msg = self.norm(msg)

        # pool by dst node (edge_index[:,0]) using amax
        unique_positions, indices = torch.unique(edge_index[:, 0], dim=0, return_inverse=True)
        expanded_indices = indices.unsqueeze(1).expand(-1, self.output_dim)

        pooled_features = torch.zeros(
            (unique_positions.size(0), self.output_dim),
            dtype=msg.dtype,
            device=x.device,
        )
        pooled_features = pooled_features.scatter_reduce(
            0, expanded_indices, msg, reduce="amax", include_self=False
        )
        return pooled_features

    def merge_norm(self, running_mean: torch.Tensor, running_var: torch.Tensor):
        """
        Merge BatchNorm parameters into Linear to produce fused (W_fused, b_fused) such that:
            BN(Linear(msg)) == Linear_fused(msg)

        Returns:
            W_fused: [out_dim, in_dim]
            b_fused: [out_dim]
        """
        std = torch.sqrt(running_var + self.norm.eps)

        if self.norm.affine:
            gamma = self.norm.weight
            beta = self.norm.bias
        else:
            gamma = torch.ones_like(std)
            beta = torch.zeros_like(std)

        W = self.linear.weight
        if self.bias:
            b = self.linear.bias
        else:
            b = torch.zeros(self.output_dim, device=W.device, dtype=W.dtype)

        W_fused = (gamma / std).unsqueeze(1) * W
        b_fused = (gamma / std) * (b - running_mean) + beta
        return W_fused, b_fused

    def message_calib(self, x: torch.Tensor, pos: torch.Tensor, edge_index: torch.Tensor) -> torch.Tensor:
        # gather messages
        pos_i = pos[edge_index[:, 0]]
        pos_j = pos[edge_index[:, 1]]
        x_j = x[edge_index[:, 1]]
        msg = torch.cat((x_j, pos_j - pos_i), dim=1)

        # fake-quantize inputs
        if self.training:
            self.observer_input.update(msg)
        msg = FakeQuantize.apply(msg, self.observer_input)

        # if training, run a dummy through BN to update its stats
        if self.training:
            dummy = self.linear(msg)
            _ = self.norm(dummy)

        # fuse BN into linear weights/bias (via helper)
        W_fused, b_fused = self.merge_norm(self.norm.running_mean, self.norm.running_var)

        # fake-quantize fused weights
        if self.training:
            self.observer_weight.update(W_fused)
        W_q = FakeQuantize.apply(W_fused, self.observer_weight)

        # apply quantized linear with fused bias
        msg = F.linear(msg, W_q, b_fused)

        # update output observer and fake-quantize output
        if self.training:
            self.observer_output.update(msg)
            self.observer_output.update(pos_j - pos_i)
        msg = FakeQuantize.apply(msg, self.observer_output)

        # pool by dst node using amax
        unique_positions, indices = torch.unique(edge_index[:, 0], dim=0, return_inverse=True)
        expanded_indices = indices.unsqueeze(1).expand(-1, self.output_dim)

        pooled_features = torch.zeros(
            (unique_positions.size(0), self.output_dim),
            dtype=x.dtype,  # preserve your original dtype choice
            device=x.device,
        )
        pooled_features = pooled_features.scatter_reduce(
            0, expanded_indices, msg, reduce="amax", include_self=False
        )
        return pooled_features

    def message_quant(self, x: torch.Tensor, pos: torch.Tensor, edge_index: torch.Tensor) -> torch.Tensor:
        if self.qlinear is None:
            raise RuntimeError("qlinear is not initialized. Call quantize() before running in quant mode.")

        # gather message and quantize appropriately
        if self.first_layer:
            pos_i = pos[edge_index[:, 0]]
            pos_j = pos[edge_index[:, 1]]
            x_j = x[edge_index[:, 1]]
            msg = torch.cat((x_j, pos_j - pos_i), dim=1)
            msg = self.observer_input.quantize_tensor(msg)
        else:
            pos_i = pos[edge_index[:, 0]]
            pos_j = pos[edge_index[:, 1]]
            pos_q = self.observer_input.quantize_tensor(pos_j - pos_i)
            msg = torch.cat((x[edge_index[:, 1]], pos_q), dim=1)

        # integer-emulated linear
        msg = msg - self.observer_input.zero_point
        msg = self.qlinear(msg)
        msg = (msg * self.m).round() + self.observer_output.zero_point
        msg = torch.clamp(msg, 0, 2 ** self.num_bits - 1)

        # pool by dst node using amax
        unique_positions, indices = torch.unique(edge_index[:, 0], dim=0, return_inverse=True)
        expanded_indices = indices.unsqueeze(1).expand(-1, self.output_dim)

        pooled_features = torch.zeros(
            (unique_positions.size(0), self.output_dim),
            dtype=x.dtype,  # preserve your original dtype choice
            device=x.device,
        )
        pooled_features = pooled_features.scatter_reduce(
            0, expanded_indices, msg, reduce="amax", include_self=False
        )
        return pooled_features

    def calibrate(self):
        self.calib_mode.fill_(True)

    def quantize(self, observer_input: Observer = None, observer_output: Observer = None):
        """
        Quantize model:
          - snap observer scales to fixed-point (for FPGA export)
          - compute m
          - fuse BN into linear params
          - build qlinear with quantized fused weights/bias
        """
        self.quantize_mode.fill_(True)

        if observer_input is not None:
            self.observer_input = observer_input
        if observer_output is not None:
            self.observer_output = observer_output

        # Snap observer scales
        self.qscale_in.copy_((self._Q * self.observer_input.scale).round())
        self.observer_input.scale = self.qscale_in / self._Q

        self.qscale_w.copy_((self._Q * self.observer_weight.scale).round())
        self.observer_weight.scale = self.qscale_w / self._Q

        self.qscale_out.copy_((self._Q * self.observer_output.scale).round())
        self.observer_output.scale = self.qscale_out / self._Q

        # Compute and snap m
        m_float = (self.observer_weight.scale * self.observer_input.scale) / self.observer_output.scale
        self.qscale_m.copy_((self._Q * m_float).round())
        self.m.copy_(self.qscale_m / self._Q)

        # Fuse BN into linear (via helper)
        weight_fused, bias_fused = self.merge_norm(self.norm.running_mean, self.norm.running_var)

        # Build qlinear (always bias=True after BN fusion)
        device = self.linear.weight.device
        with torch.no_grad():
            self.qlinear = Linear(self.input_dim, self.output_dim, bias=True).to(device)

            q_w = self.observer_weight.quantize_tensor(weight_fused)
            q_w = q_w - self.observer_weight.zero_point
            self.qlinear.weight.copy_(q_w)

            q_b = quantize_tensor(
                bias_fused,
                scale=self.observer_weight.scale * self.observer_input.scale,
                zero_point=0,
                num_bits=32,
                signed=True,
            )
            self.qlinear.bias.copy_(q_b)

    def get_parameters(self, file_name: str = None):
        if file_name is None:
            raise ValueError("file_name must be provided")
        if self.qlinear is None:
            raise RuntimeError("qlinear is not initialized. Call quantize() before exporting.")

        with open(file_name, "w") as f:
            f.write(f"Input scale ({int(self.num_bits_obs)} bit):\n {int(self.qscale_in)}\n")

            # This is based on normalisation in kws model!!!!!
            temporal_scale = 1 / (self.qscale_in / self._Q * self.cfg.dataset.high_time_radius)
            temporal_scale = (temporal_scale * self._Q).round()
            f.write(f"Input scale temporal normalisation ({int(self.num_bits_obs)} bit):\n {int(temporal_scale)}\n (remember to inverse diff calculation or include change in sing)")

            channel_scale = 1 / (self.qscale_in / self._Q * self.cfg.dataset.channel_radius)
            channel_scale = (channel_scale * self._Q).round()
            f.write(f"Input scale channel normalisation ({int(self.num_bits_obs)} bit):\n {int(channel_scale)}\n")

            f.write(f"Input zero point:\n {int(self.observer_input.zero_point)}\n")
            f.write(f"Weight scale ({int(self.num_bits_obs)} bit):\n {int(self.qscale_w)}\n")
            f.write(f"Weight zero point:\n {int(self.observer_weight.zero_point)}\n")
            f.write(f"Output scale ({int(self.num_bits_obs)} bit):\n {int(self.qscale_out)}\n")
            f.write(f"Output zero point:\n {int(self.observer_output.zero_point)}\n")
            f.write(f"M Scales ({int(self.num_bits_obs)} bit):\n {int(self.qscale_m)}\n")

            f.write("Input quantisation (only for first layer):\n")
            scale = int(self.qscale_in) / (2 ** self.num_bits_obs - 1)
            scale_f = scale * self.cfg.dataset.num_channels * (1 + self.cfg.dataset.polarity) * (1 + self.cfg.dataset.stereo)
            scale_f = 1 / scale_f
            scale_f_int = int(round((2 ** self.num_bits_obs-1) * scale_f))

            scale_t = scale * self.cfg.dataset.time_window
            scale_t_f = 1 / scale_t
            scale_t_int = int(round((2 ** self.num_bits_obs-1) * scale_t_f))
            f.write(f"F scale (for 32 bits):{int(scale_f_int)}\n")
            f.write(f"T scale (for 32 bits):{int(scale_t_int)}\n")

            # weights/bias (qlinear)
            bias = torch.flip(self.qlinear.bias, [0]).detach().cpu().numpy().astype(np.int32).tolist()
            weight = torch.flip(self.qlinear.weight, [1]).detach().cpu().numpy().astype(np.int32).tolist()

            f.write(f"Weight ({int(self.num_bits)} bit):\n")
            for idx, w in enumerate(weight):
                f.write(f"weights_conv[{idx}] = {str(w).replace('[', '{').replace(']', '}') + ';'}\n")

            f.write(f"\nBias ({int(self.num_bits)} bit):\n")
            f.write(f"bias_conv = {str(bias).replace('[', '{').replace(']', '}') + ';'}\n")

            # "LUT" for pos quantization range (debug/export)
            input_range = list(range(int(self.observer_input.min), int(self.observer_input.max + 1)))
            out_range = self.observer_input.quantize_tensor(
                torch.tensor(input_range, device=self.linear.weight.device)
            ) - self.observer_input.zero_point
            out_range = out_range.detach().cpu().numpy().astype(np.int32).tolist()

            f.write(f"Input range ({int(self.num_bits)} bit):\n {input_range}\n")
            f.write(f"Output range ({int(self.num_bits)} bit):\n {out_range}\n")

        # MEM packing (same as your original, with 72-bit chunking)
        with open(file_name.replace(".txt", ".mem"), "w") as f:
            w_zp = self.observer_weight.zero_point.to(torch.int32).item()
            x_zp = self.observer_input.zero_point.to(torch.int32).item()

            bias = torch.flip(self.qlinear.bias, [0]).detach().cpu().numpy().astype(np.int32).tolist()
            weight = torch.flip(self.qlinear.weight, [1]).detach().cpu().numpy().astype(np.int32).tolist()

            for idx, we in enumerate(weight):
                bin_vec = [
                    np.binary_repr(w + int(w_zp), width=self.num_bits + 1)[1:]
                    for w in we
                ]
                Z1a2 = sum([w + int(w_zp) for w in we]) * int(x_zp)
                NZ1Z2 = self.input_dim * int(x_zp) * int(w_zp)

                bin_vec.append(np.binary_repr(int(bias[len(bias) - idx - 1] - Z1a2 + NZ1Z2), width=32))
                bits = "".join(bin_vec)

                for i in range(0, len(bits), 72):
                    chunk = bits[i:i + 72]
                    f.write(f"{hex(int(chunk, 2))[2:]}\n")

    def __repr__(self) -> str:
        return (
            f"{self.__class__.__name__}(local_nn={self.linear}, global_nn={self.global_nn}), "
            f"num_bits={self.num_bits}, first_layer={self.first_layer}"
        )
