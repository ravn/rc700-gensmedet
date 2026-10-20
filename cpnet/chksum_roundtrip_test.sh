#!/bin/bash
# chksum_roundtrip_test.sh -- CP/NET round-trip integrity test against MP/M.
#
# Creates a deterministic 2048-byte fixture (0..255 repeated 8 times)
# on the RC702's local A:, then PIPs it to MP/M's B:/H:, PIPs it back to
# a different local name, and runs CHKSUM on all three copies.  PASS iff
# all three checksums match the pre-computed reference (0xFC00).
#
# Prereqs:
#   - z80pack MP/M running on localhost:4002 (start via test-server.exp)
#   - MAME regnecentralend built
#   - BIOS already built (run_test.sh -no-server -inject uses the same BIOS)
set -u
cd "$(dirname "$0")/.."
HERE="$(pwd)"

MAME_DIR="${MAME_DIR:-$HERE/../mame}"
MAME_BIN="$MAME_DIR/regnecentralend"
FLOPTOOL="$MAME_DIR/floptool"
IMG_MAXI="${IMG_MAXI:-$HOME/Downloads/SW1711-I8.imd}"
PATCH="python3 rcbios/patch_bios.py"
CPMCP="${CPMCP:-cpmcp}"
BIOS_CIM="${BIOS_CIM:-$HERE/rcbios-in-c/clang/bios.clang.cim}"
CPNET_DIST="${HOME}/git/cpnet-z80/dist"

WORK=/tmp/cpnet_chksum
rm -rf "$WORK"; mkdir -p "$WORK"

# ---- 1. Generate deterministic fixture + compute expected checksum ----
python3 - <<PYEOF
data = bytes(i & 0xFF for i in range(2048))  # 0..255 repeating 8 times
open("$WORK/FIXT.DAT", "wb").write(data)

# Checksum algo: 16-bit sum of every byte, with HL+=A carry (plain uint16 wrap)
h = 0
for b in data:
    h = (h + b) & 0xFFFF
print(f"EXPECTED_CHKSUM = 0x{h:04X}")
open("$WORK/expected.txt", "w").write(f"{h:04X}\n")
PYEOF
EXPECTED=$(cat "$WORK/expected.txt")
echo "Expected checksum: $EXPECTED"

# ---- 2. Build SNIOS.SPR + CHKSUM.COM (reuse bits of run_test.sh) ----
cd cpnet
python3 build_snios.py > /dev/null
cd - > /dev/null
# Assemble CHKSUM.COM
mkdir -p "$WORK/zout"
(cd "$WORK" && "$HERE/zmac/bin/zmac" -c --oo cim "$HERE/cpnet/chksum.asm" > /dev/null)
[ -f "$WORK/zout/chksum.cim" ] || { echo "chksum assemble failed"; exit 1; }

