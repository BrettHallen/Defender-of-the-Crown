# Defender of the Crown (PC): analysis

Analysis of the files in `Original/`, started 14 Nov 2026 with the method used for The Ancient Art of War (decode the formats, disassemble, name routines as they are understood, then port).

**State:** complete enough to have ported the whole game (`../Remake`). Every file is decoded (`DOTC_file_reference.md`); the booter's three game programs are disassembled with every routine named; the game's rules are written down from the EGA program, routine by routine, with every flaw found (`GAME_LOGIC.md`); the 1987 DOS version's DOC.EXE is disassembled with its game routines paired with the booter's and named, and every difference in its logic, timing, texts and graphics listed (`DOC_vs_AB.md`); the music of both kinds is ported (`../Sound`). What was checked against the originals running in DOSBox, and what was not, is at the end of this file.

| File | What it is |
|---|---|
| `DOTC_file_reference.md` | Every file: what it holds and how it is laid out |
| `GAME_LOGIC.md` | The game's rules as read from the booter's EGA program (AB): the data, the setup, the month, the events, buying, conquest, battles and sieges, the computer lords, raids and the sword fight, the ladies and the romance, tournaments and the joust, the opening, the random numbers; each of the original's flaws (the remake's `--fix=` names), and where the CGA and Tandy programs differ |
| `DOC.ASM` | Disassembly of DOC.EXE (the 1987 DOS CGA version), 19,900 lines: 232 routines in 76 segments, 95% of the code bytes reached. Every routine is named (`tools/doc_names.txt`): the 88 that port a booter routine (`DOC_vs_AB.md`), and DOC.EXE's own: its drawing primitives, the speaker, the key-disk check, and the C library it was linked with (Aztec C, large model: start-up, files and the console, memory, printf, long division, lines and circles the game never draws, and floating point done in software, with no 8087, for `ran()`); a `?` marks a name not checked by reading. Data references are named from `tools/doc_ds_names.txt`, the records' fields too (`; side.home`). The floating-point routines take their constants inline, in the 8 bytes after the call, which the listing shows as stray instructions |
| `GAMESYS.ASM` | The booter's loader, GameSYS 4.0 (GAME.DAT disk 0 track 0 sectors 2-9), with its services named |
| `AA.ASM`, `AB.ASM`, `AC.ASM` | Disassemblies of the booter's three game programs (CGA, EGA, Tandy), with the data file BH's strings and the message boxes' texts as comments. Every routine is named: AB's by reading them all (`disassembler/ab_names.txt`), AA's and AC's from their AB matches plus their own (`aa_names.txt`, `ac_names.txt`) |
| `AC_vs_AB.txt`, `AA_vs_AB.txt` | Every routine of AC (Tandy) and of AA (CGA) with its match in AB (EGA) and how alike they are |
| `disassembler/docdis.py` | Writes `DOC.ASM` (`python3 docdis.py DOC.EXE > DOC.ASM`, needs capstone). Follows far calls through the relocations, near calls and jumps, switch tables, far pointers to functions and the remaining `push bp / mov bp,sp` prologues. It takes its names from `../tools/doc_names.txt` and `doc_ds_names.txt` (and a `names.py` beside it, if there is one) |
| `disassembler/flatdis.py` | Disassembles a flat 16-bit binary from given entry points (`flatdis.py FILE BASE ENTRIES [names.txt] [--prologues] [--ds DATAFILE]`): follows calls, jumps and switch tables (sized by their bounds check, and the search-a-value kind), treats the block a program starts by jumping over as data, with `--prologues` also every C routine start not yet reached; used for GameSYS and AA-AC |
| `disassembler/matchfuncs.py` | Matches the routines of two listings (`matchfuncs.py AB.ASM AC.ASM`) |
| `disassembler/gamesys_names.txt`, `aa_names.txt`, `ab_names.txt`, `ac_names.txt` | The names in `GAMESYS.ASM`, `AA.ASM`, `AB.ASM` and `AC.ASM` |
| `tools/dec.py`, `tools/ds_names.txt` | C-like pseudocode for a routine of AB.ASM (or `-f AC.ASM`), with the data segment's names (`python3 tools/dec.py attack`) |
| `MANUAL_vs_CODE.md` | The printed manual and the C64 and Apple IIGS reference cards (`../Documentation`) checked against the PC code: what agrees, and what the PC game does differently (vassals, the castle's protection, leadership, the siege's days, the end of the game) |
| `DOC_vs_AB.md`, `tools/docmatch.py`, `tools/docflat.py`, `tools/doc_names.txt`, `tools/doc_ds_names.txt` | DOC.EXE's routines paired with AB's and named, its data segment, and what differs between the two versions' game logic, timing and graphics (`dec.py -f` reads DOC through `docflat.py`) |
| `tools/joust_scripts.py` | Lists the joust's four outcome animations (BJ items 37-40: each frame's two knights, item, rows, x, y) |
| `../Sound/tandymusic.py` | A port of the Tandy build's music driver: plays the tunes in BG into WAV files (`python3 tandymusic.py GAME.DAT OUTDIR [SECONDS]`) |
| `../Sound/speakermusic.py` | A port of the PC-speaker music player shared by DOC.EXE and the booter's CGA and EGA builds (`python3 speakermusic.py GAME.DAT-or-DOCCHARS.LIB OUTDIR [SECONDS]`) |
| `tools/dosbox/` | DOSBox configurations that run both versions (see below) |
| `../Graphics/extract_graphics.py` | Extracts every picture and sprite sheet of both versions into `../Graphics/CGA_DOS`, `Booter_CGA` and `Booter_EGA`; `doclib.py` reads the .LIB files, `gamedat.py` reads GAME.DAT (`python3 gamedat.py GAME.DAT OUTDIR` unpacks every file) |

