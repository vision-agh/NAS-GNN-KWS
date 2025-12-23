import torch
import torch.nn as nn
from torch import Tensor
from typing import Optional

from models.layers.quantisation.observer import Observer, FakeQuantize


def torch_global_add_pool(x: Tensor, batch: Tensor) -> Tensor:
    # x: [N, F], batch: [N] with values in {0,..,B-1}
    if x.numel() == 0:
        B = int(batch.max().item()) + 1 if batch.numel() else 1
        return x.new_zeros((B, x.size(1)))
    B = int(batch.max().item()) + 1
    out = x.new_zeros((B, x.size(1)))
    return out.index_add(0, batch, x)


def torch_global_mean_pool(x: Tensor, batch: Tensor) -> Tensor:
    if x.numel() == 0:
        B = int(batch.max().item()) + 1 if batch.numel() else 1
        return x.new_zeros((B, x.size(1)))
    B = int(batch.max().item()) + 1
    out_sum = x.new_zeros((B, x.size(1))).index_add(0, batch, x)
    counts = torch.bincount(batch, minlength=B).to(dtype=x.dtype).unsqueeze(1)
    return out_sum / counts.clamp(min=1)


def torch_global_max_pool(x: Tensor, batch: Tensor) -> Tensor:
    # Prefer scatter_reduce (fast, vectorized) if available.
    if x.numel() == 0:
        B = int(batch.max().item()) + 1 if batch.numel() else 1
        return x.new_full((B, x.size(1)), float("-inf"))

    B = int(batch.max().item()) + 1
    F = x.size(1)

    out = x.new_full((B, F), float("-inf"))
    idx = batch.view(-1, 1).expand(-1, F)

    if hasattr(out, "scatter_reduce"):
        # PyTorch 1.13+/2.x
        out = out.scatter_reduce(0, idx, x, reduce="amax", include_self=True)
        return out

    # Fallback: loop over B (still OK if B is small)
    for b in range(B):
        mask = batch == b
        if mask.any():
            out[b] = x[mask].max(dim=0)[0]
    return out


class MyGlobalPooling(nn.Module):
    def __init__(self, aggregator: str = "mean", num_bits: int = 8):
        super().__init__()
        if aggregator not in {"mean", "add", "max"}:
            raise ValueError(f"Unknown aggregator '{aggregator}', choose from 'mean', 'add', 'max'.")
        self.aggregator = aggregator
        self.num_bits = int(num_bits)

        self.register_buffer("calib_mode", torch.tensor(False))
        self.register_buffer("quantize_mode", torch.tensor(False))

    def forward(
        self,
        x: Tensor,
        batch: Optional[Tensor] = None,
        observer: Optional[Observer] = None,
    ) -> Tensor:
        # If batch is None, treat entire x as a single graph
        if batch is None:
            batch = x.new_zeros((x.size(0),), dtype=torch.long)

        # Pool
        if self.aggregator == "add":
            out = torch_global_add_pool(x, batch)
        elif self.aggregator == "mean":
            out = torch_global_mean_pool(x, batch)
        else:
            out = torch_global_max_pool(x, batch)

        # Quantization / calibration behavior
        if self.calib_mode.item() and not self.quantize_mode.item():
            if observer is None:
                raise ValueError("observer must be provided in calib_mode.")
            out = FakeQuantize.apply(out, observer)
        elif self.quantize_mode.item():
            # Assumes out is already in an integer-emulated domain.
            out = out.round().clamp(0, 2 ** self.num_bits - 1)

        return out

    def calibrate(self):
        self.calib_mode.fill_(True)

    def quantize(self):
        self.quantize_mode.fill_(True)

    def __repr__(self) -> str:
        return f"{self.__class__.__name__}(aggregator={self.aggregator}, num_bits={self.num_bits})"
