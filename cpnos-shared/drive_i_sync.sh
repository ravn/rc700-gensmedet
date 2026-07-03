#!/bin/sh
# drive_i_sync.sh {to-disk|from-disk} FOLDER DISK
#
# Sync the canonical drive-I: tool folder (= slave E:) with a z80pack-hd
# disk image, in either direction:
#
#   to-disk    populate DISK from FOLDER (each regular file; skip README/
#              dotfiles).  Used by `make stage-drivei-tools` after the disk
#              is recreated blank.
#   from-disk  merge DISK back into FOLDER -- extract every file and write
#              it into FOLDER with an UPPERCASE name (CP/M convention), so
#              the round-trip is stable on both case-insensitive (macOS) and
#              case-sensitive (Linux) filesystems.  Used by
#              `make sync-drivei-back` to capture anything the slave created
#              or modified on E: (compiled .REL/.COM, saved sources, etc.).
#
# cpmtools note: cpmcp/cpmls on z80pack-hd images often exit 139 (segfault)
# on cleanup AFTER the transfer has completed successfully, so all cpm* calls
# are `|| true` and success is judged by the resulting files, not the rc.
set -eu

mode=${1:?usage: drive_i_sync.sh to-disk|from-disk FOLDER DISK}
folder=${2:?missing FOLDER}
disk=${3:?missing DISK}

case "$mode" in
  to-disk)
    [ -d "$folder" ] || { echo "drive_i_sync: FOLDER '$folder' not found" >&2; exit 1; }
    [ -f "$disk" ]   || { echo "drive_i_sync: DISK '$disk' not found" >&2; exit 1; }
    for src in "$folder"/*; do
      [ -f "$src" ] || continue
      base=$(basename "$src")
      case "$base" in README*|readme*|.*) continue;; esac
      cpmcp -f z80pack-hd "$disk" "$src" "0:$base" >/dev/null 2>&1 || true
    done
    ;;
  from-disk)
    [ -d "$folder" ] || { echo "drive_i_sync: FOLDER '$folder' not found" >&2; exit 1; }
    [ -f "$disk" ]   || { echo "drive_i_sync: DISK '$disk' not found" >&2; exit 1; }
    tmp=$(mktemp -d)
    cpmcp -f z80pack-hd "$disk" '0:*.*' "$tmp/" >/dev/null 2>&1 || true
    n=0
    for f in "$tmp"/*; do
      [ -f "$f" ] || continue
      up=$(basename "$f" | tr 'a-z' 'A-Z')
      cp "$f" "$folder/$up"
      n=$((n + 1))
    done
    rm -rf "$tmp"
    echo "drive_i_sync: merged $n file(s) from $disk into $folder"
    ;;
  *)
    echo "drive_i_sync: unknown mode '$mode' (want to-disk|from-disk)" >&2
    exit 1
    ;;
esac
