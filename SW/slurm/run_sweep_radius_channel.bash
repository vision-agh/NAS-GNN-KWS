#!/bin/bash -l
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32
#SBATCH --gres=gpu:1
#SBATCH --mem=64G
#SBATCH --time=48:00:00
#SBATCH --account=plgevents-gpu-gh200
#SBATCH --partition=plgrid-gpu-gh200

# Use job arrays:
#SBATCH --array=0-5

#SBATCH --output=outputs/%x-%A_%a.out
#SBATCH --error=outputs/%x-%A_%a.err
#SBATCH --job-name=kws_sweep

ml ML-bundle/25.04
source /net/scratch/hscra/plgrid/plgjeziorek/NAS-GNN-KWS/nas/bin/activate

export SSL_CERT_FILE=/net/scratch/hscra/plgrid/plgjeziorek/NAS-GNN-KWS/nas/lib/python3.11/site-packages/certifi/cacert.pem
export HDF5_PLUGIN_PATH=/net/scratch/hscra/plgrid/plgjeziorek/NAS-GNN-KWS/nas/lib/python3.11/site-packages/hdf5plugin/plugins

cd /net/scratch/hscra/plgrid/plgjeziorek/NAS-GNN-KWS/SW/

mkdir -p outputs

CONFIGS=(
  "dataset.low_time_radius=0 dataset.high_time_radius=5000 dataset.channel_radius=10 dataset.skip_channels=1"
  "dataset.low_time_radius=0 dataset.high_time_radius=5000 dataset.channel_radius=20 dataset.skip_channels=1"
  "dataset.low_time_radius=0 dataset.high_time_radius=5000 dataset.channel_radius=30 dataset.skip_channels=1"
  "dataset.low_time_radius=0 dataset.high_time_radius=5000 dataset.channel_radius=30 dataset.skip_channels=3"
  "dataset.low_time_radius=0 dataset.high_time_radius=5000 dataset.channel_radius=40 dataset.skip_channels=4"
  "dataset.low_time_radius=0 dataset.high_time_radius=5000 dataset.channel_radius=50 dataset.skip_channels=5"
  )

CFG="${CONFIGS[$SLURM_ARRAY_TASK_ID]}"

echo "======================================"
echo "SLURM_JOB_ID:        $SLURM_JOB_ID"
echo "SLURM_ARRAY_TASK_ID: $SLURM_ARRAY_TASK_ID"
echo "RUN CONFIG:          $CFG"
echo "======================================"

# (Optional) WandB grouping
export WANDB_PROJECT="kws-nas-gsc"
export WANDB_RUN_GROUP="kws_sweep_$(date +%Y%m%d)"
export WANDB_NAME="task${SLURM_ARRAY_TASK_ID}_${CFG// /_}"

python train_kws_slurm.py --model_cfg configs/kws.yaml $CFG
