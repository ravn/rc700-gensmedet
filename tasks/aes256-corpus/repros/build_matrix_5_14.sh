#!/usr/bin/env bash
# Build matrix for ravn/z88dk#5/#14 isolated repro.
#
# Builds the same minimal program 5 ways, runs each in z88dk-ticks,
# reads byte at 0xC000 from the RAM dump.  Expected:
#   byte = 0xA5  -> store hit RAM  (PASS)
#   byte != 0xA5 -> store was dropped (FAIL -- bug confirmed)
#
# Also dumps the disassembly of each build's main() to .asm.

set -euo pipefail

Z88DK=/Users/ravn/z80/z88dk
TICKS=$Z88DK/bin/z88dk-ticks
ZCC_ENV="ZCCCFG=$Z88DK/lib/config PATH=$Z88DK/bin:$PATH"
ZCC="$Z88DK/bin/zcc"

HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
mkdir -p build_5_14
cd build_5_14

build_run() {
  local label=$1; shift
  local src=$1; shift
  local cflags="$*"
  cp ../$src ./prog.c

  if ! eval "$ZCC_ENV $ZCC +z80 -compiler=sdcc $cflags -m --list -create-app -o prog_${label} prog.c" >${label}.buildlog 2>&1; then
    printf '%-40s BUILD-FAIL\n' "$label"
    return
  fi

  local bin_size=$(wc -c < prog_${label}.bin | tr -d ' ')

  # Find HALT pattern (post-main exit).
  local done_addr=$(python3 -c "
import re
d = open('prog_${label}.bin', 'rb').read()
m = re.search(b'\\xe5\\xf3\\xe1\\x76', d)
print(f'0x{m.start()+3:04X}' if m else exit(1))
")

  # Pad with JP $done_addr to dodge ticks counter-reset on PC wraparound.
  python3 ../../fill_with_jp_done.py prog_${label}.bin prog_${label}.filled.bin "$done_addr"

  perl -e 'alarm 30; exec @ARGV' \
    $TICKS -mz80 -end $done_addr -counter 50000000 \
    -output prog_${label}.ram prog_${label}.filled.bin > prog_${label}.ticks 2>&1 || true

  local result_byte verify
  if [ ! -f prog_${label}.ram ]; then
    result_byte="--"
    verify="TIMEOUT"
  else
    result_byte=$(python3 -c "d=open('prog_${label}.ram','rb').read(); print(f'0x{d[0xC000]:02X}')")
    if [ "$result_byte" = "0xA5" ]; then verify="PASS"; else verify="FAIL"; fi
  fi

  printf '%-40s bin=%4s @0xC000=%s %s\n' "$label" "$bin_size" "$result_byte" "$verify"
}

echo "Config                                   bin  @0xC000  verify"
echo "---------------------------------------- ---- -------  ------"

build_run "01_KR_sdcccall1_default"   repro_5_14_minimal.c       '--opt-code-size -SO3 -Cs"--sdcccall 1" -Cs"--disable-warning 296" -Cs"--max-allocs-per-node 25000" -Cs"--fomit-frame-pointer"'
build_run "02_KR_sdcccall1_nogcse"    repro_5_14_minimal.c       '--opt-code-size -SO3 -Cs"--sdcccall 1" -Cs"--disable-warning 296" -Cs"--max-allocs-per-node 25000" -Cs"--fomit-frame-pointer" -Cs"--nogcse"'
build_run "03_KR_sdcccall0_nogcse"    repro_5_14_minimal.c       '--opt-code-size -SO3 -Cs"--max-allocs-per-node 25000" -Cs"--fomit-frame-pointer" -Cs"--nogcse"'
build_run "04_ANSI_sdcccall1_nogcse"  repro_5_14_minimal_ansi.c  '--opt-code-size -SO3 -Cs"--sdcccall 1" -Cs"--disable-warning 296" -Cs"--max-allocs-per-node 25000" -Cs"--fomit-frame-pointer" -Cs"--nogcse"'
build_run "05_ANSI_sdcccall1_default" repro_5_14_minimal_ansi.c  '--opt-code-size -SO3 -Cs"--sdcccall 1" -Cs"--disable-warning 296" -Cs"--max-allocs-per-node 25000" -Cs"--fomit-frame-pointer"'

echo
echo "Disassembly of main() for each build:"
for label in 01_KR_sdcccall1_default 02_KR_sdcccall1_nogcse 03_KR_sdcccall0_nogcse 04_ANSI_sdcccall1_nogcse 05_ANSI_sdcccall1_default; do
  echo "--- $label ---"
  awk '/^_main:/,/^_[a-z]/' prog_${label}.lis 2>/dev/null | head -30
  echo
done
