#!/bin/sh
# Build an RC702 8" DSDD MFI floppy image from a directory of files.
#
# Usage:
#   mkmfidisk.sh <source_dir> <output.mfi> [label]
#
# Workflow:
#   1. mkfs.cpm creates a blank CP/M 8" DSDD image (rc702-8dd diskdef).
#   2. cpmcp copies every regular file from <source_dir> onto drive 0:
#      (8.3 name truncation applied by cpmcp).
#   3. Pad to full geometry (1,182,720 bytes = 77 tracks × 2 sides ×
#      15 sectors × 512 bytes) so the IMD converter sees a complete
#      disk.  mkfs.cpm only writes up to the last allocated block.
#   4. Inline Python emits an IMD v1.18 file wrapping the raw sectors.
#      Each of 154 track/side groups is 15 sectors × 512 B MFM at
#      500 kbps (mode byte 0x03).  This geometry matches the
#      rc702-8dd diskdef exactly — no mixed-density Track 0.
#   5. MAME floptool converts IMD → MFI.  IMD is read-only under
#      MAME, so the MFI is the format the RC702 driver can actually
#      mount read/write.
#
# Requirements (in PATH or at known locations):
#   - mkfs.cpm, cpmcp                              (cpmtools)
#   - python3
#   - /Users/ravn/git/mame/floptool                (MAME tooling)
#   - Diskdefs from rc700-gensmedet/rcbios/diskdefs (via DISKDEFS env var)
#
# Deliberate limitation: writes every file in <source_dir> onto drive 0:
# user 0 with no filtering.  Sub-directories are ignored.
set -e

SRC="$1"
OUT="$2"
LABEL="${3:-ACCEPT}"

[ -n "$SRC" ] && [ -n "$OUT" ] || {
    echo "usage: $0 <source_dir> <output.mfi> [label]" >&2
    exit 1
}
[ -d "$SRC" ] || { echo "not a directory: $SRC" >&2; exit 1; }

HERE=$(cd "$(dirname "$0")" && pwd)
DISKDEFS="$HERE/../../rcbios/diskdefs"
MAME_DIR="/Users/ravn/git/mame"

[ -f "$DISKDEFS" ] || {
    echo "diskdefs not found: $DISKDEFS" >&2
    exit 1
}
[ -x "$MAME_DIR/floptool" ] || {
    echo "MAME floptool not found or not executable: $MAME_DIR/floptool" >&2
    exit 1
}

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

RAW="$TMP/raw.img"
IMD="$TMP/disk.imd"

# 1+2. Blank CP/M image + copy files
DISKDEFS="$DISKDEFS" mkfs.cpm -f rc702-8dd -L "$LABEL" "$RAW"
# Only regular files, skip sub-dirs; split into chunks to avoid argv blow-up
find "$SRC" -maxdepth 1 -type f -print0 \
    | xargs -0 -I{} sh -c 'DISKDEFS="$0" cpmcp -f rc702-8dd "$1" "{}" 0:' \
        "$DISKDEFS" "$RAW"

# 3. Pad to full geometry
FULL_BYTES=$((77 * 2 * 15 * 512))
CURRENT=$(wc -c < "$RAW" | tr -d ' ')
if [ "$CURRENT" -lt "$FULL_BYTES" ]; then
    dd if=/dev/zero of="$RAW" bs=1 count=0 seek="$FULL_BYTES" 2>/dev/null
fi

# 4. raw → IMD.  bin2imd.py auto-detects RC702 maxi by size
# (1,182,720 bytes) and emits uniform MFM 500kbps, 15×512 per side.
python3 "$HERE/../../rcbios/bin2imd.py" "$RAW" "$IMD"

# 5. IMD → MFI via floptool
"$MAME_DIR/floptool" flopconvert imd mfi "$IMD" "$OUT"
echo "wrote $OUT"
