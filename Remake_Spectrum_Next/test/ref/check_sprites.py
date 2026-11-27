#!/usr/bin/env python3
"""
Defender of the Crown (1986) - Spectrum Next remake
Nov 2026 using Claude Opus 5.5

test/ref/check_sprites.py: the converter's decoding of the Tandy sprite files
(tools/convert.py tandy_sprites) against the Mac remake's own (dump_tandy's
dump of Remake/src/assets.c's), item by item.

Usage: python3 check_sprites.py GAME.DAT TANDY_SPRITES.BIN
"""
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
import convert as C                     # noqa: E402

dat = Path(sys.argv[1]).read_bytes()
d = Path(sys.argv[2]).read_bytes()
assert d[:4] == b"DSPR"
ref = {}
o = 4
while o < len(d):
    f, i, kind = d[o], d[o + 1], d[o + 2]
    w, h, ox, oy, adv = struct.unpack_from("<5h", d, o + 3)
    hm = d[o + 13]
    o += 14
    pix = d[o:o + w * h]
    o += w * h
    mask = None
    if hm:
        mask = d[o:o + w * h]
        o += w * h
    ref[(f, i)] = (kind, w, h, ox, oy, adv, pix, mask)
mine = C.tandy_sprites(dat)
bad = 0
for k in sorted(set(ref) | {(f, i) for f in mine for i in mine[f]}):
    r, m = ref.get(k), mine.get(k[0], {}).get(k[1])
    if r is None or m is None:
        print("only in", "the remake's" if m is None else "the converter's", k)
        bad += 1
        continue
    kind, w, h, ox, oy, adv, pix, mask = r
    if (kind, w, h, adv) != (m.kind, m.w, m.h, m.adv if m.kind == C.IT_GLYPH else 0) or ox or oy \
       or bytes(m.pix) != pix or (bytes(m.mask) if m.mask is not None else None) != mask:
        print("differs", k)
        bad += 1
print(f"{len(ref)} images in the remake's decoding; {bad} differences")
sys.exit(1 if bad else 0)
