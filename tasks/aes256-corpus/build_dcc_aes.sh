#!/usr/bin/env bash
# Build aes256.c + test_main.c with dcc (David Lee's CP/M C compiler),
# run it in z88dk-ticks, verify the 0xC000 result vector, and report
# .COM size + runtime T-states.  Adds dcc as a third "friend" to the
# AES-256 clang-vs-zsdcc comparison.
#
# dcc is a CP/M compiler: it emits M80 assembly, assembled by M80.COM and
# linked by L80.COM (both run under the runcpm emulator), producing a .COM
# that loads at 0x0100.  We wrap that .COM in a 64 KB image (page-zero BDOS
# stub + .COM at 0x0100, identical to dcc/scripts/compare3.sh) so ticks can
# run it; the program writes its result vector to 0xC000 and returns, which
# warm-boots to 0x0000 -> ticks stops on `-end 0`.
#
# BUILD MODE (important):
#   Default = SINGLE translation unit.  aes256.c and the test harness are
#   concatenated into one .c and compiled together.  This PASSES.
#   TWOFILE=1 = compile aes256.c and test_main.c separately and L80-link
#   them.  This MISCOMPILES under dcc — the cross-unit calls to the AES
#   functions return deterministically wrong ciphertext (enc/dec FAIL) even
#   though the program runs to completion.  Kept as a one-command repro of
#   the dcc separate-compilation bug; NOT used for the headline measurement.
set -euo pipefail

DCC_DIR=/Users/ravn/z80/dcc
AES_DIR=/Users/ravn/z80/rc700-gensmedet/tasks/aes256-corpus
TICKS=/Users/ravn/z80/z88dk/bin/z88dk-ticks
RUNCPM="$DCC_DIR/runcpm.sh"
W=/tmp/aes_dcc
export PATH="$DCC_DIR:$PATH"

# Which AES source variant to build (default: K&R aes256.c, as clang/zsdcc do).
AES_SRC="${1:-$AES_DIR/aes256.c}"
LABEL="${2:-dcc}"

rm -rf "$W"; mkdir -p "$W"
cp -f "$DCC_DIR/m80.com" "$W/M80.COM"
cp -f "$DCC_DIR/l80.com" "$W/L80.COM"
cp -f "$DCC_DIR/DCCRTL.MAC" "$W/DCCRTL.MAC"

crlf() { perl -0pi -e 's/\r?\n/\r\n/g' "$1"; }
peep() { [ "${NOPEEP:-0}" = "1" ] || { "$DCC_DIR/dccpeep" "$1" "$W/_P.MAC" && mv "$W/_P.MAC" "$1"; }; }

if [ "${TWOFILE:-0}" = "1" ]; then
    # --- two-unit build (reproduces the dcc cross-TU miscompile) ---
    "$DCC_DIR/dcc" "$AES_SRC"             -o "$W/AES256.MAC"
    "$DCC_DIR/dcc" "$AES_DIR/test_main.c" -o "$W/TEST.MAC"
    peep "$W/AES256.MAC"; peep "$W/TEST.MAC"
    crlf "$W/AES256.MAC"; crlf "$W/TEST.MAC"
    ( cd "$W" && "$RUNCPM" M80.COM "=AES256.MAC /X /O /Z" >/dev/null 2>&1 )
    ( cd "$W" && "$RUNCPM" M80.COM "=TEST.MAC /X /O /Z"   >/dev/null 2>&1 )
    "$DCC_DIR/dccrtlstrip" -r "$W/DCCRTL.MAC" -o "$W/RTLMIN.MAC" "$W/AES256.MAC" "$W/TEST.MAC"
    crlf "$W/RTLMIN.MAC"
    ( cd "$W" && "$RUNCPM" M80.COM "=RTLMIN.MAC /X /O /Z" >/dev/null 2>&1 )
    ( cd "$W" && "$RUNCPM" L80.COM "/P:100,RTLMIN,AES256,TEST,TEST/N/E" >/dev/null 2>&1 )
    LINKOUT=TEST
