import os
import glob
import random
import datetime
import multiprocessing as mp
from pathlib import Path
from omegaconf import OmegaConf

import numpy as np
import torch
from torch.utils.data import DataLoader
from tqdm import tqdm

import wandb  # ✅ NEW

from dataset.nas import SpikingDS
from configs.build_config import build_config
from utils.collate_fn import collate_fn
from models.networks.kws import KWS


# -------------------------------------------------
# 0. Training config (CHANGE HERE)
# -------------------------------------------------
OPTIMIZER_TYPE = "adam"  # "adam" or "sgd"
LR = 1e-3
LR_CALIBRATION = 1e-4
WEIGHT_DECAY = 1e-4

USE_COSINE_SCHEDULER = True
EPOCHS = 50
EPOCHS_CALIBRATION = 5
SGD_MOMENTUM = 0.9

BATCH_SIZE = 16
NUM_WORKERS = 8
PIN_MEMORY = True

mp.set_start_method('fork', force=True)
# -------------------------------------------------
# WandB config (CHANGE HERE)
# -------------------------------------------------
WANDB_PROJECT = "kws-nas-gsc"
WANDB_ENTITY = None  # e.g. "your_team" (or leave None)
WANDB_TAGS = ["kws", "event-camera", "nas-gsc"]
WANDB_MODE = os.environ.get("WANDB_MODE", "online")  # set to "offline" if needed
WANDB_LOG_GRADS = True  # wandb.watch(model, log="all")
WANDB_LOG_CODE = True   # save your code snapshot


def count_parameters(model: torch.nn.Module):
    total = sum(p.numel() for p in model.parameters())
    trainable = sum(p.numel() for p in model.parameters() if p.requires_grad)
    return total, trainable


def log_metrics_wandb(metrics: dict, prefix: str, step: int):
    """
    Adds a prefix to metric keys and logs them in wandb.
    """
    log_dict = {f"{prefix}/{k}": v for k, v in metrics.items()}
    wandb.log(log_dict, step=step)


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
# dataset_root = Path.home() / "Datasets" / "NAS_GSC" / "dataset_aedat_w_delays_whole"
dataset_root = Path("/net/storage/pr3/plgrid/plgg_dvs_phd/Audio/dataset_aedat_w_delays_whole")
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
    cls = p.parent.name
    stem = p.stem
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

train_ds = SpikingDS(train_files, cfg)
test_ds = SpikingDS(test_files, cfg)
val_ds = SpikingDS(val_files, cfg)


# -------------------------------------------------
# 4. DataLoaders
# -------------------------------------------------
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print("Using device:", device)

pin_memory = bool(PIN_MEMORY and device.type == "cuda")
persistent_workers = bool(NUM_WORKERS and NUM_WORKERS > 0)

train_dl = DataLoader(
    train_ds,
    batch_size=BATCH_SIZE,
    shuffle=True,
    num_workers=NUM_WORKERS,
    pin_memory=pin_memory,
    persistent_workers=persistent_workers,
    collate_fn=collate_fn,
)

test_dl = DataLoader(
    test_ds,
    batch_size=BATCH_SIZE,
    shuffle=False,
    num_workers=NUM_WORKERS,
    pin_memory=pin_memory,
    persistent_workers=persistent_workers,
    collate_fn=collate_fn,
)

val_dl = DataLoader(
    val_ds,
    batch_size=BATCH_SIZE,
    shuffle=False,
    num_workers=NUM_WORKERS,
    pin_memory=pin_memory,
    persistent_workers=persistent_workers,
    collate_fn=collate_fn,
)


# -------------------------------------------------
# 5. Model
# -------------------------------------------------
model = KWS(cfg).to(device)

total_params, trainable_params = count_parameters(model)


# -------------------------------------------------
# ✅ 5.5 WandB init (AFTER cfg + model exist)
# -------------------------------------------------
date_time = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
run_name = f"kws_{date_time}"


