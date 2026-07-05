#!/usr/bin/env bash
# setup_xcc.sh -- fetch the XYZ Suite `xcc` Z80 C toolchain (retro-vault/xyz)
# and stage it where the corpus sweep expects it.  xcc is a candidate 5th
# oracle: an independent SDCC-ABI Z80 C compiler that emits real CP/M .COM
# programs (see XCC_ORACLE_SETUP.md for how the sweep drives it).
#
# We install a prebuilt release ZIP (no from-source build needed).  xcc is
# NOT yet a git submodule -- deliberately, while we evaluate it -- so this
# script is the reproducible "get it in the air" step.
#
# Usage:
#   ./setup_xcc.sh                 # latest release, L model, auto OS
#   XCC_MODEL=m ./setup_xcc.sh     # smaller libc (s|m|l; default l = full stdio)
#   XCC_TAG=v1.9.4 ./setup_xcc.sh  # pin a release tag (default: latest)
#   XCC_DIR=/path ./setup_xcc.sh   # install prefix parent (default below)
#
# Requires: gh (authenticated), unzip.  macOS + Linux.
set -euo pipefail

REPO=retro-vault/xyz
XCC_DIR="${XCC_DIR:-/Users/ravn/z80/xyz-eval}"   # macbook default; sonnyboy sed-rewrites
XCC_MODEL="${XCC_MODEL:-l}"                       # s=small, m=medium, l=large(full libc)
XCC_TAG="${XCC_TAG:-}"                            # empty = latest

case "$(uname -s)" in
  Darwin) OS=macos ;;
  Linux)  OS=linux ;;
  *) echo "setup_xcc.sh: unsupported OS $(uname -s)" >&2; exit 2 ;;
esac

case "$XCC_MODEL" in s|m|l) ;; *) echo "XCC_MODEL must be s|m|l" >&2; exit 2 ;; esac

ASSET="x-${XCC_MODEL}-${OS}.zip"
mkdir -p "$XCC_DIR"
cd "$XCC_DIR"

if [ -z "$XCC_TAG" ]; then
  XCC_TAG=$(gh release view --repo "$REPO" --json tagName --jq '.tagName')
fi
echo "setup_xcc: fetching $ASSET from $REPO $XCC_TAG -> $XCC_DIR"

gh release download "$XCC_TAG" --repo "$REPO" --pattern "$ASSET" --clobber

DEST="x-${XCC_MODEL}"
rm -rf "$DEST"
mkdir -p "$DEST"
unzip -q "$ASSET" -d "$DEST"

# The zip contains a single top dir "x-<model>-<os>/"; expose a stable
# symlink "xcc-current" -> that prefix so the sweep has one fixed path.
PREFIX="$XCC_DIR/$DEST/x-${XCC_MODEL}-${OS}"
[ -x "$PREFIX/bin/xcc" ] || { echo "setup_xcc: xcc not found at $PREFIX/bin" >&2; exit 1; }
ln -sfn "$PREFIX" "$XCC_DIR/xcc-current"

echo "setup_xcc: installed -> $XCC_DIR/xcc-current"
"$XCC_DIR/xcc-current/bin/xcc" --version
echo "setup_xcc: OK.  Point the sweep at XCC_PREFIX=$XCC_DIR/xcc-current"