## Findings

### Two versions, not one
- `cga/` is the **1987 DOS release**: DOC.EXE plus eight .LIB graphics files, CGA only. The title credits read "Master Designer Software, Inc. presents"; the IBM PC soundtrack is by Dave Farquharson.
- `ega/` is a **later self-booting release** (GameSYS © 1985-1988 by Interactive Designs; "Computography by David Todd / Fantasy Research"): two 360K disks kept as one file (GAME.DAT), with three builds of the game for **CGA, EGA and the Tandy 1000**, chosen at start (F1 for CGA, any other key for 16 colours). `DEFENDER.COM` is a cracker's loader ("Dos driver by Mok") that boots it from DOS by reading GAME.DAT instead of the floppy.
- Both tell the same story with the same scenes and characters, but their code, file formats and even their CGA pictures differ (the booter's CGA pictures were redrawn: between 1% and 72% of the bytes of a picture differ from DOC.EXE's).
- The DOS version's key-disk check is cracked in this copy. At the start, new_game loads `A:PROTECT` as if it were a .LIB (021C:011D), then calls key_disk_check (08AC:000F, 021C:0128), which reads sectors of drive A through the BIOS (int 13h, called through its vector: 08AC:0202, 0210) and compares what it finds with its own copy (08AC:0188); the conditional jump on its result is replaced by two NOPs (021C:0130).

