#!/usr/bin/env bash
# build_ez80clang_corpus.sh -- build + measure ONE compiler-comparison-corpus
# benchmark with CEdev's ez80-clang (CE-Programming/llvm-project, a SelectionDAG
# eZ80 LLVM fork -- distinct from ravn/llvm-z80's GlobalISel backend) driven by
# z88dk's own `zcc +cpm -compiler=ez80clang`.  This is the SIXTH "friend" in
# sweep.sh, alongside llvm-z80 (freestanding), zsdcc, dcc, llvm-z88dk and xcc.
#
# ez80-clang is NOT built by z88dk: per the z88dk wiki (Clang-support) you copy
# CEdev/bin/ez80-clang out of a CE-Programming/toolchain release into z88dk/bin.
# We stage it at CEDEV_PREFIX and symlink it into $Z88DK/bin.  Setup +
# the two clang_rules.1 fixes CEdev v15.0 needs: EZ80CLANG_ORACLE_SETUP.md.
#
# Pipeline (mirrors the llvm-z88dk lane so opt level is the only variable):
#   cat bench_<x>.c dcc_test_main.c            (single TU; harness concat)
#     -> zcc +cpm -compiler=ez80clang <opt> ... -create-app  (clang + clib)
#     -> 64 KB ticks image + z88dk-ticks       (run; stop at warm-boot 0x0000)
#     -> verify 0xC000 sentinel from RAM dump.
#
# opt knob:  size = --opt-code-size (-> clang -Oz)   speed = default (-> -O3)
#
# NOTE: ez80-clang does NOT link our LLVM-named rt_helpers.c (__mulsi3 /
# __udivmodsi4); it emits CE-named 32-bit libcalls (__ldivu / __llmulu /
# __llshru) that z88dk's clib does not provide.  Any 32-bit-heavy bench (pi)
# therefore fails to link -- reported COMPILE_ERROR, gated XFAIL in sweep.sh.
#
# Output: one TAB-separated line matching sweep.sh's measure_* contract:
#   bin <TAB> text <TAB> tstates <TAB> {PASS|FAIL|COMPILE_ERROR}
# (text is "n/a"; the .COM bundles the z88dk RTL, same caveat as dcc/z88clang.)
set -euo pipefail

BENCH="${1:?usage: build_ez80clang_corpus.sh <bench> <size|speed>}"
MODE="${2:?usage: build_ez80clang_corpus.sh <bench> <size|speed>}"

HERE=$(cd "$(dirname "$0")" && pwd)
Z88DK="${Z88DK:-/Users/ravn/z80/z88dk}"
TICKS="${TICKS:-$Z88DK/bin/z88dk-ticks}"
ZCC="${ZCC:-$Z88DK/bin/zcc}"
export PATH="$Z88DK/bin:$PATH"
export ZCCCFG="${ZCCCFG:-$Z88DK/lib/config}"

case "$MODE" in
  size)  OPTFLAG=--opt-code-size ;;
  speed) OPTFLAG= ;;                # default in the ez80clang branch is -O3
  *) echo "bad mode '$MODE' (want size|speed)" >&2; exit 2 ;;
esac

# Workaround for CE-Programming/llvm-project#50 (see rc700-gensmedet#124).
# ez80-clang miscompiles at -O1/-O2/-O3 (-triple z80): the IX frame-pointer
# register is left allocatable, so a spilled value handed IX corrupts every
# (ix-N) frame slot -> pi/sieve/fannkuch hang or return garbage.  Codegen is
# correct at -O0/-Os/-Oz (IX reserved: -O0 via hasStackObjects, -Os/-Oz via
# hasOptSize).  BUT -Os/-Oz emit `call __frameset`, a CE runtime prologue thunk
# z88dk's clang clib does not provide (undefined-symbol link error), so the only
# level that both LINKS and is correct here is -O0.  zcc hardwires
# `-cc1 ... -S -O3` for ez80clang regardless of --opt-code-size (zcc.c:3424);
# `-Cg-O0` appends a trailing -O0 that clang -cc1 honours over the earlier -O3.
# Applied only to the affected benches so the correct-at-O3 cells (word_fill,
# licm_pessimize) keep their optimized -O3 datapoint.
# NOTE: for these three the datapoint is therefore UNOPTIMIZED (-O0) in both
# modes -- valid/correct but not size- or speed-representative -- until the
# upstream fix lands (then -O3 becomes usable) or z88dk gains __frameset (then
# -Os/-Oz become usable).
case "$BENCH" in
  pi|sieve|fannkuch) OPTFLAG="$OPTFLAG -Cg-O0" ;;
esac

SRC="$HERE/bench_${BENCH}.c"
HARNESS="$HERE/dcc_test_main.c"
[ -f "$SRC" ]     || { echo "no such bench: $SRC" >&2; exit 2; }
[ -f "$HARNESS" ] || { echo "missing harness: $HARNESS" >&2; exit 2; }

command -v ez80-clang >/dev/null 2>&1 || {
  echo -e "FAIL\tn/a\t-\tCOMPILE_ERROR" ; exit 0 ; }   # ez80-clang not staged

W="$HERE/sweep/ez80clang_${MODE}_${BENCH}"
rm -rf "$W"; mkdir -p "$W"; cd "$W"

cat "$SRC" "$HARNESS" > tu.c

if ! "$ZCC" +cpm -compiler=ez80clang $OPTFLAG tu.c \
        -o prog -create-app >zcc.log 2>&1; then
  echo -e "FAIL\tn/a\t-\tCOMPILE_ERROR"; exit 0
fi
COM=$(ls -1 PROG.COM prog.com prog *.COM 2>/dev/null | head -1)
[ -n "$COM" ] || { echo -e "FAIL\tn/a\t-\tCOMPILE_ERROR"; exit 0; }
BIN=$(wc -c < "$COM" | tr -d ' ')

# wrap .COM in 64 KB image: JP0 warm-boot + tiny BDOS stub, run under ticks.
python3 - "$COM" ez.img <<'PY'
import sys
com,out=sys.argv[1],sys.argv[2]
mem=bytearray(65536)
mem[0]=0xC3;mem[1]=0;mem[2]=0; mem[5]=0xC3;mem[6]=0;mem[7]=0xDC
mem[0xDC00]=0x79;mem[0xDC01]=0xB7;mem[0xDC02]=0xCA;mem[0xDC03]=0;mem[0xDC04]=0;mem[0xDC05]=0xC9
d=open(com,'rb').read(); mem[0x100:0x100+len(d)]=d; open(out,'wb').write(mem)
PY

# counter 3e9 / 300s alarm: matches the z88clang lane budget.
TS=$(perl -e 'alarm 300; exec @ARGV' \
      "$TICKS" -pc 100 -end 0 -counter 3000000000 -output ez.ram ez.img \
      2>/dev/null | tail -1)
: "${TS:=?}"

VERIFY=$(python3 - ez.ram <<'PY'
import sys
ram=open(sys.argv[1],'rb').read()
ok = len(ram) > 0xC006 and ram[0xC004] == 1 and ram[0xC006] == 0xA5
print("PASS" if ok else "FAIL")
PY
)
printf '%s\tn/a\t%s\t%s\n' "$BIN" "$TS" "$VERIFY"
