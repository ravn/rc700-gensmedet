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

echo "=== 1/6 building SNIOS.SPR (dual SIO+PIO transport) ==="
python3 cpnet/build_snios.py >/dev/null
echo "  SNIOS.SPR: $(wc -c < cpnet/zout/SNIOS.SPR) B"

echo "=== 2/6 building rcbios + patching onto fresh disk image ==="
make -C rcbios-in-c bios --no-print-directory >/dev/null
cp "$REFERENCE_IMAGE" "$WORK_IMAGE"
python3 rcbios/patch_bios.py "$WORK_IMAGE" rcbios-in-c/clang/bios.clang.cim >/dev/null

echo "=== 3/6 injecting CP/NET files + \$\$\$.SUB into local disk ==="
FORMAT="rc702-8dd"
cpmcp -f "$FORMAT" "$WORK_IMAGE" cpnet/zout/SNIOS.SPR "0:SNIOS.SPR"
for f in "$CPNET_DIST"/*.com "$CPNET_DIST"/*.spr; do
    NAME=$(basename "$f" | tr '[:lower:]' '[:upper:]')
    cpmcp -f "$FORMAT" "$WORK_IMAGE" "$f" "0:$NAME"
done >/dev/null
# PPAS+PRIMES live on master's A: (staged in step 4), accessed via
# slave H: after NETWORK.  Exercises CP/NET PIO fully -- both the
# file load and the interactive run go over the wire.
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
#   NETWORK   -> map slave H: to master A:
#   H:        -> change default drive to H: (first remote-drive SELDSK
#                -- earlier suspect-of-hanging, but in fact works fine;
#                the previous 'Bdos Err' was the SUB record order being
#                reversed)
#   PPAS      -> launch PolyPascal-80 from H: (=master's A:); loads
#                PPAS.COM over CP/NET PIO and runs PRIMES.PAS
data = (rec('PPAS')
      + rec('H:')
      + rec('NETWORK H:=A:')
      + rec('LOGIN PASSWORD')
      + rec('CPNETLDR'))
open('/tmp/cpnet_pio_sub.tmp', 'wb').write(data)
"
cpmcp -f "$FORMAT" "$WORK_IMAGE" /tmp/cpnet_pio_sub.tmp '0:$$$.SUB'

echo "=== 4/6 killing prior MP/M (so disk cpmcp lands before re-open) ==="
# cpmsim caches sector reads at startup; updating mpm-net2-1.dsk while it's
# open silently serves stale content.  See cpnos-polypascal-test docstring.
screen -wipe 2>/dev/null >/dev/null || true
screen -ls 2>/dev/null | grep -E "mpm|cpmsim" | awk '{print $1}' | while read s; do screen -S "$s" -X quit 2>/dev/null || true; done
pkill -f "cpmsim" 2>/dev/null || true
sleep 6

echo "=== staging PPAS+PRIMES on master's A: source disk ==="
# z80pack/cpmsim/mpm-net2 boot script copies cpnetsmk-1.dsk to drivea.dsk
# if present (smoke-test variant), else mpm-net2-1.dsk.  Stage on
# whichever is active so master's A: has PPAS.COM + PRIMES.PAS.
MPM_LIB="$HERE/z80pack/cpmsim/disks/library"
if [ -f "$MPM_LIB/cpnetsmk-1.dsk" ]; then
    MPM_DISK="$MPM_LIB/cpnetsmk-1.dsk"
else
    MPM_DISK="$MPM_LIB/mpm-net2-1.dsk"
fi
echo "  master A: source = $MPM_DISK"
cpmrm -f ibm-3740 "$MPM_DISK" 0:PPAS.COM    2>/dev/null || true
cpmrm -f ibm-3740 "$MPM_DISK" 0:PRIMES.PAS  2>/dev/null || true
cpmcp -f ibm-3740 "$MPM_DISK" cpnos-shared/e_drive_seed/ppas/PPAS.COM   0:PPAS.COM   2>&1 | grep -v "device full" || true
cpmcp -f ibm-3740 "$MPM_DISK" cpnos-shared/e_drive_seed/ppas/PRIMES.PAS 0:PRIMES.PAS 2>&1 | grep -v "device full" || true

echo "=== 5/6 starting MP/M + polypascal_pio_inject ==="

cd "$MPM_DIR" && screen -dmS mpm ./mpm-net2 && cd "$HERE"
sleep 4
nc -z 127.0.0.1 4002 || { echo "ERROR: mpm-net2 not listening on :4002"; exit 1; }

rm -f /tmp/cpnet_pio_polypascal_result.txt /tmp/cpnos_siob.raw \
      /tmp/cpnet_pio_polypascal_log.txt

python3 -u cpnet/polypascal_pio_inject.py "$SIOB_PORT" \
    --log /tmp/cpnos_siob.raw \
    --timeout 240 > /tmp/cpnet_pio_polypascal_log.txt 2>&1 &
INJECT_PID=$!
sleep 0.5

echo "=== 6/6 launching MAME (PIO=:4002 master, SIO-B=:$SIOB_PORT inject) ==="
perl -e 'alarm 250; exec @ARGV' "$MAME_DIR/regnecentralend" rc702 \
    -rompath "$MAME_DIR/roms" \
    -flop1 "$WORK_IMAGE" \
    -nothrottle -window -skip_gameinfo \
    -seconds_to_run 240 \
    -rs232a null_modem -bitb1 /tmp/cpnet_pio_sioa.raw \
    -rs232b null_modem -bitb2 "socket.127.0.0.1:$SIOB_PORT" \
    -piob cpnet_bridge \
    -bitb3 socket.127.0.0.1:4002 2>&1 | tail -3 || true

# Best-effort cleanup
kill "$INJECT_PID" 2>/dev/null || true
screen -ls 2>/dev/null | grep -E "mpm" | awk '{print $1}' | while read s; do screen -S "$s" -X quit 2>/dev/null || true; done

echo
echo "--- polypascal_pio_inject log tail ---"
tail -20 /tmp/cpnet_pio_polypascal_log.txt 2>/dev/null
echo "--- result ---"
cat /tmp/cpnet_pio_polypascal_result.txt 2>/dev/null || echo "(no result file written)"
echo
grep -q '^PASS' /tmp/cpnet_pio_polypascal_result.txt 2>/dev/null
