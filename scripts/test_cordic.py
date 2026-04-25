#!/usr/bin/env python3
# test_cordic.py  --  Reference values for CORDIC unit (Q16.16).
import math

def q(x): return int(round(x * (1 << 16))) & 0xFFFFFFFF
CASES = [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, -0.5, -0.9]

print(f"{'x':>8} {'atan':>10} {'asin':>10} {'acos':>10}   Q16.16 hex")
for x in CASES:
    a = math.atan(x); s = math.asin(x); c = math.acos(x)
    print(f"{x:>8.4f} {a:>10.4f} {s:>10.4f} {c:>10.4f}   "
          f"0x{q(a):08X}  0x{q(s):08X}  0x{q(c):08X}")
