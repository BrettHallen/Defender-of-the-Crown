#!/usr/bin/env python3
"""
Defender of the Crown (1986) - Spectrum Next remake
Nov 2026 using Claude Opus 5.5
"Guided" by Brett Hallen

make_nex.py: packs the assembled program (with the music, which it includes)
into a .nex file (the Next's own program format, V1.2), which NextZXOS's
browser runs and emulators load directly. The pictures stay on the SD card,
beside it, and the program loads them.

  CODE.BIN  the program, assembled at 8000h: loaded into banks 2 and 0
            (8000h-BFFFh and C000h-FFFFh)

Usage: python3 make_nex.py CODE.BIN OUT.NEX
"""
import struct
import sys
from pathlib import Path

ORG = 0x8000
BANK = 16384
ORDER = [5, 2, 0, 1, 3, 4] + list(range(6, 112))   # the order banks are stored in


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: make_nex.py CODE.BIN OUT.NEX")
    code = Path(sys.argv[1]).read_bytes()
    if len(code) > ORG and not any(code[:ORG]):   # zxbasm can write the image from address 0
        code = code[ORG:]
    if ORG + len(code) > 0xFF00:
        raise SystemExit(f"the program reaches {ORG + len(code):04X}h: no room left for the stack")

    banks = {}
    mem = code.ljust(2 * BANK, b"\0")          # 8000h-FFFFh
    banks[2] = mem[:BANK]
    banks[0] = mem[BANK:]

    h = bytearray(512)
    h[0:4] = b"Next"
    h[4:8] = b"V1.2"
    h[8] = 0                                    # 768K is enough
    h[9] = len(banks)
    h[10] = 0                                   # no loading screen
    h[11] = 0                                   # black border
    struct.pack_into("<HH", h, 12, 0x0000, ORG)  # SP (the program sets its own), PC
    for b in banks:
        h[18 + b] = 1
    h[134] = 0                                  # reset the Next registers
    h[135:138] = bytes([3, 1, 5])               # core 3.1.5 or later (Layer 2 320x256, the CTC)
    h[139] = 0                                  # bank 0 at C000h
    out = bytearray(h)
    for b in ORDER:
        if b in banks:
            out += banks[b]
    Path(sys.argv[2]).write_bytes(out)
    print(f"{sys.argv[2]}: {len(out)} bytes, banks {sorted(banks)}, program {len(code)} bytes at {ORG:04X}h")


if __name__ == "__main__":
    main()
