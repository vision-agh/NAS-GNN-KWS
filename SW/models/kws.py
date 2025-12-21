from typing import Dict, Any

import torch
import lightning as L
from torch.nn import functional as F

from models.networks.kws import GCN


class LNRecognition(L.LightningModule):
    """Keyword-spotter: confidence + klasyfikacja słowa (loss liczony w max-conf timestep)."""

    # -------------------------------------------------- setup
    def __init__(self, config: Any):
        super().__init__()

        self.config = config
        # --------- hiperpary ---------
        self.save_hyperparameters(config)
        self.lr           = config.train.lr
        self.weight_decay = config.train.weight_decay
        self.batch_size   = config.train.batch_size
        self.num_classes  = config.model.num_classes            # 11 (10 słów + background)

        # --- NEW: timestamp resolution (ms per timestep) ---
        # falls back to 10 ms if not provided in the config
        self.ts_resolution_ms = 10 # ms

        # --------- sieć --------------
        self.model = GCN(config)

        # --------- straty ------------
        # confidence – 20 logitów (po 50 ms)
        # pos_weight = (liczba negatywów / liczba pozytywów) ≈ 99
        self.register_buffer("pos_weight", torch.full((100,), 99.0))
        self.conf_criterion = torch.nn.BCEWithLogitsLoss(
            pos_weight=self.pos_weight, reduction="mean"
        )

        # waga gałęzi klasyfikacji (domyślnie 5.0)
        self.cls_weight = 5.0

    # -------------------------------------------------- core API
    def forward(self, data):
        """
        Zwraca:
            conf_logits – [B, T]   (T = 20)
            cls_logits  – [B, C, T]
        """
        return self.model(data)

    def configure_optimizers(self):
        optimizer = torch.optim.Adam(self.parameters(), 
                                     lr=self.lr, 
                                     weight_decay=self.weight_decay)

        if self.config.train.use_scheduler:
            lr_scheduler = torch.optim.lr_scheduler.ReduceLROnPlateau(optimizer,
                                                                    mode='max',
                                                                    factor=0.5,
                                                                    patience=5)
            print(optimizer)
            print(lr_scheduler)
            return {'optimizer': optimizer, 
                    'lr_scheduler': lr_scheduler,
                    'monitor': 'val_ts_acc'}
        print(optimizer)
        print("No scheduler used")
        return optimizer

    # -------------------------------------------------- utils
    @staticmethod
    def _timestamp_accuracy(
        conf_logits: torch.Tensor,
        cls_logits: torch.Tensor,
        gt_keyword: torch.Tensor,
        gt_cls_idx: torch.Tensor,
        tolerance: int = 1,
    ) -> torch.Tensor:
        """
        Trafiamy, jeśli:
        • pred_timestamp w odległości ≤ `tolerance` od GT
        • pred_class == GT_class w tym timestampie
        """
        B, T = gt_keyword.shape

        gt_ts   = gt_keyword.argmax(dim=-1)                     # [B]
        pred_ts = conf_logits.argmax(dim=-1)                    # [B]
        pred_cls_btC = cls_logits.permute(0, 2, 1)              # [B,T,C]
        pred_lbl = pred_cls_btC[torch.arange(B), gt_ts].argmax(dim=-1)
        gt_lbl  = gt_cls_idx[torch.arange(B), gt_ts]            # [B]

        time_ok = (pred_ts - gt_ts).abs() <= tolerance
        return ((pred_lbl == gt_lbl) & time_ok).float().mean(), (pred_lbl == gt_lbl).float().mean()

    # --- NEW: simple timestamp error metrics ---
    @staticmethod
    def _timestamp_errors(
        conf_logits: torch.Tensor,
        gt_keyword: torch.Tensor,
    ):
        """
        Returns:
            mean_abs_dt_steps: mean absolute timestamp error [timesteps]
            mean_signed_dt_steps: signed bias (pred - gt) [timesteps]
        """
        gt_ts   = gt_keyword.argmax(dim=-1)          # [B]
        pred_ts = conf_logits.argmax(dim=-1)         # [B]
        dt = (pred_ts - gt_ts).float()               # + => late, - => early
        mean_abs_dt_steps = dt.abs().mean()
        mean_signed_dt_steps = dt.mean()
        return mean_abs_dt_steps, mean_signed_dt_steps

    # -------------------------------------------------- train / val / test
    def _shared_step(self, batch: Dict[str, torch.Tensor], stage: str):
        conf_logits, cls_logits = self.forward(batch)

        # -------- confidence loss (liczony na wszystkich T)
        loss_conf = self.conf_criterion(conf_logits, batch["keyword"])

        # -------- classification loss (TYLKO w timestepie z max-confidence)
        ts_idx = conf_logits.argmax(dim=-1)                     # [B]
        B      = conf_logits.size(0)

        cls_logits_btC = cls_logits.permute(0, 2, 1)            # [B,T,C]
        sel_logits  = cls_logits_btC[torch.arange(B, device=self.device), ts_idx]   # [B,C]
        sel_targets = batch["cls"][torch.arange(B, device=self.device), ts_idx].long()

        loss_cls = F.cross_entropy(sel_logits, sel_targets)

        total_loss = loss_conf + self.cls_weight * loss_cls

        # -------- logi
        self.log(f"{stage}_loss_conf", loss_conf, batch_size=self.batch_size)
        self.log(f"{stage}_loss_cls",  loss_cls, batch_size=self.batch_size)
        self.log(f"{stage}_loss",      total_loss, batch_size=self.batch_size)

        ts_acc, acc = self._timestamp_accuracy(
            conf_logits, cls_logits, batch["keyword"], batch["cls"]
        )
        self.log(f"{stage}_ts_acc", ts_acc, prog_bar=True, batch_size=self.batch_size, on_epoch=True)
        self.log(f"{stage}_acc",     acc,   prog_bar=True, batch_size=self.batch_size, on_epoch=True)

        # -------- NEW: delta-T metrics (steps + milliseconds)
        mean_abs_dt_steps, mean_signed_dt_steps = self._timestamp_errors(conf_logits, batch["keyword"])
        self.log(f"{stage}_dt_abs_steps",    mean_abs_dt_steps,    prog_bar=False, batch_size=self.batch_size, on_epoch=True)
        self.log(f"{stage}_dt_signed_steps", mean_signed_dt_steps, prog_bar=False, batch_size=self.batch_size, on_epoch=True)

        # also in milliseconds for readability
        mean_abs_dt_ms    = mean_abs_dt_steps * float(self.ts_resolution_ms)
        mean_signed_dt_ms = mean_signed_dt_steps * float(self.ts_resolution_ms)
        self.log(f"{stage}_dt_abs_ms",    mean_abs_dt_ms,    prog_bar=True, batch_size=self.batch_size, on_epoch=True)
        self.log(f"{stage}_dt_signed_ms", mean_signed_dt_ms, prog_bar=False, batch_size=self.batch_size, on_epoch=True)

        return total_loss

    def training_step(self, batch, batch_idx):
        return self._shared_step(batch, "train")

    def validation_step(self, batch, batch_idx):
        self._shared_step(batch, "val")

    def test_step(self, batch, batch_idx):
        self._shared_step(batch, "test")
