import glob, os
import random
import torch
import datetime
import numpy as np
from torch.utils.data import DataLoader
from tqdm import tqdm
from pathlib import Path

from dataset.nas import SpikingDS
from configs.build_config import build_config
from utils.collate_fn import collate_fn

from models.networks.recognition import Recognition

# -------------------------------------------------
# 0. Training config (CHANGE HERE)
# -------------------------------------------------
OPTIMIZER_TYPE = "adam"   # "adam" or "sgd"
LR = 1e-3
WEIGHT_DECAY = 1e-4

USE_COSINE_SCHEDULER = True
EPOCHS = 100
SGD_MOMENTUM = 0.9

# -------------------------------------------------
# 1. Reproducibility
# -------------------------------------------------
SEED = 42
random.seed(SEED)
torch.manual_seed(SEED)
torch.cuda.manual_seed_all(SEED)

# -------------------------------------------------
# 2. Files & split
# -------------------------------------------------
files = glob.glob(
    f"{Path.home()}/Datasets/NAS_GSC/dataset_aedat/*/*"
)

# Load list entries like right/xxxx.wav
testing_list = np.loadtxt(
    f"{Path.home()}/Datasets/NAS_GSC/dataset_aedat/testing_list.txt",
    dtype=str,
)
validation_list = np.loadtxt(
    f"{Path.home()}/Datasets/NAS_GSC/dataset_aedat/validation_list.txt",
    dtype=str,
)

# Normalize to a set for fast lookup
testing_set = set(testing_list)
validation_set = set(validation_list)


def file_key(path_str: str) -> str:
    """
    Returns key in form: class/file.wav
    Given full file path .../class/file.wav.aedat
    """
    p = Path(path_str)
    cls = p.parent.name  # e.g., right
    stem = p.stem       # file.wav  (first stem strips .aedat)
    return f"{cls}/{stem}"


train_files = [
    f for f in files
    if file_key(f) not in testing_set
    and file_key(f) not in validation_set
]
test_files = [
    f for f in files
    if file_key(f) in testing_set
]
val_files = [
    f for f in files
    if file_key(f) in validation_set
]

print(
    f"Train files: {len(train_files)} | "
    f"Test files: {len(test_files)} | "
    f"Validation files: {len(val_files)}"
)

# -------------------------------------------------
# 3. Dataset
# -------------------------------------------------
cfg = build_config()

train_ds = SpikingDS(train_files, cfg)
test_ds  = SpikingDS(test_files, cfg)
val_ds   = SpikingDS(val_files, cfg)

# -------------------------------------------------
# 4. DataLoaders
# -------------------------------------------------
train_dl = DataLoader(
    train_ds,
    batch_size=4,
    shuffle=True,
    num_workers=4,
    pin_memory=True,
    persistent_workers=True,
    collate_fn=collate_fn
)

test_dl = DataLoader(
    test_ds,
    batch_size=4,
    shuffle=False,
    num_workers=4,
    pin_memory=True,
    persistent_workers=True,
    collate_fn=collate_fn
)

val_dl = DataLoader(
    val_ds,
    batch_size=4,
    shuffle=False,
    num_workers=4,
    pin_memory=True,
    persistent_workers=True,
    collate_fn=collate_fn
)

# -------------------------------------------------
# 5. Device & model
# -------------------------------------------------
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print("Using device:", device)

model = Recognition(cfg.model).to(device)

criterion = torch.nn.CrossEntropyLoss()

# -------------------------------------------------
# 6. Optimizer
# -------------------------------------------------
if OPTIMIZER_TYPE.lower() == "adam":
    optimizer = torch.optim.Adam(
        model.parameters(),
        lr=LR,
        weight_decay=WEIGHT_DECAY
    )
elif OPTIMIZER_TYPE.lower() == "sgd":
    optimizer = torch.optim.SGD(
        model.parameters(),
        lr=LR,
        momentum=SGD_MOMENTUM,
        weight_decay=WEIGHT_DECAY
    )
else:
    raise ValueError(f"Unknown optimizer: {OPTIMIZER_TYPE}")

print(f"Using optimizer: {OPTIMIZER_TYPE}")

# -------------------------------------------------
# 7. Scheduler (Cosine)
# -------------------------------------------------
scheduler = None
if USE_COSINE_SCHEDULER:
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(
        optimizer,
        T_max=EPOCHS,
        eta_min=1e-6
    )
    print("Using CosineAnnealingLR")

# -------------------------------------------------
# 8. Helper: move batch to device
# -------------------------------------------------
def move_to_device(batch):
    return {
        k: v.to(device, non_blocking=True)
        if torch.is_tensor(v) else v
        for k, v in batch.items()
    }


