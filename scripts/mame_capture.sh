#!/bin/sh
# Wrapper that runs MAME with an AVI capture, then encodes the AVI to
# MP4 (h264) via dockerised ffmpeg.  Output lands in
# scratch/mame-videos/<TIMESTAMP>_<description>.mp4 -- MP4 plays in
# macOS QuickTime / Preview / Finder QuickLook without further work.
#
# Usage:
#     mame_capture.sh <description-slug> -- <mame args...>
#
# Example:
#     mame_capture.sh cpnos_da_US_typeascii \
#         -- rc702 -rompath roms -nothrottle -window -skip_gameinfo \
#                  -seconds_to_run 50 -autoboot_script test.lua
#
# Why MP4 and not MAME's native MNG: MNG plays in VLC but ffmpeg doesn't
# demux MNG (libavformat has no MNG demuxer), so we can't transcode it
# to a macOS-friendly format on the fly.  MAME's MNG is also not
# QuickTime-compatible.  AVI is raw RGB and large (~18 MB/s) but h264
# turns RC702 screens (mostly static text) into ~4 KB/s MP4s.
#
# Pipeline:
#     MAME -aviwrite scratch/...tmp.avi
#     dockerised ffmpeg: AVI -> MP4 h264 yuv420p
#     rm AVI
#     prune scratch/mame-videos/ to MAX_KEEP newest MP4s
#
# Disk envelope (rough): 50 typical 50-sec runs of cpnos boot+CCP idle
# fit in a few MB of MP4 total.

set -e

DESC=$1
if [ -z "$DESC" ] || [ "$2" != "--" ]; then
    echo "usage: $0 <description-slug> -- <mame args...>" >&2
    exit 2
fi
shift 2

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
MAME_BIN=${MAME_BIN:-/Users/ravn/z80/mame/regnecentralend}

# Video capture is OFF by default (2026-07-12): the raw AVI staging files
# (~18 MB/s) filled the disk when MAME was killed mid-run before ffmpeg could
# transcode+delete them, which crashed the machine. Re-enable per-invocation
# with MAME_CAPTURE=1. When disabled we still run MAME (with -sound none) so
# every existing caller keeps working, just without the AVI/ffmpeg pipeline.
if [ "${MAME_CAPTURE:-0}" != "1" ]; then
    echo "[mame_capture] capture disabled (set MAME_CAPTURE=1 to record)" >&2
    exec "$MAME_BIN" -sound none "$@"
fi
MAME_VIDEO_DIR=${MAME_VIDEO_DIR:-$REPO_ROOT/scratch/mame-videos}
MAX_KEEP=${MAX_KEEP:-50}
FFMPEG_IMAGE=${FFMPEG_IMAGE:-jrottenberg/ffmpeg:7-alpine}

mkdir -p "$MAME_VIDEO_DIR"

TS=$(date +%Y%m%dT%H%M%S)
SAFE_DESC=$(printf '%s' "$DESC" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9._-' '_')
STEM="${TS}_${SAFE_DESC}"
AVI_TMP="$MAME_VIDEO_DIR/$STEM.avi"
MP4_OUT="$MAME_VIDEO_DIR/$STEM.mp4"

echo "[mame_capture] AVI staging -> $AVI_TMP"
# -sound none: motor sounds annoy the user AND CoreAudio's pipe
# semantics cause SIGPIPE (exit 141) crashes under sustained
# background-test load.  No test in this project evaluates audio.
# See tasks/memory/feedback_disable_audio_in_tests.md.
"$MAME_BIN" -sound none -aviwrite "$AVI_TMP" "$@"
RC=$?

if [ -s "$AVI_TMP" ]; then
    echo "[mame_capture] encoding -> $MP4_OUT"
    # Scale the raw screen capture (i8275 native 544x200 + overscan,
    # nominally arriving as 568x212 in the AVI) up to the layout's
    # display geometry 864x550, then pad to the full 904x590 layout
    # view with the RC702 bezel orange (#C06000).  Mirrors what MAME
    # shows live via mame/src/mame/layout/rc702.lay: 20-px border
    # around the screen, background color
    # rgb(0xC0, 0x60, 0x00) = "red=0.7529 green=0.3765 blue=0.0".
    # Without the pad, the MP4 was just the screen area -- the
    # physical-monitor look got lost in capture.
    docker run --rm -v "$MAME_VIDEO_DIR:/work" "$FFMPEG_IMAGE" \
        -y -loglevel warning \
        -i "/work/$STEM.avi" \
        -vf "scale=864:550:flags=lanczos,pad=904:590:20:20:0xC06000" \
        -c:v libx264 -preset fast -crf 23 -pix_fmt yuv420p \
        "/work/$STEM.mp4" || {
            echo "[mame_capture] ffmpeg failed; keeping AVI for triage" >&2
            exit $RC
        }
    rm -f "$AVI_TMP"
    echo "[mame_capture] capture $(du -h "$MP4_OUT" | cut -f1) -> $MP4_OUT"
else
    echo "[mame_capture] no AVI produced (size 0); skipping encode" >&2
    rm -f "$AVI_TMP"
fi

# Prune to the last MAX_KEEP MP4 files (sorted by mtime).
# `ls -t` lists newest first; `tail -n +N+1` skips the keepers.
ls -t "$MAME_VIDEO_DIR"/*.mp4 2>/dev/null | tail -n +$((MAX_KEEP + 1)) | while read -r old; do
    echo "[mame_capture] pruning $old"
    rm -f "$old"
done

exit $RC
