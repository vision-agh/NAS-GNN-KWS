from omegaconf import OmegaConf


def generate_constant_thresholds(num_channels, value=32):
    return [value] * num_channels

def generate_linear_thresholds(num_channels, start=64, end=32):
    thresholds = []
    for i in range(num_channels):
        t = start + (end - start) * (i / (num_channels - 1)) if num_channels > 1 else start
        thresholds.append(int(round(t)))
    return thresholds

def generate_exponential_thresholds(num_channels, start=64, end=32, sharpness=1.0):
    thresholds = []
    for i in range(num_channels):
        t = start * ((end / start) ** (i / (num_channels - 1)) ** sharpness)
        thresholds.append(int(round(t)))
    return thresholds

def build_config(
    dataset_cfg_path="configs/dataset.yaml",
    nas_cfg_path="configs/nas.yaml",
    model_cfg_path="configs/kws.yaml",
    overrides=None,
):
    dataset_cfg = OmegaConf.load(dataset_cfg_path)
    nas_cfg = OmegaConf.load(nas_cfg_path)
    model_cfg = OmegaConf.load(model_cfg_path)

    cfg = OmegaConf.create({
        "dataset": dataset_cfg,
        "nas": nas_cfg,
        "model": model_cfg,
    })

    # Apply overrides like: ["dataset.num_channels=8", "model.hidden_dim=128"]
    if overrides:
        override_cfg = OmegaConf.from_dotlist(overrides)
        cfg = OmegaConf.merge(cfg, override_cfg)

    total_num_channels = cfg.dataset.num_channels * (2 if cfg.dataset.polarity else 1)
    start_threshold = cfg.dataset.get("start_threshold", 64)
    end_threshold = cfg.dataset.get("end_threshold", 32)
    sharpness = cfg.dataset.get("sharpness", 1.0)

    # Generate thresholds based on the specified method
    method = cfg.dataset.get("threshold_method", "exponential")
    if method == "constant":
        thresholds = generate_constant_thresholds(total_num_channels, 
                                                  value=start_threshold)
    elif method == "linear":
        thresholds = generate_linear_thresholds(total_num_channels, 
                                                start=start_threshold, 
                                                end=end_threshold)
    else:  # default to exponential
        thresholds = generate_exponential_thresholds(total_num_channels, 
                                                     start=start_threshold, 
                                                     end=end_threshold, 
                                                     sharpness=sharpness)

    cfg.dataset.thresholds = thresholds

    return cfg
