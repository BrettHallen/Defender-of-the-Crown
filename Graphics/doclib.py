"""Readers for the CGA version's .LIB files (Defender of the Crown, DOC.EXE).

A .LIB file is a BASIC BSAVE image: FD, segment, offset, length (words), then `length`
bytes, then a 1A end-of-file byte. The data starts with a word N (the number of items)
and N word offsets, in words from the start of the data (0 = no item). An item is
either a COMPRESS picture (a full 320x200 screen, see decompress) or a sprite:
word width in bits (2 bits a pixel), word height in lines, then height rows of
ceil(width/8) bytes (CGA 2bpp, leftmost pixel in the top bits)."""
import struct

def read_lib(path):
    d = open(path, 'rb').read()
    assert d[0] == 0xFD
    seg, off, ln = struct.unpack('<HHH', d[1:7])
    p = d[7:7 + ln]
    n = struct.unpack('<H', p[:2])[0]
    offs = struct.unpack('<%dH' % n, p[2:2 + 2 * n])
    items = []
    starts = sorted(set(o * 2 for o in offs if o)) + [ln]
    for o in offs:
        if not o:
            items.append(None); continue
        b = o * 2
        e = starts[starts.index(b) + 1]
        items.append(p[b:e])
    return items

def decompress(item):
    """DOC.EXE 0946:0000. Returns 200 rows of 80 bytes (CGA 2bpp, row order 0..199).
    Codes: c < 80h: c+1 literal pixels, taken 2 bits at a time (high bits first) from
    literal bytes in the stream; a partly used literal byte carries over to the next
    literal code. c >= 80h: a run of one colour (c & 3), count (c >> 2) & 0Fh, or with
    bit 6 set ((c >> 2) & 0Fh) * 256 + the next byte; the run is count + 1 pixels."""
    assert item[:8] == b'COMPRESS'
    src = item; si = 8
    out = bytearray(); acc = 0; npx = 0
    lit = 0; left = 0
    total = 320 * 200
    def put(px):
        nonlocal acc, npx
        acc = ((acc << 2) | px) & 0xFF; npx += 1
        if npx % 4 == 0:
            out.append(acc); acc = 0
    while len(out) < 16000 and si < len(src):
        c = src[si]; si += 1
        if c < 0x80:
            for _ in range(c + 1):
                if left == 0:
                    lit = src[si]; si += 1; left = 4
                left -= 1
                put((lit >> (2 * left)) & 3)
                if len(out) >= 16000: break
        else:
            col = c & 3
            cnt = (c >> 2) & 0x0F
            if c & 0x40:
                cnt = cnt * 256 + src[si]; si += 1
            for _ in range(cnt + 1):
                put(col)
                if len(out) >= 16000: break
    return [bytes(out[r * 80:(r + 1) * 80]) for r in range(200)], si

def sprite(item):
    wbits, h = struct.unpack('<HH', item[:4])
    bpr = (wbits + 7) // 8
    rows = [item[4 + r * bpr:4 + (r + 1) * bpr] for r in range(h)]
    return wbits // 2, h, rows

# CGA palettes: (background chosen by the game) + 3 colours
RGB16 = [(0,0,0),(0,0,170),(0,170,0),(0,170,170),(170,0,0),(170,0,170),(170,85,0),(170,170,170),
         (85,85,85),(85,85,255),(85,255,85),(85,255,255),(255,85,85),(255,85,255),(255,255,85),(255,255,255)]
PAL = {"0lo": [2, 4, 6], "0hi": [10, 12, 14], "1lo": [3, 5, 7], "1hi": [11, 13, 15]}  # CGA mode 4 palettes (colours 1-3)

def to_image(rows, wpx, pal, bg=0):
    from PIL import Image
    cols = [RGB16[bg]] + [RGB16[c] for c in PAL[pal]]
    im = Image.new('RGB', (wpx, len(rows)))
    px = im.load()
    for y, r in enumerate(rows):
        for x in range(wpx):
            b = r[x // 4] if x // 4 < len(r) else 0
            px[x, y] = cols[(b >> (6 - 2 * (x % 4))) & 3]
    return im
