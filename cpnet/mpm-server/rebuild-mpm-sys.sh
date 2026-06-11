#!/bin/bash
# rebuild-mpm-sys.sh -- regenerate MPM.SYS from current SERVER.RSP source.
#
# Why: editing server.asm and reinstalling server.rsp on the cpmsim
# library disks is INERT.  MP/M boots from mpm.sys which bakes SERVER
# in at GENSYS time.  This script does the full chain:
#
#   1. rebuild server.rsp from server.asm via vcpm rmac + link
#   2. stage every input GENSYS needs (RSPs, SPRs, BRSes, DATs) on a
#      vcpm working drive, with the FRESH server.rsp substituted in
#   3. drive GENSYS.COM via vcpm with the canonical answer table
#   4. patch the resulting MPM.SYS onto a fresh copy of the pristine
#      z80pack mpm-net2-1.dsk (drive A: boot disk)
#
# Output: a new mpm-net2-1.dsk image in the path passed via -o, OR in
# z80pack/cpmsim/disks/local/ (if --install is given) — preferred by
# the mpm-net2 launcher; pristine library copies stay untouched.
#
# Background: ../REBUILDING_MPM_SYS.md (one directory up).
#
# Project-side layout (this is the home for everything that diverges
# from upstream-pristine cpnet-z80):
#   - rc700-gensmedet/cpnet/mpm-server/server.asm           (patched)
#   - rc700-gensmedet/cpnet/mpm-server/rebuild-mpm-sys.sh   (this file)
#
# Prereqs (all should already be present in the workspace):
#   - cpnet-z80 submodule (upstream-tracked, unmodified):
#       cpnet-z80/tools/VirtualCpm.jar
#       cpnet-z80/dist/vcpm/{rmac,link}.com
#   - z80pack with pristine MP/M disks:
#       z80pack/cpmsim/disks/library/mpm-net2-{1,2}.dsk
#   - cpmtools with rc700 diskdefs:
#       cpmcp, cpmrm   in PATH
#       rc700-gensmedet/rcbios/diskdefs   (ibm-3740 format definition)
#   - java
#
# Usage:
#   ./rebuild-mpm-sys.sh                       # writes /tmp/mpm-net2-1.dsk
#   ./rebuild-mpm-sys.sh -o my-new-bootdisk.dsk
#   ./rebuild-mpm-sys.sh --install             # install into
#                                              # z80pack/cpmsim/disks/local/
#                                              # (preferred by the
#                                              # mpm-net2 launcher; the
#                                              # pristine library copy
#                                              # is left untouched)

set -euo pipefail

# --- locate workspace roots ---------------------------------------------
# Script lives at rc700-gensmedet/cpnet/mpm-server/.  The patched
# server.asm sits next to this script (project-side, not upstream).
HERE=$(cd "$(dirname "$0")" && pwd)                          # …/cpnet/mpm-server
RC700=$(cd "$HERE/../.." && pwd)                              # …/rc700-gensmedet
WS=$(cd "$RC700/.." && pwd)                                   # workspace root
CPNET="$WS/cpnet-z80"                                         # upstream-tracked
Z80PACK_CPMSIM="$RC700/z80pack/cpmsim"
LIBRARY="$Z80PACK_CPMSIM/disks/library"
DISKDEFS="$RC700/rcbios/diskdefs"
export DISKDEFS

VCPM_JAR="$CPNET/tools/VirtualCpm.jar"
SERVER_ASM="$HERE/server.asm"

# --- args ---------------------------------------------------------------
OUT_DSK="/tmp/mpm-net2-1.dsk"
INSTALL_LOCAL=0
KEEP_STAGE=0
VERBOSE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o)        OUT_DSK="$2"; shift 2 ;;
        --install) INSTALL_LOCAL=1; shift ;;
        --keep)    KEEP_STAGE=1; shift ;;
        -v)        VERBOSE=1; shift ;;
        -h|--help)
            sed -n '2,38p' "$0"
            exit 0 ;;
        *)         echo "unknown arg: $1" >&2; exit 1 ;;
    esac