# 1) Your "searchable" hyperparams
wandb_config = {
    # training
    "seed": SEED,
    "optimizer_type": OPTIMIZER_TYPE,
    "lr": LR,
    "lr_calibration": LR_CALIBRATION,
    "weight_decay": WEIGHT_DECAY,
    "use_cosine_scheduler": USE_COSINE_SCHEDULER,
    "epochs": EPOCHS,
    "epochs_calibration": EPOCHS_CALIBRATION,
    "sgd_momentum": SGD_MOMENTUM,
    "batch_size": BATCH_SIZE,
    "num_workers": NUM_WORKERS,
    "pin_memory": PIN_MEMORY,

    # data
    "dataset_root": str(dataset_root),
    "n_train_files": len(train_files),
    "n_val_files": len(val_files),
    "n_test_files": len(test_files),

    # model meta
    "device": str(device),
    "total_params": total_params,
    "trainable_params": trainable_params,
}

wandb.init(
    project=WANDB_PROJECT,
    entity=WANDB_ENTITY,
    name=run_name,
    config=wandb_config,
    tags=WANDB_TAGS,
    mode=WANDB_MODE,
)

# 2) Store the full cfg as YAML (safe + readable)
wandb.run.summary["cfg_yaml"] = OmegaConf.to_yaml(cfg)

# 3) (Optional) Also store the resolved dict version in summary
wandb.run.summary["cfg_dict"] = OmegaConf.to_container(cfg, resolve=True)

# Log model architecture text to W&B (very useful for reproducibility)
wandb.run.summary["model_architecture"] = str(model)
wandb.run.summary["total_params"] = total_params
wandb.run.summary["trainable_params"] = trainable_params

# Optional: save code snapshot
if WANDB_LOG_CODE:
    try:
        wandb.run.log_code(".")
    except Exception as e:
        print(f"[wandb] log_code failed: {e}")

# Optional: watch gradients + weights
if WANDB_LOG_GRADS:
    # log="all" logs grads + weights histograms; can be heavy
    wandb.watch(model, log="all", log_freq=50)


# -------------------------------------------------
# 6. Optimizers
# -------------------------------------------------
if OPTIMIZER_TYPE.lower() == "adam":
    optimizer = torch.optim.Adam(
        model.parameters(),
        lr=LR,
        weight_decay=WEIGHT_DECAY,
    )
    optimizer_calibration = torch.optim.Adam(
        model.parameters(),
        lr=LR_CALIBRATION,
        weight_decay=WEIGHT_DECAY,
    )
elif OPTIMIZER_TYPE.lower() == "sgd":
    optimizer = torch.optim.SGD(
        model.parameters(),
        lr=LR,
        momentum=SGD_MOMENTUM,
        weight_decay=WEIGHT_DECAY,
    )
    optimizer_calibration = torch.optim.SGD(
        model.parameters(),
        lr=LR_CALIBRATION,
        momentum=SGD_MOMENTUM,
        weight_decay=WEIGHT_DECAY,
    )
else:
    raise ValueError(f"Unknown optimizer: {OPTIMIZER_TYPE}")

print(f"Using optimizer: {OPTIMIZER_TYPE}")


# -------------------------------------------------
# 7. Schedulers (Cosine)
# -------------------------------------------------
scheduler = None
scheduler_calibration = None

if USE_COSINE_SCHEDULER:
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(
        optimizer,
        T_max=EPOCHS,
        eta_min=1e-6,
    )
    print("Using CosineAnnealingLR (main)")


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

    pred_lbl = pred_cls_btC[idx, gt_ts].argmax(dim=-1)
    gt_lbl = gt_cls_idx[idx, gt_ts].long()

    time_ok = (pred_ts - gt_ts).abs() <= tolerance
    return ((pred_lbl == gt_lbl) & time_ok).float().mean(), (pred_lbl == gt_lbl).float().mean()


def _timestamp_errors(conf_logits: torch.Tensor, gt_keyword: torch.Tensor):
    gt_ts = gt_keyword.argmax(dim=-1)
    pred_ts = conf_logits.argmax(dim=-1)
    dt = (pred_ts - gt_ts).float()
    return dt.abs().mean(), dt.mean()


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

    if desc is None:
        desc = "Training" if training else "Eval"

    for batch in tqdm(dataloader, desc=desc):
        batch = move_to_device(batch, dev)
        conf_logits, cls_logits = model(batch)

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

        ts_idx = conf_logits.argmax(dim=-1)
        B = conf_logits.size(0)

        cls_logits_btC = cls_logits.permute(0, 2, 1)
        idx = torch.arange(B, device=dev)

        sel_logits = cls_logits_btC[idx, ts_idx]
        sel_targets = batch["cls_vec"][idx, ts_idx].long()

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

    if total == 0:
        raise RuntimeError("Dataloader produced zero samples.")

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
    }


