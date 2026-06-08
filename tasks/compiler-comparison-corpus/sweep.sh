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

# llvm-z80 production flags (matches aes256-corpus 09_Oz_prod_like).
# NOTE the in-tree disablePass(LICM/CSE) is already in effect via the
# Z80 backend — passing `-mllvm -disable-machine-licm/cse` here is
# belt-and-suspenders.  The investigation toggles (#23) use
# `-mllvm -z80-enable-licm` / `-mllvm -z80-enable-cse` which override
# the in-tree disable.  CLANG_EXTRA env var injects extra flags into
# every cell; used by the per-investigation wrapper scripts.
LLVM_FLAGS=(-Oz -Xclang -target-feature -Xclang +static-stack
            -mllvm -disable-lsr
            -ffunction-sections -fdata-sections)
# Historical belt-and-suspenders flag `-mllvm -disable-machine-licm/cse`
# was here; removed 2026-06-08 because the Z80 backend's in-tree
# disablePass(LICM/CSE) already covers it (Z80PassConfig), and the
# explicit flag would defeat the `-mllvm -z80-enable-licm/-cse`
# investigation toggle.
if [ -n "${CLANG_EXTRA:-}" ]; then
  # split on whitespace into array elements
  read -r -a CLANG_EXTRA_ARR <<< "$CLANG_EXTRA"
  LLVM_FLAGS+=("${CLANG_EXTRA_ARR[@]}")
fi
# Optional cell-label suffix so cells with different flag sets don't
# clash on prefix names in sweep/.  Default empty.
CELL_TAG="${CELL_TAG:-}"

# zsdcc production flags (matches aes256-corpus 01_baseline_prod)
ZSDCC_FLAGS=(+z80 -compiler=sdcc -clib=sdcc_iy
             --opt-code-size -SO3
             '-Cs--sdcccall 1' '-Cs--disable-warning 296'
             '-Cs--max-allocs-per-node 25000'
             '-Cs--fomit-frame-pointer'
             -create-app)

BENCHES=(sieve fannkuch pi word_fill licm_pessimize)
# Filtered by env-var BENCH if set
if [ -n "${BENCH:-}" ]; then BENCHES=("$BENCH"); fi
ONLY="${ONLY:-both}"

# Known-failing (bench, compiler) cells -- pre-existing, documented, deferred
# upstream investigation.  See tasks/zsdcc-bench-divergence-2026-06-08.md for
# the per-bench writeup (clang return vs zsdcc return, hypothesis, repro
# strategy, upstream filing prep).  Convention: FAIL -> XFAIL (silent), PASS
# on a known-failing cell -> XPASS (loud -- upstream may have landed a fix).
EXPECTED_FAIL=" fannkuch:zsdcc pi:zsdcc "
is_expected_fail() {
  # $1=bench $2=compiler
  case "$EXPECTED_FAIL" in *" $1:$2 "*) return 0 ;; *) return 1 ;; esac
}
classify_verify() {
  # $1=bench $2=compiler $3=rc (ticks exit code)
  local b=$1 c=$2 rc=$3
  if is_expected_fail "$b" "$c"; then
    case "$rc" in
      0) printf 'XPASS(unexpected_pass)' ;;
      *) printf 'XFAIL(exit=%s)' "$rc" ;;
    esac
  else
    case "$rc" in
      0) printf 'PASS' ;;
      *) printf 'FAIL(exit=%s)' "$rc" ;;
    esac
  fi
}

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

  local bin text tstates verify rc out
  bin=$(wc -c < ${prefix}.bin | tr -d ' ')
  text=$($LLVMNM --print-size --size-sort ${prefix}_bench.o 2>/dev/null | \
    python3 -c "import sys; t=sum(int(p[1],16) for p in (l.split() for l in sys.stdin) if len(p)>=4 and p[2] in 'tT'); print(t)")
  # test_main.c traps to ticks via ED FE after writing the sentinel; ticks
  # prints "Ticks: <N>" to stdout and exits with L (Unix: 0=PASS, 1=FAIL).
  # No -end / -output needed.  -counter is a safety net.
  # `|| rc=$?` shields set -e from non-zero (FAIL) exits.
  rc=0
  out=$(perl -e 'alarm 90; exec @ARGV' \
    $TICKS -mz80 -counter 200000000 ${prefix}.bin 2>&1) || rc=$?
  # awk without exit (don't SIGPIPE the upstream printf under pipefail).
  tstates=$(printf '%s\n' "$out" | awk '/^Ticks:/{ts=$2} END{print ts}')
  verify=$(classify_verify "$bench" llvm-z80 "$rc")
  : "${tstates:=?}"
  printf '%s\tllvm-z80\t%s\t%s\t%s\t%s\n' "$bench" "$bin" "$text" "$tstates" "$verify" >> "$TSV"
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

  local bin text tstates verify rc out
  bin=$(wc -c < ${prefix}.bin | tr -d ' ')
  # text size not extracted for SDCC (different map format); see word_fill
  # baseline doc for the manual counting approach when needed.
  text="n/a"
  # test_main.c traps to ticks via ED FE; same protocol as clang path.
  rc=0
  out=$(perl -e 'alarm 90; exec @ARGV' \
    $TICKS -mz80 -counter 200000000 ${prefix}.bin 2>&1) || rc=$?
  tstates=$(printf '%s\n' "$out" | awk '/^Ticks:/{ts=$2} END{print ts}')
  verify=$(classify_verify "$bench" zsdcc "$rc")
  : "${tstates:=?}"
  printf '%s\tzsdcc\t%s\t%s\t%s\t%s\n' "$bench" "$bin" "$text" "$tstates" "$verify" >> "$TSV"
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
