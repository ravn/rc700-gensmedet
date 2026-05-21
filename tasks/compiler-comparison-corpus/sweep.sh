#!/usr/bin/env bash
# Compiler-comparison corpus sweep: each benchmark × (llvm-z80, zsdcc)
# at -Oz prod-like flags.  Writes machine-readable TSV + markdown
# summary.  Mirrors aes256-corpus/flag_sweep.sh's harness style.
#
# Per-benchmark each compiler writes a 7-byte sentinel at 0xC000:
#   [0..1] actual, [2..3] expected, [4] match (0/1), [5] reserved, [6] 0xA5.
#
# Verifier requires v[4]==1 (computation correct) AND v[6]==0xA5 (clean halt).
#
# Usage: ./sweep.sh                   # all benchmarks, both compilers
#        BENCH=sieve ./sweep.sh       # filter
#        ONLY=llvm-z80 ./sweep.sh     # one compiler

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
mkdir -p sweep
cd sweep

LLVM_Z80=/Users/ravn/z80/llvm-z80/build-macos
CLANG=$LLVM_Z80/bin/clang
LLDLD=$LLVM_Z80/bin/ld.lld
LLVMOBJCOPY=$LLVM_Z80/bin/llvm-objcopy
LLVMNM=$LLVM_Z80/bin/llvm-nm
Z88DK=/Users/ravn/z80/z88dk
TICKS=$Z88DK/bin/z88dk-ticks
ZCC_ENV="ZCCCFG=$Z88DK/lib/config PATH=$Z88DK/bin:$PATH"
ZCC="$Z88DK/bin/zcc"

# llvm-z80 production flags (matches aes256-corpus 09_Oz_prod_like)
LLVM_FLAGS=(-Oz -Xclang -target-feature -Xclang +static-stack
            -mllvm -disable-lsr -mllvm -disable-machine-licm
            -mllvm -disable-machine-cse
            -ffunction-sections -fdata-sections)

# zsdcc production flags (matches aes256-corpus 01_baseline_prod)
ZSDCC_FLAGS=(+z80 -compiler=sdcc -clib=sdcc_iy
             --opt-code-size -SO3
             '-Cs--sdcccall 1' '-Cs--disable-warning 296'
             '-Cs--max-allocs-per-node 25000'
             '-Cs--fomit-frame-pointer'
             -create-app)

BENCHES=(sieve fannkuch pi)
# Filtered by env-var BENCH if set
if [ -n "${BENCH:-}" ]; then BENCHES=("$BENCH"); fi
ONLY="${ONLY:-both}"

TSV="results.tsv"
printf 'bench\tcompiler\tbin\ttext\ttstates\tverify\n' > "$TSV"

[ -f reset_clang.s ] || ln -sf ../sweep/reset_clang.s reset_clang.s 2>/dev/null || true
[ -f clang.ld ] || ln -sf ../sweep/clang.ld clang.ld 2>/dev/null || true

