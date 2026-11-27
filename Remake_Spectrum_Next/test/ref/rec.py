#!/usr/bin/env python3
"""
Defender of the Crown (1986) - Spectrum Next remake
Nov 2026 using Claude Opus 5.5

test/ref/rec.py: reads the reference's recordings (ref_sys.c's .REC files:
each change of the Tandy screen, with its time and palette).

  python3 rec.py list OPENING.REC            the screens and their times
  python3 rec.py png OPENING.REC N OUT.png   screen N as a picture
  python3 rec.py sheet OPENING.REC OUT.png   every screen, small, on one sheet
"""
import struct
import sys
import zlib
from pathlib import Path

W, H = 320, 200
RGB16 = [
    (0, 0, 0), (0, 0, 170), (0, 170, 0), (0, 170, 170), (170, 0, 0), (170, 0, 170), (170, 85, 0), (170, 170, 170),
    (85, 85, 85), (85, 85, 255), (85, 255, 85), (85, 255, 255), (255, 85, 85), (255, 85, 255), (255, 255, 85), (255, 255, 255),
]
REC = 8 + 16 + W * H


def read(path):
    d = Path(path).read_bytes()
    assert d[:4] == b"DREC", "not a recording"
    out = []
    for o in range(4, len(d) - REC + 1, REC):
        t = struct.unpack_from("<Q", d, o)[0]
        out.append((t, d[o + 8:o + 24], d[o + 24:o + REC]))
    return out


def rgb(pal, px):
    cols = [RGB16[pal[i] & 15] for i in range(16)]
    return b"".join(bytes(cols[p & 15]) for p in px)


def write_png(path, data, w, h):
    raw = b"".join(b"\0" + data[y * w * 3:(y + 1) * w * 3] for y in range(h))
    ch = lambda t, x: struct.pack(">I", len(x)) + t + x + struct.pack(">I", zlib.crc32(t + x) & 0xFFFFFFFF)
    Path(path).write_bytes(b"\x89PNG\r\n\x1a\n" + ch(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                           + ch(b"IDAT", zlib.compress(raw)) + ch(b"IEND", b""))


def main():
    cmd, path = sys.argv[1], sys.argv[2]
    recs = read(path)
    if cmd == "list":
        prev = None
        for i, (t, pal, px) in enumerate(recs):
            changed = sum(1 for a, b in zip(px, prev) if a != b) if prev else W * H
            print(f"{i:4d} {t / 1e9:8.3f} s  pal {pal.hex()}  {changed:6d} pixels changed")
            prev = px
    elif cmd == "png":
        n = int(sys.argv[3])
        t, pal, px = recs[n]
        write_png(sys.argv[4], rgb(pal, px), W, H)
    elif cmd == "sheet":
        cols, sc = 8, 4                       # every 4th pixel: 80x50 each
        tw, th = W // sc, H // sc
        rows = (len(recs) + cols - 1) // cols
        sheet = bytearray(cols * tw * rows * th * 3)
        for i, (t, pal, px) in enumerate(recs):
            cs = [RGB16[pal[k] & 15] for k in range(16)]
            ox, oy = (i % cols) * tw, (i // cols) * th
            for y in range(th):
                for x in range(tw):
                    c = cs[px[(y * sc) * W + x * sc] & 15]
                    o = ((oy + y) * cols * tw + ox + x) * 3
                    sheet[o:o + 3] = bytes(c)
        write_png(sys.argv[3], bytes(sheet), cols * tw, rows * th)


if __name__ == "__main__":
    main()
