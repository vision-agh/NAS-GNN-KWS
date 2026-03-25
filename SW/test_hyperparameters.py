import os
import glob
import random
import datetime
from pathlib import Path

import numpy as np
import torch
from torch.utils.data import DataLoader
from tqdm import tqdm

from dataset.nas import SpikingDS
from configs.build_config import build_config
from utils.collate_fn import collate_fn
from models.networks.kws import KWS


# -------------------------------------------------
# 0. Test config
# -------------------------------------------------
BATCH_SIZE = 4
NUM_WORKERS = 4
PIN_MEMORY = True

# -------------------------------------------------
# 1. Reproducibility
# -------------------------------------------------
SEED = 42
random.seed(SEED)
np.random.seed(SEED)
torch.manual_seed(SEED)
torch.cuda.manual_seed_all(SEED)

torch.backends.cudnn.deterministic = True
torch.backends.cudnn.benchmark = False

# -------------------------------------------------
# 2. Files & split
# -------------------------------------------------
dataset_root = Path.home() / "Datasets" / "NAS_GSC" / "dataset_aedat"
files = glob.glob(str(dataset_root / "*" / "*"))

# Filter out anything that is not a file (defensive)
files = [f for f in files if Path(f).is_file()]

testing_list = np.loadtxt(dataset_root / "testing_list.txt", dtype=str)
validation_list = np.loadtxt(dataset_root / "validation_list.txt", dtype=str)

# np.loadtxt returns a scalar string if file has exactly one line -> make robust
testing_list = np.atleast_1d(testing_list).tolist()
validation_list = np.atleast_1d(validation_list).tolist()

testing_set = set(testing_list)
validation_set = set(validation_list)


def file_key(path_str: str) -> str:
    """
    Returns key in form: class/file.wav
    Given full file path .../class/file.wav.aedat
    """
    p = Path(path_str)
    cls = p.parent.name           # e.g., right
    stem = p.stem                 # file.wav  (strips .aedat)
    return f"{cls}/{stem}"


# Compute keys once to avoid repeated Path work
file_keys = {f: file_key(f) for f in files}

train_files = [
    f for f in files
    if file_keys[f] not in testing_set and file_keys[f] not in validation_set
]
test_files = [f for f in files if file_keys[f] in testing_set]
val_files = [f for f in files if file_keys[f] in validation_set]

print(
    f"Train files: {len(train_files)} | "
    f"Test files: {len(test_files)} | "
    f"Validation files: {len(val_files)}"
)

# -------------------------------------------------
# 3. Dataset
# -------------------------------------------------
cfg = build_config(model_cfg_path="configs/kws.yaml")

# -------------------------------------------------
# 4. DataLoaders
# -------------------------------------------------
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print("Using device:", device)

pin_memory = bool(PIN_MEMORY and device.type == "cuda")
persistent_workers = bool(NUM_WORKERS and NUM_WORKERS > 0)

# -------------------------------------------------
# 5. Model
# -------------------------------------------------
model = KWS(cfg).to(device)
ckpt = torch.load('example_result/kws/20251225_002857_normalised/best_model_calibration.pth')
# model.load_state_dict(ckpt)
model.eval()
model.quantize()


# -------------------------------------------------
# 8. Helpers
# -------------------------------------------------
def move_to_device(batch, dev):
    return {
        k: (v.to(dev, non_blocking=True) if torch.is_tensor(v) else v)
        for k, v in batch.items()
    }


def _timestamp_accuracy(
    conf_logits: torch.Tensor,
    cls_logits: torch.Tensor,
    gt_keyword: torch.Tensor,
    gt_cls_idx: torch.Tensor,
    tolerance: int = 1,
):
    """
    Hit if:
    - predicted timestamp within tolerance of GT timestamp
    - predicted class at GT timestamp equals GT class at GT timestamp
    Returns:
        (timestamp+class acc with tolerance), (class acc at GT timestamp)
    """
    # Ensure shapes [B, T]
    if gt_keyword.dim() != 2 or gt_cls_idx.dim() != 2:
        raise ValueError(f"Expected gt_keyword and gt_cls_idx to be [B,T], got {gt_keyword.shape} and {gt_cls_idx.shape}")

    B, T = gt_keyword.shape
    dev = conf_logits.device

    gt_ts = gt_keyword.argmax(dim=-1)            # [B]
    pred_ts = conf_logits.argmax(dim=-1)         # [B]

    # cls_logits expected [B, C, T] -> convert to [B, T, C]
    pred_cls_btC = cls_logits.permute(0, 2, 1)   # [B, T, C]

    idx = torch.arange(B, device=dev)

    # Pred class evaluated at GT timestamp (per your metric definition)
    pred_lbl = pred_cls_btC[idx, gt_ts].argmax(dim=-1)  # [B]
    gt_lbl = gt_cls_idx[idx, gt_ts].long()              # [B]

    time_ok = (pred_ts - gt_ts).abs() <= tolerance
    return ((pred_lbl == gt_lbl) & time_ok).float().mean(), (pred_lbl == gt_lbl).float().mean()


