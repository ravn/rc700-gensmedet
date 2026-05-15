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

## Session 71 finding: Option 3 cannot fire without a frontend tag

Implemented Option 3 with two eligibility variants.  Both ruled out.
See https://github.com/ravn/llvm-z80/issues/162#issuecomment-4457134375
for the full breakdown.

**Safe (known-bits-only) variant: inert.**
- `paramHasAttr(ZExt)` + `computeKnownBits` active-bits gate.
- AES corpus: identical to post-#157 baseline (zero movement).
- `rj_sb_inv` K&R: stays at 156 B.
- z80-utils test-runner: zero regression (685/42/56/207).
- The patterns this catches are already caught by existing #158
  argument-leaf machinery; no new value.

**Trust-zeroext (relaxed) variant: unsound.**
- Drops the known-bits gate, narrows on the strength of `zeroext`
  attribute alone.
- AES corpus: −85 to −115 B per config; `rj_sb_inv` 156 → 36 B (−120).
- AES verifier PASSes all 11 configs.
- z80-utils test-runner: **318 FAIL, 80 FATAL** (was 42/56).  Massive
  regression.
- **Root cause**: `zeroext` on `i16` is an ABI signal, not a
  source-narrowness signal.  `uint16_t` parameters carry `zeroext` too
  on Z80 (i16 = natural ABI width).  Variant 2 narrowed
  `dense_map(i16 zeroext 1000)` to `i8 trunc(1000) = -24`, breaking the
  switch in `test_16_switch_case.c`.

### What is structurally needed

Three structural paths remain — none is a quick patch:

1. **Frontend tag distinguishing K&R-narrow from natural-i16 zeroext.**
   Path A on `path-a-knr-zeroext` adds `zeroext` to K&R-promoted narrow
   params but doesn't *tag* them differently from natural-width
   zeroext.  Would need a new attribute (e.g. `narrow_from_i8`) so
   `canNarrowCallArgZeroext` can discriminate.
2. **Per-callee body peek.**  If the callee starts with `trunc i16 %0
   to i8`, narrowing at the boundary preserves observable behaviour.
   Requires CGSCC pass ordering and IPO-style analysis.
3. **Tighter KnownBits for rotate idioms.**  The `(x<<1)|(x>>7)` shape
   widens transient values to 9 active bits even though the
   reconstruction collapses to 8.  Improving KnownBits to track this
   would let the sound variant fire.  Large scope; benefits beyond
   #162.

### Closure status