# -------------------------------------------------
# 9. Output folder
# -------------------------------------------------
folder_path = f"results/kws/{date_time}"
os.makedirs(folder_path, exist_ok=True)
best_val_loss = float("inf")

# Log local output directory
wandb.run.summary["output_dir"] = folder_path


# -------------------------------------------------
# 10. Training loop (MAIN)
# -------------------------------------------------
for epoch in range(EPOCHS):
    model.train()
    train_metrics = one_epoch(model, train_dl, optimizer, device, cfg, desc="Training")

    # log LR + metrics
    cur_lr = float(optimizer.param_groups[0]["lr"])
    wandb.log({"train/lr": cur_lr}, step=epoch)
    log_metrics_wandb(train_metrics, prefix="train", step=epoch)

    print(
        f"Epoch {epoch+1}/{EPOCHS} | "
        f"Train Loss: {train_metrics['avg_loss']:.4f} | "
        f"Train Loss Conf: {train_metrics['avg_loss_conf']:.4f} | "
        f"Train Loss Cls: {train_metrics['avg_loss_cls']:.4f} | "
        f"Train Ts Acc: {train_metrics['ts_accuracy']*100:.2f}% | "
        f"Train Acc: {train_metrics['accuracy']*100:.2f}% | "
        f"Train Dt Abs Steps: {train_metrics['mean_abs_dt_steps']:.2f} | "
        f"Train Dt Signed Steps: {train_metrics['mean_signed_dt_steps']:.2f} | "
        f"Train Dt Abs ms: {train_metrics['mean_abs_dt_ms']:.2f} | "
        f"Train Dt Signed ms: {train_metrics['mean_signed_dt_ms']:.2f}"
    )

    model.eval()
    with torch.no_grad():
        val_metrics = one_epoch(model, val_dl, optimizer=None, dev=device, cfg=cfg, desc="Validation")

    log_metrics_wandb(val_metrics, prefix="val", step=epoch)

    print(
        f"Epoch {epoch+1}/{EPOCHS} | "
        f"Val Loss: {val_metrics['avg_loss']:.4f} | "
        f"Val Loss Conf: {val_metrics['avg_loss_conf']:.4f} | "
        f"Val Loss Cls: {val_metrics['avg_loss_cls']:.4f} | "
        f"Val Ts Acc: {val_metrics['ts_accuracy']*100:.2f}% | "
        f"Val Acc: {val_metrics['accuracy']*100:.2f}% | "
        f"Val Dt Abs Steps: {val_metrics['mean_abs_dt_steps']:.2f} | "
        f"Val Dt Signed Steps: {val_metrics['mean_signed_dt_steps']:.2f} | "
        f"Val Dt Abs ms: {val_metrics['mean_abs_dt_ms']:.2f} | "
        f"Val Dt Signed ms: {val_metrics['mean_signed_dt_ms']:.2f}"
    )

    # Save best model + log as artifact
    if val_metrics["avg_loss"] < best_val_loss:
        best_val_loss = val_metrics["avg_loss"]
        best_ckpt_path = os.path.join(folder_path, "best_model.pth")
        torch.save(model.state_dict(), best_ckpt_path)
        print(f"New best model saved with Val Loss: {best_val_loss:.4f}")

        wandb.run.summary["best_val_loss"] = best_val_loss
        wandb.run.summary["best_epoch"] = epoch

        artifact = wandb.Artifact(
            name="best_model_main",
            type="model",
            metadata={
                "best_val_loss": float(best_val_loss),
                "epoch": int(epoch),
                "optimizer": OPTIMIZER_TYPE,
                "lr": LR,
            },
        )
        artifact.add_file(best_ckpt_path)
        wandb.log_artifact(artifact)

    if scheduler is not None:
        scheduler.step()


