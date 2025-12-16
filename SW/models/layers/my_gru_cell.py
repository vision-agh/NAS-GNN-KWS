import math
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

from models.layers.quantisation.observer import (
    Observer, FakeQuantize, quantize_tensor, dequantize_tensor
)


class MyGRUCell(nn.Module):
    def __init__(self,
                 input_size: int,
                 hidden_size: int,
                 num_bits: int = 8):
        super(MyGRUCell, self).__init__()
        """
        GRU cell with observers for post-training quantization.
        This version makes CALIBRATION fast by collecting stats only (no per-step fake quant / LUT builds).
        """

        self.input_size = input_size
        self.hidden_size = hidden_size

        # GRU weights
        self.linear_ih = nn.Linear(input_size, 3 * hidden_size)
        self.linear_hh = nn.Linear(hidden_size, 3 * hidden_size)

        # Initialize weights
        self.reset_parameters()

        # Observers for quantization
        self.num_bits = num_bits
        self.num_bits_obs = 32

        self.observer_input = Observer(num_bits=num_bits)
        self.observer_hidden = Observer(num_bits=num_bits)

        self.weight_ih_observer = Observer(num_bits=num_bits)
        self.weight_hh_observer = Observer(num_bits=num_bits)

        self.output_linear_observer = Observer(num_bits=num_bits)

        # Observer for sigmoid outs
        self.output_observer_sigmoid_r = Observer(num_bits=num_bits)
        self.output_observer_sigmoid_z = Observer(num_bits=num_bits)

        # Observer for tanh out
        self.output_observer_tanh_n = Observer(num_bits=num_bits)

        # Observers for intermediate products
        self.output_observer_r_hn = Observer(num_bits=num_bits)
        self.output_observer_z_n  = Observer(num_bits=num_bits)
        self.output_observer_z_h  = Observer(num_bits=num_bits)

        # LUTs
        self.register_buffer('lut_sigmoid_r',    torch.zeros(2 ** (num_bits + 1), dtype=torch.float32))
        self.register_buffer('lut_sigmoid_z',    torch.zeros(2 ** (num_bits + 1), dtype=torch.float32))
        self.register_buffer('lut_tanh_n',       torch.zeros(2 ** (num_bits + 1), dtype=torch.float32))
        self.register_buffer('lut_rescale_i_n',  torch.zeros(2 ** num_bits,       dtype=torch.float32))

        # Pre-allocated index domains (moved with the module to the right device)
        max_lin = 2 ** (self.output_observer_sigmoid_r.num_bits + 1)
        self.register_buffer('sigmoid_domain', torch.arange(max_lin, dtype=torch.float32))
        self.register_buffer('tanh_domain',    torch.arange(max_lin, dtype=torch.float32))
        self.register_buffer('rescale_domain', torch.arange(2 ** self.output_observer_r_hn.num_bits, dtype=torch.float32))

        # Scales / zero-points used by quant path (filled in quantize())
        self.register_buffer('scale_ih',        torch.tensor(1.0, requires_grad=False))
        self.register_buffer('scale_hh',        torch.tensor(1.0, requires_grad=False))
        self.register_buffer('scale_r_hn',      torch.tensor(1.0, requires_grad=False))
        self.register_buffer('scale_z_n',       torch.tensor(1.0, requires_grad=False))
        self.register_buffer('scale_z_h',       torch.tensor(1.0, requires_grad=False))
        self.register_buffer('scale_new_h_zn',  torch.tensor(1.0, requires_grad=False))
        self.register_buffer('scale_new_h_zh',  torch.tensor(1.0, requires_grad=False))

        self.register_buffer('quant_1',         torch.tensor(1.0, requires_grad=False))

        # Modes
        self.register_buffer('calib_mode',      torch.tensor(False, requires_grad=False))
        self.register_buffer('quantize_mode',   torch.tensor(False, requires_grad=False))

        # Scales for quantization
        self.register_buffer('qscale_in',       torch.tensor(1.0, requires_grad=False)) # observer_input
        self.register_buffer('qscale_h',        torch.tensor(1.0, requires_grad=False)) # observer_hidden
        self.register_buffer('qscale_w_ih',        torch.tensor(1.0, requires_grad=False)) # weight_ih_observer
        self.register_buffer('qscale_w_hh',        torch.tensor(1.0, requires_grad=False)) # weight_hh_observer
        self.register_buffer('qscale_out_linear',      torch.tensor(1.0, requires_grad=False)) # output_linear_observer
        self.register_buffer('qscale_out_sigmoid_r',  torch.tensor(1.0, requires_grad=False)) # output_observer_sigmoid_r
        self.register_buffer('qscale_out_sigmoid_z',  torch.tensor(1.0, requires_grad=False)) # output_observer_sigmoid_z
        self.register_buffer('qscale_out_tanh_n',       torch.tensor(1.0, requires_grad=False)) # output_observer_tanh_n
        self.register_buffer('qscale_out_r_hn',        torch.tensor(1.0, requires_grad=False)) # output_observer_r_hn
        self.register_buffer('qscale_out_z_n',         torch.tensor(1.0, requires_grad=False)) # output_observer_z_n
        self.register_buffer('qscale_out_z_h',         torch.tensor(1.0, requires_grad=False)) # output_observer_z_h    

        self.register_buffer('qscale_ih',        torch.tensor(1.0, requires_grad=False)) # scale_ih
        self.register_buffer('qscale_hh',        torch.tensor(1.0, requires_grad=False)) # scale_hh
        self.register_buffer('qscale_r_hn',      torch.tensor(1.0, requires_grad=False)) # scale_r_hn
        self.register_buffer('qscale_z_n',       torch.tensor(1.0, requires_grad=False)) # scale_z_n
        self.register_buffer('qscale_z_h',       torch.tensor(1.0, requires_grad=False)) # scale_z_h
        self.register_buffer('qscale_new_h_zn',  torch.tensor(1.0, requires_grad=False)) # scale_new_h_zn
        self.register_buffer('qscale_new_h_zh',  torch.tensor(1.0, requires_grad=False)) # scale_new_h_zh


    def reset_parameters(self) -> None:
        std = 1.0 / math.sqrt(self.hidden_size)
        for w in self.parameters():
            w.data.uniform_(-std, std)

    def forward(self,
                x: torch.Tensor,
                h: torch.Tensor) -> torch.Tensor:
        """
        Dispatch by mode.
        """
        if self.calib_mode.item() and not self.quantize_mode.item():
            return self.forward_calib(x, h)
        elif self.quantize_mode.item():
            return self.forward_quant(x, h)
        elif not self.calib_mode.item() and not self.quantize_mode.item():
            return self.forward_float(x, h)
        else:
            raise ValueError('Invalid mode')

    def calibrate(self):
        self.calib_mode.fill_(True)

    def quantize(self,
                 observer_input: Observer = None,
                 observer_output: Observer = None):

        self.quantize_mode.fill_(True)

        if observer_input is not None:
            self.observer_input = observer_input
        if observer_output is not None:
            self.observer_output = observer_output  # optional, not used directly here

        # Calculate scales for FPGA
        self.qscale_in.copy_( (2**self.num_bits_obs * self.observer_input.scale).round() )
        self.observer_input.scale = self.qscale_in / (2 ** self.num_bits_obs)

        self.qscale_h.copy_( (2**self.num_bits_obs * self.observer_hidden.scale).round() )
        self.observer_hidden.scale = self.qscale_h / (2 ** self.num_bits_obs)

        self.qscale_w_ih.copy_( (2**self.num_bits_obs * self.weight_ih_observer.scale).round() )
        self.weight_ih_observer.scale = self.qscale_w_ih / (2 ** self.num_bits_obs)

        self.qscale_w_hh.copy_( (2**self.num_bits_obs * self.weight_hh_observer.scale).round() )
        self.weight_hh_observer.scale = self.qscale_w_hh / (2 ** self.num_bits_obs)

        self.qscale_out_linear.copy_( (2**self.num_bits_obs * self.output_linear_observer.scale).round() )
        self.output_linear_observer.scale = self.qscale_out_linear / (2 ** self.num_bits_obs)

        self.qscale_out_sigmoid_r.copy_( (2**self.num_bits_obs * self.output_observer_sigmoid_r.scale).round() )
        self.output_observer_sigmoid_r.scale = self.qscale_out_sigmoid_r / ( 2 ** self.num_bits_obs)

        self.qscale_out_sigmoid_z.copy_( (2**self.num_bits_obs * self.output_observer_sigmoid_z.scale).round() )
        self.output_observer_sigmoid_z.scale = self.qscale_out_sigmoid_z / ( 2 ** self.num_bits_obs)

        self.qscale_out_tanh_n.copy_( (2**self.num_bits_obs * self.output_observer_tanh_n.scale).round() )
        self.output_observer_tanh_n.scale = self.qscale_out_tanh_n / ( 2 ** self.num_bits_obs)

        self.qscale_out_r_hn.copy_( (2**self.num_bits_obs * self.output_observer_r_hn.scale).round() )
        self.output_observer_r_hn.scale = self.qscale_out_r_hn / ( 2 ** self.num_bits_obs)

        self.qscale_out_z_n.copy_( (2**self.num_bits_obs * self.output_observer_z_n.scale).round() )
        self.output_observer_z_n.scale = self.qscale_out_z_n / ( 2 ** self.num_bits_obs)

        # Quantize the INPUT linear
        q_weight_ih = self.weight_ih_observer.quantize_tensor(self.linear_ih.weight) - self.weight_ih_observer.zero_point
        q_bias_ih   = quantize_tensor(self.linear_ih.bias,
                                      scale=self.weight_ih_observer.scale * self.observer_input.scale,
                                      zero_point=0, num_bits=32, signed=True)
        self.linear_ih.weight = nn.Parameter(q_weight_ih)
        self.linear_ih.bias   = nn.Parameter(q_bias_ih)
        self.scale_ih = (self.weight_ih_observer.scale * self.observer_input.scale) / self.output_linear_observer.scale

        self.qscale_ih.copy_( (2**self.num_bits_obs * self.scale_ih).round() )
        self.scale_ih = self.qscale_ih / (2 ** self.num_bits_obs)

        # Quantize the HIDDEN linear
        q_weight_hh = self.weight_hh_observer.quantize_tensor(self.linear_hh.weight) - self.weight_hh_observer.zero_point
        q_bias_hh   = quantize_tensor(self.linear_hh.bias,
                                      scale=self.weight_hh_observer.scale * self.observer_hidden.scale,
                                      zero_point=0, num_bits=32, signed=True)
        self.linear_hh.weight = nn.Parameter(q_weight_hh)
        self.linear_hh.bias   = nn.Parameter(q_bias_hh)
        self.scale_hh = (self.weight_hh_observer.scale * self.observer_hidden.scale) / self.output_linear_observer.scale

        self.qscale_hh.copy_( (2**self.num_bits_obs * self.scale_hh).round() )
        self.scale_hh = self.qscale_hh / (2 ** self.num_bits_obs)

        # Precompute all scalar scales for elementwise ops
        self.scale_r_hn = (self.output_observer_sigmoid_r.scale * self.output_linear_observer.scale) / self.output_observer_r_hn.scale

        self.qscale_r_hn.copy_( (2**self.num_bits_obs * self.scale_r_hn).round() )
        self.scale_r_hn = self.qscale_r_hn / (2 ** self.num_bits_obs)

        self.quant_1 = quantize_tensor(torch.tensor(1.0, device=self.observer_hidden.scale.device),
                                       scale=self.output_observer_sigmoid_z.scale,
                                       zero_point=self.output_observer_sigmoid_z.zero_point,
                                       num_bits=self.output_observer_sigmoid_z.num_bits)

        self.scale_z_n = (self.output_observer_sigmoid_z.scale * self.output_observer_tanh_n.scale) / self.output_observer_z_n.scale
        self.scale_z_h = (self.output_observer_sigmoid_z.scale * self.observer_hidden.scale) / self.output_observer_z_h.scale

        self.qscale_z_n.copy_( (2**self.num_bits_obs * self.scale_z_n).round() )
        self.scale_z_n = self.qscale_z_n / (2 ** self.num_bits_obs)
        self.qscale_z_h.copy_( (2**self.num_bits_obs * self.scale_z_h).round() )
        self.scale_z_h = self.qscale_z_h / (2 ** self.num_bits_obs)

        self.scale_new_h_zn = self.output_observer_z_n.scale / self.observer_hidden.scale
        self.scale_new_h_zh = self.output_observer_z_h.scale / self.observer_hidden.scale

        self.qscale_new_h_zn.copy_( (2**self.num_bits_obs * self.scale_new_h_zn).round() )
        self.scale_new_h_zn = self.qscale_new_h_zn / (2 ** self.num_bits_obs)
        self.qscale_new_h_zh.copy_( (2**self.num_bits_obs * self.scale_new_h_zh).round() )
        self.scale_new_h_zh = self.qscale_new_h_zh / (2 ** self.num_bits_obs)

        # -------- Build LUTs ONCE (moved out of calibration forward) --------
        dev = self.linear_ih.weight.device

        # Sigmoid LUTs for (i_* + h_*) in the domain [0 .. 2^(bits+1)-1]
        in_sig = dequantize_tensor(
            self.sigmoid_domain.to(dev),
            self.output_linear_observer.scale,
            self.output_linear_observer.zero_point * 2
        )
        sig = torch.sigmoid(in_sig)
        self.lut_sigmoid_r.copy_(quantize_tensor(
            sig, self.output_observer_sigmoid_r.scale, self.output_observer_sigmoid_r.zero_point,
            num_bits=self.output_observer_sigmoid_r.num_bits
        ))
        self.lut_sigmoid_z.copy_(quantize_tensor(
            sig, self.output_observer_sigmoid_z.scale, self.output_observer_sigmoid_z.zero_point,
            num_bits=self.output_observer_sigmoid_z.num_bits
        ))

        # Tanh LUT for (r_hn + i_n_rescaled) in the domain [0 .. 2^(bits+1)-1]
        in_tanh = dequantize_tensor(
            self.tanh_domain.to(dev),
            self.output_observer_r_hn.scale,
            self.output_observer_r_hn.zero_point * 2
        )
        t = torch.tanh(in_tanh)
        self.lut_tanh_n.copy_(quantize_tensor(
            t, self.output_observer_tanh_n.scale, self.output_observer_tanh_n.zero_point,
            num_bits=self.output_observer_tanh_n.num_bits
        ))

        # Rescale LUT to map i_n (quantized with output_linear_observer) into r_hn index space
        lin_dom = torch.arange(2 ** self.output_linear_observer.num_bits, device=dev, dtype=torch.float32)
        in_vec = (lin_dom - self.output_linear_observer.zero_point) * (self.output_linear_observer.scale / self.output_observer_r_hn.scale)
        in_vec = torch.round(in_vec) + self.output_observer_r_hn.zero_point
        in_vec = in_vec.clamp_(0, 2 ** self.output_observer_r_hn.num_bits - 1)
        # Store into buffer (same num_bits used across observers in your setup)
        self.lut_rescale_i_n.copy_(in_vec)


    def forward_float(self,
                      x: torch.Tensor,
                      h: torch.Tensor) -> torch.Tensor:
        """
        Standard float GRU cell.
        """
        assert x.size(1) == self.input_size,  "Input size mismatch"
        assert h.size(1) == self.hidden_size, "Hidden size mismatch"
        assert x.size(0) == h.size(0),        "Batch size mismatch"

        gate_x = self.linear_ih(x)
        gate_h = self.linear_hh(h)

        i_r, i_z, i_n = gate_x.chunk(3, 1)
        h_r, h_z, h_n = gate_h.chunk(3, 1)

        r = torch.sigmoid(i_r + h_r)
        z = torch.sigmoid(i_z + h_z)
        n = torch.tanh(i_n + r * h_n)

        new_h = (1 - z) * n + z * h
        return new_h

    def forward_calib(self,
                      x: torch.Tensor,
                      h: torch.Tensor) -> torch.Tensor:
        """
        FAST calibration pass:
        - Pure-float compute.
        - Update observers ONLY (no FakeQuantize, no LUT building).
        - Observe static weights once per calibration session.
        """
        # Record inputs/hidden
        self.observer_input.update(x)
        self.observer_hidden.update(h)

        # Record weights ONCE (they don't change across steps)
        self.weight_ih_observer.update(self.linear_ih.weight)
        self.weight_hh_observer.update(self.linear_hh.weight)

        # Float linear projections
        gate_x = self.linear_ih(x)
        gate_h = self.linear_hh(h)

        # Update linear output observer
        self.output_linear_observer.update(gate_x)
        self.output_linear_observer.update(gate_h)

        # Split gates
        i_r, i_z, i_n = gate_x.chunk(3, 1)
        h_r, h_z, h_n = gate_h.chunk(3, 1)

        # Gates (float)
        r = torch.sigmoid(i_r + h_r)
        z = torch.sigmoid(i_z + h_z)

        # Ensure [0,1] coverage so later LUTs are safe even if data is narrow
        ones = torch.tensor([0.0, 1.0], device=x.device)
        self.output_observer_sigmoid_r.update(ones)
        self.output_observer_sigmoid_z.update(ones)

        # Also update with actual values
        self.output_observer_sigmoid_r.update(r)
        self.output_observer_sigmoid_z.update(z)

        # New gate path
        r_hn = r * h_n
        self.output_observer_r_hn.update(r_hn)
        # We also observe i_n so the sum domain (r_hn + i_n_rescaled) can be covered
        self.output_observer_r_hn.update(i_n)

        n = torch.tanh(i_n + r_hn)
        self.output_observer_tanh_n.update(n)

        # Output mixes for later scaling observers
        z_diff = 1.0 - z
        z_n = z_diff * n
        z_h = z * h
        self.output_observer_z_n.update(z_n)
        self.output_observer_z_h.update(z_h)

        new_h = z_n + z_h
        self.observer_hidden.update(new_h)
        return new_h

    def forward_quant(self,
                      x: torch.Tensor,
                      h: torch.Tensor) -> torch.Tensor:
        """
        Quantized forward pass (uses LUTs/scales prepared in quantize()).
        x, h are expected to be in the same (integer-emulated) domain used by observers.
        """
        # Input projection
        gate_x = self.linear_ih(x - self.observer_input.zero_point)
        gate_x = (gate_x * self.scale_ih).round()
        gate_x = gate_x + self.output_linear_observer.zero_point
        gate_x = gate_x.clamp(0, 2 ** self.output_linear_observer.num_bits - 1)

        # Hidden projection
        gate_h = self.linear_hh(h - self.observer_hidden.zero_point)
        gate_h = (gate_h * self.scale_hh).round()
        gate_h = gate_h + self.output_linear_observer.zero_point
        gate_h = gate_h.clamp(0, 2 ** self.output_linear_observer.num_bits - 1)

        # Split gates
        i_r, i_z, i_n = gate_x.chunk(3, 1)
        h_r, h_z, h_n = gate_h.chunk(3, 1)

        # Sigmoid LUT lookups
        r = (i_r + h_r).to(torch.int64)
        r = self.lut_sigmoid_r[r]
        z = (i_z + h_z).to(torch.int64)
        z = self.lut_sigmoid_z[z]

        # r * h_n in r_hn domain
        r_hn = (r - self.output_observer_sigmoid_r.zero_point) * (h_n - self.output_linear_observer.zero_point)
        r_hn = (r_hn * self.scale_r_hn).round()
        r_hn = r_hn + self.output_observer_r_hn.zero_point
        r_hn = r_hn.clamp(0, 2 ** self.output_observer_r_hn.num_bits - 1)

        # Rescale i_n into r_hn domain (via LUT)
        i_n_rescaled = self.lut_rescale_i_n[i_n.to(torch.int64)]

        # Tanh LUT
        n_idx = (r_hn + i_n_rescaled).to(torch.int64)
        n = self.lut_tanh_n[n_idx]

        # (1 - z) * n  and  z * h   in their respective domains
        z_diff = self.quant_1 - z

        z_n = (z_diff - self.output_observer_sigmoid_z.zero_point) * (n - self.output_observer_tanh_n.zero_point)
        z_n = (z_n * self.scale_z_n).round()
        z_n = z_n + self.output_observer_z_n.zero_point
        z_n = z_n.clamp(0, 2 ** self.output_observer_z_n.num_bits - 1)

        z_h = (z - self.output_observer_sigmoid_z.zero_point) * (h - self.observer_hidden.zero_point)
        z_h = (z_h * self.scale_z_h).round()
        z_h = z_h + self.output_observer_z_h.zero_point
        z_h = z_h.clamp(0, 2 ** self.output_observer_z_h.num_bits - 1)

        # Combine back to hidden domain
        new_h = (z_n - self.output_observer_z_n.zero_point) * self.scale_new_h_zn + \
                (z_h - self.output_observer_z_h.zero_point) * self.scale_new_h_zh
        new_h = new_h.round() + self.observer_hidden.zero_point
        new_h = new_h.clamp(0, 2 ** self.observer_hidden.num_bits - 1)
        return new_h
    

    def get_parameters(self,
                       file_name: str = None):
        
        with open('weights/gru.txt', 'w') as f:
            '''Save scales and zero points to file.'''
            f.write(f"Input scale ({int(self.num_bits_obs)} bit):\n {int(self.qscale_in)}\n")
            f.write(f"Input zero point:\n {int(self.observer_input.zero_point)}\n")

            f.write(f"Hidden scale ({int(self.num_bits_obs)} bit):\n {int(self.qscale_h)}\n")
            f.write(f"Hidden zero point:\n {int(self.observer_hidden.zero_point)}\n")

            f.write(f"Weight input scale ({int(self.num_bits_obs)} bit):\n {int(self.qscale_w_ih)}\n")
            f.write(f"Weight input zero point:\n {int(self.weight_ih_observer.zero_point)}\n")

            f.write(f"Weight hidden scale ({int(self.num_bits_obs)} bit):\n {int(self.qscale_w_hh)}\n")
            f.write(f"Weight hidden zero point:\n {int(self.weight_hh_observer.zero_point)}\n")

            f.write(f"Output linear scale ({int(self.num_bits_obs)} bit):\n {int(self.qscale_out_linear)}\n")
            f.write(f"Output linear zero point:\n {int(self.output_linear_observer.zero_point)}\n")

            f.write(f"Output sigmoid r scale ({int(self.num_bits_obs)} bit):\n {int(self.qscale_out_sigmoid_r)}\n")
            f.write(f"Output sigmoid r zero point:\n {int(self.output_observer_sigmoid_r.zero_point)}\n")

            f.write(f"Output sigmoid z scale ({int(self.num_bits_obs)} bit):\n {int(self.qscale_out_sigmoid_z)}\n")
            f.write(f"Output sigmoid z zero point:\n {int(self.output_observer_sigmoid_z.zero_point)}\n")

            f.write(f"Output tanh n scale ({int(self.num_bits_obs)} bit):\n {int(self.qscale_out_tanh_n)}\n")
            f.write(f"Output tanh n zero point:\n {int(self.output_observer_tanh_n.zero_point)}\n")

            f.write(f"Output r_hn scale ({int(self.num_bits_obs)} bit):\n {int(self.qscale_out_r_hn)}\n")
            f.write(f"Output r_hn zero point:\n {int(self.output_observer_r_hn.zero_point)}\n")

            f.write(f"Output z_n scale ({int(self.num_bits_obs)} bit):\n {int(self.qscale_out_z_n)}\n")     
            f.write(f"Output z_n zero point:\n {int(self.output_observer_z_n.zero_point)}\n")

            f.write(f"Output z_h scale ({int(self.num_bits_obs)} bit):\n {int(self.qscale_out_z_h)}\n")
            f.write(f"Output z_h zero point:\n {int(self.output_observer_z_h.zero_point)}\n")

            f.write(f"Scale ih ({int(self.num_bits_obs)} bit):\n {int(self.qscale_ih)}\n")
            f.write(f"Scale hh ({int(self.num_bits_obs)} bit):\n {int(self.qscale_hh)}\n")
            f.write(f"Scale r_hn ({int(self.num_bits_obs)} bit):\n {int(self.qscale_r_hn)}\n")
            f.write(f"Scale z_n ({int(self.num_bits_obs)} bit):\n {int(self.qscale_z_n)}\n")
            f.write(f"Scale z_h ({int(self.num_bits_obs)} bit):\n {int(self.qscale_z_h)}\n")
            f.write(f"Scale new_h_zn ({int(self.num_bits_obs)} bit):\n {int(self.qscale_new_h_zn)}\n")
            f.write(f"Scale new_h_zh ({int(self.num_bits_obs)} bit):\n {int(self.qscale_new_h_zh)}\n")

            '''Save weights and bias to file.'''
            weight_ih = torch.flip(self.linear_ih.weight, [1])
            weight_ih = weight_ih.detach().cpu().numpy().astype(np.int32).tolist()
            
            f.write(f"Weight_ih ({int(self.num_bits)} bit):\n")
            for idx, w in enumerate(weight_ih):
                f.write(f"weights_linear_ih[{idx}] = {str(w).replace('[', '{').replace(']', '}') + ';'}\n")

            bias_ih = torch.flip(self.linear_ih.bias, [0])
            bias_ih = bias_ih.detach().cpu().numpy().astype(np.int32).tolist()
            f.write(f"\nBias_ih ({int(self.num_bits)} bit):\n {str(bias_ih).replace('[', '{').replace(']', '}') + ';'}\n")

            '''Save weights and bias to file.'''
            weight_hh = torch.flip(self.linear_hh.weight, [1])
            weight_hh = weight_hh.detach().cpu().numpy().astype(np.int32).tolist()
            
            f.write(f"Weight_hh ({int(self.num_bits)} bit):\n")
            for idx, w in enumerate(weight_hh):
                f.write(f"weights_linear_hh[{idx}] = {str(w).replace('[', '{').replace(']', '}') + ';'}\n")

            bias_hh = torch.flip(self.linear_hh.bias, [0])
            bias_hh = bias_hh.detach().cpu().numpy().astype(np.int32).tolist()
            f.write(f"\nBias_hh ({int(self.num_bits)} bit):\n {str(bias_hh).replace('[', '{').replace(']', '}') + ';'}\n")

            # weight_ih = torch.flip(self.linear_ih.weight, [0])
            # weight_ih = weight_ih.detach().cpu().numpy().astype(np.int32).tolist()

            # weight_hh = torch.flip(self.linear_hh.weight, [0])
            # weight_hh = weight_hh.detach().cpu().numpy().astype(np.int32).tolist()

            with open('weights/linear_ih.mem', 'w') as f:
                for idx, we in enumerate(weight_ih):
                    bin_vec = [np.binary_repr(w+self.weight_ih_observer.zero_point.to(torch.int32).item(), width=9)[1:] for w in we]
                    Z1a2 = sum([w + self.weight_ih_observer.zero_point.to(torch.int32).item() for w in we]) * \
                        self.observer_input.zero_point.to(torch.int32).item()
                    NZ1Z2 = self.hidden_size * \
                                self.observer_input.zero_point.to(torch.int32).item() * \
                                    self.weight_ih_observer.zero_point.to(torch.int32).item()
                    # Concat to bin_vec binary repr of bias
                    bin_vec = bin_vec + [np.binary_repr(bias_ih[len(bias_ih)-idx-1] - Z1a2 + NZ1Z2, width=32)]
                    dlugi_ciag_bitow = ''.join(bin_vec)
                    wartosc_hex = hex(int(dlugi_ciag_bitow, 2))
                    f.write(f"{str(wartosc_hex)[2:]}\n")

            with open('weights/linear_hh.mem', 'w') as f:
                for idx, we in enumerate(weight_hh):
                    bin_vec = [np.binary_repr(w+self.weight_hh_observer.zero_point.to(torch.int32).item(), width=9)[1:] for w in we]
                    Z1a2 = sum([w + self.weight_hh_observer.zero_point.to(torch.int32).item() for w in we]) * \
                        self.observer_hidden.zero_point.to(torch.int32).item()
                    NZ1Z2 = self.hidden_size * \
                                self.observer_hidden.zero_point.to(torch.int32).item() * \
                                    self.weight_hh_observer.zero_point.to(torch.int32).item()
                    # Concat to bin_vec binary repr of bias
                    bin_vec = bin_vec + [np.binary_repr(bias_hh[len(bias_hh)-idx-1] - Z1a2 + NZ1Z2, width=32)]
                    dlugi_ciag_bitow = ''.join(bin_vec)
                    wartosc_hex = hex(int(dlugi_ciag_bitow, 2))
                    f.write(f"{str(wartosc_hex)[2:]}\n")

            with open('weights/lut_sigmoid_r.mem', 'w') as f:
                f.write(f"memory_initialization_radix={10};\n")
                f.write(f"memory_initialization_vector=")
                for idx, val in enumerate(self.lut_sigmoid_r):
                    f.write(f"{int(val.item())}")
                    if idx < len(self.lut_sigmoid_r) - 1:
                        f.write(" ")
                    else:
                        f.write(";\n")

            with open('weights/lut_sigmoid_z.mem', 'w') as f:
                f.write(f"memory_initialization_radix={10};\n")
                f.write(f"memory_initialization_vector=")
                for idx, val in enumerate(self.lut_sigmoid_z):
                    f.write(f"{int(val.item())}")
                    if idx < len(self.lut_sigmoid_z) - 1:
                        f.write(" ")
                    else:
                        f.write(";\n")

            with open('weights/lut_tanh_n.mem', 'w') as f:
                f.write(f"memory_initialization_radix={10};\n")
                f.write(f"memory_initialization_vector=")
                for idx, val in enumerate(self.lut_tanh_n):
                    f.write(f"{int(val.item())}")
                    if idx < len(self.lut_tanh_n) - 1:
                        f.write(" ")
                    else:
                        f.write(";\n")
            
            with open('weights/lut_rescale_i_n.mem', 'w') as f:
                f.write(f"memory_initialization_radix={10};\n")
                f.write(f"memory_initialization_vector=")
                for idx, val in enumerate(self.lut_rescale_i_n):
                    f.write(f"{int(val.item())}")
                    if idx < len(self.lut_rescale_i_n) - 1:
                        f.write(" ")
                    else:
                        f.write(";\n")


