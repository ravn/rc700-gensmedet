#!/usr/bin/env bash
# build_dcc_corpus.sh -- build + measure ONE compiler-comparison-corpus
# benchmark with dcc (David Lee's CP/M C compiler), run it in z88dk-ticks,
# and print a measurement tuple.  Third "friend" alongside llvm-z80 and
# zsdcc in sweep.sh.
#
# Adapted from aes256-corpus/build_dcc_aes.sh, with the macbook runcpm hook
# swapped for VirtualCpm.jar (the cpnet-z80 CP/M emulator) so it runs on
# sonnyboy too.
#
# Usage:
#   ./build_dcc_corpus.sh <bench> <size|speed>
#     <bench>        bare benchmark name (sieve, fannkuch, ...); reads
#                    ../bench_<bench>.c relative to the sweep/ workdir.
#     size | speed   dcc's only optimization knob is the dccpeep peephole
#                    pass, which makes code both smaller AND faster (it is
#                    NOT a size/speed tradeoff).  To fill the corpus's
#                    size+speed columns we map:
#                      size  = dccpeep OFF (unoptimized dcc output)
#                      speed = dccpeep ON  (optimized dcc output)
#
# Output: one TAB-separated line to stdout matching sweep.sh's measure_*
#   contract:   bin <TAB> text <TAB> tstates <TAB> verify
#   (text is always "n/a" for dcc, as for zsdcc -- different map format).
# Diagnostics go to stderr.
#
# Build model (see dcc_test_main.c for the full rationale):
#   - SINGLE TU: bench_<x>.c + dcc_test_main.c concatenated (dcc miscompiles
#     cross-unit calls).
#   - dcc -> .mac -> M80 -> dccrtlstrip -> M80 -> L80 -> .COM, the M80/L80
#     steps run under VirtualCpm.  CP/M warm-boots to 0x0000 on return, so
#     ticks stops via `-end 0` (no ED-FE trap).  Verify the 0xC000 sentinel
#     from the ticks RAM dump.
#
# VirtualCpm gotchas baked in below (learned the hard way):
#   - Needs Java 21+ (VirtualCpm.jar is class-file v65).  Override with
#     $JAVA; default `java` must be 21+.
#   - HostFileBdos maps CP/M UPPERCASE names to LOWERCASE host files, so
#     every staged file (m80.com, l80.com, *.mac) MUST be lowercase on disk.
#   - Drive mapped in-workspace via CPMDrive_A + CPMDefault=a: (no
#     ~/HostFileBdos), the same mechanism cpnos-in-c/cpnos-build uses.
set -euo pipefail

BENCH="${1:?usage: build_dcc_corpus.sh <bench> <size|speed>}"
MODE="${2:?usage: build_dcc_corpus.sh <bench> <size|speed>}"

# --- toolchain locations (macbook-style committed paths; the sonnyboy
# --- runner sed-rewrites the /Users/ravn/z80 prefixes, and overrides
# --- $JAVA to the host's Java 21). ---
DCC_DIR="${DCC_DIR:-/Users/ravn/z80/dcc}"
VCPM_JAR="${VCPM_JAR:-/Users/ravn/z80/cpnet-z80/tools/VirtualCpm.jar}"
Z88DK="${Z88DK:-/Users/ravn/z80/z88dk}"
TICKS="${TICKS:-$Z88DK/bin/z88dk-ticks}"
JAVA="${JAVA:-java}"

HERE=$(cd "$(dirname "$0")" && pwd)
SWEEP="$HERE/sweep"
mkdir -p "$SWEEP"

case "$MODE" in
    size)  USE_PEEP=0 ;;   # dccpeep OFF
    speed) USE_PEEP=1 ;;   # dccpeep ON
    *) echo "build_dcc_corpus.sh: bad mode '$MODE' (want size|speed)" >&2; exit 2 ;;
esac

SRC="$HERE/bench_${BENCH}.c"
HARNESS="$HERE/dcc_test_main.c"
[ -f "$SRC" ]     || { echo "no such bench source: $SRC" >&2; exit 2; }
[ -f "$HARNESS" ] || { echo "missing dcc harness: $HARNESS" >&2; exit 2; }

# Per-cell workdir = the CP/M drive A:.  Isolated so the size and speed
# cells (and different benches) never clash on the fixed lowercase CP/M
# filenames (main.mac/.rel/.com, rtlmin.*).
W="$SWEEP/dcc_${MODE}_${BENCH}"
rm -rf "$W"; mkdir -p "$W"

