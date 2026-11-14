#!/usr/bin/env python3
"""Lists the joust's outcome scripts (BJ items 37-40, played by AB's joust_outcome 6C59 over the
stands picture CJ).

Usage: joust_scripts.py BJ.bin   (BJ unpacked from GAME.DAT, e.g. with ../../Graphics/gamedat.py)

A script is a list of frames of two knights, 4 bytes each: BJ item - 20, rows to draw (the rest of
the sprite is cut off at the bottom, behind the barrier), x (4-pixel units), y. A knight whose y is
0 is gone for the rest of the script; the script ends when an x is over 80. Each frame is drawn
with sprites_draw and present_bottom, with two gallop beeps (the divisor at DS:0065 falls by 500
a beep from 30000, back to 30000 below 28500)."""
import struct, sys
NAMES = {37: 'near miss', 38: 'opponent unhorsed', 39: 'player unhorsed', 40: 'the horse hit (disgrace)'}
d = open(sys.argv[1], 'rb').read()
for k in range(37, 41):
    o = struct.unpack('<H', d[2 * k:2 * k + 2])[0]
    live = [True, True]; frames = []
    while o + 8 <= len(d):
        f = []; end = False
        for n in range(2):
            if not live[n]: f.append(None); continue
            item, rows, x, y = d[o] + 20, d[o + 1], d[o + 2], d[o + 3]; o += 4
            if x > 80: end = True; break
            f.append((item, rows, x, y))
            if y == 0: live[n] = False
        if end: break
        frames.append(f)
    print('Item %d (%s): %d frames' % (k, NAMES[k], len(frames)))
    for i, f in enumerate(frames):
        print('  %3d  ' % i + '   '.join('-' if a is None else 'item %2d rows %2d at (%2d, %3d)' % a for a in f))
