import argparse
import glob
import random
from pathlib import Path
from typing import Dict, List

import numpy as np
import torch
from torch.utils.data import DataLoader
from tqdm import tqdm
from omegaconf import OmegaConf

from dataset.nas import SpikingDS
from utils.collate_fn import collate_fn
from models.networks.kws import KWS

from configs.build_config import build_config


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
# Stats helpers
# -------------------------
def _safe_stats(x: torch.Tensor) -> Dict[str, float]:
    """Return mean/std/min/max and p50/p90/p99 for a 1D float tensor."""
    if x.numel() == 0:
        return dict(
            mean=float("nan"),
            std=float("nan"),
            min=float("nan"),
            max=float("nan"),
            p50=float("nan"),
            p90=float("nan"),
            p99=float("nan"),
        )
    x = x.to(torch.float64).flatten()
    q = torch.quantile(x, torch.tensor([0.50, 0.90, 0.99], device=x.device, dtype=x.dtype))
    return {
        "mean": float(x.mean().item()),
        "std": float(x.std(unbiased=False).item()),
        "min": float(x.min().item()),
        "max": float(x.max().item()),
        "p50": float(q[0].item()),
        "p90": float(q[1].item()),
        "p99": float(q[2].item()),
    }


@torch.no_grad()
def dataset_event_window_and_graph_stats(
    dataloader,
    window_s: float = 0.01,
    desc: str = "Dataset stats",
) -> Dict[str, float]:
    """
    Computes dataset-wide stats for an event-graph dataset.

    Assumptions:
      - batch['pos'][:,0] is time in seconds (float)
      - batch['batch'] maps each node/event to sample id within the batch
      - nodes for each sample are contiguous in the concatenated tensors
      - edges are intra-sample (we still mask safely by node index ranges)

    Outputs:
      - Events per time window: mean/std/max over all windows across split
      - Duration (per sample): mean/std/min/max + p50/p90/p99
      - Events/sample: mean/std/min/max + p50/p90/p99
      - Events/sec per sample: mean/std/min/max + p50/p90/p99
      - Global events/sec: sum(events)/sum(duration)
      - Edges/event per sample: mean/std/max + global sum(E)/sum(N)
      - Edge density per sample: E/(N*(N-1)) (directed) mean/std/max
    """

    # (A) events per time window across all samples/windows
    all_events_per_win: List[int] = []

    # Per-sample scalars
    durations_s: List[float] = []
    events_per_sample: List[int] = []
    events_per_sec_per_sample: List[float] = []

    # (B) edges per event (E/N) per sample
    edges_per_event_list: List[float] = []

    # (C) edge density per sample: E / (N*(N-1))  (directed)
    edge_density_list: List[float] = []

    total_edges = 0
    total_events = 0
    total_duration = 0.0

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
            raise ValueError(
                f"Unrecognized edge_index shape {tuple(edge_index.shape)} "
                f"(expected [2,E] or [E,2])"
            )

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

            t = pos[s:e, 0].to(torch.float64)

            # ----- duration (seconds)
            tmin = float(t.min().item())
            tmax = float(t.max().item())
            dur = max(0.0, tmax - tmin)
            durations_s.append(dur)
            total_duration += dur

            # ----- events/sample
            events_per_sample.append(n)
            total_events += n

            # ----- events/sec per sample
            denom = dur if dur > 0.0 else 1e-12  # avoid inf; flags degenerate timestamps
            events_per_sec_per_sample.append(float(n) / denom)

            # ----- (A) events per window for this sample
            t_rel = t - t.min()
            win = torch.floor(t_rel / window_s).to(torch.int64)  # [n]
            nwin = int(win.max().item()) + 1
            ev_counts = torch.bincount(win, minlength=nwin)
            all_events_per_win.extend(ev_counts.tolist())

            # ----- edges in this sample
            emask = (u >= s) & (u < e) & (v >= s) & (v < e)
            E = int(emask.sum().item())
            total_edges += E

            # ----- (B) edges per event
            edges_per_event_list.append(float(E) / float(n))

            # ----- (C) edge density per sample (directed)
            denom_edges = n * (n - 1)
            edge_density_list.append(float(E) / float(denom_edges) if denom_edges > 0 else 0.0)

    if len(all_events_per_win) == 0:
        raise RuntimeError("No windows found (dataset empty or pos empty).")
    if len(events_per_sample) == 0:
        raise RuntimeError("No samples found (dataset empty).")

    ev_win = torch.tensor(all_events_per_win, dtype=torch.float64)
    dur_t = torch.tensor(durations_s, dtype=torch.float64)
    eps_t = torch.tensor(events_per_sec_per_sample, dtype=torch.float64)
    nps_t = torch.tensor(events_per_sample, dtype=torch.float64)
    epe_t = torch.tensor(edges_per_event_list, dtype=torch.float64)
    edens_t = torch.tensor(edge_density_list, dtype=torch.float64)

    dur_stats = _safe_stats(dur_t)
    eps_stats = _safe_stats(eps_t)
    nps_stats = _safe_stats(nps_t)
    epe_stats = _safe_stats(epe_t)
    edens_stats = _safe_stats(edens_t)

    out = {
        "window_s": float(window_s),

        # Events per window (over all windows)
        "events_windows": int(ev_win.numel()),
        "events_per_win_avg": float(ev_win.mean().item()),
        "events_per_win_std": float(ev_win.std(unbiased=False).item()),
        "events_per_win_max": int(ev_win.max().item()),

        # Totals
        "samples": int(nps_t.numel()),
        "total_events": int(total_events),
        "total_edges": int(total_edges),
        "total_duration_s": float(total_duration),

        # Duration stats
        "duration_mean_s": dur_stats["mean"],
        "duration_std_s": dur_stats["std"],
        "duration_min_s": dur_stats["min"],
        "duration_max_s": dur_stats["max"],
        "duration_p50_s": dur_stats["p50"],
        "duration_p90_s": dur_stats["p90"],
        "duration_p99_s": dur_stats["p99"],

        # Events/sample stats
        "events_per_sample_mean": nps_stats["mean"],
        "events_per_sample_std": nps_stats["std"],
        "events_per_sample_min": nps_stats["min"],
        "events_per_sample_max": nps_stats["max"],
        "events_per_sample_p50": nps_stats["p50"],
        "events_per_sample_p90": nps_stats["p90"],
        "events_per_sample_p99": nps_stats["p99"],

        # Events/sec per sample stats + global
        "events_per_sec_mean": eps_stats["mean"],
        "events_per_sec_std": eps_stats["std"],
        "events_per_sec_min": eps_stats["min"],
        "events_per_sec_max": eps_stats["max"],
        "events_per_sec_p50": eps_stats["p50"],
        "events_per_sec_p90": eps_stats["p90"],
        "events_per_sec_p99": eps_stats["p99"],
        "events_per_sec_global": float(total_events) / max(float(total_duration), 1e-12),

        # Graph stats: edges per event
        "edges_per_event_avg": epe_stats["mean"],
        "edges_per_event_std": epe_stats["std"],
        "edges_per_event_max": epe_stats["max"],
        "edges_per_event_global": float(total_edges) / float(max(total_events, 1)),

        # Graph stats: edge density
        "edge_density_avg": edens_stats["mean"],
        "edge_density_std": edens_stats["std"],
        "edge_density_max": edens_stats["max"],
    }
    return out


