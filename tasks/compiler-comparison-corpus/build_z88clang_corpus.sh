#!/usr/bin/env bash
# build_z88clang_corpus.sh -- build + measure ONE compiler-comparison-corpus
# benchmark with ravn/llvm-z80 clang linked against z88dk's CP/M runtime,
# driven by z88dk's own `zcc +cpm -compiler=llvmz80`.  This is the FOURTH
# "friend" in sweep.sh, alongside the freestanding llvm-z80 cell, zsdcc and
# dcc.
#
# The clang<->z88dk bridge (copt asm-dialect rules + label fixer + extern
# header) now lives INSIDE z88dk as `-compiler=llvmz80` (z88dk commit
# "zcc: add -compiler=llvmz80"), so this runner is just an ordinary zcc
# invocation -- no external copt/perl/awk pipeline here anymore.  Proved
# 2026-07-05: byte-identical .COM and t-states to the earlier standalone
# bridge (sieve 14237 B / 3803610 ts either way).
#
# Pipeline:
#   cat bench_<x>.c dcc_test_main.c            (single TU; harness concat)
#     + rt_helpers.c                           (32-bit __mulsi3/__udivmodsi4;
#                                                LLVM libcalls z88dk clib lacks)
#     -> zcc +cpm -compiler=llvmz80 <opt> ... -create-app   (clang + clib)
#     -> 64 KB ticks image + z88dk-ticks       (run; stop at warm-boot 0x0000)
#     -> verify 0xC000 sentinel from RAM dump.
#
# opt knob (mirrors the llvm-z80 cell so the objective is the only variable):
#   size  = --opt-code-size (zcc -> clang -Oz)   speed = default (clang -O2)
#
# Output: one TAB-separated line matching sweep.sh's measure_* contract:
#   bin <TAB> text <TAB> tstates <TAB> {PASS|FAIL|COMPILE_ERROR}
# (text is "n/a"; the .COM bundles the z88dk RTL so text is not comparable
#  to the freestanding llvm-z80 cell, same caveat as dcc.)
set -euo pipefail

BENCH="${1:?usage: build_z88clang_corpus.sh <bench> <size|speed>}"
MODE="${2:?usage: build_z88clang_corpus.sh <bench> <size|speed>}"

HERE=$(cd "$(dirname "$0")" && pwd)
Z88DK="${Z88DK:-/Users/ravn/z80/z88dk}"
TICKS="${TICKS:-$Z88DK/bin/z88dk-ticks}"
ZCC="${ZCC:-$Z88DK/bin/zcc}"
export PATH="$Z88DK/bin:$PATH"
export ZCCCFG="${ZCCCFG:-$Z88DK/lib/config}"

case "$MODE" in
  size)  OPTFLAG=--opt-code-size ;;
  speed) OPTFLAG= ;;                # default in the llvmz80 branch is -O2
  *) echo "bad mode '$MODE' (want size|speed)" >&2; exit 2 ;;
esac

SRC="$HERE/bench_${BENCH}.c"
HARNESS="$HERE/dcc_test_main.c"
RTSRC="$HERE/rt_helpers.c"
[ -f "$SRC" ]     || { echo "no such bench: $SRC" >&2; exit 2; }
[ -f "$HARNESS" ] || { echo "missing harness: $HARNESS" >&2; exit 2; }

W="$HERE/sweep/z88clang_${MODE}_${BENCH}"
rm -rf "$W"; mkdir -p "$W"; cd "$W"

# Single TU: bench + harness concatenated (dcc harness contract; kept so the
# 4th oracle uses the exact same source shape as the dcc cell).  rt_helpers.c
# is a second source file zcc compiles + links through the same llvmz80 path.
cat "$SRC" "$HARNESS" > tu.c
cp "$RTSRC" rt_helpers.c

if ! "$ZCC" +cpm -compiler=llvmz80 $OPTFLAG tu.c rt_helpers.c \
        -o prog -create-app >zcc.log 2>&1; then
  echo -e "FAIL\tn/a\t-\tCOMPILE_ERROR"; exit 0
fi
COM=$(ls -1 PROG.COM prog.com prog *.COM 2>/dev/null | head -1)
[ -n "$COM" ] || { echo -e "FAIL\tn/a\t-\tCOMPILE_ERROR"; exit 0; }

# Note: the .COM no longer carries the uninitialised BSS region.  This is a
# z88dk linker-level fix (lib/target/cpm/classic/cpm_crt0.asm now defaults
# __crt_org_bss = -1, so z80asm emits BSS as a separate binary that appmake
# leaves out of the .COM).  The CRT still zeroes BSS at startup, so the leaner
# .COM is byte-for-byte correct -- no post-processing needed here.
BIN=$(wc -c < "$COM" | tr -d ' ')

# wrap .COM in 64 KB image: JP0 warm-boot + tiny BDOS stub, run under ticks.
python3 - "$COM" dcc.img <<'PY'
import sys
com,out=sys.argv[1],sys.argv[2]
mem=bytearray(65536)
mem[0]=0xC3;mem[1]=0;mem[2]=0; mem[5]=0xC3;mem[6]=0;mem[7]=0xDC
mem[0xDC00]=0x79;mem[0xDC01]=0xB7;mem[0xDC02]=0xCA;mem[0xDC03]=0;mem[0xDC04]=0;mem[0xDC05]=0xC9
d=open(com,'rb').read(); mem[0x100:0x100+len(d)]=d; open(out,'wb').write(mem)
PY

# counter 3e9 / 300s alarm: pi's naive 32-bit helpers run to ~256M tstates.
TS=$(perl -e 'alarm 300; exec @ARGV' \
      "$TICKS" -pc 100 -end 0 -counter 3000000000 -output dcc.ram dcc.img \
      2>/dev/null | tail -1)
: "${TS:=?}"

VERIFY=$(python3 - dcc.ram <<'PY'
import sys
ram=open(sys.argv[1],'rb').read()
ok = len(ram) > 0xC006 and ram[0xC004] == 1 and ram[0xC006] == 0xA5
print("PASS" if ok else "FAIL")
PY
)
printf '%s\tn/a\t%s\t%s\n' "$BIN" "$TS" "$VERIFY"
