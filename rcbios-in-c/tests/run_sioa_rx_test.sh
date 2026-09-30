#!/bin/bash
# run_sioa_rx_test.sh -- RX (host -> RC702) or bidirectional SIO-A test.
# Args: <label> <com_name> <com_cim> [wait_frames]
# Uses sioa_feed_and_read.py (sends 20 bytes, then listens for echo).
set -u
cd "$(dirname "$0")/.."
HERE="$(pwd)"
LABEL="$1"; COM_NAME="$2"; COM_CIM="$3"; WAIT="${4:-400}"

MAME_DIR="${MAME_DIR:-$HOME/git/mame}"
MAME_BIN="$MAME_DIR/regnecentralend"
FLOPTOOL="$MAME_DIR/floptool"
IMG_MAXI="${IMG_MAXI:-$HOME/Downloads/SW1711-I8.imd}"
PATCH="python3 ../rcbios/patch_bios.py"
CPMCP="${CPMCP:-cpmcp}"
PORT=4001

WORK="/tmp/sioa_test/$LABEL"
rm -rf "$WORK"; mkdir -p "$WORK"

cp "$IMG_MAXI" "$WORK/disk.imd"
$PATCH "$WORK/disk.imd" clang/bios.cim >/dev/null
$CPMCP -f rc702-8dd "$WORK/disk.imd" "$COM_CIM" "0:$COM_NAME" >/dev/null
$FLOPTOOL flopconvert auto mfi "$WORK/disk.imd" "$WORK/disk.mfi" >/dev/null 2>&1

python3 -u tests/sioa_feed_and_read.py $PORT > "$WORK/tcp.log" 2>&1 &
TCP=$!
sleep 0.3

OBJDUMP=/Users/ravn/z80/llvm-z80/build-macos-asserts/bin/llvm-objdump
KBHEAD_ADDR=$("$OBJDUMP" --triple=z80 -t clang/bios.elf 2>/dev/null | awk '/ _wb$/{print "0x"$1; exit}')
KBBUF_ADDR=$("$OBJDUMP" --triple=z80 -t clang/bios.elf 2>/dev/null | awk '/ _kbbuf$/{print "0x"$1; exit}')
export KBHEAD_ADDR KBBUF_ADDR
SIOA_TRACE_LOG="$WORK/sioa.csv" \
SIOA_TRACE_CMD="${COM_NAME%.COM}"$'\r' \
SIOA_TRACE_WAIT="$WAIT" \
"$MAME_BIN" rc702 -rompath "$MAME_DIR/roms" \
    -flop1 "$WORK/disk.mfi" \
    -rs232a null_modem \
    -bitb1 "socket.127.0.0.1:$PORT" \
    -skip_gameinfo -window -resolution 1100x720 \
    -autoboot_script "$HERE/tests/sioa_trace.lua" \
    > "$WORK/mame.log" 2>&1 &
MAME=$!

( sleep 25 && kill $MAME 2>/dev/null ) &
KILL=$!
wait $MAME 2>/dev/null
kill $KILL 2>/dev/null
wait $TCP 2>/dev/null

echo "=== $LABEL ==="
echo "--- TCP (feeder log) ---"
cat "$WORK/tcp.log"
echo
echo "--- Screen ---"
grep '^# ' "$WORK/sioa.csv" | head -30
echo
echo "--- SIO-A instrumentation summary ---"
grep 'SIO-A' "$WORK/mame.log" | head -30
