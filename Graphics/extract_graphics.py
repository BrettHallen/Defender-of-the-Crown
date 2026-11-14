#!/usr/bin/env python3
"""Extract the graphics of both PC versions of Defender of the Crown.

Usage: python3 extract_graphics.py [ORIGINAL_DIR] [OUT_DIR]
  ORIGINAL_DIR defaults to ../Original (with cga/*.LIB and ega/GAME.DAT), OUT_DIR to here.
Writes:
  CGA_DOS/      DOC.EXE's .LIB files: every COMPRESS picture (LIB_nn.png) and a sheet of
                each file's sprites (LIB_sprites.png, numbered by item)
  Booter_CGA/   GAME.DAT's Q files: the booter's CGA pictures (16000 bytes, 2 bits a pixel)
  Booter_EGA/   GAME.DAT's C files: the booter's 16-colour pictures (EGA and Tandy)
  Booter_EGA/sprites/  the EGA build's sprite files (BE BJ BK BL BN BO Bd Bh Bi), one sheet each,
                numbered by item, in the palette of the picture they are shown over
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
# The EGA build's sprite files: a table of word pointers (the item number is the word's index;
# 0 = no item), each item either a "big" sprite (word height, word bytes a row, then planes
# 3, 2, 1, 0) or a slot sprite (4 word pointers to pre-shifted copies, here all the same; the copy:
# byte rows, byte bytes a row, word plane size, the mask (1 = transparent), then planes 3, 2, 1, 0).
SCENE = {'BE': 'CE', 'BJ': 'CJ', 'BK': 'CI', 'BL': 'CK', 'BN': 'CN', 'BO': 'CL', 'Bd': 'CP', 'Bh': 'CR', 'Bi': 'CS'}
def picpal(n):
    r = gamedat.raw(dat, gamedat.directory(dat)[n])
    return [(v & 7) | ((v >> 1) & 8) for v in r[:16]]
def planes_image(d, o, h, bpr, pal, mask=None):
    im = Image.new('RGBA', (bpr * 8, h), (0, 0, 0, 0)); px = im.load(); ps = h * bpr
    for y in range(h):
        for x in range(bpr * 8):
            k = y * bpr + (x >> 3); bit = 7 - (x & 7)
            if mask is not None and (d[mask + k] >> bit) & 1: continue
            c = 0
            for j, pl in enumerate((3, 2, 1, 0)): c |= ((d[o + j * ps + k] >> bit) & 1) << pl
            px[x, y] = RGB16[pal[c]] + (255,)
    return im
def sprite_items(d):
    w = lambda o: struct.unpack('<H', d[o:o + 2])[0]
    first = None; i = 0; items = []
    while 2 * i + 2 <= len(d) and (first is None or 2 * i < first):
        v = w(2 * i)
        if v and (first is None or v < first): first = v
        items.append(v); i += 1
    for k, p in enumerate(items):
        if not p or p + 8 > len(d): continue
        q = [w(p + 2 * j) for j in range(4)]
        if all(first <= x < len(d) for x in q) and d[q[0]] and d[q[0] + 1]:
            yield k, 'slot', q[0]
        else:
            yield k, 'big', p
ds = os.path.join(de, 'sprites'); os.makedirs(ds, exist_ok=True)
for n, pic in SCENE.items():
    d = gamedat.lzw(gamedat.raw(dat, gamedat.directory(dat)[n])); pal = picpal(pic); tiles = []
    for k, kind, o in sprite_items(d):
        if kind == 'slot':
            h, bpr = d[o], d[o + 1]
            if o + 4 + 5 * h * bpr > len(d): continue
            im = planes_image(d, o + 4 + h * bpr, h, bpr, pal, o + 4)
        elif n == 'BL' and k <= 19:
            # the territories' shapes for the map (xor_mask): word height, word bytes a row, word colour, 1 bit a pixel
            h, bpr, col = struct.unpack('<HHH', d[o:o + 6])
            im = Image.new('RGBA', (bpr * 8, h), (0, 0, 0, 0)); px = im.load()
            for y in range(h):
                for x in range(bpr * 8):
                    if (d[o + 6 + y * bpr + (x >> 3)] >> (7 - (x & 7))) & 1: px[x, y] = (255, 255, 255, 255)
        else:
            h, bpr = struct.unpack('<HH', d[o:o + 4])
            if not (0 < h <= 200 and 0 < bpr <= 40) or o + 4 + 4 * h * bpr > len(d): continue
            im = planes_image(d, o + 4, h, bpr, pal)
        bg = Image.new('RGBA', im.size, (60, 60, 90, 255)); bg.alpha_composite(im)
        tiles.append((k, bg.convert('RGB')))
    sprite_sheet(tiles, os.path.join(ds, '%s_in_%s.png' % (n, pic)))
print('GAME.DAT done')
