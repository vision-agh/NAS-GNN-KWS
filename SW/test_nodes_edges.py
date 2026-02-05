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



from typing import Dict, List
import torch
from tqdm import tqdm

@torch.no_grad()
def dataset_event_window_and_edges_per_event_stats(
    dataloader,
    window_s: float = 0.01,
    desc: str = "Dataset stats",
) -> Dict[str, float]:
    """
    Computes dataset-wide:
      (A) Events per time window (10ms by default):
          avg, std, max over all windows across the split.
      (B) Edges per event:
          avg, max over samples, where edges_per_event = E / N.
          Also returns global_edges_per_event = sum(E)/sum(N).

    Assumptions:
      - batch['pos'][:,0] is time in seconds (float)
      - batch['batch'] maps each node/event to sample id within the batch
      - nodes for each sample are contiguous in the concatenated tensors
      - edges are intra-sample (still masked safely by node index ranges)
    """

    all_events_per_win: List[int] = []

    edges_per_event_list: List[float] = []
    total_edges = 0
    total_events = 0

    for batch in tqdm(dataloader, desc=desc):
        pos = batch["pos"]          # [N, ...], pos[:,0] = t (seconds)
        bvec = batch["batch"]       # [N]
        edge_index = batch["edge_index"]

        # edge_index -> u, v as 1D int64
        if edge_index.dim() != 2:
            raise ValueError(f"edge_index must be 2D, got shape {tuple(edge_index.shape)}")

        if edge_index.shape[0] == 2:
            # [2, E]
            u = edge_index[0].to(torch.int64)
            v = edge_index[1].to(torch.int64)
        elif edge_index.shape[1] == 2:
            # [E, 2]
            u = edge_index[:, 0].to(torch.int64)
            v = edge_index[:, 1].to(torch.int64)
        else:
            raise ValueError(f"Unrecognized edge_index shape {tuple(edge_index.shape)} (expected [2,E] or [E,2])")

        # contiguous node ranges per sample in this batch
        counts = torch.bincount(bvec.to(torch.int64))
        B = int((counts > 0).sum().item())
        counts = counts[:B]

        starts = torch.zeros(B, dtype=torch.int64)
        starts[1:] = torch.cumsum(counts, dim=0)[:-1]
        ends = starts + counts

        # Per-sample processing
        for i in range(B):
            s = int(starts[i].item())
            e = int(ends[i].item())
            n = e - s
            if n <= 0:
                continue

            # ---- (A) events per window
            t = pos[s:e, 0].to(torch.float64)
            t_rel = t - t.min()
            win = torch.floor(t_rel / window_s).to(torch.int64)  # [n]
            nwin = int(win.max().item()) + 1
            ev_counts = torch.bincount(win, minlength=nwin)
            all_events_per_win.extend(ev_counts.tolist())

            # ---- (B) edges per event (E / N) per sample
            emask = (u >= s) & (u < e) & (v >= s) & (v < e)
            E = int(emask.sum().item())
            N = n

            total_edges += E
            total_events += N

            edges_per_event_list.append(float(E) / float(N))

    if len(all_events_per_win) == 0:
        raise RuntimeError("No windows found (dataset empty or pos empty).")
    if len(edges_per_event_list) == 0:
        raise RuntimeError("No samples found (dataset empty).")

    ev = torch.tensor(all_events_per_win, dtype=torch.float64)
    epe = torch.tensor(edges_per_event_list, dtype=torch.float64)

    out = {
        "window_s": float(window_s),

        # Events per window (over all windows)
        "events_windows": int(ev.numel()),
        "events_per_win_avg": float(ev.mean().item()),
        "events_per_win_std": float(ev.std(unbiased=False).item()),
        "events_per_win_max": int(ev.max().item()),

        # Edges per event (over samples)
        "samples": int(epe.numel()),
        "edges_per_event_avg": float(epe.mean().item()),
        "edges_per_event_max": float(epe.max().item()),
        "edges_per_event_global": float(total_edges) / float(max(total_events, 1)),

        # optional raw totals (handy sanity check)
        "total_edges": int(total_edges),
        "total_events": int(total_events),
    }
    return out


def print_dataset_stats(split: str, s: Dict[str, float]):
    print(
        f"[{split}] Dataset stats:\n"
        f"  Events per 10ms window (window={s['window_s']:.5f}s): "
        f"avg={s['events_per_win_avg']:.3f}, std={s['events_per_win_std']:.3f}, "
        f"max={s['events_per_win_max']} (#windows={s['events_windows']})\n"
        f"  Edges per event (E/N per sample): "
        f"avg={s['edges_per_event_avg']:.6f}, max={s['edges_per_event_max']:.6f}, "
        f"global=sum(E)/sum(N)={s['edges_per_event_global']:.6f}\n"
        f"  Totals: edges={s['total_edges']} | events={s['total_events']} | samples={s['samples']}"
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

    # NEW: optionally limit per-class printout
    parser.add_argument("--per_class_topk", type=int, default=0,
                        help="If >0, print only top-K classes by support in per-class table (default=0 prints all).")

    args = parser.parse_args()

    set_seed(args.seed)

    run_dir = Path(args.run_dir)
    if not run_dir.exists():
        raise FileNotFoundError(f"run_dir not found: {run_dir}")

    # ---- Load config
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

    # ---- Dataset-wide event/edge density stats in 10ms windows
    stats = dataset_event_window_and_edges_per_event_stats(
        dl, window_s=0.01, desc=f"Dataset stats ({args.split})"
    )
    print_dataset_stats(args.split, stats)



if __name__ == "__main__":
    main()
