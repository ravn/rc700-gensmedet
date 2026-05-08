#!/bin/sh
#
# regen_buildinfo.sh OUT_HEADER
#
# Regenerate cpnos_buildinfo.h with the current UTC date + short git
# hash, but only update the file's mtime when the content actually
# differs from what's on disk.  Called from cpnos-rom/Makefile via
# $(shell ...) at parse time so the .h's mtime tracks REAL content
# changes -- a Makefile recipe with `.PHONY` would mark the target
# "always out of date" and propagate that to every dependent .o /
# audit .s, forcing a slow full rebuild on every `make` invocation.
#
# Stays a separate script (not inline shell in $(shell)) so Make's
# paren / brace counter doesn't trip on the `{ ... }` shell block.

set -e

OUT="$1"
[ -z "$OUT" ] && { echo "usage: $0 <out-header>" >&2; exit 2; }

D=$(date -u +'%Y-%m-%d %H:%M')
H=$(git rev-parse --short HEAD 2>/dev/null || echo '????')
if ! git diff --quiet -- . 2>/dev/null; then H="${H}+"; fi

TMP="${OUT}.tmp"
mkdir -p "$(dirname "$OUT")"
{
    echo '#ifndef CPNOS_BUILDINFO_H'
    echo '#define CPNOS_BUILDINFO_H'
    printf '#define BUILD_DATE_STR "%s"\n' "$D"
    printf '#define GIT_HASH_STR   "%s"\n' "$H"
    echo '#define BUILD_INFO_STR BUILD_DATE_STR " " GIT_HASH_STR'
    echo '#endif'
} > "$TMP"

if cmp -s "$TMP" "$OUT" 2>/dev/null; then
    rm -f "$TMP"
else
    mv "$TMP" "$OUT"
    echo "buildinfo: $D $H" >&2
fi
