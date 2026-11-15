# Defender of the Crown
Analysis of Cinemaware's Defender of the Crown for the IBM PC, and a modern remake for the Mac (as was done for [The Ancient Art of War](https://github.com/BrettHallen/Ancient-Art-of-War)).

## Versions
The [original files](/Original) hold two different PC versions:
- `cga/`: the 1987 DOS release (DOC.EXE + .LIB graphics), CGA only.
- `ega/`: a later self-booting release (GameSYS 4.0 by Interactive Designs) with CGA, EGA and Tandy 1000 16-colour graphics, kept as one disk image file (GAME.DAT) and started from DOS with DEFENDER.COM.

## [Remake](/Remake)
The remake for macOS (C and SDL3), a port of the booter's EGA program, showing the game as the 1987 DOS version's CGA, the booter's CGA, EGA or Tandy 1000 did (Tab switches, `--video=cga1|cga2|ega|tandy`), with a game log (`--log`). So far: the opening, the choice of character, Sherwood, the month with its events, the computer lords' turns, Buy Home Army, Seek Conquest with battles and sieges, Read Map, Go Raiding with the sword fight, the rescue of a kidnapped lady, and the tournaments with the joust; still to come: the romance scene. Build and run as in its [README](/Remake/README.md).

## [Analysis](/Analysis)
What every file holds ([file reference](/Analysis/DOTC_file_reference.md)), the [findings](/Analysis/README.md), and the disassemblies of DOC.EXE, the booter's loader and its three game programs (CGA, EGA and Tandy 1000).

## [Sound](/Sound)
`tandymusic.py` plays the Tandy 1000 version's three-voice music and `speakermusic.py` the PC-speaker music (shared by the DOS version and the booter's CGA and EGA builds) into WAV files; both are ports of the original players.

## [Graphics](/Graphics)
The pictures and sprites of both versions, decoded by `extract_graphics.py`: [DOS CGA](/Graphics/CGA_DOS), [booter CGA](/Graphics/Booter_CGA) and [booter EGA/Tandy](/Graphics/Booter_EGA), with the EGA build's [sprites](/Graphics/Booter_EGA/sprites).
