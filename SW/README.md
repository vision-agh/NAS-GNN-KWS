```bash
# Create conda env
conda create -n gcn_nas python=3.9
conda activate gcn_nas

# Install PyTorch (CUDA 12.1/12.8 depending on your setup; adjust if needed)
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
# or:
# pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128

# Install Python dependencies
pip install \
    omegaconf \
    opencv-python \
    matplotlib \
    psutil \
    wandb \
    lightning \
    numba \
    pybind11 \
    tqdm \
    pandas \
    loguru \
    pycocotools

# Install HDF5 related libs
conda install h5py
conda install -c conda-forge blosc-hdf5-plugin

# Inside main folder
cd GCN-OF

# REMEMBER TO COMPILE TO C++ GRAPH GEN!!!!!!!1
python setup.py build_ext --inplace
```

Data:

Your `data` folder should look like this:

```text
dataset/
└── all_samples
    ├── down0001.wav
    ├── ...
    └── yes2377.wav
└── verification
    ├── down0001.wav.aedat
    ├── ...
    └── yes2377.wav.aedat
```


# Example results

20251223_113159 - one epoch training with calibration, only for quick testing

20251223_213525_fully_trained - fully trained model over 50 epochs float and 5 calibration (WITHOUT POSITIONAL NORMALISATION)

Used config:

# general settings
version: commands               # Dataset version: commands (10+1 classes), full (35 classes)
num_channels: 64                # Number of cochlea channels
polarity: True                  # {True, False} if True - 2 x num_channels, False - num_channels
stereo: False                   # {True, False} if True - we use stereo, False- we use mono
cochlea: left                   # {'left', 'right', 'both'}

# graph construction settings
channel_radius: 20              # Channel distance radius in graph construction
low_time_radius: 2_000          # Inner time radius in microseconds         (0 - no inner radius)
high_time_radius: 10_000         # Outer time radius in microseconds
time_window: 1_000_000          # Time window in microseconds for event selection
skip_channels: 2                # Number of channels to skip from each side       (1 - no skipping)
features_aggregation: global    # local, global or None

# filtration settings
use_filtration: True            # Whether to use event filtration
div_factor: 8                   # Division factor (2 ^ div_factor) for time normalization
weight: 32                      # Weight for potential accumulation
thresholds: None                # List of thresholds for event filtration, if None - automatic thresholding

# active range detection settings
bin_width: 0.01                 # Bin width in seconds for histogram computation
cooldown_steps: 3               # Cooldown steps for active range detection
mean_scale: 1.0                 # Mean scaling factor for active range detection high threshold
std_scale: 0.5                  # Standard deviation scaling factor for active range detection high threshold
low_percentage: 0.7             # Threshold_low = low_percentage * Threshold_high
gausian_kernel_size: 7          # Kernel size for Gaussian smoothing in active range detection