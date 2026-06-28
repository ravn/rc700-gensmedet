#!/usr/bin/env bash
#
# cross-version-boot-test.sh — pre-merge boot-interop gate for the RC702
# autoload PROM (autoload-in-c) and the clang C BIOS (rcbios-in-c).
#
# WHY: the PROM and the BIOS ship as independent artifacts that meet only at
# runtime.  A change to either must not break boot against the OTHER side's
# *unmodified* counterpart, and must boot in BOTH SW1-S01 switch positions.
# This encodes three standing acceptance facts (see tasks/memory/):
#   1. rcbios + the ORIGINAL roa375.rom must boot to A> in BOTH switch positions.
#   2. The clang autoload PROM must boot the ORIGINAL/stock unmodified BIOS
#      (the as-shipped CCP+BDOS+BIOS on the stock image) in BOTH positions.
#   3. The autoload PROM must fit in 2 KB (PROM0 hard cap).
#
# The 4-way matrix (PROM paired with its cross-version counterpart BIOS):
#   A.  original roa375.rom  + clang rcbios disk   x {S01 On, S01 Off}
#   B.  clang autoload PROM  + stock unpatched disk x {S01 On, S01 Off}
# PASS only if all 4 reach the CP/M `A>` prompt (screen-scanned by
# mame_boot_test.lua) AND the autoload PROM fits 2 KB.
#
# Switch position is forced rule-compliantly via the :DSW ioport field
# (SW1_S01 env -> mame_boot_test.lua), never an I/O read tap.
#
# Usage:  bash tasks/scripts/cross-version-boot-test.sh
# Env:    MAME=<dir>  BOOT_TIMEOUT_S=<n>  KEEP_TMP=1
set -u

# --- locate the repo root (this script lives in <root>/tasks/scripts/) --------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"          # rc700-gensmedet/
AUTOLOAD="$ROOT/autoload-in-c"
RCBIOS="$ROOT/rcbios-in-c"
MAME="${MAME:-$ROOT/../mame}"
MAME_BIN="$MAME/mame"
MAME_ROM="$MAME/roms/rc702/roa375.ic66"
LUA="$AUTOLOAD/mame_boot_test.lua"
BOOT_TIMEOUT_S="${BOOT_TIMEOUT_S:-60}"

ORIG_PROM="$ROOT/roa375/roa375.rom"              # genuine 2 KB ROA375 dump
STOCK_DISK="$AUTOLOAD/test-disks/SW1711-I8.imd"  # in-tree pristine stock image

WORK="$(mktemp -d)"
RESULT="$WORK/boot_result.txt"
PROM_BACKUP="$WORK/roa375.ic66.bak"
trap '[ -f "$PROM_BACKUP" ] && cp "$PROM_BACKUP" "$MAME_ROM"; [ -n "${KEEP_TMP:-}" ] || rm -rf "$WORK"' EXIT

say() { printf '\n=== %s ===\n' "$*"; }
fail() { printf 'FATAL: %s\n' "$*" >&2; exit 2; }

[ -x "$MAME_BIN" ] || fail "MAME binary not found: $MAME_BIN (set MAME=<dir>)"
[ -f "$ORIG_PROM" ] || fail "original PROM not found: $ORIG_PROM"
[ -f "$STOCK_DISK" ] || fail "stock disk not found: $STOCK_DISK"
[ -f "$MAME_ROM" ] && cp "$MAME_ROM" "$PROM_BACKUP"

# --- 1. build both sides' clang artifacts ------------------------------------
say "Building clang autoload PROM"
make -C "$AUTOLOAD" prom COMPILER=clang >"$WORK/build_autoload.log" 2>&1 \
    || { cat "$WORK/build_autoload.log"; fail "autoload PROM build failed"; }
CLANG_PROM="$AUTOLOAD/clang/prom0.ic66"          # 4 KB-padded MAME slot image
[ -f "$CLANG_PROM" ] || fail "clang PROM image missing: $CLANG_PROM"

say "Building clang rcbios BIOS"
make -C "$RCBIOS" bios COMPILER=clang >"$WORK/build_rcbios.log" 2>&1 \
    || { cat "$WORK/build_rcbios.log"; fail "rcbios BIOS build failed"; }
BIOS_CIM="$RCBIOS/clang/bios.clang.cim"
[ -f "$BIOS_CIM" ] || fail "clang BIOS .cim missing: $BIOS_CIM"

