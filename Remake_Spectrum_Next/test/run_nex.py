#!/usr/bin/env python3
"""
Defender of the Crown (1986) - Spectrum Next remake
Nov 2026 using Claude Opus 5.5
"Guided" by Brett Hallen

run_nex.py: the checks without a Next. Loads DOTC.NEX as NextZXOS does and
runs it on a Z80 emulator (pip install z80) at its own speed, with a model of
the Next around it:

  - the MMU (NextRegs 50h-57h: each 8K slot's page) over the 1MB of pages
  - the NEXTREG instructions (a plain Z80 doesn't have them: each is a
    breakpoint)
  - Layer 2 320x256 and its first palette, the zxnDMA's memory copies
  - the AY, the keyboard, the raster line
  - the CTC: an interrupt every 16384 T-states (28 MHz / 256 / 64), through
    the hardware IM2 controller
  - esxDOS's file calls (RST 08h) on the SD card's files (build/sd/DOTC)

The program's `idle` (where it waits for the next interrupt) jumps the model's
clock to the next interrupt; its `frame_done` (a new screen is up) records the
screen. The checks:

  1. the music driver: for each of the eight songs, the Z80 port (tandy.asm)
     and the Python one (tools/convert.py's Tandy, from the Mac remake's
     sound.c) side by side, one driver interrupt at a time: the AY must hold,
     after every one, what the Tandy chip would
  2. the opening, against the Mac remake's own (the reference: test/ref):
     the same screens, pixel for pixel and colour for colour, in the same
     order, at about the same times; with no key, up to the choice of
     character; with S (skip) pressed during the credits; and with a choice
     made, through Sherwood

Usage: python3 run_nex.py [BUILD-FOLDER] [REFERENCE-FOLDER]
  BUILD-FOLDER (default build) holds the converter's files and main.map;
  REFERENCE-FOLDER (default build/ref) the reference's recordings:
  opening.rec (no keys), skip.rec (S at 5 s) and sherwood.rec (keypad 6, 2,
  Enter at 70, 71, 72 s): test/ref/README.md says how to make them.
"""
import struct
import sys
import zlib
from pathlib import Path

import z80

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "tools"))
from convert import Tandy, RGB16, to_333, from_333      # noqa: E402  the reference driver, the colours

ORDER = [5, 2, 0, 1, 3, 4] + list(range(6, 112))
PAGE = 8192
ROM = 0xFF
T_INT = 256 * 64                       # T-states between CTC interrupts (28 MHz / 256 / 64)
CPU_HZ = 28_000_000
T_LINE = CPU_HZ / 50 / 312             # a raster line, 50 Hz
SENTINEL = 0x7FF0                      # a return address for routines called from the test
TOP, W, H = 28, 320, 200
SCREEN_PAGE, BACK_PAGE = 40, 50
KEY_SONGS = [5, 6, 4, 2, 0, 3, 7, 1]
PIT_HZ = 1193182

# the keyboard: name -> (half-row, bit)
KEYMAP = {"CAPS": (0xFE, 0), "S": (0xFD, 1), "ENTER": (0xBF, 0), "SPACE": (0x7F, 0)}
for i, k in enumerate("12345"):
    KEYMAP[k] = (0xF7, i)
for i, k in enumerate("09876"):
    KEYMAP[k] = (0xEF, i)


def load_map(path):
    labels = {}
    for line in Path(path).read_text().splitlines():
        if ":" in line:
            a, n = line.split(":", 1)
            labels[n.strip().lstrip(".")] = int(a, 16)
    return labels


