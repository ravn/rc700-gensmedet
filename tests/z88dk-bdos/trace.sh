#!/usr/bin/env bash
# trace.sh -- build a z88dk CP/M program, run it on the RC702 in MAME under the
# zero-injection BDOS-5 tracer (bdos_trace.lua), and print the linear trace of
# every BDOS (CALL 5) invocation with entry params (C, DE) and exit values
# (A, HL).  This is the "debug helper that prints entry parameters and exit
# values from calls to 5" -- it needs no ZSID and no serial console because in
# MAME we can tap the BDOS entry vector directly.
#
# Usage:
#   ./trace.sh [source.c]      # default: bdostst.c
# Env:
#   BDOS_SECS  trace window seconds (default 40)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"          # rc700-gensmedet
WORKSPACE="$(cd "$ROOT/.." && pwd)"        # /Users/ravn/z80

Z88DK="${Z88DK:-$WORKSPACE/z88dk}"
MAME_DIR="${MAME_DIR:-$WORKSPACE/mame}"
IMG="${IMG:-$ROOT/autoload-in-c/test-disks/SW1711-I8.imd}"
DISKDEFS="${DISKDEFS:-$ROOT/rcbios/diskdefs}"
DEF=rc702-8dd
SRC="${1:-bdostst.c}"

export PATH="$Z88DK/bin:$PATH"
export ZCCCFG="${ZCCCFG:-$Z88DK/lib/config}"

# COM name = uppercased basename, max 8 chars (CP/M).
base="$(basename "$SRC" .c)"
comname="$(echo "$base" | tr '[:lower:]' '[:upper:]' | cut -c1-8)"

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

echo "=== 1. build $comname.COM (llvm-z88dk) from $SRC ==="
# Link the interim clang-ABI bdos shim (z88dk#20) when present.
COMPILER="${COMPILER:-llvmz80}"
SHIM=""
if [ "$COMPILER" = "llvmz80" ]; then
  [ -f "$HERE/cpm_bdos_clang.asm" ] && SHIM="$HERE/cpm_bdos_clang.asm"
  [ -f "$HERE/cpm_stdio_clang.asm" ] && SHIM="$SHIM $HERE/cpm_stdio_clang.asm"
fi
( cd "$HERE" && zcc +cpm -compiler=$COMPILER --opt-code-size "$SRC" $SHIM \
      -o "$W/prog" -create-app -pragma-define:CLIB_OPEN_MAX=8 )
COM="$(ls "$W"/*.COM 2>/dev/null | head -1)"
echo "  $(basename "$COM"): $(wc -c < "$COM" | tr -d ' ') bytes"

echo "=== 2. build rcbios-in-c BIOS ==="
( cd "$ROOT/rcbios-in-c" && make bios >/dev/null )
BIOS="$ROOT/rcbios-in-c/clang/bios.clang.cim"

echo "=== 3. build disk image ==="
cp "$IMG" "$W/work.imd"
python3 "$ROOT/rcbios/patch_bios.py" "$W/work.imd" "$BIOS" >/dev/null
DISKDEFS="$DISKDEFS" cpmcp -f "$DEF" "$W/work.imd" "$COM" "0:$comname.COM"
rm -f "$W/work.mfi"
"$MAME_DIR/floptool" flopconvert auto mfi "$W/work.imd" "$W/work.mfi" >/dev/null 2>&1

echo "=== 4. run under BDOS-5 tracer ==="
TRACE="$W/trace.txt"
rm -f "$TRACE"
TRACE_OUT="$TRACE" BDOS_CMD="$comname"$'\r' BDOS_SECS="${BDOS_SECS:-40}" \
  "$MAME_DIR/regnecentralen" rc702 -rompath "$MAME_DIR/roms" \
    -flop1 "$W/work.mfi" -skip_gameinfo -window -resolution 1100x720 \
    -nothrottle -autoboot_script "$HERE/bdos_trace.lua" >/dev/null 2>&1 &
MPID=$!
for _ in $(seq 1 130); do
    kill -0 "$MPID" 2>/dev/null || break
    sleep 1
done
kill -0 "$MPID" 2>/dev/null && kill -9 "$MPID" 2>/dev/null || true
wait "$MPID" 2>/dev/null || true

echo "=== 5. BDOS trace ==="
cat "$TRACE" 2>/dev/null || echo "(no trace captured)"

# Persist a copy next to the test for inspection.
cp "$TRACE" "$HERE/last-trace.txt" 2>/dev/null || true

echo "=== 6. extract BDOSTST.LOG (authoritative per-check results) ==="
LOGIMD="$W/after.imd"
if "$MAME_DIR/floptool" flopconvert mfi imd "$W/work.mfi" "$LOGIMD" >/dev/null 2>&1; then
    DISKDEFS="$DISKDEFS" cpmcp -f "$DEF" "$LOGIMD" "0:BDOSTST.LOG" "$HERE/last-bdostst.log" 2>/dev/null \
        && { echo "--- BDOSTST.LOG ---"; cat "$HERE/last-bdostst.log"; } \
        || echo "(BDOSTST.LOG not found on disk)"
else
    echo "(mfi->imd convert failed)"
fi