def print_dataset_stats(split: str, s: Dict[str, float]):
    print(
        f"[{split}] Dataset stats:\n"
        f"  Events per window (window={s['window_s']:.5f}s): "
        f"avg={s['events_per_win_avg']:.3f}, std={s['events_per_win_std']:.3f}, "
        f"max={s['events_per_win_max']} (#windows={s['events_windows']})\n"
        f"  Sample duration [s]: "
        f"mean={s['duration_mean_s']:.6f}, std={s['duration_std_s']:.6f}, "
        f"min={s['duration_min_s']:.6f}, max={s['duration_max_s']:.6f} "
        f"(p50={s['duration_p50_s']:.6f}, p90={s['duration_p90_s']:.6f}, p99={s['duration_p99_s']:.6f})\n"
        f"  Events/sample: "
        f"mean={s['events_per_sample_mean']:.3f}, std={s['events_per_sample_std']:.3f}, "
        f"min={s['events_per_sample_min']:.0f}, max={s['events_per_sample_max']:.0f} "
        f"(p50={s['events_per_sample_p50']:.0f}, p90={s['events_per_sample_p90']:.0f}, p99={s['events_per_sample_p99']:.0f})\n"
        f"  Events/sec (per-sample): "
        f"mean={s['events_per_sec_mean']:.3f}, std={s['events_per_sec_std']:.3f}, "
        f"min={s['events_per_sec_min']:.3f}, max={s['events_per_sec_max']:.3f} "
        f"(p50={s['events_per_sec_p50']:.3f}, p90={s['events_per_sec_p90']:.3f}, p99={s['events_per_sec_p99']:.3f})\n"
        f"  Events/sec (global sum(events)/sum(duration)): {s['events_per_sec_global']:.3f}\n"
        f"  Edges per event (E/N per sample): "
        f"avg={s['edges_per_event_avg']:.6f}, std={s['edges_per_event_std']:.6f}, "
        f"max={s['edges_per_event_max']:.6f}, global=sum(E)/sum(N)={s['edges_per_event_global']:.6f}\n"
        f"  Edge density (directed) per sample E/(N*(N-1)): "
        f"avg={s['edge_density_avg']:.6e}, std={s['edge_density_std']:.6e}, "
        f"max={s['edge_density_max']:.6e}\n"
        f"  Totals: samples={s['samples']} | events={s['total_events']} | "
        f"edges={s['total_edges']} | duration_s={s['total_duration_s']:.6f}"
    )


