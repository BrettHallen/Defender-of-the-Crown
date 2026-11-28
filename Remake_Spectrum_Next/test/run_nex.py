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
        self.stop_at = None              # run() returns when the program gets here (stop())
        self.auto_from = None            # from then on (s), Enter after a wait of 1 s for a key (key_wait)
        self.auto_n, self.auto_at = 0, None   # the Enters so far; at = (n, f): f() before the n-th
        self.kw_start = self.kw_last = None
        self.release_at = None
        self.on_break = None
        self.poll_from = None            # from then on (s), Enter after 1 s of reading the keys without one
        self.poll_since = self.poll_last = None
        self.poll_keys = []              # those Enters: these keys first
        self.marks = []                  # the times of those Enters
        self.pokes = []                  # (s, address, word): written to the data segment then
        self.m.set_input_callback(self.port_in)
        self.m.set_output_callback(self.port_out)
        # breakpoints: every NEXTREG in the program, RST 08h's target, idle, frame_done
        self.nextregs = self._find_nextregs(0xA000, labels["code_end"])
        for a in self.nextregs:
            self.m.set_breakpoint(a)
        for a in (0x0008, labels["idle"], labels["frame_done"], labels["key_wait"], labels["key_none"], SENTINEL):
            self.m.set_breakpoint(a)
        # the Next's own credit card in the opening (ng_credit to ng_credit_end), and the choice of
        # character (ng_choose): their times, to take the card out of the screens compared (shown)
        self.watch = {labels[k]: k for k in ("ng_credit", "ng_credit_end", "ng_choose") if k in labels}
        self.seen = {}
        for a in self.watch:
            self.m.set_breakpoint(a)

    def shown(self):
        """the screens shown, as the reference's: the Next's own credit card left
        out (the remake has none), and the screens after it up to the choice of
        character shown that much sooner (the choice comes when the music ends,
        in both)"""
        if "ng_credit_end" not in self.seen:
            return self.frames
        t1, t2 = self.seen["ng_credit"], self.seen["ng_credit_end"]
        t3 = self.seen.get("ng_choose", float("inf"))
        out = []
        for t, s in self.frames:
            if t1 < t <= t2:
                continue
            out.append((t - (t2 - t1) if t2 < t < t3 else t, s))
        return out

    def key_polled(self):
        """no key (bios_key): Enter after 1 s of polls less than 0.1 s apart, from poll_from on"""
        t = self.t / CPU_HZ
        while self.pokes and t >= self.pokes[0][0]:
            _, a, w = self.pokes.pop(0)
            self.ds_poke(a, w)
        if self.poll_from is None or self.release_at is not None:
            return
        if self.poll_last is None or t - self.poll_last > 0.1:
            self.poll_since = t
        self.poll_last = t
        if t >= self.poll_from and t - self.poll_since >= 1.0:
            key = self.poll_keys.pop(0) if self.poll_keys else "ENTER"
            self.keys, self.release_at = {key}, self.t + int(0.08 * CPU_HZ)
            self.poll_since = t
            self.marks.append(t)

    def ds_poke(self, a, w):
        """a word into the data segment (at 4000h, slots 2-4)"""
        self.m.memory[0x4000 + a] = w & 0xFF
        self.m.memory[0x4001 + a] = w >> 8

    def key_waiting(self):
        """the program waits for a key (wait_key): Enter after 1 s, from auto_from on"""
        t = self.t / CPU_HZ
        if self.kw_last is None or t - self.kw_last > 0.05 or self.release_at is not None:
            self.kw_start = t
        self.kw_last = t
        if self.auto_from is not None and t >= self.auto_from and t - self.kw_start >= 1.0 and self.release_at is None:
            self.auto_n += 1
            if self.auto_at and self.auto_at[0] == self.auto_n:
                self.auto_at[1]()
            self.keys, self.release_at = {"ENTER"}, self.t + int(0.08 * CPU_HZ)
            self.kw_start = None

    def stop(self, addr):
        """run() to return once the program reaches addr"""
        self.stop_at = addr
        self.m.set_breakpoint(addr)

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
        elif code == 0x8E:              # M_GETDATE: 1 Jan 2026, 12:00:00 (MS-DOS's way)
            m.bc = ((2026 - 1980) << 9) | (1 << 5) | 1
            m.de = 12 << 11
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
            if self.release_at is not None and self.t >= self.release_at:
                self.keys, self.release_at = set(), None
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
            elif pc == L["key_wait"]:
                self.ret()
                self.key_waiting()
            elif pc == L["key_none"]:   # (then as idle)
                self.key_polled()
                self.ret()
                if m.iff1 and self.next_int is not None and self.t < self.next_int:
                    self.t = self.next_int
            elif pc == SENTINEL or pc == self.stop_at:
                return
            elif pc in self.watch:
                self.seen.setdefault(self.watch[pc], self.t / CPU_HZ)
                m.step_over_breakpoint()
            elif self.on_break and self.on_break(pc):   # a debugging breakpoint, handled (and stepped over)
                pass
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

    def data_segment(self):
        """the data segment (pages 12-14) as it is"""
        return b"".join(bytes(self.page(12 + k)) for k in range(3))

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


