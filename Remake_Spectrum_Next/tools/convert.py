#!/usr/bin/env python3
"""
Defender of the Crown (1986) - Spectrum Next remake
Nov 2026 using Claude Opus 5.5
"Guided" by Brett Hallen
Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)

convert.py: turns the booter's Tandy 1000 pictures and music
(from your own GAME.DAT) into files for the Next, so no original artwork or
music is kept in the repository.

  sd/DOTC/DOTC_GFX/CA.PIC ... CT.PIC
              the 20 Tandy pictures (C pictures A-T, as the Mac remake's
              PIC_SCROLL ... PIC_WINDOW), for the SD card, in four 8K pages
              (pic_file): the 160 pairs of columns, 40 to a page, each 200
              bytes (a row each: the even column's pixel in the high nibble,
              the odd one's in the low), and the 16 palette registers (each
              one of the Tandy's 16 colours) at 1F40h in the last page
  preview/CA.png ... CT.png
              previews of the pictures as the Next will show them (colours
              rounded to the Next's 9-bit palette)
  rgb16.bin   the Tandy's 16 colours as the Next's (NextReg 44h's two bytes each)
  ds.bin      the data segment (BH: the game's texts, tables and variables),
              24K, as the Next keeps it at 4000h-9FFFh
  spr_font.bin, spr_chars.bin
              the Tandy font and box pieces (BC) and the character-choice name
              boxes (BF) in the Next's sprite format (sprite_blob below)
  speaker.bin the PC-speaker tunes' note lengths (BB items 97h-9Eh): the game
              times itself by them in every mode, under the Tandy music
  bg.bin      the Tandy music (BG), for the Next's port of the original's
              driver (src/tandy.asm)
  ay_period.bin  1024 words: the AY period for each Tandy tone register
  ay_volume.bin  16 bytes: the AY volume for each Tandy attenuation

It follows the Mac remake: GAME.DAT's directory and LZW (Remake/src/dat.c),
and the C pictures and the Tandy palette mapping (assets.c picture_16). The
Tandy class below is the music driver (sound.c, AC 7444-7C53) in Python: the
test (test/run_nex.py) runs it beside the Next's Z80 port to check it.

Usage: python3 convert.py GAME.DAT OUTPUT-FOLDER
"""
import struct
import sys
import zlib
from pathlib import Path

DISK_SIZE = 0x5A000
SCREEN_W, SCREEN_H = 320, 200
TOP = 28                       # 320x200 centred in 256 lines
PICTURES = 20                  # CA-CT
PIT_HZ = 1193182.0
CHIP_HZ = 3579545.0            # the Tandy 1000's SN76496
AY_HZ = 1750000.0              # the Next's AY chips (28 MHz / 16)

RGB16 = [
    (0, 0, 0), (0, 0, 170), (0, 170, 0), (0, 170, 170), (170, 0, 0), (170, 0, 170), (170, 85, 0), (170, 170, 170),
    (85, 85, 85), (85, 85, 255), (85, 255, 85), (85, 255, 255), (255, 85, 85), (255, 85, 255), (255, 255, 85), (255, 255, 255),
]


# ------------------------------------------------------------------ GAME.DAT (dat.c)

def dat_find(dat, name):
    for disk in range(2):
        d = disk * DISK_SIZE + 8 * 512
        for o in range(0, 512 - 5, 6):
            if dat[d + o] == 0:
                break
            if dat[d + o:d + o + 2] == name.encode():
                s = dat[d + o + 2] | dat[d + o + 3] << 8
                c = dat[d + o + 4] | dat[d + o + 5] << 8
                return dat[disk * DISK_SIZE + s * 512:disk * DISK_SIZE + (s + c) * 512]
    raise SystemExit(f"GAME.DAT has no {name}")