# --- 2. acceptance fact #3: autoload fits 2 KB --------------------------------
# prom0.ic66 is 0xFF-padded to 4096 for the MAME slot; the real payload is the
# raw clang PROM.  Assert the raw image is <= 2048 B.
RAW_PROM="$AUTOLOAD/clang/prom.clang.bin"
PROM2K="PASS"
if [ -f "$RAW_PROM" ]; then
    SZ=$(wc -c < "$RAW_PROM" | tr -d ' ')
    if [ "$SZ" -gt 2048 ]; then PROM2K="FAIL ($SZ B > 2048)"; else PROM2K="PASS ($SZ B <= 2048, $((2048-SZ)) B free)"; fi
else
    PROM2K="SKIP (raw image $RAW_PROM not found)"
fi

# --- 3. prepare the cross-version disks/PROMs ---------------------------------
say "Preparing matrix artifacts"
# A: original PROM padded to 4096 for the roa375.ic66 slot.  The MAME slot is
# a 0x1000-byte file format (ROMX_LOAD ... 0x1000); the genuine ROA375 dump is
# 2 KB, so the high half is 0xFF (ROMREGION_ERASEFF).  Use the SAME perl idiom
# as autoload-in-c/Makefile's `prom` target -- BSD `tr` mangles byte counts.
ORIG_PROM_PADDED="$WORK/roa375_orig.ic66"
{ cat "$ORIG_PROM"; \
  perl -e "print \"\\xff\" x (4096 - $(wc -c < "$ORIG_PROM" | tr -d ' '))"; \
} > "$ORIG_PROM_PADDED"

# A: clang rcbios disk = stock image with track-0 INIT+BIOS patched in.
CLANG_DISK="$WORK/clang_rcbios.imd"
cp "$STOCK_DISK" "$CLANG_DISK"
python3 "$RCBIOS/../rcbios/patch_bios.py" "$CLANG_DISK" "$BIOS_CIM" \
    >"$WORK/patch.log" 2>&1 || { cat "$WORK/patch.log"; fail "patch_bios.py failed"; }

# B uses the clang autoload PROM + the unpatched STOCK_DISK directly.

# --- 4. boot helper -----------------------------------------------------------
# $1 label  $2 prom-file  $3 disk  $4 SW1_S01 (0=On 1=Off)
declare -a ROWS
overall=0
run_boot() {
    local label="$1" prom="$2" disk="$3" s01="$4"
    cp "$prom" "$MAME_ROM"
    rm -f "$RESULT"
    local pos; [ "$s01" = "1" ] && pos="Off" || pos="On"
    printf '  -> %-34s SW1-S01=%s ... ' "$label" "$pos"
    SW1_S01="$s01" BOOT_RESULT_FILE="$RESULT" BOOT_TIMEOUT_S="$BOOT_TIMEOUT_S" \
        "$MAME_BIN" rc702 -rompath "$MAME/roms" \
        -nothrottle -window -skip_gameinfo \
        -seconds_to_run "$((BOOT_TIMEOUT_S + 5))" \
        -autoboot_script "$LUA" \
        -flop1 "$disk" >"$WORK/mame_${label// /_}_$s01.log" 2>&1
    local verdict="FAIL (no result file)"
    if [ -f "$RESULT" ] && grep -q '^PASS' "$RESULT"; then verdict="PASS"; else
        [ -f "$RESULT" ] && verdict="$(head -1 "$RESULT")"
        overall=1
    fi
    printf '%s\n' "$verdict"
    ROWS+=("$(printf '%-36s SW1-S01=%-3s  %s' "$label" "$pos" "$verdict")")
}

say "Running 4-way boot matrix (each boot ~${BOOT_TIMEOUT_S}s budget)"
run_boot "A: orig roa375.rom + clang BIOS" "$ORIG_PROM_PADDED" "$CLANG_DISK" 0
run_boot "A: orig roa375.rom + clang BIOS" "$ORIG_PROM_PADDED" "$CLANG_DISK" 1
run_boot "B: clang autoload + stock BIOS"  "$CLANG_PROM"       "$STOCK_DISK" 0
run_boot "B: clang autoload + stock BIOS"  "$CLANG_PROM"       "$STOCK_DISK" 1

# --- 5. report ----------------------------------------------------------------
say "Cross-version boot matrix summary"
for r in "${ROWS[@]}"; do echo "  $r"; done
echo "  autoload 2 KB fit:                   $PROM2K"
case "$PROM2K" in FAIL*) overall=1;; esac

echo
if [ "$overall" -eq 0 ]; then
    echo "RESULT: PASS — all cross-version boots reached A> and PROM fits 2 KB"
else
    echo "RESULT: FAIL — see logs in $WORK (run with KEEP_TMP=1 to retain)"
    [ -z "${KEEP_TMP:-}" ] && echo "        (re-run with KEEP_TMP=1 to inspect MAME logs)"
fi
exit "$overall"