def compare(name, mine, ref, out_dir, slack=0.8, early=None, marks=None):
    """Exactly the reference's screens, each pixel for pixel, each first shown at
    about the same time (slack seconds, from each run's first screen: the Next
    reads the opening's pictures from the card first). A repeating animation
    (the fire) may run a cycle more or less, and the next scene start at
    another of its frames: it is timed by the BIOS clock's ticks and by the
    retraces, and how those two fall together differs from run to run, on the
    PC as here. The Next unpacks a picture from its 4-bit cache in about 0.12 s,
    where the remake shows it at once, and draws a dialog's letters and edges
    at about 0.2 and 0.4 ms each (a box of 13 lines: about 0.13 s): the times
    trail by that much, the waits after each counted from the end of its
    drawing, until a wait for the end of a tune or for a key puts them level
    again. early = (from, to): the reference's screens first shown in that
    time may come any time before (the Next's own end of the opening's wait,
    wait_tune), and are left to the caller to time. marks = (the Next's, the
    reference's): the times of the Enters pressed at its menus (1 s into each
    wait): each screen is timed from the last before it, in each, as the
    drawing's delays add up from month to month."""
    if mine and ref:
        d = mine[0][0] - ref[0][0]
        mine = [(t - d, s) for t, s in mine]
        if marks:
            marks = ([m - d for m in marks[0]], marks[1])
    def since(t, ms):
        k = sum(1 for m in ms if m <= t)
        return (k, t - ms[k - 1]) if k else (0, t)
    a, b = dict(), dict()
    for t, shot in mine:
        a.setdefault(shot, t)
    for t, shot in ref:
        b.setdefault(shot, t)
    if marks:
        sa = {x: since(a[x], marks[0]) for x in a}
        sb = {x: since(b[x], marks[1]) for x in b}
        for x in a:
            if x in b and sa[x][0] == sb[x][0] and sa[x][0]:
                a[x] = b[x] + sa[x][1] - sb[x][1]
    only_mine = [x for x in a if x not in b]
    only_ref = [x for x in b if x not in a]
    if only_mine or only_ref:
        for k, (shot, t, who) in enumerate([(x, a[x], "next") for x in only_mine[:3]] + [(x, b[x], "ref") for x in only_ref[:3]]):
            write_png(out_dir / f"{name}_{who}_{k}_at_{t:.2f}.png", shot, W, H)
        raise AssertionError(f"{name}: {len(only_mine)} screens the reference never shows (the first at "
                             f"{min(a[x] for x in only_mine) if only_mine else 0:.2f} s), {len(only_ref)} of its the "
                             f"Next never shows (the first at {min(b[x] for x in only_ref) if only_ref else 0:.2f} s): "
                             f"see {out_dir}/{name}_*.png")
    timed = [x for x in a if not (early and early[0] <= b[x] < early[1] and a[x] <= b[x])]
    worst = max(abs(a[x] - b[x]) for x in timed)
    if worst > slack:
        x = max(timed, key=lambda x: abs(a[x] - b[x]))
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
    music_end = None
    while nx.t < 75.5 * CPU_HZ:                    # (when the opening's Tandy music ends)
        nx.run(seconds=nx.t / CPU_HZ + 0.05)
        if music_end is None and nx.t > 10 * CPU_HZ and not nx.m.memory[L["drv_playing"]]:
            music_end = nx.t / CPU_HZ
    ref = [f for f in read_rec(ref_dir / "opening.rec") if f[0] <= 75]
    n, shown, ref_shown, worst = compare("opening", nx.shown(), ref, out, early=CHOICE_UP)
    choice = next(t for t, s in nx.frames if s == next(s for t, s in ref if t >= CHOICE_UP[0]))
    # (the Next's own credit card puts the introduction's picture about 2.9 s later: its wait of 180 ticks
    # now ends about 0.6 s after the music, and the choice comes then)
    assert music_end and 0 <= choice - music_end < 1.0, f"the choice at {choice:.2f} s, the music's end at {music_end}"
    print(f"2. the opening, no keys: the reference's {n} different screens, pixel for pixel, "
          f"first shown within {worst * 1000:.0f} ms of its ({shown} screens shown, the reference {ref_shown}); "
          f"{nx.calls} file calls. The choice of character {(choice - music_end) * 1000:.0f} ms after the Tandy "
          f"music's end, at {choice:.1f} s (the reference: 68.0 s, at the speaker tune's)")

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
    n, shown, ref_shown, worst = compare("skip", nx.shown(), ref, out)
    print(f"2. S at 5 s: the reference's {n} different screens, pixel for pixel, "
          f"first shown within {worst * 1000:.0f} ms of its ({shown} screens shown, the reference {ref_shown})")

    # the choice made (6, 2, then Enter), through Sherwood
    nx = Next(nex, L, build / "sd" / "DOTC")
    ref = [f for f in read_rec(ref_dir / "sherwood.rec") if f[0] <= SHERWOOD_END]
    d = press_keys(nx, SHERWOOD_KEYS, ref)
    nx.run(seconds=SHERWOOD_END + d)
    n, shown, ref_shown, worst = compare("sherwood", nx.shown(), ref, out, early=CHOICE_UP)
    print(f"2. the choice and Sherwood: the reference's {n} different screens, pixel for pixel, "
          f"first shown within {worst * 1000:.0f} ms of its ({shown} screens shown, the reference {ref_shown})")


