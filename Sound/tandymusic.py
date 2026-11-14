#!/usr/bin/env python3
"""Play the Tandy 1000 music of the booter version (GAME.DAT file BG) into WAV files.

A port of AC's music driver (AC.ASM 7444-7C53; ints at 75A4), interrupt by interrupt,
with a simple SN76489 (the Tandy's sound chip) at 44.1 kHz.

Usage: tandymusic.py GAME.DAT OUTDIR [SECONDS]   (writes song0.wav ... song7.wav)

BG (unpacked to 4B80:0000) starts with a table of song offsets (song n at word n).
A song: [FFFEh = loops] tempo v0 v1 v2 v3. tempo is the PIT divisor for IRQ 0
(1193182 / tempo interrupts a second; the BIOS clock is still called at 18.2 Hz).
v0-v2 are the three tone channels, v3 the noise channel; a voice whose first word is
0 is silent. A voice is 6 words of instrument, then events:
  instrument: attack, decay, sustain, release step, release interval, vibrato delay
              (FFFFh = no vibrato). Volumes are SN76489 attenuations (0 loud, 15 off).
  event: duration (sequencer ticks, one every 4 interrupts), then a note: the chip's
         10-bit tone divisor (frequency 3579545 / 32 / n), or 0 = release.
         A note word FFFAh turns vibrato off and the next word is skipped (the
         driver then sends FFFAh to the chip as the note: kept here).
  FFFFh ends the voice: followed by FFFEh, voices 0 and 1 restart the song from its
  FFFEh marker, anything else stops the music; voices 2 and 3 test the other way
  round (FFFEh stops, anything else restarts from the last loop point).
Envelope, on the 3 interrupts of 4 that are not sequencer ticks: attack (volume -=
attack to 0), decay (+= decay to the sustain level), sustain, release (+= release
step every release-interval interrupts to 15). Vibrato: after the delay, every 3rd
sequencer tick the divisor goes +1, +1, -1, -1."""
import sys, os, struct, math, wave

PIT = 1193182
CHIP = 3579545
RATE = 44100

class Driver:
    def __init__(self, bg):
        self.bg = bg
        self.regs = [0, 0, 0, 0, 15, 15, 15, 15]   # tone0-2, noise ctrl, att0-3
        self.latch = 0
        self.playing = False
        self.loop_at = None
        self.tempo = 0
        self.writes = []

    def w(self, o): return struct.unpack('<H', self.bg[o:o + 2])[0]

    def out(self, b):                      # port C0h
        b &= 0xFF
        if b & 0x80:
            self.latch = (b >> 4) & 7
            ch, typ = self.latch >> 1, self.latch & 1
            if typ: self.regs[4 + ch] = b & 15
            elif ch == 3: self.regs[3] = b & 7
            else: self.regs[ch] = (self.regs[ch] & 0x3F0) | (b & 15)
        else:
            ch, typ = self.latch >> 1, self.latch & 1
            if typ: self.regs[4 + ch] = b & 15
            elif ch == 3: self.regs[3] = b & 7
            else: self.regs[ch] = (self.regs[ch] & 15) | ((b & 0x3F) << 4)

    def silence(self):                      # 7C78
        for b in (0x9F, 0xBF, 0xDF, 0xFF): self.out(b)
        self.state = [5, 5, 5, 5]
        self.active = [0, 0, 0, 0]

    def stop(self):                         # 7C53
        self.silence()
        self.playing = False

    def start(self, song):                  # 7444
        self.song_at(self.w(2 * song))

    def song_at(self, bx):                  # 747A
        self.stop()
        if self.w(bx) == 0xFFFF: return
        if self.w(bx) == 0xFFFE:
            self.loop_at = bx; bx += 2
        self.tempo = self.w(bx)             # 74BA
        self.inst = [None] * 4; self.ptr = [0] * 4
        for v in range(4):
            p = self.w(bx + 2 + 2 * v)
            if self.w(p) == 0:
                self.active[v] = 0
            else:
                self.inst[v] = [self.w(p + 2 * k) for k in range(6)]
                self.active[v] = 1; p += 12
            self.ptr[v] = p
        self.vol = [15, 15, 15, 15]
        self.subtick = 1
        self.playing = True
        self.dur = [1, 1, 1, 1]
        self.rel = [0, 0, 0, 0]
        self.tone = [0, 0, 0, 0]; self.vib = [0, 0, 0, 0]; self.vsub = [0, 0, 0, 0]; self.vph = [0, 0, 0, 0]

    def send_tone(self, v, n):              # 7820
        n &= 0xFFFF
        self.out((n & 15) | (0x80 + 0x20 * v)); self.out((n >> 4) & 0xFF)

    def next_event(self, v):                # 7678 / 76E2 / 774C / 77B6
        bx = self.ptr[v]
        d = self.w(bx); self.dur[v] = d
        if d == 0xFFFF:
            nxt = self.w(bx + 2)
            restart = (nxt == 0xFFFE) if v < 2 else (nxt != 0xFFFE)
            if restart and self.loop_at is not None: self.song_at(self.loop_at); return 'restart'
            self.stop(); return 'stop'
        bx += 2
        n = self.w(bx)
        if n == 0xFFFA:
            self.inst[v][5] = 0xFFFF; bx += 2
        if n == 0:
            self.state[v] = 4
        else:
            self.tone[v] = n; self.send_tone(v, n)
            self.state[v] = 1
            self.vib[v] = self.inst[v][5]; self.vph[v] = 0
        self.ptr[v] = bx + 2

    def vibrato(self, v):                   # 7A83
        self.vib[v] = (self.vib[v] - 1) & 0xFFFF
        if self.vib[v] != 0 and self.vib[v] < 0x8000: return
        self.vib[v] = (self.vib[v] + 1) & 0xFFFF
        if self.vsub[v] != 2: self.vsub[v] += 1; return
        self.vsub[v] = 0
        self.vph[v] += 1
        if self.vph[v] < 3: self.tone[v] += 1
        else:
            if self.vph[v] == 4: self.vph[v] = 0
            self.tone[v] -= 1
        self.send_tone(v, self.tone[v])

    def interrupt(self):                    # 75A4 -> [4BE9] = 75F4
        if not self.playing: return
        self.subtick -= 1
        if self.subtick == 0:
            self.subtick = 4
            for v in range(4):
                if not self.playing: break
                if self.active[v]:
                    self.dur[v] = (self.dur[v] - 1) & 0xFFFF
                    if self.dur[v] == 0:
                        r = self.next_event(v)
                        if r == 'restart': return
                    elif self.inst[v][5] != 0xFFFF:
                        self.vibrato(v)
            return
        for v in range(4):                  # 7870: envelopes
            s = self.state[v]
            if s in (3, 5): continue
            a, dcy, sus, rstep, rint, _ = self.inst[v] if self.inst[v] else (0,) * 6
            ax = self.vol[v]
            if s == 1:
                ax = clamp(ax - a); self.vol[v] = ax
                if ax == 0: self.state[v] = 2
            elif s == 2:
                ax += dcy; self.vol[v] = ax; ax = clamp(ax)
                if ax >= sus: ax = sus; self.vol[v] = sus; self.state[v] = 3
            else:
                self.rel[v] -= 1
                if self.rel[v] > 0: continue
                self.rel[v] = rint
                ax += rstep; self.vol[v] = ax; ax = clamp(ax)
                if ax >= 15: self.state[v] = 5; ax = 15
            self.out((ax & 15) | (0x90 + 0x20 * v))

