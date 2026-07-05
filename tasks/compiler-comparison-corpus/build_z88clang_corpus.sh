#!/usr/bin/env bash
# build_z88clang_corpus.sh -- build + measure ONE compiler-comparison-corpus
# benchmark with ravn/llvm-z80 clang linked against z88dk's CP/M runtime
# (crt0 + clib), via the copt bridge.  This is the FOURTH "friend" in
# sweep.sh, alongside the freestanding llvm-z80 cell, zsdcc and dcc.
#
# Pipeline (proved 2026-07-05, all five benches PASS):
#   cat bench_<x>.c dcc_test_main.c            (single TU; harness concat)
#     -> clang --target=z80 <opt> -ffreestanding -std=c89 -S   (our backend)
#     -> z88dk-copt llvmz80_rules.1            (asm-dialect -> z80asm SECTION)
#     -> fixlabels.pl                          (.LBB0_4 / L_.str dot labels)
#     -> awk filter                            (extern GLOBAL header; drop
#                                               .local; hoist .comm -> bss)
#     -> zcc +cpm prog.asm rt.asm -create-app  (z88dk crt0 + clib link)
#     -> 64 KB ticks image + z88dk-ticks       (run; stop at warm-boot 0x0000)
#     -> verify 0xC000 sentinel from RAM dump.
#
# rt.asm = rt_helpers.c (32-bit __mulsi3/__udivmodsi4) compiled through the
# SAME bridge so the libcall ABI matches; z88dk's clib lacks these.  This is
# the "hybrid runtime" (z88dk = libc, our compiler-rt = ABI builtins).
#
# opt knob (mirrors the llvm-z80 cell so the objective is the only variable):
#   size  = clang -Oz      speed = clang -O2
#
# Output: one TAB-separated line matching sweep.sh's measure_* contract:
#   bin <TAB> text <TAB> tstates <TAB> {PASS|FAIL|COMPILE_ERROR}
# (text is "n/a"; the .COM bundles the z88dk RTL so text is not comparable
#  to the freestanding llvm-z80 cell, same caveat as dcc.)
set -euo pipefail

BENCH="${1:?usage: build_z88clang_corpus.sh <bench> <size|speed>}"
MODE="${2:?usage: build_z88clang_corpus.sh <bench> <size|speed>}"

HERE=$(cd "$(dirname "$0")" && pwd)
LLVM_Z80="${LLVM_Z80:-/Users/ravn/z80/llvm-z80/build-macos}"
CLANG="${CLANG:-$LLVM_Z80/bin/clang}"
Z88DK="${Z88DK:-/Users/ravn/z80/z88dk}"
TICKS="${TICKS:-$Z88DK/bin/z88dk-ticks}"
RULES="$HERE/llvmz80_rules.1"
FIX="$HERE/fixlabels.pl"
RTSRC="$HERE/rt_helpers.c"
export PATH="$Z88DK/bin:$PATH"
export ZCCCFG="$Z88DK/lib/config"

case "$MODE" in
  size)  OPT=-Oz ;;
  speed) OPT=-O2 ;;
  *) echo "bad mode '$MODE' (want size|speed)" >&2; exit 2 ;;
esac

SRC="$HERE/bench_${BENCH}.c"
HARNESS="$HERE/dcc_test_main.c"
[ -f "$SRC" ]     || { echo "no such bench: $SRC" >&2; exit 2; }
[ -f "$HARNESS" ] || { echo "missing harness: $HARNESS" >&2; exit 2; }

W="$HERE/sweep/z88clang_${MODE}_${BENCH}"
rm -rf "$W"; mkdir -p "$W"; cd "$W"

# clang C -> z80asm (copt bridge + label fix + .local/.comm + extern header)
translate() { # <src.c> <out.asm>
  local src=$1 out=$2 base=${2%.asm}
  "$CLANG" --target=z80 "$OPT" -ffreestanding -std=c89 \
      -Wno-deprecated-non-prototype -S "$src" -o "${base}.s"
  z88dk-copt "$RULES" < "${base}.s" 2>/dev/null | perl "$FIX" > "${base}.body"
  awk '
    /^[ \t]*\.local[ \t]/ { next }
    /^[ \t]*\.comm[ \t]/ { split($2,c,","); cn[++nc]=c[1]; cs[nc]=c[2]; def[c[1]]=1; next }
    /^[A-Za-z_.][A-Za-z0-9_.$]*:/ { d=$0; sub(/:.*/,"",d); def[d]=1 }
    { L[NR]=$0; n=split($0,t,/[ \t,()+\-]+/); for(i=1;i<=n;i++) if(t[i]~/^_[A-Za-z0-9_]+$/||t[i]~/^L__[A-Za-z0-9_]+$/) r[t[i]]=1 }
    END{
      for(s in r) if(!(s in def)) print "\tGLOBAL\t" s;
      for(i=1;i<=NR;i++) print L[i];
      if(nc>0){ print "\tSECTION bss_compiler"; for(i=1;i<=nc;i++){ print cn[i] ":"; print "\tDEFS " cs[i] } }
    }' "${base}.body" | grep -v '__do_zero_bss' | grep -v 'Declaring this symbol' > "$out"
}

cat "$SRC" "$HARNESS" > tu.c
if ! translate tu.c prog.asm 2>trans.err; then
  echo -e "FAIL\tn/a\t-\tCOMPILE_ERROR"; exit 0
fi
translate "$RTSRC" rt.asm 2>/dev/null || true

if ! zcc +cpm prog.asm rt.asm -o prog -create-app 2>link.err; then
  echo -e "FAIL\tn/a\t-\tCOMPILE_ERROR"; exit 0
fi
COM=$(ls -1 *.COM prog.com 2>/dev/null | head -1)
[ -n "$COM" ] || { echo -e "FAIL\tn/a\t-\tCOMPILE_ERROR"; exit 0; }
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
