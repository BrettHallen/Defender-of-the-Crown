#!/usr/bin/env python3
"""
Defender of the Crown (1986) - Spectrum Next remake
Nov 2026 using Claude Opus 5.5
"Guided" by Brett Hallen

run_nex.py: a check without a Next. Loads the .nex file as NextZXOS does and
runs the program on a Z80 emulator (pip install z80), with a small model of
the Next around it: the Next registers (and the NEXTREG instructions, which
a plain Z80 doesn't have), Layer 2 320x256 and its palette, the AY, the keys,
and the CTC's interrupts through the hardware IM2 controller. It checks:

  1. the set-up: Layer 2's screen is the converter's preview pixel for pixel;
     IM2 with the vector table, CTC 0 alone enabled and programmed
  2. the music driver: for each of the eight songs, the Z80 port (tandy.asm)
     and the Python one (tools/convert.py's Tandy, from the Mac remake's
     sound.c) run side by side, one driver interrupt at a time, and the AY
     must hold, after every one, what the Tandy chip would (through the
     period and volume tables)
  3. the timing: the whole program with CTC interrupts arriving; each one
     acknowledged; the driver run 1193182 / tempo times a second
  4. the keys: 3 starts the third tune; Space starts it again

and writes the screen it saw to seen_on_next.png.

Usage: python3 run_nex.py [BUILD-FOLDER]   (default: build; reads dotc_title.nex,
       title.map, title.png, bg.bin, ay_period.bin, ay_volume.bin there)
"""
import struct
import sys
import zlib
from pathlib import Path

import z80

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "tools"))
from convert import Tandy              # noqa: E402  the reference driver

ORDER = [5, 2, 0, 1, 3, 4] + list(range(6, 112))
SENTINEL = 0x7FF0                      # a return address for routines called from the test
KEY_SONGS = [5, 6, 4, 2, 0, 3, 7, 1]
PIT_HZ = 1193182
CTC_HZ = 28_000_000 / 256 / 64         # the CTC at 28 MHz (video timing 0), time constant 64


def load_nex(path):
    d = Path(path).read_bytes()
    assert d[:4] == b"Next" and d[4:8] == b"V1.2", "not a V1.2 .nex"
    count, flags = d[9], d[10]
    assert flags == 0, "no loading screen expected"
    sp, pc = struct.unpack_from("<HH", d, 12)
    present = [b for b in range(112) if d[18 + b]]
    assert len(present) == count, "bank count doesn't match the bank flags"
    banks, o = {}, 512
    for b in ORDER:
        if d[18 + b]:
            banks[b] = bytearray(d[o:o + 16384])
            o += 16384
    assert o == len(d), "the file's length doesn't match its banks"
    return banks, sp, pc, d[139]


def load_map(path):
    labels = {}
    for line in Path(path).read_text().splitlines():
        if ":" in line:
            a, n = line.split(":", 1)
            labels[n.strip().lstrip(".")] = int(a, 16)
    return labels


