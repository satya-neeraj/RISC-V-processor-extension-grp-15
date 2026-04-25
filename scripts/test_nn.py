#!/usr/bin/env python3
# test_nn.py  --  Float-model end-to-end NN inference reference.
# Loads weights.npy + data/digit_matrix.txt, runs forward pass, and prints
# predicted digit and softmax probabilities.  Use this to cross-check the
# hardware's PuTTY output against a known-good software implementation.

import numpy as np, os, argparse, sys

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "..", "data")

def load_digit(d):
    with open(os.path.join(DATA, "digit_matrix.txt")) as f:
        lines = [l.rstrip() for l in f if l.strip()]
    i = lines.index(f"# DIGIT {d}") + 1
    rows = [l.split() for l in lines[i:i+14]]
    return np.array(rows, dtype=np.float32).reshape(-1)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--digit", type=int, default=7)
    args = ap.parse_args()

    w = np.load(os.path.join(DATA, "weights.npy"), allow_pickle=True).item()
    x = load_digit(args.digit)

    h = np.maximum(0, w["W1"] @ x + w["b1"])
    s = w["W2"] @ h + w["b2"]
    exp = np.exp(s - s.max())
    p = exp / exp.sum()

    print(f"Digit queried: {args.digit}")
    print(f"PREDICTED DIGIT : {int(p.argmax())}")
    print(f"PROBABILITY     : {p.max():.4f}")
    print("ALL PROBS       :", " ".join(f"{v:.3f}" for v in p))

if __name__ == "__main__":
    main()
