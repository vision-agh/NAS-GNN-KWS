import numpy as np
import cv2

def detect_active_range(hist, bin_edges, cfg):
    hist_smoothed = cv2.GaussianBlur(hist[None, :], (cfg.dataset.gausian_kernel_size, 1), 0)[0]

    m = hist_smoothed.mean()
    s = hist_smoothed.std()

    T_high = cfg.dataset.mean_scale * m + cfg.dataset.std_scale * s
    T_low = cfg.dataset.low_percentage * T_high

    hs = hist_smoothed

    # find activation start
    start_mask = hs >= T_high
    if not np.any(start_mask):
        return None, None, hs

    start_idx = np.argmax(start_mask)   # first True

    # examine only after start
    tail = hs[start_idx:]

    below_low = tail < T_low

    # compute run-length via cumulative trick
    # We need first index where below_low has cooldown_steps consecutive True
    if cfg.dataset.cooldown_steps == 1:
        fail_idx = np.argmax(below_low)
        if below_low[fail_idx]:
            end_idx = start_idx + fail_idx - 1
        else:
            end_idx = len(hs) - 1
    else:
        # use sliding window sum
        # convolution gives count of True in window
        window = np.ones(cfg.dataset.cooldown_steps, dtype=np.int32)
        conv = np.convolve(below_low.astype(np.int32), window, mode='valid')
        fail_pos = np.argmax(conv == cfg.dataset.cooldown_steps)

        if conv[fail_pos] == cfg.dataset.cooldown_steps:
            end_idx = start_idx + fail_pos - 1
        else:
            end_idx = len(hs) - 1

    start_time = bin_edges[start_idx]
    end_time = bin_edges[end_idx + 1]
    return start_time, end_time, hs
