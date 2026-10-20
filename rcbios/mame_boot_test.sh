#!/bin/bash
# MAME boot test suite for RC702/RC703 disk images.
#
# Boots each disk image in the appropriate MAME variant, captures the
# screen buffer after CP/M boots, and checks for the expected signon.
#
# Prerequisites:
#   - MAME regnecentralen subtarget built (release or debug)
#   - Disk images in ~/Downloads/ (IMD format)
#   - mame_autoboot_dir.lua in the same directory as this script
#
# Usage:
#   cd rcbios && bash mame_boot_test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MAME_DIR="${MAME_DIR:-$(cd "$SCRIPT_DIR/../../mame" && pwd)}"
MAME="${MAME_DIR}/regnecentralen"

# Use debug build if release not available
if [ ! -x "$MAME" ]; then
    MAME="${MAME_DIR}/regnecentralend"
fi

if [ ! -x "$MAME" ]; then
    echo "ERROR: MAME binary not found at ${MAME_DIR}/regnecentralen{,d}"
    exit 1
fi

AUTOBOOT_LUA="${SCRIPT_DIR}/mame_autoboot_dir.lua"
ROMPATH="${MAME_DIR}/roms"
SCREEN="/tmp/screen.txt"
DL="${HOME}/Downloads"
PASS=0
FAIL=0
SKIP=0

run_test() {
    local machine="$1"
    local bios="$2"
    local image="$3"
    local expected="$4"
    local name
    name="$(basename "${image}" .imd)"

    if [ ! -f "$image" ]; then
        printf "%-55s SKIP (not found)\n" "${name}"
        SKIP=$((SKIP + 1))
        return
    fi

    printf "%-55s " "${name}"

    rm -f "$SCREEN"
    # Run MAME in background with a kill-timer (macOS has no timeout command).
    # The autoboot lua script calls manager.machine:exit() after ~25s.
    "$MAME" "$machine" \
        -rompath "$ROMPATH" \
        -bios "$bios" \
        -window -skip_gameinfo -nothrottle -sound none \
        -flop1 "$image" \
        -autoboot_delay 20 \
        -autoboot_script "$AUTOBOOT_LUA" \
        > /dev/null 2>&1 &
    local mame_pid=$!
    ( sleep 90 && kill "$mame_pid" 2>/dev/null ) &
    local timer_pid=$!
    wait "$mame_pid" 2>/dev/null || true
    kill "$timer_pid" 2>/dev/null || true
    wait "$timer_pid" 2>/dev/null || true

    if [ ! -f "$SCREEN" ]; then
        echo "FAIL (no screen capture)"
        FAIL=$((FAIL + 1))
        return
    fi

    if grep -qF "$expected" "$SCREEN"; then
        echo "PASS"
        PASS=$((PASS + 1))
    else
        echo "FAIL"
        echo "  expected: ${expected}"
        echo "  got:      $(head -1 "$SCREEN" | sed 's/ *$//')"
        FAIL=$((FAIL + 1))
    fi
}

skip_test() {
    local image="$1"
    local reason="$2"
    local name
    name="$(basename "${image}" .imd)"
    printf "%-55s SKIP (%s)\n" "${name}" "$reason"
    SKIP=$((SKIP + 1))
}

echo "MAME RC702/RC703 Boot Test Suite"
echo "================================"
echo "MAME: ${MAME}"
echo ""

# ── RC702 mini (5.25" DD) — rc702mini, bios 0 (roa375) ──

echo "--- rc702mini (roa375) ---"
run_test rc702mini 0 "$DL/CPM_med_COMAL80.imd"                       "rel.2.1"
run_test rc702mini 0 "$DL/CPM_v.2.2_rel.2.1.imd"                     "rel.2.1"
run_test rc702mini 0 "$DL/CPM_v.2.2_rel.2.2.imd"                     "rel. 2.2"
run_test rc702mini 0 "$DL/PolyPascal_v3.10.imd"                      "CP/M Ver 2.2 Rel 2.01"
run_test rc702mini 0 "$DL/SW1711-15_RC702_CPM_System_diskette.imd"    "rel.2.1"
run_test rc702mini 0 "$DL/SW1711-I5_CPM2.2_r1.4.imd"                 "58K CP/M"
run_test rc702mini 0 "$DL/SW1711-I5_CPM2.2_r2.0.imd"                 "rel.2.0"
run_test rc702mini 0 "$DL/SW1711-I5_CPM2.2_r2.1.imd"                 "rel.2.1"
run_test rc702mini 0 "$DL/SW1711-I5_CPM2.2_r2.2.imd"                 "rel. 2.2"
run_test rc702mini 0 "$DL/SW1711-I5_RC702_CPM_v2.3.imd"              "rel. 2.3"
run_test rc702mini 0 "$DL/SW7503-2.imd"                              "58K CP/M"
run_test rc702mini 0 "$DL/COMAL_v1.07_SYSTEM_RC702.imd"              "comal80"
echo ""

# ── RC702 maxi (8" DSDD) — rc702, bios 0 (roa375) ──

echo "--- rc702 maxi (roa375) ---"
run_test rc702 0 "$DL/SW1711-I8.imd"                                 "rel. 2.3"
run_test rc702 0 "$DL/PolyPascal_3.10.imd"                           "rel. 2.3"
run_test rc702 0 "$DL/Compas_v.2.13DK.imd"                           "58K CP/M"
echo ""

# ── RC703 (5.25" QD 80-track) — rc703, bios 1 (rob357) ──

echo "--- rc703 (rob357) ---"
run_test rc703 1 "$DL/RC703_CPM_v2.2_r1.2.imd"                       "rel. 1.2"
run_test rc703 1 "$DL/RC703_BDS_C_v1.50_workdisk.imd"                "CP/M Ver 2.2 Rel 2.20"
run_test rc703 1 "$DL/RC703_Div_BIOS_typer.imd"                      "56k CP/M vers. 2.2"
run_test rc703 1 "$DL/SW1311_cpm_v.2.2.imd"                          "rel. 1.2"
echo ""

# ── RC703 maxi (8" DSDD) — rc703maxi, bios 2 (rob357) ──

echo "--- rc703maxi (rob357) ---"
run_test rc703maxi 2 "$DL/SW1311-I8.imd"                             "rel. 1.0"
echo ""

# ── Non-bootable / special format ──

echo "--- skipped ---"
skip_test "$DL/RC703_DIV_ROA.imd"              "data only, no boot sectors"
skip_test "$DL/SW1329-d8.imd"                  "data only, no boot sectors"
skip_test "$DL/Metanic_COMAL-80D_v1.8.imd"     "non-standard format (uniform MFM, no FM T0)"
echo ""

echo "================================"
echo "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
