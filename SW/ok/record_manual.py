import os

import matplotlib
import matplotlib.pyplot as plt
import pyOKAERTool as okt
from pyNAVIS import *

settings = MainSettings(num_channels=32, mono_stereo=0, on_off_both=1, address_size=2, timestamp_size=4, ts_tick=1)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
BIT_FILE = os.path.join(REPO_ROOT, "HW", "vivado", "rec", "recording_system.runs", "impl_1", "recording_system.bit")
opal = okt.Okaertool(bit_file=BIT_FILE)
opal.init()
opal.reset_board()

BLOCKSIZE = 16 * 16
opal.USB_TRANSFER_LENGTH = BLOCKSIZE * 16
opal.USB_BLOCK_SIZE = BLOCKSIZE

INPUTS = ['port_a']
RECORD_DURATION = 0.5


def record_manual(duration=RECORD_DURATION):
    opal.reset_board()

    print("rekord")
    spikes = opal.monitor(duration=duration, inputs=INPUTS)
    opal.reset_timestamp()

    if spikes is None or spikes[0].get_num_spikes() == 0:
        print("Brak zarejestrowanych spike'ow.")
        return

    spike_file = SpikesFile(addresses=spikes[0].addresses, timestamps=spikes[0].timestamps)
    print(f"Zarejestrowano {len(spike_file.timestamps)} spike'ow")

    Plots.spikegram(spike_file, settings)

    if matplotlib.get_backend().lower() == "agg":
        out_path = os.path.join(SCRIPT_DIR, "record_manual_spikegram.png")
        plt.savefig(out_path)
        print(f"Brak interaktywnego backendu matplotlib - zapisano wykres do {out_path}")
    else:
        plt.show()


if __name__ == "__main__":
    record_manual()
