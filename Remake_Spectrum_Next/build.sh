#!/bin/sh
# Defender of the Crown - Spectrum Next remake: builds build/sd/ from your own
# GAME.DAT (default: ../Original/ega/GAME.DAT): the game's folder DOTC, with
# DOTC.NEX and the pictures in DOTC_GFX beside it, to copy to the SD card as it is.
#
#   ./build.sh [path/to/GAME.DAT]
#
# Needs Python 3 and Boriel's zxbasm assembler:  pip3 install zxbasic
set -e
cd "$(dirname "$0")"
GAME_DAT="${1:-../Original/ega/GAME.DAT}"
if [ ! -f "$GAME_DAT" ]; then
    echo "No GAME.DAT at $GAME_DAT: give its path, e.g. ./build.sh /path/to/GAME.DAT" >&2
    exit 1
fi
if ! command -v zxbasm >/dev/null 2>&1; then
    echo "zxbasm not found: install it with  pip3 install zxbasic" >&2
    exit 1
fi
mkdir -p build
python3 tools/convert.py "$GAME_DAT" build
zxbasm --zxnext src/title.asm -o build/title.bin -M build/title.map
python3 tools/make_nex.py build/title.bin build/sd/DOTC/DOTC.NEX
