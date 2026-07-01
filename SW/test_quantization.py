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

from omegaconf import OmegaConf

from utils.generate_outputs import gen_input_events, gen_graph_out, conv_gen_out, conv_first_gen_out, vector_out

def move_to_device(batch, dev):
    return {
        k: (v.to(dev, non_blocking=True) if torch.is_tensor(v) else v)
        for k, v in batch.items()
    }


# Parallel 64 = '20260205_153506_job12193988_task0_x1002c2s6b1n0'
# Parallel 32 = '20260216_225818_job12650489_task3_x1002c3s2b0n0'

# Prepare dataset
files = glob.glob(
    f"{Path.home()}/Datasets/NAS_GSC/dataset_aedat_w_delays_parallel_32ch/stop/cd85758f_nohash_2.wav*"
)
# cfg = build_config(model_cfg_path="configs/kws.yaml")

cfg = OmegaConf.load('runs/kws/20260216_225818_job12650489_task3_x1002c3s2b0n0/config.yaml')
OmegaConf.resolve(cfg)
ds = SpikingDS(files, cfg)

# Prepare model
model = KWS(cfg).to('cuda')
ckpt = torch.load('runs/kws/20260216_225818_job12650489_task3_x1002c3s2b0n0/checkpoints/best_model_calibration.pth')
model.load_state_dict(ckpt)
model.eval()

# Set model to quantization mode
model.quantize()

# Create output directory for debug outputs
path_debug = 'runs/kws/20260216_225818_job12650489_task3_x1002c3s2b0n0/debug_outputs/'
path_parameters = 'runs/kws/20260216_225818_job12650489_task3_x1002c3s2b0n0/parameters/'
os.makedirs(path_debug, exist_ok=True)
os.makedirs(path_parameters, exist_ok=True)

model.conv1.get_parameters(path_parameters + 'conv1.txt')
model.conv2.get_parameters(path_parameters + 'conv2.txt')
model.conv3.get_parameters(path_parameters + 'conv3.txt')
model.conv4.get_parameters(path_parameters + 'conv4.txt')
model.fc1.get_parameters(path_parameters + 'fc1.txt')
model.fc2.get_parameters(path_parameters + 'fc2.txt')
model.rnn.gru.get_parameters(path_parameters + 'rnn')
model.cls.get_parameters(path_parameters + 'cls.txt')
model.conf.get_parameters(path_parameters + 'conf.txt')


for data in ds:
    data['batch'] = torch.zeros(data['x'].shape[0], dtype=torch.long)
    data = move_to_device(data, 'cuda')

    gen_input_events(data['pos_original'], data['polarity_feature'], cfg, path_debug + 'input_events.txt')
    gen_input_events(data['pos_filtered'], data['x'][:, -1], cfg, path_debug + 'filtered_events.txt')
    gen_graph_out(model.conv1.observer_input.quantize_tensor(data['x']), data['pos_filtered'], data['edge_index'], cfg, path_debug + 'graph_out.txt')

    with torch.no_grad():
        conf, cls = model(data)
        print(conf)
        print(cls)

    break