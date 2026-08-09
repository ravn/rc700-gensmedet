#!/usr/bin/env bash
#
# End-to-end pipeline for the ravn/z88dk#36 on-disk checksum verification.
#
#   prog.c  ->  PROG.COM  ->  bootable rc700-8dd IMD (licensed boot region
#   spliced via -s)  ->  boot in MAME on A:  ->  run PROG  ->  compare the two
#   independent checksums (CRC-32 + FNV-1a-32) against host references computed
#   over (a) the deterministic in-memory array and (b) the exact on-disk bytes.
#
# This is a MULTI-STEP pipeline, not a single compile. It also requires the
# licensed reference system image SW1711-I8.imd for the boot region: without
# -s the disk is a non-bootable data diskette (tracks 0/1 zero-filled).
#
# Usage:
#   ./build_and_verify.sh [ARRAY_SIZE] [--mame]
#     ARRAY_SIZE : big[] payload size (default 40000 -> ~48 KB, 3 extents).
#                  0 = tiny single-extent tool.
#     --mame     : also boot in MAME and check the on-disk result (slow, ~1 min
#                  wall / ~200 s simulated). Omit for a fast host-only check.
#
# Host tool paths are overridable via env (defaults are the macbook layout):
#   Z88DK_BIN, ZCCCFG, WS (workspace root), MAME_BIN, REF_IMD
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS="${WS:-$(cd "$HERE/../../.." && pwd)}"                 # workspace root
Z88DK="${Z88DK:-$WS/z88dk}"
export PATH="${Z88DK_BIN:-$Z88DK/bin}:$PATH"
export ZCCCFG="${ZCCCFG:-$Z88DK/lib/config}"
APPMAKE="${APPMAKE:-$Z88DK/bin/z88dk-appmake}"
REF_IMD="${REF_IMD:-$WS/rc700-gensmedet/autoload-in-c/test-disks/SW1711-I8.imd}"
IMD2RAW="${IMD2RAW:-$WS/rc700-gensmedet/rcbios/imd2raw.py}"
MAME_BIN="${MAME_BIN:-$WS/mame/regnecentralend}"
MAME_ROMS="${MAME_ROMS:-$WS/mame/roms}"

ARRAY_SIZE="${1:-40000}"
RUN_MAME=0
[ "${2:-}" = "--mame" ] && RUN_MAME=1
[ "${1:-}" = "--mame" ] && { RUN_MAME=1; ARRAY_SIZE=40000; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
echo ">> workspace=$WS  array_size=$ARRAY_SIZE  work=$WORK"

# 1) generate the dual-checksum tool
python3 "$HERE/gen_prog.py" "$ARRAY_SIZE" > "$WORK/prog.c"

# 2) extract the licensed boot region (tracks 0-1) from the reference system disk
python3 "$IMD2RAW" "$REF_IMD" "$WORK/bootregion.bin" 2 >/dev/null
echo ">> boot region = $(wc -c < "$WORK/bootregion.bin") bytes (from $(basename "$REF_IMD"))"

# 3) compile AND build the bootable rc700-8dd IMD in a single zcc invocation.
#    zcc's -create-app stage drives z88dk-appmake directly: the -Cz... options
#    are forwarded to appmake (+cpmdisk), so we get PROG.COM + prog.imd at once.
#    (Verified 2026-08-09: the IMD payload is byte-identical to a standalone
#     `z88dk-appmake +cpmdisk ...` call; only the IMD header timestamp differs.)
#    -o prog  =>  on-disk file is PROG.COM (matches the tool's self-check default)
#    and prog.imd is the bootable image. The rc700 subtype has no disk line, so
#    the format (-f rc700-8dd) is given explicitly. All appmake args go in a
#    single quoted -Cz"..." (space-separated) rather than one -Cz per token.
( cd "$WORK" && zcc +cpm -subtype=rc700 -O2 prog.c -o prog -create-app \
      -Cz"+cpmdisk -f rc700-8dd --container=imd -s $WORK/bootregion.bin" )
cp "$WORK/prog.imd" "$WORK/bootprog.imd"
echo ">> PROG.COM = $(wc -c < "$WORK/PROG.COM") bytes ; built $WORK/bootprog.imd"

# 4) host references
echo "== host reference: in-memory array big[] =="
python3 - "$ARRAY_SIZE" <<'PY'
import sys, zlib
N = int(sys.argv[1])
if N == 0:
    print("(no array)"); raise SystemExit
vals = bytes((i * 31 + 7) & 0xFF for i in range(N))
h = 2166136261
for b in vals: h ^= b; h = (h * 16777619) & 0xFFFFFFFF
print("ABYTES=%08X  ACRC32=%08X  AFNV32=%08X" % (N, zlib.crc32(vals) & 0xFFFFFFFF, h))
PY
echo "== host reference: on-disk file PROG.COM =="
python3 "$HERE/cpmref.py" "$WORK/bootprog.imd" PROG.COM

# 5) optional: boot in MAME and show what PROG actually printed on A:
if [ "$RUN_MAME" = 1 ]; then
    echo "== MAME rc702 (boot on A:, run PROG) -- this is slow =="
    rm -f /tmp/screen.txt
    "$MAME_BIN" rc702 -rompath "$MAME_ROMS" -bios 0 -window -skip_gameinfo \
        -nothrottle -sound none -flop1 "$WORK/bootprog.imd" \
        -autoboot_script "$HERE/mame_run.lua" -seconds_to_run 220 >/dev/null 2>&1 || true
    grep -v '^ *$' /tmp/screen.txt 2>/dev/null || echo "(no screen captured)"
else
    echo "(skip MAME; pass --mame to boot and verify on A:)"
fi
echo ">> done"
