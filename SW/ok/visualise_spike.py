import random
from pathlib import Path

import matplotlib.pyplot as plt
from pyNAVIS import *

#DATASET_DIR = Path("/home/pwz/Music/datasets/gsc_v2_32p_ok")
DATASET_DIR = Path("/home/pwz/Music/datasets/vox")

settings = MainSettings(num_channels=32, mono_stereo=0, on_off_both=1, address_size=2, timestamp_size=4, ts_tick=1)

# Own RNG instance: pyNAVIS's Plots.spikegram calls random.seed(0) internally,
# which would otherwise reset the global random module state after every plot.
rng = random.Random()


def pick_random_sample():
    classes = [d for d in DATASET_DIR.iterdir() if d.is_dir() and any(d.glob("*.aedat"))]
    if not classes:
        raise FileNotFoundError(f"No class folders with .aedat files found in {DATASET_DIR}")

    label = rng.choice(classes)
    aedat_files = list(label.glob("*.aedat"))
    file_path = rng.choice(aedat_files)
    return label.name, file_path


while True:
    label, file_path = pick_random_sample()

    spikes_info = Loaders.loadAEDAT(str(file_path), settings)

    graph_title = f"Class: {label} ({file_path.name})"
    Plots.spikegram(spikes_info, settings, graph_title=graph_title)
    plt.show()
