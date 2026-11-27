# The reference

The Spectrum Next version is checked against the Mac remake itself: its own game, drawing, asset and sound code (`../../../Remake/src`, all but `main.c`, `sys.c` and `icon.c`), built here without SDL.

- `SDL3/SDL.h` stands in for the little of SDL that code uses, over the C library.
- `ref_sys.c` stands in for `sys.c`, with the same waits and keys but on one thread and a virtual clock, so a run is the same every time. Every screen the game presents in Tandy mode is recorded, with its time and palette.
- `dump_tandy.c` dumps the remake's decoding of the Tandy sprite files. `check_sprites.py` checks the converter's decoding against it, item by item.
- `rec.py` lists a recording, or writes one of its screens or a sheet of them all as a PNG.

## Building and recording
A C compiler is all it needs:
```sh
cd test/ref
./build.sh
mkdir -p ../../build/ref
GAME=../../../Original/ega        # the folder with your GAME.DAT
./ref $GAME ../../build/ref/opening.rec 80                         # no keys
./ref $GAME ../../build/ref/skip.rec 72 5:1F                       # S at 5 s
./ref $GAME ../../build/ref/sherwood.rec 140 70:4D 71:50 72:1C     # keypad 6, 2, Enter
./dump_tandy $GAME /tmp/tandy_sprites.bin
python3 check_sprites.py $GAME/GAME.DAT /tmp/tandy_sprites.bin
```
Each key is `seconds:scan code` (the PC's, in hex). `../run_nex.py` then runs the Next's program with the same keys and checks that it shows the same screens.
