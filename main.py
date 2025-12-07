import os, glob
from omegaconf import OmegaConf
from dataset.nas import SpikingDS

files = glob.glob('/home/imperator/Datasets/NAS_GSC/dataset/verification/*')
cfg = OmegaConf.load("configs/dataset.yaml")

ds = SpikingDS(files, cfg)

