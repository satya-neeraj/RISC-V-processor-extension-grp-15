#!/usr/bin/env python3
# ==========================================================================
# bin_to_hex.py  --  Convert firmware.bin to one-word-per-line hex
#                    suitable for $readmemh.
# ==========================================================================

import sys, struct, os

def main():
    if len(sys.argv) != 3:
        print("Usage: bin_to_hex.py <in.bin> <out.hex>"); sys.exit(1)
    in_path, out_path = sys.argv[1], sys.argv[2]
    with open(in_path, "rb") as f:
        data = f.read()
    # pad to multiple of 4
    if len(data) % 4:
        data += b'\x00' * (4 - len(data) % 4)
    words = struct.unpack(f"<{len(data)//4}I", data)

    IMEM_WORDS = 16384   # 64 KB
    pad = IMEM_WORDS - len(words)
    if pad < 0:
        print(f"[!] firmware.bin too big: {len(words)*4} B, IMEM=64 KB"); sys.exit(2)

    with open(out_path, "w") as f:
        for w in words:
            f.write(f"{w:08x}\n")
        for _ in range(pad):
            f.write("00000013\n")   # NOP fill
    print(f"Wrote {out_path}: {len(words)} instruction words + {pad} NOP fill")

if __name__ == "__main__":
    main()
