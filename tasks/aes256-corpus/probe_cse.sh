#!/usr/bin/env bash
set -uo pipefail
CLANG=/Users/ravn/z80/llvm-z80/build-macos/bin/clang
LLDLD=/Users/ravn/z80/llvm-z80/build-macos/bin/ld.lld
LLVMNM=/Users/ravn/z80/llvm-z80/build-macos/bin/llvm-nm
LLVMOBJCOPY=/Users/ravn/z80/llvm-z80/build-macos/bin/llvm-objcopy
TICKS=/Users/ravn/z80/z88dk/bin/z88dk-ticks
HERE=$(cd "$(dirname "$0")" && pwd); cd "$HERE/sweep"
BASE=(--target=z80 -nostdlib -ffreestanding -std=c89 -Wno-deprecated-non-prototype \
  -Oz -Xclang -target-feature -Xclang +static-stack -mllvm -disable-lsr \
  -ffunction-sections -fdata-sections)

run() {
  local lbl="$1"; shift
  rm -f m_${lbl}_*.o m_${lbl}.elf m_${lbl}.bin m_${lbl}.filled.bin 2>/dev/null
  $CLANG "${BASE[@]}" "$@" -c reset_clang.s -o m_${lbl}_reset.o
  $CLANG "${BASE[@]}" "$@" -c ../aes256.c -o m_${lbl}_aes.o
  $CLANG "${BASE[@]}" "$@" -c ../test_main.c -o m_${lbl}_main.o
  $LLDLD -T clang.ld --gc-sections -o m_${lbl}.elf m_${lbl}_reset.o m_${lbl}_aes.o m_${lbl}_main.o
  $LLVMOBJCOPY -O binary m_${lbl}.elf m_${lbl}.bin
  local bs dn ts text
  bs=$(wc -c < m_${lbl}.bin | tr -d ' ')
  text=$($LLVMNM --print-size --size-sort m_${lbl}_aes.o 2>/dev/null | python3 -c "import sys; print(sum(int(p[1],16) for p in (l.split() for l in sys.stdin) if len(p)>=4 and p[2] in 'tT'))")
  dn=$($LLVMNM m_${lbl}.elf | awk '$3=="_done"{print "0x"$1;exit}')
  python3 ../fill_with_jp_done.py m_${lbl}.bin m_${lbl}.filled.bin "$dn" >/dev/null 2>&1
  ts=$($TICKS -mz80 -counter 200000000 -end "$dn" m_${lbl}.filled.bin 2>&1 | awk '/^[0-9]+$/{print}')
  printf '  %-26s aes_text=%5d  bin=%5d  ts=%s\n' "$lbl" "$text" "$bs" "$ts"
}

run default_both_on
run licm_only_cse_off -mllvm -z80-enable-cse=false
run both_off -mllvm -z80-enable-licm=false -mllvm -z80-enable-cse=false
