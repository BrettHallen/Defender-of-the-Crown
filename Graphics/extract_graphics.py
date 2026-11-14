#!/usr/bin/env python3
"""Extract the graphics of both PC versions of Defender of the Crown.

Usage: python3 extract_graphics.py [ORIGINAL_DIR] [OUT_DIR]
  ORIGINAL_DIR defaults to ../Original (with cga/*.LIB and ega/GAME.DAT), OUT_DIR to here.
Writes:
  CGA_DOS/      DOC.EXE's .LIB files: every COMPRESS picture (LIB_nn.png) and a sheet of
                each file's sprites (LIB_sprites.png, numbered by item)
  Booter_CGA/   GAME.DAT's Q files: the booter's CGA pictures (16000 bytes, 2 bits a pixel)
  Booter_EGA/   GAME.DAT's C files: the booter's 16-colour pictures (EGA and Tandy)
CGA pictures are drawn in palette 0 low intensity (green, red, brown) on black, as both
programs set it (DOC.EXE 070A:01B3; checked in DOSBox for both versions' title)."""
import os, sys, glob, struct
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
import doclib, gamedat
from PIL import Image, ImageDraw

RGB16 = doclib.RGB16
src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, '..', 'Original')
out = sys.argv[2] if len(sys.argv) > 2 else here
PAL = '0lo'

def sprite_sheet(tiles, path):
    W = 640; x = y = rowh = 0; pos = []
    for i, im in tiles:
        im2 = im.resize((im.width * 2, im.height * 2), Image.NEAREST)
        if x + im2.width > W: x = 0; y += rowh + 14; rowh = 0
        pos.append((x, y, i, im2)); x += im2.width + 6; rowh = max(rowh, im2.height)
    sheet = Image.new('RGB', (W, y + rowh + 14), (60, 60, 90)); dr = ImageDraw.Draw(sheet)
    for x, y, i, im in pos:
        dr.text((x, y), str(i), fill=(255, 255, 0)); sheet.paste(im, (x, y + 11))
    sheet.save(path)

# DOC.EXE's .LIB files
d = os.path.join(out, 'CGA_DOS'); os.makedirs(d, exist_ok=True)
for f in sorted(glob.glob(os.path.join(src, 'cga', '*.LIB'))):
    name = os.path.basename(f)[:-4]
    tiles = []
    for i, it in enumerate(doclib.read_lib(f)):
        if not it: continue
        if it[:8] == b'COMPRESS':
            rows, _ = doclib.decompress(it)
            doclib.to_image(rows, 320, PAL).save(os.path.join(d, '%s_%02d.png' % (name, i)))
            continue
        w, h = struct.unpack('<HH', it[:4])
        if w == 0 or h == 0 or 4 + (w + 7) // 8 * h > len(it): continue   # not a sprite (tables)
        wp, h, rows = doclib.sprite(it)
        tiles.append((i, doclib.to_image(rows, wp, PAL)))
    if tiles: sprite_sheet(tiles, os.path.join(d, '%s_sprites.png' % name))
    print(name, 'done')

# GAME.DAT
dat = open(os.path.join(src, 'ega', 'GAME.DAT'), 'rb').read()
dq = os.path.join(out, 'Booter_CGA'); de = os.path.join(out, 'Booter_EGA')
os.makedirs(dq, exist_ok=True); os.makedirs(de, exist_ok=True)
for n, e in sorted(gamedat.directory(dat).items()):
    r = gamedat.raw(dat, e)
    if n[0] == 'Q':
        u = gamedat.lzw(r)
        doclib.to_image([u[y * 80:(y + 1) * 80] for y in range(200)], 320, PAL).save(os.path.join(dq, n + '.png'))
    elif n[0] == 'C' and not gamedat.is_lzw(r):
        pal = [(v & 7) | ((v >> 1) & 8) for v in r[:16]]
        u = gamedat.lzw(r[16:])
        im = Image.new('P', (320, 200)); im.putpalette([v for c in RGB16 for v in c])
        pix = bytearray(64000)
        for y in range(200):
            for x in range(320):
                o = y * 40 + (x >> 3); bit = 7 - (x & 7); c = 0
                for pl in range(4): c |= ((u[o + pl * 8000] >> bit) & 1) << pl
                pix[y * 320 + x] = pal[c]
        im.putdata(pix); im.save(os.path.join(de, n + '.png'))
print('GAME.DAT done')
