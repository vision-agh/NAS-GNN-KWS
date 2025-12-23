import torch
import torch.nn as nn
from torch import Tensor
from typing import Optional

from models.layers.quantisation.observer import Observer, FakeQuantize


class MyMovingGlobalPooling(nn.Module):
    def __init__(
        self,
        aggregator: str = "max",
        num_bits: int = 8,
        config: Optional[dict] = None,
    ):
        super().__init__()
        if aggregator not in {"mean", "add", "max"}:
            raise ValueError(f"Unknown aggregator '{aggregator}', choose from 'mean','add','max'.")
        self.aggregator = aggregator
        self.num_bits = int(num_bits)
        self.config = config

        self.register_buffer("calib_mode", torch.tensor(False, requires_grad=False))
        self.register_buffer("quantize_mode", torch.tensor(False, requires_grad=False))

    def forward(
        self,
        x: Tensor,
        pos: Tensor,
        batch: Optional[Tensor] = None,
        observer: Optional[Observer] = None,
    ) -> Tensor:
        if batch is None:
            batch = x.new_zeros(x.size(0), dtype=torch.long)

        step = self.config.dataset.bin_width if self.config is not None else 0.01

        if self.aggregator == "add":
            out = self.global_add_pool(x, pos, batch, step=step, observer=observer)
        elif self.aggregator == "mean":
            out = self.global_mean_pool(x, pos, batch, step=step, observer=observer)
        else:
            out = self.global_max_pool(x, pos, batch, step=step, observer=observer)

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

    # ---------------------------------------------------------------------
    # Core implementation (shared)
    # ---------------------------------------------------------------------
    def _global_pool_reduce(
        self,
        x: Tensor,        # [N, F]
        pos: Tensor,      # [N, 2] pos[:,0]=time
        batch: Tensor,    # [N]
        step: float,
        reduce: str,      # "amax" | "mean" | "sum"
        observer: Optional[Observer] = None,
    ) -> Tensor:
        """
        Divide each sample’s events into time bins and pool inside each bin.
        Returns: [B, T, F]
        """
        if x.numel() == 0:
            # If no events, return one graph, one time-bin by convention
            B = int(batch.max().item()) + 1 if batch.numel() else 1
            T = 1
            return x.new_zeros((B, T, x.size(1)))

        # static parameters
        t_max = pos[:, 0].max().item()
        T = int(round(t_max / step)) + 1
        B = int(batch.max().item()) + 1
        feat_dim = x.size(1)

        # time-bin index [N] in 0..T-1
        idx = (pos[:, 0] / step).floor().long()
        idx = idx.clamp_(0, T - 1)

        # flatten (batch, time) -> [N] in 0..B*T-1
        flat_idx = batch * T + idx
        idx_expanded = flat_idx.unsqueeze(1).expand(-1, feat_dim)

        # identity init depends on reduce
        if reduce == "amax":
            pooled_flat = torch.full(
                (B * T, feat_dim),
                fill_value=-float("inf"),
                dtype=x.dtype,
                device=x.device,
            )
        else:
            pooled_flat = torch.zeros(
                (B * T, feat_dim),
                dtype=x.dtype,
                device=x.device,
            )

        pooled_flat = torch.scatter_reduce(
            pooled_flat,
            dim=0,
            index=idx_expanded,
            src=x,
            reduce=reduce,
            include_self=True,
        )  # [B*T, F]

        # For max: replace untouched bins (-inf) with 0 or zero_point (quant mode)
        if reduce == "amax":
            if self.quantize_mode.item():
                if observer is None:
                    raise ValueError("observer must be provided in quantize_mode for max pooling (zero_point fill).")
                fill = x.new_full(pooled_flat.shape, float(observer.zero_point.item()))
            else:
                fill = x.new_zeros(pooled_flat.shape)
            pooled_flat = torch.where(pooled_flat == -float("inf"), fill, pooled_flat)

        return pooled_flat.view(B, T, feat_dim)

    # ---------------------------------------------------------------------
    # Public wrappers (kept as in your code)
    # ---------------------------------------------------------------------
    def global_max_pool(
        self,
        x: Tensor,
        pos: Tensor,
        batch: Tensor,
        step: float = 0.01,
        observer: Optional[Observer] = None,
    ) -> Tensor:
        return self._global_pool_reduce(x, pos, batch, step=step, reduce="amax", observer=observer)

    def global_mean_pool(
        self,
        x: Tensor,
        pos: Tensor,
        batch: Tensor,
        step: float = 0.01,
        observer: Optional[Observer] = None,
    ) -> Tensor:
        # Note: requires a PyTorch version where scatter_reduce supports "mean"
        return self._global_pool_reduce(x, pos, batch, step=step, reduce="mean", observer=observer)

    def global_add_pool(
        self,
        x: Tensor,
        pos: Tensor,
        batch: Tensor,
        step: float = 0.01,
        observer: Optional[Observer] = None,
    ) -> Tensor:
        # Note: scatter_reduce uses "sum"
        return self._global_pool_reduce(x, pos, batch, step=step, reduce="sum", observer=observer)

    def __repr__(self) -> str:
        return f"{self.__class__.__name__}(aggregator={self.aggregator}, num_bits={self.num_bits})"
