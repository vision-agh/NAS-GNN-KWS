import yaml
import glob
import random
import matplotlib.pyplot as plt
from omegaconf import OmegaConf
from dataset.nas import SpikingDS

files = glob.glob(
    '/home/imperator/Datasets/NAS_GSC/dataset/verification/*'
)
random.shuffle(files)

cfg = OmegaConf.load("configs/dataset.yaml")
ds = SpikingDS(files, cfg)

for data in ds:
    edge, pos = data['edge_index'], data['pos']
    print("Edges:", edge.shape)
    print("Pos:", pos.shape)
    plt.scatter(pos[:, 0].numpy(), pos[:, 1].numpy(), s=0.1)
    plt.show()