### DOC.EXE (the DOS version)
- A large-model C program: every routine is called far, 76 code segments, one data segment (DGROUP at segment 0BCE). The strings are in DGROUP: the story texts, the events, the battle and siege messages, the credits.
- At start (021C:0002) it loads DOCCHARS.LIB into the buffer at [4508] (up to A000h bytes) and TITLE.LIB into the one at [4702] (up to C000h bytes) (load_lib 070A:015A: open, read the 7-byte BSAVE header, then the data over it). Scenes load their own .LIB (RAID, JOUST1, JOUST2, SIEGE, LOVE1, LOVE2) when they start.
- Pictures are unpacked into an off-screen buffer (show_lib_picture 070A:02B1 -> decompress 0946:0000, into DS:46EA; the format is in the file reference) and brought onto the screen by show_screen (070A:01B3), which also sets the palette: with a blinds wipe (four passes of every fourth line, two ticks a pass), or at once while DS:46D8 is set. Sprites are raw CGA bytes with a width in bits and a height, drawn straight onto the screen by a dozen primitives (put, AND mask, OR, XOR, colour 0 transparent, ...: `DOC_vs_AB.md`).
- Colours: CGA palette 0 (green, red, brown) on black throughout (set once in 070A:01B3); one screen (050E:0626) switches on the bright palette 0. The extracted title and cast screens match DOSBox pixel for pixel.
- It checks for an EGA (08F2:0002, int 10h AH=12h) but has no EGA graphics: the check only chooses the CRT controller register the joust's bobbing picture writes (10h on an EGA, 5 on a CGA).