class Next:
    def __init__(self, nex, labels, sd):
        self.L = labels
        self.sd = Path(sd)
        d = Path(nex).read_bytes()
        assert d[:4] == b"Next" and d[4:8] == b"V1.2", "not a V1.2 .nex"
        sp, pc = struct.unpack_from("<HH", d, 12)
        self.pages = {p: bytearray(PAGE) for p in range(224)}
        o = 512
        for b in ORDER:
            if d[18 + b]:
                self.pages[2 * b][:] = d[o:o + PAGE]
                self.pages[2 * b + 1][:] = d[o + PAGE:o + 2 * PAGE]
                o += 2 * PAGE
        assert o == len(d), "the file's length doesn't match its banks"
        self.m = z80.Z80Machine()
        self.mmu = [ROM, ROM, 10, 11, 4, 5, 0, 1]     # as the .nex loader leaves it
        for s in range(8):
            self._load(s)
        self.m.pc, self.m.sp = pc, sp
        self.reg = {0x05: 0, 0x08: 0, 0x09: 0, 0x11: 0, 0x12: 9, 0x14: 0xE3, 0x43: 0, 0x70: 0}
        self.sel = 0
        self.t = 0                       # T-states since the start
        self.next_int = None             # the CTC's next interrupt (once it is set going)
        self.ctc = []
        self.ints = 0
        self.l2_on = False
        self.clip, self.clip_i = [0, 255, 0, 191], 0
        self.pal = [0] * 256
        self.pal_i, self.pal_half = 0, None
        self.ay = [0] * 16
        self.ay_sel, self.ay_chip = 0, 0
        self.dma = []
        self.files, self.next_handle, self.calls = {}, 1, 0
        self.port_7ffd = self.port_1ffd = 0
        self.l2_port = 0
        self.border = 0
        self.keys = set()
        self.frames = []                 # (time s, screen RGB bytes)
        self.m.set_input_callback(self.port_in)
        self.m.set_output_callback(self.port_out)
        # breakpoints: every NEXTREG in the program, RST 08h's target, idle, frame_done
        self.nextregs = self._find_nextregs(0xA000, labels["code_end"])
        for a in self.nextregs:
            self.m.set_breakpoint(a)
        for a in (0x0008, labels["idle"], labels["frame_done"], SENTINEL):
            self.m.set_breakpoint(a)

    # ---- memory
    def _load(self, s):
        p = self.mmu[s]
        self.m.memory[s * PAGE:(s + 1) * PAGE] = bytes(PAGE) if p == ROM else bytes(self.pages[p])

    def _save(self, s):
        p = self.mmu[s]
        if p != ROM:
            self.pages[p][:] = bytes(self.m.memory[s * PAGE:(s + 1) * PAGE])

    def remap(self, s, p):
        self._save(s)
        self.mmu[s] = p
        self._load(s)

    def page(self, p):
        """page p as it is now (written back from the slot it is in, if any)"""
        for s in range(8):
            if self.mmu[s] == p:
                self._save(s)
        return self.pages[p]

    def _find_nextregs(self, start, end):
        """every ED 91 / ED 92 in the program: a breakpoint on one that is data
        (never run) does no harm, and a real NEXTREG starts with one"""
        mem = bytes(self.m.memory[start:end + 1])
        return {start + i for i in range(len(mem) - 1) if mem[i] == 0xED and mem[i + 1] in (0x91, 0x92)}

    # ---- the Next registers
    def nextreg(self, r, v):
        self.reg[r] = v
        if 0x50 <= r <= 0x57:
            self.remap(r - 0x50, v)
        elif r == 0x1C and v & 1:
            self.clip_i = 0
        elif r == 0x18:
            self.clip[self.clip_i & 3] = v
            self.clip_i += 1
        elif r == 0x40:
            self.pal_i, self.pal_half = v, None
        elif r == 0x44:
            if self.pal_half is None:
                self.pal_half = v
            else:
                if (self.reg[0x43] >> 4) & 7 == 1:   # Layer 2's first palette
                    self.pal[self.pal_i & 255] = (self.pal_half << 1) | (v & 1)
                self.pal_i += 1
                self.pal_half = None
        elif r == 0x69:
            self.l2_on = bool(v & 0x80)

    def port_in(self, port):
        if port == 0x253B:
            if self.sel == 0x1F:
                return int(self.t / T_LINE) % 312 & 0xFF
            if self.sel == 0x1E:
                return (int(self.t / T_LINE) % 312) >> 8
            return self.reg.get(self.sel, 0)
        if port & 0xFF == 0xFE:          # the keyboard: rows by the high byte, 0 = held
            v = 0xFF
            hi = port >> 8
            for k in self.keys:
                row, bit = KEYMAP[k]
                if not hi & (~row & 0xFF):
                    v &= ~(1 << bit)
            return v & 0xFF
        return 0xFF

    def port_out(self, port, v):
        if port == 0x243B:
            self.sel = v
        elif port == 0x253B:
            self.nextreg(self.sel, v)
        elif port == 0x123B:
            if not v & 0x10:
                self.l2_port = v
                self.l2_on = bool(v & 2)
        elif port == 0xFFFD:
            if v & 0x80:
                assert (v & 0x1C) == 0x1C and self.reg[0x08] & 2, "a Turbosound select"
                self.ay_chip = {3: 0, 2: 1, 1: 2}[v & 3]
            else:
                self.ay_sel = v & 0x0F
        elif port == 0xBFFD:
            if self.ay_chip == 0:
                self.ay[self.ay_sel] = v
        elif port == 0x7FFD:
            self.port_7ffd = v
        elif port == 0x1FFD:
            self.port_1ffd = v
        elif port & 0xFF == 0xFE:
            self.border = v & 7
        elif port == 0x183B:             # CTC 0: going once its time constant is written
            self.ctc.append(v)
            if len(self.ctc) >= 2 and self.ctc[-2] & 0x04 and self.ctc[-2] & 0x80:
                assert self.ctc[-2:] == [0xA7, 64] and self.reg.get(0xC5) == 1 and self.reg.get(0xC0) == 1
                self.next_int = self.t + T_INT
        elif port & 0xFF == 0x6B:        # the zxnDMA: the copy dma_copy programs
            self.dma.append(v)
            if len(self.dma) == 16:      # dma_copy's 16 bytes, the last the enable (87h)
                p = self.dma
                self.dma = []
                assert p[0] == 0x83 and p[1] == 0x7D and p[6:11] == [0x54, 2, 0x50, 2, 0xAD] \
                    and p[13:] == [0x82, 0xCF, 0x87], f"a DMA program not modelled: {p}"
                src, n, dst = p[2] | p[3] << 8, p[4] | p[5] << 8, p[11] | p[12] << 8
                self.m.memory[dst:dst + n] = bytes(self.m.memory[src:src + n])
                self.t += 2 * n

    # ---- esxDOS
    def esxdos(self):
        m = self.m
        ret = m.memory[m.sp] | m.memory[(m.sp + 1) & 0xFFFF] << 8
        m.sp = (m.sp + 2) & 0xFFFF
        code = m.memory[ret]
        m.pc = (ret + 1) & 0xFFFF
        assert self.port_7ffd & 0x10 and self.port_1ffd & 0x04, "esxDOS needs the 48K BASIC ROM paged in"
        assert self.mmu[:5] == [ROM, ROM, 10, 11, 4], f"esxDOS calls with the memory {self.mmu}"
        assert not self.l2_port & 1 and not m.iff1, "Layer 2 writes and interrupts off during file calls"
        self.calls += 1
        fail = True
        if code == 0x9A:                # F_OPEN: A drive, IX name, B mode
            name = bytearray()
            a = m.ix
            while m.memory[a]:
                name.append(m.memory[a])
                a += 1
            path = self.sd / name.decode()
            assert m.a == ord("*") and m.b == 0x01, "open for reading on the current drive"
            if path.is_file():
                self.files[self.next_handle] = [path.read_bytes(), 0]
                m.a = self.next_handle
                self.next_handle += 1
                fail = False
            else:
                m.a = 5
        elif code == 0x9D:              # F_READ: A handle, IX address, BC count
            f = self.files[m.a]
            n = min(m.bc, len(f[0]) - f[1])
            assert m.ix >= 0x4000 and m.ix + n <= 0x10000
            m.memory[m.ix:m.ix + n] = f[0][f[1]:f[1] + n]
            f[1] += n
            m.bc = n
            self.t += n * 20
            fail = False
        elif code == 0x9B:              # F_CLOSE
            del self.files[m.a]
            fail = False
        else:
            raise AssertionError(f"esxDOS call {code:02X}h not modelled")
        m.f = (m.f | 1) if fail else (m.f & ~1)

    # ---- running
    def interrupt(self):
        m = self.m
        m.sp = (m.sp - 2) & 0xFFFF
        m.memory[m.sp] = m.pc & 0xFF
        m.memory[(m.sp + 1) & 0xFFFF] = m.pc >> 8
        v = (m.i << 8) | 0x06
        m.pc = m.memory[v] | m.memory[v + 1] << 8
        m.iff1 = m.iff2 = 0
        self.ints += 1

    def ret(self):
        m = self.m
        m.pc = m.memory[m.sp] | m.memory[(m.sp + 1) & 0xFFFF] << 8
        m.sp = (m.sp + 2) & 0xFFFF

    def run(self, seconds=None, until=None):
        """run until the model's clock reaches `seconds`, or until() is true (checked at each stop)"""
        m = self.m
        L = self.L
        end = None if seconds is None else int(seconds * CPU_HZ)
        while True:
            if end is not None and self.t >= end:
                return
            if until and until():
                return
            if self.next_int is not None and self.t >= self.next_int and m.iff1 and not m.int_disabled:
                self.next_int += T_INT
                self.interrupt()
                continue
            assert not (m.iff1 and self.next_int is None), "interrupts on before the CTC is set going"
            budget = max(1, self.next_int - self.t) if m.iff1 and self.next_int is not None else 4096
            m.ticks_to_stop = budget
            ev = m.run()
            self.t += budget - m.ticks_to_stop
            if not ev & 1:                # the budget ran out: an interrupt is due
                continue
            pc = m.pc
            if pc in self.nextregs:
                op = m.memory[pc + 1]
                if op == 0x91:
                    self.nextreg(m.memory[pc + 2], m.memory[pc + 3])
                    m.pc = pc + 4
                    self.t += 20
                else:
                    self.nextreg(m.memory[pc + 2], m.a)
                    m.pc = pc + 3
                    self.t += 17
            elif pc == 0x0008:
                self.esxdos()
            elif pc == L["idle"]:
                self.ret()
                if m.iff1 and self.next_int is not None and self.t < self.next_int:   # nothing to do until the next interrupt
                    self.t = self.next_int
            elif pc == L["frame_done"]:
                self.record()
                self.ret()
            elif pc == SENTINEL:
                return
            else:
                raise AssertionError(f"stopped at {pc:04X}")

    def call(self, addr, a=None):
        """a routine, as if called (interrupts off: the music checks)"""
        m = self.m
        if a is not None:
            m.a = a
        m.iff1 = m.iff2 = 0
        m.sp = (m.sp - 2) & 0xFFFF
        m.memory[m.sp] = SENTINEL & 0xFF
        m.memory[(m.sp + 1) & 0xFFFF] = SENTINEL >> 8
        m.pc = addr
        self.run()

    # ---- the screen
    def screen(self):
        """the 320x200 picture Layer 2 shows, as RGB"""
        assert self.l2_on and (self.reg[0x70] >> 4) & 3 == 1 and self.clip == [0, 159, 0, 255], "Layer 2's set-up"
        bank = self.reg[0x12]
        data = b"".join(bytes(self.page(2 * bank + k)) for k in range(10))
        rgb = bytearray(W * H * 3)
        cols = []
        for c in self.pal[:256]:
            r, g, b = c >> 6, (c >> 3) & 7, c & 7
            cols.append(bytes(((r * 255 + 3) // 7, (g * 255 + 3) // 7, (b * 255 + 3) // 7)))
        for x in range(W):
            col = data[x * 256 + TOP:x * 256 + TOP + H]
            for y in range(H):
                o = (y * W + x) * 3
                rgb[o:o + 3] = cols[col[y]]
        return bytes(rgb)

    def record(self):
        shot = self.screen()
        if not self.frames or self.frames[-1][1] != shot:
            self.frames.append((self.t / CPU_HZ, shot))


# ------------------------------------------------------------------ the reference

def read_rec(path):
    """the reference's screens: (time s, RGB) as the Next would show them (its colours)"""
    d = Path(path).read_bytes()
    assert d[:4] == b"DREC"
    R = 8 + 16 + W * H
    lut = [bytes(from_333(to_333(c))) for c in RGB16]
    out = []
    for o in range(4, len(d) - R + 1, R):
        t = struct.unpack_from("<Q", d, o)[0] / 1e9
        pal = d[o + 8:o + 24]
        px = d[o + 24:o + R]
        cols = [lut[pal[i] & 15] for i in range(16)]
        rgb = b"".join(cols[p & 15] for p in px)
        if not out or out[-1][1] != rgb:
            out.append((t, rgb))
    return out


def write_png(path, rgb, w, h):
    raw = b"".join(b"\0" + rgb[y * w * 3:(y + 1) * w * 3] for y in range(h))
    ch = lambda t, x: struct.pack(">I", len(x)) + t + x + struct.pack(">I", zlib.crc32(t + x) & 0xFFFFFFFF)
    Path(path).write_bytes(b"\x89PNG\r\n\x1a\n" + ch(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                           + ch(b"IDAT", zlib.compress(raw)) + ch(b"IEND", b""))


def firsts(frames):
    """each distinct screen once, at its first appearance"""
    seen, out = set(), []
    for t, shot in frames:
        if shot not in seen:
            seen.add(shot)
            out.append((t, shot))
    return out


def compare(name, mine, ref, out_dir, slack=0.6):
    """Exactly the reference's screens, each pixel for pixel, each first shown at
    about the same time (slack seconds, from each run's first screen: the Next
    reads the opening's pictures from the card first). A repeating animation
    (the fire) may run a cycle more or less, and the next scene start at
    another of its frames: it is timed by the BIOS clock's ticks and by the
    retraces, and how those two fall together differs from run to run, on the
    PC as here. The Next unpacks a picture from its 4-bit cache in about 0.12 s,
    where the remake shows it at once: the times trail by that much a picture,
    until the next wait for the end of a tune puts them level again."""
    if mine and ref:
        d = mine[0][0] - ref[0][0]
        mine = [(t - d, s) for t, s in mine]
    a, b = dict(), dict()
    for t, shot in mine:
        a.setdefault(shot, t)
    for t, shot in ref:
        b.setdefault(shot, t)
    only_mine = [x for x in a if x not in b]
    only_ref = [x for x in b if x not in a]
    if only_mine or only_ref:
        for k, (shot, t, who) in enumerate([(x, a[x], "next") for x in only_mine[:3]] + [(x, b[x], "ref") for x in only_ref[:3]]):
            write_png(out_dir / f"{name}_{who}_{k}_at_{t:.2f}.png", shot, W, H)
        raise AssertionError(f"{name}: {len(only_mine)} screens the reference never shows (the first at "
                             f"{min(a[x] for x in only_mine) if only_mine else 0:.2f} s), {len(only_ref)} of its the "
                             f"Next never shows (the first at {min(b[x] for x in only_ref) if only_ref else 0:.2f} s): "
                             f"see {out_dir}/{name}_*.png")
    worst = max(abs(a[x] - b[x]) for x in a)
    if worst > slack:
        x = max(a, key=lambda x: abs(a[x] - b[x]))
        raise AssertionError(f"{name}: a screen first shown at {a[x]:.2f} s, the reference's at {b[x]:.2f} s")
    return len(a), len(mine), len(ref), worst


# ------------------------------------------------------------------ the checks

def music(build, L):
    bg = (build / "bg.bin").read_bytes()
    p = (build / "ay_period.bin").read_bytes()
    period = [p[2 * n] | p[2 * n + 1] << 8 for n in range(1024)]
    volume = list((build / "ay_volume.bin").read_bytes())

    def expect(d):
        out = []
        for c in range(3):
            pr = period[d.regs[c] & 0x3FF]
            out += [pr & 255, pr >> 8]
        return out + [volume[d.regs[4 + c]] for c in range(3)]

    nex = build / "sd" / "DOTC" / "DOTC.NEX"
    for song in range(8):
        nx = Next(nex, L, build / "sd" / "DOTC")
        nx.remap(2, 12); nx.remap(3, 13); nx.remap(4, 14)       # (as the program's start leaves them)
        for c in range(3):                                      # the AY as the start-up leaves it
            nx.ay[2 * c], nx.ay[2 * c + 1] = period[0] & 255, period[0] >> 8
        d = Tandy(bg)
        nx.call(L["drv_start"], a=song)
        d.start(song)
        got = lambda: nx.ay[0:6] + nx.ay[8:11]
        assert got() == expect(d), f"song {song}: after the start"
        tempo = d.tempo
        loops = 0
        for t in range(int(PIT_HZ / tempo * 240)):
            nx.call(L["drv_interrupt"])
            d.interrupt()
            if d.restarted:
                loops += 1
                d.restarted = False
            assert got() == expect(d), f"song {song}: the AY differs after interrupt {t + 1}"
            assert (nx.m.memory[L["drv_playing"]] != 0) == d.playing, f"song {song}: playing differs"
            if not d.playing:
                break
        assert nx.mmu[1] == ROM, "slot 1 should be the ROM again"
        secs = (t + 1) * tempo / PIT_HZ
        print(f"1. song {song} (key {KEY_SONGS.index(song) + 1}): {t + 1} interrupts identical, "
              + (f"ended after {secs:.1f} s" if not d.playing else f"still playing at {secs:.0f} s")
              + (f", looped {loops} time(s)" if loops else ""))


def opening(build, ref_dir, L):
    nex = build / "sd" / "DOTC" / "DOTC.NEX"
    out = build / "check"
    out.mkdir(exist_ok=True)

    # no keys: to the choice of character
    nx = Next(nex, L, build / "sd" / "DOTC")
    nx.run(seconds=75.5)
    ref = [f for f in read_rec(ref_dir / "opening.rec") if f[0] <= 75]
    n, shown, ref_shown, worst = compare("opening", nx.frames, ref, out)
    print(f"2. the opening, no keys: the reference's {n} different screens, pixel for pixel, "
          f"first shown within {worst * 1000:.0f} ms of its ({shown} screens shown, the reference {ref_shown}); "
          f"{nx.calls} file calls")

    # S five seconds in: the rest of the opening skipped, to the choice
    nx = Next(nex, L, build / "sd" / "DOTC")
    nx.run(until=lambda: bool(nx.frames))
    start = nx.frames[0][0]
    nx.run(seconds=start + 5.0)
    nx.keys = {"S"}
    nx.run(seconds=start + 5.1)
    nx.keys = set()
    nx.run(seconds=start + 70)
    ref = [f for f in read_rec(ref_dir / "skip.rec") if f[0] <= 70]
    n, shown, ref_shown, worst = compare("skip", nx.frames, ref, out)
    print(f"2. S at 5 s: the reference's {n} different screens, pixel for pixel, "
          f"first shown within {worst * 1000:.0f} ms of its ({shown} screens shown, the reference {ref_shown})")

    # the choice made (6, 2, then Enter), through Sherwood
    nx = Next(nex, L, build / "sd" / "DOTC")
    for t, key in SHERWOOD_KEYS:
        nx.run(seconds=t)
        nx.keys = {key}
        nx.run(seconds=t + 0.08)
        nx.keys = set()
    nx.run(seconds=SHERWOOD_END)
    ref = [f for f in read_rec(ref_dir / "sherwood.rec") if f[0] <= SHERWOOD_END]
    n, shown, ref_shown, worst = compare("sherwood", nx.frames, ref, out)
    print(f"2. the choice and Sherwood: the reference's {n} different screens, pixel for pixel, "
          f"first shown within {worst * 1000:.0f} ms of its ({shown} screens shown, the reference {ref_shown})")


# the keys for the reference's sherwood.rec (test/ref/README.md): keypad 6, 2, Enter
SHERWOOD_KEYS = [(70.0, "6"), (71.0, "2"), (72.0, "ENTER")]
SHERWOOD_END = 103.2                    # the reference goes on to the first month at 103.3 s


def main():
    build = Path(sys.argv[1] if len(sys.argv) > 1 else "build")
    ref_dir = Path(sys.argv[2] if len(sys.argv) > 2 else build / "ref")
    L = load_map(build / "main.map")
    music(build, L)
    opening(build, ref_dir, L)
    print("all checks passed")


if __name__ == "__main__":
    main()
