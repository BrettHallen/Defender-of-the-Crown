# Defender of the Crown
Analysis of Cinemaware's Defender of the Crown for the IBM PC, and a modern remake for the Mac (as was done for [The Ancient Art of War](https://github.com/BrettHallen/Ancient-Art-of-War)).<br>

The remake could also be compiled for Linux and Windows but this hasn't been tested.<br>

## Versions
The [original files](/Original) hold two different PC versions:
- `cga/`: the 1987 DOS release (DOC.EXE + .LIB graphics), CGA only.
- `ega/`: a later self-booting release (GameSYS 4.0 by Interactive Designs) with CGA, EGA and Tandy 1000 16-colour graphics, kept as one disk image file (GAME.DAT) and started from DOS with DEFENDER.COM.

## [Remake](/Remake)
The remake for macOS (C and SDL3), a port of the booter's EGA program, showing the game as the 1987 DOS version's CGA, the booter's CGA, EGA or Tandy 1000 did (Tab switches, `--video=cga1|cga2|ega|tandy`), with a game log (`--log`).<br>

The remake is completed:
- the opening,
- the choice of character,
- Sherwood,
- the month with its events,
- the computer lords' turns,
- Buy Home Army,
- Seek Conquest with battles and sieges,
- Read Map,
- Go Raiding with the sword fight,
- the rescue of a kidnapped lady with the romance, and
- the tournaments with the joust

Build and run as in its [README](/Remake/README.md), or the [Quick Reference](/Remake/DOTC_Remake_Quick_Reference.pdf).

## [Spectrum Next remake](/Remake_Spectrum_Next)
A version for the ZX Spectrum Next from the booter's Tandy 1000 program: its pictures on Layer 2 (320×256) and its music on the AY chips, converted at build time from your own GAME.DAT. So far the opening: the credits, the title with its sparkles, the cast, the choice of character and Sherwood, checked screen by screen against the Mac remake.

## [Analysis](/Analysis)
What every file holds ([file reference](/Analysis/DOTC_file_reference.md)), the [findings](/Analysis/README.md) and what was checked against the originals, the game's rules as read from the code ([game logic](/Analysis/GAME_LOGIC.md)), the two PC versions compared ([DOC.EXE against the booter](/Analysis/DOC_vs_AB.md)), the printed manual checked against the code ([manual vs code](/Analysis/MANUAL_vs_CODE.md)), and the disassemblies of DOC.EXE, the booter's loader and its three game programs (CGA, EGA and Tandy 1000).

## [Documentation](/Documentation)
Scans of the printed manual and the Commodore 64 and Apple IIGS reference cards (no scan of the IBM PC's card has been found). And a [strategy guide](/Documentation/DOTC_PC_Strategy_Guide.pdf) for the PC version, written from its code.

## [Sound](/Sound)
`tandymusic.py` plays the Tandy 1000 version's three-voice music and `speakermusic.py` the PC-speaker music (shared by the DOS version and the booter's CGA and EGA builds) into WAV files; both are ports of the original players.

## [Graphics](/Graphics)
The pictures and sprites of both versions, decoded by `extract_graphics.py`: [DOS CGA](/Graphics/CGA_DOS), [booter CGA](/Graphics/Booter_CGA) and [booter EGA/Tandy](/Graphics/Booter_EGA), with the EGA build's [sprites](/Graphics/Booter_EGA/sprites).
