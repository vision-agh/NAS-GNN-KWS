import os
import random
import numpy as np
import sounddevice as sd
import time
from scipy.io import wavfile
import ok
import sys
import struct
import csv

sd.default.samplerate = 48000
sd.default.channels = 1
sd.default.dtype = 'float32'
sd.default.latency = ('high', 'high')
sd.default.blocksize = 2048


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
BIT_FILE = os.path.join(REPO_ROOT, "HW", "vivado", "kws", "kws_system.runs", "impl_1", "ok_top_wrapper.bit")
DATASET_ROOT = "C:/Users/wikto/datasets/gsc_v2"


CSV_DIR = "batch_analysis_all_classes"
STATS_DIR = "stats_all_classes"

WORDS_COMM = [
    "yes", "no", "up", "down", "left",
    "right", "on", "off", "stop", "go", "unknown"
]

CLASSES_TO_TEST = ["down", "up", "go", "no", "yes", "stop", "left", "right", "on", "off"]
NUM_SAMPLES_TO_TEST = 100
CONFIDENCE_THRESHOLD = 170
CAPTURE_WINDOW_S = 2.0

os.makedirs(CSV_DIR, exist_ok=True)
os.makedirs(STATS_DIR, exist_ok=True)

devices = ok.FrontPanelDevices()
dev = devices.Open("")

if dev is None:
    print("Device could not be opened")
    sys.exit(1)

cfg_result = dev.ConfigureFPGA(BIT_FILE)
if cfg_result != 0:
    print(f"FPGA configuration failed, error code {cfg_result}")
    sys.exit(1)
print("FPGA configured successfully.")

dp = dev.GetFPGADataPortClassic()
if dp is None:
    print("Failed to get FPGA Data Port.")
    sys.exit(1)

def run_pipe_inference(wav_path):
    dp.SetWireInValue(0x00, 1, 1)
    dp.UpdateWireIns()
    time.sleep(0.01)
    dp.SetWireInValue(0x00, 0, 1)
    dp.UpdateWireIns()

    dp.SetWireInValue(0x01, 1, 1)
    dp.UpdateWireIns()

    samplerate, audio_data = wavfile.read(wav_path)

    if audio_data.dtype != np.float32:
        audio_data = audio_data.astype(np.float32) / np.iinfo(audio_data.dtype).max
        audio_data = np.clip(audio_data, -1.0, 1.0)

    sd.play(audio_data, samplerate)
    time.sleep(CAPTURE_WINDOW_S)

    dp.SetWireInValue(0x01, 0, 1)
    dp.UpdateWireIns()

    sd.wait()

    frames_to_read = 200
    bytes_per_frame = 16
    read_size = frames_to_read * bytes_per_frame

    buf = bytearray(read_size)
    dp.ReadFromPipeOut(0xA0, buf)

    captured_frames = []

    for i in range(0, read_size, bytes_per_frame):
        chunk = buf[i:i+bytes_per_frame]
        word1, word2, word3, word4 = struct.unpack('<IIII', chunk)

        if word1 == 0 and word2 == 0 and word3 == 0 and word4 == 0:
            continue

        confidence = word4 & 0xFF

        class_scores = [
            (word4 >> 8) & 0xFF,
            (word4 >> 16) & 0xFF,
            (word4 >> 24) & 0xFF,
            word3 & 0xFF,
            (word3 >> 8) & 0xFF,
            (word3 >> 16) & 0xFF,
            (word3 >> 24) & 0xFF,
            word2 & 0xFF,
            (word2 >> 8) & 0xFF,
            (word2 >> 16) & 0xFF,
            (word2 >> 24) & 0xFF
        ]

        captured_frames.append({
            "confidence": confidence,
            "scores": class_scores
        })

    return captured_frames

def write_distribution(f, title, distribution, valid_samples):
    f.write(f"{title}:\n")
    if valid_samples > 0 and distribution:
        sorted_dist = sorted(distribution.items(), key=lambda item: item[1], reverse=True)
        for cls_name, count in sorted_dist:
            percentage = (count / valid_samples) * 100
            f.write(f"  {cls_name}: {count} times ({percentage:.2f}%)\n")
    else:
        f.write("  No valid predictions to distribute.\n")
    f.write("\n")

