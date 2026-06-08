#!/usr/bin/env bash
# ravn/llvm-z80#177 Task 3 / #23 investigation: A/B LICM/CSE on-vs-off
# at -O2 and -Oz.
#
# 2026-06-08: replaced the broken `-mllvm -disable-machine-licm/-cse`
# OFF-cell scheme (which was degenerate because the Z80 backend's in-tree
# disablePass is unconditional) with the new `-mllvm -z80-enable-licm`
# / `-mllvm -z80-enable-cse` flags that LIFT the in-tree disable.
# OFF cells now use no extra flag (the in-tree disable is the OFF state);
# ON cells use the enable flag(s).
#
# WARNING: the O2_LICM_ON cell will MISCOMPILE (#198, MachineCSE alone
# corrupts AES at -O2 -- verifier FAIL).  Its tstates/size are MEANINGLESS;
# only the verify column matters there.
set -uo pipefail
CLANG=/Users/ravn/z80/llvm-z80/build-macos/bin/clang
LLDLD=/Users/ravn/z80/llvm-z80/build-macos/bin/ld.lld
LLVMNM=/Users/ravn/z80/llvm-z80/build-macos/bin/llvm-nm
LLVMOBJCOPY=/Users/ravn/z80/llvm-z80/build-macos/bin/llvm-objcopy
TICKS=/Users/ravn/z80/z88dk/bin/z88dk-ticks
HERE=$(cd "$(dirname "$0")" && pwd); cd "$HERE/sweep"
AES_SRC=../aes256.c
BASE="-Xclang -target-feature -Xclang +static-stack -mllvm -disable-lsr -ffunction-sections -fdata-sections"
# OFF state = default (in-tree disablePass active).  ON state = lift the
# in-tree disable.  Both `-z80-enable-licm` and `-z80-enable-cse` so the
# A/B isolates the combined LICM+CSE workaround as a single signal.
LICMON="-mllvm -z80-enable-licm -mllvm -z80-enable-cse"

bm() {
  local label=$1; shift; local cflags="$*"; local p="t3_${label}"
  $CLANG --target=z80 -nostdlib -ffreestanding -std=c89 -Wno-deprecated-non-prototype $cflags -c reset_clang.s -o ${p}_reset.o 2>/dev/null
  $CLANG --target=z80 -nostdlib -ffreestanding -std=c89 -Wno-deprecated-non-prototype $cflags -c "$AES_SRC" -o ${p}_aes.o 2>/dev/null
  $CLANG --target=z80 -nostdlib -ffreestanding -std=c89 -Wno-deprecated-non-prototype $cflags -c ../test_main.c -o ${p}_main.o 2>/dev/null
  $LLDLD -T clang.ld --gc-sections -o ${p}.elf ${p}_reset.o ${p}_aes.o ${p}_main.o 2>/dev/null
  $LLVMOBJCOPY -O binary ${p}.elf ${p}.bin
  local bin_size aes_text done_addr tstates verify
  bin_size=$(wc -c < ${p}.bin | tr -d ' ')
  aes_text=$($LLVMNM --print-size --size-sort ${p}_aes.o 2>/dev/null | python3 -c "import sys; print(sum(int(x[1],16) for x in (l.split() for l in sys.stdin) if len(x)>=4 and x[2] in 'tT'))")
  done_addr=$($LLVMNM ${p}.elf | awk '$3=="_done"{print "0x" $1; exit}')
  python3 ../fill_with_jp_done.py ${p}.bin ${p}.filled.bin "$done_addr"
  tstates=$(perl -e 'alarm 90; exec @ARGV' $TICKS -mz80 -end $done_addr -counter 100000000 -output ${p}.ram ${p}.filled.bin 2>&1 | tail -1 || true)
  if [ ! -f ${p}.ram ]; then tstates="TIMEOUT"; verify="TIMEOUT"; else
    verify=$(python3 -c "d=open('${p}.ram','rb').read(); v=d[0xC000:0xC023]; print('PASS' if v[16]==1 and v[33]==1 and v[34]==0xA5 else 'FAIL')"); fi
  printf '%-22s aes_text=%5s bin=%5s tstates=%11s %s\n' "$label" "$aes_text" "$bin_size" "$tstates" "$verify"
}
echo "Config                  aes_text   bin     tstates    verify"
echo "----------------------- -------- ------ ----------- ------"
bm "Oz_LICM_OFF" -Oz $BASE
bm "Oz_LICM_ON"  -Oz $BASE $LICMON
bm "O2_LICM_OFF" -O2 $BASE
bm "O2_LICM_ON"  -O2 $BASE $LICMON     # MISCOMPILE expected — #198 (CSE)
