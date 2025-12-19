import re
import torch
import edge_generator
import cv2
import numpy as np

from torch.utils.data import Dataset
from dataset.utils.detective_active_range import detect_active_range
from dataset.utils.nas_loader import nas_loader
from configs.nas_settings import settings


WORDS_COMM = [
    "yes", "no", "up", "down", "left",
    "right", "on", "off", "stop", "go", "unknown"
]

WORDS_ALL = [
    "backward", "bed", "bird", "cat", "dog",
    "down", "eight", "five", "follow", "forward",
    "four", "go", "happy", "house", "learn",
    "left", "marvin", "nine", "no", "off",
    "on", "one",  "right", "seven", "sheila",
    "six", "stop", "three",  "tree", "two",
    "up", "visual", "wow", "yes", "zero"
]

WORD_COMM_TO_CLASS = {w: i for i, w in enumerate(WORDS_COMM)}
WORD_ALL_TO_CLASS = {w: i for i, w in enumerate(WORDS_ALL)}

class SpikingDS(Dataset):
    def __init__(self,
                 files,
                 config,
                 train: bool = False):
        
        self.train = train
        self.config = config
        self.files = files
        self.version = config.version

        self.polarity = config.polarity
        self.stereo = config.stereo
        self.cochlea = config.cochlea

        self.num_channels = config.num_channels
        self.channel_radius = config.channel_radius
        self.low_time_radius = config.low_time_radius
        self.high_time_radius = config.high_time_radius
        self.time_leaky = config.time_leaky
        self.norm_channel_filter = config.norm_channel_filter
        self.threshold = config.threshold
        self.time_window = config.time_window
        self.skip_channels = config.skip_channels
        self.features_aggregation = config.features_aggregation
        
        self.nas_settings = settings

        self.edge_gen = edge_generator.EdgeGenerator(self.config.num_channels * (1 + self.polarity) * (1 + self.stereo), 
                                                        self.config.channel_radius, 
                                                        self.config.low_time_radius,
                                                        self.config.high_time_radius,
                                                        self.config.time_leaky, 
                                                        self.config.norm_channel_filter,
                                                        self.config.threshold,
                                                        self.config.time_window,
                                                        self.config.skip_channels,
                                                        self.config.features_aggregation)

    def __len__(self) -> int:
        return len(self.files)
    
    def __getitem__(self, index):
        data_file = self.files[index]
        y = self.filename_to_class(data_file)

        addr, ts = nas_loader(data_file, self.nas_settings)

        pos = torch.from_numpy(np.column_stack((ts, addr))).float()
        pos[:, 0] = torch.round(pos[:, 0])
        pos = pos[pos[:, 0] < 2 * self.time_window]

        # ---------------- COCHLEA FILTERING ----------------
        if self.config.cochlea == 'left':
            pos = pos[pos[:, 1] < self.num_channels * 2]
        elif self.config.cochlea == 'right':
            pos = pos[pos[:, 1] >= self.num_channels * 2]
        # 'both' keeps all

        if len(pos) == 0:
            return None # skip empty samples

        # ---------------- ADDRESS REMAPPING ----------------
        remapped_addr, polarity_feat = self.remap_addresses(pos[:, 1].long())
        pos[:, 1] = remapped_addr

        # ---------------- EDGE GENERATION ------------------
        edge_index, x, pos = self.edge_gen.generate_edges(pos[:, 0], pos[:, 1], polarity_feat)

        pos[:, 0] = pos[:, 0] / self.time_window
        pos[:, 1] = pos[:, 1] / self.num_channels if not self.polarity else pos[:, 1] / (self.num_channels * 2)
        
        if pos.shape[0] < 2:
            return self.__getitem__((index + 1) % len(self))

        return {'x': x,
                'pos': pos,
                'edge_index': edge_index,
                'y': y,
                'file': data_file}

    
    def filename_to_class(self, fname):
        word = fname.split('/')[-2]
        if self.version == 'commands':
            if word not in WORD_COMM_TO_CLASS:
                word = 'unknown'

        if self.version == 'commands':
            return WORD_COMM_TO_CLASS.get(word)
        else:
            return WORD_ALL_TO_CLASS.get(word)

    def decode_event(self, addr):
        # cochlea selection
        coch = 0 if addr < (self.num_channels * 2) else 1
        local = addr % (self.num_channels * 2)

        polarity = -1 if (local % 2 == 0) else 1
        channel = local // 2     # 0–63

        return coch, channel, polarity
    
    def remap_addresses(self, addrs):
        """
        Returns:
            new_addr: remapped address
            polarity_feat: polarity feature if polarity=False else None
        """

        # --- Decode raw event properties ---
        coch = (addrs >= self.num_channels * 2).long()                 # 0 = left, 1 = right
        local = addrs % (self.num_channels * 2)                          # 0–127 inside the cochlea
        polarity = torch.where(local % 2 == 0, -1, 1)
        channel = local // 2                         # 0–63

        # ================================================================
        #   STEP 1: COCHLEA FILTERING AND NORMALIZATION
        # ================================================================

        if self.cochlea == "left":
            # keep only left
            coch = torch.zeros_like(coch)
            # local already 0–127
        elif self.cochlea == "right":
            # keep only right
            coch = torch.zeros_like(coch)     # normalize right → 0
            # local still 0–127 because (addr % 128)
        else:
            # both → keep coch=0 or 1
            pass

        # ================================================================
        #   STEP 2: POLARITY HANDLING
        # ================================================================

        # ---------- CASE A: polarity encoded into address (0–127) ----------
        if self.polarity:
            # addr = channel*2 + (0=neg,1=pos)
            new_addr = channel * 2 + (polarity == 1).long()

            # If stereo and both cochleas → add offset 128 for right
            if self.stereo and self.cochlea == "both":
                new_addr = new_addr + coch * self.num_channels * 2

            polarity_feat = None

        # ---------- CASE B: polarity is a separate feature -------------
        else:
            new_addr = channel                # 0–63
            polarity_feat = polarity.float()  # additional feature

            if self.stereo and self.cochlea == "both":
                new_addr = new_addr + coch * self.num_channels

        return new_addr, polarity_feat

if __name__ == '__main__':
    import yaml
    import matplotlib.pyplot as plt
    from omegaconf import OmegaConf

    cfg = OmegaConf.load("configs/dataset.yaml")
    ds = SpikingDS(['verification/down0001.wav.aedat', 'verification/up0001.wav.aedat'], cfg)

    for data in ds:
        edge, x, pos = data
        print("Edges:", edge.shape)
        print("X:", x.shape)
        print("Pos:", pos.shape)
        plt.scatter(pos[:, 0].numpy(), pos[:, 1].numpy(), s=0.1)
        plt.show()
