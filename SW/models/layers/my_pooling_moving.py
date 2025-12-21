import torch
import torch.nn as nn
from torch import Tensor
from typing import Optional

from models.layers.quantisation.observer import Observer, FakeQuantize, quantize_tensor

# Pooling implementations in pure PyTorch
def global_add_pool(x: Tensor, 
                          pos: Tensor, 
                          batch: Tensor) -> Tensor:
    # x: [N, F], batch: [N] with values in {0,..,B-1}
    B = int(batch.max().item()) + 1
    out = x.new_zeros((B, x.size(1)))
    out = out.index_add(0, batch, x)
    return out


def global_mean_pool(x: Tensor,        # [N, F]
    pos: Tensor,      # [N, 2]  – pos[:, 0] is time in seconds
    batch: Tensor,    # [N]     – values 0 … B-1
    step: float = 0.01
) -> Tensor:
    """
    Divide each sample’s events into T = int(1/step) time bins and perform
    max-pooling inside every bin separately for every batch.
    Returns a tensor of shape [B, T, F].

    The implementation is *purely* out-of-place: no tensor is modified after
    construction, so it is autograd-friendly and side-effect-free.
    """

    # 1) static parameters
    T = int(pos[:, 0].max().item() / step)
    B = int(batch.max().item()) + 1
    F = x.size(1)

    # 2) time-bin index for every event  ➜ [N] in 0 … T-1
    idx = (pos[:, 0] / step).floor().long()

    # 3) flatten (batch, time) ⇒ single axis 0 … B·T-1
    flat_idx = batch * T + idx

    # 4) tensor filled with −∞, used as “identity” for max
    pooled_flat = torch.full(
        (B * T, F),
        fill_value=0,
        dtype=x.dtype,
        device=x.device,
    )

    # 5) broadcast indices to match feature dimension  ➜ [N, F]
    idx_expanded = flat_idx.unsqueeze(1).expand(-1, F)

    # 6) scatter-reduce (mean) – out-of-place
    pooled_flat = torch.scatter_reduce(
        pooled_flat,
        dim=0,
        index=idx_expanded,
        src=x,
        reduce="mean",
        include_self=True,
    )  # shape [B·T, F]

    # 7) replace untouched bins (still −∞) with 0 – out-of-place “where”
    pooled_flat = torch.where(
        pooled_flat == -float("inf"),
        torch.ones_like(pooled_flat) * (-100.0),
        pooled_flat,
    )

    # 8) reshape back to [B, T, F] – view/reshape is fine, no data is mutated
    return pooled_flat.view(B, T, F)





