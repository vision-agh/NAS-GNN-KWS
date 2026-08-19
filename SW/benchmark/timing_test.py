"""
Simple timing breakdown for the training pipeline.
Run from repo root: python benchmark/timing_test.py

Measures, in order:
  1. Raw __getitem__ time (CPU preprocessing per sample) - single process
  2. DataLoader throughput for a few different num_workers values
  3. Model forward time (GPU)
  4. Model forward+backward time (GPU)

No training config is modified - this only reads files and runs forward passes.
"""
import glob
import time
import argparse
from pathlib import Path

import numpy as np
import torch
from torch.utils.data import DataLoader

from dataset.nas import SpikingDS
from configs.build_config import build_config
from utils.collate_fn import collate_fn
from models.networks.kws import KWS

BATCH_SIZE = 2
N_SAMPLES_GETITEM = 30      # samples for raw __getitem__ timing
N_BATCHES_LOADER = 20       # batches per num_workers setting
N_BATCHES_MODEL = 20        # batches for forward/backward timing
WORKER_OPTIONS = [0, 2, 4, 8, 16]


def get_files():
    dataset_root = Path.home() / "Dataset" / "gsc_v2_32p_ok"
    files = glob.glob(str(dataset_root / "*" / "*"))
    files = [f for f in files if Path(f).is_file() and not f.endswith(".txt")]
    return files


def time_block(label, fn, n_repeats):
    # warmup
    fn()
    torch.cuda.synchronize() if torch.cuda.is_available() else None
    start = time.perf_counter()
    for _ in range(n_repeats):
        fn()
    torch.cuda.synchronize() if torch.cuda.is_available() else None
    elapsed = time.perf_counter() - start
    per_call = elapsed / n_repeats
    print(f"{label:45s} | total {elapsed:7.3f}s | per-call {per_call*1000:8.2f} ms")
    return per_call


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset_cfg", type=str, default="configs/dataset.yaml")
    parser.add_argument("--nas_cfg", type=str, default="configs/nas.yaml")
    parser.add_argument("--model_cfg", type=str, default="configs/kws.yaml")
    args = parser.parse_args()

    cfg = build_config(
        dataset_cfg_path=args.dataset_cfg,
        nas_cfg_path=args.nas_cfg,
        model_cfg_path=args.model_cfg,
    )

    files = get_files()
    print(f"Found {len(files)} files")

    ds = SpikingDS(files, cfg)

    # -----------------------------------------------------------
    # 1. Raw __getitem__ timing (single process, no DataLoader)
    # -----------------------------------------------------------
    print("\n=== 1. Raw __getitem__ (CPU preprocessing, single process) ===")
    idxs = np.random.choice(len(ds), size=N_SAMPLES_GETITEM, replace=False)
    times = []
    for i in idxs:
        t0 = time.perf_counter()
        _ = ds[i]
        times.append(time.perf_counter() - t0)
    times = np.array(times)
    print(f"mean {times.mean()*1000:.2f} ms | median {np.median(times)*1000:.2f} ms | "
          f"min {times.min()*1000:.2f} ms | max {times.max()*1000:.2f} ms")

    # -----------------------------------------------------------
    # 2. DataLoader throughput vs num_workers
    # -----------------------------------------------------------
    print("\n=== 2. DataLoader throughput vs num_workers ===")
    for nw in WORKER_OPTIONS:
        dl = DataLoader(
            ds,
            batch_size=BATCH_SIZE,
            shuffle=True,
            num_workers=nw,
            pin_memory=True,
            persistent_workers=(nw > 0),
            collate_fn=collate_fn,
        )
        it = iter(dl)
        # warmup (fills worker pipeline)
        next(it)
        t0 = time.perf_counter()
        n = 0
        for _ in range(N_BATCHES_LOADER):
            try:
                next(it)
            except StopIteration:
                break
            n += 1
        elapsed = time.perf_counter() - t0
        del it, dl
        samples_per_sec = (n * BATCH_SIZE) / elapsed if elapsed > 0 else float("nan")
        print(f"num_workers={nw:3d} | {n} batches in {elapsed:6.2f}s | "
              f"{samples_per_sec:6.2f} samples/s | {n/elapsed:6.2f} it/s")

    # -----------------------------------------------------------
    # 3 & 4. Model forward / forward+backward timing (GPU)
    # -----------------------------------------------------------
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"\n=== 3/4. Model forward / forward+backward on {device} ===")

    model = KWS(cfg).to(device)
    optimizer = torch.optim.Adam(model.parameters(), lr=1e-3)

    dl = DataLoader(
        ds,
        batch_size=BATCH_SIZE,
        shuffle=True,
        num_workers=4,
        pin_memory=True,
        persistent_workers=True,
        collate_fn=collate_fn,
    )
    batches = []
    it = iter(dl)
    for _ in range(N_BATCHES_MODEL):
        batches.append(next(it))
    del it, dl

    print("Batch graph sizes (nodes, edges):",
          [(b["x"].shape[0], b["edge_index"].shape[0]) for b in batches])

    def move(batch):
        return {k: (v.to(device, non_blocking=True) if torch.is_tensor(v) else v) for k, v in batch.items()}

    model.train()

    def forward_only():
        with torch.no_grad():
            for b in batches:
                model(move(b))

    def forward_backward():
        n_ok = 0
        for b in batches:
            gb = move(b)
            try:
                optimizer.zero_grad(set_to_none=True)
                conf_logits, cls_logits = model(gb)
                loss = conf_logits.sum() + cls_logits.sum()  # dummy loss, just to time backward
                loss.backward()
                optimizer.step()
                n_ok += 1
            except torch.OutOfMemoryError:
                torch.cuda.empty_cache()
                print(f"  [skip OOM batch: nodes={gb['x'].shape[0]}, edges={gb['edge_index'].shape[0]}]")
        return n_ok

    time_block("Forward only (no_grad)", forward_only, 3)

    # backward pass timed separately (skips batches that OOM due to shared GPU)
    forward_backward()  # warmup
    torch.cuda.synchronize()
    t0 = time.perf_counter()
    n_ok = 0
    for _ in range(3):
        n_ok += forward_backward()
    torch.cuda.synchronize()
    elapsed = time.perf_counter() - t0
    if n_ok > 0:
        print(f"{'Forward + backward + step':45s} | total {elapsed:7.3f}s | per-call {elapsed/n_ok*1000:8.2f} ms "
              f"({n_ok} successful batches)")
    else:
        print("Forward+backward: all batches OOM'd, no timing available")

    print("\nDone.")


if __name__ == "__main__":
    main()
