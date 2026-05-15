#!/bin/bash
# build-ccp.sh -- reproducibly rebuild ccp.spr from source.
#
# Runs DRI's RMAC + LINK under VirtualCpm and verifies the output
# is byte-identical to the distribution's cpnet-z80/dist/ccp.spr.
#
# Usage:  ./build-ccp.sh [output-dir]
#
# Prerequisites:
#   - /Users/ravn/z80/cpnet-z80/tools/VirtualCpm.jar
#   - /Users/ravn/z80/cpnet-z80/dist/vcpm/{rmac,link}.com
#   - /Users/ravn/z80/cpnet-z80/dist/src/ccp.asm

set -euo pipefail

OUT=${1:-/tmp/ccp_build}
HERE=$(cd "$(dirname "$0")" && pwd)
CPNET=/Users/ravn/z80/cpnet-z80
VCPM_JAR="$CPNET/tools/VirtualCpm.jar"

mkdir -p "$OUT/a" "$OUT/d"

# A: holds DRI tools, D: is the working dir.
cp "$CPNET/dist/vcpm/rmac.com" "$OUT/a/"
cp "$CPNET/dist/vcpm/link.com" "$OUT/a/"

# CCP source -> D: one-instruction-per-line (CRLF for RMAC).
# dri_split.py expands DRI MAC's '!' statement+comment terminators
# into newlines so the source is readable and editable while still
# producing byte-identical ccp.spr from RMAC.
"$HERE/dri_split.py" "$CPNET/dist/src/ccp.asm" "$OUT/d/CCP.ASM"

export CPMDrive_A="$OUT/a"
export CPMDrive_D="$OUT/d"
export CPMDefault=d:

echo "--- RMAC ccp ---"
java -jar "$VCPM_JAR" rmac ccp

echo "--- LINK ccp[os] ---"
java -jar "$VCPM_JAR" link 'ccp[os]'

echo "--- verify ---"
if cmp -s "$OUT/d/ccp.spr" "$CPNET/dist/ccp.spr"; then
    echo "PASS: $OUT/d/ccp.spr byte-identical to $CPNET/dist/ccp.spr (3200 B)"
else
    echo "FAIL: rebuild differs from distribution"
    cmp "$OUT/d/ccp.spr" "$CPNET/dist/ccp.spr" || true
    exit 1
fi