# ---- 3. Build disk image: reference + BIOS patch + CP/NET files + fixture + $$$.SUB ----
cp "$IMG_MAXI" "$WORK/disk.imd"
$PATCH "$WORK/disk.imd" "$BIOS_CIM" > /dev/null
FORMAT="rc702-8dd"
$CPMCP -f "$FORMAT" "$WORK/disk.imd" "$HERE/cpnet/zout/SNIOS.SPR" "0:SNIOS.SPR" > /dev/null
for f in "$CPNET_DIST"/*.com "$CPNET_DIST"/*.spr; do
    NAME=$(basename "$f" | tr '[:lower:]' '[:upper:]')
    $CPMCP -f "$FORMAT" "$WORK/disk.imd" "$f" "0:$NAME" > /dev/null
done
$CPMCP -f "$FORMAT" "$WORK/disk.imd" "$WORK/zout/chksum.cim" "0:CHKSUM.COM" > /dev/null
$CPMCP -f "$FORMAT" "$WORK/disk.imd" "$WORK/FIXT.DAT" "0:FIXT.DAT" > /dev/null

# $$$.SUB runs in reverse file order.  We want:
#   1) CPNETLDR
#   2) LOGIN PASSWORD
#   3) NETWORK H:=B:
#   4) ERA H:FIXT.DAT        (cleanup in case of stale server state)
#   5) PIP H:FIXT.DAT=A:FIXT.DAT     (push to server)
#   6) PIP A:BACK.DAT=H:FIXT.DAT     (pull back)
#   7) CHKSUM A:FIXT.DAT      (local original)
#   8) CHKSUM A:BACK.DAT      (local round-tripped)
#   9) CHKSUM H:FIXT.DAT      (server-side read via CP/NET)
python3 - <<PYEOF
def rec(cmd):
    b = cmd.encode('ascii')
    return bytes([len(b)]) + b + bytes(127 - len(b))
commands = [
    'CHKSUM H:FIXT.DAT',
    'CHKSUM A:BACK.DAT',
    'CHKSUM A:FIXT.DAT',
    'PIPNET A:BACK.DAT=H:FIXT.DAT',
    'PIPNET H:FIXT.DAT=A:FIXT.DAT',
    'ERA H:FIXT.DAT',
    'NETWORK H:=B:',
    'LOGIN PASSWORD',
    'CPNETLDR',
]
open("$WORK/sub.bin", "wb").write(b"".join(rec(c) for c in commands))
PYEOF
$CPMCP -f "$FORMAT" "$WORK/disk.imd" "$WORK/sub.bin" '0:$$$.SUB' > /dev/null
$FLOPTOOL flopconvert auto mfi "$WORK/disk.imd" "$WORK/disk.mfi" > /dev/null 2>&1

# ---- 4. Launch MAME with trace lua (dumps screen at end) ----
rm -f /tmp/chksum_trace.csv
LOGIN_TRACE_LOG=/tmp/chksum_trace.csv \
LOGIN_TRACE_SECS=60 \
"$MAME_BIN" rc702 -rompath "$MAME_DIR/roms" \
    -rom1 "$HERE/autoload-in-c/clang/prom0.ic66" \
    -flop1 "$WORK/disk.mfi" \
    -rs232a null_modem \
    -bitb1 "socket.127.0.0.1:4002" \
    -skip_gameinfo -window -resolution 1100x720 -nothrottle \
    -autoboot_script "$HERE/cpnet/login_trace.lua" \
    > "$WORK/mame.log" 2>&1 &
MAME=$!
( sleep 90 && kill $MAME 2>/dev/null ) &
KILL=$!
wait $MAME 2>/dev/null
kill $KILL 2>/dev/null

# ---- 5. Parse CHKSUM outputs from the screen dump at end of trace.csv ----
# CHKSUM prints 4 uppercase hex digits followed by CR LF on CRT.
# Screen dump has row lines like "#  NN: <text>".
echo
echo "=== Screen dump (last 20 rows) ==="
grep "^#  " /tmp/chksum_trace.csv | tail -20

# Extract lines that look like a standalone 4-hex-digit checksum on the CRT.
CHECKSUMS=$(grep "^#  " /tmp/chksum_trace.csv | grep -oE '\b[0-9A-F]{4}\b' | sort -u)
echo
echo "=== Checksums seen on screen ==="
echo "$CHECKSUMS"
echo
echo "=== Expected: $EXPECTED ==="
COUNT=$(echo "$CHECKSUMS" | grep -xF "$EXPECTED" | wc -l | tr -d ' ')
if [ "$COUNT" = "1" ]; then
    # All three CHKSUM commands should have printed the same value
    TOTAL_LINES=$(grep "^#  " /tmp/chksum_trace.csv | grep -cE "^#  [0-9]+: $EXPECTED")
    echo "Matching lines: $TOTAL_LINES"
    if [ "$TOTAL_LINES" -ge 3 ]; then
        echo "=== PASS: all 3 CHKSUM outputs match 0x$EXPECTED ==="
        exit 0
    else
        echo "=== FAIL: expected 3 matches on screen, got $TOTAL_LINES ==="
        exit 1
    fi
else
    echo "=== FAIL: expected checksum 0x$EXPECTED not seen (or mismatched) ==="
    exit 1
fi
