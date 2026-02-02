import yaml
import numpy as np
import os, glob
import random
import torch
import matplotlib.pyplot as plt
from dataset.nas import SpikingDS
from pathlib import Path
from configs.build_config import build_config
from models.networks.kws import KWS
from dataset.nas import WORDS_COMM
from omegaconf import OmegaConf

from utils.generate_outputs import gen_input_events, gen_graph_out, conv_gen_out, conv_first_gen_out, vector_out

def move_to_device(batch, dev):
    return {
        k: (v.to(dev, non_blocking=True) if torch.is_tensor(v) else v)
        for k, v in batch.items()
    }

# Prepare dataset
files = glob.glob(
    f"{Path.home()}/Datasets/NAS_GSC/dataset_aedat_w_delays_whole/*/*"    # or select class e.g. stop here
)

# shuffle files for testing
random.shuffle(files)

cfg = OmegaConf.load('runs/kws/20260127_193651_job11896010_task2_x1002c3s3b1n0/config.yaml')
OmegaConf.resolve(cfg)
print(cfg)
ds = SpikingDS(files, cfg)

# Prepare model
model = KWS(cfg).to('cuda')
ckpt = torch.load('runs/kws/20260127_193651_job11896010_task2_x1002c3s3b1n0/checkpoints/best_model_calibration.pth')
model.load_state_dict(ckpt)
model.eval()

# Set model to quantization mode
model.quantize()

for data in ds:
    data['batch'] = torch.zeros(data['x'].shape[0], dtype=torch.long)
    data = move_to_device(data, 'cuda')

    print(WORDS_COMM[data['y']], data['end_time'], data['file'])
    with torch.no_grad():
        conf, cls = model(data)

    cls = torch.softmax(cls, dim=1)  # Apply softmax to the class scores
    y = data['y']
    conf = torch.sigmoid(conf).cpu().numpy()
    pos = data['pos'].cpu().numpy()
    plt.scatter(pos[:, 0], pos[:, 1], s=1, alpha=0.5)
    vec_time = np.linspace(0, 1, conf.shape[1])
    plt.plot(vec_time, conf[0], label='Conf', color='red')
    for i in range(11):
        plt.plot(vec_time, cls[0,i,:].cpu().detach().numpy(), label=WORDS_COMM[i], linestyle='--', color=plt.cm.tab10(i))
    plt.yticks([])
    plt.legend()
    plt.show()