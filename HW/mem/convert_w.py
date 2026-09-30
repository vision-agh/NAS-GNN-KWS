import os

INPUT_FILE = "conv4.mem"
OUTPUT_B = "conv4_b.mem"
OUTPUT_W = "conv4_w.mem"

# wczytaj dane
with open(INPUT_FILE, "r") as f:
    lines = [line.strip() for line in f]

if len(lines) != 648:
    raise ValueError("Plik conv3.mem musi mieć dokładnie 648 linii")

out_b = []
out_w = []

# przetwarzanie co 9 linii
for i in range(0, 648, 9):
    merged = "".join(lines[i:i+9])

    # ostatnie 8 znaków (32-bit HEX)
    out_b.append(merged[-8:])

    # reszta bez zmian
    out_w.append(merged[:-8])

# zapis conv2_b.mem
with open(OUTPUT_B, "w") as f:
    for line in out_b:
        f.write(line + "\n")

# zapis conv2_w.mem
with open(OUTPUT_W, "w") as f:
    for line in out_w:
        f.write(line + "\n")

print("Gotowe:")
print(" - conv4_b.mem: 72 linie (ostatnie 8 znaków)")
print(" - conv4_w.mem: 72 linie (reszta, bez zmian)")
