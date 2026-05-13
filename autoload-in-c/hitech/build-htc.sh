#!/bin/sh
# Compile one .c file under HI-TECH C V4.11 (cross-compiler, MS-DOS hosted
# via DOSBox in ghcr.io/ravn/hitech-v411).  Three-stage pipeline:
#
#   1. Host `gcc -E` preprocesses the source.  V4.11's cpp.exe lacks
#      `#elif`, `#include` line markers (path-too-long issues), and
#      modern C dialect features; using gcc -E sidesteps all of them.
#
#   2. Python filter strips:
#        - Ctrl-Z (0x1A) bytes: every V4.11 header ends with one
#          (CP/M EOF convention); V4.11's p1 honours ^Z mid-stream
#          and silently truncates the parse.
#        - `// line comments`: V4.11 cpp doesn't accept them.
#      All `__attribute__` / `__naked` / `inline` etc. token shimming
#      lives in rom.h's HITECH branch — no scrub needed here.
#
#   3. V4.11 pipeline inside DOSBox:  p1 -QP,port -> cgen -> zas
#      The -QP,port flag enables V4.11's `port` type qualifier (which
#      emits IN/OUT directly); zc.exe passes it automatically when
#      targeting Z80.
#
# Output: <STEM>.OBJ in the current directory.  Subsequent `link` +
# `objtohex` runs (also via the V4.11 image) produce a flashable .bin.
#
# Usage:
#   hitech/build-htc.sh <source.c>
#   ROOT_C_HEADERS=/path/to/v411/diskA/HITECH hitech/build-htc.sh foo.c

set -eu

usage() { echo "usage: $0 <source.c>" >&2; exit 64; }
[ $# -ge 1 ] || usage
src=$1; shift
stem=$(basename "$src" .c)
upper=$(echo "$stem" | tr a-z A-Z | cut -c1-8)
here=$(cd "$(dirname "$src")" && pwd)
hitech_dir=$(cd "$(dirname "$0")" && pwd)

# Pre-flight: locate V4.11 stdlib headers.
ROOT_C_HEADERS=${ROOT_C_HEADERS:-/tmp/hitech-v411/diskA/HITECH}
if [ ! -d "$ROOT_C_HEADERS" ]; then
    echo "$0: V4.11 headers not found at $ROOT_C_HEADERS" >&2
    echo "  set ROOT_C_HEADERS or clone github.com/ravn/hitech-v411" >&2
    exit 1
fi

IMG=${IMG:-hitech-v411:test}

echo "[$stem -> $upper.OBJ]"

# 1. Preprocess on host with the same predefines V4.11 zc emits.
gcc -E -nostdinc -undef -P \
    -DHI_TECH_C=1 -Dz80=1 -DHITECH=1 \
    -I"$hitech_dir" \
    -I"$here" \
    -I"$ROOT_C_HEADERS" \
    "$src" > "$upper.PP" 2> "$upper.PPERR"

# 2. Strip CP/M EOF markers and // comments.
python3 - "$upper.PP" "$upper.I" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
src = src.replace('\x1a', '')                  # Ctrl-Z (CP/M EOF)
src = re.sub(r'//[^\n]*', '', src)             # // comments
open(sys.argv[2], 'w').write(src)
PY

# 3. V4.11 pipeline inside DOSBox.
docker run --rm -v "$(pwd):/work" "$IMG" dosbox -conf /dev/null -noautoexec -exit \
    -c "mount c /opt/hitech" -c "mount d /work" -c "set HITECH=C:\\" -c "d:" \
    -c "c:\\p1.exe -QP,port $upper.I $upper.T2 $upper.T3 > $upper.P1L" \
    -c "c:\\cgen.exe $upper.T2 $upper.T1 > $upper.CGL" \
    -c "c:\\zas.exe -N -O$upper.OBJ $upper.T1 > $upper.ZSL" \
    -c "exit" >/dev/null 2>&1

# Report failures (any tool with non-empty stdout indicates a problem).
rc=0
for f in "$upper.P1L" "$upper.CGL" "$upper.ZSL"; do
    if [ -s "$f" ]; then
        echo "  --- $f ---"
        sed 's/^/    /' "$f"
        rc=1
    fi
done

if [ -s "$upper.OBJ" ] && [ "$(wc -c < "$upper.OBJ")" -gt 30 ]; then
    echo "  -> $upper.OBJ ($(wc -c < "$upper.OBJ") bytes)"
else
    echo "  -> $upper.OBJ produced no real content"
    rc=1
fi
exit $rc
