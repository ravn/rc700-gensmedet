#!/usr/bin/env bash
# Red/green harness for the zcc -compiler=llvmz80 bridge's label handling.
#
# Each t_*.c carries an `// EXPECT: <text>` line.  We build it through the REAL
# `zcc +cpm -compiler=llvmz80` pipeline (clang -> copt/fixlabels bridge ->
# z80asm -> z88dk clib -> CP/M .COM) and run the .COM in ntvcm, comparing the
# program's stdout to the expected text.
#
# The three dotted-symbol families clang emits (.LBB / L_.str.N / _func.var)
# all have to survive the bridge as z80asm-legal identifiers; a build that
# fails to assemble (COMPILE) or produces wrong output (OUTPUT) is a FAIL.
#
# Usage:  ./run_bridge_tests.sh
# Env:    Z88DK (default /Users/ravn/z80/z88dk), NTVCM (default
#         /Users/ravn/z80/ntvcm/ntvcm)
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
Z88DK="${Z88DK:-/Users/ravn/z80/z88dk}"
NTVCM="${NTVCM:-/Users/ravn/z80/ntvcm/ntvcm}"
ZCC="${ZCC:-$Z88DK/bin/zcc}"
export PATH="$Z88DK/bin:$PATH"
export ZCCCFG="${ZCCCFG:-$Z88DK/lib/config}"

pass=0; fail=0
for src in "$HERE"/t_*.c; do
    name="$(basename "$src" .c)"
    exp="$(sed -n 's|^// EXPECT: ||p' "$src")"
    W="$(mktemp -d)"
    cp "$src" "$W/tu.c"
    ( cd "$W"
      if ! "$ZCC" +cpm -compiler=llvmz80 tu.c -o prog -create-app >zcc.log 2>&1; then
          echo "FAIL  $name  (COMPILE)"
          sed -n '1,6p' zcc.log | sed 's/^/        /'
          exit 2
      fi
      COM="$(ls -1 PROG.COM prog.com prog 2>/dev/null | head -1)"
      [ -n "$COM" ] || { echo "FAIL  $name  (NO .COM)"; exit 2; }
      got="$("$NTVCM" "$COM" 2>/dev/null | tr -d '\r')"
      if [ "$got" = "$exp" ]; then
          echo "PASS  $name  -> $got"
      else
          echo "FAIL  $name  (OUTPUT)"
          echo "        expected: $exp"
          echo "        got:      $got"
          exit 3
      fi
    )
    if [ $? -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); fi
    rm -rf "$W"
done

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
