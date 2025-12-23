import math
from pathlib import Path
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

from models.layers.quantisation.observer import Observer, FakeQuantize, quantize_tensor, dequantize_tensor


class MyGRUCell(nn.Module):
    """
    GRU cell with observers for post-training quantization.

    Modes:
      - float:  forward_float
      - calib:  forward_calib (collect observer stats only)
      - quant:  forward_quant (integer-emulated pipeline with LUTs/scales from quantize())
    """

    def __init__(self, input_size: int, hidden_size: int, num_bits: int = 8):
        super().__init__()
        self.input_size = input_size
        self.hidden_size = hidden_size

        # Linear projections
        self.linear_ih = nn.Linear(input_size, 3 * hidden_size)
        self.linear_hh = nn.Linear(hidden_size, 3 * hidden_size)
        self.reset_parameters()

        # Quantization config
        self.num_bits = num_bits
        self.num_bits_obs = 32
        self._Q = float(2 ** self.num_bits_obs)

        # ---- Observers ----
        self.observer_input = Observer(num_bits=num_bits)
        self.observer_hidden = Observer(num_bits=num_bits)

        self.weight_ih_observer = Observer(num_bits=num_bits)
        self.weight_hh_observer = Observer(num_bits=num_bits)

        self.output_linear_observer = Observer(num_bits=num_bits)

        self.output_observer_sigmoid_r = Observer(num_bits=num_bits)
        self.output_observer_sigmoid_z = Observer(num_bits=num_bits)
        self.output_observer_tanh_n = Observer(num_bits=num_bits)

        self.output_observer_r_hn = Observer(num_bits=num_bits)
        self.output_observer_z_n  = Observer(num_bits=num_bits)
        self.output_observer_z_h  = Observer(num_bits=num_bits)

        # ---- LUT buffers ----
        lut_size_lin = 2 ** (num_bits + 1)
        lut_size_rescale = 2 ** num_bits

        self.register_buffer("lut_sigmoid_r",   torch.zeros(lut_size_lin, dtype=torch.float32))
        self.register_buffer("lut_sigmoid_z",   torch.zeros(lut_size_lin, dtype=torch.float32))
        self.register_buffer("lut_tanh_n",      torch.zeros(lut_size_lin, dtype=torch.float32))
        self.register_buffer("lut_rescale_i_n", torch.zeros(lut_size_rescale, dtype=torch.float32))

        # Precomputed domains for LUT generation
        self.register_buffer("sigmoid_domain", torch.arange(lut_size_lin, dtype=torch.float32))
        self.register_buffer("tanh_domain",    torch.arange(lut_size_lin, dtype=torch.float32))

        # ---- Runtime scales (filled in quantize()) ----
        self._register_scalar("scale_ih",       1.0)
        self._register_scalar("scale_hh",       1.0)
        self._register_scalar("scale_r_hn",     1.0)
        self._register_scalar("scale_z_n",      1.0)
        self._register_scalar("scale_z_h",      1.0)
        self._register_scalar("scale_new_h_zn", 1.0)
        self._register_scalar("scale_new_h_zh", 1.0)

        self._register_scalar("quant_1", 1.0)

        # Modes
        self.register_buffer("calib_mode",    torch.tensor(False))
        self.register_buffer("quantize_mode", torch.tensor(False))

        # ---- Fixed-point (FPGA export) qscales ----
        # Observers
        self._register_scalar("qscale_in",            1.0)
        self._register_scalar("qscale_h",             1.0)
        self._register_scalar("qscale_w_ih",          1.0)
        self._register_scalar("qscale_w_hh",          1.0)
        self._register_scalar("qscale_out_linear",    1.0)
        self._register_scalar("qscale_out_sigmoid_r", 1.0)
        self._register_scalar("qscale_out_sigmoid_z", 1.0)
        self._register_scalar("qscale_out_tanh_n",    1.0)
        self._register_scalar("qscale_out_r_hn",      1.0)
        self._register_scalar("qscale_out_z_n",       1.0)
        self._register_scalar("qscale_out_z_h",       1.0)

        # Derived scales
        self._register_scalar("qscale_ih",        1.0)
        self._register_scalar("qscale_hh",        1.0)
        self._register_scalar("qscale_r_hn",      1.0)
        self._register_scalar("qscale_z_n",       1.0)
        self._register_scalar("qscale_z_h",       1.0)
        self._register_scalar("qscale_new_h_zn",  1.0)
        self._register_scalar("qscale_new_h_zh",  1.0)

    # ---------------------------------------------------------------------
    # Utilities
    # ---------------------------------------------------------------------
    def _register_scalar(self, name: str, value: float):
        self.register_buffer(name, torch.tensor(float(value), dtype=torch.float32))

    def _quantize_scale_to_q(self, scale_buf_name: str, observer: Observer):
        """
        qscale = round(2^num_bits_obs * observer.scale)
        observer.scale = qscale / 2^num_bits_obs
        """
        qscale = getattr(self, scale_buf_name)
        qscale.copy_((self._Q * observer.scale).round())
        observer.scale = qscale / self._Q

    def reset_parameters(self) -> None:
        std = 1.0 / math.sqrt(self.hidden_size)
        for p in self.parameters():
            p.data.uniform_(-std, std)

    # ---------------------------------------------------------------------
    # Mode dispatch
    # ---------------------------------------------------------------------
    def forward(self, x: torch.Tensor, h: torch.Tensor) -> torch.Tensor:
        if self.quantize_mode.item():
            return self.forward_quant(x, h)
        if self.calib_mode.item():
            return self.forward_calib(x, h)
        return self.forward_float(x, h)

    def calibrate(self):
        self.calib_mode.fill_(True)


    # ---------------------------------------------------------------------
    # Forward paths
    # ---------------------------------------------------------------------
    def forward_float(self, x: torch.Tensor, h: torch.Tensor) -> torch.Tensor:
        assert x.size(1) == self.input_size, "Input size mismatch"
        assert h.size(1) == self.hidden_size, "Hidden size mismatch"
        assert x.size(0) == h.size(0), "Batch size mismatch"

        gate_x = self.linear_ih(x)
        gate_h = self.linear_hh(h)

        i_r, i_z, i_n = gate_x.chunk(3, 1)
        h_r, h_z, h_n = gate_h.chunk(3, 1)

        r = torch.sigmoid(i_r + h_r)
        z = torch.sigmoid(i_z + h_z)
        n = torch.tanh(i_n + r * h_n)

        return (1 - z) * n + z * h

    def forward_calib(self, x: torch.Tensor, h: torch.Tensor) -> torch.Tensor:
        # Inputs/hidden
        if self.training:
            self.observer_input.update(x)
            self.observer_hidden.update(h)

        x = FakeQuantize.apply(x, self.observer_input)
        h = FakeQuantize.apply(h, self.observer_hidden)

        # Weights (static)
        if self.training:
            self.weight_ih_observer.update(self.linear_ih.weight)
            self.weight_hh_observer.update(self.linear_hh.weight)

        gate_x = F.linear(x, FakeQuantize.apply(self.linear_ih.weight, self.weight_ih_observer), self.linear_ih.bias)
        gate_h = F.linear(h, FakeQuantize.apply(self.linear_hh.weight, self.weight_hh_observer), self.linear_hh.bias)

        # gate_x = self.linear_ih(x)
        # gate_h = self.linear_hh(h)

        if self.training:
            self.output_linear_observer.update(gate_x)
            self.output_linear_observer.update(gate_h)

        gate_x = FakeQuantize.apply(gate_x, self.output_linear_observer)
        gate_h = FakeQuantize.apply(gate_h, self.output_linear_observer)

        i_r, i_z, i_n = gate_x.chunk(3, 1)
        h_r, h_z, h_n = gate_h.chunk(3, 1)

        r = torch.sigmoid(i_r + h_r)
        z = torch.sigmoid(i_z + h_z)

        # Ensure coverage of [0,1] for sigmoid observers
        if self.training:
            ones = x.new_tensor([0.0, 1.0])
            self.output_observer_sigmoid_r.update(ones)
            self.output_observer_sigmoid_z.update(ones)
            self.output_observer_sigmoid_r.update(r)
            self.output_observer_sigmoid_z.update(z)

        r = FakeQuantize.apply(r, self.output_observer_sigmoid_r)
        z = FakeQuantize.apply(z, self.output_observer_sigmoid_z)

        r_hn = r * h_n

        if self.training:
            self.output_observer_r_hn.update(r_hn)
            self.output_observer_r_hn.update(i_n)

        n = torch.tanh(i_n + r_hn)

        if self.training:
            self.output_observer_tanh_n.update(n)

        n = FakeQuantize.apply(n, self.output_observer_tanh_n)

        z_diff = 1.0 - z
        z_n = z_diff * n
        z_h = z * h

        if self.training:
            self.output_observer_z_n.update(z_n)
            self.output_observer_z_h.update(z_h)

        z_n = FakeQuantize.apply(z_n, self.output_observer_z_n)
        z_h = FakeQuantize.apply(z_h, self.output_observer_z_h)

        new_h = z_n + z_h
        
        if self.training:
            self.observer_hidden.update(new_h)

        new_h = FakeQuantize.apply(new_h, self.observer_hidden)

        return new_h

    def forward_quant(self, x: torch.Tensor, h: torch.Tensor) -> torch.Tensor:
        # Input projection (integer-emulated)
        gate_x = self.linear_ih(x - self.observer_input.zero_point)
        gate_x = (gate_x * self.scale_ih).round()
        gate_x = gate_x + self.output_linear_observer.zero_point
        gate_x = gate_x.clamp(0, 2 ** self.output_linear_observer.num_bits - 1)

        # Hidden projection
        gate_h = self.linear_hh(h - self.observer_hidden.zero_point)
        gate_h = (gate_h * self.scale_hh).round()
        gate_h = gate_h + self.output_linear_observer.zero_point
        gate_h = gate_h.clamp(0, 2 ** self.output_linear_observer.num_bits - 1)

        i_r, i_z, i_n = gate_x.chunk(3, 1)
        h_r, h_z, h_n = gate_h.chunk(3, 1)

        # Sigmoid LUTs
        r = self.lut_sigmoid_r[(i_r + h_r).to(torch.int64)]
        z = self.lut_sigmoid_z[(i_z + h_z).to(torch.int64)]

        # r * h_n -> r_hn domain
        r_hn = (r - self.output_observer_sigmoid_r.zero_point) * (h_n - self.output_linear_observer.zero_point)
        r_hn = (r_hn * self.scale_r_hn).round()
        r_hn = r_hn + self.output_observer_r_hn.zero_point
        r_hn = r_hn.clamp(0, 2 ** self.output_observer_r_hn.num_bits - 1)

        # i_n rescaled into r_hn domain
        i_n_rescaled = self.lut_rescale_i_n[i_n.to(torch.int64)]

        # Tanh LUT
        n = self.lut_tanh_n[(r_hn + i_n_rescaled).to(torch.int64)]

        # (1 - z) * n and z * h
        z_diff = self.quant_1 - z

        z_n = (z_diff - self.output_observer_sigmoid_z.zero_point) * (n - self.output_observer_tanh_n.zero_point)
        z_n = (z_n * self.scale_z_n).round()
        z_n = z_n + self.output_observer_z_n.zero_point
        z_n = z_n.clamp(0, 2 ** self.output_observer_z_n.num_bits - 1)

        z_h = (z - self.output_observer_sigmoid_z.zero_point) * (h - self.observer_hidden.zero_point)
        z_h = (z_h * self.scale_z_h).round()
        z_h = z_h + self.output_observer_z_h.zero_point
        z_h = z_h.clamp(0, 2 ** self.output_observer_z_h.num_bits - 1)

        # Combine into hidden domain
        new_h = (
            (z_n - self.output_observer_z_n.zero_point) * self.scale_new_h_zn
            + (z_h - self.output_observer_z_h.zero_point) * self.scale_new_h_zh
        )
        new_h = new_h.round() + self.observer_hidden.zero_point
        new_h = new_h.clamp(0, 2 ** self.observer_hidden.num_bits - 1)
        return new_h
    
    # ---------------------------------------------------------------------
    # Quantization preparation
    # ---------------------------------------------------------------------
    def quantize(self, observer_input: Observer = None, observer_output: Observer = None):
        self.quantize_mode.fill_(True)

        if observer_input is not None:
            self.observer_input = observer_input
        if observer_output is not None:
            self.observer_output = observer_output  # optional, not used directly

        # 1) Snap observer scales to fixed-point for export
        self._quantize_scale_to_q("qscale_in",            self.observer_input)
        self._quantize_scale_to_q("qscale_h",             self.observer_hidden)
        self._quantize_scale_to_q("qscale_w_ih",          self.weight_ih_observer)
        self._quantize_scale_to_q("qscale_w_hh",          self.weight_hh_observer)
        self._quantize_scale_to_q("qscale_out_linear",    self.output_linear_observer)
        self._quantize_scale_to_q("qscale_out_sigmoid_r", self.output_observer_sigmoid_r)
        self._quantize_scale_to_q("qscale_out_sigmoid_z", self.output_observer_sigmoid_z)
        self._quantize_scale_to_q("qscale_out_tanh_n",    self.output_observer_tanh_n)
        self._quantize_scale_to_q("qscale_out_r_hn",      self.output_observer_r_hn)
        self._quantize_scale_to_q("qscale_out_z_n",       self.output_observer_z_n)
        # z_h scale is exported too; make sure observer exists and has scale
        self._quantize_scale_to_q("qscale_out_z_h",       self.output_observer_z_h)

        # 2) Quantize weights/biases for the two linears
        self._quantize_linears()

        # 3) Compute derived scales for elementwise ops
        self._compute_derived_scales()

        # 4) Build LUTs once
        self._build_luts()

    def _quantize_linears(self):
        # INPUT linear
        q_w_ih = self.weight_ih_observer.quantize_tensor(self.linear_ih.weight) - self.weight_ih_observer.zero_point
        q_b_ih = quantize_tensor(
            self.linear_ih.bias,
            scale=self.weight_ih_observer.scale * self.observer_input.scale,
            zero_point=0,
            num_bits=32,
            signed=True,
        )
        self.linear_ih.weight = nn.Parameter(q_w_ih)
        self.linear_ih.bias = nn.Parameter(q_b_ih)

        self.scale_ih = (self.weight_ih_observer.scale * self.observer_input.scale) / self.output_linear_observer.scale
        self.qscale_ih.copy_((self._Q * self.scale_ih).round())
        self.scale_ih = self.qscale_ih / self._Q

        # HIDDEN linear
        q_w_hh = self.weight_hh_observer.quantize_tensor(self.linear_hh.weight) - self.weight_hh_observer.zero_point
        q_b_hh = quantize_tensor(
            self.linear_hh.bias,
            scale=self.weight_hh_observer.scale * self.observer_hidden.scale,
            zero_point=0,
            num_bits=32,
            signed=True,
        )
        self.linear_hh.weight = nn.Parameter(q_w_hh)
        self.linear_hh.bias = nn.Parameter(q_b_hh)

        self.scale_hh = (self.weight_hh_observer.scale * self.observer_hidden.scale) / self.output_linear_observer.scale
        self.qscale_hh.copy_((self._Q * self.scale_hh).round())
        self.scale_hh = self.qscale_hh / self._Q

    def _compute_derived_scales(self):
        # r*h_n scale
        self.scale_r_hn = (self.output_observer_sigmoid_r.scale * self.output_linear_observer.scale) / self.output_observer_r_hn.scale
        self.qscale_r_hn.copy_((self._Q * self.scale_r_hn).round())
        self.scale_r_hn = self.qscale_r_hn / self._Q

        # quantized constant 1.0 in sigmoid_z domain
        self.quant_1 = quantize_tensor(
            torch.tensor(1.0, device=self.observer_hidden.scale.device),
            scale=self.output_observer_sigmoid_z.scale,
            zero_point=self.output_observer_sigmoid_z.zero_point,
            num_bits=self.output_observer_sigmoid_z.num_bits,
        )

        # z_n and z_h scales
        self.scale_z_n = (self.output_observer_sigmoid_z.scale * self.output_observer_tanh_n.scale) / self.output_observer_z_n.scale
        self.scale_z_h = (self.output_observer_sigmoid_z.scale * self.observer_hidden.scale) / self.output_observer_z_h.scale

        self.qscale_z_n.copy_((self._Q * self.scale_z_n).round())
        self.scale_z_n = self.qscale_z_n / self._Q

        self.qscale_z_h.copy_((self._Q * self.scale_z_h).round())
        self.scale_z_h = self.qscale_z_h / self._Q

        # Back to hidden domain
        self.scale_new_h_zn = self.output_observer_z_n.scale / self.observer_hidden.scale
        self.scale_new_h_zh = self.output_observer_z_h.scale / self.observer_hidden.scale

        self.qscale_new_h_zn.copy_((self._Q * self.scale_new_h_zn).round())
        self.scale_new_h_zn = self.qscale_new_h_zn / self._Q

        self.qscale_new_h_zh.copy_((self._Q * self.scale_new_h_zh).round())
        self.scale_new_h_zh = self.qscale_new_h_zh / self._Q

    def _build_luts(self):
        dev = self.linear_ih.weight.device

        # Sigmoid LUTs for (i_* + h_*) domain
        in_sig = dequantize_tensor(
            self.sigmoid_domain.to(dev),
            self.output_linear_observer.scale,
            self.output_linear_observer.zero_point * 2,
        )
        sig = torch.sigmoid(in_sig)

        self.lut_sigmoid_r.copy_(quantize_tensor(
            sig,
            self.output_observer_sigmoid_r.scale,
            self.output_observer_sigmoid_r.zero_point,
            num_bits=self.output_observer_sigmoid_r.num_bits,
        ))
        self.lut_sigmoid_z.copy_(quantize_tensor(
            sig,
            self.output_observer_sigmoid_z.scale,
            self.output_observer_sigmoid_z.zero_point,
            num_bits=self.output_observer_sigmoid_z.num_bits,
        ))

        # Tanh LUT for (r_hn + i_n_rescaled) domain
        in_tanh = dequantize_tensor(
            self.tanh_domain.to(dev),
            self.output_observer_r_hn.scale,
            self.output_observer_r_hn.zero_point * 2,
        )
        t = torch.tanh(in_tanh)
        self.lut_tanh_n.copy_(quantize_tensor(
            t,
            self.output_observer_tanh_n.scale,
            self.output_observer_tanh_n.zero_point,
            num_bits=self.output_observer_tanh_n.num_bits,
        ))

        # Rescale LUT: i_n (linear domain) -> r_hn index domain
        lin_dom = torch.arange(2 ** self.output_linear_observer.num_bits, device=dev, dtype=torch.float32)
        in_vec = (lin_dom - self.output_linear_observer.zero_point) * (
            self.output_linear_observer.scale / self.output_observer_r_hn.scale
        )
        in_vec = torch.round(in_vec) + self.output_observer_r_hn.zero_point
        in_vec = in_vec.clamp_(0, 2 ** self.output_observer_r_hn.num_bits - 1)
        self.lut_rescale_i_n.copy_(in_vec)

    # ---------------------------------------------------------------------
    # Export utilities
    # ---------------------------------------------------------------------
    def get_parameters(self, file_name: str = None):
        """
        Writes FPGA/RTL-friendly dumps. Kept compatible with your current outputs.
        """
        weights_dir = Path("weights")
        weights_dir.mkdir(parents=True, exist_ok=True)

        # ---- Text summary ----
        with open(weights_dir / "gru.txt", "w") as f:
            self._write_scale_dump(f)

            weight_ih, bias_ih = self._export_linear_params(self.linear_ih, flip_w_dim=1, flip_b_dim=0)
            weight_hh, bias_hh = self._export_linear_params(self.linear_hh, flip_w_dim=1, flip_b_dim=0)

            self._write_weight_dump(f, "Weight_ih", weight_ih)
            self._write_bias_dump(f, "Bias_ih", bias_ih)

            self._write_weight_dump(f, "Weight_hh", weight_hh)
            self._write_bias_dump(f, "Bias_hh", bias_hh)

        # ---- .mem files ----
        self._write_linear_mem(weights_dir / "linear_ih.mem", weight_ih, bias_ih,
                               in_zp=int(self.observer_input.zero_point),
                               w_zp=int(self.weight_ih_observer.zero_point))

        self._write_linear_mem(weights_dir / "linear_hh.mem", weight_hh, bias_hh,
                               in_zp=int(self.observer_hidden.zero_point),
                               w_zp=int(self.weight_hh_observer.zero_point))

        self._write_lut_mem(weights_dir / "lut_sigmoid_r.mem", self.lut_sigmoid_r)
        self._write_lut_mem(weights_dir / "lut_sigmoid_z.mem", self.lut_sigmoid_z)
        self._write_lut_mem(weights_dir / "lut_tanh_n.mem", self.lut_tanh_n)
        self._write_lut_mem(weights_dir / "lut_rescale_i_n.mem", self.lut_rescale_i_n)

    def _write_scale_dump(self, f):
        # Observers
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

        # Derived
        f.write(f"Scale ih ({int(self.num_bits_obs)} bit):\n {int(self.qscale_ih)}\n")
        f.write(f"Scale hh ({int(self.num_bits_obs)} bit):\n {int(self.qscale_hh)}\n")
        f.write(f"Scale r_hn ({int(self.num_bits_obs)} bit):\n {int(self.qscale_r_hn)}\n")
        f.write(f"Scale z_n ({int(self.num_bits_obs)} bit):\n {int(self.qscale_z_n)}\n")
        f.write(f"Scale z_h ({int(self.num_bits_obs)} bit):\n {int(self.qscale_z_h)}\n")
        f.write(f"Scale new_h_zn ({int(self.num_bits_obs)} bit):\n {int(self.qscale_new_h_zn)}\n")
        f.write(f"Scale new_h_zh ({int(self.num_bits_obs)} bit):\n {int(self.qscale_new_h_zh)}\n")

    def _export_linear_params(self, lin: nn.Linear, flip_w_dim: int, flip_b_dim: int):
        w = torch.flip(lin.weight, [flip_w_dim]).detach().cpu().numpy().astype(np.int32).tolist()
        b = torch.flip(lin.bias, [flip_b_dim]).detach().cpu().numpy().astype(np.int32).tolist()
        return w, b

    def _write_weight_dump(self, f, name: str, w_list):
        f.write(f"{name} ({int(self.num_bits)} bit):\n")
        for idx, row in enumerate(w_list):
            f.write(f"{name.lower()}[{idx}] = {str(row).replace('[', '{').replace(']', '}')};\n")

    def _write_bias_dump(self, f, name: str, b_list):
        f.write(f"\n{name} ({int(self.num_bits)} bit):\n {str(b_list).replace('[', '{').replace(']', '}')};\n")

    def _write_linear_mem(self, path: Path, weight_rows, bias_vec, in_zp: int, w_zp: int):
        """
        Preserves your packing:
          - 8-bit stored weight bits (you were using width=9 then slicing [1:])
          - 32-bit bias appended at end
        """
        with open(path, "w") as f:
            for idx, row in enumerate(weight_rows):
                # weights: store as 8 bits (drop MSB of 9-bit repr)
                bin_vec = [np.binary_repr(w + w_zp, width=9)[1:] for w in row]

                Z1a2 = sum([w + w_zp for w in row]) * in_zp
                NZ1Z2 = self.hidden_size * in_zp * w_zp

                # bias index reversed as in your original code
                bias_i = bias_vec[len(bias_vec) - idx - 1] - Z1a2 + NZ1Z2
                bin_vec.append(np.binary_repr(bias_i, width=32))

                bits = "".join(bin_vec)
                f.write(f"{hex(int(bits, 2))[2:]}\n")

    def _write_lut_mem(self, path: Path, lut: torch.Tensor):
        with open(path, "w") as f:
            f.write("memory_initialization_radix=10;\n")
            f.write("memory_initialization_vector=")
            for i, v in enumerate(lut):
                f.write(str(int(v.item())))
                f.write(" " if i < len(lut) - 1 else ";\n")
