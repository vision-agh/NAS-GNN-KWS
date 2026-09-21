import numpy as np
import os
import sys
import shutil
import sounddevice as sd
import time
import pyOKAERTool as okt
import matplotlib.pyplot as plt
from pyNAVIS import *
from scipy.io import savemat
from scipy.io import wavfile

settings = MainSettings(num_channels=32, mono_stereo=0, on_off_both=1, address_size=2, timestamp_size=4, ts_tick=1)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
BIT_FILE = os.path.join(REPO_ROOT, "HW", "vivado", "rec", "recording_system.runs", "impl_1", "recording_system.bit")
opal = okt.Okaertool(bit_file=BIT_FILE)
opal.init()
opal.reset_board()

MAX_INPUTS = 3
INPUTS = ['port_a']
BASE_DIR = r"C:/Users/wikto/datasets/gsc_v2"
OUTPUT_DIR = r"C:/Users/wikto/datasets/gsc_v2_32p_ok"

# os.makedirs(OUTPUT_DIR, exist_ok=True)

Fs = 48000  # frecuencia de muestreo
okt_freq = 1e8
GAIN = 0.8

monitortime = 0.8
incTime = 0.2

sd.default.samplerate = 48000
sd.default.channels = 1
sd.default.dtype = 'float32'  # safer than int16
sd.default.latency = ('high', 'high')
sd.default.blocksize = 2048

def generate_sine(freq, duration, samplerate=48000):
    t = np.arange(int(duration*samplerate)) / samplerate
    mono = np.sin(2*np.pi*freq*t).astype(np.float32)
    stereo = np.column_stack((mono, mono))
    return stereo


# ====================================
# Conversion function
# ====================================
def convert_to_aedat(input_audio_path, output_aedat_path, settings):
    samplerate, audio_data = wavfile.read(input_audio_path)
    print(f"sample rate: {samplerate}")
    print(f"audio data: {len(audio_data)}")
    opal.reset_board()

    time_wait_after = 0.5
    time_wait_before = 0.1

    # duration = len(audio_data) / samplerate
    duration = 1.0
    
    duration = duration + time_wait_after + time_wait_before
    print(f"duration: {duration}")
    sd.play(audio_data, samplerate)
    time.sleep(max(0.0, 0.35 - time_wait_before))
    spikes = opal.monitor(duration=duration, inputs=['port_a'])
    sd.wait()

    spike_file = SpikesFile(addresses=spikes[0].addresses, timestamps=spikes[0].timestamps)
    opal.reset_timestamp()
    output_dir = os.path.dirname(output_aedat_path)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)
        
    if output_aedat_path.endswith('.aedat'):
        output_aedat_path = output_aedat_path[:-6]
    Savers.save_AEDAT(spike_file, output_aedat_path, settings)

def playsound(input_audio_path):
    samplerate, audio_data = wavfile.read(input_audio_path)
    sd.play(audio_data, samplerate)
    sd.wait()

def convertsinewave(freq,settings):
    signal = generate_sine(freq, monitortime + incTime, samplerate=Fs) * GAIN
    opal.reset_board()
    duration = len(signal) / Fs
    # opal.monitor(live=True, inputs=['port_a'])  
    sd.play(signal, Fs)
    time.sleep(0.25)
    # opal.monitor(live=True, inputs=['port_a'])
    spikes = opal.monitor(duration=duration+0.0, inputs=['port_a'])
    sd.wait()
    # time.sleep(0.2)  # small delay to ensure all spikes are captured
    # spikes = opal.stop_monitor()
    opal.reset_timestamp()
    check_and_represent_spikes(spikes)