def lzw(src):
    """9-12 bit codes, LSB first, 100h clear, 101h end (GameSYS 065D, AB 9ABB)"""
    out = bytearray()
    prefix = [0] * 4096
    suffix = [0] * 4096
    n = len(src)
    bit = 0
    width, nxt, limit, old, first = 9, 0x102, 0x200, -1, 0

    def code(bit, width):
        b = bit >> 3
        v = src[b] | (src[b + 1] << 8 if b + 1 < n else 0) | (src[b + 2] << 16 if b + 2 < n else 0)
        return (v >> (bit & 7)) & ((1 << width) - 1)

    while bit + width <= n * 8:
        c = code(bit, width)
        bit += width
        if c == 0x101:
            break
        if c == 0x100:
            width, limit, nxt = 9, 0x200, 0x102
            if bit + width > n * 8:
                break
            c = code(bit, width)
            bit += width
            out.append(c)
            old = first = c
            continue
        if old < 0:
            break
        stack = []
        cc = c
        if c >= nxt:
            stack.append(first)
            cc = old
        while cc > 0xFF:
            stack.append(suffix[cc])
            cc = prefix[cc]
        stack.append(cc)
        first = cc
        out.extend(reversed(stack))
        if nxt < 4096:
            prefix[nxt] = old
            suffix[nxt] = first
            nxt += 1
        old = c
        if nxt >= limit and width < 12:
            width += 1
            limit <<= 1
    return bytes(out)


def dat_file(dat, name, raw=False):
    p = dat_find(dat, name)
    if raw or ((p[0] | p[1] << 8) & 0x1FF) != 0x100:
        return p
    return lzw(p)


# ------------------------------------------------------------------ the pictures (assets.c picture_16)

def tandy_picture(dat, name):
    raw = dat_file(dat, name, raw=True)
    u = lzw(raw[16:])
    if len(u) < 32000:
        raise SystemExit(f"GAME.DAT's picture {name} could not be read")
    pix = bytearray(SCREEN_W * SCREEN_H)
    for y in range(SCREEN_H):
        for x in range(SCREEN_W):
            v = 0
            for pl in range(4):
                v |= ((u[pl * 8000 + y * 40 + (x >> 3)] >> (7 - (x & 7))) & 1) << pl
            pix[y * SCREEN_W + x] = v
    # the Tandy build maps the palette bytes as v & 0Fh, plus 8 if v & 30h
    pal = [(v & 15) | (8 if v & 0x30 else 0) for v in raw[:16]]
    return pix, pal


