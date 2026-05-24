#!/usr/bin/env bash
# Measure AES 09_Oz_prod_like .text (sum of t/T symbol sizes in aes256.o).
# Single-config quick signal for the #180 peephole audit re-tests.
# Usage: measure_aes09.sh [label]   (label only affects the temp .o name)
set -e
LABEL="${1:-probe}"
CLANG=/Users/ravn/z80/llvm-z80/build-macos/bin/clang
LLVMNM=/Users/ravn/z80/llvm-z80/build-macos/bin/llvm-nm
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE/sweep"
"$CLANG" --target=z80 -nostdlib -ffreestanding -std=c89 -Wno-deprecated-non-prototype \
  -Oz -Xclang -target-feature -Xclang +static-stack \
  -mllvm -disable-lsr -mllvm -disable-machine-licm -mllvm -disable-machine-cse \
  -ffunction-sections -fdata-sections \
  -c ../aes256.c -o "${LABEL}_aes.o"
"$LLVMNM" --print-size --size-sort "${LABEL}_aes.o" 2>/dev/null | \
  python3 -c "import sys; t=sum(int(p[1],16) for p in (l.split() for l in sys.stdin) if len(p)>=4 and p[2] in 'tT'); print(t)"