def check_and_represent_spikes(spikes):
    # Check if spikes is not None. If so, finish the script
    if spikes is None:
        opal.logger.error("No spikes were recorded. Exiting the script.")
        sys.exit(1)
        
    # Print the number of spikes for each input
    for i in range(MAX_INPUTS):
        opal.logger.info("Input %d: %d spikes", i, spikes[i].get_num_spikes())

    # Create pyNAVIS spike_file only if there are spikes for a specific input
    opal.logger.info("Creating spike files for all selected inputs")
    spike_files = []
    for i in range(MAX_INPUTS):
        if spikes[i].get_num_spikes() > 0:
            spike_files.append(SpikesFile(addresses=spikes[i].addresses, timestamps=spikes[i].timestamps))

    # Add this cell BEFORE plotting to verify data integrity
    import numpy as np

    opal.logger.info("=== DATA INTEGRITY CHECK ===")

    # IMPORTANT: Timestamps are in 10ns ticks (hardware clock period)
    TIMESTAMP_TICK_US = 0.01  # Each tick = 10ns = 0.01 microseconds

    for i in range(len(spike_files)):
        if len(spike_files[i].timestamps) == 0:
            opal.logger.warning(f"Input {INPUTS[i]}: No spikes recorded")
            continue
        
        timestamps = np.array(spike_files[i].timestamps)
        addresses = np.array(spike_files[i].addresses)
        
        # opal.logger.info(f"/--- Input {INPUTS[i]} ---")
        # opal.logger.info(f"Total spikes: {len(timestamps)}")
        # opal.logger.info(f"Timestamp range (ticks): {timestamps.min()} - {timestamps.max()}")
        # opal.logger.info(f"Timestamp range (µs): {timestamps.min() * TIMESTAMP_TICK_US:.2f} - {timestamps.max() * TIMESTAMP_TICK_US:.2f}")
        # opal.logger.info(f"Duration (ms): {(timestamps.max() - timestamps.min()) * TIMESTAMP_TICK_US / 1000:.2f}")
        # opal.logger.info(f"Address range: {addresses.min()} - {addresses.max()}")
        
        # Check for timestamp ordering
        if not np.all(timestamps[:-1] <= timestamps[1:]):
            opal.logger.error(f"Timestamps are NOT in ascending order!")
            bad_idx = np.where(timestamps[:-1] > timestamps[1:])[0][0]
            opal.logger.error(f"First violation at index {bad_idx}: {timestamps[bad_idx]} > {timestamps[bad_idx+1]}")
        else:
            opal.logger.info("Timestamps are in ascending order")
        
        # Check for negative timestamps
        if np.any(timestamps < 0):
            opal.logger.error(f"Found {np.sum(timestamps < 0)} negative timestamps!")
        else:
            opal.logger.info("No negative timestamps")
        
        # Check timestamp deltas (should be reasonable for audio events)
        if len(timestamps) > 1:
            deltas = np.diff(timestamps)
            mean_delta_ns = np.mean(deltas) * 10  # Convert ticks to nanoseconds
            median_delta_ns = np.median(deltas) * 10
            max_delta_ns = np.max(deltas) * 10
            
            opal.logger.info(f"Timestamp deltas (ns): mean={mean_delta_ns:.1f}, median={median_delta_ns:.1f}, max={max_delta_ns:.1f}")
            
            # Expected delta for sequential addresses (e.g., ~24 ticks = 240ns)
            if addresses.max() - addresses.min() > 200:  # If we have many addresses
                opal.logger.info(f"Expected delta for sequential scan: ~240ns (24 ticks @ 10ns)")
        
        # Calculate event rate
        duration_s = (timestamps.max() - timestamps.min()) * TIMESTAMP_TICK_US / 1e6  # Convert to seconds
        if duration_s > 0:
            event_rate = len(timestamps) / duration_s
            opal.logger.info(f"Event rate: {event_rate:.0f} spikes/sec")
            
            # Check if rate is reasonable (typical audio: 1k-1M events/sec)
            # if event_rate > 10_000_000:
            #     opal.logger.warning(f"Event rate seems very high: {event_rate:.0f} spikes/sec")
            # elif event_rate < 100:
            #     opal.logger.warning(f"Event rate seems very low: {event_rate:.0f} spikes/sec")
            # else:
            #     opal.logger.info("Event rate within reasonable range")
        
        # Check address distribution
        unique_addrs = np.unique(addresses)
        opal.logger.info(f"Unique addresses: {len(unique_addrs)}")
        opal.logger.info(f"Address range: {addresses.min()} to {addresses.max()}")
        
        # Check if addresses are sequential (as expected after reset)
        if len(unique_addrs) > 10:
            expected_sequential = np.arange(addresses.min(), addresses.max() + 1)
            if np.array_equal(np.sort(unique_addrs), expected_sequential):
                opal.logger.info("Addresses are sequential (as expected after reset)")
            else:
                missing = set(expected_sequential) - set(unique_addrs)
                if missing:
                    opal.logger.info(f"Some addresses missing: {sorted(missing)[:10]}...")
        
        # Show distribution for most active addresses
        addr_counts = np.bincount(addresses.astype(int))
        top_10_indices = np.argsort(addr_counts)[-10:][::-1]
        top_10_counts = addr_counts[top_10_indices]
        opal.logger.info(f"Top 10 addresses by count:")
        for addr, count in zip(top_10_indices, top_10_counts):
            if count > 0:
                opal.logger.info(f"  Address {addr}: {count} events")

    opal.logger.info("=== END DATA INTEGRITY CHECK ===")

    # for i in range(len(spike_files)):
    #     opal.logger.info("Plotting the spikegram for input %s", INPUTS[i])
    #     Plots.spikegram(spike_files[i], settings)

    # for i in range(len(spike_files)):
    #     opal.logger.info("Plotting the sonogram for input %s", INPUTS[i])
    #     Plots.sonogram(spike_files[i], settings)

    for i in range(len(spike_files)):
        opal.logger.info("Plotting the histogram for input %s", INPUTS[i])
        Plots.histogram(spike_files[i], settings)

    # for i in range(len(spike_files)):
    #     opal.logger.info("Plotting the average activity for input %s", INPUTS[i])
    #     Plots.average_activity(spike_files[i], settings)
    plt.show()



