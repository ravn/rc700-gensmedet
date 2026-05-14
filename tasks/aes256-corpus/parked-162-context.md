# Parked context — ravn/llvm-z80#162 (K&R u8 chain into K&R u8 call)

Captured 2026-05-14 in session 70.  When resuming this work, read this
file plus the two #162 comments before re-investigating; the picture is
already established.

## State

- **Issue**: https://github.com/ravn/llvm-z80/issues/162
- **Branch with Path A partial fix**: `llvm-z80/path-a-knr-zeroext` @
  commit `298a4cbe63d0` (NOT merged; kept for reference + to enable
  combined Option 3 work)
- **C repro**: `tasks/aes256-corpus/repros/repro_rj_sb_inv_kr_fshl_missed.c`
  (uses `__attribute__((noinline))` on `gf_mulinv` — critical, else
  inlining hides the bug)
- **Lit test for Path A** (on the branch only):
  `clang/test/CodeGen/Z80/knr-narrow-param-zeroext.c`
- **Empirical sizes at HEAD `3686ebdea927` (post-#160, pre-#162-fix)**:
  - K&R `rj_sb_inv`: 156 B
  - ANSI `rj_sb_inv`: 21 B (corpus shows 18; minor inlining-cascade
    differences between the standalone repro and full aes256.c)
  - Gap: 138 B / 8.7×
  - K&R `clang.bin`: 4450 B
  - K&R `aes256.c` text: 3996 B
  - Path A alone: ALL unchanged (semantically correct, empirically inert)

## Diagnosis (don't re-derive)

1. **Where the bug isn't**: not in #158 (TruncInstCombine through args
   is fine but needs a trunc root that K&R-chain-into-K&R-call doesn't
   provide).  Not in #160 (icmp-sink — chain has no icmps).
2. **What's actually wrong**: K&R-promoted parameters historically
   lacked the `zeroext` attribute on the wider IR parameter, hiding the
   "high bits are provably zero" guarantee from mid-end passes.  Path A
   fixes this — verified by IR inspection.
3. **Why Path A alone doesn't move corpus sizes**: phase-ordering
   issue.  At `-Oz`/`-O2`:
   - `mem2reg` exposes truncs at parameter entry
   - `instcombine` canonicalises `(zext (trunc X))` → `(and X, 0xFF)`
     — the trunc is gone
   - `aggressive-instcombine`'s `TruncInstCombine` runs next, finds no
     trunc root, bails
4. **Reproducible**: `opt -passes='mem2reg,instcombine,aggressive-instcombine,instcombine'`
   on the same -O0 IR DOES narrow (3× `fshl.i8` recognised).
   `opt -passes='default<O2>'` does NOT narrow.

## Three paths to close #162

Pick exactly one in the next session.

| Option | Scope | Estimated effort | Risk |
|---|---|---:|---|
| **3 — call-boundary narrowing sink** in TruncInstCombine | Extend `getBestTruncatedType` to root from `call f(i16 zeroext X, ...)` arguments when the callee's parameter is also `zeroext`-i16-narrow.  Most direct match for the K&R-into-K&R-call pattern. | 50-100 LOC in `llvm/lib/Transforms/AggressiveInstCombine/TruncInstCombine.cpp` — same shape as the #160 icmp-sink patch | LOW; localised to a pass we've already touched |
| **1 — and-mask sink** in TruncInstCombine | Treat `(and X, MASK)` where MASK = (2^M - 1) as a trunc-equivalent root.  Broader applicability than Option 3 (any narrow-mask shape, not just calls) | 100-200 LOC; need care choosing which masks trigger | MEDIUM; affects all targets |
| **2 — move AggressiveInstCombine earlier** in the -O2 pipeline | Run it BEFORE the trunc-eliminating InstCombine canonicalisation | Tiny patch in `PassBuilderPipelines.cpp` | HIGH; broadest blast radius |

**Recommended: Option 3** (most contained, biggest match for the
filed-issue scope, builds on existing pattern from #160 work).

## How to resume

1. `git checkout path-a-knr-zeroext` in llvm-z80
2. Re-run the failing condition:
   ```
   CLANG=/Users/ravn/z80/llvm-z80/build-macos/bin/clang
   cp tasks/aes256-corpus/repros/repro_rj_sb_inv_kr_fshl_missed.c /tmp/rj.c
   $CLANG --target=z80 -Oz -nostdlib -ffreestanding -std=c89 \
          -Wno-deprecated-non-prototype -DKR -c /tmp/rj.c -o /tmp/rj_kr.o
   llvm-nm --print-size --size-sort /tmp/rj_kr.o | grep rj_sb_inv
   # Expect: 0000009c = 156 B (pre-fix size; Path A alone doesn't move it)
   ```
3. Write the failing lit test FIRST for Option 3 (in
   `llvm/test/Transforms/AggressiveInstCombine/`)
4. Implement Option 3
5. Verify lit PASSES, repro size drops, AES sweep moves
6. A/B test-runner against `tasks/aes256-corpus/baselines.md`

## Cross-references

- #162 main comments:
  - https://github.com/ravn/llvm-z80/issues/162 (initial diagnosis)
  - https://github.com/ravn/llvm-z80/issues/162#issuecomment-4454783096
    (Path A status + phase-ordering finding)
- Related fixed: #158, #159, #160 (icmp-sink), #161
- Adjacent unstarted: #156, #157
- Memory: `[[feedback_test_before_fix]]` (write test first),
  `[[reference_z80_tool_paths]]` (paths for clang/opt/lit),
  `[[feedback_ab_before_blaming_test_runner]]` (A/B before diagnosing)