def analyze_class_batch(target_class, num_samples, confidence_threshold=CONFIDENCE_THRESHOLD):
    class_folder = os.path.join(DATASET_ROOT, target_class)

    if not os.path.exists(class_folder):
        print(f"Error: Directory {class_folder} does not exist.")
        return None

    all_wavs = [f for f in os.listdir(class_folder) if f.endswith('.wav')]
    if len(all_wavs) == 0:
        print(f"No .wav files found in {class_folder}")
        return None

    samples_to_run = random.sample(all_wavs, min(num_samples, len(all_wavs)))
    print(f"\n=======================================================")
    print(f" Starting Batch Analysis: '{target_class}' ({len(samples_to_run)} samples)")
    print(f"=======================================================\n")

    batch_results = []
    top1_distribution = {}
    top2_distribution = {}
    top3_distribution = {}
    valid_frame_counts = []
    zero_valid_sample_count = 0
    error_count = 0
    frames_per_sample = 200
    correct_recognition_count = 0 

    for idx, wav_name in enumerate(samples_to_run):
        wav_path = os.path.join(class_folder, wav_name)
        print(f"[{idx+1}/{len(samples_to_run)}] Processing: {wav_name}...")

        try:
            frames = run_pipe_inference(wav_path)
        except Exception as e:
            print(f"    -> Error processing {wav_name}: {e}")
            batch_results.append([wav_name, 0, "Error", "Error", "Error"])
            error_count += 1
            continue

        high_conf_frames = [f for f in frames if f["confidence"] > confidence_threshold]
        valid_frame_counts.append(len(high_conf_frames))

        if len(high_conf_frames) == 0:
            top_1, top_2, top_3 = "None", "None", "None"
            zero_valid_sample_count += 1
            print(f"    -> Skipped (No frames exceeded {confidence_threshold} confidence)")
        else:
            avg_scores = [0] * 11
            for frame in high_conf_frames:
                for class_idx in range(11):
                    avg_scores[class_idx] += frame["scores"][class_idx]

            avg_scores = [score / len(high_conf_frames) for score in avg_scores]
            ranked_classes = sorted(range(11), key=lambda i: avg_scores[i], reverse=True)

            top_1 = WORDS_COMM[ranked_classes[0]]
            top_2 = WORDS_COMM[ranked_classes[1]]
            top_3 = WORDS_COMM[ranked_classes[2]]

            top1_distribution[top_1] = top1_distribution.get(top_1, 0) + 1
            top2_distribution[top_2] = top2_distribution.get(top_2, 0) + 1
            top3_distribution[top_3] = top3_distribution.get(top_3, 0) + 1

            if top_1 == target_class or (top_1 == "unknown" and top_2 == target_class):
                correct_recognition_count += 1

            print(f"    -> Valid Frames: {len(high_conf_frames)} | Top 1: {top_1} | Top 2: {top_2} | Top 3: {top_3}")

        batch_results.append([wav_name, len(high_conf_frames), top_1, top_2, top_3])
        time.sleep(0.1)

    csv_filename = os.path.join(CSV_DIR, f"batch_analysis_{target_class}.csv")
    with open(csv_filename, mode='w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['Sample Name', 'High-Conf Frames', 'Top 1 Class', 'Top 2 Class', 'Top 3 Class'])
        writer.writerows(batch_results)

    valid_samples = len(samples_to_run) - zero_valid_sample_count - error_count
    accuracy_pct = (correct_recognition_count / valid_samples * 100) if valid_samples > 0 else 0

    avg_valid_frames = sum(valid_frame_counts) / len(valid_frame_counts) if valid_frame_counts else 0
    avg_skipped_frames = frames_per_sample - avg_valid_frames
    total_frames_seen = len(valid_frame_counts) * frames_per_sample
    total_valid_frames = sum(valid_frame_counts)
    total_skipped_frames = total_frames_seen - total_valid_frames
    skip_rate_pct = (total_skipped_frames / total_frames_seen * 100) if total_frames_seen else 0

    stats_filename = os.path.join(STATS_DIR, f"stats_{target_class}.txt")
    with open(stats_filename, mode='w') as f:
        f.write(f"--- Statistics for Class: '{target_class}' ---\n")
        f.write(f"Total samples tested: {len(samples_to_run)}\n")
        f.write(f"Samples with errors: {error_count}\n")
        f.write(f"Samples with zero valid frames: {zero_valid_sample_count}\n")
        f.write(f"Valid samples: {valid_samples}\n\n")
        f.write(f"Correctly recognized samples: {correct_recognition_count}\n")
        f.write(f"Accuracy (Correct / Valid): {accuracy_pct:.2f}%\n\n")
        f.write(f"Frames per sample (raw): {frames_per_sample}\n")
        f.write(f"Average valid frames per sample: {avg_valid_frames:.2f}\n")
        f.write(f"Average skipped frames per sample (confidence <= {confidence_threshold}): {avg_skipped_frames:.2f}\n")
        f.write(f"Frame skip rate: {skip_rate_pct:.2f}%\n\n")

        write_distribution(f, "Top-1 Class Distribution", top1_distribution, valid_samples)
        write_distribution(f, "Top-2 Class Distribution", top2_distribution, valid_samples)
        write_distribution(f, "Top-3 Class Distribution", top3_distribution, valid_samples)

    print(f"\nBatch analysis complete. Results saved to '{csv_filename}'.")
    print(f"Statistics saved to '{stats_filename}'.")

    return {
        "class": target_class,
        "total_tested": len(samples_to_run),
        "valid_samples": valid_samples,
        "correct": correct_recognition_count,
        "accuracy_pct": accuracy_pct
    }

summary_records = []

for target in CLASSES_TO_TEST:
    res = analyze_class_batch(target, NUM_SAMPLES_TO_TEST)
    if res:
        summary_records.append(res)

summary_filename = os.path.join(STATS_DIR, "accuracy_summary.txt")
total_tested_all = sum(r["total_tested"] for r in summary_records)
total_valid_all = sum(r["valid_samples"] for r in summary_records)
total_correct_all = sum(r["correct"] for r in summary_records)
mean_accuracy = (total_correct_all / total_valid_all * 100) if total_valid_all > 0 else 0

with open(summary_filename, mode='w') as f:
    f.write("========================================================================\n")
    f.write(f" ACCURACY SUMMARY REPORT (Threshold: {CONFIDENCE_THRESHOLD}, Samples/Class: {NUM_SAMPLES_TO_TEST})\n")
    f.write("========================================================================\n\n")
    f.write(f"{'Class':<12} | {'Tested':<8} | {'Valid':<8} | {'Correct':<8} | {'Accuracy':<10}\n")
    f.write("-" * 56 + "\n")

    for r in summary_records:
        f.write(f"{r['class']:<12} | {r['total_tested']:<8} | {r['valid_samples']:<8} | {r['correct']:<8} | {r['accuracy_pct']:>7.2f}%\n")

    f.write("-" * 56 + "\n")
    f.write(f"{'TOTAL / MEAN':<12} | {total_tested_all:<8} | {total_valid_all:<8} | {total_correct_all:<8} | {mean_accuracy:>7.2f}%\n")

print("\n" + "=" * 56)
print(f"Overall Accuracy Summary saved to '{summary_filename}'.")
print("=" * 56)