# -------------------------
# Main
# -------------------------
def main():
    parser = argparse.ArgumentParser("KWS test-only (no wandb, no saving)")
    # parser.add_argument(
    #     "--run_dir",
    #     type=str,
    #     required=True,
    #     help="Path to the run folder that contains config.yaml and checkpoints/",
    # )
    parser.add_argument(
        "--split",
        type=str,
        default="test",
        choices=["test", "val", "train"],
        help="Which split to evaluate.",
    )
    parser.add_argument("--batch_size", type=int, default=16)
    parser.add_argument("--num_workers", type=int, default=8)
    parser.add_argument("--pin_memory", action="store_true")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--run_dir", type=str, required=True,
                        help="Path to the run folder that contains config.yaml and checkpoints/")

    # kept from your script (not used in stats, but leaving as-is)
    parser.add_argument(
        "--per_class_topk",
        type=int,
        default=0,
        help="If >0, print only top-K classes by support in per-class table (default=0 prints all).",
    )

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

    cfg = build_config()

    print("Configuration:")
    print(OmegaConf.to_yaml(cfg))

    # ---- dataset root
    dataset_root = Path.home() / "Datasets" / "NAS_GSC" / "dataset_aedat_w_delays_128ch"
    train_files, val_files, test_files = build_splits(dataset_root)
    print(f"Split sizes | Train: {len(train_files)} | Val: {len(val_files)} | Test: {len(test_files)}")

    if args.split == "train":
        files = train_files
    elif args.split == "val":
        files = val_files
    else:
        files = test_files
    
    # combine all splits for stats
    files = train_files + val_files + test_files

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

    # ---- Dataset-wide stats
    stats = dataset_event_window_and_graph_stats(
        dl, window_s=0.01, desc=f"Dataset stats ({args.split})"
    )
    print_dataset_stats(args.split, stats)


if __name__ == "__main__":
    main()
