#!/bin/bash
# todget_rcbios_test.sh -- rcbios + PIO + TODGET regression test.
#
# Proves the same TODGET.COM binary that works on cpnos slave runs
# byte-identical on rcbios+CPNETLDR against the rebuilt mpm-net2
# master.  Pairs with cpnos-in-c's TODGET path; together they show
# the FN-105 vendor-extension wire frame is slave-implementation
# independent under CP/NET 1.2.
#
# Wire topology (identical to polypascal_pio_test.sh):
#   PIO-B  -> cpnet_bridge       -> :4002 (mpm-net2 master)
#   SIO-A  -> file sink (unused under PIO)
#   SIO-B  -> file sink           (captures slave console output)
#
# SW1 bit 2 = 0 -> PIO transport (default On in the reference image).
# SW1 bit 0 = 0 -> joined console: SIO-B carries CONOUT, which is
#                  what TODGET printf()s land on.  No keyboard
#                  injection needed: $$$.SUB feeds the CCP from disk.
#
# Why this exists (not "extend NDOS for BDOS-105"):
#   Under CP/NET 1.2, BDOS-105 is NOT a forwardable function (see
#   `tasks/memory/feedback_cpnet_12_only.md`).  Upstream ndos3.asm:504
#   correctly passes it through ("can't support here, use SEND NW
#   MESG").  TODGET drives FN-105 as a vendor extension via NSEND
#   (BDOS-66) / NRECV (BDOS-67) -- both of which NDOS3 *does*
#   dispatch (ndos3.asm:518 / :519).  So the same TODGET.COM works
#   on both slaves; this harness proves the rcbios path.
#
# Prereqs (same as polypascal_pio_test.sh):
#   - ~/Downloads/SW1711-I8.imd     reference 8" MAXI disk
#   - ~/git/cpnet-z80/dist/         CCP.SPR, CPNETLDR.COM, NDOS.SPR
#   - z80pack mpm-net2 startable from z80pack/cpmsim/
#   - cpnet/mpm-server/rebuild-mpm-sys.sh --install run at least once
#     (so the FN-105 gettod handler is baked into MPM.SYS)
#   - cpnet/todget/TODGET.COM built  (cd cpnet/todget && make)
#   - MAME at $MAME_DIR (default ../mame)
#
# Usage:
#   cd rc700-gensmedet
#   cpnet/todget_rcbios_test.sh                 # clang BIOS (default)
#   COMPILER=sdcc cpnet/todget_rcbios_test.sh   # SDCC BIOS

set -eu

cd "$(dirname "$0")/.."
HERE="$(pwd)"

MAME_DIR="${MAME_DIR:-$HERE/../mame}"
MPM_DIR="${MPM_DIR:-$HERE/z80pack/cpmsim}"
REFERENCE_IMAGE="${REFERENCE_IMAGE:-$HOME/Downloads/SW1711-I8.imd}"
CPNET_DIST="${CPNET_DIST:-$HOME/git/cpnet-z80/dist}"
TODGET_COM="${TODGET_COM:-$HERE/cpnet/todget/TODGET.COM}"
WORK_IMAGE="/tmp/todget_rcbios_test.imd"
SIOB_CAPTURE="/tmp/todget_rcbios_siob.raw"
SIOA_CAPTURE="/tmp/todget_rcbios_sioa.raw"
RESULT_FILE="/tmp/todget_rcbios_result.txt"

[ -f "$REFERENCE_IMAGE" ] || { echo "ERROR: $REFERENCE_IMAGE missing"; exit 1; }
[ -d "$CPNET_DIST" ]      || { echo "ERROR: $CPNET_DIST missing"; exit 1; }
[ -f "$TODGET_COM" ]      || { echo "ERROR: $TODGET_COM missing; cd cpnet/todget && make"; exit 1; }

TRANSPORT="PIO"
echo "========================================================="
echo "  rcbios todget-test  COMPILER=${COMPILER:-clang}  TRANSPORT=$TRANSPORT"
echo "========================================================="

echo "--- 1/6 building SNIOS.SPR (dual SIO+PIO transport) ---"
python3 cpnet/build_snios.py >/dev/null
echo "  SNIOS.SPR: $(wc -c < cpnet/zout/SNIOS.SPR) B"

echo "--- 2/6 building rcbios + patching onto fresh disk image ---"
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

