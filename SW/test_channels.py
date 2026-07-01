import argparse
import glob
import random
from pathlib import Path
from typing import Optional, Tuple

import numpy as np
import torch
from tqdm import tqdm
from omegaconf import OmegaConf

import matplotlib.pyplot as plt

from configs.build_config import build_config
from dataset.utils.nas_loader import nas_loader


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


# -------------------------
# Channel inference (cfg stores half-resolution channels)
# -------------------------
def infer_num_channels_from_cfg(cfg) -> int:
    """
    Config stores half-resolution channels.
    If cfg says 64, real channels can be 0..128 => 129 channels.
    Uses: C_real = 2 * n_cfg + 1
    """
    n_cfg = None
    for key in ["n_channels", "num_channels", "channels", "C"]:
        if hasattr(cfg.nas, key):
            v = int(getattr(cfg.nas, key))
            if v > 0:
                n_cfg = v
                break
    if n_cfg is None:
        return 0
    return n_cfg


def per_channel_counts(addr: np.ndarray, C: int) -> np.ndarray:
    """Counts events per channel for one sample."""
    if C <= 0:
        return np.zeros((0,), dtype=np.int64)
    if addr.size == 0:
        return np.zeros((C,), dtype=np.int64)
    return np.bincount(addr.astype(np.int64), minlength=C).astype(np.int64)


def compute_events_per_channel_stats(
    files,
    cfg,
    C: Optional[int] = None,
    max_files: int = 0,
) -> Tuple[np.ndarray, np.ndarray, np.ndarray, int]:
    """
    Returns:
      mean_counts[C], std_counts[C], total_counts[C], n_samples
    where mean/std are across samples (one sample = one file).
    """

    # Infer C if not provided: start from cfg-derived full channel count, then guard with data max.
    if C is None:
        C = infer_num_channels_from_cfg(cfg)  # e.g., cfg=64 -> 129
        # Probe a subset of files to ensure C covers data
        for f in files[: min(len(files), 200)]:
            addr, _ts = nas_loader(f, cfg.nas)
            addr = addr // 2            
            if addr.size > 0:
                C = max(C, int(addr.max()) + 1)

        if C <= 0:
            raise RuntimeError("Could not infer number of channels (cfg missing and addr empty).")

    # Online accumulation for mean/std per channel over samples
    sums = np.zeros((C,), dtype=np.float64)
    sums2 = np.zeros((C,), dtype=np.float64)
    totals = np.zeros((C,), dtype=np.int64)
    n_samples = 0

    it = files if (max_files is None or max_files <= 0) else files[:max_files]

    for f in tqdm(it, desc="Counting events/channel"):
        addr, _ts = nas_loader(f, cfg.nas)
        addr = addr // 2  # Convert to full-res channels (0..C-1)
        counts = per_channel_counts(addr, C)
        
        if counts.shape[0] != C:
            print(f"Warning: file {f} has max channel {counts.shape[0]-1} < inferred C={C}. Skipping.")
            continue

        sums += counts
        sums2 += counts.astype(np.float64) ** 2
        totals += counts
        n_samples += 1

    if n_samples == 0:
        raise RuntimeError("No samples processed.")

    mean = sums / n_samples
    # population std (unbiased=False)
    var = (sums2 / n_samples) - (mean ** 2)
    var = np.maximum(var, 0.0)
    std = np.sqrt(var)

    return mean, std, totals, n_samples


def save_csv(out_csv: Path, mean: np.ndarray, std: np.ndarray, totals: np.ndarray):
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    C = mean.shape[0]
    out = np.stack([np.arange(C), mean, std, totals.astype(np.float64)], axis=1)
    np.savetxt(out_csv, out, delimiter=",", header="channel,mean,std,total", comments="")


def save_plot(out_png: Path, mean: np.ndarray, std: np.ndarray):
    out_png.parent.mkdir(parents=True, exist_ok=True)
    x = np.arange(mean.shape[0])
    lower = mean - std
    upper = mean + std

    plt.figure(figsize=(10, 6.5))
    plt.plot(x, mean, linewidth=2)
    plt.fill_between(x, lower, upper, alpha=0.25)
    plt.xlabel("Channel")
    plt.ylabel("Avg. + std. # events per sample")
    # plt.title("Events per Channel (mean ± std across samples)")
    plt.tight_layout()
    plt.savefig(out_png, dpi=600)
    plt.close()


# -------------------------
# Main
# -------------------------
def main():
    parser = argparse.ArgumentParser("NAS per-channel event count stats + plot (mean±std over samples)")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument(
        "--dataset_root",
        type=str,
        default=str(Path.home() / "Datasets" / "NAS_GSC" / "dataset_aedat_w_delays_parallel_32ch"),
    )
    parser.add_argument(
        "--glob",
        type=str,
        default="*/*",
        help='Pattern under dataset_root, e.g. "*/*" or "stop/*"',
    )
    parser.add_argument("--max_files", type=int, default=0, help="0 = all files")
    parser.add_argument(
        "--channels",
        type=int,
        default=0,
        help="Force REAL number of channels (0 = infer as 2*cfg+1, guarded by data max).",
    )
    parser.add_argument("--topk", type=int, default=20, help="Print top-K channels by mean count")
    parser.add_argument(
        "--out_dir",
        type=str,
        default=".",
        help="Output directory for CSV and plot",
    )
    parser.add_argument(
        "--csv_name",
        type=str,
        default="events_per_channel_stats.csv",
        help="CSV filename (saved inside out_dir)",
    )
    parser.add_argument(
        "--plot_name",
        type=str,
        default="events_per_channel_mean_std.png",
        help="Plot filename (saved inside out_dir)",
    )
    args = parser.parse_args()

    set_seed(args.seed)
    cfg = build_config()

    print("Configuration:")
    print(OmegaConf.to_yaml(cfg))

    dataset_root = Path(args.dataset_root)
    files = sorted(glob.glob(str(dataset_root / args.glob)))
    files = [f for f in files if Path(f).is_file()]

    if len(files) == 0:
        raise FileNotFoundError(f"No files found under {dataset_root} with glob='{args.glob}'")

    C = args.channels if args.channels > 0 else None
    mean, std, totals, n_samples = compute_events_per_channel_stats(
        files, cfg, C=C, max_files=args.max_files
    )

    C_real = mean.shape[0]
    print(f"\nProcessed samples: {n_samples}")
    print(f"Channels (real): {C_real}")

    print(
        f"\nAcross channels (mean of per-channel means): "
        f"{mean.mean():.3f} ± {mean.std(ddof=0):.3f} events/sample/channel"
    )
    print(
        f"Total events (all channels): {int(totals.sum())} "
        f"(avg per sample: {totals.sum()/max(n_samples,1):.3f})"
    )

    topk = min(max(args.topk, 0), C_real)
    if topk > 0:
        idx = np.argsort(-mean)[:topk]
        print(f"\nTop-{topk} channels by mean events/sample:")
        print("  ch\tmean\tstd\ttotal")
        for ch in idx:
            print(f"  {ch}\t{mean[ch]:.3f}\t{std[ch]:.3f}\t{totals[ch]}")

    out_dir = Path(args.out_dir)
    out_csv = out_dir / args.csv_name
    out_png = out_dir / args.plot_name

    save_csv(out_csv, mean, std, totals)
    save_plot(out_png, mean, std)

    print(f"\nSaved CSV : {out_csv.resolve()}")
    print(f"Saved Plot: {out_png.resolve()}")


if __name__ == "__main__":
    main()
