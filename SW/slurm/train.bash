#!/bin/bash -l
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=32
#SBATCH --gres=gpu:1
#SBATCH --mem=64G
#SBATCH --time=48:00:00
#SBATCH --account=plgevents-gpu-gh200
#SBATCH --partition=plgrid-gpu-gh200
#SBATCH --output=outputs/%x-%A_%a.out
#SBATCH --error=outputs/%x-%A_%a.err

# IMPORTANT: load the modules for machine learning tasks and libraries
ml ML-bundle/25.04

# create and activate the virtual environment
source /net/scratch/hscra/plgrid/plgjeziorek/NAS-GNN-KWS/nas/bin/activate

export SSL_CERT_FILE=/net/scratch/hscra/plgrid/plgjeziorek/NAS-GNN-KWS/nas/lib/python3.11/site-packages/certifi/cacert.pem
export HDF5_PLUGIN_PATH=/net/scratch/hscra/plgrid/plgjeziorek/NAS-GNN-KWS/nas/lib/python3.11/site-packages/hdf5plugin/plugins

cd /net/scratch/hscra/plgrid/plgjeziorek/NAS-GNN-KWS/SW/

# print the list of installed packages
pip list

python train_kws.py