def clamp(x):                               # 7A6F
    x = max(0, min(15, x if x < 0x8000 else x - 0x10000))
    return x & 15

def render(bg, song, seconds):
    drv = Driver(bg); drv.silence(); drv.start(song)
    if not drv.playing: return None
    samples = bytearray()
    amp = [int(8000 * 10 ** (-2 * i / 20)) if i < 15 else 0 for i in range(16)]
    phase = [0.0] * 3; lfsr = 0x4000; nph = 0.0
    t_int = 0.0
    period = drv.tempo / PIT
    total = int(seconds * RATE)
    for i in range(total):
        t = i / RATE
        while t_int <= t:
            drv.interrupt(); t_int += period
            if drv.tempo: period = drv.tempo / PIT
        if not drv.playing and i > RATE // 4 and all(drv.regs[4 + k] == 15 for k in range(4)):
            break
        s = 0
        for c in range(3):
            n = drv.regs[c] or 1024
            f = CHIP / 32 / n
            phase[c] = (phase[c] + f / RATE) % 1.0
            if f < RATE / 2: s += amp[drv.regs[4 + c]] if phase[c] < 0.5 else -amp[drv.regs[4 + c]]
        if drv.regs[7] < 15:
            nc = drv.regs[3]; nf = CHIP / 32 / [16, 32, 64, drv.regs[2] or 1024][nc & 3]
            nph += nf / RATE
            while nph >= 1:
                nph -= 1
                fb = ((lfsr ^ (lfsr >> 1)) & 1) if nc & 4 else (lfsr & 1)
                lfsr = (lfsr >> 1) | (fb << 14)
            s += amp[drv.regs[7]] if lfsr & 1 else -amp[drv.regs[7]]
        samples += struct.pack('<h', max(-32767, min(32767, s)))
    return bytes(samples)

if __name__ == '__main__':
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'Graphics'))
    import gamedat
    dat = open(sys.argv[1], 'rb').read()
    bg = gamedat.lzw(gamedat.raw(dat, gamedat.directory(dat)['BG']))
    out = sys.argv[2]; os.makedirs(out, exist_ok=True)
    secs = float(sys.argv[3]) if len(sys.argv) > 3 else 90
    for song in range(8):
        pcm = render(bg, song, secs)
        if not pcm: continue
        with wave.open(os.path.join(out, 'song%d.wav' % song), 'wb') as wv:
            wv.setnchannels(1); wv.setsampwidth(2); wv.setframerate(RATE); wv.writeframes(pcm)
        print('song %d: %.1f s' % (song, len(pcm) / 2 / RATE))