def _timestamp_errors(conf_logits: torch.Tensor, gt_keyword: torch.Tensor):
    """
    Returns:
        mean_abs_dt_steps: mean absolute timestamp error [timesteps]
        mean_signed_dt_steps: signed bias (pred - gt) [timesteps]
    """
    gt_ts = gt_keyword.argmax(dim=-1)    # [B]
    pred_ts = conf_logits.argmax(dim=-1) # [B]
    dt = (pred_ts - gt_ts).float()       # + => late, - => early
    return dt.abs().mean(), dt.mean()


def _f1_from_confusion(conf_mat: torch.Tensor):
    """
    Computes macro and weighted F1 from a confusion matrix.
    conf_mat is [C, C] with rows=GT, cols=Pred.
    """
    conf_mat = conf_mat.to(dtype=torch.float32)

    tp = torch.diag(conf_mat)                          # [C]
    fp = conf_mat.sum(dim=0) - tp                      # [C]
    fn = conf_mat.sum(dim=1) - tp                      # [C]
    support = conf_mat.sum(dim=1)                      # [C]

    precision = tp / (tp + fp + 1e-12)
    recall = tp / (tp + fn + 1e-12)
    f1 = 2.0 * precision * recall / (precision + recall + 1e-12)

    macro_f1 = f1.mean().item()
    weighted_f1 = (f1 * support / (support.sum() + 1e-12)).sum().item()
    return macro_f1, weighted_f1


def one_epoch(model, dataloader, optimizer, dev, cfg, desc=None):
    training = model.training and (optimizer is not None)

    total_loss_conf = 0.0
    total_loss_cls = 0.0
    total_loss = 0.0

    total_ts_acc = 0.0
    total_acc = 0.0

    total_dt_abs_steps = 0.0
    total_dt_signed_steps = 0.0

    total_dt_abs_ms = 0.0
    total_dt_signed_ms = 0.0

    total = 0

    conf_mat = None

    if desc is None:
        desc = "Training" if training else "Eval"

    for batch in tqdm(dataloader, desc=desc):
        
        batch = move_to_device(batch, dev)
        conf_logits, cls_logits = model(batch)

        if conf_mat is None:
            C = int(cls_logits.size(1))
            conf_mat = torch.zeros((C, C), dtype=torch.long)

        # BCE targets must be float
        conf_target = batch["conf_vec"].to(dtype=conf_logits.dtype)

        # pos_weight must be floating tensor on the correct device/dtype
        T = conf_target.shape[1]
        pos_weight = torch.full(
            (T,),
            float(T - 1),
            device=dev,
            dtype=conf_logits.dtype,
        )

        loss_conf = torch.nn.functional.binary_cross_entropy_with_logits(
            conf_logits,
            conf_target,
            pos_weight=pos_weight,
            reduction="mean",
        )

        # Select class prediction at predicted timestamp (ts_idx)
        ts_idx = conf_logits.argmax(dim=-1)            # [B]
        B = conf_logits.size(0)

        cls_logits_btC = cls_logits.permute(0, 2, 1)   # [B, T, C]
        idx = torch.arange(B, device=dev)

        sel_logits = cls_logits_btC[idx, ts_idx]       # [B, C]
        sel_targets = batch["cls_vec"][idx, ts_idx].long()  # [B]

        loss_cls = torch.nn.functional.cross_entropy(sel_logits, sel_targets)

        loss = loss_conf + 5.0 * loss_cls

        ts_acc, acc = _timestamp_accuracy(
            conf_logits, cls_logits, batch["conf_vec"], batch["cls_vec"]
        )

        mean_abs_dt_steps, mean_signed_dt_steps = _timestamp_errors(
            conf_logits, batch["conf_vec"]
        )

        # cfg.dataset.bin_width assumed to be milliseconds per bin
        bin_width = float(cfg.dataset.bin_width)
        mean_abs_dt_ms = mean_abs_dt_steps * bin_width
        mean_signed_dt_ms = mean_signed_dt_steps * bin_width

        # F1 score: compute confusion matrix using class at GT timestamp (consistent with _timestamp_accuracy)
        gt_ts = batch["conf_vec"].argmax(dim=-1)              # [B]
        pred_lbl = cls_logits_btC[idx, gt_ts].argmax(dim=-1)  # [B]
        gt_lbl = batch["cls_vec"][idx, gt_ts].long()          # [B]

        C = conf_mat.size(0)
        cm_idx = (gt_lbl * C + pred_lbl).to(dtype=torch.int64)
        conf_mat += torch.bincount(cm_idx.cpu(), minlength=C * C).view(C, C)

        if training:
            optimizer.zero_grad(set_to_none=True)
            loss.backward()
            optimizer.step()

        total_loss += loss.item() * B
        total_loss_conf += loss_conf.item() * B
        total_loss_cls += loss_cls.item() * B
        total_ts_acc += ts_acc.item() * B
        total_acc += acc.item() * B

        total_dt_abs_steps += mean_abs_dt_steps.item() * B
        total_dt_signed_steps += mean_signed_dt_steps.item() * B
        total_dt_abs_ms += mean_abs_dt_ms.item() * B
        total_dt_signed_ms += mean_signed_dt_ms.item() * B

        total += B

    # Avoid divide-by-zero in edge cases
    if total == 0:
        raise RuntimeError("Dataloader produced zero samples.")

    macro_f1, weighted_f1 = _f1_from_confusion(conf_mat)

    return {
        "avg_loss": total_loss / total,
        "avg_loss_conf": total_loss_conf / total,
        "avg_loss_cls": total_loss_cls / total,
        "ts_accuracy": total_ts_acc / total,
        "accuracy": total_acc / total,
        "mean_abs_dt_steps": total_dt_abs_steps / total,
        "mean_signed_dt_steps": total_dt_signed_steps / total,
        "mean_abs_dt_ms": total_dt_abs_ms / total,
        "mean_signed_dt_ms": total_dt_signed_ms / total,
        "macro_f1": macro_f1,
        "weighted_f1": weighted_f1,
    }


