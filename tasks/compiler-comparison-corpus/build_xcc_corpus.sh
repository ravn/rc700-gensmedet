#!/usr/bin/env bash
# build_xcc_corpus.sh -- build + measure ONE compiler-comparison-corpus
# benchmark with xcc (the XYZ Suite Z80 C compiler, retro-vault/xyz), run the
# resulting CP/M .COM in z88dk-ticks, and print a measurement tuple.  Fifth
# "friend" alongside llvm-z80, zsdcc, dcc, and llvm-z88dk in sweep.sh.
#
# See XCC_ORACLE_SETUP.md for the install step (setup_xcc.sh) and the beta
# libc auto-link workaround this script bakes in.
#
# Usage:
#   ./build_xcc_corpus.sh <bench> <size|speed>
#     <bench>       bare benchmark name; reads bench_<bench>.c beside this
#                   script and concatenates the CP/M harness dcc_test_main.c.
#     size | speed  xcc opt knob:  size = -Os,  speed = -Of.
#
# Output: one TAB line matching sweep.sh's measure_* contract:
#   bin <TAB> text <TAB> tstates <TAB> {PASS|FAIL|COMPILE_ERROR}
#   (text is "n/a" -- xcc emits SDCC-dialect .rel, no clang-style .text size).
#
# Build model (identical measurement path to build_dcc_corpus.sh so the cells
# are apples-to-apples with the other .COM lanes):
#   - SINGLE TU: bench_<x>.c + dcc_test_main.c concatenated.  The harness
#     writes the 7-byte 0xC000 sentinel and returns; xcc's crt0-cpm3 routes
#     main's return through _exit = `LD C,0; JP 5` (BDOS warm boot -> PC hits
#     0x0000), so ticks stops via `-end 0` and we read the sentinel from the
#     RAM dump.
#   - xcc -c -> .rel, then xld drives the link.  BETA WORKAROUND: libc is not
#     auto-linked, so we list crt0 + object + libc.a + libruntime.a +
#     libcpm3.a explicitly (see XCC_ORACLE_SETUP.md).
set -euo pipefail

BENCH="${1:?usage: build_xcc_corpus.sh <bench> <size|speed>}"
MODE="${2:?usage: build_xcc_corpus.sh <bench> <size|speed>}"

# --- toolchain locations (macbook-style committed paths; the sonnyboy runner
# --- sed-rewrites the /Users/ravn/z80 prefixes).  XCC_PREFIX is the stable
# --- symlink setup_xcc.sh stages. ---
XCC_PREFIX="${XCC_PREFIX:-/Users/ravn/z80/xyz-eval/xcc-current}"
Z88DK="${Z88DK:-/Users/ravn/z80/z88dk}"
TICKS="${TICKS:-$Z88DK/bin/z88dk-ticks}"

XCC="$XCC_PREFIX/bin/xcc"
XLD="$XCC_PREFIX/bin/xld"
XLIB="$XCC_PREFIX/z80/lib"

HERE=$(cd "$(dirname "$0")" && pwd)
SWEEP="$HERE/sweep"
mkdir -p "$SWEEP"

case "$MODE" in
    size)  XCC_OPT=-Os ;;
    speed) XCC_OPT=-Of ;;
    *) echo "build_xcc_corpus.sh: bad mode '$MODE' (want size|speed)" >&2; exit 2 ;;
esac

if [ ! -x "$XCC" ]; then
    echo "build_xcc_corpus.sh: xcc not found at $XCC -- run setup_xcc.sh first" >&2
    printf 'FAIL\tn/a\t-\tCOMPILE_ERROR\n'
    exit 0
fi

SRC="$HERE/bench_${BENCH}.c"
HARNESS="$HERE/dcc_test_main.c"
[ -f "$SRC" ]     || { echo "no such bench source: $SRC" >&2; exit 2; }
[ -f "$HARNESS" ] || { echo "missing harness: $HARNESS" >&2; exit 2; }

W="$SWEEP/xcc_${MODE}_${BENCH}"
rm -rf "$W"; mkdir -p "$W"

# SINGLE-TU source: bench first, harness (externs + main) after.
cat "$SRC" "$HARNESS" > "$W/main.c"

# --- compile (non-fatal: a parse rejection -> COMPILE_ERROR tuple, not an
# --- aborted sweep under set -e, mirroring the dcc/zsdcc lanes) ---
"$XCC" -c "$XCC_OPT" "$W/main.c" -o "$W/main.rel" >&2 || true
if [ ! -s "$W/main.rel" ]; then
    printf 'FAIL\tn/a\t-\tCOMPILE_ERROR\n'
    exit 0
fi

# --- link a true CP/M .COM (beta libc-workaround: explicit lib list) ---
"$XLD" --mode=sdcc -nostartfiles -T "$XLIB/linker-cpm3.lk" \
    "$XLIB/crt0-cpm3.rel" "$W/main.rel" \
    "$XLIB/libc.a" "$XLIB/libruntime.a" "$XLIB/libcpm3.a" \
    --oformat=binary -o "$W/main.com" >&2 || true
if [ ! -s "$W/main.com" ]; then
    printf 'FAIL\tn/a\t-\tCOMPILE_ERROR\n'
    exit 0
fi
BIN=$(wc -c < "$W/main.com" | tr -d ' ')

# NOTE on .COM size vs the z88dk clang lanes: xcc's .COM legitimately carries
# its zero-initialised globals.  The z88dk (+cpm) lanes now keep BSS out of the
# .COM via a linker fix (cpm_crt0.asm sets __crt_org_bss = -1, so z80asm emits
# BSS as a separate binary; the CRT re-zeroes it at startup).  xcc can't do the
# same: it places zero-initialised arrays (e.g. sieve's flags[8000]) into _DATA,
# not _BSS, and crt0-cpm3.s only zeroes _BSS (its own comment: "cannot yet
# reconstruct initialized _DATA values").  So those bytes MUST ship in the file.
# This is an xcc toolchain limitation (no zero-init -> BSS split), not something
# the corpus can strip.
# Wrap the .COM in a 64 KB ticks image: page-zero warm-boot + a tiny BDOS
# stub, .COM at 0x0100.  Identical to build_dcc_corpus.sh so the tstate
# measurement path is the same for every .COM lane.
python3 - "$W/main.com" "$W/xcc.img" <<'PY'
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
        "$TICKS" -pc 100 -end 0 -counter 200000000 -output "$W/xcc.ram" "$W/xcc.img" \
        2>/dev/null | tail -1)
: "${TS:=?}"

# Verify the 0xC000 sentinel from the RAM dump: match byte AND end marker.
VERIFY=$(python3 - "$W/xcc.ram" <<'PY'
import sys
ram = open(sys.argv[1], 'rb').read()
ok = len(ram) > 0xC006 and ram[0xC004] == 1 and ram[0xC006] == 0xA5
print("PASS" if ok else "FAIL")
PY
)

printf '%s\tn/a\t%s\t%s\n' "$BIN" "$TS" "$VERIFY"
