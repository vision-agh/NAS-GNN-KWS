import glob
import random
import torch
from torch.utils.data import DataLoader
from omegaconf import OmegaConf
from tqdm import tqdm

from dataset.nas import SpikingDS
from models.networks.recognition import Recognition
from utils.collate_fn import collate_fn

from utils.visualise_graph import visualize_events_and_graph

# -------------------------------------------------
# 1. Reproducibility
# -------------------------------------------------
SEED = 42
random.seed(SEED)
torch.manual_seed(SEED)

# -------------------------------------------------
# 2. Files & split
# -------------------------------------------------
files = glob.glob(
    '/home/imperator/Datasets/NAS_GSC/dataset/verification/*'
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
    batch_size=1,
    shuffle=True,
    num_workers=1,
    pin_memory=True,
    persistent_workers=True,
    collate_fn=collate_fn
)

test_dl = DataLoader(
    test_ds,
    batch_size=1,
    shuffle=False,
    num_workers=1,
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
optimizer = torch.optim.Adam(model.parameters(), lr=1e-3)

# -------------------------------------------------
# 6. Helper: move batch to device
# -------------------------------------------------
def move_to_device(batch):
    return {
        k: v.to(device, non_blocking=True)
        if torch.is_tensor(v) else v
        for k, v in batch.items()
    }

# -------------------------------------------------
# 7. Sanity check (DO THIS ONCE)
# -------------------------------------------------

batch = next(iter(train_dl))
# visualize_events_and_graph(batch['pos'], batch['edge_index'])
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
# 8. Training loop
# -------------------------------------------------
EPOCHS = 10

for epoch in range(EPOCHS):
    # -------------------------
    # Train
    # -------------------------
    model.train()
    total_loss = 0.0
    correct = 0
    total = 0

    for batch in tqdm(train_dl):
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
    # Evaluate
    # -------------------------
    model.eval()
    correct = 0
    total = 0

    with torch.no_grad():
        for batch in tqdm(test_dl):
            batch = move_to_device(batch)

            logits = model(batch)

            preds = logits.argmax(dim=1)
            correct += (preds == batch["y"]).sum().item()
            total += batch["y"].size(0)

    test_acc = correct / total

    print(
        f"Epoch {epoch:02d} | "
        f"Train loss: {train_loss:.4f} | "
        f"Train acc: {train_acc:.3f} | "
        f"Test acc: {test_acc:.3f}"
    )

# -------------------------------------------------
# 9. Save model
# -------------------------------------------------
torch.save(model.state_dict(), "recognition_baseline.pth")
print("Model saved.")
