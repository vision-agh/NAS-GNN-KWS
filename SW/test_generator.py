import yaml
import numpy as np
import glob
import random
import matplotlib.pyplot as plt
from dataset.nas import SpikingDS
from pathlib import Path
from configs.build_config import build_config

vis_edges = False

files = glob.glob(
    f"{Path.home()}/Datasets/NAS_GSC/dataset_aedat_w_delays_parallel/zero/*"
)
cfg = build_config()
print(cfg)

ds = SpikingDS(files, cfg)

for data in ds:
    edge_index, pos, y, file = data['edge_index'], data['pos'], data['y'], data['file']
    start_time, end_time = data['start_time'], data['end_time']
    hist_smoothed = data['hist_smoothed']

    times = pos[:, 0].cpu().numpy()
    channels = pos[:, 1].cpu().numpy()

    # Plot the event scatter with edges
    print("Edges:", edge_index.shape)
    print("Pos:", pos.shape)
    print("Y:", y)
    print("File:", file)
    print("Start Time:", start_time)
    print("End Time:", end_time)
    fig, ax = plt.subplots(figsize=(10, 6))

    plt.scatter(pos[:, 0].numpy(), pos[:, 1].numpy(), s=3)
    edges = edge_index.cpu().numpy()

    if vis_edges == True:
        for src, dst in edges:
            t1, c1 = times[src], channels[src]
            t2, c2 = times[dst], channels[dst]
            if src == dst:
                continue

            ax.plot([t1, t2], [c1, c2], linewidth=0.4, alpha=0.2, color='red')
    plt.show(block=False)
    
    # Plot the smoothed histogram with active range

    plt.figure()
    plt.title(f"Smoothed Histogram: \nStart: {start_time:.2f} ms, End: {end_time:.2f} ms")
    bin_centers = np.arange(len(hist_smoothed)) * cfg.dataset.bin_width
    plt.plot(bin_centers, hist_smoothed)
    plt.axvline(start_time, color='green', linestyle='--', label='Start Time')
    plt.axvline(end_time, color='red', linestyle='--', label='End Time')
    plt.xlabel("Time (s)")
    plt.ylabel("Event Count")
    plt.legend()
    plt.show()