def pic_file(dat, name):
    """picture NAME as the Next keeps it (above), and a preview (RGB, 320x256 as Layer 2 shows it)"""
    pix, pal = tandy_picture(dat, name)
    f = bytearray(4 * PAGE)
    for p in range(160):
        o = (p // 40) * PAGE + (p % 40) * 200
        for y in range(SCREEN_H):
            f[o + y] = pix[y * SCREEN_W + 2 * p] << 4 | pix[y * SCREEN_W + 2 * p + 1]
    f[3 * PAGE + 0x1F40:3 * PAGE + 0x1F50] = bytes(pal)
    preview = bytearray(320 * 256 * 3)
    for y in range(SCREEN_H):
        for x in range(SCREEN_W):
            o = ((TOP + y) * 320 + x) * 3
            preview[o:o + 3] = bytes(from_333(to_333(RGB16[pal[pix[y * SCREEN_W + x]]])))
    return bytes(f[:3 * PAGE + 0x1F50]), preview


# ------------------------------------------------------------------ the sprites (assets.c decode_file, Tandy)

# the Tandy program's sprite files, by what they hold (assets.h FileId; AC's names)
SPRITE_FILES = ["BC", "BF", "BR", "BX", "BY", "Ba", "Bb", "Be", "Bj", "Bk", "Bl"]
F_FONT, F_CHARS, F_PORTRAITS = 0, 1, 2
IT_NONE, IT_BIG, IT_SLOT, IT_MASK, IT_GLYPH = range(5)


class Image:
    """w x h pixel values (pix), the background bits kept where it is drawn
    masked (mask: 0 opaque, 15 transparent; None: drawn whole)"""
    def __init__(self, w, h, pix, mask=None, kind=IT_NONE, adv=0):
        self.w, self.h, self.pix, self.mask, self.kind, self.adv = w, h, pix, mask, kind, adv


def _word(d, o):
    return d[o] | d[o + 1] << 8 if o + 1 < len(d) else 0


def _tandy_pixels(d, o, h, bpr, mask_o=0):
    """h rows of bpr bytes, 2 pixels a byte (high nibble first); and the mask's (AND values)"""
    w = bpr * 2
    ps = h * bpr
    if h <= 0 or bpr <= 0 or h > 200 or w > 640 or o + ps > len(d) or (mask_o and mask_o + ps > len(d)):
        return None
    pix = bytearray(w * h)
    mask = bytearray(w * h) if mask_o else None
    for y in range(h):
        for x in range(w):
            b = d[o + y * bpr + (x >> 1)]
            pix[y * w + x] = (b >> (0 if x & 1 else 4)) & 15
            if mask_o:
                b = d[mask_o + y * bpr + (x >> 1)]
                mask[y * w + x] = (b >> (0 if x & 1 else 4)) & 15
    return Image(w, h, pix, mask)


def decode_sprite_file(raw, file_id, first_item=0, last_item=255):
    """the items of a Tandy sprite file: {item: Image}"""
    d = bytes(raw) + bytes(4096)          # the last item can reach past the end: zeros stand in
    n, first = 0, 0
    while 2 * n + 2 <= len(d) and n < 256 and (not first or 2 * n < first):
        v = _word(d, 2 * n)
        if v and (not first or v < first):
            first = v
        n += 1
    items = {}
    for i in range(first_item, min(n - 1, last_item) + 1):
        p = _word(d, 2 * i)
        if not p or p + 8 > len(d):
            continue
        if file_id == F_FONT and 0x97 <= i <= 0x9E:          # the PC-speaker tunes
            continue
        if file_id == F_FONT and 0x20 <= i <= 0x7A:          # a letter: ANDed in (AC 73BB)
            wb, bpr, h = _word(d, p), _word(d, p + 2), _word(d, p + 4)
            im = _tandy_pixels(d, p + 6, h, bpr)
            if im:
                im.mask = bytearray((~v) & 15 for v in im.pix)
                im.pix = bytearray(len(im.pix))
                im.kind, im.adv = IT_GLYPH, wb
                items[i] = im
            continue
        if file_id == F_PORTRAITS and 1 <= i <= 19:          # a territory's shape
            im = _tandy_pixels(d, p + 4, _word(d, p), _word(d, p + 2))
            if im:
                im.kind = IT_MASK
                items[i] = im
            continue
        q = _word(d, p)
        slot = first <= q and q + 4 < len(d) and d[q] and d[q + 1]
        if slot:
            q2 = _word(d, p + 2)
            if q2 < first or q2 >= len(d):
                slot = False
        if slot:
            h, bpr, ps = d[q], d[q + 1], _word(d, q + 2)
            if ps >= h * bpr:
                im = _tandy_pixels(d, q + 4 + ps, h, bpr, q + 4)
                if im:
                    im.kind = IT_SLOT
                    items[i] = im
                    continue
        h, bpr = _word(d, p), _word(d, p + 2)
        if 0 < h <= 200 and 0 < bpr <= 160:
            im = _tandy_pixels(d, p + 4, h, bpr)
            if im:
                im.kind = IT_BIG
                items[i] = im
    return items


def tandy_sprites(dat):
    """{file: {item: Image}} for the Tandy program's sprite files, as assets.c's load_set"""
    files = {}
    for f, name in enumerate(SPRITE_FILES):
        files[f] = decode_sprite_file(dat_file(dat, name), f, 0, 127 if f == F_PORTRAITS else 255)
    bs = decode_sprite_file(dat_file(dat, "BS"), F_PORTRAITS, 128, 255)   # the portraits (128-149) are in BS
    files[F_PORTRAITS].update(bs)
    return files


DS_SIZE = 0x6000                 # the data segment as the Next keeps it (4000h-9FFFh)
PAGE = 0x2000


def sprite_blob(items):
    """a sprite file for the Next: 256 words, each item's offset in the blob (0: none),
    then the items, none across an 8K page: kind, flags (bit 0: masked), w (word),
    h, adv (the glyph's width word / 2 + 1, the original's advance), then the
    pixels column by column (Layer 2 320x256 keeps its columns whole): for each
    column its h pixels, top to bottom. A masked item has, for each column,
    the row its span starts at and the span's length (the rows above and below
    are see-through: mask 15, pixel 0), then each of the span's pixels as its
    mask byte and the pixel"""
    blob = bytearray(512)
    for i in sorted(items):
        im = items[i]
        data = bytearray()
        for x in range(im.w):
            if im.mask is None:
                data += bytes(im.pix[y * im.w + x] for y in range(im.h))
                continue
            seen = [y for y in range(im.h) if not (im.mask[y * im.w + x] == 15 and im.pix[y * im.w + x] == 0)]
            first, n = (seen[0], seen[-1] - seen[0] + 1) if seen else (0, 0)
            data += bytes([first, n])
            for y in range(first, first + n):
                data += bytes([im.mask[y * im.w + x], im.pix[y * im.w + x]])
        adv = (im.adv >> 1) + 1 if im.kind == IT_GLYPH else 0
        item = bytes([im.kind, 1 if im.mask is not None else 0, im.w & 255, im.w >> 8, im.h, adv]) + data
        if len(item) > PAGE:
            raise SystemExit(f"sprite item {i:02X}h is larger than 8K")
        if len(blob) % PAGE + len(item) > PAGE:
            blob += bytes(PAGE - len(blob) % PAGE)
        struct.pack_into("<H", blob, 2 * i, len(blob))
        blob += item
    if len(blob) > 0x10000:
        raise SystemExit("a sprite file is larger than 64K")
    return bytes(blob)


def speaker_tunes(dat):
    """for tunes 97h-9Eh: 8 words, each tune's offset; at each, the note count (word)
    and the notes' lengths in BIOS ticks (a byte each), as sound.c's tick_player reads BB"""
    bb = dat_file(dat, "BB")
    w = lambda o: bb[o] | bb[o + 1] << 8
    out = bytearray(16)
    for k, t in enumerate(range(0x97, 0x9F)):
        base = w(2 * t)
        n = w(base + 2)
        ticks = [w(base + 6 + 4 * i) for i in range(1, n + 1)]
        if max(ticks) > 255:
            raise SystemExit(f"tune {t:02X}h has a note longer than 255 ticks")
        struct.pack_into("<H", out, 2 * k, len(out))
        out += struct.pack("<H", n) + bytes([0]) + bytes(ticks)   # index 1 is the first note
    return bytes(out)


def to_333(rgb):
    """an 8-bit colour to the Next's 3 bits a component (nearest)"""
    return tuple(min(7, (c * 7 + 127) // 255) for c in rgb)


def from_333(c):
    return tuple((v * 255 + 3) // 7 for v in c)


def next_colour(rgb):
    """NextReg 44h's two bytes: RRRGGGBB, then the low bit of blue"""
    r, g, b = to_333(rgb)
    return bytes([(r << 5) | (g << 2) | (b >> 1), b & 1])


# ------------------------------------------------------------------ the Tandy music driver (sound.c)

class Tandy:
    def __init__(self, bg):
        self.bg = bg
        self.regs = [0] * 8           # tone 0-2, noise control, attenuation 0-3
        self.latch = 0
        self.loop_at = -1
        self.tempo = 0
        self.playing = False
        self.restarted = False
        self.inst = [[0] * 6 for _ in range(4)]
        self.has_inst = [False] * 4
        z = lambda: [0] * 4
        self.ptr, self.dur, self.state, self.active = z(), z(), z(), z()
        self.vol, self.rel, self.tone, self.vib, self.vsub, self.vph = z(), z(), z(), z(), z(), z()
        self.subtick = 0
        self.silence()

    def w(self, o):
        return self.bg[o] | self.bg[o + 1] << 8 if 0 <= o and o + 1 < len(self.bg) else 0

    def out(self, b):                  # port C0h
        b &= 0xFF
        if b & 0x80:
            self.latch = (b >> 4) & 7
        ch, typ = self.latch >> 1, self.latch & 1
        if typ:
            self.regs[4 + ch] = b & 15
        elif ch == 3:
            self.regs[3] = b & 7
        elif b & 0x80:
            self.regs[ch] = (self.regs[ch] & 0x3F0) | (b & 15)
        else:
            self.regs[ch] = (self.regs[ch] & 15) | ((b & 0x3F) << 4)

    def silence(self):                 # 7C78
        for b in (0x9F, 0xBF, 0xDF, 0xFF):
            self.out(b)
        for v in range(4):
            self.state[v] = 5
            self.active[v] = 0

    def stop(self):                    # 7C53
        self.silence()
        self.playing = False

    def song_at(self, bx):             # 747A, 74BA
        self.stop()
        if self.w(bx) == 0xFFFF:
            return
        if self.w(bx) == 0xFFFE:
            self.loop_at = bx
            bx += 2
        self.tempo = self.w(bx)
        for v in range(4):
            p = self.w(bx + 2 + 2 * v)
            if self.w(p) == 0:
                self.active[v] = 0
                self.has_inst[v] = False
            else:
                self.inst[v] = [self.w(p + 2 * k) for k in range(6)]
                self.has_inst[v] = True
                self.active[v] = 1
                p += 12
            self.ptr[v] = p
            self.vol[v], self.dur[v] = 15, 1
            self.rel[v] = self.tone[v] = self.vib[v] = self.vsub[v] = self.vph[v] = 0
        self.subtick = 1
        self.playing = True

    def start(self, song):             # 7444
        self.loop_at = -1
        self.song_at(self.w(2 * song))

    def set_tone(self, v, n):          # 7820
        n &= 0xFFFF
        self.out((n & 15) | (0x80 + 0x20 * v))
        self.out((n >> 4) & 0xFF)

    def next_event(self, v):
        bx = self.ptr[v]
        du = self.w(bx)
        self.dur[v] = du
        if du == 0xFFFF:
            nx = self.w(bx + 2)
            restart = nx == 0xFFFE if v < 2 else nx != 0xFFFE   # voices 2 and 3 test the other way round
            if restart and self.loop_at >= 0:
                self.song_at(self.loop_at)
                self.restarted = True
                return 1
            self.stop()
            return 2
        bx += 2
        n = self.w(bx)
        if n == 0xFFFA:
            self.inst[v][5] = 0xFFFF
            bx += 2
        if n == 0:
            self.state[v] = 4
        else:
            self.tone[v] = n
            self.set_tone(v, n)
            self.state[v] = 1
            self.vib[v] = self.inst[v][5]
            self.vph[v] = 0
        self.ptr[v] = bx + 2
        return 0

    def vibrato(self, v):              # 7A83
        self.vib[v] = (self.vib[v] - 1) & 0xFFFF
        if self.vib[v] != 0 and self.vib[v] < 0x8000:
            return
        self.vib[v] = (self.vib[v] + 1) & 0xFFFF
        if self.vsub[v] != 2:
            self.vsub[v] += 1
            return
        self.vsub[v] = 0
        self.vph[v] += 1
        if self.vph[v] < 3:
            self.tone[v] += 1
        else:
            if self.vph[v] == 4:
                self.vph[v] = 0
            self.tone[v] -= 1
        self.set_tone(v, self.tone[v])

    @staticmethod
    def clamp15(x):                    # 7A6F
        x &= 0xFFFF
        if x >= 0x8000:
            x -= 0x10000
        return 0 if x < 0 else 15 if x > 15 else x

    def interrupt(self):               # 75F4
        if not self.playing:
            return
        self.subtick -= 1
        if self.subtick == 0:
            self.subtick = 4
            for v in range(4):
                if not self.playing:
                    break
                if not self.active[v]:
                    continue
                self.dur[v] = (self.dur[v] - 1) & 0xFFFF
                if self.dur[v] == 0:
                    if self.next_event(v) == 1:
                        return
                elif self.inst[v][5] != 0xFFFF:
                    self.vibrato(v)
            return
        for v in range(4):             # 7870: the envelopes
            s = self.state[v]
            if s in (3, 5):
                continue
            a, dcy, sus, rstep, rint = self.inst[v][:5] if self.has_inst[v] else (0, 0, 0, 0, 0)
            ax = self.vol[v]
            if s == 1:
                ax = self.clamp15(ax - a)
                self.vol[v] = ax
                if ax == 0:
                    self.state[v] = 2
            elif s == 2:
                ax += dcy
                self.vol[v] = ax
                ax = self.clamp15(ax)
                if ax >= sus:
                    ax = self.vol[v] = sus
                    self.state[v] = 3
            else:
                self.rel[v] -= 1
                if self.rel[v] > 0:
                    continue
                self.rel[v] = rint
                ax += rstep
                self.vol[v] = ax
                ax = self.clamp15(ax)
                if ax >= 15:
                    self.state[v] = 5
                    ax = 15
            self.out((ax & 15) | (0x90 + 0x20 * v))


# the AY's 16 volume levels, relative (as MAME measures the AY-3-8910)
AY_LEVELS = [0.0, 0.0106, 0.0150, 0.0222, 0.0320, 0.0466, 0.0665, 0.1039,
             0.1237, 0.1986, 0.2803, 0.3548, 0.4702, 0.6030, 0.7530, 1.0]


def ay_volume(att):
    """SN76496 attenuation (2 dB a step, 15 off) to the nearest AY level"""
    if att >= 15:
        return 0
    amp = 10 ** (-2.0 * att / 20.0)
    return min(range(1, 16), key=lambda k: abs(AY_LEVELS[k] - amp))


def ay_period(n):
    """SN tone register (CHIP/32/n Hz) to an AY period (AY/16/p Hz)"""
    n = n or 1024
    return max(1, min(4095, round(n * 32 * AY_HZ / (16 * CHIP_HZ))))


def ay_tables():
    periods = b"".join(struct.pack("<H", ay_period(n)) for n in range(1024))
    volumes = bytes(ay_volume(att) for att in range(16))
    return periods, volumes


# ------------------------------------------------------------------ a small PNG writer (the preview)

def write_png(path, rgb, w, h):
    raw = b"".join(b"\0" + bytes(rgb[y * w * 3:(y + 1) * w * 3]) for y in range(h))

    def chunk(t, data):
        c = zlib.crc32(t + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + t + data + struct.pack(">I", c)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    Path(path).write_bytes(png)


# ------------------------------------------------------------------ main

def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: convert.py GAME.DAT OUTPUT-FOLDER")
    dat = Path(sys.argv[1]).read_bytes()
    if len(dat) < 2 * DISK_SIZE:
        raise SystemExit(f"{sys.argv[1]} is not the booter's GAME.DAT")
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)

    sd = out / "sd" / "DOTC" / "DOTC_GFX"
    sd.mkdir(parents=True, exist_ok=True)
    (out / "preview").mkdir(exist_ok=True)
    for i in range(PICTURES):
        name = "C" + chr(ord("A") + i)
        data, preview = pic_file(dat, name)
        (sd / f"{name}.PIC").write_bytes(data)
        write_png(out / "preview" / f"{name}.png", preview, 320, 256)

    rgb16 = b"".join(next_colour(c) for c in RGB16)
    if any(rgb16[2 * i] == 0xE3 for i in range(16)):    # Layer 2's transparent colour (NextReg 14h)
        raise SystemExit("a Tandy colour is the Next's transparent colour (E3h)")
    (out / "rgb16.bin").write_bytes(rgb16)
    bh = dat_file(dat, "BH")
    if len(bh) > DS_SIZE:
        raise SystemExit("BH is larger than the Next's data segment")
    (out / "ds.bin").write_bytes(bh + bytes(DS_SIZE - len(bh)))
    sprites = tandy_sprites(dat)
    (out / "spr_font.bin").write_bytes(sprite_blob(sprites[F_FONT]))
    (out / "spr_chars.bin").write_bytes(sprite_blob(sprites[F_CHARS]))
    (out / "speaker.bin").write_bytes(speaker_tunes(dat))
    bg = dat_file(dat, "BG")
    (out / "bg.bin").write_bytes(bg)
    periods, volumes = ay_tables()
    (out / "ay_period.bin").write_bytes(periods)
    (out / "ay_volume.bin").write_bytes(volumes)

    print(f"sd/DOTC/DOTC_GFX/CA.PIC-{name}.PIC, preview/: the {PICTURES} Tandy pictures")
    print(f"ds.bin: the data segment (BH, {len(bh)} bytes); spr_font.bin, spr_chars.bin: the font and name boxes; "
          f"speaker.bin: the speaker tunes' timing")
    print(f"bg.bin: the Tandy music (BG, {len(bg)} bytes); ay_period.bin, ay_volume.bin: the AY tables")


if __name__ == "__main__":
    main()
