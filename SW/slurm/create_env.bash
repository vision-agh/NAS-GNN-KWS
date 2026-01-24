#!/bin/bash -l
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --time=00:10:00
#SBATCH --account=plgevents-gpu-gh200
#SBATCH --partition=plgrid-gpu-gh200
#SBATCH --output=outputs/job-%j.out
#SBATCH --error=outputs/job-%j.err
 
# IMPORTANT: load the modules for machine learning tasks and libraries
ml ML-bundle/25.04
 
# create and activate the virtual environment
python -m venv  nas/
source nas/bin/activate

pip install --no-cache-dir torch==2.8.0+cu128

# install the rest of requirements, for example via requirements file
pip install --no-cache-dir omegaconf opencv-python matplotlib psutil wandb lightning numba pybind11 tqdm pandas loguru pycocotools h5py hdf5plugin

cd /net/scratch/hscra/plgrid/plgjeziorek/NAS-GNN-KWS/SW/

python setup.py build_ext --inplace
pip list