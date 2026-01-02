import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

from models.layers.quantisation.observer import Observer, FakeQuantize, quantize_tensor


class MyLinear(nn.Module):
    """Quantized version of nn.Linear with PTQ observers and FPGA-friendly parameter export."""

    def __init__(self, input_dim: int = 1, output_dim: int = 4, bias: bool = True, num_bits: int = 8):
        super().__init__()

        self.input_dim = int(input_dim)
        self.output_dim = int(output_dim)
        self.bias = bool(bias)
        self.num_bits = int(num_bits)

        # Fixed-point precision for exported scales
        self.num_bits_obs = 32
        self._Q = float(2 ** self.num_bits_obs)

        self.linear = nn.Linear(self.input_dim, self.output_dim, bias=self.bias)
        self.reset_parameters()

        # Modes
        self.register_buffer("calib_mode", torch.tensor(False))
        self.register_buffer("quantize_mode", torch.tensor(False))

        # Observers
        self.observer_input = Observer(num_bits=self.num_bits)
        self.observer_weight = Observer(num_bits=self.num_bits)
        self.observer_output = Observer(num_bits=self.num_bits)

        # Runtime scale for quant path: y = round((Wx+b)*m) + zp_out
        self._register_scalar("m", 1.0)

        # Exported qscales
        self._register_scalar("qscale_in", 1.0)
        self._register_scalar("qscale_w", 1.0)
        self._register_scalar("qscale_out", 1.0)
        self._register_scalar("qscale_m", 1.0)

        # Metadata buffers (kept if you use them downstream)
        self.register_buffer("num_bits_model", torch.tensor(self.num_bits))
        self.register_buffer("num_bits_scale", torch.tensor(self.num_bits_obs))

        # Set externally if this is the first layer in the model
        self.first_layer = False

    # ---------------------------------------------------------------------
    # Utilities
    # ---------------------------------------------------------------------
    def _register_scalar(self, name: str, value: float):
        self.register_buffer(name, torch.tensor(float(value), dtype=torch.float32))

    def _snap_observer_scale(self, qscale_buf: torch.Tensor, obs: Observer):
        """
        Quantize observer scale to fixed-point (for FPGA export consistency):
          qscale = round(2^num_bits_obs * obs.scale)
          obs.scale = qscale / 2^num_bits_obs
        """
        qscale_buf.copy_((self._Q * obs.scale).round())
        obs.scale = qscale_buf / self._Q

    @staticmethod
    def _to_i32_list(x: torch.Tensor):
        return x.detach().cpu().numpy().astype(np.int32).tolist()

    # ---------------------------------------------------------------------
    # Core API
    # ---------------------------------------------------------------------
    def reset_parameters(self):
        self.linear.reset_parameters()

    def calibrate(self):
        self.calib_mode.fill_(True)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        if self.quantize_mode.item():
            return self.forward_quant(x)
        if self.calib_mode.item():
            return self.forward_calib(x)
        return self.forward_float(x)

    def forward_float(self, x: torch.Tensor) -> torch.Tensor:
        return self.linear(x)

    def forward_calib(self, x: torch.Tensor) -> torch.Tensor:
        """
        Calibration forward:
        - Update observers (when training)
        - Fake-quantize input/weights/output
        """
        if self.training:
            self.observer_input.update(x)
        x_q = FakeQuantize.apply(x, self.observer_input)

        if self.training:
            self.observer_weight.update(self.linear.weight.data)
        w_q = FakeQuantize.apply(self.linear.weight, self.observer_weight)

        if self.bias:
            y = F.linear(x_q, w_q, self.linear.bias)
        else:
            y = F.linear(x_q, w_q)

        if self.training:
            self.observer_output.update(y)
        y_q = FakeQuantize.apply(y, self.observer_output)
        return y_q
    
    def forward_quant(self, x: torch.Tensor) -> torch.Tensor:
        """
        Quantized forward:
        - First layer: quantize input, subtract zp
        - Later layers: assume x already in quant domain, just subtract zp
        - Apply linear, rescale by m, add output zp, clamp to uint range
        """
        if self.first_layer:
            x_q = self.observer_input.quantize_tensor(x)
            x_q = x_q - self.observer_input.zero_point
        else:
            x_q = x - self.observer_input.zero_point

        y = self.linear(x_q)
        y = (y * self.m).round() + self.observer_output.zero_point
        y = y.clamp(0, 2 ** self.num_bits - 1)
        return y

    def quantize(self, observer_input: Observer = None, observer_output: Observer = None):
        """
        Quantize model:
        - Snap scales for input/weight/output to fixed-point
        - Compute m = (s_w * s_in) / s_out (also snapped)
        - Quantize and store weights (and bias if present) in module params
        """
        self.quantize_mode.fill_(True)

        if observer_input is not None:
            self.observer_input = observer_input
        if observer_output is not None:
            self.observer_output = observer_output

        # 1) Snap observer scales
        self._snap_observer_scale(self.qscale_in, self.observer_input)
        self._snap_observer_scale(self.qscale_w, self.observer_weight)
        self._snap_observer_scale(self.qscale_out, self.observer_output)

        # 2) Compute and snap m
        m_float = (self.observer_weight.scale * self.observer_input.scale) / self.observer_output.scale
        self.qscale_m.copy_((self._Q * m_float).round())
        self.m.copy_(self.qscale_m / self._Q)

        # 3) Quantize weights to int domain and center around zero-point
        q_w = self.observer_weight.quantize_tensor(self.linear.weight)  # [0..2^bits-1] typically
        q_w = q_w - self.observer_weight.zero_point
        self.linear.weight = nn.Parameter(q_w)

        # 4) Quantize bias to int32 if present
        if self.bias:
            q_b = quantize_tensor(
                self.linear.bias,
                scale=self.observer_input.scale * self.observer_weight.scale,
                zero_point=0,
                num_bits=32,
                signed=True,
            )
            self.linear.bias = nn.Parameter(q_b)

    # ---------------------------------------------------------------------
    # Export
    # ---------------------------------------------------------------------
    def get_parameters(self, file_name: str):
        """
        Exports:
          - .txt with scales/zero-points and weights/bias
          - .mem with packed row bits + 32-bit bias (if bias=True)
        """
        if file_name is None:
            raise ValueError("file_name must be provided")

        file_name = str(file_name)

        # ---- TXT ----
        with open(file_name, "w") as f:
            f.write(f"Input scale ({self.num_bits_obs} bit):\n {int(self.qscale_in)}\n")
            f.write(f"Input zero point:\n {int(self.observer_input.zero_point)}\n")
            f.write(f"Weight scale ({self.num_bits_obs} bit):\n {int(self.qscale_w)}\n")
            f.write(f"Weight zero point:\n {int(self.observer_weight.zero_point)}\n")
            f.write(f"Output scale ({self.num_bits_obs} bit):\n {int(self.qscale_out)}\n")
            f.write(f"Output zero point:\n {int(self.observer_output.zero_point)}\n")
            f.write(f"M scale ({self.num_bits_obs} bit):\n {int(self.qscale_m)}\n")

            # Weights (flip input dim)
            weight = torch.flip(self.linear.weight, [1])
            weight_list = self._to_i32_list(weight)

            f.write(f"Weight ({self.num_bits} bit):\n")
            for idx, row in enumerate(weight_list):
                f.write(f"weights_conv[{idx}] = {str(row).replace('[', '{').replace(']', '}')};\n")

            bias_list = None
            if self.bias:
                bias = torch.flip(self.linear.bias, [0])
                bias_list = self._to_i32_list(bias)
                f.write(f"\nBias ({self.num_bits} bit):\n {str(bias_list).replace('[', '{').replace(']', '}')};\n")

        # ---- MEM ----
        mem_name = file_name.replace(".txt", ".mem")
        with open(mem_name, "w") as f:
            w_zp = int(self.observer_weight.zero_point.to(torch.int32).item())
            x_zp = int(self.observer_input.zero_point.to(torch.int32).item())

            # If bias=False, export bias=0 to keep packing format stable (optional)
            if bias_list is None:
                bias_list = [0 for _ in range(self.output_dim)]

            for row_idx, row in enumerate(weight_list):
                # 8-bit weight payload per weight (dropping MSB of 9-bit repr like your original)
                bin_vec = [np.binary_repr(w + w_zp, width=9)[1:] for w in row]

                # Compensation terms (preserving your original math)
                Z1a2 = sum([w + w_zp for w in row]) * x_zp
                NZ1Z2 = self.input_dim * x_zp * w_zp

                # bias index reversed as in original code
                b = bias_list[len(bias_list) - row_idx - 1] - Z1a2 + NZ1Z2
                bin_vec.append(np.binary_repr(int(b), width=32))

                bits = "".join(bin_vec)
                f.write(f"{hex(int(bits, 2))[2:]}\n")

    def __repr__(self):
        return (
            f"{self.__class__.__name__}(input_dim={self.input_dim}, "
            f"output_dim={self.output_dim}, bias={self.bias}, num_bits={self.num_bits})"
        )
