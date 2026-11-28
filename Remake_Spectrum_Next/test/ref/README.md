# The reference

The Spectrum Next version is checked against the Mac remake itself: its own game, drawing, asset and sound code (`../../../Remake/src`, all but `main.c`, `sys.c` and `icon.c`), built here without SDL.

- `SDL3/SDL.h` stands in for the little of SDL that code uses, over the C library.
- `ref_sys.c` stands in for `sys.c`, with the same waits and keys but on one thread and a virtual clock, so a run is the same every time. Every screen the game presents in Tandy mode is recorded, with its time and palette. With `REF_DS` set, the data segment is written to that file at the end, to compare the game's state. A loop that only reads the clock (`while (sys_ticks() == t0)`) moves the virtual clock on, as real time would.
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
REF_DS=../../build/ref/month_ds.bin \
./ref $GAME ../../build/ref/month.rec 108 70:4D 71:50 72:1C        # to the first orders; its data segment too
./ref $GAME ../../build/ref/pass.rec 160 70:4D 71:50 72:1C 110:50 110.5:50 111:50 111.5:50 112:50 113:1C   # then Pass
REF_MARKS=../../build/ref/months.marks REF_AUTO=114 REF_DS_AT=9 REF_DS=../../build/ref/months_ds.bin \
./ref $GAME ../../build/ref/months.rec 400 70:4D 71:50 72:1C 110:50 110.5:50 111:50 111.5:50 112:50 113:1C   # 9 months
REF_DS=../../build/ref/buy_ds.bin ./ref $GAME ../../build/ref/buy.rec 134.5 70:4D 71:50 72:1C 110:50 110.5:50 111:50 \
    112:1C 114:4D 115:4D 116:4D 117:50 118:4D 119:4B 120:48 121:4B 122:50 122.5:50 123:50 123.5:50 124.5:1C
REF_DS=../../build/ref/conq_ds.bin ./ref $GAME ../../build/ref/conq.rec 149.5 70:4D 71:50 72:1C 110:50 110.5:50 111:50 \
    111.5:50 112:1C 114:1C 116:4D 117:1C 119:50 120:1C 122:48 122.5:48 123:48 124:1C 126:50 127:1C 129:4D 129.5:4D \
    130:4D 130.5:4D 131:50 131.5:50 132:50 133:1C 135:1C 137:4D 138:1C
REF_POKE="107:C1=6,151=6,153=6,155=28,157=6,159=1,6F3=1" REF_POLL=117 REF_POLL_KEYS=1C,1C,1C,1C,50,1C,1C,50,1C,1C \
REF_MARKS=../../build/ref/siege.marks REF_DS=../../build/ref/siege_ds.bin \
./ref $GAME ../../build/ref/siege.rec 230.5 70:4D 71:50 72:1C 110:50 111:1C 113:1C 115:4D 116:1C   # a siege of Norfolk
REF_POLL=110 REF_MARKS=../../build/ref/tourn.marks REF_DS=../../build/ref/tourn_ds.bin \
./ref $GAME ../../build/ref/tourn.rec 165 70:4D 71:50 72:1C                         # Hold Tournament
./dump_tandy $GAME /tmp/tandy_sprites.bin
python3 check_sprites.py $GAME/GAME.DAT /tmp/tandy_sprites.bin
```
Each key is `seconds:scan code` (the PC's, in hex). With `REF_AUTO=seconds`, from then on each wait for a key at a menu gets Enter after 1 s (its times written to `REF_MARKS`); `REF_DS_AT=n` writes the data segment to `REF_DS` at the n-th such Enter and ends the run there. `../run_nex.py` then runs the Next's program with the same keys and checks that it shows the same screens.