# -------------------------------------------------
# 11. Test best model
# -------------------------------------------------
print("Testing best model on test set...")
best_path = os.path.join(folder_path, "best_model.pth")
model.load_state_dict(torch.load(best_path, map_location=device))

model.eval()
with torch.no_grad():
    test_metrics = one_epoch(model, test_dl, optimizer=None, dev=device, cfg=cfg, desc="Test")

# log test metrics (use a distinct step so plots don't overlap)
test_step = EPOCHS
log_metrics_wandb(test_metrics, prefix="test", step=test_step)

print(
    f"Best Model Test | "
    f"Test Loss: {test_metrics['avg_loss']:.4f} | "
    f"Test Loss Conf: {test_metrics['avg_loss_conf']:.4f} | "
    f"Test Loss Cls: {test_metrics['avg_loss_cls']:.4f} | "
    f"Test Ts Acc: {test_metrics['ts_accuracy']*100:.2f}% | "
    f"Test Acc: {test_metrics['accuracy']*100:.2f}% | "
    f"Test Dt Abs Steps: {test_metrics['mean_abs_dt_steps']:.2f} | "
    f"Test Dt Signed Steps: {test_metrics['mean_signed_dt_steps']:.2f} | "
    f"Test Dt Abs ms: {test_metrics['mean_abs_dt_ms']:.2f} | "
    f"Test Dt Signed ms: {test_metrics['mean_signed_dt_ms']:.2f}"
)


# -------------------------------------------------
# 12. Calibration phase
# -------------------------------------------------
model.calibrate()
best_val_loss = float("inf")

# (optional) define a step offset so the calibration curves don't overlap main training
calib_step_offset = EPOCHS + 10

for epoch in range(EPOCHS_CALIBRATION):
    step = calib_step_offset + epoch

    model.train()
    train_metrics = one_epoch(model, train_dl, optimizer_calibration, device, cfg, desc="Calibration Train")

    cur_lr = float(optimizer_calibration.param_groups[0]["lr"])
    wandb.log({"calib_train/lr": cur_lr}, step=step)
    log_metrics_wandb(train_metrics, prefix="calib_train", step=step)

    print(
        f"Calib Epoch {epoch+1}/{EPOCHS_CALIBRATION} | "
        f"Train Loss: {train_metrics['avg_loss']:.4f} | "
        f"Train Loss Conf: {train_metrics['avg_loss_conf']:.4f} | "
        f"Train Loss Cls: {train_metrics['avg_loss_cls']:.4f} | "
        f"Train Ts Acc: {train_metrics['ts_accuracy']*100:.2f}% | "
        f"Train Acc: {train_metrics['accuracy']*100:.2f}% | "
        f"Train Dt Abs Steps: {train_metrics['mean_abs_dt_steps']:.2f} | "
        f"Train Dt Signed Steps: {train_metrics['mean_signed_dt_steps']:.2f} | "
        f"Train Dt Abs ms: {train_metrics['mean_abs_dt_ms']:.2f} | "
        f"Train Dt Signed ms: {train_metrics['mean_signed_dt_ms']:.2f}"
    )

    model.eval()
    with torch.no_grad():
        val_metrics = one_epoch(model, val_dl, optimizer=None, dev=device, cfg=cfg, desc="Calibration Val")

    log_metrics_wandb(val_metrics, prefix="calib_val", step=step)

    print(
        f"Calib Epoch {epoch+1}/{EPOCHS_CALIBRATION} | "
        f"Val Loss: {val_metrics['avg_loss']:.4f} | "
        f"Val Loss Conf: {val_metrics['avg_loss_conf']:.4f} | "
        f"Val Loss Cls: {val_metrics['avg_loss_cls']:.4f} | "
        f"Val Ts Acc: {val_metrics['ts_accuracy']*100:.2f}% | "
        f"Val Acc: {val_metrics['accuracy']*100:.2f}% | "
        f"Val Dt Abs Steps: {val_metrics['mean_abs_dt_steps']:.2f} | "
        f"Val Dt Signed Steps: {val_metrics['mean_signed_dt_steps']:.2f} | "
        f"Val Dt Abs ms: {val_metrics['mean_abs_dt_ms']:.2f} | "
        f"Val Dt Signed ms: {val_metrics['mean_signed_dt_ms']:.2f}"
    )

    if val_metrics["avg_loss"] < best_val_loss:
        best_val_loss = val_metrics["avg_loss"]
        best_calib_ckpt_path = os.path.join(folder_path, "best_model_calibration.pth")
        torch.save(model.state_dict(), best_calib_ckpt_path)
        print(f"New best calibrated model saved with Val Loss: {best_val_loss:.4f}")

        wandb.run.summary["best_calib_val_loss"] = float(best_val_loss)
        wandb.run.summary["best_calib_epoch"] = int(epoch)

        artifact = wandb.Artifact(
            name="best_model_calibrated",
            type="model",
            metadata={
                "best_calib_val_loss": float(best_val_loss),
                "epoch": int(epoch),
                "optimizer": OPTIMIZER_TYPE,
                "lr_calibration": LR_CALIBRATION,
            },
        )
        artifact.add_file(best_calib_ckpt_path)
        wandb.log_artifact(artifact)

    if scheduler_calibration is not None:
        scheduler_calibration.step()


