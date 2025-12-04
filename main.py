import aedat
import numpy as np
import math
import matplotlib.pyplot as plt
from dataset.utils.nas_settings import settings
from dataset.utils.nas_loader import nas_loader

# file = 'verification/down0001.wav.aedat'
file = 'verification/up0001.wav.aedat'
# file = 'verification/go0001.wav.aedat'
# file = 'verification/left0001.wav.aedat'
# file = 'verification/right0001.wav.aedat'

addresses, timestamps = nas_loader(file, settings=settings)

print(len(addresses))
plt.scatter(timestamps, addresses, s=0.1)
plt.show()