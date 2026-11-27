#!/bin/sh
# test/ref/build.sh: builds the reference (ref_sys.c) from the Mac remake's
# sources in ../../../Remake/src, all but main.c, sys.c and icon.c, and
# dump_tandy (its Tandy sprites, to check the converter's against).
set -e
cd "$(dirname "$0")"
SRC=../../../Remake/src
srcs=""
for f in $SRC/*.c; do
    case "$(basename "$f")" in main.c|sys.c|icon.c) ;; *) srcs="$srcs $f" ;; esac
done
${CC:-cc} -O1 -g -w -I. -I$SRC ref_sys.c $srcs -lm -o ref
${CC:-cc} -O1 -g -w -I. -I$SRC dump_tandy.c $SRC/assets.c $SRC/dat.c -lm -o dump_tandy
