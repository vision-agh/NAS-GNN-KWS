from omegaconf import OmegaConf


def generate_thresholds(num_channels):
    return [32] * num_channels  # replace with real logic

def generate_exponential_thresholds(num_channels, start=64, end=32):
    thresholds = []
    for i in range(num_channels):
        t = start * ((end / start) ** (i / (num_channels - 1)))
        thresholds.append(int(round(t)))
    return thresholds

def build_config(dataset_cfg_path="configs/dataset.yaml",
                 nas_cfg_path="configs/nas.yaml",
                 model_cfg_path="configs/recognition.yaml"):
    dataset_cfg = OmegaConf.load(dataset_cfg_path)
    nas_cfg = OmegaConf.load(nas_cfg_path)
    model_cfg = OmegaConf.load(model_cfg_path)

    cfg = OmegaConf.create({
        "dataset": dataset_cfg,
        "nas": nas_cfg,
        "model": model_cfg,
    })

    # TODO: implement real threshold generation logic
    # thresholds = generate_thresholds(cfg.dataset.num_channels * (2 if cfg.dataset.polarity else 1))
    thresholds = generate_exponential_thresholds(cfg.dataset.num_channels * (2 if cfg.dataset.polarity else 1))
    cfg.dataset.thresholds = thresholds
    return cfg