# -------------------------------------------------
# 13. Test best calibrated model
# -------------------------------------------------
print("Testing best calibrated model on test set...")
best_calib_path = os.path.join(folder_path, "best_model_calibration.pth")
model.load_state_dict(torch.load(best_calib_path, map_location=device))

model.eval()
with torch.no_grad():
    test_metrics = one_epoch(model, test_dl, optimizer=None, dev=device, cfg=cfg, desc="Test (Calibrated)")

calib_test_step = calib_step_offset + EPOCHS_CALIBRATION + 1
log_metrics_wandb(test_metrics, prefix="test_calibrated", step=calib_test_step)

print(
    f"Best Calibrated Model Test | "
    f"Test Loss: {test_metrics['avg_loss']:.4f} | "
    f"Test Loss Conf: {test_metrics['avg_loss_conf']:.4f} | "
    f"Test Loss Cls: {test_metrics['avg_loss_cls']:.4f} | "
    f"Test Ts Acc: {test_metrics['ts_accuracy']*100:.2f}% | "
    f"Test Acc: {test_metrics['accuracy']*100:.2f}% | "
    f"Test Dt Abs Steps: {test_metrics['mean_abs_dt_steps']:.2f} | "
    f"Test Dt Signed Steps: {test_metrics['mean_signed_dt_steps']:.2f} | "
    f"Test Dt Abs ms: {test_metrics['mean_abs_dt_ms']:.2f} | "
    f"Test Dt Signed ms: {test_metrics['mean_signed_dt_ms']:.2f}"
)


# -------------------------------------------------
# 14. Quantize + final test
# -------------------------------------------------
model.quantize()

model.eval()
with torch.no_grad():
    test_metrics = one_epoch(model, test_dl, optimizer=None, dev=device, cfg=cfg, desc="Test (Quantized)")

quant_step = calib_test_step + 1
log_metrics_wandb(test_metrics, prefix="test_quantized", step=quant_step)

print(
    f"Final Test after Quantization | "
    f"Test Loss: {test_metrics['avg_loss']:.4f} | "
    f"Test Loss Conf: {test_metrics['avg_loss_conf']:.4f} | "
    f"Test Loss Cls: {test_metrics['avg_loss_cls']:.4f} | "
    f"Test Ts Acc: {test_metrics['ts_accuracy']*100:.2f}% | "
    f"Test Acc: {test_metrics['accuracy']*100:.2f}% | "
    f"Test Dt Abs Steps: {test_metrics['mean_abs_dt_steps']:.2f} | "
    f"Test Dt Signed Steps: {test_metrics['mean_signed_dt_steps']:.2f} | "
    f"Test Dt Abs ms: {test_metrics['mean_abs_dt_ms']:.2f} | "
    f"Test Dt Signed ms: {test_metrics['mean_signed_dt_ms']:.2f}"
)

wandb.finish()