echo "--- 3/6 injecting CP/NET files + TODGET.COM + \$\$\$.SUB ---"
FORMAT="rc702-8dd"
cpmcp -f "$FORMAT" "$WORK_IMAGE" cpnet/zout/SNIOS.SPR "0:SNIOS.SPR"
for f in "$CPNET_DIST"/*.com "$CPNET_DIST"/*.spr; do
    NAME=$(basename "$f" | tr '[:lower:]' '[:upper:]')
    cpmcp -f "$FORMAT" "$WORK_IMAGE" "$f" "0:$NAME"
done >/dev/null
cpmcp -f "$FORMAT" "$WORK_IMAGE" "$TODGET_COM" "0:TODGET.COM"

# CCP $$$.SUB exec is BOTTOM-UP: pops the last record first.
# Execute sequence:
#   CPNETLDR        load CP/NET (NDOS + SNIOS)
#   LOGIN PASSWORD  first real CP/NET login frame (PIO send/recv)
#   TODGET          drive FN-105 vendor extension via BDOS-66/67
# No NETWORK mapping needed: TODGET uses only the message pipe,
# not a remote drive.
python3 -c "
def rec(cmd):
    b = cmd.encode('ascii')
    return bytes([len(b)]) + b + bytes(127 - len(b))
data = (rec('TODGET')
      + rec('LOGIN PASSWORD')
      + rec('CPNETLDR'))
open('/tmp/todget_rcbios_sub.tmp', 'wb').write(data)
"
cpmcp -f "$FORMAT" "$WORK_IMAGE" /tmp/todget_rcbios_sub.tmp '0:$$$.SUB'

echo "--- 4/6 killing prior MP/M (avoid stale-disk cache) ---"
# Same cpmsim caveat as polypascal_pio_test: in-flight cpmsim caches
# sector reads; the rebuild-mpm-sys.sh --install step must have
# already updated disks/local/mpm-net2-1.dsk on disk before this
# point.  Killing here ensures the FRESH disk is re-opened.
screen -wipe 2>/dev/null >/dev/null || true
screen -ls 2>/dev/null | grep -E "mpm|cpmsim" | awk '{print $1}' | while read s; do screen -S "$s" -X quit 2>/dev/null || true; done
pkill -f "cpmsim" 2>/dev/null || true
sleep 6

echo "--- 5/6 starting mpm-net2 master ---"
cd "$MPM_DIR" && screen -dmS mpm ./mpm-net2 && cd "$HERE"
sleep 4
nc -z 127.0.0.1 4002 || { echo "ERROR: mpm-net2 not listening on :4002"; exit 1; }

rm -f "$SIOB_CAPTURE" "$SIOA_CAPTURE" "$RESULT_FILE"

echo "--- 6/6 launching MAME (PIO=:4002 master, SIO-B captured to file) ---"
# Short runtime: CPNETLDR + LOGIN + TODGET completes in well under
# 60 s of MAME-time on the polypascal harness's comparable path.
# Cap at 90 s wall-clock to leave headroom for slow CI hosts.
perl -e 'alarm 100; exec @ARGV' "$MAME_DIR/regnecentralend" rc702 \
    -rompath "$MAME_DIR/roms" \
    -flop1 "$WORK_IMAGE" \
    -nothrottle -window -skip_gameinfo \
    -seconds_to_run 90 \
    -rs232a null_modem -bitb1 "$SIOA_CAPTURE" \
    -rs232b null_modem -bitb2 "$SIOB_CAPTURE" \
    -piob cpnet_bridge \
    -bitb3 socket.127.0.0.1:4002 2>&1 | tail -3 || true

# Best-effort cleanup of the mpm-net2 daemon (do not assume own).
screen -ls 2>/dev/null | grep -E "mpm" | awk '{print $1}' | while read s; do screen -S "$s" -X quit 2>/dev/null || true; done

echo
echo "--- captured SIO-B tail (last 800 B) ---"
tail -c 800 "$SIOB_CAPTURE" 2>/dev/null | tr -d '\000' | head -c 800
echo
echo "--- result ---"

# Success predicate: a YYYY-MM-DD HH:MM:SS line must appear in the
# captured CONOUT stream.  That string is only produced if:
#   1. CPNETLDR successfully loaded NDOS+SNIOS
#   2. LOGIN successfully exchanged a CP/NET frame (PIO transport up)
#   3. TODGET's BDOS-66 NSEND reached the master
#   4. master's FN-105 gettod handler returned a valid ASCII date
#   5. TODGET's BDOS-67 NRECV delivered it back to TPA
# Anything less and the regex fails: PASS condition is self-checking.
DATE_RE='20[0-9][0-9]-[0-1][0-9]-[0-3][0-9] [0-2][0-9]:[0-5][0-9]:[0-5][0-9]'
if tr -d '\000' < "$SIOB_CAPTURE" 2>/dev/null | grep -Eq "$DATE_RE"; then
    MATCH=$(tr -d '\000' < "$SIOB_CAPTURE" | grep -Eo "$DATE_RE" | head -1)
    echo "PASS: TODGET received '$MATCH' from master"
    echo "PASS $MATCH" > "$RESULT_FILE"
    exit 0
else
    echo "FAIL: no YYYY-MM-DD HH:MM:SS in SIO-B capture"
    echo "FAIL" > "$RESULT_FILE"
    exit 1
fi
