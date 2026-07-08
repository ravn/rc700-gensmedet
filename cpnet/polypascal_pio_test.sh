#!/bin/bash
# polypascal_pio_test.sh — rcbios + PIO + PolyPascal regression test.
#
# End-to-end equivalent of cpnos-in-c's `cpnos-polypascal-test`, but
# for the rcbios slave path: rcbios boots from local floppy, runs
# CPNETLDR + LOGIN + NETWORK + H:PPAS H:PRIMES.PAS, PolyPascal-80
# runs PRIMES through 29989 driven by polypascal_pio_inject.py over
# SIO-B (joined console), Q returns to CCP.
#
# Wire topology:
#   PIO-B  -> cpnet_bridge       -> :4002 (mpm-net2 master)
#   SIO-A  -> file sink (unused; the new SNIOS doesn't open SIO-A in
#                                 PIO mode)
#   SIO-B  -> null_modem socket  -> :9001 (polypascal_pio_inject.py)
#
# SW1 bit 2 = 0 (default On) selects PIO transport in the new
# dual-transport SNIOS.SPR (cpnet/snios.asm).  Bit 0 = 0 (default On)
# selects joined console so SIO-B carries keyboard injection both
# ways.
#
# Prereqs:
#   - ~/Downloads/SW1711-I8.imd  (reference 8" MAXI disk)
#   - ~/git/cpnet-z80/dist/      (CCP.SPR, CPNETLDR.COM, etc.)
#   - cpnos-shared/e_drive_seed/ppas/{PPAS.COM,PRIMES.PAS} (in tree)
#   - MAME at $MAME_DIR (default /Users/ravn/z80/mame)
#   - z80pack mpm-net2 startable from z80pack/cpmsim/

set -eu

cd "$(dirname "$0")/.."
HERE="$(pwd)"

MAME_DIR="${MAME_DIR:-$HERE/../mame}"
MPM_DIR="${MPM_DIR:-$HERE/z80pack/cpmsim}"
REFERENCE_IMAGE="${REFERENCE_IMAGE:-$HOME/Downloads/SW1711-I8.imd}"
CPNET_DIST="${CPNET_DIST:-$HOME/git/cpnet-z80/dist}"
WORK_IMAGE="/tmp/cpnet_pio_test.imd"
SIOB_PORT="${SIOB_PORT:-9001}"

[ -f "$REFERENCE_IMAGE" ] || { echo "ERROR: $REFERENCE_IMAGE missing"; exit 1; }
[ -d "$CPNET_DIST" ]      || { echo "ERROR: $CPNET_DIST missing"; exit 1; }

# Transport is fixed by SW1 bit 2 = 0 (default On) in the disk image
# we patch.  Print it explicitly so anyone watching the test log knows
# which slave-side CP/NET transport is being exercised.
TRANSPORT="PIO"
echo "========================================================="
echo "  rcbios polypascal-test  COMPILER=${COMPILER:-clang}  TRANSPORT=$TRANSPORT"
echo "========================================================="

echo "=== 1/6 building SNIOS.SPR (dual SIO+PIO transport) ==="
python3 cpnet/build_snios.py >/dev/null
echo "  SNIOS.SPR: $(wc -c < cpnet/zout/SNIOS.SPR) B"

echo "=== 2/6 building rcbios + patching onto fresh disk image ==="
# COMPILER env var (default clang) picks rcbios's compile path.
# rcbios's clang BIOS at rcbios-in-c/clang/bios.clang.cim,
# rcbios's SDCC  BIOS at rcbios-in-c/sdcc/bios.cim.  SNIOS.SPR is
# asm-only -- same SPR for both.
RCBIOS_COMPILER="${COMPILER:-clang}"
echo "  rcbios COMPILER=$RCBIOS_COMPILER"
make -C rcbios-in-c bios COMPILER="$RCBIOS_COMPILER" --no-print-directory >/dev/null
cp "$REFERENCE_IMAGE" "$WORK_IMAGE"
if [ "$RCBIOS_COMPILER" = clang ]; then
    BIOS_CIM=rcbios-in-c/clang/bios.clang.cim