def file_sweep(folder_path, output_dir, start_folder=None):
    subdirs = [d for d in os.listdir(folder_path) if os.path.isdir(os.path.join(folder_path, d))]
    subdirs.sort()

    if start_folder and start_folder in subdirs:
        start_idx = subdirs.index(start_folder)
        subdirs = subdirs[start_idx:]

    for subdir in subdirs:
        current_dir = os.path.join(folder_path, subdir)
        for root, _, files in os.walk(current_dir):
            wav_files = [f for f in files if f.lower().endswith(".wav")]
            wav_files.sort()

            rel_path = os.path.relpath(root, folder_path)
            output_subdir = os.path.join(output_dir, rel_path)
            os.makedirs(output_subdir, exist_ok=True)

            for wav_file in wav_files:
                input_path = os.path.join(root, wav_file)
                output_path = os.path.join(output_subdir, wav_file)
                try:
                    convert_to_aedat(input_path, output_path, settings)
                    time.sleep(0.3)
                except Exception as e:
                    raise
def visualize_converted_results(output_dir, settings, max_files=5):
    count = 0
    
    for root, dirs, files in os.walk(output_dir):
        aedat_files = [f for f in files if f.endswith(".aedat")]
        
        for file in aedat_files:
            if count >= max_files:
                return

            full_path = os.path.join(root, file)
            print(f"Wczytywanie: {full_path}")
            
            try:
                spikes_info = Loaders.loadAEDAT(full_path, settings)
                
                Plots.spikegram(spikes_info, settings)
                plt.title(f"Spikegram: {file}")

                # Plots.histogram(spikes_info, settings)
                # plt.title(f"Histogram: {file}")

                plt.show()
                
                count += 1
                
            except Exception as e:
                print(f"Error: {e}")
import random

import random
import matplotlib.pyplot as plt

import os
import random
import matplotlib.pyplot as plt

import os
import random
import matplotlib.pyplot as plt

def interactive_random_viewer(folder_path, settings):
    aedat_files = []
    for root, _, files in os.walk(folder_path):
        for f in files:
            if f.endswith(".aedat"):
                aedat_files.append(os.path.join(root, f))

    if not aedat_files:
        return

    random.shuffle(aedat_files)
    
    state = {'keep_going': True}

    for file_path in aedat_files:
        if not state['keep_going']:
            break
            
        try:
            spikes_info = Loaders.loadAEDAT(file_path, settings)
            
            Plots.spikegram(spikes_info, settings)
            
            fig = plt.gcf()
            file_name = os.path.basename(file_path)
            folder_name = os.path.basename(os.path.dirname(file_path))
            plt.title(f"{folder_name}/{file_name}")
            
            def on_press(event):
                if event.key == ' ':
                    plt.close(fig)
                elif event.key == 'escape':
                    state['keep_going'] = False
                    plt.close(fig)

            fig.canvas.mpl_connect('key_press_event', on_press)
            
            plt.show()
            
        except Exception:
            continue

