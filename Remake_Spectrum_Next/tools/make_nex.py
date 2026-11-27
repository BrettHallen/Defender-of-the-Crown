#!/usr/bin/env python3
"""
Defender of the Crown (1986) - Spectrum Next remake
Nov 2026 using Claude Opus 5.5
"Guided" by Brett Hallen

make_nex.py: packs the assembled program and its data into a .nex file (the
Next's own program format, V1.2), which NextZXOS's browser runs and
emulators load directly. The pictures stay on the SD card, beside it, and
the program loads them.

  CODE.BIN    the program, assembled at A000h (src/main.asm): pages 5 and 0
              (the upper half of bank 2 and the lower of bank 0, where the
              .nex loader puts them at A000h-DFFFh)
  PAGE:FILE   a file from 8K page PAGE on (the data segment, the music, the
              sprite files: see src/main.asm)

Usage: python3 make_nex.py CODE.BIN OUT.NEX [PAGE:FILE ...]
"""
import struct
import sys
from pathlib import Path

ORG = 0xA000
PAGE = 8192
BANK = 16384
ORDER = [5, 2, 0, 1, 3, 4] + list(range(6, 112))   # the order banks are stored in


def main():
    if len(sys.argv) < 3:
        raise SystemExit("usage: make_nex.py CODE.BIN OUT.NEX [PAGE:FILE ...]")
    code = Path(sys.argv[1]).read_bytes()
    if len(code) > ORG and not any(code[:ORG]):   # zxbasm can write the image from address 0
        code = code[ORG:]
    if ORG + len(code) > 0xE000:
        raise SystemExit(f"the program reaches {ORG + len(code):04X}h: past its pages")

    pages = {}
    mem = code.ljust(2 * PAGE, b"\0")           # A000h-DFFFh
    pages[5] = mem[:PAGE]
    pages[0] = mem[PAGE:]
    for arg in sys.argv[3:]:
        first, name = arg.split(":", 1)
        data = Path(name).read_bytes()
        for k in range(0, len(data), PAGE):
            p = int(first) + k // PAGE
            if p in pages:
                raise SystemExit(f"page {p} is taken twice")
            pages[p] = data[k:k + PAGE].ljust(PAGE, b"\0")
    banks = {}
    for p, d in pages.items():
        b = banks.setdefault(p // 2, bytearray(BANK))
        b[(p & 1) * PAGE:(p & 1) * PAGE + PAGE] = d

    h = bytearray(512)
    h[0:4] = b"Next"
    h[4:8] = b"V1.2"
    h[8] = 0                                    # 768K is enough
    h[9] = len(banks)
    h[10] = 0                                   # no loading screen
    h[11] = 0                                   # black border
    struct.pack_into("<HH", h, 12, 0xDE00, ORG)  # SP (the program sets its own), PC
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
