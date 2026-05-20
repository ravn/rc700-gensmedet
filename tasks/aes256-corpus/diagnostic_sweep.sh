#!/usr/bin/env bash
# Diagnostic sweep — tests the hypothesis that K&R-only zsdcc bugs
# (ravn/z88dk#5 --nogcse, #6 sdcc_ix) share root cause with
# ravn/z88dk#14 (K&R int-promotion under --sdcccall 1).
#
# Strategy: each of the 6 configs flips ONE of {--sdcccall, --nogcse,
# -clib=sdcc_iy/_ix} relative to the production baseline, on K&R
# source.  If toggling --sdcccall to 0 makes #5 / #6 disappear, they
# share root cause with #14.
#
# Writes TSV-only; markdown comes from the analysis step.

set -euo pipefail

Z88DK=/Users/ravn/z80/z88dk
TICKS=$Z88DK/bin/z88dk-ticks
ZCC_ENV="ZCCCFG=$Z88DK/lib/config PATH=$Z88DK/bin:$PATH"
ZCC="$Z88DK/bin/zcc"

HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
mkdir -p sweep_diag
cd sweep_diag

AES_SRC=${AES_SRC:-../aes256.c}

TSV=results_diag.tsv
printf 'label\tbin\ttstates\tverify\tflags\n' > "$TSV"

build_and_measure() {
  local label=$1; shift
  local cflags="$*"
  local prefix="${label}"

  cp "$AES_SRC" ./aes256.c
  cp ../test_main.c .
  rm -f ${prefix}_*.map ${prefix}.bin ${prefix}.map ${prefix}.ram

  if ! eval "$ZCC_ENV $ZCC +z80 -compiler=sdcc $cflags -m -create-app \
       -o ${prefix} aes256.c test_main.c" >${prefix}.buildlog 2>&1; then
    printf '%-40s %s\n' "$label" "BUILD-FAIL"
    printf '%s\t-\t-\tBUILD-FAIL\t%s\n' "$label" "$cflags" >> "$TSV"
    return
  fi

  local bin_size=$(wc -c < ${prefix}.bin | tr -d ' ')

  local done_addr=$(python3 -c "
import re
d = open('${prefix}.bin', 'rb').read()
m = re.search(b'\\xe5\\xf3\\xe1\\x76', d)
print(f'0x{m.start()+3:04X}' if m else exit(1))
")

  # Pad the bin with JP $done_addr per fill_with_jp_done.py to avoid
  # ticks's pc==start counter-reset bug.  Without this, miscompiled
  # bins that overrun into NOP-sled wrap PC to 0x0000 -> ticks resets
  # tstate counter -> reported runtime is the LAST wraparound only,
  # not the total.  Matches what flag_sweep_sdcc.sh does.
  python3 ../fill_with_jp_done.py ${prefix}.bin ${prefix}.filled.bin "$done_addr"

  local tstates=$(perl -e 'alarm 90; exec @ARGV' \
    $TICKS -mz80 -end $done_addr -counter 100000000 \
    -output ${prefix}.ram ${prefix}.filled.bin 2>&1 | tail -1 || true)

  local verify
  if [ ! -f ${prefix}.ram ]; then
    verify="TIMEOUT"
  else
    verify=$(python3 -c "d=open('${prefix}.ram','rb').read(); v=d[0xC000:0xC023]; \
      print('PASS' if v[16]==1 and v[33]==1 and v[34]==0xA5 else 'FAIL')")
  fi

  printf '%s\t%s\t%s\t%s\t%s\n' "$label" "$bin_size" "$tstates" "$verify" "$cflags" >> "$TSV"
  printf '%-40s bin=%5s tstates=%10s %s\n' "$label" "$bin_size" "$tstates" "$verify"
}

echo "Diagnostic sweep — K&R source"
echo "Goal: test if --sdcccall 0 makes #5 / #6 disappear"
echo "Config                                   bin    tstates   verify"
echo "---------------------------------------- ----- ---------- ------"

# Baselines for reference (both already in main sweep, repeated for context).
build_and_measure "01_KR_prod_sdcccall1_iy"     '-clib=sdcc_iy --opt-code-size -SO3 -Cs"--sdcccall 1" -Cs"--disable-warning 296" -Cs"--max-allocs-per-node 25000" -Cs"--fomit-frame-pointer"'
build_and_measure "02_KR_sdcccall0_iy"          '-clib=sdcc_iy --opt-code-size -SO3 -Cs"--max-allocs-per-node 25000" -Cs"--fomit-frame-pointer"'

# Cross-products with --nogcse:
build_and_measure "03_KR_sdcccall1_iy_nogcse"   '-clib=sdcc_iy --opt-code-size -SO3 -Cs"--sdcccall 1" -Cs"--disable-warning 296" -Cs"--max-allocs-per-node 25000" -Cs"--fomit-frame-pointer" -Cs"--nogcse"'
build_and_measure "04_KR_sdcccall0_iy_nogcse"   '-clib=sdcc_iy --opt-code-size -SO3 -Cs"--max-allocs-per-node 25000" -Cs"--fomit-frame-pointer" -Cs"--nogcse"'

# Cross-products with -clib=sdcc_ix:
build_and_measure "05_KR_sdcccall1_ix"          '-clib=sdcc_ix --opt-code-size -SO3 -Cs"--sdcccall 1" -Cs"--disable-warning 296" -Cs"--max-allocs-per-node 25000" -Cs"--fomit-frame-pointer"'
build_and_measure "06_KR_sdcccall0_ix"          '-clib=sdcc_ix --opt-code-size -SO3 -Cs"--max-allocs-per-node 25000" -Cs"--fomit-frame-pointer"'

# Both bugs combined:
build_and_measure "07_KR_sdcccall1_ix_nogcse"   '-clib=sdcc_ix --opt-code-size -SO3 -Cs"--sdcccall 1" -Cs"--disable-warning 296" -Cs"--max-allocs-per-node 25000" -Cs"--fomit-frame-pointer" -Cs"--nogcse"'
build_and_measure "08_KR_sdcccall0_ix_nogcse"   '-clib=sdcc_ix --opt-code-size -SO3 -Cs"--max-allocs-per-node 25000" -Cs"--fomit-frame-pointer" -Cs"--nogcse"'

echo
echo "Wrote sweep_diag/results_diag.tsv"
