#!/usr/bin/env python3
# ==========================================================================
# train_nn.py  --  Offline training of a small MLP (196 -> 64 -> 10)
#                  with ReLU hidden activation.
#
# Input: flattened 14x14 digit images (196 features, normalized to [0,1]).
# Target: one-hot 10-class labels (digits 0..9).
#
# Outputs:
#   data/weights.npy  -- dict { 'W1': (64,196), 'b1': (64,), 'W2': (10,64), 'b2': (10,) }
#   data/bias.npy     -- same as above for convenience (one-file fallback)
#
# This script does NOT require MNIST.  It builds a tiny synthetic "digit
# matrix" dataset (10 template images one per class, plus noisy augmentations)
# so the full pipeline can be demonstrated end-to-end on the Nexys A7
# without internet access or external datasets.
# ==========================================================================

import numpy as np
import os

np.random.seed(0)

INPUT  = 196
HIDDEN = 64
OUTPUT = 10
EPOCHS = 400
LR     = 0.05

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "..", "data")
os.makedirs(DATA, exist_ok=True)


def build_templates():
    """Hand-drawn 14x14 templates for digits 0..9 (1.0 ink, 0.0 bg)."""
    t = np.zeros((10, 14, 14), dtype=np.float32)

    # Digit 0 -- ring
    t[0, 2:12, 3] = 1;  t[0, 2:12, 10] = 1
    t[0, 2, 3:11] = 1;  t[0, 11, 3:11] = 1

    # Digit 1 -- vertical line
    t[1, 2:12, 7] = 1;  t[1, 3, 6] = 1;  t[1, 11, 5:10] = 1

    # Digit 2 -- top curve + diagonal + bottom bar
    t[2, 2, 4:10] = 1;  t[2, 3:6, 10] = 1
    t[2, 6, 4:10] = 1
    for i in range(5): t[2, 7+i, 9-i] = 1
    t[2, 11, 3:11] = 1

    # Digit 3 -- E mirrored
    t[3, 2, 3:10] = 1;  t[3, 6, 4:10] = 1;  t[3, 11, 3:10] = 1
    t[3, 2:7, 10] = 1;  t[3, 7:12, 10] = 1

    # Digit 4 -- two verticals + bar
    t[4, 2:8, 4] = 1;  t[4, 2:12, 10] = 1;  t[4, 7, 4:11] = 1

    # Digit 5 -- top bar, left side, middle, bottom curve
    t[5, 2, 3:11] = 1;  t[5, 3:7, 3] = 1;   t[5, 7, 3:11] = 1
    t[5, 8:11, 10] = 1;  t[5, 11, 3:10] = 1

    # Digit 6 -- like 5 with full lower ring
    t[6, 2, 4:10] = 1;   t[6, 3:11, 3] = 1;  t[6, 7, 3:10] = 1
    t[6, 11, 4:10] = 1;  t[6, 8:11, 10] = 1

    # Digit 7 -- top bar + diagonal
    t[7, 2, 3:11] = 1
    for i in range(9): t[7, 3+i, 10-i//1] = 1

    # Digit 8 -- two stacked rings
    t[8, 2, 4:10] = 1;   t[8, 6, 4:10] = 1;  t[8, 11, 4:10] = 1
    t[8, 3:6, 3] = 1;    t[8, 7:11, 3] = 1
    t[8, 3:6, 10] = 1;   t[8, 7:11, 10] = 1

    # Digit 9 -- ring + tail
    t[9, 2, 4:10] = 1;   t[9, 6, 4:10] = 1;  t[9, 3:6, 3] = 1
    t[9, 3:11, 10] = 1;  t[9, 11, 4:10] = 1
    return t


def make_dataset(n_per_class=200, noise=0.15):
    templates = build_templates()
    X, Y = [], []
    for c in range(10):
        for _ in range(n_per_class):
            img = templates[c] + np.random.randn(14, 14) * noise
            img = np.clip(img, 0, 1)
            X.append(img.reshape(-1))
            Y.append(c)
    X = np.array(X, dtype=np.float32)
    Y = np.array(Y, dtype=np.int64)
    idx = np.random.permutation(len(X))
    return X[idx], Y[idx], templates


def one_hot(y, k=10):
    o = np.zeros((len(y), k), dtype=np.float32)
    o[np.arange(len(y)), y] = 1
    return o


def relu(x): return np.maximum(x, 0)
def drelu(x): return (x > 0).astype(np.float32)


def train():
    X, Y, templates = make_dataset()
    Yh = one_hot(Y)

    # Xavier init
    W1 = np.random.randn(HIDDEN, INPUT)  * np.sqrt(2.0 / INPUT)
    b1 = np.zeros(HIDDEN, dtype=np.float32)
    W2 = np.random.randn(OUTPUT, HIDDEN) * np.sqrt(2.0 / HIDDEN)
    b2 = np.zeros(OUTPUT, dtype=np.float32)

    for ep in range(EPOCHS):
        # forward
        z1 = X @ W1.T + b1
        h1 = relu(z1)
        z2 = h1 @ W2.T + b2
        # softmax for loss only
        exp = np.exp(z2 - z2.max(axis=1, keepdims=True))
        p = exp / exp.sum(axis=1, keepdims=True)

        # backward
        dz2 = (p - Yh) / len(X)
        dW2 = dz2.T @ h1
        db2 = dz2.sum(axis=0)
        dh1 = dz2 @ W2
        dz1 = dh1 * drelu(z1)
        dW1 = dz1.T @ X
        db1 = dz1.sum(axis=0)

        W1 -= LR * dW1; b1 -= LR * db1
        W2 -= LR * dW2; b2 -= LR * db2

        if (ep + 1) % 50 == 0:
            acc = (p.argmax(axis=1) == Y).mean()
            print(f"  epoch {ep+1:3d}: acc = {acc:.3f}")

    # sanity check on templates
    probe = templates.reshape(10, -1)
    z1 = probe @ W1.T + b1;  h1 = relu(z1)
    z2 = h1 @ W2.T + b2
    print("Template predictions:", z2.argmax(axis=1))

    np.save(os.path.join(DATA, "weights.npy"),
            {"W1": W1.astype(np.float32),
             "b1": b1.astype(np.float32),
             "W2": W2.astype(np.float32),
             "b2": b2.astype(np.float32)},
            allow_pickle=True)
    np.save(os.path.join(DATA, "bias.npy"),
            {"b1": b1.astype(np.float32),
             "b2": b2.astype(np.float32)},
            allow_pickle=True)
    print(f"\nSaved weights to {DATA}/weights.npy  and biases to {DATA}/bias.npy")
    return W1, b1, W2, b2, templates


if __name__ == "__main__":
    train()
