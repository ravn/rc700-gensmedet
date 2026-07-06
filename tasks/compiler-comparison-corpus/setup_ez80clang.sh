#!/usr/bin/env bash
# setup_ez80clang.sh -- stage CEdev's `ez80-clang` (CE-Programming/toolchain)
# as the corpus sweep's 6th, CODE-QUALITY-ONLY oracle and symlink it into
# $Z88DK/bin so `zcc +cpm -compiler=ez80clang` can find it.  See
# EZ80CLANG_ORACLE_SETUP.md for the full rationale + the two clang_rules.1
# fixes CEdev v15.0 needs (those live in the z88dk repo, already committed).
#
# ez80-clang is NOT built by z88dk and is NOT built from source here: per the
# z88dk wiki (Clang-support) you copy CEdev/bin/ez80-clang out of a prebuilt
# CE-Programming/toolchain release.  It is a SelectionDAG eZ80 LLVM fork whose
# `-triple z80` sub-target emits genuine 16-bit z80 code; we use it only to
# compare code quality (size/speed), never as a runtime-correctness oracle.
#
# Usage:
#   ./setup_ez80clang.sh                # latest release, auto OS/arch
#   CEDEV_TAG=v15.0 ./setup_ez80clang.sh
#   CEDEV_DIR=/path ./setup_ez80clang.sh   # staging parent (default below)
#
# Requires: gh (authenticated).  macOS (DMG) + Linux (tar.gz).
set -euo pipefail

REPO=CE-Programming/toolchain
CEDEV_DIR="${CEDEV_DIR:-/Users/ravn/z80/cedev-eval}"   # macbook default
CEDEV_TAG="${CEDEV_TAG:-}"                              # empty = latest
Z88DK="${Z88DK:-/Users/ravn/z80/z88dk}"

# CEdev release assets: CEdev-Linux.tar.gz, CEdev-macOS-arm.dmg,
# CEdev-macOS-intel.dmg, CEdev-Windows.zip.
case "$(uname -s)" in
  Darwin)
    case "$(uname -m)" in
      arm64) ASSET=CEdev-macOS-arm.dmg ;;
      *)     ASSET=CEdev-macOS-intel.dmg ;;
    esac ;;
  Linux) ASSET=CEdev-Linux.tar.gz ;;
  *) echo "setup_ez80clang: unsupported OS $(uname -s)" >&2; exit 2 ;;
esac

mkdir -p "$CEDEV_DIR"
cd "$CEDEV_DIR"

if [ -z "$CEDEV_TAG" ]; then
  CEDEV_TAG=$(gh release view --repo "$REPO" --json tagName --jq '.tagName')
fi
echo "setup_ez80clang: fetching $ASSET from $REPO $CEDEV_TAG -> $CEDEV_DIR"
gh release download "$CEDEV_TAG" --repo "$REPO" --pattern "$ASSET" --clobber

case "$ASSET" in
  *.dmg)
    # HARD RULE: never let a mount land in /Volumes (the workspace-search hook
    # blocks inspecting it and it forces iCloud downloads).  Mount at a
    # workspace-internal mountpoint, copy the tree out, detach.
    MNT="$CEDEV_DIR/.mnt"
    rm -rf "$MNT"; mkdir -p "$MNT"
    hdiutil attach "$ASSET" -nobrowse -readonly -mountpoint "$MNT" >/dev/null
    rm -rf "$CEDEV_DIR/CEdev"
    cp -R "$MNT/CEdev" "$CEDEV_DIR/CEdev"
    hdiutil detach "$MNT" >/dev/null
    rmdir "$MNT" 2>/dev/null || true
    # macOS quarantines downloaded binaries; clear it so the binary runs.
    xattr -dr com.apple.quarantine "$CEDEV_DIR/CEdev" 2>/dev/null || true
    ;;
  *.tar.gz)
    rm -rf "$CEDEV_DIR/CEdev"
    tar -xzf "$ASSET"          # unpacks a top-level CEdev/
    ;;
esac

BIN="$CEDEV_DIR/CEdev/bin/ez80-clang"
[ -x "$BIN" ] || { echo "setup_ez80clang: ez80-clang not found at $BIN" >&2; exit 1; }

# Symlink into $Z88DK/bin so `zcc +cpm -compiler=ez80clang` (which PATH-searches
# EZ80CLANGEXE=ez80-clang) finds it.  z88dk makes NO changes to the compiler.
ln -sfn "$BIN" "$Z88DK/bin/ez80-clang"

echo "setup_ez80clang: installed -> $BIN"
echo "setup_ez80clang: symlinked -> $Z88DK/bin/ez80-clang"
"$BIN" --version | head -2
echo "setup_ez80clang: OK.  The clang_rules.1 fixes for CEdev v15.0 are already"
echo "  committed in the z88dk repo (branch rc700-gensmedet-1); if you use a"
echo "  different CEdev version, re-check EZ80CLANG_ORACLE_SETUP.md section 2."
