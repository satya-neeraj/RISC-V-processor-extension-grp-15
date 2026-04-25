#!/usr/bin/env python3
# ==========================================================================
# generate_hex.py  --  Build dmem.hex (weights + input image + zero buffers)
#
# The CPU firmware (main.c) expects this DMEM layout (word offsets from the
# base 0x00010000 -- byte offsets listed below):
#
#   0x00000  INPUT[0..195]   (196 words)
#   0x01000  W1[0..12543]    (12544 words)
#   0x0E000  b1[0..63]       (64 words)
#   0x0E100  H1[0..63]       (64 words)       (workspace, zeros)
#   0x0E200  W2[0..639]      (640 words)
#   0x0EC00  b2[0..9]        (10 words)
#   0x0EC40  SCORES[0..9]    (10 words)       (zeros)
#   0x0EC80  PROBS[0..9]     (10 words)       (zeros)
#
# imem.hex is produced separately by the firmware Makefile (bin_to_hex.py).
#
# Usage:
#   python3 generate_hex.py --digit 7
#       -> picks the digit-7 template, quantizes to Q16.16, writes dmem.hex
# ==========================================================================

import numpy as np
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "..", "data")
MEM  = os.path.join(HERE, "..", "mem")
os.makedirs(MEM, exist_ok=True)

Q = 16  # Q16.16

def q(x):
    return int(round(x * (1 << Q))) & 0xFFFFFFFF


def load_weights():
    path = os.path.join(DATA, "weights.npy")
    if not os.path.exists(path):
        print(f"[!] No weights found at {path}.  Running train_nn.py first...")
        sys.path.insert(0, HERE)
        import train_nn
        train_nn.train()
    d = np.load(path, allow_pickle=True).item()
    return d["W1"], d["b1"], d["W2"], d["b2"]


def load_digit_matrix(digit):
    """Read data/digit_matrix.txt; return the 14x14 float array for the digit.
    The file has 10 blocks labeled '# DIGIT N' each with 14 lines of 14 floats."""
    path = os.path.join(DATA, "digit_matrix.txt")
    with open(path) as f:
        lines = [l.rstrip() for l in f if l.strip()]
    # find block
    idx = None
    for i, l in enumerate(lines):
        if l.strip() == f"# DIGIT {digit}":
            idx = i + 1
            break
    if idx is None:
        raise RuntimeError(f"Digit {digit} not found in {path}")
    block = lines[idx:idx+14]
    return np.array([[float(x) for x in row.split()] for row in block],
                    dtype=np.float32)


def write_dmem_hex(dmem_words, out_path):
    """Write 32-bit hex words, one per line, zero-padded to fill 32K words."""
    SIZE = 32768   # 128 KB / 4
    padded = list(dmem_words) + [0] * (SIZE - len(dmem_words))
    assert len(padded) == SIZE
    with open(out_path, "w") as f:
        for w in padded:
            f.write(f"{w:08x}\n")
    print(f"Wrote {out_path}  ({SIZE} words = 128 KB)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--digit", type=int, default=7)
    args = ap.parse_args()

    W1, b1, W2, b2 = load_weights()
    img = load_digit_matrix(args.digit)
    x   = img.reshape(-1)
    assert x.shape == (196,)

    # Build DMEM as a dense 32K-word array
    SIZE = 32768
    mem  = [0] * SIZE

    # --- INPUT @ 0x00000 / word 0 ---
    for i, v in enumerate(x):
        mem[i] = q(v)

    # --- W1 @ 0x01000 (word 1024) row-major (j, i) order j=0..63, i=0..195 ---
    base = 0x01000 // 4
    for j in range(W1.shape[0]):
        for i in range(W1.shape[1]):
            mem[base + j*W1.shape[1] + i] = q(float(W1[j, i]))

    # --- b1 @ 0x0E000 (word 0x3800) ---
    base = 0x0E000 // 4
    for j in range(b1.shape[0]):
        mem[base + j] = q(float(b1[j]))

    # --- H1 @ 0x0E100 ...zeros... ---

    # --- W2 @ 0x0E200 (word 0x3880) row-major ---
    base = 0x0E200 // 4
    for j in range(W2.shape[0]):
        for i in range(W2.shape[1]):
            mem[base + j*W2.shape[1] + i] = q(float(W2[j, i]))

    # --- b2 @ 0x0EC00 ---
    base = 0x0EC00 // 4
    for j in range(b2.shape[0]):
        mem[base + j] = q(float(b2[j]))

    # --- SCORES, PROBS are zero-initialized by not being written ---

    write_dmem_hex(mem, os.path.join(MEM, "dmem.hex"))

    # Also pretty-print predicted class using float model for sanity
    def relu(v): return np.maximum(v, 0)
    h = relu(W1 @ x + b1)
    s = W2 @ h + b2
    print(f"Float-model prediction: {int(np.argmax(s))}  (asked for digit {args.digit})")


if __name__ == "__main__":
    main()
