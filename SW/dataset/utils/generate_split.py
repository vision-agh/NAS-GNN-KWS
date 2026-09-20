#!/usr/bin/env python3
"""Generate testing_list.txt / validation_list.txt for a GSC-style dataset.

Expects a <dataset_root>/<class>/<file> layout (one subfolder per word/class,
as in gsc_v2_32p_ok, vox-gscd, vox-combine, ...). Performs a per-file random
split (files are not grouped by speaker), matching the behavior observed in
vox-gscd's existing split lists. Whatever is left unlisted is implicitly the
training set (train_kws.py treats any file not in testing/validation as train).

Usage:
    python generate_split.py /path/to/dataset_root [--test-pct 10] [--val-pct 10] [--seed 42]
"""
import argparse
import random
from pathlib import Path


def collect_files(dataset_root: Path):
    files = []
    for class_dir in sorted(p for p in dataset_root.iterdir() if p.is_dir()):
        for f in sorted(class_dir.iterdir()):
            if f.is_file():
                files.append(f"{class_dir.name}/{f.name}")
    return files


def split(files, test_pct, val_pct, seed):
    rng = random.Random(seed)
    shuffled = files[:]
    rng.shuffle(shuffled)

    n = len(shuffled)
    n_test = round(n * test_pct / 100)
    n_val = round(n * val_pct / 100)

    test = sorted(shuffled[:n_test])
    val = sorted(shuffled[n_test:n_test + n_val])
    # remainder is training, left implicit (not written to any file)
    return test, val


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("dataset_root", type=Path)
    parser.add_argument("--test-pct", type=float, default=10.0, help="Percent of files to hold out for testing")
    parser.add_argument("--val-pct", type=float, default=10.0, help="Percent of files to hold out for validation")
    parser.add_argument("--seed", type=int, default=42, help="Random seed for reproducibility")
    parser.add_argument("--testing-list-name", default="testing_list.txt")
    parser.add_argument("--validation-list-name", default="validation_list.txt")
    args = parser.parse_args()

    files = collect_files(args.dataset_root)
    if not files:
        raise SystemExit(f"No class folders/files found under {args.dataset_root}")

    test, val = split(files, args.test_pct, args.val_pct, args.seed)

    test_path = args.dataset_root / args.testing_list_name
    val_path = args.dataset_root / args.validation_list_name

    test_path.write_text("\n".join(test) + "\n")
    val_path.write_text("\n".join(val) + "\n")

    n = len(files)
    n_train = n - len(test) - len(val)
    print(f"Total files: {n}")
    print(f"Testing:    {len(test):5d} ({100 * len(test) / n:5.2f}%) -> {test_path}")
    print(f"Validation: {len(val):5d} ({100 * len(val) / n:5.2f}%) -> {val_path}")
    print(f"Training:   {n_train:5d} ({100 * n_train / n:5.2f}%) [implicit, not written]")


if __name__ == "__main__":
    main()
