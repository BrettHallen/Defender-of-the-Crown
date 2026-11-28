#!/usr/bin/env python3
"""
Defender of the Crown (1986) - Spectrum Next remake
Nov 2026 using Claude Opus 5.5
"Guided" by Brett Hallen

syms.py: the program's labels (zxbasm's map of main.asm) as EQUs, for its
overlays (src/ov_*.asm) to call it by name.

Usage: python3 syms.py main.map main_syms.asm
"""
import sys
from pathlib import Path


def main():
    out = ["; the program's labels (tools/syms.py, from main.asm's map): for the overlays"]
    for line in Path(sys.argv[1]).read_text().splitlines():
        addr, _, name = line.partition(": ")
        name = name.strip().lstrip(".")
        if name and "." not in name:
            out.append(f"{name} EQU ${addr.strip()}")
    Path(sys.argv[2]).write_text("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
