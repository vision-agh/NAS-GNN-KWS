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