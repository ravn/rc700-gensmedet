#!/bin/sh
# Stage the cpnet-smoke test disk.
#
# MP/M's CP/NET server (z80pack mpm-net2) exposes its drive A: only,
# regardless of which slave drive letter the request carries.  So we
# can't put the test source on a separate disk — it must live on
# MP/M's A: drive alongside M80.COM/L80.COM/LOAD.COM.
#
# This script takes mpm-net2-1.dsk as a template, injects sumtest.asm
# into it, and writes the result as cpnetsmk-1.dsk in the library.
# The mpm-net2 launcher stages cpnetsmk-1.dsk as drivea.dsk when it
# exists, falling back to the stock mpm-net2-1.dsk otherwise.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
PARENT=$(cd "$HERE/../.." && pwd)
LIB="$PARENT/z80pack/cpmsim/disks/library"
SRC_DISK="$LIB/mpm-net2-1.dsk"
OUT_DISK="$LIB/cpnetsmk-1.dsk"

if [ ! -f "$HERE/sumtest.asm" ]; then
    echo "regenerating sumtest.asm" >&2
    python3 "$HERE/mksmokeasm.py"
fi

cp "$SRC_DISK" "$OUT_DISK"

# mpm-net2-1 is ~2 KB free out of 241 KB; sumtest.asm for N=1000 is
# ~42 KB, so we delete MP/M-native .PRL tools the slave can't run
# anyway (PRL is Page-Relocatable, MP/M-only).  .SUB and .PRL are
# both safe to drop — the slave never executes them.  Also clear
# out MAIL/SCHED/SPOOL support which is MP/M-only.
for name in \
    ABORT.PRL ASM.PRL CONSOLE.PRL DIR.PRL DSKRESET.PRL DUMP.PRL \
    ED.PRL ERA.PRL ERAQ.PRL MPMSTAT.PRL PIP.PRL PRINTER.PRL \
    PRLCOM.PRL RDT.PRL REN.PRL SCHED.PRL SDIR.PRL SET.PRL \
    SETTOD.PRL SHOW.PRL SPOOL.PRL STAT.PRL STOPSPLR.PRL \
    SUBMIT.PRL TOD.PRL TYPE.PRL USER.PRL \
    $$$.SUB MAIL.COM
do
    cpmrm -f ibm-3740 "$OUT_DISK" "0:$name" 2>/dev/null || true
done

cpmrm -f ibm-3740 "$OUT_DISK" 0:SUMTEST.ASM 2>/dev/null || true
cpmcp -f ibm-3740 "$OUT_DISK" "$HERE/sumtest.asm" 0:SUMTEST.ASM

# Pre-assemble filecopy.com on host so the file-I/O bench (WORKLOAD=
# filecopy) can run it directly without an m80/l80 step.  Pure 8080
# source, zmac --dri -8 produces a CP/M .COM image at zout/filecopy.cim.
ZMAC=$(cd "$HERE/../../zmac/bin" && pwd)/zmac
if [ -x "$ZMAC" ]; then
    (cd "$HERE" && "$ZMAC" -8 --dri filecopy.asm > /dev/null 2>&1)
    if [ -f "$HERE/zout/filecopy.cim" ]; then
        cpmrm -f ibm-3740 "$OUT_DISK" 0:FILECOPY.COM 2>/dev/null || true
        cpmcp -f ibm-3740 "$OUT_DISK" "$HERE/zout/filecopy.cim" 0:FILECOPY.COM
    else
        echo "warning: zmac did not produce filecopy.cim; FILECOPY.COM not staged" >&2
    fi
else
    echo "warning: zmac not found at $ZMAC; FILECOPY.COM not staged" >&2
fi

# TINY.ASM diagnostic staging removed (was: smallest-possible M80
# source used by the old smoke workload's `type tiny.asm` + `m80 tiny`
# steps).  Current minimal workload goes straight to m80 sumtest, so
# the artifact is dead code.  See ravn/rc700-gensmedet#43.
cpmrm -f ibm-3740 "$OUT_DISK" 0:TINY.ASM 2>/dev/null || true

# mpm-net2-1.dsk ships RMAC/M80/LINK/LOAD but no L80.  Our smoke script
# uses Microsoft's M80+L80 pair, so pull L80.COM off cpm22-1.dsk.
CPM22_DISK="$LIB/cpm22-1.dsk"
TMP_L80=$(mktemp -d)
trap "rm -rf $TMP_L80" EXIT
cpmcp -f ibm-3740 "$CPM22_DISK" 0:L80.COM "$TMP_L80/L80.COM"
cpmrm -f ibm-3740 "$OUT_DISK" 0:L80.COM 2>/dev/null || true
cpmcp -f ibm-3740 "$OUT_DISK" "$TMP_L80/L80.COM" 0:L80.COM

# Replace the stock CPNOS.IMG (z80pack generic slave) with our RC702-
# retargeted cpnos.com.  Without this, netboot fetches z80pack's image
# that drives ports the RC702 doesn't have.  Rebuild cpnos-build first
# if not already current.
CPNOS_COM="$PARENT/cpnos-rom/cpnos-build/d/cpnos.com"
if [ ! -f "$CPNOS_COM" ]; then
    echo "error: $CPNOS_COM not found — run 'make -C cpnos-rom/cpnos-build' first" >&2
    exit 1
fi
cpmrm -f ibm-3740 "$OUT_DISK" 0:CPNOS.IMG 2>/dev/null || true
cpmcp -f ibm-3740 "$OUT_DISK" "$CPNOS_COM" 0:CPNOS.IMG

echo "wrote $OUT_DISK"
echo "cpnetsmk-1.dsk free space + contents:"
cpmls -f ibm-3740 -D "$OUT_DISK" | tail -3