def train_one_epoch(model, dataloader, criterion, optimizer, device):
    model.train()
    total_loss = 0.0
    correct = 0
    total = 0

    for batch in tqdm(dataloader, desc="Training"):
        batch = move_to_device(batch)

        optimizer.zero_grad()
        logits = model(batch)
        loss = criterion(logits, batch["y"])
        loss.backward()
        optimizer.step()

        total_loss += loss.item() * batch["y"].size(0)
        preds = logits.argmax(dim=1)
        correct += (preds == batch["y"]).sum().item()
        total += batch["y"].size(0)

    avg_loss = total_loss / total
    accuracy = correct / total
    return avg_loss, accuracy


def evaluate(model, dataloader, criterion, device):
    model.eval()
    total_loss = 0.0
    correct = 0
    total = 0

    with torch.no_grad():
        for batch in tqdm(dataloader, desc="Evaluating"):
            batch = move_to_device(batch)
            logits = model(batch)
            loss = criterion(logits, batch["y"])

            total_loss += loss.item() * batch["y"].size(0)
            preds = logits.argmax(dim=1)
            correct += (preds == batch["y"]).sum().item()
            total += batch["y"].size(0)

    avg_loss = total_loss / total
    accuracy = correct / total
    return avg_loss, accuracy


folder_path = f"results/recognition/{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}"
os.makedirs(folder_path, exist_ok=True)
best_val_acc = 0.0

# -------------------------------------------------
# 10. Training loop
# -------------------------------------------------
for epoch in range(1):
    # -------------------------
    # Train
    # -------------------------
    train_loss, train_acc = train_one_epoch(
        model,
        train_dl,
        criterion,
        optimizer,
        device
    )
    print(
        f"Epoch {epoch+1}/{EPOCHS} | "
        f"Train Loss: {train_loss:.4f} | "
        f"Train Acc: {train_acc*100:.2f}%"
    )

    # -------------------------
    # Validate
    # -------------------------
    val_loss, val_acc = evaluate(
        model,
        val_dl,
        criterion,
        device
    )
    print(
        f"Epoch {epoch+1}/{EPOCHS} | "
        f"Val Loss: {val_loss:.4f} | "
        f"Val Acc: {val_acc*100:.2f}%"
    )

    if val_acc > best_val_acc:
        best_val_acc = val_acc
        torch.save(
            model.state_dict(),
            os.path.join(folder_path, "best_model.pth")
        )
        print(f"New best model saved with Val Acc: {best_val_acc*100:.2f}%")

    # -------------------------
    # Step scheduler
    # -------------------------
    if scheduler is not None:
        scheduler.step()


# -------------------------------------------------
# 11. Test best model
# -------------------------------------------------
print("Testing best model on test set...")
model.load_state_dict(
    torch.load(os.path.join(folder_path, "best_model.pth"))
)
test_loss, test_acc = evaluate(
    model,
    test_dl,
    criterion,
    device
)
print(
    f"Test Loss: {test_loss:.4f} | "
    f"Test Acc: {test_acc*100:.2f}%"
)


model.calibrate()
best_val_acc = 0.0

for epoch in range(1):
    # -------------------------
    # Train
    # -------------------------
    train_loss, train_acc = train_one_epoch(
        model,
        train_dl,
        criterion,
        optimizer,
        device
    )
    print(
        f"Epoch {epoch+1}/{EPOCHS} | "
        f"Train Loss: {train_loss:.4f} | "
        f"Train Acc: {train_acc*100:.2f}%"
    )

    # -------------------------
    # Validate
    # -------------------------
    val_loss, val_acc = evaluate(
        model,
        val_dl,
        criterion,
        device
    )
    print(
        f"Epoch {epoch+1}/{EPOCHS} | "
        f"Val Loss: {val_loss:.4f} | "
        f"Val Acc: {val_acc*100:.2f}%"
    )

    if val_acc > best_val_acc:
        best_val_acc = val_acc
        torch.save(
            model.state_dict(),
            os.path.join(folder_path, "best_model_calibration.pth")
        )
        print(f"New best model saved with Val Acc: {best_val_acc*100:.2f}%")

    # -------------------------
    # Step scheduler
    # -------------------------
    if scheduler is not None:
        scheduler.step()


# -------------------------------------------------
# 11. Test best calibrated model
# -------------------------------------------------
print("Testing best calibrated model on test set...")
model.load_state_dict(
    torch.load(os.path.join(folder_path, "best_model_calibration.pth"))
)
test_loss, test_acc = evaluate(
    model,
    test_dl,
    criterion,
    device
)
print(
    f"Test Loss: {test_loss:.4f} | "
    f"Test Acc: {test_acc*100:.2f}%"
)

model.quantize()

test_loss, test_acc = evaluate(
    model,
    test_dl,
    criterion,
    device
)
print(
    f"Test Loss: {test_loss:.4f} | "
    f"Test Acc: {test_acc*100:.2f}%"
)