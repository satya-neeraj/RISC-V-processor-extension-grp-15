#!/usr/bin/env python3
# test_mac.py  --  Python reference for the Q16.16 MAC unit.
# Q16.16 accumulator is really Q32.32 internally; readback returns bits
# [47:16] with saturation.
#
# Cases verify 1-2 accumulations and readback.

def q(x): return int(round(x * (1 << 16))) & 0xFFFFFFFF
def s32(x): return ((x + (1<<31)) & ((1<<32)-1)) - (1<<31)

def mac_ref(pairs):
    acc = 0  # Q32.32
    for a, b in pairs:
        acc += a * b   # Q16.16 * Q16.16 = Q32.32
    # readback: bits [47:16]
    v = (acc >> 16) & 0xFFFFFFFF
    # saturate
    if acc >> 63:      # negative
        return s32(v) if v >= 0x80000000 else -0x80000000   # simplified
    return v if v < 0x80000000 else 0x7FFFFFFF

CASES = [
    [(q(1.0), q(1.0))],
    [(q(1.5), q(2.0))],                          # 3.0
    [(q(0.5), q(0.5)), (q(0.25), q(1.0))],       # 0.25 + 0.25 = 0.5
    [(q(-1.0), q(2.0)), (q(1.0), q(1.0))],       # -1.0
]
for i, p in enumerate(CASES):
    r = mac_ref(p)
    print(f"case {i}: pairs={[(hex(a), hex(b)) for a,b in p]}  acc_q16_16=0x{r:08X} ({r/(1<<16):.4f})")
