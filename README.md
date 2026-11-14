# Defender of the Crown
Analysis of Cinemaware's Defender of the Crown for the IBM PC, as a step towards a modern remake for the Mac (as was done for [The Ancient Art of War](https://github.com/BrettHallen/Ancient-Art-of-War)).

## Versions
The [original files](/Original) hold two different PC versions:
- `cga/`: the 1987 DOS release (DOC.EXE + .LIB graphics), CGA only.
- `ega/`: a later self-booting release (GameSYS 4.0 by Interactive Designs) with CGA, EGA and Tandy 1000 16-colour graphics, kept as one disk image file (GAME.DAT) and started from DOS with DEFENDER.COM.

## [Analysis](/Analysis)
What every file holds ([file reference](/Analysis/DOTC_file_reference.md)), the [findings](/Analysis/README.md), and the disassemblies of DOC.EXE, the booter's loader and its three game programs (CGA, EGA and Tandy 1000).

## [Sound](/Sound)
`tandymusic.py` plays the Tandy 1000 version's three-voice music and `speakermusic.py` the PC-speaker music (shared by the DOS version and the booter's CGA and EGA builds) into WAV files; both are ports of the original players.

## [Graphics](/Graphics)
The pictures and sprites of both versions, decoded by `extract_graphics.py`: [DOS CGA](/Graphics/CGA_DOS), [booter CGA](/Graphics/Booter_CGA) and [booter EGA/Tandy](/Graphics/Booter_EGA).
