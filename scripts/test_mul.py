#!/usr/bin/env python3
# test_mul.py  --  Behavioral reference for 32x32 signed multiply used to
#                  verify tb_mul.v results.  Prints test vectors.

def s32(x): return ((x + (1<<31)) & ((1<<32)-1)) - (1<<31)
def u32(x): return x & ((1<<32)-1)

CASES = [
    (0, 0), (1, 1), (-1, -1), (1, -1), (-1, 1),
    (12345, 6789),
    (0x7FFFFFFF, 2), (-0x80000000, 2),
    (1<<15, 1<<15), (-(1<<15), 1<<15),
    (0xCAFEBABE - (1<<32), 0x12345678),   # signed negative vs positive
    (0x00010000, 0x00010000),             # Q16.16 1.0 * 1.0 (low 32 bits = 0)
    (0x00018000, 0x00018000),             # 1.5 * 1.5 (Q16.16), low32 = 0x40000 (2.25*65536)
]

print(f"{'a':>11} {'b':>11} {'expected_low32':>16}")
for a, b in CASES:
    prod = s32(a) * s32(b)
    low32 = u32(prod)
    print(f"{s32(a):>11d} {s32(b):>11d} {low32:>16d}  (0x{low32:08X})")
