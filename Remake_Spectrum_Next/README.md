# Defender of the Crown - Spectrum Next remake
A version of Defender of the Crown for the ZX Spectrum Next, built from the booter's **Tandy 1000** program (`AC` in GAME.DAT), in Z80 assembly. It follows the [Mac remake](../Remake)'s port of the original, routine by routine. The pictures are shown pixel for pixel on Layer 2 (320×256, 256 colours), and the three-voice music is played by the original's own driver on the Next's AY chips.

## Status: the opening, the months, the computer lords and the map's orders
`DOTC.NEX` plays the start of a new game, as the original did in Tandy mode:
- the credits on the scroll, and the title with its sparkles;
- the credits again with the cast, and the introduction, all over the opening theme. After the original's credits comes one of the Next's own: "ZX Spectrum Next remake using Claude Opus 5.5, Nov. 2026";
- the choice of character: the keypad keys (7 8 9 / 4 5 6 / 1 2 3 on the number row) or the cursor keys move the choice, and **Enter** chooses;
- Sherwood, with Robin's two speeches and the campfire flickering.

**S** skips the rest of the opening, and Sherwood (the Mac remake's own key).

**V** switches the picture between pixel-exact (at the start) and stretched. The PC showed its 320×200 picture on a 4:3 screen, with pixels taller than they were wide. On the Next's 320×256 they are about square, so the picture looks a little squashed. Stretched, the Next's copper shows the 200 lines on 240 of the 256, one line in five twice, which gives back the original's proportions. It changes only how the picture is shown, not how it is drawn, and costs the program nothing.

One change from the original: the introduction moves on to the choice of character when the opening theme ends. The original, like the Mac remake, waits for the PC-speaker version of the theme, which runs about 15 s longer than the Tandy music, so it sat silent all that time. Sherwood is as the original: each of Robin's speeches lasts as long as its tune (about 14 s), and the month begins after the second.

The colours are the Tandy's 16, in the Next's 9-bit palette. The Tandy's middle level is rounded down there, not up, so the six dark colours are a little darker than the PC's but stay clearly apart from the light ones. Rounded up, two Saxon lords' cyans looked almost the same on the map.

Then the game itself begins, month by month:
- the setup: the homes, the lords, the ladies, the garrisons, the armies and the enmities, from the original's own random numbers;
- the map, with each owner's territories in its colour and the castles;
- the status panel: your lord's skills, the campaign army, the income counting into the treasure (with the speaker's beeps), your portrait by morale, your lady if you have one, and the month;
- the events: the Vikings, the Danes, the Norman plotters, the Sheriff, the sabotage, Robin's raid, the German knights and the revolt;
- the computer lords' turns: each picks its order (buy, march on a target, a Norman's raid, go home), and their armies fight it out on the map;
- a battle where your castle or army is attacked: the tactics menu (Up, Down, Enter) and the men fighting, round by round;
- **Hold Tournament** (5 gold), and the computer lords' tournaments: the trumpeters' fanfare, then up to three rounds. Each round you choose the stakes, Fame (your leadership) or Land (a territory without a castle), and your opponent. The knights ride in, then the joust down the lane: after Enter, the keypad or cursor keys steer your lance's point (7 8 9 up, 1 2 3 down, 4 and 6 sideways) at the oncoming knight's shield, and the outcome plays out over the stands. A near miss runs again; striking the horse means disgrace. **S** skips the fanfare and the knights riding in;
- **Your Orders?**: the keypad or cursor keys move the bar, **Enter** chooses, **Left** and **Right** change the amounts in Buy Home Army and Transfer Forces. Held, a key repeats, as on the PC:
  - **Seek Conquest**: send your campaign army into a neighbouring territory (with Robin's men, if you asked him), Transfer Forces, Read Map, See Robin; safe passage through a friendly Saxon's land, and battles;
  - **a siege**: marching on a lord's castle with a catapult brings up the bombardment. Choose the ammunition (Up, Down, Enter), then pull the catapult back (Up and Down set how far, Enter lets go) and watch the shot fly. Each day's hits wear down the castle's walls, and after the last day your army storms it, against what is left of its protection. Without a catapult, the castle can't be besieged;
  - **Buy Home Army**: soldiers, knights, catapults and castles;
  - **Read Map**: a territory's income, vassals and owner;
  - **Pass** ends your month. **Options** sets the music on or off, starts a new game, or ends this one, which resets the Next back to its menu.

Not yet:
- **Go Raiding** does nothing yet and brings the menu back, and a kidnapped lady is never offered for rescue.
- The game's end: winning or losing.

Checked on a real Next so far: the opening, including its pictures, colours, music and keys. The rest has been checked in the emulator test below.

A note of the music sometimes holds on a little too long: the Mac remake's Tandy music does the same, so it is the original's.

## How it works
- **`tools/convert.py`** reads GAME.DAT as the Mac remake does (`Remake/src/dat.c`, `assets.c`) and writes:
  - the 20 Tandy pictures for the SD card (`sd/DOTC/DOTC_GFX/CA.PIC`-`CT.PIC`): each in four 8K pages, as 160 pairs of columns at 4 bits a pixel, with its 16 palette registers. `preview/` holds a PNG of each as the Next will show it;
  - the data segment (`ds.bin`: BH, the game's texts, tables and variables);
  - the Tandy sprite files (`spr_font.bin`, the font and box pieces; `spr_chars.bin`, the name boxes; `spr_portraits.bin`, the map's territory shapes, the castles, the army and the portraits), decoded as `assets.c` does. A masked sprite keeps, for each column, only the span between its see-through ends;
  - the PC-speaker tunes' note lengths (`speaker.bin`): in every mode the game times itself by them, with the Tandy music laid over the top;
  - the Tandy music data (`bg.bin`), and the tables that turn the Tandy chip's tones and volumes into the AY's.
- **`src/main.asm`** is the program: the memory map, the start-up and the variables. It includes:
  - **`sys.asm`**: the CTC interrupt, which keeps the original's clocks (the BIOS's 18.2 ticks a second, the PC display's 60 retraces a second, and the music driver's own rate) and the speaker tune's timing. Also the keys, read as the PC's scan codes, the waits, the S skip, and loading pictures through esxDOS;
  - **`gfx.asm`**: two Layer 2 buffers standing for the original's screen and back page. The game draws on the back page, and `present` copies the columns that changed to the screen with the DMA. It also has the Tandy program's drawing: rectangles, sprites (copied, XORed or masked), letters, pixels, the palette, and pictures unpacked from the cache;
  - **`opening.asm`**: `new_game`'s opening (AB 10B2), the dialog boxes and their menus (7A80), the sparkles (179A), the choice of character and the campfire (18C9);
  - **`game.asm`**: the game's logic, as the Mac remake's `game.c` and `month.c`: the random numbers (seeded from the Next's real-time clock, if it has one), the month (1B44), the map (4013), the status panel (90A3), the events (2F4E), the orders (1A91) and the options (1957);
  - **`defs.asm`**: the constants the program and its overlays share.
- **The overlays** (`src/ov_*.asm`) hold the rest of the game's logic, as the 16K of code at A000h-DFFFh can't. Each is an 8K page, assembled at 2000h after the program (they call it by the labels in its map: `tools/syms.py`). A stub in the program pages one into slot 1 while it runs, and puts back what was there after (`ovl_go`):
  - **`ov_setup.asm`**: the setup of a new game (AB 21CC-2556);
  - **`ov_war.asm`**: the computer lords (`ai.c`), the armies, attacks, battles and the computer lords' sieges (`war.c`);
  - **`ov_conq.asm`**: choosing a territory, Buy Home Army, Read Map and Seek Conquest (`month.c`, `conquest.c`);
  - **`ov_siege.asm`**: the siege's bombardment: the ammunition, the catapult and the shot's flight (`war.c`);
  - **`ov_tourn.asm`**: the tournament, its rounds, the knights riding in, the joust and its outcome (`tourney.c`).
- **The scenes' sprites** (`DOTC_GFX/SIEGE.SPR`, `TOURN.SPR`, `LANE.SPR`) are read from the card when a scene first needs them (`load_sprites`), into the pages the opening's pictures leave free once the game begins.
- **The picture's proportions** (`gfx.asm` `stretch_on`): a copper program, written at the start for the frame's line count (HDMI, VGA, 50 or 60 Hz), sets Layer 2's vertical scroll back by a line every 6 display lines, in the blanking at each line's end, so the picture's 200 lines fill 240.
- **The sprite slots** (`gfx.asm`): the game's 12 moving sprites, drawn masked over what they cover each frame and taken off again after it, as the Mac remake's `gfx_sprites_draw` and `gfx_sprites_erase`. What they cover is kept in pages 37-39.
  - **`tandy.asm`**: the Tandy music driver (AC 7444-7C53), reading the music data through slot 1 from inside the interrupt.
- **Memory:**

  | Slot | Address | Holds |
  |---|---|---|
  | 0 | 0000h | the ROM; sprites and the picture cache are read here |
  | 1 | 2000h | the ROM; the music driver reads its data here |
  | 2-4 | 4000h | the data segment: `DSEG + offset` is the original's `DS:offset` |
  | 5-6 | A000h | the code; the interrupt vectors at DF00h, the stack below them |
  | 7 | E000h | the window onto Layer 2's pages, and the files' while loading |

  Pages 2-4, 19 and 23 hold the overlays, 6-9 the sword fight's and battle's sprites, 12-14 the data segment, 16-18 the music, 20-36 the other sprites, 37-39 what the sprite slots cover, 40-59 Layer 2's two buffers, 60-83 the opening's six pictures (then the scenes' sprites), 84-91 the map, and 92-95 any other picture, one at a time. All of it fits in the Next's 1MB. The opening's pictures are read from the card before it starts, so it never waits for the card while it plays. The map is unpacked once, at the start, to a byte a pixel, so the DMA can put it back on the screen in about 10 ms each time the game redraws it.
- **`tools/make_nex.py`** packs the program and its data into `DOTC.NEX`.

The Z80 code follows Tomaž Kragelj's [ZX Spectrum Next Assembly Developer Guide](https://github.com/tomaz/zx-next-dev-guide) for Layer 2, the palette and the AY (Turbosound), Klive IDE's [book](https://kliveide.net/en/book/) for the CTC and the hardware IM2 controller, the Next wiki for the DMA, and the [NextZXOS and esxDOS APIs](https://gitlab.com/thesmog358/tbblue/-/blob/master/docs/nextzxos/NextZXOS_and_esxDOS_APIs.pdf) document for the file calls.

## The checks
**`test/run_nex.py`** runs `DOTC.NEX` without a Next. It loads the file as NextZXOS does and runs it on a Z80 emulator at its own speed, with a model of the Next around it: the MMU, the NEXTREG instructions, Layer 2 and its palette, the DMA, the AY, the keyboard, the CTC's interrupt every 16,384 T-states through the IM2 controller, and esxDOS's file calls. It checks:
1. **The music driver.** For each of the eight songs, the Z80 driver and a Python copy of the Mac remake's run side by side, for up to four minutes. After every one of the driver's interrupts, the AY must hold what the Tandy chip would.
2. **The opening, against the Mac remake itself.** `test/ref` builds the remake's own game and drawing code without SDL, on a virtual clock, and records every screen it shows in Tandy mode (see its README). The Next must show exactly the same screens, pixel for pixel and colour for colour, each first shown at about the same time. It is checked three ways: with no keys up to the choice of character, with S pressed during the credits, and with a character chosen, through Sherwood. The choice of character is the one screen that comes at another time: when the Tandy music ends, about 15 s before the reference's, which the check also checks.

   The times can trail by up to about 0.6 s. The remake draws at once, but the Next takes time: about 70 ms to unpack a picture from its cache, and about 0.2 ms for each letter and 0.4 ms for each piece of a box's edge (a box of 13 lines takes about 0.13 s). Each wait after a drawing is counted from its end, so the delays add up until the next wait for a tune's end or for a key evens them out. The campfire may also run a cycle more or less than the remake's: how the BIOS ticks and the retraces fall together varies from run to run, on the PC as here.
3. **The setup and the first month.** With a character chosen, the status panel, the orders menu and Pass: the same screens again, up to where the remake's computer lords take their turns. Then the data segment at the orders menu (the sides, the territories, the armies, the ladies, the enmities, the random numbers and the status panel's lines) must hold what the remake's does, byte for byte.
4. **Nine months of the computer lords' turns**, with Enter pressed at each menu (Pass) a second after it comes up, in both: the same screens, including a battle where a Norman attacks the player's army, and the same data segment at the end, the lords' searches and orders too. Each screen is timed from the last Enter before it, as the Next's drawing falls behind the remake's from month to month (up to 2 s by a month's end).
5. **The map's orders**: Buy Home Army (buying, a refusal, selling back), and Read Map, Transfer Forces and a march into Lincolnshire, each with its keys and the same screens and data segment as the remake.
6. **A siege**: an army with a catapult sent into Norfolk, the six days' bombardment (each ammunition and pull chosen with keys), the battle at the walls, then the next month up to its orders: the same screens and data segment. A battle's rounds run at about the original's pace (the whole battle about 2% longer than the remake's); the screens are timed from the bombardment's last key.
7. **A tournament**: Hold Tournament at the first orders, the fanfare, a joust for fame, a near miss and a second pass, then the next month up to its orders: the same screens and data segment. The knights ride in when the tournament's tune ends: on the Next when its Tandy music does, about 4.6 s before the remake's speaker timing, so the screens from there on are timed in their own part. The Next draws the outcome over the stands at about 34 frames a second against the remake's 60, so that part trails by up to 3 s.

The reference's recordings for these are made as `test/ref/README.md` shows.

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
- Go Raiding with the sword fights and the ladies, and the game's end. Their sprites and pictures will be read from the card for each scene, into the pages the opening's pictures leave free once the game begins.