- No code change landed; uncommitted work reverted.
- Branch `path-a-knr-zeroext` left as-is (Path A frontend WIP at
  `298a4cbe63d0` retained for Option 1 in #162 cross-listing).
- #162 stays open with the finding documented.

### Recommended next attempt

**Option 1 (and-mask sink) is now the most attractive remaining path.**
Treats `(and X, MASK)` where MASK = (2^M - 1) as a trunc-equivalent
root.  Doesn't require a tag; doesn't require frontend changes.  Should
catch the InstCombine-canonical form of K&R promotion.

For rj_sb_inv specifically: Option 1 still doesn't fire on the rotate
idiom (no terminal `(and X, 255)` masked-call-arg), so 3 (KnownBits
improvement) remains the only path for that exact shape.

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
  - https://github.com/ravn/llvm-z80/issues/162#issuecomment-4457134375
    (session 71 Option 3 ruled out — zeroext is ABI signal not source-narrow)
- #163 main comments:
  - https://github.com/ravn/llvm-z80/issues/163 (and-mask sink filing)
  - https://github.com/ravn/llvm-z80/issues/163#issuecomment-4457428303
    (session 71 Option 1 ruled out — no use-count guard regressed
    +200-500B/config; single-use guard inert)
- Related fixed: #156, #157, #158, #159, #160 (icmp-sink), #161
- Memory: `[[feedback_test_before_fix]]` (write test first),
  `[[reference_z80_tool_paths]]` (paths for clang/opt/lit),
  `[[feedback_ab_before_blaming_test_runner]]` (A/B before diagnosing),
  `[[feedback_zeroext_is_abi_not_source]]` (session 71 #162 finding)

## Status after session 71

Both Option 1 (#163) and Option 3 (#162) attempted and ruled out:
- Option 3: zeroext attribute alone is not a sound source-narrow proof
  on multi-byte ABIs.  Cannot fire safely without a frontend tag.
- Option 1: and-mask sink fires correctly but the trunc-zext roundtrip
  cost on Z80 exceeds the upstream narrowing gain for chains with
  multiple users.  Single-use guard makes it sound but inert.

Remaining structural paths (same three as in #162 session 71 finding):

1. **Frontend tag** distinguishing K&R-narrow from natural-i16 zeroext
2. **Per-callee body peek** (IPO: if callee starts with `trunc i16 → i8`,
   the high bits are observably discarded; narrowing at boundary is safe)
3. **Tighter KnownBits** for rotate-idiom DAGs

None is a quick session.  The remaining `rj_sb_inv` +120-138 B K&R vs
ANSI gap is now a documented structural item.

## Status after session 72 — #162 CLOSED via path 2

**Final state**: #162 closed by `519aaaec4817` (per-callee body peek)
on top of `3d296f439645` (#164 phase 1 + #163 infrastructure).

Headline result: `rj_sb_inv` K&R **156 → 36 B (−120, 4.3×)**.  AES
corpus 11/13 configs improved by 84–121 B.  Production knob
`09_Oz_prod_like`: 2806 → 2721 B.  Test-runner unchanged.

See [`llvm-z80/tasks/session72-truncinstcombine-cost-gate-and-callee-peek.md`](../../../llvm-z80/tasks/session72-truncinstcombine-cost-gate-and-callee-peek.md)
for the full write-up.

### Path 2 retrospective

The empirical breakthrough was a 30-second manual-trunc-injection
experiment that proved the existing TruncInstCombine engine narrows
the entire `rj_sb_inv` chain (including 3× `llvm.fshl.i8` recognition)
the moment a single trunc-zext bracket is injected at the call site.
This contradicted session 71's stated recommendation that path 3
(tighter KnownBits) was the most attractive remaining path.

Lesson: **multi-path issue branches should be empirically re-evaluated
with current state before re-engaging**, not just resumed from the
prior session's recommendation.

### Phase 2 plumbing details

Critical ordering subtlety captured in the commit and code comments:
the call's argument must be swapped to the synthetic `Zx` *before*
probing, otherwise `getBestTruncatedType` sees the chain root as
multi-use (call + Tr) and bails.

Phase 2 also added an Argument short-circuit in `getMinBitWidth` to
fix pre-existing UB (line 258's `cast<Instruction>(Src)` is wrong when
`Src` is directly an `Argument`).  The #158 fix added Argument
handling inside the walker loops but not in the initialisation.

### What's NOT closed

- **#164 phase 2** — byte-budget cost model replacing the boolean
  `isZExtFree` gate.  Phase 1 (boolean gate) is inert-on-Z80 by
  design; phase 2 would let multi-use Z80 ands fire when the byte
  savings exceed the re-extension cost.
- **#165 (NEW, session 72)** — extend `canNarrowIcmpThroughGraph`
  to accept narrowable non-constant operands.  Would close `gf_log`
  (153 → ~30 B) and similar phi-loop patterns in aes256.c.
- **Path 1** (Clang frontend K&R-narrow tag) — not needed for
  `rj_sb_inv` (path 2 handled it); may still be worth pursuing for
  cases without a callee-body witness.
- **Path 3** (tighter KnownBits for rotate idioms) — mostly moot
  now that path 2 reaches the chain.  Remains useful for
  hypothetical chains without a callee-body witness.

### Branch / artifact retention

Branch `path-a-knr-zeroext` at `298a4cbe63d0` retained for future
path 1 work, if ever revived.  No active work.

---

## (Original session 71 entry below for history)

ravn/llvm-z80#163 (and-mask synthetic trunc root) + #164 (TTI cost gate)
LANDED in `3d296f439645`:
- TruncInstCombine receives TTI; phase 2 of `run()` walks `(and X, MASK)`
  patterns and injects a synthetic trunc root for each.
- Cost gate: `!hasOneUse && !isZExtFree(NarrowTy, OrigTy)` blocks the
  multi-use regression observed in session 71 (+200-500 B / config).
- Side-fix: pre-existing UB in `getMinBitWidth` when trunc's direct
  operand is an Argument (cast<Instruction> without check) — added a
  short-circuit mirroring the Constant case at line 254.
- Z80 outcome: every AES corpus config byte-identical to post-#157
  baseline; test-runner 685/42/56/207 unchanged.  Single-use path fires
  but doesn't move the needle (matches session 71 prediction).
- Other-target outcome: x86-family `isZExtFree=true`, synthetic root
  fires unconditionally; existing upstream `trunc_multi_uses.ll` still
  PASSes via the new path.

What #164 unblocks for Z80 (still future work):
- #164 phase 2: byte budget (`zext_bytes * use_count` vs
  `narrow_bytes * chain_len`) instead of boolean gate — would let
  single-use guard relax on chains where narrowing pays for re-extension.
- #162 path 2 (per-callee body peek) and path 3 (tighter KnownBits for
  rotate idioms) can now layer on top of the existing cost model rather
  than fighting it.

Branch `path-a-knr-zeroext` at `298a4cbe63d0` remains parked for #162's
eventual frontend-tag approach.  Repro scripts and lit tests retained.