# Stage the M80/L80 toolchain + runtime under lowercase host names.
cp -f "$DCC_DIR/m80.com"    "$W/m80.com"
cp -f "$DCC_DIR/l80.com"    "$W/l80.com"
cp -f "$DCC_DIR/DCCRTL.MAC" "$W/dccrtl.mac"

# SINGLE-TU source: bench first, harness (externs + main) after.
cat "$SRC" "$HARNESS" > "$W/main.c"

crlf() { perl -0pi -e 's/\r?\n/\r\n/g' "$@"; }
vcpm() { ( cd "$W" && CPMDrive_A="$W" CPMDefault=a: \
            "$JAVA" -jar "$VCPM_JAR" "$@" </dev/null ); }

# --- compile + assemble + link, all lowercase ---
# dcc compile is non-fatal: a dcc C89-parser rejection (e.g. pi's empty
# macro, licm's cast-lvalue) must yield a COMPILE_ERROR tuple, not abort the
# sweep under set -e.  `|| true` + the missing-.mac guard mirror the zsdcc
# lane's `|| true` + missing-.bin guard.
"$DCC_DIR/dcc" "$W/main.c" -o "$W/main.mac" >&2 || true
if [ ! -s "$W/main.mac" ]; then
    printf 'FAIL\tn/a\t-\tCOMPILE_ERROR\n'
    exit 0
fi
if [ "$USE_PEEP" -eq 1 ]; then
    "$DCC_DIR/dccpeep" "$W/main.mac" "$W/_peep.mac" >&2
    mv -f "$W/_peep.mac" "$W/main.mac"
fi
crlf "$W/main.mac" "$W/dccrtl.mac"
vcpm m80 "=main.mac /X /O /Z" >&2

# Strip the RTL down to what main.mac references, assemble, then link.
"$DCC_DIR/dccrtlstrip" -r "$W/dccrtl.mac" -o "$W/rtlmin.mac" "$W/main.mac" >&2
crlf "$W/rtlmin.mac"
vcpm m80 "=rtlmin.mac /X /O /Z" >&2
# DRI LINK: dest=main, modules rtlmin+main; /N/E writes main.com and exits.
vcpm l80 "/P:100,rtlmin,main,main/N/E" >&2

if [ ! -f "$W/main.com" ]; then
    printf 'FAIL\tn/a\t-\tCOMPILE_ERROR\n'
    exit 0
fi
BIN=$(wc -c < "$W/main.com" | tr -d ' ')

# Wrap the .COM in a 64 KB ticks image: page-zero warm-boot + a tiny BDOS
# stub (so any stray BDOS call returns cleanly), .COM at 0x0100.  Identical
# to aes256-corpus/build_dcc_aes.sh.
python3 - "$W/main.com" "$W/dcc.img" <<'PY'
import sys
com, out = sys.argv[1], sys.argv[2]
mem = bytearray(65536)
mem[0x0000]=0xC3; mem[0x0001]=0x00; mem[0x0002]=0x00          # JP 0x0000 warm boot
mem[0x0005]=0xC3; mem[0x0006]=0x00; mem[0x0007]=0xDC          # JP 0xDC00 BDOS stub
mem[0xDC00]=0x79; mem[0xDC01]=0xB7; mem[0xDC02]=0xCA          # LD A,C; OR A; JP Z,
mem[0xDC03]=0x00; mem[0xDC04]=0x00; mem[0xDC05]=0xC9          # ..0x0000 ; RET
d=open(com,'rb').read(); mem[0x0100:0x0100+len(d)]=d
open(out,'wb').write(mem)
PY

# Run: start at 0x100, stop when PC hits 0x0000 (program returned -> warm
# boot), dump RAM, capture the T-state count from ticks' last output line.
TS=$(perl -e 'alarm 120; exec @ARGV' \
        "$TICKS" -pc 100 -end 0 -counter 200000000 -output "$W/dcc.ram" "$W/dcc.img" \
        2>/dev/null | tail -1)
: "${TS:=?}"

# Verify the 0xC000 sentinel from the RAM dump: match byte AND end marker.
VERIFY=$(python3 - "$W/dcc.ram" <<'PY'
import sys
ram = open(sys.argv[1], 'rb').read()
ok = len(ram) > 0xC006 and ram[0xC004] == 1 and ram[0xC006] == 0xA5
print("PASS" if ok else "FAIL")
PY
)

printf '%s\tn/a\t%s\t%s\n' "$BIN" "$TS" "$VERIFY"