def first_month(build, ref_dir, L):
    """the setup and the player's first month: the status panel, the orders, Pass"""
    nex = build / "sd" / "DOTC" / "DOTC.NEX"
    out = build / "check"
    nx = Next(nex, L, build / "sd" / "DOTC")
    ref = [f for f in read_rec(ref_dir / "pass.rec") if f[0] <= MONTH_END]
    state = []
    d = press_keys(nx, SHERWOOD_KEYS + MONTH_KEYS, ref,
                   at=(MONTH_DS_AT, lambda: state.append(nx.data_segment())))
    state = state[0]
    nx.stop(L["ai_turn"])                # the player's turn over: the computer lords' next
    nx.run(seconds=MONTH_END + d + 5)
    assert nx.m.pc == L["ai_turn"], "the player's turn should be over"

    n, shown, ref_shown, worst = compare("month", nx.shown(), ref, out, early=CHOICE_UP)
    print(f"3. the setup, the status panel, the orders and Pass: the reference's {n} different screens, pixel for "
          f"pixel, first shown within {worst * 1000:.0f} ms of its ({shown} screens shown, the reference {ref_shown})")
    # the game's state at the orders: the records the setup and the month wrote
    want = (ref_dir / "month_ds.bin").read_bytes()
    for name, lo, hi in DS_CHECKED:
        diff = [o for o in range(lo, hi) if state[o] != want[o]]
        assert not diff, f"{name}: the data segment differs at " + ", ".join(f"{o:04X}h ({state[o]:02X}, the reference {want[o]:02X})" for o in diff[:8])
    print(f"3. the data segment at the orders: " + ", ".join(n for n, _, _ in DS_CHECKED) + " as the reference's")


