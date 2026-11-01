#!/bin/sh
# Build all RC759 variants by default, or one explicitly selected variant.

set -eu
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
exec python3 "$SCRIPT_DIR/build_emu2_current.py" "$@"
