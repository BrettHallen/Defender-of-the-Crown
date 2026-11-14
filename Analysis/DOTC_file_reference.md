# Defender of the Crown (PC): file reference

Source: `Original/` in the repo (all files dated 24 Dec 1996, from the archive `Defender_of_the_Crown_1987.zip`). First analysed 14 Nov 2026. The findings and the method are in `README.md`; the graphics are extracted by `../Graphics/extract_graphics.py`.

**The folder holds two different PC versions of the game**, not one game with two graphics modes:

| Folder | Version | Graphics | Runs from |
|---|---|---|---|
| `cga/` | The 1987 DOS release (DOC.EXE, "Master Designer Software, Inc. presents"; IBM PC soundtrack by Dave Farquharson) | CGA only | DOS |
| `ega/` | A later self-booting release on two 360K disks (Interactive Designs' ZeroBoot 2.2 and GameSYS 4.0, © 1985-1988; "Computography by David Todd / Fantasy Research, additional computography by Dave Farquharson") | CGA, EGA or Tandy 1000 16-colour, chosen at start (F1 = CGA) | Its own boot disk; `DEFENDER.COM` (by "Mok") runs it from DOS |

The two have the same story texts, pictures in the same scenes and the same characters, but the code, the file formats and the picture data are different. The booter's CGA pictures are not the DOS version's (between 1% and 72% of a picture's bytes differ).

## Top level
| File | Size | What it is |
|---|---|---|
| `run.bat` | 349 | The collector's menu: 1 runs `cga\DOC`, 2 runs `ega\DEFENDER`. Not part of the game. |
| `CHOICE.EXE` | 49,152 | DOS's CHOICE, used by `run.bat`. |
| `Defender of the Crown (1987).ba1` | 211 | A game collection's launcher (starts DOSBox). Not part of the game. |
| `Defender_of_the_Crown_1987.zip` | 893,538 | The archive these files came from (the same files). |

## cga/: the 1987 DOS version
| File | Size | What it is |
|---|---|---|
| DOC.EXE | 71,168 | The game. MZ, header 1800h bytes, 1,514 relocations, entry 0AA5:0011. A large-model C program: 76 code segments called far, one data segment DGROUP at segment 0BCE (4120h bytes initialised, BSS to 4728h). The C runtime has `/dev/con` and `Too many args.` (compiler not identified yet). Disassembly: `DOC.ASM`. |
| READTHIS.EXE | 52,310 | A text viewer added later (Borland C++, packed). Not part of the original game. |
| DOCCHARS.LIB | 40,102 | Shared graphics: 19 territory shapes for the map (items 0-18), map and UI pieces, two fonts (upper case 46-89, lower case 94-121), 22 portraits (127-148), the sword fight's swordsmen (159-180), the England map picture (item 93), and the 8 PC-speaker tunes (150-157: word flags, word note count, two words of player state, then (PIT divisor, duration in int 1Ch ticks) per note; see `README.md`). Loaded at start (021C:0143). |
| TITLE.LIB | 41,060 | The scrolls, the title, the cast, the introduction, the character choice and the Sherwood picture; sprites: the four characters' name plates and the crown. Loaded at start (021C:0165). |
| JOUST1.LIB | 16,474 | The tournament seen from above and 36 small jousting sprites; items 36-39 are tables (not decoded yet). |
| JOUST2.LIB | 49,074 | The jousting lane and the stands; the charging knight (2-19) and the lance view (20-40). |
| RAID.LIB | 43,776 | The castle raid: the castle at night, the hall, the plotters, the trumpeters, the land view; "You / Enemy" strength bars. |
| SIEGE.LIB | 29,100 | The two castle views for a siege; the catapult's stones, fire and bits of wall (50 sprites). |
| LOVE1.LIB | 33,670 | The Saxon lady's portraits and her eyes (blinking). |
| LOVE2.LIB | 33,232 | The bedchamber scene, its window, the couple, "THE END". |

### The .LIB format (DOC.EXE)
- A BASIC **BSAVE** image: byte FDh, word segment, word offset, word length, then *length* bytes, then 1Ah. DOC.EXE's loader (070A:015A) reads the 7-byte header and then the data into a buffer.
- The data begins with a word N and N word offsets, **in words** from the start of the data (0 = no item). Item *i* is fetched with offset[*i*] (070A:02B1 indexes the table with 1-based numbers: word 0 is N).
- An item is either:
  - a **picture**: `COMPRESS` (8 bytes), then a run-length code that unpacks to a full CGA screen (decompress 0946:0000): a byte c < 80h is c+1 literal pixels, 2 bits each, taken from literal bytes in the stream (high bits first; a part-used literal byte carries over to the next literal code); c >= 80h is a run of colour c & 3, (c >> 2) & 0Fh + 1 pixels long, or with bit 6 set ((c >> 2) & 0Fh) x 256 + the next byte + 1. The output is 200 lines of 80 bytes in screen order (the routine writes even lines to B800:0000 and odd ones to +2000h; the end address is patched into the code at 0946:00B5);
  - a **sprite**: word width in bits (2 bits a pixel), word height, then height rows of ceil(width / 8) bytes. Many come in pairs: the picture and its mask (1 bits = keep the background).
- **Colours:** CGA mode 4, palette 0 (green, red, brown) on black (070A:01B3 calls set_palette 0984:0130 with 0 and set_background 0984:0167 with [46DE]). [46DE] is 10h for one screen (050E:0626: the bright palette 0) and 0 otherwise. The title and the cast screens extracted this way are pixel-identical to DOSBox's.

## ega/: the booter version
| File | Size | What it is |
|---|---|---|
| DEFENDER.COM | 784 | "Dos driver by Mok": runs the booter from DOS (needs a 386: it uses 32-bit instructions). It opens GAME.DAT, reads disk 0 track 0 sectors 2-9 (GameSYS) to 8C00:0100, patches GameSYS's two int 13h reads to call its own handlers (which read or write GAME.DAT at disk x 5A000h + head x 1200h + track x 2400h + (sector-1) x 200h), and renumbers GameSYS's interrupts from 20h-2Fh to 80h-9Fh so that DOS keeps its own: in GameSYS before starting it, and in the game program after GameSYS has loaded it (it looks for `int 21h`, `int 22h`, `int 2Ch` and `int 2Eh` in 8000:0100-C100 and patches them). Each directory read flips the disk number, so when the game polls for a disk it soon finds the one it wants. |
| GAME.DAT | 737,280 | **Two 360K floppy images** one after the other (40 tracks, 2 sides, 9 sectors of 512 bytes). Read with `../Graphics/gamedat.py`; `gamedat.py GAME.DAT --disks DIR` writes them as disk1.img and disk2.img, which DOSBox can boot (the only way to run the Tandy build in DOSBox). |

### The disks
- Sector *n* of a disk (*n* = track x 18 + side x 9 + sector - 1) is at disk x 5A000h + *n* x 512. Disk 0 is used to track 36, disk 1 to track 36.
- **Track 0 sector 1**: ZeroBoot 2.2's boot sector. It loads sectors 2-9 to 0050:0100, checks for "Ga" at 0124h and jumps to it.
- **Track 0 sectors 2-9**: GameSYS 4.0 (`GAMESYS.ASM`). It sets up its services as interrupts (20h print a string, 21h load a file, 22h read the directory / which disk is in the drive, 2Ch the configuration, 2Dh a timer, 2Fh detect the video), detects the machine (Tandy, Tandon ROMs) and the video (int 2Fh: [34C] = 0 CGA, 1 EGA, 2 Tandy 1000 mode 9, 3 another CGA-like card), asks for F1 (CGA) or another key (16 colours), loads the program for the video (AA for 0 and 3, AB for 1, AC for 2) to 2000:0000, unpacks it to 0170:0100 and jumps to it.
- **Track 0 sector 9 of each disk**: its **directory**: 6-byte entries (2-character name, first sector *n*, sector count) ended by a 0 byte; the word at 1FCh is the disk's number (0 or 1).
- **Compression**: LZW, as Unix `compress` but simpler (GameSYS 065D; the game has its own copy, AB.ASM 9ABB): codes of 9 to 12 bits packed LSB first, 100h clears the table, 101h ends, the first free code is 102h, and the width grows when the next free code reaches 2^width. All files but the C pictures start with a clear code.

### The files (names by video: A program, B data and sprites, C 16-colour pictures, Q CGA pictures)
| Name | Disk | Sectors | Unpacked | What it is |
|---|---|---|---|---|
| AA | 0 | 56 | 41,979 | The game for **CGA** (and video type 3): code only, loaded at 0170:0100 |
| AB | 0 | 56 | 40,400 | The game for **EGA** (mode 0Dh, 320x200, 16 colours; planar, 40 bytes a line) |
| AC | 0 | 59 | 41,883 | The game for the **Tandy 1000** (mode 9, 320x200, 16 colours); the only build that uses the Tandy's sound chip (port C0h) |
| BH | 0 | 23 | 19,439 | Shared by all three: the game's data and texts (the cast, the territories, the credits, the story, the events) |
| BA BD BP BT BU BV BW Bc Bf Bg | 0 | | | CGA only (used by AA) |
| BB BE BJ BK BL BN BO Bd Bh Bi | 0, 1 | | | EGA only (used by AB) |
| BC BF BG BR BS BX BY Ba Bb Be Bj Bk Bl | 0, 1 | | | Tandy only (used by AC) |
| QA-QT | 0 | | 16,000 each (QF 16,384) | The 20 **CGA pictures**: 200 lines of 80 bytes, 2 bits a pixel, in screen order. Palette 0 on black (the title checked in DOSBox) |
| CA-CD, CE-CT | 0, 1 | | 32,000 each | The 20 **16-colour pictures** (EGA and Tandy): 16 palette bytes, then LZW (not starting at the file's first byte, so `gamedat.py` lists them as raw) that unpacks to 4 planes of 8000 bytes (plane 0 = blue). AB loads one with int 21h to 1000:7000, keeps the palette (9C31), unpacks from 1000:7010 to 3000:8000 (9ABB) and copies the planes to A000h (9993). In the 200-line EGA mode bit 4 of a palette register is the intensity, so a value *v* shows as colour (*v* & 7) \| (*v* >> 1 & 8); the palettes map the 16 pixel values to colours in a different order for each picture (and some pictures repeat colours). The Tandy build maps the same bytes the same way (*v* & 0Fh, plus 8 if *v* & 30h) and converts the planes to packed pixels. The title (CB) is pixel-identical to DOSBox's in both builds (but for the sparkle). |

The B files come in matching sets for the three programs (for example BT, BJ and BX have the same item table at their start; so do BU, BK and BY, and Bf, Bh and Bj): the same sprites drawn for each video mode. Decoded so far (checked against DOSBox screens or between the builds):
- **Big sprites** (Bf CGA, Bh EGA, Bj Tandy, 26 items, word offsets at the start): word height, word bytes per row, then the pixels: CGA 2 bits a pixel; EGA four planes one after another, in the order plane 3, 2, 1, 0 (8 pixels a byte); Tandy packed, 2 pixels a byte, the left one in the high nibble. Bh and Bj have the same offsets and all 24 sprites are identical in pixels.
- **Message-box and text pieces** (BB EGA, BC Tandy; BA is CGA's): a table of 0BFh words indexed by character code. 97h-9Eh are the eight PC-speaker tunes (the same as DOCCHARS.LIB 150-157; BC has only 99h, 9Ah, 9Dh and 9Eh). 20h-7Ah is the font (EGA: word width, word height, 1 bit a pixel; Tandy: word width, word bytes per row, word height, 4 bits a pixel), 14h-1Dh and 7Bh-7Eh the box's edges and corners (each a list of pre-shifted copies: 4 in BB, all the same, 2 in BC). An edge piece is: byte height, byte bytes per row, word plane size, then the mask (EGA one plane, 1 = transparent; Tandy 4 bits a pixel, Fh = transparent), then the pixels (EGA planes 3, 2, 1, 0; Tandy packed). The tops and bottoms cycle through pieces 14h-19h, the sides 1Ah-1Dh, the corners 7Bh-7Eh (AC 6B7E). In BC, 16h and 19h are copies of 14h and 17h; all the other pieces are identical to BB's.
- **The EGA build's sprite files** (sheets in `../Graphics/Booter_EGA/sprites/`, drawn in the palette of the picture they are shown over): a table of word pointers, the item number being the word's index (0 = no item), each item a big sprite (as above) or a slot sprite (4 word pointers to pre-shifted copies, all the same here; a copy is byte rows, byte bytes a row, word plane size, the mask with 1 = transparent, then planes 3, 2, 1, 0). **BE** the character-choice name boxes (8-11); **BJ** the tournament from above (2-35), the outcome scripts (37-40, see `tools/joust_scripts.py`) and the two knights crossing the stands (41-61); **BK** the opponent charging down the lane (3-19) and the player's lance (20); **BL** the territories' shapes (1-19: word height, word bytes a row, word colour, 1 bit a pixel), the castles (30, 35), the army (127) and the portraits (128-139: three for each of the four characters the player can be, by morale; 140 Robin, 141-145 the five Normans; 146-149 the ladies); **BN** the sword fight (160-179) and the battle's knights (180, 181); **BO** "THE END" (6), the strength bars (7 "You", 8 "Enemy") and the hit sparks (9, 10); **Bd** the siege (holes in the wall 3-7, the catapult 8-9 and its loaded and released arm 10-11, 24-25, 38-39, the three shots in flight 12-23, 26-37, 40-51, the flame 52); **Bh** the four ladies and their eyes (frames); **Bi** the romance silhouettes.
- **Message boxes** (in BH): 12 bytes each, passed by value to the box routine (AB dialog 7A80): x (4-pixel units), y, number of lines, width, icon (-2 text only, -3 a box without its frame, otherwise a framed box), 4 more bytes, then at +9 a word pointing at the table of the lines' string pointers. `AB.ASM`, `AA.ASM` and `AC.ASM` show each box's text where it is used.
- **Sprites inside AB**: the Sherwood and romance fire's two flames (AB 015C and 08B8, file offset - 100h): byte rows (47), byte bytes a row (8), word plane size (376), the mask (1 = transparent), then the four planes; the sprite slots point at them through two tables of 4 pre-shifted pointers (014C, 0154).
- **BG**: the Tandy build's music (unpacked to 4B80:0000). A table of 9 song offsets (8 songs are used, 0-7), then each song: an optional FFFEh (the song loops), the tempo (PIT divisor: 1193182 / tempo interrupts a second; 5000-8000), and four voice offsets (three tone channels and the noise channel; a voice whose first word is 0 is silent; no tune uses the noise channel). A voice: 6 words of instrument (attack, decay, sustain level, release step, release interval, vibrato delay or FFFFh; volumes are the chip's attenuations, 0 loudest, 15 off), then events of a duration (sequencer ticks, one every 4 interrupts) and a note (the chip's 10-bit tone divisor, 3579545 / 32 / n Hz; 0 = release; FFFAh = vibrato off, the next word skipped), ended by FFFFh and FFFEh (restart the song) or anything else (stop). Played by AC 7444-7C53 and by `../Sound/tandymusic.py`.

The 20 Q pictures and the 20 C pictures show the same 20 scenes in the same order (A blank scroll, B title, C the cast, D the introduction, E choose a character, F Sherwood, G trumpeters, H tournament from above, I jousting lane, J the stands, K the map of England, L land view, M plotters, N castle at night, O hall, P castle (siege), Q castle (second view), R the lady, S bedchamber, T window).