def months(build, ref_dir, L):
    """the computer lords' turns: Pass month after month (Enter at each menu, as the
    reference's months.rec), to the seventh Enter"""
    nex = build / "sd" / "DOTC" / "DOTC.NEX"
    out = build / "check"
    nx = Next(nex, L, build / "sd" / "DOTC")
    ref = read_rec(ref_dir / "months.rec")
    end = ref[-1][0]
    state = []
    d = press_keys(nx, SHERWOOD_KEYS + MONTH_KEYS, [f for f in ref if f[0] < 1])
    nx.auto_from = MONTHS_AUTO + d
    nx.auto_at = (MONTHS_ENTERS, lambda: state.append((nx.t / CPU_HZ, nx.data_segment())))
    marks = []
    kw = nx.key_waiting
    def key_waiting():
        n = nx.auto_n
        kw()
        if nx.auto_n != n:
            marks.append(nx.t / CPU_HZ)
    nx.key_waiting = key_waiting
    nx.run(until=lambda: bool(state))
    ref_marks = [float(x) for x in (ref_dir / "months.marks").read_text().split()]
    # (the slack: in a month the Next's drawing falls up to 2 s behind the remake's, which draws at once:
    # its battle redraws the armies' box every round, about 0.15 s a time)
    n, shown, ref_shown, worst = compare("months", nx.shown(), ref, out, slack=2.0, early=CHOICE_UP,
                                         marks=(marks, ref_marks))
    print(f"4. the computer lords' turns, {MONTHS_ENTERS} months: the reference's {n} different screens, pixel for "
          f"pixel, first shown within {worst * 1000:.0f} ms of its ({shown} screens shown, the reference {ref_shown})")
    want = (ref_dir / "months_ds.bin").read_bytes()
    t, got = state[0]
    for name, lo, hi in DS_CHECKED + DS_WAR:
        diff = [o for o in range(lo, hi) if got[o] != want[o]]
        assert not diff, f"{name}: the data segment differs at " + ", ".join(f"{o:04X}h ({got[o]:02X}, the reference {want[o]:02X})" for o in diff[:8])
    print(f"4. the data segment then (at {t:.1f} s, the reference's at {end:.1f} s): as the reference's, "
          f"with the computer lords' search and orders")


def buy(build, ref_dir, L):
    """Buy Home Army: 3 soldiers, a knight refused (too dear), one sold back that
    wasn't bought (refused), a soldier sold back, Continue (the reference's buy.rec)"""
    nex = build / "sd" / "DOTC" / "DOTC.NEX"
    nx = Next(nex, L, build / "sd" / "DOTC")
    ref = read_rec(ref_dir / "buy.rec")
    d = press_keys(nx, SHERWOOD_KEYS + BUY_KEYS, [f for f in ref if f[0] < 1])
    nx.run(seconds=ref[-1][0] + d + 1.5)
    n, shown, ref_shown, worst = compare("buy", nx.shown(), ref, build / "check", slack=1.5, early=CHOICE_UP)
    print(f"5. Buy Home Army: the reference's {n} different screens, pixel for pixel, first shown within "
          f"{worst * 1000:.0f} ms of its ({shown} screens shown, the reference {ref_shown})")
    want, got = (ref_dir / "buy_ds.bin").read_bytes(), nx.data_segment()
    for name, lo, hi in DS_CHECKED + DS_WAR:
        diff = [o for o in range(lo, hi) if got[o] != want[o]]
        assert not diff, f"{name}: the data segment differs at " + ", ".join(f"{o:04X}h ({got[o]:02X}, the reference {want[o]:02X})" for o in diff[:8])
    print("5. the data segment then: as the reference's")


# Buy Home Army (down x3, Enter); right x3; down, right (refused), left (refused); up, left; down x4, Enter
BUY_KEYS = [(110.0, "2"), (110.5, "2"), (111.0, "2"), (112.0, "ENTER"), (114.0, "6"), (115.0, "6"), (116.0, "6"),
            (117.0, "2"), (118.0, "6"), (119.0, "4"), (120.0, "8"), (121.0, "4"), (122.0, "2"), (122.5, "2"),
            (123.0, "2"), (123.5, "2"), (124.5, "ENTER")]


