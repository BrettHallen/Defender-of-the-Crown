# Defender of the Crown - Spectrum Next remake
A version of Defender of the Crown for the ZX Spectrum Next, built from the booter's **Tandy 1000** program (`AC` in GAME.DAT): its 16-colour pictures shown pixel for pixel on Layer 2 (320×256, 256 colours), and its three-voice music played by the original's own driver on the Next's AY chips.

**No original game files are included.** As with the [Mac remake](../Remake), everything is converted at build time from your own `GAME.DAT`, so the repository keeps no original artwork or music. The `build/` folder (which does hold the converted files) is not committed.

## Status: the title test
`build/dotc_title.nex` shows the Tandy title picture ("Defender of the Crown" on the stone wall) and plays the Tandy music:

| Key | Tune (the game's tune number) |
|---|---|
| **1** | 97h, the opening theme (starts by itself) |
| **2**-**8** | 98h-9Eh |
| **Space** | the current tune again from the top |

Checked on a real Next (the first version, with the opening theme pre-recorded): the picture, its colours and the sound. The Tandy's 16 colours come out in the Next's 9-bit palette, with a component of 85 or 170 becoming 73 or 182 of 255, the Next's nearest. The 320×200 picture sits in the middle of the 256 lines, so it looks a little flatter than on a DOS monitor, which stretched the 200 lines to the screen's height. The music plays on one AY in mono, as on the Tandy's single speaker.

## How it works
- **`tools/convert.py`** reads GAME.DAT as the Mac remake does (`Remake/src/dat.c`, `assets.c`). It writes:
  - the title picture `CB` as a Layer 2 screen and palette (`title.l2`, `title.pal`), with `title.png` as a preview;
  - the Tandy music data unchanged (`bg.bin`, BG);
  - two tables for turning the Tandy chip's settings into the AY's. `ay_period.bin` turns a tone register into an AY period: the Tandy's SN76496 runs at 3.58 MHz and the AY at 1.75 MHz, so the notes keep their pitch. `ay_volume.bin` turns an attenuation (2 dB steps) into the nearest AY volume.
- **`src/tandy.asm`** is the Tandy music driver (AC 7444-7C53) in Z80, ported from the Mac remake's C (`Remake/src/sound.c`). It covers the songs and their loop points, the four voices' notes, the instruments' attack, decay, sustain and release, and the vibrato. It reads the original music data directly, and whatever the Tandy would send its chip goes to the AY at once. The noise voice runs but isn't heard: the music doesn't use it, and the Mac remake doesn't play it either.
- **`src/title.asm`** sets up Layer 2, the AY and the timing, and reads the keys. The original's driver ran 1193182 / *tempo* times a second, 149 to 239 times depending on the song. Here the Next's **CTC** channel 0 interrupts about 1,700 times a second (28 MHz / 256 / 64), through the Next's hardware IM2 controller. Each interrupt adds its length, in PC-timer counts, to a counter. Each time the counter passes the song's tempo, the driver runs once. That gives the original's rate on average, within 0.6 ms. A single channel is used because CSpect doesn't chain CTC channels. The CTC's clock follows the video timing (NextReg 11h), so the program picks its step from a table for the eight timings.
- **`tools/make_nex.py`** packs the program, the music data and the picture into a `.nex` file, the Next's own program format. The program and music take 8000h-E72Dh (banks 2 and 0) and the picture banks 20-24.
- **`test/run_nex.py`** checks the `.nex` without a Next. It loads it as NextZXOS does and runs it on a Z80 emulator, with a model of the Next registers, Layer 2, the AY, the keys and the CTC interrupts. It checks four things:
  1. the screen matches `title.png` pixel for pixel, and the interrupts and the CTC are set up as above;
  2. for each of the eight songs, the Z80 driver and a Python copy of the Mac remake's run side by side for up to four minutes. After every one of the driver's interrupts, the AY must hold what the Tandy chip would. All eight songs match at every interrupt, loops included (about 220,000 interrupts in all);
  3. with CTC interrupts arriving into the running program, each one is acknowledged, and the driver runs 192.3 times a second for the opening theme (the original: 192.4);
  4. the keys start their tunes.

The Z80 code follows Tomaž Kragelj's [ZX Spectrum Next Assembly Developer Guide](https://github.com/tomaz/zx-next-dev-guide) for Layer 2, the palette and the AY (Turbosound), and Klive IDE's [book](https://kliveide.net/en/book/) for the CTC and the hardware IM2 controller.

## Building on macOS
You need Python 3 and Boriel's `zxbasm` assembler, which comes with ZX Basic:
```sh
python3 -m pip install --user zxbasic
```
(If `zxbasm` isn't found afterwards, add the folder pip printed to your `PATH`, or use `pipx install zxbasic`.)

Then:
```sh
cd Remake_Spectrum_Next
./build.sh                 # uses ../Original/ega/GAME.DAT
./build.sh /path/to/GAME.DAT
```
This writes `build/dotc_title.nex`. To run the checks (`python3 -m pip install --user z80` first):
```sh
python3 test/run_nex.py build
```

## Running
- **On the Next:** copy `dotc_title.nex` to the SD card (any folder) and open it from the NextZXOS Browser. It needs core 3.1.0 or later (any Next from the second Kickstarter has one).
- **On the Mac:** open it in a Next emulator such as [ZEsarUX](https://github.com/chernandezba/zesarux) or [#CSpect](http://www.cspect.org) (CSpect needs Mono on macOS).

## Next steps
- Load the pictures from the SD card as the game needs them, as the PC loaded them from disk.
- The opening: the credits, the title with its sparkles, the cast and Sherwood, from the Mac remake's port of the original's code.