def visualize_multiple_folders(folder_paths, settings, files_per_folder=4):
    all_files = []
    
    for folder_path in folder_paths:
        folder_files = []
        for root, dirs, files in os.walk(folder_path):
            aedat_files = [os.path.join(root, f) for f in files if f.endswith(".aedat")]
            folder_files.extend(aedat_files)
        
        folder_files.sort()
        all_files.extend(folder_files[:files_per_folder])
    
    total_files = len(all_files)
    if total_files == 0:
        print("Nie znaleziono plików .aedat")
        return
    
    print(f"Znaleziono {total_files} plików do wizualizacji")
    
    n_cols = 3
    n_rows = (total_files + n_cols - 1) // n_cols
    
    fig, axes = plt.subplots(n_rows, n_cols, figsize=(15, 5 * n_rows))
    
    if n_rows == 1:
        axes = axes.reshape(1, -1)
    
    axes_flat = axes.flatten()
    
    for idx, file_path in enumerate(all_files):
        print(f"Wczytywanie [{idx+1}/{total_files}]: {file_path}")
        
        try:
            spikes_info = Loaders.loadAEDAT(file_path, settings)
            
            plt.sca(axes_flat[idx])
            
            Plots.spikegram(spikes_info, settings)
            
            file_name = os.path.basename(file_path)
            folder_name = os.path.basename(os.path.dirname(file_path))
            plt.title(f"{folder_name}/{file_name}", fontsize=8)
            
        except Exception as e:
            print(f"Error loading {file_path}: {e}")
            axes_flat[idx].text(0.5, 0.5, f'Error: {str(e)[:50]}', 
                               ha='center', va='center', fontsize=8)
            axes_flat[idx].set_title(os.path.basename(file_path), fontsize=8)
    
    for idx in range(total_files, len(axes_flat)):
        axes_flat[idx].axis('off')
    
    plt.tight_layout()
    plt.show()
def compare_spike_folders(file_names, dir_a, dir_b, settings):
    num_files = len(file_names)
    fig, axes = plt.subplots(num_files, 2, figsize=(15, 5 * num_files))
    
    if num_files == 1:
        axes = axes.reshape(1, 2)
        
    for idx, file_name in enumerate(file_names):
        path_a = os.path.normpath(os.path.join(dir_a, file_name))
        file_name_zcu = file_name.replace('.aedat', '.wav.aedat')
        path_b = os.path.normpath(os.path.join(dir_b, file_name_zcu))
        
        if not os.path.exists(path_a) or not os.path.exists(path_b):
            continue
            
        try:
            spikes_a = Loaders.loadAEDAT(path_a, settings)
            spikes_b = Loaders.loadAEDAT(path_b, settings)
            
            count_a = len(spikes_a.timestamps)
            count_b = len(spikes_b.timestamps)
            
            axes[idx, 0].scatter(spikes_a.timestamps, spikes_a.addresses, s=1, c='blue', alpha=0.5, marker='.')
            axes[idx, 0].set_title(f"OK: {file_name} ({count_a} spikes)", fontsize=10)
            axes[idx, 0].set_xlabel("Time (ticks)")
            axes[idx, 0].set_ylabel("Address")
            
            axes[idx, 1].scatter(spikes_b.timestamps, spikes_b.addresses, s=1, c='red', alpha=0.5, marker='.')
            axes[idx, 1].set_title(f"ZCU: {file_name_zcu} ({count_b} spikes)", fontsize=10)
            axes[idx, 1].set_xlabel("Time (ticks)")
            axes[idx, 1].set_ylabel("Address")
            
            max_time = max(np.max(spikes_a.timestamps) if count_a > 0 else 0, 
                           np.max(spikes_b.timestamps) if count_b > 0 else 0)
            if max_time > 0:
                axes[idx, 0].set_xlim(0, max_time)
                axes[idx, 1].set_xlim(0, max_time)
            
            axes[idx, 0].set_ylim(0, 32)
            axes[idx, 1].set_ylim(0, 32)
            
        except Exception:
            axes[idx, 0].text(0.5, 0.5, 'Error', ha='center', va='center')
            axes[idx, 1].text(0.5, 0.5, 'Error', ha='center', va='center')

    plt.tight_layout()
    plt.show()

# ====================================
# TESTING
# ====================================
BLOCKSIZE = 16 * 16
opal.USB_TRANSFER_LENGTH = BLOCKSIZE * 16
opal.USB_BLOCK_SIZE = BLOCKSIZE



