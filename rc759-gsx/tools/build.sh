#!/bin/sh
# Build dd759h1.sys with current emu2 using a controlling PTY.

set -eu
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
exec python3 "$SCRIPT_DIR/build_emu2_current.py"
