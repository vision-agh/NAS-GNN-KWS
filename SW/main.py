import glob
import random
import torch
from torch.utils.data import DataLoader
from omegaconf import OmegaConf
from tqdm import tqdm

from dataset.nas import SpikingDS
from models.networks.recognition import Recognition
from utils.collate_fn import collate_fn

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
    '/home/lsriw/Datasets/NAS_GSC/dataset/verification/*'
)
random.shuffle(files)

split_ratio = 0.8
n_train = int(len(files) * split_ratio)

train_files = files[:n_train]
test_files  = files[n_train:]

print(f"Train files: {len(train_files)} | Test files: {len(test_files)}")

# -------------------------------------------------
# 3. Dataset
# -------------------------------------------------
cfg_dataset = OmegaConf.load("configs/dataset.yaml")
cfg_model   = OmegaConf.load("configs/model.yaml")

train_ds = SpikingDS(train_files, cfg_dataset)
test_ds  = SpikingDS(test_files, cfg_dataset)

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

# -------------------------------------------------
# 5. Device & model
# -------------------------------------------------
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print("Using device:", device)

model = Recognition(cfg_model).to(device)

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

# -------------------------------------------------
# 9. Sanity check (DO THIS ONCE)
# -------------------------------------------------
batch = next(iter(train_dl))
batch = move_to_device(batch)

print("x:", batch["x"].shape)
print("pos:", batch["pos"].shape)
print("edge_index:", batch["edge_index"].shape)
print("batch vec:", batch["batch"].shape)
print("labels:", batch["y"].shape)

with torch.no_grad():
    out = model(batch)
print("logits:", out.shape)

# -------------------------------------------------
# 10. Training loop
# -------------------------------------------------
for epoch in range(EPOCHS):
    # -------------------------
    # Train
    # -------------------------
    model.train()
    total_loss = 0.0
    correct = 0
    total = 0

    for batch in tqdm(train_dl, desc=f"Train {epoch:02d}"):
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

    train_loss = total_loss / total
    train_acc  = correct / total

    # -------------------------
    # Scheduler step
    # -------------------------
    if scheduler is not None:
        scheduler.step()

    # -------------------------
    # Evaluate
    # -------------------------
    model.eval()
    correct = 0
    total = 0

    with torch.no_grad():
        for batch in tqdm(test_dl, desc=f"Test  {epoch:02d}"):
            batch = move_to_device(batch)
            logits = model(batch)
            preds = logits.argmax(dim=1)
            correct += (preds == batch["y"]).sum().item()
            total += batch["y"].size(0)

    test_acc = correct / total
    current_lr = optimizer.param_groups[0]["lr"]

    print(
        f"Epoch {epoch:02d} | "
        f"LR {current_lr:.2e} | "
        f"Train loss: {train_loss:.4f} | "
        f"Train acc: {train_acc:.3f} | "
        f"Test acc: {test_acc:.3f}"
    )

# -------------------------------------------------
# 11. Save model
# -------------------------------------------------
torch.save(model.state_dict(), "recognition_baseline.pth")
print("Model saved.")