# convert_to_aedat("C:/Users/wikto/datasets/gsc_v2/bed/012187a4_nohash_0.wav", "C:/Users/wikto/datasets/gsc_v2_ok/bed/012187a4_nohash_0.aedat", settings)
# time.sleep(0.3)
# convert_to_aedat("C:/Users/wikto/datasets/gsc_v2/forward/0b7ee1a0_nohash_0.wav", "C:/Users/wikto/datasets/gsc_v2_ok/forward/0b7ee1a0_nohash_0.aedat", settings)
# time.sleep(0.3)
# convert_to_aedat("C:/Users/wikto/datasets/gsc_v2/three/0a2b400e_nohash_1.wav", "C:/Users/wikto/datasets/gsc_v2_ok/three/0a2b400e_nohash_1.aedat", settings)
# time.sleep(0.3)
# convert_to_aedat("C:/Users/wikto/datasets/gsc_v2/yes/0a9f9af7_nohash_1.wav", "C:/Users/wikto/datasets/gsc_v2_ok/yes/0a9f9af7_nohash_1.aedat", settings)

# ====================================
# MORE TESTING
# ====================================

# spikes_info_1_1 = Loaders.loadAEDAT("C:/Users/wikto/datasets/gsc_v2_32p_ok/bed/012187a4_nohash_0.aedat", settings)
# spikes_info_1_2 = Loaders.loadAEDAT("C:/Users/wikto/datasets/gsc_v2_32p_zcu/bed/012187a4_nohash_0.wav.aedat", settings)

# spikes_info_2_1 = Loaders.loadAEDAT("C:/Users/wikto/datasets/gsc_v2_32p_ok/three/0a2b400e_nohash_1.aedat", settings)
# spikes_info_2_2 = Loaders.loadAEDAT("C:/Users/wikto/datasets/gsc_v2_32p_zcu/three/0a2b400e_nohash_1.wav.aedat", settings)
# spikes_info_3_1 = Loaders.loadAEDAT("C:/Users/wikto/datasets/gsc_v2_32p_ok/yes/0a9f9af7_nohash_1.aedat", settings)
# spikes_info_3_2 = Loaders.loadAEDAT("C:/Users/wikto/datasets/gsc_v2_32p_zcu/yes/0a9f9af7_nohash_1.wav.aedat", settings)


# spikes_info_1 = Loaders.loadAEDAT("C:/Users/wikto/datasets/gsc_v2_32p_zcu/backward/017c4098_nohash_0.wav.aedat", settings)
# spikes_info_2 = Loaders.loadAEDAT("C:/Users/wikto/datasets/gsc_v2_32p_zcu/backward/017c4098_nohash_1.wav.aedat", settings)
# spikes_info_3 = Loaders.loadAEDAT("C:/Users/wikto/datasets/gsc_v2_32p_zcu/backward/017c4098_nohash_2.wav.aedat", settings)
# spikes_info_4 = Loaders.loadAEDAT("C:/Users/wikto/datasets/gsc_v2_32p_zcu/backward/017c4098_nohash_3.wav.aedat", settings)

# Plots.spikegram(spikes_info_1_1, settings)
# Plots.spikegram(spikes_info_1_2, settings)
# plt.show()
# Plots.spikegram(spikes_info_2_1, settings)
# Plots.spikegram(spikes_info_2_2, settings)
# plt.show()
# Plots.spikegram(spikes_info_3_1, settings)
# Plots.spikegram(spikes_info_3_2, settings)
# plt.show()

# Plots.spikegram(spikes_info_1, settings)
# Plots.spikegram(spikes_info_2, settings)
# Plots.spikegram(spikes_info_3, settings)
# Plots.spikegram(spikes_info_4, settings)
# plt.show()


# DIR_OK = r"C:\Users\wikto\datasets\gsc_v2_32p_ok"
# DIR_ZCU = r"C:\Users\wikto\datasets\gsc_v2_32p_zcu"


# files_to_compare = [
#     "bed/012187a4_nohash_0.aedat",
#     "three/0a2b400e_nohash_1.aedat",
#     "yes/0a9f9af7_nohash_1.aedat"
# ]

# compare_spike_folders(files_to_compare, DIR_OK, DIR_ZCU, settings)

# visualize_converted_results(OUTPUT_DIR, settings, max_files=10)


#visualize_multiple_folders(folder_paths, settings, files_per_folder=3)
# interactive_random_viewer(r"C:\Users\wikto\datasets\gsc_v2_32p_ok_temp\up", settings)

# convertsinewave(100, settings)
file_sweep(BASE_DIR, OUTPUT_DIR, start_folder="backward")