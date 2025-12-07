import torch
import torch.nn as nn
from torch import Tensor
from typing import Optional

from models.layers.quantisation.observer import Observer, FakeQuantize, quantize_tensor

# Pooling implementations in pure PyTorch
def torch_global_add_pool(x: Tensor, batch: Tensor) -> Tensor:
    # x: [N, F], batch: [N] with values in {0,..,B-1}
    B = int(batch.max().item()) + 1
    out = x.new_zeros((B, x.size(1)))
    out = out.index_add(0, batch, x)
    return out


def torch_global_mean_pool(x: Tensor, batch: Tensor) -> Tensor:
    # sum then divide by counts
    B = int(batch.max().item()) + 1
    out_sum = x.new_zeros((B, x.size(1)))
    out_sum = out_sum.index_add(0, batch, x)
    counts = torch.bincount(batch, minlength=B).unsqueeze(1).to(x.dtype)
    out = out_sum / counts.clamp(min=1)
    return out


def torch_global_max_pool(x: Tensor, batch: Tensor) -> Tensor:
    B = int(batch.max().item()) + 1
    F = x.size(1)
    out = x.new_full((B, F), -float('inf'))
    # loop over batch IDs (efficient if B small)
    for b in torch.unique(batch):
        mask = batch == b
        out[b] = x[mask].max(dim=0)[0]
    return out


class MyGlobalPooling(nn.Module):
    def __init__(
        self,
        aggregator: str = 'mean',
        num_bits: int = 8
    ):
        super().__init__()
        if aggregator not in {'mean', 'add', 'max'}:
            raise ValueError(f"Unknown aggregator '{aggregator}', choose from 'mean','add','max'.")
        self.aggregator = aggregator
        self.num_bits = num_bits

        self.register_buffer('calib_mode', torch.tensor(False, requires_grad=False))
        self.register_buffer('quantize_mode', torch.tensor(False, requires_grad=False))

    def forward(
        self,
        x: torch.Tensor,
        batch: Optional[torch.Tensor] = None,
        observer: Optional[nn.Module] = None
    ) -> Tensor:
        if batch is None:
            # treat entire x as single graph
            batch = x.new_zeros(x.size(0), dtype=torch.long)

        # choose pure-PyTorch pooling
        if self.aggregator == 'add':
            out = torch_global_add_pool(x, batch)
        elif self.aggregator == 'mean':
            out = torch_global_mean_pool(x, batch)
        else:  # 'max'
            out = torch_global_max_pool(x, batch)

        # quantization/observer logic
        if self.calib_mode and not self.quantize_mode:
            out = FakeQuantize.apply(out, observer)
        elif self.quantize_mode:
            out = torch.clamp(out, 0, 2**self.num_bits - 1)
            out = out.round()
            # out = observer.dequantize_tensor(out)
        # else: no calibration or quantization

        return out

    def calibrate(self):
        self.calib_mode.fill_(True)

    def quantize(self):
        self.quantize_mode.fill_(True)

    def __repr__(self) -> str:
        return f"{self.__class__.__name__}(aggregator={self.aggregator}, num_bits={self.num_bits})"
