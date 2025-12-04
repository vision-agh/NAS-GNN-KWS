import numpy as np
import cv2

def detect_active_range(hist, bin_edges, T_high=None, T_low=None, cooldown_steps=5):
    hist = hist.astype(np.float32)
    hist_smoothed = cv2.GaussianBlur(hist.reshape(1, -1), (7, 1), 0).flatten()

    if T_high is None:
        T_high = np.mean(hist_smoothed) + 0.5 * np.std(hist_smoothed)
    if T_low is None:
        T_low = 0.2 * T_high

    active = False
    cooldown = 0
    start_idx = None
    end_idx = None

    for i, val in enumerate(hist_smoothed):
        if not active and val >= T_high:
            active = True
            start_idx = i
            cooldown = 0
        elif active:
            if val >= T_low:
                cooldown = 0  # reset cooldown
            else:
                cooldown += 1
                if cooldown >= cooldown_steps:
                    end_idx = i - cooldown
                    break  # end of activity

    if active and end_idx is None:
        end_idx = len(hist_smoothed) - 1 

    if start_idx is not None and end_idx is not None:
        start_time = bin_edges[start_idx]
        end_time = bin_edges[end_idx + 1]
        return start_time, end_time, hist_smoothed
    else:
        return None, None, hist_smoothed