### Unused code
Routines nothing calls (the remake needs none of them):
- **The booter (AB):** take_gold (44F4: a share of a side's gold, all of it up to 15, 15 of 16-38, else 40%), lady_at (2529: the lady held in a territory), clear_screen (8647) and the C runtime's long_shl (9E77; its shift rights are used). The Tandy program (AC) also has an unused clear_screen_worker (7DF1).
- **DOC.EXE:** the same two game routines, gold_share (050E:013F) and lady_at (03DE:0106), and a third, wall_damage (0637:05AB: the siege wall's next damage picture), whose code siege_by_player has inline instead (0637:0966). From the C library: the line and circle graphics (0984-09C8), creat, unlink, rename, realloc, frexp, ldexp, modf, and ran_exp? (0AFF:0073, exp(ran() x x)).
- **Copy protection:** DOC.EXE still runs its key-disk check, but the crack makes it ignore the result (above). The booter in this copy is started from DOS by `DEFENDER.COM`, a cracker's loader that reads GAME.DAT instead of the original floppies.

### GAME.DAT (the booter version)
- ZeroBoot's boot sector loads GameSYS, which provides the services (as interrupts 20h-22h and 2Ch-2Fh), detects the machine and video card and loads the right program (AA CGA, AB EGA, AC Tandy) to 0170:0100.
- Each disk has a directory in track 0 sector 9 (2-character names, first sector, sector count). Files are LZW-compressed (9-12 bit codes, as Unix `compress` without the block alignment). All 77 files unpack (`gamedat.py`).
- The programs AA, AB and AC are code only; they share one data file (BH: the texts and tables) and each has its own sprite files (B*). They read files by name through GameSYS (int 21h with the 2-character name in AX).
- **Pictures**: the CGA program uses the 20 Q files (16,000-byte CGA screens); the EGA and Tandy programs use the 20 C files (16 palette bytes + an LZW 4-plane 320x200 picture). Both sets are extracted. The EGA title matches DOSBox's.

### The Tandy 1000 version (AC)
It is the third build in GAME.DAT, not a separate release. GameSYS runs it when it finds a Tandy (its machine check and video detection, int 2Fh: [34C] = 2) and offers "16-color Tandy mode" at the prompt.

**The same game as the EGA build, with its own video and sound layer.** AC has 191 routines: 105 are instruction for instruction the same as in AB (EGA), 44 more are close matches (mostly differing in constants such as the segments where data is loaded), and 42 are AC's own: the video primitives, the sprite engine, the palette and the music driver (`AC_vs_AB.txt`). All the game logic is shared (at different addresses), and so is the data file BH. The remake can therefore keep one game and switch only the drawing and the sound.

**The CGA build (AA) is built the same way.** It has 172 routines: 115 the same as AB's, 34 close matches, and 23 its own: the drawing into a back buffer at 3000:8000 in the CGA's own layout, the copies to the screen (B800h, two banks) and, for GameSYS's video type 3 ("other"), separate copies in a four-bank layout, the fire flicker (XORed flames chosen at random) and a CRTC register write used by the joust (lance_step) when GameSYS's configuration word DS:0000 is 2 (`AA_vs_AB.txt`, `disassembler/aa_names.txt`).

**Video.** Mode 9 (320x200, 16 colours). AC draws into a back buffer at 3000:8000 laid out linearly (160 bytes a line, 2 pixels a byte, the left one in the high nibble; it uses the same row table DS:0D30 as AB, times 4) and copies it to the screen (B800h, four banks of 2000h) after the vertical retrace (present_worker 96A3). The Tandy's palette registers (3DAh/3DEh) are set from the picture's 16 palette bytes (tandy_set_palette A15C: *v* & 0Fh, plus 8 if *v* & 30h).

**Pictures**: the same 20 C files as the EGA build, unpacked to planes and converted to packed pixels (planar_to_packed A1A4). With every picture's palette the Tandy mapping gives the same colours as the EGA's, and the title is pixel-identical in DOSBox.

**Sprites**: the same pixels as the EGA build, stored as packed pixels instead of planes (formats in the file reference). Checked: all 24 sprites of Bh (EGA) and Bj (Tandy) are identical; so are the message-box pieces of BB and BC, except that **the Tandy build has only 4 of the 6 edge pieces for the top and bottom of a box** (BC's pieces 16h and 19h point at copies of 14h and 17h). That is the one difference seen on screen: a box's top and bottom edges repeat a slightly different pattern (in DOSBox, 150 pixels of the "insert reel two" box). Other screens compared in DOSBox (the introduction, Sherwood, the map, the orders menu, the tournament) differed only in game state (the territories are dealt at random, and the two builds run at different speeds).

**Sound.** The Tandy build alone has music for the Tandy's three-voice sound chip (SN76489, port C0h); the CGA and EGA builds play one-voice versions of the same tunes on the PC speaker (below). The Tandy music driver (AC 7444-7C53) runs from IRQ 0, which it speeds up to the song's tempo (149-239 interrupts a second) while still calling the BIOS clock at 18.2 Hz: every 4th interrupt is a sequencer tick, the others run the volume envelopes. The tunes are in BG (format in the file reference). `../Sound/tandymusic.py` ports the driver interrupt by interrupt and renders the tunes; the title tune it renders matches DOSBox's Tandy recording (the same notes; note starts within 10 ms over 30 s, loudness envelope correlation 0.91-0.99).

**The scenes do not wait for the Tandy music.** The CGA and EGA builds time parts of the opening by their tunes (the title waits for tune 97h to end, Sherwood's fire flickers until tune 98h ends, twice; with music off the tunes still run silently for this). AC has no play_tune / wait_tune: it starts a song (music_play) and times the same scenes by frame counts (Sherwood: counted rounds of 4 fire frames, a loop on CX of 20 and 26 at 07C7 and 07EF, then 125). The two kinds of tune also differ in length (the title 65.2 s on the speaker, 50.1 s on the Tandy; the intro 14.7 s against a song that runs on through Sherwood).

| Tune | Played (AC, with the scene's pictures and files) |
|---|---|
| 0 | the raid (44FA, the castle at night CN) |
| 1, 7 | the main turn loop (0C88, the land view CL) |
| 2 | the tournament (5337, trumpeters CG, jousting sprites BX/BY) |
| 3 (loops) | battles (4862, "You engage the campaign army of ...") and sieges (674D, 69AB, castles CP/CQ) |
| 4 (loops) | the Saxon lady (3A05, CR/CS/CT) |
| 5 | the title (01EA; the tune recorded in DOSBox) |
| 6 | the introduction (01EA) |

(Which tune goes with which scene is read from the routines that start them and the files they load; only the title was heard.)

Driver quirks a faithful remake keeps: a note word FFFAh turns vibrato off but the driver then sends FFFAh to the chip as the note and skips the next word; voices 2 and 3 test the loop marker the other way round from voices 0 and 1; the first voice to reach its end decides whether the song loops (in tune 0 voice 1 ends first, at tick 3072, and restarts the song: voice 2's last 129 ticks are never heard, and voice 0 holds its last note, whose duration 0 means 65536 ticks); a voice's end that restarts a song that has no loop marker goes back to the last song that had one (no tune ends that way).

### PC-speaker music (all three PC releases)
**One player, eight tunes, the same in DOC.EXE and the booter.** The tunes are items 150-157 of DOC.EXE's DOCCHARS.LIB (listed before as tables not yet decoded) and items 97h-9Eh of the booter's BA (CGA) and BB (EGA); the three copies are note for note the same. The player is the same code in DOC.EXE (its int 1Ch handler at load-image offset 9317h) and in the booter (AB play_tune 9559, int 1Ch handler 968A; AA 84AF-8655 has the same routines). The Tandy build has the player too (AC 925C, 9341) and keeps four of the tunes in BC, but plays its three-voice music instead; it still uses the speaker for the beeps below.

- A tune: word flags, word note count, word index and word ticks left (the player's state, 0 in the files), then the notes: word PIT divisor, word duration. A note sets PIT channel 2 to the divisor (a square wave of 1193182 / divisor Hz) for *duration* ticks of int 1Ch (18.2 a second; 0 lasts one tick). Divisor 36 (33 kHz, inaudible) is the rest. The speaker stays on from note to note; the first note starts on the tick after the tune is started.
- play_tune(tune, flags): flags 8000h play, 4000h loop, 2000h silent but timed, 0 stop. The game passes [35] (play once), [37] (loop) or [39] (always 0: stops the tune). The sound option ([33]) sets [35]/[37] to 8000h/C000h when on and A000h/E000h when off, so with the sound off the tunes still run silently and the scenes that wait for a tune's end (wait_tune 958E, tune_at 95BE) keep their timing.
- Beeps: beep(divisor, ticks) (AB 9520, the same in all three builds), e.g. beep(1000, 2) and beep(250, 2) (AB 932E, 938B) and beep([5F] or [65], 1) in the action scenes (AB 6C35, 6DCE, 6E67).
- `../Sound/speakermusic.py` ports the player and renders the tunes; the title tune it renders matches DOSBox's recording of the EGA build (the same pitch in 99.5% of 10-ms frames over 40 s, no drift).

| Speaker tune | Notes, length | Tandy tune (same scene) | Played |
|---|---|---|---|
| 97h | 229, 65 s | 5 | the title |
| 98h | 55, 14.5 s | 6 | the introduction |
| 99h | 72, 31 s | 4 | the Saxon lady |
| 9Ah | 49, 10 s | 2 | the tournament |
| 9Bh | 108, 28 s, loops | 0 | the raid |
| 9Ch | 109, 35 s, loops | 3 | battles and sieges |
| 9Dh | 52, 21 s | 7 | the main turn loop (AB 1B44, two places) |
| 9Eh | 110, 24 s | 1 | the main turn loop (AB 1B44, one place) |

(The pairs come from the routines that start them, matched between AB and AC; only the title was heard in both.)

### Graphics extracted (`../Graphics`)
- `CGA_compare/`: DOC.EXE's and the booter's CGA pictures side by side with their differing pixels, and DOSBox screens of both.
- `CGA_DOS/`: DOC.EXE's 20 pictures and a numbered sheet of each .LIB's sprites (portraits, fonts, territory shapes, swordsmen, jousting knights, siege effects, the lady's eyes).
- `Booter_CGA/`: the booter's 20 CGA pictures.
- `Booter_EGA/`: the booter's 20 16-colour pictures (EGA and Tandy).

### The two CGA versions compared (`../Graphics/CGA_compare`)
**The same drawings, partly recoloured and retouched.** DOC.EXE's 20 CGA pictures (in its .LIB files) and the booter's 20 (QA-QT) are the same 20 scenes; the booter's are not a straight copy:
- **Identical or nearly** (97-100% of pixels): the jousting lane, the second siege castle (SIEGE_01 / QQ), the window, the land view (QL, the sky aside).
- **Recoloured in places** (the same lines, other colours): the title's bricks (DOS red, booter green), the map's surround (DOS red, booter brown), the castle hall (DOS red, booter brown), the first siege castle (DOS brown, booter red), the trumpeters' banner and sky, the lady's dress, the character-choice panels (DOS brown, booter green).
- **Sprites baked in or left out**: DOC.EXE's pictures include things the booter draws as sprites (the knight on the lane, the two silhouettes and the window's figures in the romance, the raid's strength bars), and DOC.EXE's Sherwood (TITLE_06) has its scroll drawn in.
- **Palettes**: both use CGA palette 0, low intensity, on black (checked in DOSBox: title, character choice, Sherwood and the map in both). DOC.EXE alone switches on the intensity bit for one picture, the romance's bedchamber (LOVE2; 050E:0626 sets the background register's bit 4), so that scene is brighter there.
- **Other differences seen in DOSBox**: DOC.EXE's opening reads "Master Designer Software, Inc. presents...", and after the title shows the credits under a crown, two of them (Computography, Art Direction) blank; its character choice marks the character with its own name plates (TITLE.LIB). The rest: `DOC_vs_AB.md`.

## Running the originals in DOSBox
`tools/dosbox/` has four configurations; edit the `mount` line if the repo is elsewhere:
- `dotc_cga.conf`: the DOS version (DOC.EXE) on a CGA.
- `dotc_ega.conf`: the booter on an EGA (press a key other than F1 at the prompt). DEFENDER.COM needs `cputype=386`.
- `dotc_boot_cga.conf`: the booter on a CGA.
- `dotc_tandy.conf`: the booter on a Tandy 1000. DEFENDER.COM gives a garbled screen in DOSBox's Tandy mode (it puts its code and stack at 8000h-9FFFFh, near where a Tandy keeps its video memory), so this one boots the two floppy images instead: make them once with `python3 Graphics/gamedat.py Original/ega/GAME.DAT --disks Original/ega`. Ctrl-F4 swaps the disks when the game asks.

Checked in DOSBox 0.74-3 on 14 Nov 2026: both versions start and show their titles; the Tandy title is pixel-identical to the EGA one (CB).

## What was checked against the originals
The remake was compared with the originals running in DOSBox (`tools/dosbox/`), frame by frame where it says so; the rest was ported from the code alone.

| | Booter EGA (AB) | Booter CGA (AA), Tandy (AC) | DOS version (DOC.EXE) |
|---|---|---|---|
| Opening: credits, title, sparkles | the credits pixel-identical | Tandy title pixel-identical | pixel-identical (crown, sparkles) |
| Character choice | | CGA pixel-identical | |
| Sherwood | pixel-identical (but the flickering fire) | | pixel-identical text |
| Status panel, map, orders menu, Buy Home Army, Transfer Forces | the first month's status, Buy Home Army, Hold Tournament | | pixel-identical |
| Field battle screen | | | pixel-identical (soldiers only) |
| Siege (catapult, sprites) | | | the sprites |
| Raid, sword fight | | | the fighters |
| Joust: ride-in, charge, an unhorsing | pixel-identical, frame by frame | | pixel-identical (lane, lance, unhorsing) |
| Music | the title tune | the Tandy title tune | |

**Not compared:** the booter's sieges and raids, the romance (any version), the battles and sieges against you, the monthly events and the three endings (they use boxes, texts and sprites checked elsewhere), the mounted knights on the battle screen, and the DOS version's pace (`--rules=dos`, from its code). Two things DOSBox does not show at all: the joust's bobbing picture (a CRT controller trick: `GAME_LOGIC.md`, *The joust*) and the speed of the PCs of 1987 (the remake's catapult and sword fight paces are estimates of it).

## Left
- The `?` names in `tools/doc_names.txt` (a few routines named from a quick look, not read through).
- The uses of each beep, listed one by one; which tune plays in which scene is read from the code (only the title was heard).
