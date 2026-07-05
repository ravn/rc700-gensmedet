# llvmz80 bridge label tests

Red/green tests for the `zcc +cpm -compiler=llvmz80` bridge's handling of the
dotted symbols LLVM's Z80 backend emits. z80asm's lexer forbids `.` inside an
identifier (a `.` is its own token, `scan2.re:32`: `ident1 = [_a-zA-Z][_a-zA-Z0-9]*`),
so every dotted symbol clang emits must be flattened to a z80asm-legal name by
the bridge (`z88dk/lib/llvmz80/`: `llvmz80_rules.1` copt rules + `fixlabels.pl`).

## The three dotted-symbol families clang emits

The leading `_` and the `L` internal prefix both come from the Z80 target's
Mach-O name mangling (datalayout `m:o`); the dot inside `.str`/`func.var` comes
from clang's own IR naming, not any assembler prefix.

| Family | Example | Max dots | Origin |
|--------|---------|:---:|--------|
| 1. local labels   | `.LBB0_4`, `.Lfunc_end0` | 1 | internal-symbol prefix `.L` |
| 2. private globals| `L_.str`, `L_.str.1`     | 2 | `L`+`_`+ IR name `.str[.N]` |
| 3. static locals  | `_counter.n`             | 1 | `_`+ IR name `func.var` |

Family 3 (`_func.var`) is neither `.L*` nor `L_*`; it was unhandled by the
original bridge, so any program with a `static` local variable failed to
assemble (`ld hl,(_counter.n)` -> z80asm "syntax error"). Fixed in
`fixlabels.pl` with a generic "identifier with internal dot(s) -> dots to _"
rule (guarded by a `(?<!\.)` lookbehind so it never bites a dotted directive).

## Running

    ./fixlabels_test.sh     # fast, pure-perl unit test of the flattening
    ./run_bridge_tests.sh   # end-to-end: build each t_*.c via real zcc -> run in ntvcm

`run_bridge_tests.sh` needs a built `zcc` with `-compiler=llvmz80` support and
`ntvcm` (env `Z88DK`, `NTVCM`). Each `t_*.c` carries an `// EXPECT: <text>`
line compared against the program's stdout — proof that the clang path can now
print to the CP/M console (the reason the benchmark corpus historically used a
memory sentinel instead).

## Red/green history

Pre-fix: `t_static` + `t_combined` fail to assemble; `fixlabels_test.sh` reds on
the `fam3` cases. Post-fix: all pass, with `t_branches`/`t_strings` as
untouched positive controls.
