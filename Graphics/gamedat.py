#!/usr/bin/env python3
"""Reader for GAME.DAT, the EGA/Tandy/CGA booter version of Defender of the Crown
(Interactive Designs' ZeroBoot 2.2 + GameSYS 4.0, made runnable from DOS by Mok's DEFENDER.COM).

GAME.DAT is two 360K floppy images one after the other (40 tracks, 2 sides, 9 sectors
of 512 bytes; disk 1 at 5A000h). Sector n of a disk (0-based, n = track*18 + side*9 +
sector-1) is at disk*5A000h + n*512. Track 0 sector 9 (n = 8) of each disk is its
directory: 6-byte entries (2-char name, first sector n, sector count), ended by a
0 name byte; the word at 1FCh is the disk's number. Every file is LZW-compressed
(GameSYS 065D: codes 9-12 bits, packed LSB first, 100h = clear, 101h = end, first
free code 102h; the width grows when the next free code reaches 2^width).

Usage: gamedat.py GAME.DAT [OUTDIR]       list (and unpack) every file
       gamedat.py GAME.DAT --disks OUTDIR  write the two floppy images"""
import struct, sys, os

DISK = 0x5A000

def directory(dat):
    out = {}
    for disk in (0, 1):
        sec = dat[disk * DISK + 8 * 512: disk * DISK + 9 * 512]
        o = 0
        while sec[o]:
            n, s, c = struct.unpack('<HHH', sec[o:o + 6])
            out[chr(n & 0xFF) + chr(n >> 8)] = (disk, s, c)
            o += 6
    return out

def raw(dat, entry):
    disk, s, c = entry
    a = disk * DISK + s * 512
    return dat[a:a + c * 512]

def lzw(src):
    out = bytearray()
    bitpos = 0; width = 9
    prefix = [0] * 4096; suffix = [0] * 4096
    nxt = 0x102; limit = 0x200
    def code():
        nonlocal bitpos
        b = bitpos >> 3
        v = int.from_bytes(src[b:b + 3].ljust(3, b'\0'), 'little') >> (bitpos & 7)
        bitpos += width
        return v & ((1 << width) - 1)
    def expand(c):
        s = bytearray()
        while c > 0xFF:
            s.append(suffix[c]); c = prefix[c]
        s.append(c)
        s.reverse(); return s
    old = None; first = 0
    while True:
        if (bitpos + width) > len(src) * 8: break
        c = code()
        if c == 0x101: break
        if c == 0x100:
            width = 9; limit = 0x200; nxt = 0x102
            c = code()
            out.append(c); old = c; first = c
            continue
        if c >= nxt:          # KwKwK
            s = expand(old) + bytes([first])
        else:
            s = expand(c)
        out += s
        first = s[0]
        if nxt < 4096:
            prefix[nxt] = old; suffix[nxt] = first; nxt += 1
        old = c
        if nxt >= limit and width < 12:
            width += 1; limit <<= 1
    return bytes(out)

def is_lzw(r):
    """An LZW file starts with the clear code 100h."""
    return (r[0] | (r[1] << 8)) & 0x1FF == 0x100

def write_disks(dat, outdir):
    """Split GAME.DAT into its two 360K floppy images (disk1.img, disk2.img), which
    DOSBox can boot (`boot disk1.img disk2.img`, Ctrl-F4 swaps the disks)."""
    os.makedirs(outdir, exist_ok=True)
    for i in (0, 1):
        open(os.path.join(outdir, 'disk%d.img' % (i + 1)), 'wb').write(dat[i * DISK:(i + 1) * DISK])

if __name__ == '__main__':
    dat = open(sys.argv[1], 'rb').read()
    if len(sys.argv) > 3 and sys.argv[2] == '--disks':
        write_disks(dat, sys.argv[3]); sys.exit()
    outdir = sys.argv[2] if len(sys.argv) > 2 else None
    for name, e in directory(dat).items():
        r = raw(dat, e)
        u = lzw(r) if is_lzw(r) else r
        print('%s disk %d sector %3d count %2d %s -> %6d bytes' % (name, e[0], e[1], e[2], 'lzw' if is_lzw(r) else 'raw', len(u)))
        if outdir:
            os.makedirs(outdir, exist_ok=True)
            open(os.path.join(outdir, name + ('_' if name[1].islower() else '') + '.bin'), 'wb').write(u)
