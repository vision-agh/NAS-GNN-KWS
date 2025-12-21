import yaml
import glob
import random
import matplotlib.pyplot as plt
from dataset.nas import SpikingDS
from pathlib import Path
from configs.build_config import build_config

vis_edges = True

files = glob.glob(
    f"{Path.home()}/Datasets/NAS_GSC/dataset_aedat/*/*"
)
cfg = build_config()
print(cfg)

ds = SpikingDS(files, cfg)

for data in ds:
    edge_index, pos, y, file = data['edge_index'], data['pos'], data['y'], data['file']
    times = pos[:, 0].cpu().numpy()
    channels = pos[:, 1].cpu().numpy()

    print("Edges:", edge_index.shape)
    print("Pos:", pos.shape)
    print("Y:", y)
    print("File:", file)
    fig, ax = plt.subplots(figsize=(10, 6))

    plt.scatter(pos[:, 0].numpy(), pos[:, 1].numpy(), s=3)
    edges = edge_index.cpu().numpy()  # shape (E, 2)

    if vis_edges == True:
        for src, dst in edges:
            t1, c1 = times[src], channels[src]
            t2, c2 = times[dst], channels[dst]

            # skip self-loop lines (but you can enable)
            if src == dst:
                continue

            ax.plot([t1, t2], [c1, c2], linewidth=0.4, alpha=0.4, color='red')
    plt.show()