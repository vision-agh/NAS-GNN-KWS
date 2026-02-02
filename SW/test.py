import argparse
import glob
import random
from pathlib import Path

import numpy as np
import torch
from torch.utils.data import DataLoader
from tqdm import tqdm
from omegaconf import OmegaConf

from dataset.nas import SpikingDS
from utils.collate_fn import collate_fn
from models.networks.kws import KWS


# -------------------------
# Reproducibility
# -------------------------
def set_seed(seed: int = 42):
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    torch.cuda.manual_seed_all(seed)
    torch.backends.cudnn.deterministic = True
    torch.backends.cudnn.benchmark = False


def count_parameters(model: torch.nn.Module):
    total = sum(p.numel() for p in model.parameters())
    trainable = sum(p.numel() for p in model.parameters() if p.requires_grad)
    return total, trainable


# -------------------------
# Dataset split helpers
# -------------------------
def file_key(path_str: str) -> str:
    """
    Returns key in form: class/file.wav
    Given full file path .../class/file.wav.aedat (or similar)
    """
    p = Path(path_str)
    cls = p.parent.name
    stem = p.stem
    return f"{cls}/{stem}"


def build_splits(dataset_root: Path):
    files = glob.glob(str(dataset_root / "*" / "*"))
    files = [f for f in files if Path(f).is_file()]

    testing_list = np.loadtxt(dataset_root / "testing_list.txt", dtype=str)
    validation_list = np.loadtxt(dataset_root / "validation_list.txt", dtype=str)

    testing_list = np.atleast_1d(testing_list).tolist()
    validation_list = np.atleast_1d(validation_list).tolist()

    testing_set = set(testing_list)
    validation_set = set(validation_list)

    file_keys = {f: file_key(f) for f in files}

    train_files = [
        f for f in files
        if file_keys[f] not in testing_set and file_keys[f] not in validation_set
    ]
    test_files = [f for f in files if file_keys[f] in testing_set]
    val_files = [f for f in files if file_keys[f] in validation_set]

    return train_files, val_files, test_files


# -------------------------
# Macro F1 helper (NEW)
# -------------------------
def macro_f1_from_labels(y_true: torch.Tensor, y_pred: torch.Tensor, num_classes: int, eps: float = 1e-12) -> float:
    """
    Computes macro F1 over classes that appear in y_true (support>0).
    y_true, y_pred: [N] int64 tensors on CPU or GPU.
    """
    y_true = y_true.to(torch.int64).view(-1)
    y_pred = y_pred.to(torch.int64).view(-1)

    # confusion matrix via bincount
    valid = (y_true >= 0) & (y_true < num_classes) & (y_pred >= 0) & (y_pred < num_classes)
    y_true = y_true[valid]
    y_pred = y_pred[valid]

    idx = y_true * num_classes + y_pred
    cm = torch.bincount(idx, minlength=num_classes * num_classes).view(num_classes, num_classes).to(torch.float64)

    tp = torch.diag(cm)
    support = cm.sum(dim=1)       # row sums (true counts)
    pred_count = cm.sum(dim=0)    # col sums (pred counts)

    fp = pred_count - tp
    fn = support - tp

    precision = tp / (tp + fp + eps)
    recall = tp / (tp + fn + eps)
    f1 = 2.0 * precision * recall / (precision + recall + eps)

    present = support > 0
    if not torch.any(present):
        return 0.0

    return f1[present].mean().item()


# -------------------------
# Evaluation
# -------------------------
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
    tolerance: int = 3,
):
    if gt_keyword.dim() != 2 or gt_cls_idx.dim() != 2:
        raise ValueError(
            f"Expected gt_keyword and gt_cls_idx to be [B,T], got {gt_keyword.shape} and {gt_cls_idx.shape}"
        )

    B, T = gt_keyword.shape
    dev = conf_logits.device

    gt_ts = gt_keyword.argmax(dim=-1)
    pred_ts = conf_logits.argmax(dim=-1)

    pred_cls_btC = cls_logits.permute(0, 2, 1)
    idx = torch.arange(B, device=dev)

    pred_lbl = pred_cls_btC[idx, pred_ts].argmax(dim=-1)
    gt_lbl = gt_cls_idx[idx, gt_ts].long()

    time_ok = (pred_ts - gt_ts).abs() <= tolerance
    ts_acc = ((pred_lbl == gt_lbl) & time_ok).float().mean()
    acc = (pred_lbl == gt_lbl).float().mean()
    return ts_acc, acc


