"""
Checks whether the torch.unique(edge_index[:, 0], return_inverse=True) call in
MyPointNetConv.message_* (models/layers/my_pointnet.py) is redundant, i.e.
whether destination node ids already form a dense 0..N-1 range so that
`indices` == edge_index[:, 0] and unique_positions.size(0) == N (num nodes).

If true for every sample/layer, the unique() call (an O(E log E) sort done
4x per forward, 4x per backward) can be replaced by scatter_reduce directly
indexed by edge_index[:, 0].

Does not modify any model/dataset code - read only.
Run from repo root: python benchmark/check_unique_redundant.py
"""
import glob
from pathlib import Path

import torch

from dataset.nas import SpikingDS
from configs.build_config import build_config

N_SAMPLES = 50


def get_files():
    dataset_root = Path.home() / "Dataset" / "gsc_v2_32p_ok"
    files = glob.glob(str(dataset_root / "*" / "*"))
    files = [f for f in files if Path(f).is_file() and not f.endswith(".txt")]
    return files


def main():
    cfg = build_config()
    files = get_files()
    ds = SpikingDS(files, cfg)

    n_checked = 0
    n_dense = 0
    n_isolated_nodes_total = 0

    idxs = torch.randperm(len(ds))[:N_SAMPLES].tolist()
    for i in idxs:
        item = ds[i]
        if item is None:
            continue
        edge_index = item["edge_index"]
        num_nodes = item["x"].shape[0]

        dst = edge_index[:, 0]
        unique_positions, indices = torch.unique(dst, return_inverse=True)

        is_dense = (
            unique_positions.numel() == num_nodes
            and torch.equal(unique_positions, torch.arange(num_nodes, dtype=unique_positions.dtype))
            and torch.equal(indices, dst)
        )

        n_checked += 1
        n_dense += int(is_dense)
        n_isolated = num_nodes - unique_positions.numel()
        n_isolated_nodes_total += max(n_isolated, 0)

        if not is_dense:
            print(f"sample {i}: NOT dense | num_nodes={num_nodes} | "
                  f"unique_dst={unique_positions.numel()} | isolated_nodes={n_isolated}")

    print(f"\nChecked {n_checked} samples")
    print(f"Dense (unique() is redundant): {n_dense}/{n_checked}")
    print(f"Total isolated (no-incoming-edge) nodes seen: {n_isolated_nodes_total}")


if __name__ == "__main__":
    main()