# -------------------------------------------------
# 8. CONFIG SEARCH
# -------------------------------------------------

channel_radius = [10, 15, 20, 25, 30, 35, 40]
skip_channels = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

low_time_radius = [0, 100, 250, 500, 1000, 2000, 5000, 10000]
high_time_radius = [1000, 2000, 2500, 5000, 10000, 15000, 20000]

div_factor = [5, 6, 7, 8, 9, 10, 11]
weight = [16, 20, 25, 30, 32, 35, 40]

for param in channel_radius:
    cfg.dataset.channel_radius = param
    print(cfg.dataset)

    test_ds = SpikingDS(test_files, cfg)

    test_dl = DataLoader(
        test_ds,
        batch_size=BATCH_SIZE,
        shuffle=False,
        num_workers=NUM_WORKERS,
        pin_memory=pin_memory,
        persistent_workers=persistent_workers,
        collate_fn=collate_fn,
    )

    with torch.no_grad():
        test_metrics = one_epoch(
            model,
            test_dl,
            optimizer=None,
            dev=device,
            cfg=cfg,
            desc="Testing",
        )
        print(
            f"Test Loss: {test_metrics['avg_loss']:.4f} | "
            f"Test Loss Conf: {test_metrics['avg_loss_conf']:.4f} | "
            f"Test Loss Cls: {test_metrics['avg_loss_cls']:.4f} | "
            f"Test Ts Acc: {test_metrics['ts_accuracy']*100:.2f}% | "
            f"Test Acc: {test_metrics['accuracy']*100:.2f}% | "
            f"Test Macro F1: {test_metrics['macro_f1']*100:.2f}% | "
            f"Test Weighted F1: {test_metrics['weighted_f1']*100:.2f}% | "
            f"Test Dt Abs Steps: {test_metrics['mean_abs_dt_steps']:.2f} | "
            f"Test Dt Signed Steps: {test_metrics['mean_signed_dt_steps']:.2f} | "
            f"Test Dt Abs ms: {test_metrics['mean_abs_dt_ms']:.2f} | "
            f"Test Dt Signed ms: {test_metrics['mean_signed_dt_ms']:.2f}"
        )