def _timestamp_errors(conf_logits: torch.Tensor, gt_keyword: torch.Tensor):
    gt_ts = gt_keyword.argmax(dim=-1)
    pred_ts = conf_logits.argmax(dim=-1)
    dt = (pred_ts - gt_ts).float()
    return dt.abs().mean(), dt.mean()


@torch.no_grad()
def evaluate(model, dataloader, dev, cfg, desc="Eval"):
    model.eval()

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

    # NEW: accumulate labels for macro F1
    y_true_all = []
    y_pred_all = []
    num_classes = None

    for batch in tqdm(dataloader, desc=desc):
        batch = move_to_device(batch, dev)
        conf_logits, cls_logits = model(batch)

        # cls_logits: [B, C, T]
        if num_classes is None:
            num_classes = int(cls_logits.size(1))

        conf_target = batch["conf_vec"].to(dtype=conf_logits.dtype)

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

        ts_idx = conf_logits.argmax(dim=-1)  # predicted timestamp (used for loss_cls)
        B = conf_logits.size(0)

        cls_logits_btC = cls_logits.permute(0, 2, 1)  # [B, T, C]
        idx = torch.arange(B, device=dev)

        sel_logits = cls_logits_btC[idx, ts_idx]           # [B, C]
        sel_targets = batch["cls_vec"][idx, ts_idx].long() # [B]

        loss_cls = torch.nn.functional.cross_entropy(sel_logits, sel_targets)
        loss = loss_conf + loss_cls

        ts_acc, acc = _timestamp_accuracy(
            conf_logits, cls_logits, batch["conf_vec"], batch["cls_vec"]
        )

        mean_abs_dt_steps, mean_signed_dt_steps = _timestamp_errors(
            conf_logits, batch["conf_vec"]
        )

        bin_width = float(cfg.dataset.bin_width)
        mean_abs_dt_ms = mean_abs_dt_steps * bin_width
        mean_signed_dt_ms = mean_signed_dt_steps * bin_width

        total_loss += loss.item() * B
        total_loss_conf += loss_conf.item() * B
        total_loss_cls += loss_cls.item() * B
        total_ts_acc += ts_acc.item() * B
        total_acc += acc.item() * B

        total_dt_abs_steps += mean_abs_dt_steps.item() * B
        total_dt_signed_steps += mean_signed_dt_steps.item() * B
        total_dt_abs_ms += mean_abs_dt_ms.item() * B
        total_dt_signed_ms += mean_signed_dt_ms.item() * B

        # NEW: label collection for macro F1
        gt_ts = batch["conf_vec"].argmax(dim=-1)                 # [B]
        gt_lbl = batch["cls_vec"][idx, gt_ts].long()             # [B]
        pred_ts = conf_logits.argmax(dim=-1)                     # [B]
        pred_lbl = cls_logits_btC[idx, pred_ts].argmax(dim=-1)   # [B]

        y_true_all.append(gt_lbl.detach().cpu())
        y_pred_all.append(pred_lbl.detach().cpu())

        total += B

    if total == 0:
        raise RuntimeError("Dataloader produced zero samples.")

    y_true = torch.cat(y_true_all, dim=0) if y_true_all else torch.empty(0, dtype=torch.int64)
    y_pred = torch.cat(y_pred_all, dim=0) if y_pred_all else torch.empty(0, dtype=torch.int64)
    macro_f1 = macro_f1_from_labels(y_true, y_pred, num_classes=num_classes or 0)

    return {
        "avg_loss": total_loss / total,
        "avg_loss_conf": total_loss_conf / total,
        "avg_loss_cls": total_loss_cls / total,
        "ts_accuracy": total_ts_acc / total,
        "accuracy": total_acc / total,
        "macro_f1": macro_f1,  # NEW
        "mean_abs_dt_steps": total_dt_abs_steps / total,
        "mean_signed_dt_steps": total_dt_signed_steps / total,
        "mean_abs_dt_ms": total_dt_abs_ms / total,
        "mean_signed_dt_ms": total_dt_signed_ms / total,
    }


