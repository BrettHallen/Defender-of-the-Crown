#!/usr/bin/env python3
"""Play the PC-speaker music of Defender of the Crown into WAV files.

All three PC releases share one player and the same eight tunes:
  - DOC.EXE (1987 DOS version): DOCCHARS.LIB items 150-157, player in DOC.EXE's int 1Ch
    handler (load-image offset 9317h)
  - the booter's CGA and EGA builds: items 97h-9Eh of BA (CGA) and BB (EGA), loaded at
    1000:0000; player AA 84AF-8655 / AB 9559-96FF (int 1Ch handler at AB 968A)
  - the Tandy build keeps four of them in BC (99h, 9Ah, 9Dh, 9Eh) but plays its own
    three-voice music instead (tandymusic.py)

A tune: word flags, word note count n, word index, word ticks left (the player's state,
0 in the files), then n notes of (word PIT divisor, word duration). Each note sets PIT
channel 2 to the divisor (a square wave of 1193182 / divisor Hz on the speaker) for
`duration` ticks of int 1Ch (18.2 a second; 0 lasts one tick, like 1). Divisor 36
(33 kHz, inaudible) is used for rests. The speaker stays on from note to note.
play(tune, flags) (AB 9559): flags 8000h = play, 4000h = loop, 2000h = silent but timed
(the sound option off: [33] = 0 gives 8000h/C000h -> A000h/E000h), 0 = stop. The game
passes [35] (once), [37] (loop) or [39] (always 0: stop the tune).

Usage: speakermusic.py FILE OUTDIR [SECONDS]
  FILE is GAME.DAT (reads BB), or DOCCHARS.LIB. Writes tune97.wav ... tune9E.wav."""
import sys, os, struct, wave

PIT = 1193182
TICK = 65536 / PIT          # int 1Ch period, 54.9 ms
RATE = 44100

def w(d, o): return struct.unpack('<H', d[o:o + 2])[0]

def parse(d, o=0):
    n = w(d, o + 2)
    return [(w(d, o + 4 + 4 * k), w(d, o + 6 + 4 * k)) for k in range(1, n + 1)]

def tunes_from(path):
    base = os.path.basename(path).upper()
    if base.startswith('DOCCHARS'):
        sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'Graphics'))
        import doclib
        items = doclib.read_lib(path)
        return {0x97 + j: parse(items[150 + j]) for j in range(8)}
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'Graphics'))
    import gamedat
    dat = open(path, 'rb').read()
    bb = gamedat.lzw(gamedat.raw(dat, gamedat.directory(dat)['BB']))
    return {i: parse(bb, w(bb, 2 * i)) for i in range(0x97, 0x9F)}

def schedule(notes, loop=False, seconds=None):
    """The player tick by tick (AB 968A): returns [(start_tick, ticks, divisor)].
    The first note starts on the first tick after play()."""
    out = []; t = 1; idx = 0
    while True:
        if idx == len(notes):
            if not loop: break
            idx = 0
        div, dur = notes[idx]; idx += 1
        ticks = max(dur, 1)
        out.append((t, ticks, div)); t += ticks
        if seconds and t * TICK > seconds: break
    return out

def render(notes, loop=False, seconds=None, volume=6000):
    sch = schedule(notes, loop, seconds)
    end = (sch[-1][0] + sch[-1][1]) * TICK if sch else 0
    n = int((end + 0.1) * RATE)
    if seconds: n = min(n, int(seconds * RATE))
    pcm = bytearray(2 * n)
    phase = 0.0
    k = 0
    for i in range(n):
        t = i / RATE / TICK
        while k < len(sch) and t >= sch[k][0] + sch[k][1]: k += 1
        v = 0
        if k < len(sch) and t >= sch[k][0]:
            f = PIT / (sch[k][2] or 65536)
            if f < 20000:
                phase = (phase + f / RATE) % 1.0
                v = volume if phase < 0.5 else -volume
        struct.pack_into('<h', pcm, 2 * i, v)
    return bytes(pcm)

LOOPING = {0x9B, 0x9C}      # started with [37] (loop) somewhere in the game

if __name__ == '__main__':
    tunes = tunes_from(sys.argv[1])
    out = sys.argv[2]; os.makedirs(out, exist_ok=True)
    secs = float(sys.argv[3]) if len(sys.argv) > 3 else 90
    for i, notes in tunes.items():
        pcm = render(notes, i in LOOPING, secs)
        with wave.open(os.path.join(out, 'tune%02X.wav' % i), 'wb') as wv:
            wv.setnchannels(1); wv.setsampwidth(2); wv.setframerate(RATE); wv.writeframes(pcm)
        print('tune %02X: %d notes, %.1f s' % (i, len(notes), len(pcm) / 2 / RATE))