run_llvm_z80() {
  local bench=$1
  local src=../bench_${bench}.c
  local prefix=llvm_z80_${bench}
  local main=../test_main.c
  rm -f ${prefix}_*.o ${prefix}.elf ${prefix}.bin ${prefix}.filled.bin ${prefix}.ram 2>/dev/null || true

  $CLANG --target=z80 -nostdlib -ffreestanding -std=c89 -Wno-deprecated-non-prototype \
    "${LLVM_FLAGS[@]}" -c ../sweep/reset_clang.s -o ${prefix}_reset.o
  $CLANG --target=z80 -nostdlib -ffreestanding -std=c89 -Wno-deprecated-non-prototype \
    "${LLVM_FLAGS[@]}" -c "$src" -o ${prefix}_bench.o
  $CLANG --target=z80 -nostdlib -ffreestanding -std=c89 -Wno-deprecated-non-prototype \
    "${LLVM_FLAGS[@]}" -c "$main" -o ${prefix}_main.o
  $LLDLD -T ../sweep/clang.ld --gc-sections -o ${prefix}.elf \
    ${prefix}_reset.o ${prefix}_bench.o ${prefix}_main.o \
    $LLVM_Z80/lib/z80/z80_rt.a
  $LLVMOBJCOPY -O binary ${prefix}.elf ${prefix}.bin

  local bin text done_addr tstates verify
  bin=$(wc -c < ${prefix}.bin | tr -d ' ')
  text=$($LLVMNM --print-size --size-sort ${prefix}_bench.o 2>/dev/null | \
    python3 -c "import sys; t=sum(int(p[1],16) for p in (l.split() for l in sys.stdin) if len(p)>=4 and p[2] in 'tT'); print(t)")
  done_addr=$($LLVMNM ${prefix}.elf | awk '$3=="_done"{print "0x" $1; exit}')
  python3 ../fill_with_jp_done.py ${prefix}.bin ${prefix}.filled.bin "$done_addr"
  tstates=$(perl -e 'alarm 90; exec @ARGV' \
    $TICKS -mz80 -end $done_addr -counter 200000000 \
    -output ${prefix}.ram ${prefix}.filled.bin 2>&1 | tail -1 || true)
  verify="?"
  if [ -f ${prefix}.ram ]; then
    verify=$(python3 -c "d=open('${prefix}.ram','rb').read(); v=d[0xC000:0xC007]; \
      r=v[0]|(v[1]<<8); e=v[2]|(v[3]<<8); \
      print('PASS' if (v[4]==1 and v[6]==0xA5) else f'FAIL(r={r} e={e} v4={v[4]} v6={v[6]:02x})')")
  fi
  printf '%s\tllvm-z80\t%s\t%s\t%s\t%s\n' "$bench" "$bin" "$text" "${tstates:-?}" "$verify" >> "$TSV"
  printf '%-20s llvm-z80    bin=%5s text=%5s ts=%10s %s\n' "$bench" "$bin" "$text" "$tstates" "$verify"
}

run_zsdcc() {
  local bench=$1
  local src=../bench_${bench}.c
  local prefix=zsdcc_${bench}
  local main=../test_main.c
  rm -f ${prefix}* 2>/dev/null || true

  env $ZCC_ENV $ZCC "${ZSDCC_FLAGS[@]}" -o $prefix "$src" "$main" >/dev/null 2>&1 || true
  if [ ! -f ${prefix}.bin ]; then
    printf '%s\tzsdcc\tFAIL\t-\t-\tCOMPILE_ERROR\n' "$bench" >> "$TSV"
    printf '%-20s zsdcc       COMPILE_ERROR\n' "$bench"
    return
  fi

  local bin text tstates verify done_addr
  bin=$(wc -c < ${prefix}.bin | tr -d ' ')
  # text size: not directly comparable since SDCC link is different;
  # use total bin size + total .lis-derived breakdown later.
  text="n/a"
  # _done is the halt label inside our test_main; need addr from sdcc map.
  # zcc emits a .map file; grep for the symbol.
  done_addr=$(awk '/_main|main_/{print}' ${prefix}.map 2>/dev/null | head -1 || echo "")
  # For zsdcc the program runs until HALT in CRT.  ticks counts until -counter limit
  # OR -end matches.  We use _exit / __EXIT or just rely on counter timeout.
  tstates=$(perl -e 'alarm 90; exec @ARGV' \
    $TICKS -mz80 -counter 200000000 \
    -output ${prefix}.ram ${prefix}.bin 2>&1 | tail -1 || true)
  verify="?"
  if [ -f ${prefix}.ram ]; then
    verify=$(python3 -c "d=open('${prefix}.ram','rb').read(); v=d[0xC000:0xC007]; \
      r=v[0]|(v[1]<<8); e=v[2]|(v[3]<<8); \
      print('PASS' if (v[4]==1 and v[6]==0xA5) else f'FAIL(r={r} e={e} v4={v[4]} v6={v[6]:02x})')")
  fi
  printf '%s\tzsdcc\t%s\t%s\t%s\t%s\n' "$bench" "$bin" "$text" "${tstates:-?}" "$verify" >> "$TSV"
  printf '%-20s zsdcc       bin=%5s ts=%10s %s\n' "$bench" "$bin" "$tstates" "$verify"
}

echo "Bench                  Compiler    bin     text       ts        verify"
echo "---------------------- --------- ------- -------- ---------- ----------"
for b in "${BENCHES[@]}"; do
  if [ "$ONLY" = "both" ] || [ "$ONLY" = "llvm-z80" ]; then
    run_llvm_z80 "$b"
  fi
  if [ "$ONLY" = "both" ] || [ "$ONLY" = "zsdcc" ]; then
    run_zsdcc "$b"
  fi
done

echo
echo "Wrote sweep/$TSV"