done
log() { echo "[rebuild-mpm-sys] $*"; }

[[ -f "$VCPM_JAR" ]]                              || { echo "missing $VCPM_JAR" >&2; exit 1; }
[[ -f "$LIBRARY/mpm-net2-1.dsk" ]]                || { echo "missing $LIBRARY/mpm-net2-1.dsk (z80pack pristine)" >&2; exit 1; }
[[ -f "$LIBRARY/mpm-net2-2.dsk" ]]                || { echo "missing $LIBRARY/mpm-net2-2.dsk (z80pack pristine)" >&2; exit 1; }
[[ -d "$DISKDEFS" ]] || [[ -f "$DISKDEFS" ]]      || { echo "missing diskdefs at $DISKDEFS" >&2; exit 1; }
command -v cpmcp >/dev/null                       || { echo "cpmtools (cpmcp) not in PATH" >&2; exit 1; }
command -v java  >/dev/null                       || { echo "java not in PATH" >&2; exit 1; }

# --- build stage --------------------------------------------------------
STAGE=$(mktemp -d -t rebuild-mpm-sys)
trap '[[ $KEEP_STAGE -eq 0 ]] && rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/build_a" "$STAGE/build_d"        # vcpm drives for rmac+link
mkdir -p "$STAGE/gensys_a"                        # vcpm drive for GENSYS
log "stage: $STAGE"

# --- step 1: rebuild server.rsp from this directory's PATCHED server.asm
# via vcpm rmac+link.  The rmac and link tools themselves come from
# the upstream-tracked cpnet-z80 submodule (pristine).  Only server.asm
# is project-side.
log "rebuild server.rsp from $SERVER_ASM"
cp "$CPNET/dist/vcpm/rmac.com" "$STAGE/build_a/"
cp "$CPNET/dist/vcpm/link.com" "$STAGE/build_a/"
awk 'BEGIN{RS="\n";ORS="\r\n"} {sub(/\r$/,""); print}' "$SERVER_ASM" \
    > "$STAGE/build_d/SERVER.ASM"
(
    export CPMDrive_A="$STAGE/build_a"
    export CPMDrive_D="$STAGE/build_d"
    export CPMDefault=d:
    java -jar "$VCPM_JAR" rmac server '$RDPDSZ' >"$STAGE/rmac.log" 2>&1 \
        || { tail "$STAGE/rmac.log"; exit 1; }
    java -jar "$VCPM_JAR" link 'server.rsp=server[os,nr]' >"$STAGE/link.log" 2>&1 \
        || { tail "$STAGE/link.log"; exit 1; }
)
[[ -f "$STAGE/build_d/server.rsp" ]] || { echo "server.rsp not produced" >&2; exit 1; }
log "server.rsp: $(wc -c < "$STAGE/build_d/server.rsp") bytes"

# --- step 2: stage every GENSYS input from the pristine library disk ----
log "stage GENSYS inputs from $LIBRARY/mpm-net2-2.dsk"
# GENSYS reads:
#   gensys.com itself
#   .RSP set     (resident system processes)
#   .SPR set     (BNK*, RES*, XDOS, TMP)
#   .BRS set     (banked-resident segments for SCHED/MPMSTAT/SPOOL)
#   system.dat   (default-value file)
GENSYS_INPUTS=(
    gensys.com
    abort.rsp sched.rsp spool.rsp mpmstat.rsp netwrkif.rsp server.rsp
    bnkbdos.spr bnkxdos.spr bnkxios.spr resbdos.spr resxios.spr xdos.spr tmp.spr
    mpmstat.brs sched.brs spool.brs
    system.dat
)
for f in "${GENSYS_INPUTS[@]}"; do
    UPPER=$(echo "$f" | tr '[:lower:]' '[:upper:]')
    cpmcp -f ibm-3740 "$LIBRARY/mpm-net2-2.dsk" "0:$f" "$STAGE/gensys_a/$UPPER" \
        2>/dev/null \
        || { echo "missing $f on mpm-net2-2.dsk" >&2; exit 1; }