else
    # --- single-unit build (correct; the headline dcc measurement) ---
    # Concatenate the AES source with the test harness (RESULTS_ADDR +
    # expected_ct + main) into one translation unit.  test_main's leading
    # typedef/struct/prototypes are dropped (already present in aes256.c).
    python3 - "$AES_SRC" "$AES_DIR/test_main.c" "$W/MAIN.c" <<'PY'
import sys
aes = open(sys.argv[1]).read()
tm  = open(sys.argv[2]).read()
start = tm.index('#define RESULTS_ADDR')   # keep RESULTS_ADDR + expected_ct + main
open(sys.argv[3], 'w').write(
    aes + "\n\n/* ---- inlined test harness (single TU) ---- */\n" + tm[start:])
PY
    "$DCC_DIR/dcc" "$W/MAIN.c" -o "$W/MAIN.MAC"
    peep "$W/MAIN.MAC"
    crlf "$W/MAIN.MAC"
    ( cd "$W" && "$RUNCPM" M80.COM "=MAIN.MAC /X /O /Z" >/dev/null 2>&1 )
    "$DCC_DIR/dccrtlstrip" -r "$W/DCCRTL.MAC" -o "$W/RTLMIN.MAC" "$W/MAIN.MAC"
    crlf "$W/RTLMIN.MAC"
    ( cd "$W" && "$RUNCPM" M80.COM "=RTLMIN.MAC /X /O /Z" >/dev/null 2>&1 )
    ( cd "$W" && "$RUNCPM" L80.COM "/P:100,RTLMIN,MAIN,MAIN/N/E" >/dev/null 2>&1 )
    LINKOUT=MAIN
fi

test -f "$W/$LINKOUT.COM" || { echo "ERROR: dcc link produced no $LINKOUT.COM"; ls -la "$W"; exit 1; }
cp -f "$W/$LINKOUT.COM" "$AES_DIR/dcc.com"
SIZE=$(wc -c < "$AES_DIR/dcc.com")

# Wrap .COM in a 64 KB ticks image (page-zero stub + .COM @0x0100).
python3 - "$AES_DIR/dcc.com" "$W/dcc.img" <<'PY'
import sys
com, out = sys.argv[1], sys.argv[2]
mem = bytearray(65536)
mem[0x0000]=0xC3; mem[0x0001]=0x00; mem[0x0002]=0x00          # JP 0x0000 (warm boot)
mem[0x0005]=0xC3; mem[0x0006]=0x00; mem[0x0007]=0xDC          # JP 0xDC00 (BDOS)
mem[0xDC00]=0x79; mem[0xDC01]=0xB7; mem[0xDC02]=0xCA          # LD A,C; OR A; JP Z,
mem[0xDC03]=0x00; mem[0xDC04]=0x00; mem[0xDC05]=0xC9          # ..0x0000 ; RET
d=open(com,'rb').read(); mem[0x0100:0x0100+len(d)]=d
open(out,'wb').write(mem)
PY

# Run in ticks: start at 0x100, stop when pc hits 0 (program returned to
# CCP -> warm boot), dump RAM, capture the T-state count.
TS=$("$TICKS" -pc 100 -end 0 -counter 200000000 -output "$W/dcc.ram" "$W/dcc.img" 2>/dev/null | tail -1)

# Verify the 35-byte result vector at 0xC000.
python3 - "$W/dcc.ram" "$SIZE" "$TS" "$LABEL" <<'PY'
import sys
ram=open(sys.argv[1],'rb').read(); size=sys.argv[2]; ts=sys.argv[3]; label=sys.argv[4]
v=ram[0xC000:0xC023]
ct=' '.join(f'{b:02x}' for b in v[0:16])
ok = v[16]==1 and v[33]==1 and v[34]==0xA5
print(f"{label:16} ct: {ct}  enc={v[16]:02x} dec={v[33]:02x} end={v[34]:02x}  "
      f"[{'PASS' if ok else 'FAIL'}]")
print(f"{label:16} size={size} B (incl. CP/M RTL)   tstates={ts}")
PY