def siege(build, ref_dir, L):
    """the player's siege: his army (40 soldiers, 6 knights, a catapult) put in
    Lincolnshire (his, as the reference's REF_POKE), sent into Norfolk (a
    Norman's castle): the bombardment (the keys read for a second get Enter,
    or the next of SIEGE_KEYS: the ammunition, the catapult's pull), then the
    battle (the reference's siege.rec)"""
    nex = build / "sd" / "DOTC" / "DOTC.NEX"
    nx = Next(nex, L, build / "sd" / "DOTC")
    ref = read_rec(ref_dir / "siege.rec")
    nx.run(until=lambda: bool(nx.frames))
    d = nx.frames[0][0] - ref[0][0]
    nx.pokes = [(SIEGE_POKE_AT + d, a, w) for a, w in SIEGE_POKES]
    nx.poll_from, nx.poll_keys = SIEGE_POLL + d, list(SIEGE_KEYS)
    press_keys(nx, SHERWOOD_KEYS + SIEGE_ORDERS, ref)
    ref_marks = [float(x) for x in (ref_dir / "siege.marks").read_text().split()]
    # the bombardment's Enters time its screens; the battle's (a second into
    # its polls, the Next's drawing slower with many men) change nothing
    ref_marks = ref_marks[:SIEGE_MARKS]
    nx.run(until=lambda: len(nx.marks) >= SIEGE_MARKS)
    nx.run(until=lambda: nx.frames[-1][1] == ref[-1][1],      # (to the reference's last screen)
           seconds=nx.marks[-1] + ref[-1][0] - ref_marks[-1] + 4.0)
    n, shown, ref_shown, worst = compare("siege", nx.shown(), ref, build / "check", slack=2.0, early=CHOICE_UP,
                                         marks=(nx.marks[:SIEGE_MARKS], ref_marks))
    print(f"6. a siege (the bombardment, the battle, then the next month to its orders): the reference's {n} different screens, pixel for pixel, first shown "
          f"within {worst * 1000:.0f} ms of its ({shown} screens shown, the reference {ref_shown})")
    want, got = (ref_dir / "siege_ds.bin").read_bytes(), nx.data_segment()
    for name, lo, hi in DS_CHECKED + DS_WAR + DS_SIEGE:
        diff = [o for o in range(lo, hi) if got[o] != want[o]]
        assert not diff, f"{name}: the data segment differs at " + ", ".join(f"{o:04X}h ({got[o]:02X}, the reference {want[o]:02X})" for o in diff[:8])
    print("6. the data segment then: as the reference's")


SIEGE_POKE_AT = 107.0                   # at the first orders: the army in Lincolnshire, the player's
SIEGE_POKES = [(0x00C1, 6), (0x0151, 6), (0x0153, 6), (0x0155, 40), (0x0157, 6), (0x0159, 1), (0x06F3, 1)]
SIEGE_ORDERS = [(110.0, "2"), (111.0, "ENTER"), (113.0, "ENTER"), (115.0, "6"), (116.0, "ENTER")]  # Seek Conquest, Send, Norfolk
SIEGE_POLL = 117.0
SIEGE_MARKS = 17                        # the bombardment's Enters (the last, the battle's start)
SIEGE_KEYS = ["ENTER", "ENTER", "ENTER", "ENTER", "2", "ENTER", "ENTER", "2", "ENTER", "ENTER"]
DS_SIEGE = [("the siege", 0xA82, 0xA90)]


