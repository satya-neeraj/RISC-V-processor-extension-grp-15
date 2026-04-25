#!/usr/bin/env python3
# test_div.py  --  Reference for signed 32-bit division using RISC-V semantics.
#    DIV:  a / b (truncated toward zero)
#    REM:  a - (a/b)*b    (same sign as a)
#    Divide by zero: q = -1, r = a

def s32(x): return ((x + (1<<31)) & ((1<<32)-1)) - (1<<31)
def trunc(a, b):
    q = abs(a) // abs(b)
    if (a < 0) ^ (b < 0): q = -q
    r = a - q*b
    return q, r

CASES = [(7,2), (-7,2), (7,-2), (-7,-2), (0,5), (100,1), (1<<31,-1), (5,0), (-5,0)]
print(f"{'a':>12} {'b':>12} {'q':>12} {'r':>12}")
for a, b in CASES:
    if b == 0:
        q = -1; r = a
    else:
        q, r = trunc(a, b)
    print(f"{a:>12d} {b:>12d} {s32(q):>12d} {s32(r):>12d}")
