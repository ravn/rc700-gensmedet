#!/usr/bin/env bash
# Fast, self-contained unit test of fixlabels.pl (no z88dk/ntvcm needed).
# Feeds one dotted line per clang symbol family and checks the flattening.
# Complements the end-to-end t_*.c programs run by run_bridge_tests.sh.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
FIX="${FIX:-/Users/ravn/z80/z88dk/lib/llvmz80/fixlabels.pl}"

check() {  # <label> <input> <expected>
    local label="$1" in="$2" want="$3"
    local got; got="$(printf '%s\n' "$in" | perl "$FIX")"
    if [ "$got" = "$want" ]; then
        echo "PASS  $label"
    else
        echo "FAIL  $label"
        echo "        in:   $in"
        echo "        want: $want"
        echo "        got:  $got"
        return 1
    fi
}

fail=0
# Family 1: local labels (leading dot stripped; operand + definition).
check "fam1 .LBB operand"  $'\tjr\tz,.LBB0_6'   $'\tjr\tz,LBB0_6'   || fail=1
check "fam1 .LBB def"      '.LBB0_2:'            'LBB0_2:'           || fail=1
# Family 2: private string globals, incl. two-dot .N variant.
check "fam2 L_.str"        $'\tld\thl,L_.str'    $'\tld\thl,L__str'  || fail=1
check "fam2 L_.str.1"      $'\tld\tde,L_.str.1'  $'\tld\tde,L__str_1'|| fail=1
check "fam2 L_.str.1 def"  'L_.str.1:'           'L__str_1:'         || fail=1
# Family 3: static locals _func.var (the pre-fix regression).
check "fam3 _f.a operand"  $'\tld\thl,(_counter.n)' $'\tld\thl,(_counter_n)' || fail=1
check "fam3 _f.a def"      '_counter.n:'         '_counter_n:'       || fail=1
# Guard: a dotted assembler directive must NOT be flattened (defensive).
check "guard directive"    $'\t.rodata.str1.1'   $'\t.rodata.str1.1' || fail=1

echo "----"
[ "$fail" -eq 0 ] && echo "all fixlabels unit tests passed" || echo "fixlabels unit tests FAILED"
exit "$fail"
