#!/bin/bash
# build-ccp-zmac.sh -- reproduce ccp.spr's 2560-byte code section with zmac.
#
# Host-side build that avoids RMAC/LINK under VirtualCpm entirely.
# Useful as the base for Z80-optimisation experiments: zmac handles
# full-length symbols (no 6-char truncation like M80) and has -8 mode
# for byte-compatible 8080 assembly, plus native Z80 mode.
#
# Assembles the dri_split output of ccp.asm at ORG 0, then zero-pads
# zmac's truncated tail (zmac strips trailing DEFS; the real .SPR pads
# to the page-aligned code length).  Asserts byte-identity against the
# code section extracted from cpnet-z80/dist/ccp.spr.
#
# Usage:  ./build-ccp-zmac.sh [output-dir]

set -euo pipefail

OUT=${1:-/tmp/ccp_zmac}
HERE=$(cd "$(dirname "$0")" && pwd)
CPNET=/Users/ravn/z80/cpnet-z80
ZMAC="$HERE/../../zmac/bin/zmac"

mkdir -p "$OUT"
"$HERE/dri_split.py" "$CPNET/dist/src/ccp.asm" "$OUT/CCP.ASM"

( cd "$OUT" && "$ZMAC" -8 --dri CCP.ASM >/dev/null )

# Extract the 2560-byte code section from the reference SPR.
#  offset 0..127 = parameter record
#  offset 128..255 = data sector
#  offset 256..2815 = code (2560 B) + relocation bitmap (320 B)
dd if="$CPNET/dist/ccp.spr" bs=1 skip=256 count=2560 of="$OUT/spr_code.bin" 2>/dev/null

# zmac truncates trailing DEFS; pad to the full code length.
ZMAC_SIZE=$(wc -c < "$OUT/zout/CCP.cim")
if [ "$ZMAC_SIZE" -lt 2560 ]; then
    PAD=$((2560 - ZMAC_SIZE))
    dd if=/dev/zero bs=1 count="$PAD" 2>/dev/null | cat "$OUT/zout/CCP.cim" - > "$OUT/zmac_padded.bin"
else
    cp "$OUT/zout/CCP.cim" "$OUT/zmac_padded.bin"
fi

if cmp -s "$OUT/zmac_padded.bin" "$OUT/spr_code.bin"; then
    echo "PASS: zmac assembles ccp.asm byte-identical to ccp.spr code section (2560 B)"
else
    echo "FAIL: zmac output differs from ccp.spr code section"
    cmp "$OUT/zmac_padded.bin" "$OUT/spr_code.bin" || true
    exit 1
fi