else
    BIOS_CIM=rcbios-in-c/sdcc/bios.cim
fi
python3 rcbios/patch_bios.py "$WORK_IMAGE" "$BIOS_CIM" >/dev/null

echo "=== 3/6 injecting CP/NET files + \$\$\$.SUB into local disk ==="
FORMAT="rc702-8dd"
cpmcp -f "$FORMAT" "$WORK_IMAGE" cpnet/zout/SNIOS.SPR "0:SNIOS.SPR"
for f in "$CPNET_DIST"/*.com "$CPNET_DIST"/*.spr; do
    NAME=$(basename "$f" | tr '[:lower:]' '[:upper:]')
    cpmcp -f "$FORMAT" "$WORK_IMAGE" "$f" "0:$NAME"
done >/dev/null
# PPAS+PRIMES live on master's A: (staged in step 4), accessed via
# slave H: after NETWORK.  Exercises CP/NET PIO fully -- both the
# file load and the interactive run go over the wire.  PPAS lives on
# master's I: (4 MB HD, fresh each run) mapped to slave H: via
# NETWORK H:=I:.  mpm-net2-1.dsk (A:) is too small to hold PPAS.COM.
python3 -c "
def rec(cmd):
    b = cmd.encode('ascii')
    return bytes([len(b)]) + b + bytes(127 - len(b))
# CCP \$\$\$.SUB execution pops the LAST record first then truncates.
# File order is REVERSE of execution order.  Execute sequence:
#   CPNETLDR  -> load CP/NET (NDOS + SNIOS.SPR, SNIOS NTWKIN reads SW1
#                bit 2; bit clear -> PIO transport in the new dual-
#                transport SNIOS)
#   LOGIN     -> first real CP/NET login frame, exercises PIO send/recv
#   NETWORK   -> map slave H: to master I: (4 MB HD has PPAS; A: is full)
#   H:        -> change default drive to H:
# CCP $$$.SUB exec is BOTTOM-UP: pops the last record first.
# PPAS is NOT in the SUB -- inject via SIO-B keyboard path (robust).
data = (rec('H:')
      + rec('NETWORK H:=I:')
      + rec('LOGIN PASSWORD')
      + rec('CPNETLDR'))
open('/tmp/cpnet_pio_sub.tmp', 'wb').write(data)
"
cpmcp -f "$FORMAT" "$WORK_IMAGE" /tmp/cpnet_pio_sub.tmp '0:$$$.SUB'

echo "=== 4/6 killing prior MP/M (so disk cpmcp lands before re-open) ==="
# cpmsim caches sector reads at startup; updating the disk image while it's
# open silently serves stale content.  See cpnos-polypascal-test docstring.
screen -wipe 2>/dev/null >/dev/null || true
screen -ls 2>/dev/null | grep -E "mpm|cpmsim" | awk '{print $1}' | while read s; do screen -S "$s" -X quit 2>/dev/null || true; done
pkill -f "cpmsim" 2>/dev/null || true
sleep 6

echo "=== staging PPAS+PRIMES+PPAS.ERM+TESTDONE.COM on master's drive I: (4 MB HD) ==="
# mpm-net2 copies library/mpm-net2-drivei.dsk to drivei.dsk each start.
# Build a fresh drive I image with PPAS files (mirrors cpnos stage-drivei-ppas).
MPM_DIR_LOCAL="$HERE/z80pack/cpmsim"
DSK="$MPM_DIR_LOCAL/disks/library/mpm-net2-drivei.dsk"
for f in PPAS.COM PPAS.ERM PRIMES.PAS; do
    cpmrm -f z80pack-hd "$DSK" "0:$f" 2>/dev/null || true
    cpmcp -f z80pack-hd "$DSK" "$HERE/cpnos-shared/e_drive_seed/ppas/$f" "0:$f" 2>&1 || true
done
# Generate TESTDONE.COM: prints "RCBIOS PIO TEST DONE\r\n" via BDOS-9, warm-boots.
# CP/M .COM loads at 0x0100; BDOS entry at 0x0005; string ends with '$'.
python3 -c "
msg = b'RCBIOS PIO TEST DONE\r\n\$'
# LD C,9  (0x0E 0x09)  LD DE,msg_addr  (0x11 lo hi)  CALL 5  (0xCD 0x05 0x00)  RST 0 (0xC7)
code_len = 8
msg_addr = 0x0100 + code_len
lo = msg_addr & 0xFF
hi = (msg_addr >> 8) & 0xFF
code = bytes([0x0E, 0x09, 0x11, lo, hi, 0xCD, 0x05, 0x00, 0xC7]) + msg
open('/tmp/testdone.com', 'wb').write(code)
"
cpmrm -f z80pack-hd "$DSK" "0:TESTDONE.COM" 2>/dev/null || true
cpmcp -f z80pack-hd "$DSK" /tmp/testdone.com "0:TESTDONE.COM" 2>&1 || true
cpmls -f z80pack-hd "$DSK" 2>/dev/null | grep -iE "ppas|primes|testdone" | sed 's/^/  /'

echo "=== 5/6 starting MP/M + polypascal_pio_inject ==="

cd "$MPM_DIR" && screen -dmS mpm ./mpm-net2 && cd "$HERE"
sleep 4
nc -z 127.0.0.1 4002 || { echo "ERROR: mpm-net2 not listening on :4002"; exit 1; }

rm -f /tmp/cpnet_pio_polypascal_result.txt /tmp/cpnos_siob.raw \
      /tmp/cpnet_pio_polypascal_log.txt

python3 -u cpnet/polypascal_pio_inject.py "$SIOB_PORT" \
    --log /tmp/cpnos_siob.raw \
    --timeout 1200 > /tmp/cpnet_pio_polypascal_log.txt 2>&1 &
INJECT_PID=$!
sleep 0.5

echo "=== 6/6 launching MAME (PIO=:4002 master, SIO-B=:$SIOB_PORT inject) ==="
# MAME runs in background so inject drives it and signals completion.
# seconds_to_run is a safety cap; inject kills MAME as soon as all stages
# pass (or the inject timeout fires).
perl -e 'alarm 1200; exec @ARGV' "$MAME_DIR/regnecentralend" rc702 \
    -rompath "$MAME_DIR/roms" \
    -flop1 "$WORK_IMAGE" \
    -nothrottle -window -skip_gameinfo \
    -seconds_to_run 7200 \
    -rs232a null_modem -bitb1 /tmp/cpnet_pio_sioa.raw \
    -rs232b null_modem -bitb2 "socket.127.0.0.1:$SIOB_PORT" \
    -piob cpnet_bridge \
    -bitb3 socket.127.0.0.1:4002 >/dev/null 2>/dev/null &
MAME_PID=$!

# Wait for inject to finish (PASS or FAIL), then kill MAME.
wait "$INJECT_PID" 2>/dev/null || true
kill -KILL "$MAME_PID" 2>/dev/null || true
wait "$MAME_PID" 2>/dev/null || true

# Best-effort cleanup
screen -ls 2>/dev/null | grep -E "mpm" | awk '{print $1}' | while read s; do screen -S "$s" -X quit 2>/dev/null || true; done

echo
echo "--- polypascal_pio_inject log tail ---"
tail -20 /tmp/cpnet_pio_polypascal_log.txt 2>/dev/null
echo "--- result ---"
cat /tmp/cpnet_pio_polypascal_result.txt 2>/dev/null || echo "(no result file written)"
echo
grep -q '^PASS' /tmp/cpnet_pio_polypascal_result.txt 2>/dev/null
