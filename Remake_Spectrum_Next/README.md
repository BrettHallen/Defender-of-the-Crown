# Defender of the Crown - Spectrum Next remake
A version of Defender of the Crown for the ZX Spectrum Next, built from the booter's **Tandy 1000** program (`AC` in GAME.DAT), in Z80 assembly. It follows the [Mac remake](../Remake)'s port of the original, routine by routine. The pictures are shown pixel for pixel on Layer 2 (320×256, 256 colours), and the three-voice music is played by the original's own driver on the Next's AY chips.

## Status: the opening
`DOTC.NEX` plays the start of a new game, as the original did in Tandy mode:
- the credits on the scroll, and the title with its sparkles;
- the credits again with the cast, and the introduction, all over the opening theme;
- the choice of character: the keypad keys (7 8 9 / 4 5 6 / 1 2 3 on the number row) or the cursor keys move the choice, and **Enter** chooses;
- Sherwood, with Robin's two speeches and the campfire flickering.

**S** skips the rest of the opening, and Sherwood (the Mac remake's own key). After Sherwood the game stops for now: the first month comes next.

Checked on a real Next so far: the pictures, their colours, and the music on the AY timed by the CTC. The opening itself has been checked in the emulator test below.

## How it works
- **`tools/convert.py`** reads GAME.DAT as the Mac remake does (`Remake/src/dat.c`, `assets.c`) and writes:
  - the 20 Tandy pictures for the SD card (`sd/DOTC/DOTC_GFX/CA.PIC`-`CT.PIC`): each in four 8K pages, as 160 pairs of columns at 4 bits a pixel, with its 16 palette registers. `preview/` holds a PNG of each as the Next will show it;
  - the data segment (`ds.bin`: BH, the game's texts, tables and variables);
  - the Tandy sprite files the opening uses (`spr_font.bin`, the font and box pieces; `spr_chars.bin`, the name boxes), decoded as `assets.c` does. A masked sprite keeps, for each column, only the span between its see-through ends;
  - the PC-speaker tunes' note lengths (`speaker.bin`): in every mode the game times itself by them, with the Tandy music laid over the top;
  - the Tandy music data (`bg.bin`), and the tables that turn the Tandy chip's tones and volumes into the AY's.
- **`src/main.asm`** is the program: the memory map, the start-up and the variables. It includes:
  - **`sys.asm`**: the CTC interrupt, which keeps the original's clocks (the BIOS's 18.2 ticks a second, the PC display's 60 retraces a second, and the music driver's own rate) and the speaker tune's timing. Also the keys, read as the PC's scan codes, the waits, the S skip, and loading pictures through esxDOS;
  - **`gfx.asm`**: two Layer 2 buffers standing for the original's screen and back page. The game draws on the back page, and `present` copies the columns that changed to the screen with the DMA. It also has the Tandy program's drawing: rectangles, sprites (copied, XORed or masked), letters, pixels, the palette, and pictures unpacked from the cache;
  - **`opening.asm`**: `new_game`'s opening (AB 10B2), the dialog boxes (7A80), the sparkles (179A), the choice of character and the campfire (18C9);
  - **`tandy.asm`**: the Tandy music driver (AC 7444-7C53), reading the music data through slot 1 from inside the interrupt.
- **Memory:**

  | Slot | Address | Holds |
  |---|---|---|
  | 0 | 0000h | the ROM; sprites and the picture cache are read here |
  | 1 | 2000h | the ROM; the music driver reads its data here |
  | 2-4 | 4000h | the data segment: `DSEG + offset` is the original's `DS:offset` |
  | 5-6 | A000h | the code; the interrupt vectors at DF00h, the stack below them |
  | 7 | E000h | the window onto Layer 2's pages, and the files' while loading |

  Pages 12-14 hold the data segment, 16-18 the music, 20-24 the sprites, 40-59 Layer 2's two buffers, and 60-83 the picture cache. The opening's six pictures are read from the card before it starts, so it never waits for the card while it plays.
- **`tools/make_nex.py`** packs the program and its data into `DOTC.NEX`.

The Z80 code follows Tomaž Kragelj's [ZX Spectrum Next Assembly Developer Guide](https://github.com/tomaz/zx-next-dev-guide) for Layer 2, the palette and the AY (Turbosound), Klive IDE's [book](https://kliveide.net/en/book/) for the CTC and the hardware IM2 controller, the Next wiki for the DMA, and the [NextZXOS and esxDOS APIs](https://gitlab.com/thesmog358/tbblue/-/blob/master/docs/nextzxos/NextZXOS_and_esxDOS_APIs.pdf) document for the file calls.

## The checks
**`test/run_nex.py`** runs `DOTC.NEX` without a Next. It loads the file as NextZXOS does and runs it on a Z80 emulator at its own speed, with a model of the Next around it: the MMU, the NEXTREG instructions, Layer 2 and its palette, the DMA, the AY, the keyboard, the CTC's interrupt every 16,384 T-states through the IM2 controller, and esxDOS's file calls. It checks:
1. **The music driver.** For each of the eight songs, the Z80 driver and a Python copy of the Mac remake's run side by side, for up to four minutes. After every one of the driver's interrupts, the AY must hold what the Tandy chip would.
2. **The opening, against the Mac remake itself.** `test/ref` builds the remake's own game and drawing code without SDL, on a virtual clock, and records every screen it shows in Tandy mode (see its README). The Next must show exactly the same screens, pixel for pixel and colour for colour, each first shown at about the same time. It is checked three ways: with no keys up to the choice of character, with S pressed during the credits, and with a character chosen, through Sherwood.

   The times can trail by up to half a second. The Next unpacks each picture from its cache in about 0.12 s, where the remake shows it at once, and the next wait for a tune's end evens them out again. The campfire may also run a cycle more or less than the remake's: how the BIOS ticks and the retraces fall together varies from run to run, on the PC as here.

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
This writes `build/sd/DOTC/`, the game's folder: `DOTC.NEX`, with the pictures in `DOTC_GFX/`.

To run the checks, install the emulator (`python3 -m pip install --user z80`), record the reference (`test/ref/README.md`), then:
```sh
python3 test/run_nex.py build
```

## Running
- **On the Next:** copy the `DOTC` folder (from `build/sd/`) to the SD card, open it in the NextZXOS Browser and run `DOTC.NEX`. It reads the pictures from `DOTC_GFX/`, beside it. It needs core 3.1.5 or later (any Next from the second Kickstarter has one). If a picture can't be read, the border turns red.
- **On the Mac:** open it in a Next emulator such as [ZEsarUX](https://github.com/chernandezba/zesarux) or [#CSpect](http://www.cspect.org) (CSpect needs Mono on macOS), with `build/sd` as its SD card folder.

## Next steps
- The setup of a new game and the first month: the map, the status panel and the orders menu (with the dialog's menus).