def tournament(build, ref_dir, L):
    """Hold Tournament at the first orders (the keys read for a second get
    Enter, as the reference's REF_POLL): the fanfare, jousting for fame, the
    knights riding in, a near miss and another pass, then the next month to
    its orders (the reference's tourn.rec)"""
    nex = build / "sd" / "DOTC" / "DOTC.NEX"
    nx = Next(nex, L, build / "sd" / "DOTC")
    ref = read_rec(ref_dir / "tourn.rec")
    nx.run(until=lambda: bool(nx.frames))
    d = nx.frames[0][0] - ref[0][0]
    nx.poll_from = TOURN_POLL + d
    press_keys(nx, SHERWOOD_KEYS, ref)
    ref_marks = [float(x) for x in (ref_dir / "tourn.marks").read_text().split()]
    nx.run(until=lambda: nx.frames[-1][1] == ref[-1][1], seconds=ref[-1][0] + d + 20.0)    # to its last screen
    # The knights ride in when the tournament's tune ends: on the Next, when
    # its Tandy music does, about 4.6 s before the reference's speaker timing
    # (wait_tune). The screens up to there, and from there on (from the first
    # of the knights riding in), are each timed in their own part.
    split = next(s for t, s in ref if t >= TOURN_RIDE_IN)
    frames = nx.shown()
    at = next(t for t, s in frames if s == split)
    ref_at = next(t for t, s in ref if s == split)
    nx_a, nx_b = [f for f in frames if f[0] < at], [f for f in frames if f[0] >= at]
    ref_a, ref_b = [f for f in ref if f[0] < ref_at], [f for f in ref if f[0] >= ref_at]
    for x in set(s for _, s in nx_a) & set(s for _, s in ref_b):     # (screens of both: their first)
        nx_b = [f for f in nx_b if f[1] != x]
        ref_b = [f for f in ref_b if f[1] != x]
    n, shown, ref_shown, worst = compare("tourn", nx_a, ref_a, build / "check", slack=2.0, early=CHOICE_UP,
                                         marks=([m for m in nx.marks if m < at], [m for m in ref_marks if m < ref_at]))
    # (the Next draws the outcome's knights over the stands at about 34 frames
    # a second, the remake at 60, and its dialogs' letters take time: by the
    # next month's orders it trails by about 3 s)
    n2, shown2, ref_shown2, worst2 = compare("tourn", nx_b, ref_b, build / "check", slack=4.0,
                                             marks=([m for m in nx.marks if m >= at], [m for m in ref_marks if m >= ref_at]))
    n, shown, ref_shown, worst = n + n2, shown + shown2, ref_shown + ref_shown2, max(worst, worst2)
    print(f"7. a tournament (the fanfare, a joust for fame, two passes, then the next month to its orders): the "
          f"reference's {n} different screens, pixel for pixel, first shown within {worst * 1000:.0f} ms of its "
          f"({shown} screens shown, the reference {ref_shown})")
    want, got = (ref_dir / "tourn_ds.bin").read_bytes(), nx.data_segment()
    for name, lo, hi in DS_CHECKED + DS_WAR + DS_TOURN:
        diff = [o for o in range(lo, hi) if got[o] != want[o]]
        assert not diff, f"{name}: the data segment differs at " + ", ".join(f"{o:04X}h ({got[o]:02X}, the reference {want[o]:02X})" for o in diff[:8])
    print("7. the data segment then: as the reference's")


TOURN_POLL = 110.0
TOURN_RIDE_IN = 133.3                   # the reference's knights ride in (its tune's end)
DS_TOURN = [("the tournament", 0x3D, 0x43), ("the beats", 0x5F, 0x67), ("the joust", 0xD0C, 0xD24)]


def conquest(build, ref_dir, L):
    """the player's orders on the map: Read Map (Lincolnshire), Seek Conquest:
    Transfer Forces (4 soldiers), then the campaign army sent into Lincolnshire,
    to the next month's orders (the reference's conq.rec)"""
    nex = build / "sd" / "DOTC" / "DOTC.NEX"
    nx = Next(nex, L, build / "sd" / "DOTC")
    ref = read_rec(ref_dir / "conq.rec")
    d = press_keys(nx, SHERWOOD_KEYS + CONQ_KEYS, [f for f in ref if f[0] < 1])
    nx.run(seconds=ref[-1][0] + d + 1.5)
    n, shown, ref_shown, worst = compare("conquest", nx.shown(), ref, build / "check", slack=1.5, early=CHOICE_UP)
    print(f"5. Read Map, Transfer Forces and a march into Lincolnshire: the reference's {n} different screens, pixel "
          f"for pixel, first shown within {worst * 1000:.0f} ms of its ({shown} screens shown, the reference {ref_shown})")
    want, got = (ref_dir / "conq_ds.bin").read_bytes(), nx.data_segment()
    for name, lo, hi in DS_CHECKED + DS_WAR:
        diff = [o for o in range(lo, hi) if got[o] != want[o]]
        assert not diff, f"{name}: the data segment differs at " + ", ".join(f"{o:04X}h ({got[o]:02X}, the reference {want[o]:02X})" for o in diff[:8])
    print("5. the data segment then: as the reference's")


