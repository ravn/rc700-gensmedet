# MAME video capture scratch directory

Holds the most recent **50** MP4 captures of MAME RC702 runs.  Pruning
is automatic: every invocation of `scripts/mame_capture.sh` removes
older files beyond `MAX_KEEP` (default 50).

## Format

Files are H.264-encoded MP4 at the emulated CRT frame rate (~50 Hz for
RC702 i8275).  Naming: `YYYYMMDDTHHMMSS_<description-slug>.mp4`.

MP4 was chosen so macOS Finder QuickLook + Preview + QuickTime Player
all open the file with a double-click; no VLC, no transcoding step.

## Pipeline (per run)

    MAME -aviwrite <stem>.avi    # raw 4:2:2; ~18 MB/s
    docker ffmpeg AVI -> MP4     # h264 -preset fast -crf 23
    rm <stem>.avi                # the AVI is throwaway

50 typical 50-sec runs of cpnos boot + idle CCP fit in single-digit
MB total because RC702 displays are mostly static text.

## Usage

    scripts/mame_capture.sh <description-slug> -- <mame args...>

See the script for envvars (`MAX_KEEP`, `MAME_VIDEO_DIR`,
`FFMPEG_IMAGE`).

## Not tracked in git

These are throwaway artifacts.  Listed in `.gitignore`.