def print_metrics(title: str, m: dict):
    print(
        f"{title} | "
        f"Loss: {m['avg_loss']:.4f} | "
        f"LossConf: {m['avg_loss_conf']:.4f} | "
        f"LossCls: {m['avg_loss_cls']:.4f} | "
        f"TsAcc: {m['ts_accuracy']*100:.2f}% | "
        f"Acc: {m['accuracy']*100:.2f}% | "
        f"MacroF1: {m['macro_f1']:.4f} | "  # NEW
        f"DtAbsSteps: {m['mean_abs_dt_steps']:.2f} | "
        f"DtSignedSteps: {m['mean_signed_dt_steps']:.2f} | "
        f"DtAbsMs: {m['mean_abs_dt_ms']:.2f} | "
        f"DtSignedMs: {m['mean_signed_dt_ms']:.2f}"
    )


def main():
    parser = argparse.ArgumentParser("KWS test-only (no wandb, no saving)")
    parser.add_argument("--run_dir", type=str, required=True,
                        help="Path to the run folder that contains config.yaml and checkpoints/")
    parser.add_argument("--split", type=str, default="test", choices=["test", "val", "train"],
                        help="Which split to evaluate.")
    parser.add_argument("--batch_size", type=int, default=16)
    parser.add_argument("--num_workers", type=int, default=8)
    parser.add_argument("--pin_memory", action="store_true")
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    set_seed(args.seed)

    run_dir = Path(args.run_dir)
    if not run_dir.exists():
        raise FileNotFoundError(f"run_dir not found: {run_dir}")

    # ---- Load config from the selected run folder (no build_config, no overrides)
    cfg_path = run_dir / "config.yaml"
    if not cfg_path.exists():
        raise FileNotFoundError(f"Missing config.yaml in: {run_dir}")

    cfg = OmegaConf.load(cfg_path)
    OmegaConf.resolve(cfg)

    print("Configuration:")
    print(OmegaConf.to_yaml(cfg))

    # ---- dataset root
    dataset_root = Path.home() / "Datasets" / "NAS_GSC" / "dataset_aedat_w_delays_whole"
    train_files, val_files, test_files = build_splits(dataset_root)
    print(f"Split sizes | Train: {len(train_files)} | Val: {len(val_files)} | Test: {len(test_files)}")

    if args.split == "train":
        files = train_files
    elif args.split == "val":
        files = val_files
    else:
        files = test_files

    # ---- Dataset / Dataloader
    ds = SpikingDS(files, cfg)

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(device)
    pin_memory = bool(args.pin_memory and device.type == "cuda")
    persistent_workers = bool(args.num_workers and args.num_workers > 0)

    dl = DataLoader(
        ds,
        batch_size=args.batch_size,
        shuffle=False,
        num_workers=args.num_workers,
        pin_memory=pin_memory,
        persistent_workers=persistent_workers,
        collate_fn=collate_fn,
    )

    # ---- Model
    model = KWS(cfg).to(device)
    total_params, trainable_params = count_parameters(model)
    print(f"Device: {device}")
    print(f"Params | total: {total_params:,} | trainable: {trainable_params:,}")

    # ---- Checkpoint selection
    print(f"Loading checkpoint: {run_dir / 'checkpoints' / 'best_model.pth'}")
    state = torch.load(run_dir / "checkpoints" / "best_model.pth", map_location=device)
    model.load_state_dict(state, strict=True)

    # ---- Evaluate
    metrics = evaluate(model, dl, device, cfg, desc=f"Eval ({args.split})")
    print_metrics(f"RESULT ({args.split})", metrics)

    print(f"Loading checkpoint: {run_dir / 'checkpoints' / 'best_model_calibration.pth'}")
    state = torch.load(run_dir / "checkpoints" / "best_model_calibration.pth", map_location=device)
    model.load_state_dict(state, strict=True)

    model.quantize()
    metrics = evaluate(model, dl, device, cfg, desc=f"Eval ({args.split})")
    print_metrics(f"RESULT QUANT ({args.split})", metrics)


if __name__ == "__main__":
    main()