# Read Map (down x4, Enter), Read Territory, keypad 6 (Lincolnshire), Enter; Continue; Seek Conquest (up x3);
# Transfer Forces: right x4, down x3 to Continue; Send forth: keypad 6, Enter
CONQ_KEYS = [(110.0, "2"), (110.5, "2"), (111.0, "2"), (111.5, "2"), (112.0, "ENTER"), (114.0, "ENTER"), (116.0, "6"),
             (117.0, "ENTER"), (119.0, "2"), (120.0, "ENTER"), (122.0, "8"), (122.5, "8"), (123.0, "8"), (124.0, "ENTER"),
             (126.0, "2"), (127.0, "ENTER"), (129.0, "6"), (129.5, "6"), (130.0, "6"), (130.5, "6"),
             (131.0, "2"), (131.5, "2"), (132.0, "2"), (133.0, "ENTER"), (135.0, "ENTER"), (137.0, "6"), (138.0, "ENTER")]


# the computer lords' own: the search for a target, their last orders, the battles' damage
DS_WAR = [("the search", 0x69, 0x9F), ("the last orders", 0x24B, 0x24B + 14), ("the damage", 0xB4C, 0xB50)]
MONTHS_AUTO = 114.0                     # the reference's months.rec: REF_AUTO=114, REF_DS_AT=9
MONTHS_ENTERS = 9


# what the setup and the month write (game.h), checked against the reference's
DS_CHECKED = [("the random numbers", 0x25, 0x27), ("the month, year, morale, event", 0x43, 0x4B),
              ("the sides", 0x9F, 0x9F + 24 * 7), ("the armies", 0x147, 0x147 + 10 * 26),
              ("the enmities", 0x416, 0x416 + 14 * 7), ("the ladies", 0x478, 0x478 + 8 * 4),
              ("the territories", 0x695, 0x695 + 15 * 19), ("the status panel's lines", 0x3FE1, 0x4074),
              ("D_RANDOM", 0x5B, 0x5F)]
# down five times to Pass, then Enter (the reference's pass.rec)
MONTH_KEYS = [(110.0, "2"), (110.5, "2"), (111.0, "2"), (111.5, "2"), (112.0, "2"), (113.0, "ENTER")]
MONTH_DS_AT = 108.0                     # the reference's month_ds.bin: the orders menu up
MONTH_END = 114.18                      # then its computer lords' turns


def press_keys(nx, keys, ref, at=None):
    """the keys (seconds, key), each held 80 ms, at the reference's times from
    the first screen (the Next's first comes later: it reads the pictures
    first); at = (seconds, f): f() at that time too. Returns the Next's lag."""
    nx.run(until=lambda: bool(nx.frames))
    d = nx.frames[0][0] - ref[0][0]
    for t, key in keys:
        if at and t > at[0]:
            nx.run(seconds=at[0] + d)
            at[1]()
            at = None
        nx.run(seconds=t + d)
        nx.keys = {key}
        nx.run(seconds=t + d + 0.08)
        nx.keys = set()
    return d


# the reference shows the choice of character at 68.0 s, when the speaker tune's
# timing ends; the Next when the Tandy music does, about 15 s before (wait_tune)
CHOICE_UP = (67.9, 70.0)

# the keys for the reference's sherwood.rec (test/ref/README.md): keypad 6, 2, Enter
SHERWOOD_KEYS = [(70.0, "6"), (71.0, "2"), (72.0, "ENTER")]
SHERWOOD_END = 103.2                    # the reference goes on to the first month at 103.3 s


def main():
    build = Path(sys.argv[1] if len(sys.argv) > 1 else "build")
    ref_dir = Path(sys.argv[2] if len(sys.argv) > 2 else build / "ref")
    L = load_map(build / "main.map")
    music(build, L)
    opening(build, ref_dir, L)
    first_month(build, ref_dir, L)
    months(build, ref_dir, L)
    buy(build, ref_dir, L)
    conquest(build, ref_dir, L)
    siege(build, ref_dir, L)
    tournament(build, ref_dir, L)
    print("all checks passed")


if __name__ == "__main__":
    main()
