import re
import torch
import edge_generator
import cv2
import numpy as np

from torch.utils.data import Dataset
from dataset.utils.detective_active_range import detect_active_range
from dataset.utils.nas_loader import nas_loader
from dataset.utils.nas_settings import settings


WORDS = [
    "yes",
    "no",
    "up",
    "down",
    "left",
    "right",
    "on",
    "off",
    "stop",
    "go",
]

WORD_TO_CLASS = {w: i for i, w in enumerate(WORDS)}

class SpikingDS(Dataset):
    def __init__(self,
                 files,
                 config,
                 train: bool = False):
        
        self.train = train
        self.config = config
        self.files = files

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
        y = self.filename_to_class(data_file.split('/')[-1])

        addr, ts = nas_loader(data_file, self.nas_settings)

        pos = torch.from_numpy(np.column_stack((ts, addr))).float()
        pos[:, 0] = torch.round(pos[:, 0])
        pos = pos[pos[:, 0] < self.time_window]

        # ---------------- COCHLEA FILTERING ----------------
        if self.config.cochlea == 'left':
            pos = pos[pos[:, 1] < self.num_channels * 2]
        elif self.config.cochlea == 'right':
            pos = pos[pos[:, 1] >= self.num_channels * 2]
        # 'both' keeps all

        if len(pos) == 0:
            return None  # or handle empty window

        # ---------------- ADDRESS REMAPPING ----------------
        remapped_addr, polarity_feat = self.remap_addresses(pos[:, 1].long())
        pos[:, 1] = remapped_addr

        # ---------------- EDGE GENERATION ------------------
        edge_index, x, pos = self.edge_gen.generate_edges(pos[:, 0], pos[:, 1], polarity_feat)


        pos[:, 0] = pos[:, 0] / self.time_window
        pos[:, 1] = pos[:, 1] / self.num_channels

        
        if pos.shape[0] < 2:
            return self.__getitem__((index + 1) % len(self))

        return {'x': x,
                'pos': pos,
                'edge_index': edge_index,
                'y': y,
                'file': data_file}

    
    def filename_to_class(self, fname):
        match = re.match(r"([a-z]+)\d+", fname.lower())
        if not match:
            return None

        word = match.group(1)
        return WORD_TO_CLASS.get(word)

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





        # data['pos'][:, 0] = torch.round(data['pos'][:, 0])                  # Round to nearest microsecond
        # data['pos'] = data['pos'][data['pos'][:, 0] < self.time_window]     # Cut data to time window

        # # Generate edge_index and features

        # edge_index, x = self.edge_gen.generate_edges(data['pos'][:, 0], 
        #                                             data['pos'][:, 1])
        
        # data['edge_index'] = edge_index
        # data['x'] = x

        # if self.config.general.name == 'Google_Speech_Commands' and \
        #       self.config.model.num_classes == 11:
        #     data['y'] = torch.tensor(label_map[int(data['y'].item())], dtype=torch.long)
        
        # # Normalise node positions
        # data['pos'][:, 0] = data['pos'][:, 0] / self.time_window
        # data['pos'][:, 1] = data['pos'][:, 1] / self.num_channels


        # bin_width = 0.01
        # bins = np.arange(0, 1 + bin_width, bin_width)
        # hist, bin_edges = np.histogram(data['pos'][:, 0].cpu().numpy(), bins=bins)
        # hist = hist.astype(np.float32)

        # start_time, end_time, hist_smoothed = detect_active_range(hist, bin_edges)

        # data['end_time'] = end_time  # seconds in range [0,1]

        # # --- here we generate labels y ---
        # T = int(1.0 / bin_width)      # num of bins = 100
        # y = torch.zeros(T, dtype=torch.float32)
        # cls = torch.zeros(T, dtype=torch.float32)

        # if end_time is not None:
        #     # index of bin, where words ends
        #     bin_idx = int(end_time // bin_width)
        #     if 0 <= bin_idx < T:
        #         y[bin_idx] = 1.0
        #         cls[bin_idx] = data['y']

        #         if bin_idx + 1 < T:
        #             y[bin_idx+1] = 0.5
        #             cls[bin_idx+1] = data['y']

        #         if bin_idx - 1 >= 0:
        #             y[bin_idx-1] = 0.5
        #             cls[bin_idx-1] = data['y']

        # data['keyword'] = y
        # data['cls'] = cls

        # return data


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
