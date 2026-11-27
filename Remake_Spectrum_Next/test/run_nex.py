#!/usr/bin/env python3
"""
Defender of the Crown (1986) - Spectrum Next remake
Nov 2026 using Claude Opus 5.5
"Guided" by Brett Hallen

run_nex.py: a check without a Next. Loads the .nex file as NextZXOS does and
runs the program on a Z80 emulator (pip install z80), with a small model of
the Next around it: the Next registers (and the NEXTREG instructions, which
a plain Z80 doesn't have), MMU slot 3, Layer 2 320x256 and its two palettes,
the AY, the keys, the CTC's interrupts through the hardware IM2 controller,
and esxDOS's file calls (RST 08h) reading the SD card's files from build/sd/DOTC, the game's folder.
It checks:

  1. the set-up: the title loaded from the SD card, Layer 2's screen the
     converter's preview pixel for pixel; IM2 with the vector table, CTC 0
     alone enabled and programmed
  2. the music driver: for each of the eight songs, the Z80 port (tandy.asm)
     and the Python one (tools/convert.py's Tandy, from the Mac remake's
     sound.c) run side by side, one driver interrupt at a time, and the AY
     must hold, after every one, what the Tandy chip would (through the
     period and volume tables)
  3. the timing: the whole program with CTC interrupts arriving; each one
     acknowledged; the driver run 1193182 / tempo times a second
  4. the keys: 3 starts the third tune; Space starts it again
  5. the pictures: P steps through all 20 and O back, each screen the
     converter's preview pixel for pixel, the two buffers and palettes taking
     turns; every file call made with the 48K ROM paged, Layer 2 writes off and
     interrupts off, and MMU slot 3 put back afterwards
  6. a missing picture: a red border, the screen as it was, the file closed

and writes the screen it saw to seen_on_next.png.

Usage: python3 run_nex.py [BUILD-FOLDER]   (default: build; reads sd/DOTC/DOTC.NEX,
       sd/DOTC/DOTC_GFX/*.PIC, title.map, preview/*.png, bg.bin, ay_period.bin and
       ay_volume.bin there)
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
    def __init__(self, nex, labels, sd):
        self.L = labels
        self.sd = Path(sd)
        self.files = {}                 # esxDOS handles: [data, position]
        self.next_handle = 1
        self.calls = 0
        self.missing = set()            # names to treat as missing
        self.port_7ffd, self.port_1ffd = 0x00, 0x00
        self.l2_port = 0
        self.border = 0
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
        self.reg = {0x05: 0x00, 0x08: 0x00, 0x09: 0x00, 0x11: 0x00, 0x12: 9, 0x14: 0xE3, 0x43: 0x00,
                    0x53: 11, 0x70: 0x00}
        self.sel = 0
        self.line = 0
        self.l2_on = False
        self.clip, self.clip_i = [0, 255, 0, 191], 0
        self.pals = {1: [0] * 256, 5: [0] * 256}    # Layer 2's first and second palettes, 9-bit
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
            assert (v >> 4) & 7 in (1, 5), "palette writes should go to one of Layer 2's palettes"
        elif r == 0x44:
            if self.pal_half is None:
                self.pal_half = v
            else:
                self.pals[(self.reg[0x43] >> 4) & 7][self.pal_i & 255] = (self.pal_half << 1) | (v & 1)
                self.pal_i += 1
                self.pal_half = None
        elif r == 0x69:
            self.l2_on = bool(v & 0x80)
        elif r == 0xC9 and v & 1:
            self.c9_acks += 1

    def port_in(self, port):
        if port == 0x253B:
            if self.sel == 0x1F:          # the raster line moves on with each read
                self.line = (self.line + 1) % 312
                return self.line & 0xFF
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
            if not hi & 0x20:           # DFFEh: P on bit 0, O on bit 1
                if "P" in self.keys:
                    v &= ~1
                if "O" in self.keys:
                    v &= ~2
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
        elif port == 0x7FFD:
            self.port_7ffd = v
        elif port == 0x1FFD:
            self.port_1ffd = v
        elif port & 0xFF == 0xFE:
            self.border = v & 7
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

    def esxdos(self):
        """RST 08h: the code byte after it says which call"""
        m = self.m
        ret = m.memory[m.sp] | m.memory[(m.sp + 1) & 0xFFFF] << 8
        m.sp = (m.sp + 2) & 0xFFFF
        code = m.memory[ret]
        m.pc = (ret + 1) & 0xFFFF
        assert self.port_7ffd & 0x10 and self.port_1ffd & 0x04, "esxDOS needs the 48K BASIC ROM paged in"
        assert not self.l2_port & 1, "Layer 2 writes must be off during esxDOS calls"
        assert not m.iff1, "interrupts should be off during file calls"
        self.calls += 1
        fail = True
        if code == 0x9A:                # F_OPEN: A drive, IX name, B mode
            name = bytearray()
            a = m.ix
            while m.memory[a]:
                name.append(m.memory[a])
                a += 1
            name = name.decode()
            assert m.a == ord("*") and m.b == 0x01, "open for reading on the current drive"
            path = self.sd / name
            if name not in self.missing and path.is_file():
                h = self.next_handle
                self.next_handle += 1
                self.files[h] = [path.read_bytes(), 0]
                m.a = h
                fail = False
            else:
                m.a = 5                 # not found
        elif code == 0x9D:              # F_READ: A handle, IX address, BC count
            f = self.files[m.a]
            n = min(m.bc, len(f[0]) - f[1])
            data = f[0][f[1]:f[1] + n]
            f[1] += n
            for i, byte in enumerate(data):
                a = (m.ix + i) & 0xFFFF
                if 0x6000 <= a < 0x8000:        # MMU slot 3
                    page = self.reg[0x53]
                    self.banks[page // 2][(page & 1) * 8192 + a - 0x6000] = byte
                else:
                    assert a >= 0x4000, "a read into the ROM"
                    m.memory[a] = byte
            m.bc = n
            fail = False
        elif code == 0x9B:              # F_CLOSE
            del self.files[m.a]
            fail = False
        else:
            raise AssertionError(f"esxDOS call {code:02X}h not modelled")
        m.f = (m.f | 1) if fail else (m.f & ~1)

    def step(self):
        """one instruction, the Next's NEXTREG and esxDOS's RST 08h included"""
        m = self.m
        pc = m.pc
        if pc == 0x0008:
            self.esxdos()
            return
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
        assert 0x8000 <= m.pc < self.L["code_end"] or m.pc in (SENTINEL, 0x0008), f"PC left the program: {m.pc:04X}"

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
        pal = self.pals[5 if self.reg[0x43] & 0x04 else 1]
        rgb = bytearray()
        for y in range(256):
            for x in range(320):
                c = pal[data[x * 256 + y]]
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
    sd = build / "sd" / "DOTC"                     # the game's folder, the current one when it runs
    nex = sd / "DOTC.NEX"

    # 1. the set-up, up to the main loop
    nx = Next(nex, L, sd)
    nx.run_to(L["main_loop"])
    shot = nx.screen()
    assert shot == read_png_rgb(build / "preview" / "CB.png"), "the screen differs from the converter's preview"
    assert nx.reg[0x53] == 11 and not nx.files and nx.border == 0, "after loading the title"
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
    print("1. set-up: the title loaded from the SD card, the screen matches the preview; IM2, CTC 0 at 28 MHz / 256 / 64; the opening theme started")

    # 2. the driver, song by song, against the Python one
    for song in range(8):
        nx = Next(nex, L, sd)
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
    nx = Next(nex, L, sd)
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
    # 5. the pictures
    def press(nx, key):
        nx.keys = {key}
        start = nx.calls
        for _ in range(200_000):
            nx.step()
            if nx.calls > start and nx.m.pc == L["main_loop"]:
                break
        else:
            raise AssertionError(f"{key} loaded nothing")
        nx.keys = set()
        for _ in range(200):            # the key let go
            nx.step()

    seen_banks, seen_pals = set(), set()
    order = [(1 + k) % 20 for k in range(1, 21)] + [0, 19, 18]   # P through CC ... CA, CB; then O back
    for k, pic in enumerate(order):
        press(nx, "P" if k < 20 else "O")
        name = "C" + chr(ord("A") + pic)
        assert nx.m.memory[L["cur_pic"]] == pic, f"{name}: the picture number"
        assert nx.screen() == read_png_rgb(build / "preview" / f"{name}.png"), f"{name} differs from its preview"
        assert nx.reg[0x53] == 11 and not nx.files and nx.border == 0 and nx.m.iff1, f"{name}: after loading"
        seen_banks.add(nx.reg[0x12])
        seen_pals.add(nx.reg[0x43] & 0x04)
    assert seen_banks == {20, 25} and seen_pals == {0, 4}, "the buffers and palettes should take turns"
    print(f"5. pictures: P through all 20 and O back, each screen its preview pixel for pixel; "
          f"{nx.calls} file calls, all with the 48K ROM, Layer 2 writes off, interrupts off")

    # 6. a missing picture
    before = nx.screen()
    after = (nx.m.memory[L["cur_pic"]] + 1) % 20
    nx.missing = {f"DOTC_GFX/C{chr(ord('A') + after)}.PIC"}       # the one P will load next
    nx.keys = {"P"}
    for _ in range(200_000):
        nx.step()
        if nx.border == 2 and nx.m.pc == L["main_loop"]:
            break
    else:
        raise AssertionError("no red border for a missing picture")
    nx.keys = set()
    assert nx.screen() == before and nx.reg[0x53] == 11 and not nx.files and nx.m.iff1, "after a missing picture"
    print("6. a missing picture: red border, the screen as it was")
    print("all checks passed")


if __name__ == "__main__":
    main()