class MyMovingGlobalPooling(nn.Module):
    def __init__(
        self,
        aggregator: str = 'max',
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
        pos: torch.Tensor,
        batch: Optional[torch.Tensor] = None,
        observer: Optional[nn.Module] = None
    ) -> Tensor:
        
        if batch is None:
            # treat entire x as single graph
            batch = x.new_zeros(x.size(0), dtype=torch.long)

        # choose pure-PyTorch pooling
        if self.aggregator == 'add':
            out = self.global_add_pool(x, pos, batch, observer=observer)
        elif self.aggregator == 'mean':
            out = self.global_mean_pool(x, pos, batch, observer=observer)
        else:  # 'max'
            out = self.global_max_pool(x, pos, batch, observer=observer)

        # quantization/observer logic
        # if self.calib_mode and not self.quantize_mode:
        #     out = FakeQuantize.apply(out, observer)
        # elif self.quantize_mode:
        #     out = torch.clamp(out, 0, 2**self.num_bits - 1)
        #     out = out.round()
        #     out = observer.dequantize_tensor(out)
        # else: no calibration or quantization

        return out

    def calibrate(self):
        self.calib_mode.fill_(True)

    def quantize(self):
        self.quantize_mode.fill_(True)

    def global_max_pool(self,
        x: Tensor,        # [N, F]
        pos: Tensor,      # [N, 2]  – pos[:, 0] is time in seconds
        batch: Tensor,    # [N]     – values 0 … B-1
        step: float = 0.01,
        observer: Optional[Observer] = None
    ) -> Tensor:
        """
        Divide each sample’s events into T = int(1/step) time bins and perform
        max-pooling inside every bin separately for every batch.
        Returns a tensor of shape [B, T, F].

        The implementation is *purely* out-of-place: no tensor is modified after
        construction, so it is autograd-friendly and side-effect-free.
        """

        # 1) static parameters
        T = int(pos[:, 0].max().item() / step) + 1
        B = int(batch.max().item()) + 1
        F = x.size(1)

        # 2) time-bin index for every event  ➜ [N] in 0 … T-1
        idx = (pos[:, 0] / step).floor().long()

        # 3) flatten (batch, time) ⇒ single axis 0 … B·T-1
        flat_idx = batch * T + idx

        # 4) tensor filled with −∞, used as “identity” for max
        pooled_flat = torch.full(
            (B * T, F),
            fill_value=-float("inf"),
            dtype=x.dtype,
            device=x.device,
        )

        # 5) broadcast indices to match feature dimension  ➜ [N, F]
        idx_expanded = flat_idx.unsqueeze(1).expand(-1, F)

        # 6) scatter-reduce (amax) – out-of-place
        pooled_flat = torch.scatter_reduce(
            pooled_flat,
            dim=0,
            index=idx_expanded,
            src=x,
            reduce="amax",
            include_self=True,
        )  # shape [B·T, F]

        # 7) replace untouched bins (still −∞) with 0 – out-of-place “where”
        if self.quantize_mode.item():
            pooled_flat = torch.where(
            pooled_flat == -float("inf"),
            torch.ones_like(pooled_flat) * observer.zero_point.item(),
            pooled_flat,
        )
        else:
            pooled_flat = torch.where(
                pooled_flat == -float("inf"),
                torch.ones_like(pooled_flat) * (0.0),
                pooled_flat,
            )

        # 8) reshape back to [B, T, F] – view/reshape is fine, no data is mutated
        return pooled_flat.view(B, T, F)
    
    def global_mean_pool(self,
        x: Tensor,        # [N, F]
        pos: Tensor,      # [N, 2]  – pos[:, 0] is time in seconds
        batch: Tensor,    # [N]     – values 0 … B-1
        step: float = 0.01,
        observer: Optional[Observer] = None
    ) -> Tensor:
        """
        Divide each sample’s events into T = int(1/step) time bins and perform
        max-pooling inside every bin separately for every batch.
        Returns a tensor of shape [B, T, F].

        The implementation is *purely* out-of-place: no tensor is modified after
        construction, so it is autograd-friendly and side-effect-free.
        """

        # 1) static parameters
        T = int(1.0 / step)
        B = int(batch.max().item()) + 1
        F = x.size(1)

        # 2) time-bin index for every event  ➜ [N] in 0 … T-1
        idx = (pos[:, 0] / step).floor().long()

        # 3) flatten (batch, time) ⇒ single axis 0 … B·T-1
        flat_idx = batch * T + idx

        # 4) tensor filled with −∞, used as “identity” for max
        pooled_flat = torch.full(
            (B * T, F),
            fill_value=float(0),
            dtype=x.dtype,
            device=x.device,
        )

        # 5) broadcast indices to match feature dimension  ➜ [N, F]
        idx_expanded = flat_idx.unsqueeze(1).expand(-1, F)

        # 6) scatter-reduce (amax) – out-of-place
        pooled_flat = torch.scatter_reduce(
            pooled_flat,
            dim=0,
            index=idx_expanded,
            src=x,
            reduce="mean",
            include_self=True,
        )  # shape [B·T, F]

        # # 7) replace untouched bins (still −∞) with 0 – out-of-place “where”
        # if self.quantize_mode.item():
        #     pooled_flat = torch.where(
        #     pooled_flat == -float("inf"),
        #     torch.ones_like(pooled_flat) * observer.zero_point.item(),
        #     pooled_flat,
        # )
        # else:
        #     pooled_flat = torch.where(
        #         pooled_flat == -float("inf"),
        #         torch.ones_like(pooled_flat) * (0.0),
        #         pooled_flat,
        #     )

        # 8) reshape back to [B, T, F] – view/reshape is fine, no data is mutated
        return pooled_flat.view(B, T, F)
    
    def global_add_pool(self,
        x: Tensor,        # [N, F]
        pos: Tensor,      # [N, 2]  – pos[:, 0] is time in seconds
        batch: Tensor,    # [N]     – values 0 … B-1
        step: float = 0.01,
        observer: Optional[Observer] = None
    ) -> Tensor:
        """
        Divide each sample’s events into T = int(1/step) time bins and perform
        max-pooling inside every bin separately for every batch.
        Returns a tensor of shape [B, T, F].

        The implementation is *purely* out-of-place: no tensor is modified after
        construction, so it is autograd-friendly and side-effect-free.
        """

        # 1) static parameters
        T = int(1.0 / step)
        B = int(batch.max().item()) + 1
        F = x.size(1)

        # 2) time-bin index for every event  ➜ [N] in 0 … T-1
        idx = (pos[:, 0] / step).floor().long()

        # 3) flatten (batch, time) ⇒ single axis 0 … B·T-1
        flat_idx = batch * T + idx

        # 4) tensor filled with −∞, used as “identity” for max
        pooled_flat = torch.full(
            (B * T, F),
            fill_value=float(0),
            dtype=x.dtype,
            device=x.device,
        )

        # 5) broadcast indices to match feature dimension  ➜ [N, F]
        idx_expanded = flat_idx.unsqueeze(1).expand(-1, F)

        # 6) scatter-reduce (amax) – out-of-place
        pooled_flat = torch.scatter_reduce(
            pooled_flat,
            dim=0,
            index=idx_expanded,
            src=x,
            reduce="sum",
            include_self=True,
        )  # shape [B·T, F]

        # # 7) replace untouched bins (still −∞) with 0 – out-of-place “where”
        # if self.quantize_mode.item():
        #     pooled_flat = torch.where(
        #     pooled_flat == -float("inf"),
        #     torch.ones_like(pooled_flat) * observer.zero_point.item(),
        #     pooled_flat,
        # )
        # else:
        #     pooled_flat = torch.where(
        #         pooled_flat == -float("inf"),
        #         torch.ones_like(pooled_flat) * (0.0),
        #         pooled_flat,
        #     )

        # 8) reshape back to [B, T, F] – view/reshape is fine, no data is mutated
        return pooled_flat.view(B, T, F)

    def __repr__(self) -> str:
        return f"{self.__class__.__name__}(aggregator={self.aggregator}, num_bits={self.num_bits})"