class Next:
    def __init__(self, nex, labels):
        self.L = labels
        self.banks, sp, pc, entry = load_nex(nex)
        for b in range(112):
            self.banks.setdefault(b, bytearray(16384))
        self.m = z80.Z80Machine()
        mem = bytearray(65536)
        mem[0x4000:0x8000] = self.banks[5]
        mem[0x8000:0xC000] = self.banks[2]
        mem[0xC000:0x10000] = self.banks[entry]
        self.m.set_memory_block(0, mem)
        self.m.pc, self.m.sp = pc, sp
        self.m.set_breakpoint(SENTINEL)
        self.reg = {0x05: 0x00, 0x08: 0x00, 0x09: 0x00, 0x11: 0x00, 0x12: 9, 0x14: 0xE3, 0x70: 0x00}
        self.sel = 0
        self.l2_on = False
        self.clip, self.clip_i = [0, 255, 0, 191], 0
        self.pal = [0] * 256            # Layer 2 first palette, 9-bit
        self.pal_i, self.pal_half = 0, None
        self.ay = [0] * 16
        self.ay_sel, self.ay_chip = 0, 0
        self.ctc = []                   # what was written to CTC 0
        self.c9_acks = 0
        self.keys = set()               # held: "1"-"8", " "
        self.m.set_input_callback(self.port_in)
        self.m.set_output_callback(self.port_out)

    # the Next registers
    def nextreg(self, r, v):
        self.reg[r] = v
        if r == 0x1C and v & 1:
            self.clip_i = 0
        elif r == 0x18:
            self.clip[self.clip_i & 3] = v
            self.clip_i += 1
        elif r == 0x40:
            self.pal_i, self.pal_half = v, None
        elif r == 0x43:
            assert (v >> 4) & 7 == 1, "palette writes should go to Layer 2's first palette"
        elif r == 0x44:
            if self.pal_half is None:
                self.pal_half = v
            else:
                self.pal[self.pal_i & 255] = (self.pal_half << 1) | (v & 1)
                self.pal_i += 1
                self.pal_half = None
        elif r == 0x69:
            self.l2_on = bool(v & 0x80)
        elif r == 0xC9 and v & 1:
            self.c9_acks += 1

    def port_in(self, port):
        if port == 0x253B:
            return self.reg.get(self.sel, 0)
        if port & 0xFF == 0xFE:         # the keyboard: rows by the high byte, 0 = held
            v = 0xFF
            hi = port >> 8
            if not hi & 0x08:           # F7FEh: 1-5 on bits 0-4
                for i in range(5):
                    if str(i + 1) in self.keys:
                        v &= ~(1 << i)
            if not hi & 0x10:           # EFFEh: 6, 7, 8 on bits 4, 3, 2
                for k, bit in (("6", 4), ("7", 3), ("8", 2)):
                    if k in self.keys:
                        v &= ~(1 << bit)
            if not hi & 0x80:           # 7FFEh: Space on bit 0
                if " " in self.keys:
                    v &= ~1
            return v & 0xFF
        return 0xFF

    def port_out(self, port, v):
        if port == 0x243B:
            self.sel = v
        elif port == 0x253B:
            self.nextreg(self.sel, v)
        elif port == 0x123B:
            if not v & 0x10:
                self.l2_on = bool(v & 2)
        elif port == 0xFFFD:
            if v & 0x80:
                assert (v & 0x1C) == 0x1C, "a Turbosound select needs bits 4-2 set"
                assert self.reg[0x08] & 2, "Turbosound should be on before selecting a chip"
                self.ay_chip = {3: 0, 2: 1, 1: 2}[v & 3]
            else:
                self.ay_sel = v & 0x0F
        elif port == 0xBFFD:
            if self.ay_chip == 0:
                self.ay[self.ay_sel] = v
        elif port == 0x183B:
            self.ctc.append(v)

    def step(self):
        """one instruction, the Next's NEXTREG included"""
        m = self.m
        pc = m.pc
        op = m.memory[pc], m.memory[(pc + 1) & 0xFFFF]
        if op == (0xED, 0x91):          # NEXTREG n, v
            self.nextreg(m.memory[pc + 2], m.memory[pc + 3])
            m.pc = pc + 4
        elif op == (0xED, 0x92):        # NEXTREG n, A
            self.nextreg(m.memory[pc + 2], m.a)
            m.pc = pc + 3
        else:
            m.ticks_to_stop = 1
            m.run()
        assert 0x8000 <= m.pc < self.L["code_end"] or m.pc == SENTINEL, f"PC left the program: {m.pc:04X}"

    def run_to(self, addr, limit=2_000_000):
        for _ in range(limit):
            if self.m.pc == addr:
                return
            self.step()
        raise AssertionError(f"never reached {addr:04X}")

    def call(self, addr, a=None):
        """a routine with no NEXTREG in it, at full speed: CALL it, stop at the return"""
        m = self.m
        if a is not None:
            m.a = a
        m.sp = (m.sp - 2) & 0xFFFF
        m.memory[m.sp] = SENTINEL & 0xFF
        m.memory[(m.sp + 1) & 0xFFFF] = SENTINEL >> 8
        m.pc = addr
        while m.pc != SENTINEL:
            m.ticks_to_stop = 10_000_000
            m.run()

    def interrupt(self):
        """the CTC's interrupt through hardware IM2: vector (I, 06h)"""
        m = self.m
        assert m.iff1, "interrupts are off"
        m.sp = (m.sp - 2) & 0xFFFF
        m.memory[m.sp] = m.pc & 0xFF
        m.memory[(m.sp + 1) & 0xFFFF] = m.pc >> 8
        v = (m.i << 8) | 0x06
        m.pc = m.memory[v] | m.memory[v + 1] << 8
        m.iff1 = m.iff2 = 0

    def screen(self):
        assert self.l2_on, "Layer 2 is off"
        assert (self.reg[0x70] >> 4) & 3 == 1, "Layer 2 is not in 320x256 mode"
        assert self.clip == [0, 159, 0, 255], f"clip window {self.clip}"
        bank = self.reg[0x12]
        data = b"".join(self.banks[bank + i] for i in range(5))
        rgb = bytearray()
        for y in range(256):
            for x in range(320):
                c = self.pal[data[x * 256 + y]]
                assert c >> 1 != self.reg[0x14], "a transparent pixel"
                r, g, b = c >> 6, (c >> 3) & 7, c & 7
                rgb += bytes(((r * 255 + 3) // 7, (g * 255 + 3) // 7, (b * 255 + 3) // 7))
        return rgb

    def playing(self):
        return self.m.memory[self.L["drv_playing"]] != 0


def read_png_rgb(path):
    d = Path(path).read_bytes()
    o, idat, w = 8, b"", 0
    while o < len(d):
        n = struct.unpack_from(">I", d, o)[0]
        t = d[o + 4:o + 8]
        if t == b"IHDR":
            w = struct.unpack_from(">I", d, o + 8)[0]
        elif t == b"IDAT":
            idat += d[o + 8:o + 8 + n]
        o += 12 + n
    raw = zlib.decompress(idat)
    row = w * 3 + 1
    return b"".join(raw[y * row + 1:(y + 1) * row] for y in range(len(raw) // row))


def write_png(path, rgb, w, h):
    raw = b"".join(b"\0" + bytes(rgb[y * w * 3:(y + 1) * w * 3]) for y in range(h))
    ch = lambda t, x: struct.pack(">I", len(x)) + t + x + struct.pack(">I", zlib.crc32(t + x) & 0xFFFFFFFF)
    Path(path).write_bytes(b"\x89PNG\r\n\x1a\n" + ch(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                           + ch(b"IDAT", zlib.compress(raw)) + ch(b"IEND", b""))


class Expect:
    """what the AY should hold for the Python driver's chip registers"""
    def __init__(self, build):
        p = (build / "ay_period.bin").read_bytes()
        self.period = [p[2 * n] | p[2 * n + 1] << 8 for n in range(1024)]
        self.volume = list((build / "ay_volume.bin").read_bytes())

    def ay(self, d):
        out = []
        for c in range(3):
            pr = self.period[d.regs[c] & 0x3FF]
            out += [pr & 255, pr >> 8]
        return out + [self.volume[d.regs[4 + c]] for c in range(3)]


def ay_now(nx):
    return nx.ay[0:6] + nx.ay[8:11]


def main():
    build = Path(sys.argv[1] if len(sys.argv) > 1 else "build")
    L = load_map(build / "title.map")
    bg = (build / "bg.bin").read_bytes()
    ex = Expect(build)
    nex = build / "dotc_title.nex"

    # 1. the set-up, up to the main loop
    nx = Next(nex, L)
    nx.run_to(L["main_loop"])
    shot = nx.screen()
    assert shot == read_png_rgb(build / "title.png"), "the screen differs from the converter's preview"
    write_png(build / "seen_on_next.png", shot, 320, 256)
    assert nx.m.i == L["vectors"] >> 8 and L["vectors"] & 0xFF == 0, "I and the vector table"
    v = L["vectors"] + 6
    assert nx.m.memory[v] | nx.m.memory[v + 1] << 8 == L["ctc_isr"], "the CTC 0 vector"
    assert nx.reg[0xC0] & 0xE1 == 0x01, "hardware IM2 with vectors 00h-1Fh"
    assert nx.reg[0xC4] == 0 and nx.reg[0xC5] == 0x01 and nx.reg[0xC6] == 0, "only CTC 0 may interrupt"
    assert nx.ctc == [0x03, 0x03, 0xA7, 64], f"CTC 0 programming {nx.ctc}"
    assert nx.ay[7] == 0x38 and nx.reg[0x09] & 0x20, "the mixer and mono"
    assert nx.m.iff1, "interrupts on"
    assert nx.playing(), "the opening theme should be playing"
    print("1. set-up: the screen matches the preview; IM2, CTC 0 at 28 MHz / 256 / 64; the opening theme started")

    # 2. the driver, song by song, against the Python one
    for song in range(8):
        nx = Next(nex, L)
        nx.run_to(L["main_loop"])
        d = Tandy(bg)
        nx.call(L["drv_start"], a=song)
        d.start(song)
        assert ay_now(nx) == ex.ay(d), f"song {song}: after the start"
        tempo = nx.m.memory[L["drv_tempo"]] | nx.m.memory[L["drv_tempo"] + 1] << 8
        assert tempo == d.tempo
        limit = int(PIT_HZ / tempo * 240)            # four minutes
        loops = 0
        for t in range(limit):
            nx.call(L["drv_interrupt"])
            d.interrupt()
            if d.restarted:
                loops += 1
                d.restarted = False
            assert ay_now(nx) == ex.ay(d), f"song {song}: the AY differs after interrupt {t + 1}"
            assert nx.playing() == d.playing, f"song {song}: playing differs after interrupt {t + 1}"
            if not d.playing:
                break
        secs = (t + 1) * tempo / PIT_HZ
        end = f"ended after {secs:.1f} s" if not d.playing else f"still playing at {secs:.0f} s"
        print(f"2. song {song} (key {KEY_SONGS.index(song) + 1}, tempo {tempo}, {PIT_HZ / tempo:.1f} a second): "
              f"{t + 1} interrupts identical, {end}" + (f", looped {loops} time(s)" if loops else ""))

    # 3. the timing: CTC interrupts into the running program
    nx = Next(nex, L)
    nx.run_to(L["main_loop"])
    d = Tandy(bg)
    d.start(5)
    tempo = d.tempo
    step = 698                                       # ctc_steps[0]
    acc, runs = 0, 0
    seconds = 10
    for k in range(int(CTC_HZ * seconds)):
        for _ in range(7):                           # the main loop goes on between interrupts
            nx.step()
        nx.interrupt()
        before = nx.c9_acks
        while True:                                  # the interrupt routine, back to the main loop
            nx.step()
            if nx.m.iff1 and L["main_loop"] <= nx.m.pc < L["ctc_isr"]:
                break
        assert nx.c9_acks == before + 1, "the interrupt wasn't acknowledged in NextReg C9h"
        acc += step
        if acc >= tempo:
            acc -= tempo
            runs += 1
            d.interrupt()
        assert ay_now(nx) == ex.ay(d), f"the AY differs after CTC interrupt {k + 1}"
    rate = runs / seconds
    print(f"3. timing: {int(CTC_HZ * seconds)} CTC interrupts in {seconds} s, each acknowledged; "
          f"the driver ran {runs} times ({rate:.1f} a second; the original {PIT_HZ / tempo:.1f})")
    assert abs(rate - PIT_HZ / tempo) < 0.5

    # 4. the keys
    for key, code in (("3", 2), (" ", 8)):
        nx.keys = {key}
        for _ in range(3000):
            nx.step()
            if nx.m.memory[L["last_key"]] == code and nx.m.pc == L["main_loop"]:
                break
        else:
            raise AssertionError(f"key {key!r} not seen")
        nx.keys = set()
        d.start(KEY_SONGS[2])           # the same chip: its tone registers keep the last notes, as the Tandy's
        assert ay_now(nx) == ex.ay(d) and nx.playing(), f"key {key!r}: song {KEY_SONGS[2]} didn't start"
    print(f"4. keys: 3 starts song {KEY_SONGS[2]}; Space starts it again")
    print("all checks passed")


if __name__ == "__main__":
    main()
