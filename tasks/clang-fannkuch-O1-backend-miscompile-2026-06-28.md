# clang (llvm-z80) miscompiles fannkuch at -O1/-O2 — Z80 backend CFG-layout bug

Status: **OPEN, verified, not yet reduced/filed.** Routing: this is a
Z80-target backend codegen bug -> belongs at `llvm-z80/llvm-z80` (the fork),
NOT llvm/llvm-project (it is target-specific machine-CFG handling, not a
generic middle-end bug). Per the explain-before-filing rule, get an explicit
go-ahead before posting.

Found by: compiler-comparison-corpus SPEED column (clang `-O2`) on
`bench_fannkuch.c`, 2026-06-28 (sonnyboy).

## Symptom (VERIFIED)
`fannkuchredux(7)` returns **0x0000** instead of the correct **0x10E4**
(maxFlipsCount=16, checksum=228) when compiled by clang at **-O1 or -O2**.
At **-Oz** and **-O0** the result is correct. So the corpus SIZE cell
(`-Oz`, production) PASSES and only the experimental SPEED cell (`-O2`)
FAILS. Production density builds use -Oz, so production is unaffected.

Result 0x0000 = the function bailed out before computing anything: the
returned pack `(maxFlipsCount<<8)|(checksum&0xff)` is all-zero, i.e. control
flow reached the `if (r == n) return ...` exit on the first inner-loop
iteration (suspected: a loop that should decrement `r` to 1 was skipped, so
`r` still equals `n`). The "return 0" framing is the OBSERVED value; the
"skipped r-decrement loop" is a plausible mechanism, NOT yet confirmed at
the instruction level.

## It is a BACKEND bug — middle-end exonerated (VERIFIED)
Cross-compiled the *optimized* IR through a fixed backend:

    clang … -O1 -emit-llvm -S -o f_o1.ll bench_fannkuch.c   # optimized IR
    clang … -Oz -emit-llvm -S -o f_oz.ll bench_fannkuch.c

    llc -O0  f_o1.ll  -> PASS      llc -O0  f_oz.ll -> PASS
    llc -O1  f_o1.ll  -> FAIL      llc -O1  f_oz.ll -> PASS
    llc -O2  f_o1.ll  -> FAIL      llc -O2  f_oz.ll -> PASS

`f_o1.ll` is itself CORRECT (it passes through `llc -O0`), so the middle-end
did not emit wrong IR. The Z80 **backend** miscompiles the `-O1`/`-O2` IR
loop shape (rotated loops + loop preheaders) at codegen opt >= 1. The `-Oz`
IR shape (simpler, unrotated) is immune.

## Manifesting pass = branch-folder (VERIFIED via opt-bisect)
opt-bisect localizes it identically at both levels:
- clang pipeline: pass #455 `branch-folder on function (bench_run)`
- llc pipeline (cleaner, backend-only, 78 points): pass #43
  `branch-folder on function (bench_run)`
  (limit=42 PASS, limit=43 FAIL — enabling branch-folder with every later
   pass skipped is *sufficient* to produce the wrong result.)

`fannkuchredux` is `static` and inlined into `bench_run`, so the affected
function is `bench_run`.

## …but branch-folder is not the whole story (VERIFIED nuance)
`llc -O1 -disable-branch-fold` still FAILS, even though opt-bisect-limit=42
(which also skips branch-folder *and* every pass after it) PASSES. The
passes immediately after branch-folder are `tailduplication` (#44),
`machine-cp` (#45), `block-placement` (#46). Reading: the *pre*-branch-folder
MIR is already in a state that ANY CFG-layout/relayout pass corrupts; only
skipping all of them survives. This points the root defect upstream of
branch-folder — most likely Z80 **`analyzeBranch` / branch representation**
(the shared analysis every CFG-layout pass relies on), with branch-folder
simply the first pass to exercise it. (HYPOTHESIS — the exact faulty
analysis/branch is not yet pinned.)

What branch-folder concretely does to `bench_run` (from
`-print-before/-after=branch-folder`): it rewrites the `JP_cc %taken /
JP_nn %fall` terminator pairs into single short `JR_cc` forms and
renumbers+reorders the 35 basic blocks. The miscompile is a control-flow
corruption introduced during that fold+relayout. The exact mis-rewritten
(condition, taken-target, fallthrough-target) triple has not yet been
isolated (renumbering makes the before/after diff non-trivial by hand).

## Minimal reproducer (backend-only, no harness)
    HERE=rc700-gensmedet/tasks/compiler-comparison-corpus
    CLANG=…/llvm-z80/build/bin/clang ; LLC=…/llvm-z80/build/bin/llc
    $CLANG --target=z80 -nostdlib -ffreestanding -std=c89 \
        -Xclang -target-feature -Xclang +static-stack \
        -ffunction-sections -fdata-sections \
        -O1 -emit-llvm -S -o f_o1.ll $HERE/bench_fannkuch.c
    $LLC -O1 f_o1.ll -o f_o1.s        # miscompiled bench_run
    $LLC -O0 f_o1.ll -o f_ok.s        # correct bench_run
Diff `f_o1.s` vs `f_ok.s` for `bench_run` to see the divergent control flow.

## Workarounds
- Use `-Oz` (production already does) or `-O0`. No single `-mllvm` toggle
  recovers `-O1`/`-O2` (disabling branch-fold alone is insufficient, see
  above).

## Next steps (follow-up, when picked up)
1. `llvm-reduce` the `f_o1.ll` reproducer against an interestingness test
   (`llc -O1` wrong vs `llc -O0` right) to a few blocks.
2. Audit Z80 `analyzeBranch`/`insertBranch`/`reverseBranchCondition` and the
   `JP_cc`/`JR_cc` terminator opcodes against the pre-branch-folder MIR; verify
   successor lists stay consistent with terminators across the fold.
3. Add a Z80 lit test (FileCheck the bench_run CFG) once root-caused; add the
   runtime fixture to test-runner. (CLAUDE.md: every backend fix ships a lit
   test.)
4. File at llvm-z80/llvm-z80 after explain + go-ahead.

## Update 2026-06-28b — CFG ruled out, dataflow suspected
Compared bench_run terminators + successor lists BEFORE vs AFTER branch-folder
(`llc -O1 -print-{before,after}=branch-folder`). After the fold EVERY block's
terminator matches its successor list (NZ/Z targets + fall-through all
consistent; only bb.34 RET has a stale succ, harmless). So analyzeBranch /
successor bookkeeping is NOT corrupt — the dangling-branch hypothesis is
refuted. The miscompile returns 0x0000 (uninitialised `de`), meaning a needed
store/def is dropped or relocated by branch-folder's BLOCK REORDERING, not a
broken branch. Asm-level slot diffing is useless: -O0 and -O1 allocate the BSS
frame differently. Pinpointing needs llvm-reduce with a RUNTIME oracle (emit
sentinel != 0x10E4), not a structural fingerprint.