done
# Substitute the freshly built server.rsp
cp "$STAGE/build_d/server.rsp" "$STAGE/gensys_a/SERVER.RSP"
log "staged $(ls "$STAGE/gensys_a" | wc -l | tr -d ' ') files (incl. fresh SERVER.RSP)"

# --- step 3: drive GENSYS via vcpm with the answer table ----------------
log "run GENSYS under vcpm"
# Answer table (must match cpnet/REBUILDING_MPM_SYS.md):
#   prompts 0..18 : accept defaults (empty line each)
#   prompts 19..24: Y to include all 6 RSPs (SPOOL, ABORT, SCHED, SERVER,
#                   NETWRKIF, MPMSTAT)
#   prompts 25..32: accept memory-segment-table defaults (8 lines)
#   prompt 33     : accept new memory segment table entries (Y default)
ANSWERS=()
for _ in $(seq 1 19); do ANSWERS+=(""); done
for _ in $(seq 1 6);  do ANSWERS+=("Y"); done
for _ in $(seq 1 9);  do ANSWERS+=(""); done

(
    export CPMDrive_A="$STAGE/gensys_a"
    export CPMDrive_D="$STAGE/gensys_a"     # GENSYS writes MPM.SYS to default drive
    export CPMDefault=a:
    printf '%s\n' "${ANSWERS[@]}" \
        | java -jar "$VCPM_JAR" gensys >"$STAGE/gensys.log" 2>&1
)
if ! grep -q '\*\* GENSYS DONE \*\*' "$STAGE/gensys.log"; then
    echo "GENSYS did not complete — last 40 lines of log:" >&2
    tail -40 "$STAGE/gensys.log" >&2
    exit 1
fi
[[ -f "$STAGE/gensys_a/MPM.SYS" ]] || { echo "MPM.SYS not produced" >&2; exit 1; }
NEW_SIZE=$(wc -c < "$STAGE/gensys_a/MPM.SYS")
log "MPM.SYS: $NEW_SIZE bytes"

# Sanity: the pristine MPM.SYS is ~42 KB.  Anything dramatically smaller
# means GENSYS ran but didn't include the bank/resident segments.
if [[ "$NEW_SIZE" -lt 40000 ]]; then
    echo "WARNING: MPM.SYS is only $NEW_SIZE bytes — pristine is ~42 KB." >&2
    echo "         GENSYS log tail:" >&2
    tail -20 "$STAGE/gensys.log" >&2
    exit 1
fi

# --- step 4: patch the new MPM.SYS onto a fresh boot disk ---------------
log "patch boot disk"
cp "$LIBRARY/mpm-net2-1.dsk" "$OUT_DSK"
cpmrm -f ibm-3740 "$OUT_DSK" 0:mpm.sys 2>/dev/null || true
cpmcp -f ibm-3740 "$OUT_DSK" "$STAGE/gensys_a/MPM.SYS" 0:mpm.sys
# Round-trip verify
tmp_verify=$(mktemp)
cpmcp -f ibm-3740 "$OUT_DSK" 0:mpm.sys "$tmp_verify"
cmp -s "$tmp_verify" "$STAGE/gensys_a/MPM.SYS" \
    || { echo "round-trip cmp failed" >&2; rm -f "$tmp_verify"; exit 1; }
rm -f "$tmp_verify"
log "wrote $OUT_DSK ($(wc -c < "$OUT_DSK") bytes)"

if [[ "$INSTALL_LOCAL" -eq 1 ]]; then
    # Install to disks/local/ (sibling of disks/library/), which the
    # mpm-net2 launcher prefers over the pristine library disk.
    # This keeps z80pack's tracked library files unchanged.
    LOCAL_DIR="$Z80PACK_CPMSIM/disks/local"
    mkdir -p "$LOCAL_DIR"
    cp "$OUT_DSK" "$LOCAL_DIR/mpm-net2-1.dsk"
    log "installed to $LOCAL_DIR/mpm-net2-1.dsk"
    log "(launcher cpmsim/mpm-net2 prefers this over disks/library)"
fi

if [[ "$KEEP_STAGE" -eq 1 ]]; then
    log "kept stage: $STAGE"
fi
log "done."
