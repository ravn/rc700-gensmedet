# Baseline numbers — A/B reference

Captured baselines used to avoid stash + rebuild + retest cycles in future
sessions. Each row records what HEAD produced at a specific commit so we
can answer "what was the pre-patch X?" without rebuilding.

Update this file whenever a llvm-z80 patch is merged that affects the numbers.

## llvm-z80 HEAD: `6fdfe4817f8e` (pre-#160 icmp-sink, post-#158/#159/#161)

Captured 2026-05-14 in session 70 by stashing the in-progress patch and
rebuilding stock clang.  This is the baseline against which the
fix-160-icmp-narrowing-sink branch (commit `7801a8f10f62`) was A/B'd.

### z80-utils test-runner — `cargo run --release -- clang`

```
BUILD_DIR=/Users/ravn/z80/llvm-z80/build-macos \
  PATH="/Users/ravn/z80/z88dk/bin:$PATH" \
  cargo run --release -- clang
```

| Total | PASS | FAIL | FATAL | SKIP |
|------:|-----:|-----:|------:|-----:|
| 990 | 681 | 46 | 56 | 207 |

The 46 FAIL / 56 FATAL are pre-existing noise (see ravn/llvm-z80#136 for
the edge_*_O1 class).  Any patch that doesn't change these counts has
zero regressions on this oracle.

### AES corpus `make sweep_clang`

```
cd /Users/ravn/z80/rc700-gensmedet/tasks/aes256-corpus
make clean && make sweep_clang
```

| Config | bin B | aes_text B | tstates | verify |
|---|------:|-----------:|--------:|:------:|
| `01_baseline_Oz` | 4642 | 4188 | 66019335 | PASS |
| `02_Os` | 4915 | 4475 | 65699061 | PASS |
| `03_O3` | 13637 | 12394 | 65631096 | PASS |
| `04_O2` | 9203 | 8046 | 65702075 | PASS |
| `05_Oz_static_stack` | 3165 | 2735 | 100000003 | FAIL (#156) |
| `06_Oz_no_licm_cse` | 4430 | 4026 | 31542192 | PASS |
| `07_Oz_no_lsr` | 5008 | 4244 | 66008773 | PASS |
| `08_Oz_gc_sections` | 4622 | 4188 | 66019335 | PASS |
| `09_Oz_prod_like` | 3042 | 2682 | 58131 | FAIL (#156) |
| `10_Oz_no_licm_cse_lsr` | 4786 | 4038 | 31565733 | PASS |
| `11_Oz_no_licm_cse_gc` | 4410 | 4026 | 31542192 | PASS |

### AES `make sizes` (single-config)

| Variant | bin B |
|---|------:|
| clang.bin (K&R) | 4642 |
| clang_ansi.bin | 4241 |
| zsdcc.bin (K&R) | 3604 |
| zsdcc_ansi.bin | 3323 |
| DEMO.COM (HiTech-mystery) | 9216 |

## llvm-z80 HEAD: `3369f137dd2d` (post-#156 +static-stack miscompile fix)

Captured 2026-05-15 in session 71 after merging fix-156-bss-spill-loop-header
to main.  Branch hash `b6b684d9a9b0`; merge commit `3369f137dd2d`.

### z80-utils test-runner — `cargo run --release -- clang`

| Total | PASS | FAIL | FATAL | SKIP |
|------:|-----:|-----:|------:|-----:|
| 990 | **685** | **42** | 56 | 207 |

+4 PASS / −4 FAIL vs `7801a8f10f62` baseline above.  Unrelated tests
unblocked by the peephole fix — see #156 for details.

### AES corpus `make sweep_clang`

| Config | bin B | tstates | verify |
|---|------:|--------:|:------:|
| `01_baseline_Oz` | 4450 | 65979155 | PASS |
| `02_Os` | 4725 | 65653409 | PASS |
| `03_O3` | 12688 | 65564499 | PASS |
| `04_O2` | 8654 | 65648107 | PASS |
| **`05_Oz_static_stack`** | **2995** | **33588245** | **PASS** ← was FAIL |
| `06_Oz_no_licm_cse` | 3988 | 31403069 | PASS |
| `07_Oz_no_lsr` | 4816 | 65968593 | PASS |
| `08_Oz_gc_sections` | 4430 | 65979155 | PASS |
| **`09_Oz_prod_like`** | **2806** | **22649211** | **PASS** ← was FAIL |
| `10_Oz_no_licm_cse_lsr` | 4344 | 31426610 | PASS |
| `11_Oz_no_licm_cse_gc` | 3968 | 31403069 | PASS |

**All 11 configs PASS.**  Smallest+fastest PASS config is now
`09_Oz_prod_like` at 2806 B / 22.6M tstates — production knob set
(static-stack + no-licm/cse + no-lsr + gc-sections).

### AES `make sizes`

| Variant | bin B | Δ vs `7801a8f` |
|---|------:|------:|
| clang.bin (K&R) | 4450 | 0 |
| clang_ansi.bin | 4241 | 0 |
| zsdcc.bin | 3604 | 0 |
| zsdcc_ansi.bin | 3323 | 0 |

Per-function sizes unchanged on the no-static-stack default build.
The fix is in a peephole that only fires under `+static-stack`, so the
baseline build is by-construction untouched.

## llvm-z80 HEAD: `7801a8f10f62` (post-#160 icmp-sink)

Captured 2026-05-14 in session 70 after committing the
fix-160-icmp-narrowing-sink patch.

### z80-utils test-runner — `cargo run --release -- clang`

| Total | PASS | FAIL | FATAL | SKIP |
|------:|-----:|-----:|------:|-----:|
| 990 | 681 | 46 | 56 | 207 |

Identical to stock baseline above — zero regressions.

### AES corpus `make sweep_clang`

| Config | bin B | Δ from `6fdfe48` | verify |
|---|------:|------:|:------:|
| `01_baseline_Oz` | 4450 | **−192** | PASS |
| `02_Os` | 4725 | −190 | PASS |
| `03_O3` | 12688 | −949 | PASS |
| `04_O2` | 8654 | −549 | PASS |
| `05_Oz_static_stack` | 2991 | −174 | FAIL (#156) |
| `06_Oz_no_licm_cse` | 3988 | **−442** | PASS |
| `07_Oz_no_lsr` | 4816 | −192 | PASS |
| `08_Oz_gc_sections` | 4430 | −192 | PASS |
| `09_Oz_prod_like` | 2802 | −240 | FAIL (#156) |
| `10_Oz_no_licm_cse_lsr` | 4344 | −442 | PASS |
| `11_Oz_no_licm_cse_gc` | 3968 | **−442** | PASS |

### AES `make sizes`

| Variant | bin B | Δ |
|---|------:|------:|
| clang.bin (K&R) | 4450 | −192 |
| clang_ansi.bin | 4241 | 0 (ANSI was already narrow) |
| zsdcc.bin | 3604 | 0 (not affected) |
| zsdcc_ansi.bin | 3323 | 0 |

### Per-function AES (K&R variant)

| Function | bin B at `6fdfe48` | bin B at `7801a8f` | Δ |
|---|------:|------:|------:|
| `aes_mc_inv` | 537 | **460** | **−77** |
| `aes_mixColumns` | 415 | **300** | **−115** |
| Others | unchanged | unchanged | 0 |

`aes_mc_inv` and `aes_mixColumns` are now byte-identical between K&R and
ANSI variants — the residual #160 caller-bloat gap is fully closed for
those two functions.  `rj_sb_inv` (+138 B K&R vs ANSI) and `gf_log`
(+23 B) remain on K&R; they are likely #157-class (regalloc) or
caller-of-K&R-callee residuals not addressed by the icmp-sink fix.

## llvm-z80 HEAD: `3369f137dd2d` + `-fno-omit-frame-pointer` recipe (closes #157)

Captured 2026-05-15 session 71 after deciding closure path A on #157.
No compiler change — the flag was always there.  This documents the
empirical recipe and re-runs the sweep with two new configs (12, 13).

### AES corpus `make sweep_clang`

```
make clean && make sweep_clang
```

Same compiler as the row above (no compiler change), just two added rows:

| Config | bin B | aes_text B | tstates | verify |
|---|------:|-----------:|--------:|:------:|
| `01_baseline_Oz` | 4450 | 3996 | 65 979 155 | PASS |
| `02_Os` | 4725 | 4285 | 65 653 409 | PASS |
| `03_O3` | 12688 | 11445 | 65 564 499 | PASS |
| `04_O2` | 8654 | 7497 | 65 648 107 | PASS |
| `05_Oz_static_stack` | 2995 | 2565 | 33 588 245 | PASS |
| `06_Oz_no_licm_cse` | 3988 | 3584 | 31 403 069 | PASS |
| `07_Oz_no_lsr` | 4816 | 4052 | 65 968 593 | PASS |
| `08_Oz_gc_sections` | 4430 | 3996 | 65 979 155 | PASS |
| `09_Oz_prod_like` | **2806** | 2446 | **22 649 211** | PASS |
| `10_Oz_no_licm_cse_lsr` | 4344 | 3596 | 31 426 610 | PASS |
| `11_Oz_no_licm_cse_gc` | 3968 | 3584 | 31 403 069 | PASS |
| **`12_Oz_no_omit_fp`** | **3805** | **3351** | **41 788 650** | PASS |
| **`13_Oz_no_omit_fp_no_licm_cse_gc`** | **3488** | **3104** | **25 468 348** | PASS |

Best non-`+static-stack` config is now `13_Oz_no_omit_fp_no_licm_cse_gc`
at 3488 B (was 3968 at `11_Oz_no_licm_cse_gc` — **−480 B**).
`09_Oz_prod_like` remains the absolute winner via `+static-stack`.

## llvm-z80 HEAD: `3d296f439645` (post-#164 TruncInstCombine cost gate)

Captured 2026-05-15 session 72.  Lands ravn/llvm-z80#163 (and-mask
synthetic trunc root) under the #164 TTI-isZExtFree cost gate.  On Z80
the gate is `!hasOneUse && !isZExtFree(NarrowTy, OrigTy)`; Z80 returns
isZExtFree=false, so multi-use ands are blocked.  Single-use ands fire
but produce no net byte movement on this corpus (session 71 prediction
held).

### AES corpus

| Config | bin B | vs post-#157 | verify |
|---|------:|---:|:------:|
| `01_baseline_Oz` | 4450 | 0 | PASS |
| `02_Os` | 4725 | 0 | PASS |
| `03_O3` | 12688 | 0 | PASS |
| `04_O2` | 8654 | 0 | PASS |
| `05_Oz_static_stack` | 2995 | 0 | PASS |
| `06_Oz_no_licm_cse` | 3988 | 0 | PASS |
| `07_Oz_no_lsr` | 4816 | 0 | PASS |
| `08_Oz_gc_sections` | 4430 | 0 | PASS |
| `09_Oz_prod_like` | 2806 | 0 | PASS |
| `10_Oz_no_licm_cse_lsr` | 4344 | 0 | PASS |
| `11_Oz_no_licm_cse_gc` | 3968 | 0 | PASS |
| `12_Oz_no_omit_fp` | 3805 | 0 | PASS |
| `13_Oz_no_omit_fp_no_licm_cse_gc` | 3488 | 0 | PASS |

All 13/13 byte-identical to post-#157 baseline.  Cost gate works as
designed.

### z80-utils test-runner

| Total | PASS | FAIL | FATAL | SKIP |
|------:|-----:|-----:|------:|-----:|
| 990 | 685 | 42 | 56 | 207 |

Identical to session 71 baseline.  No regressions.

### What this commit enables (not realised on AES corpus)

- ravn/llvm-z80#163 infrastructure is now in main.  When future work
  improves either the cost model (phase 2 of #164: byte budget instead
  of boolean gate) or upstream KnownBits tracking through rotate idioms
  (#162 path 3), the and-mask sink will fire on more chains without
  changing this code.
- On non-Z80 targets where `isZExtFree=true` (x86 mostly), the
  synthetic root fires unconditionally.  Existing upstream lit test
  `trunc_multi_uses.ll` continues to PASS via the new path.

## llvm-z80 HEAD: `519aaaec4817` (post-#162 path 2 callee-body peek)

Captured 2026-05-15 session 72.  Lands ravn/llvm-z80#162 path 2:
per-callee body peek for call-arg trunc-root injection.  When the
callee's entry block begins with `trunc iW %arg to iM` or the
canonical `and iW %arg, 2^M - 1`, the chain feeding the corresponding
caller argument is narrowable via a synthetic trunc-zext bracket at
the call site.

### AES corpus

| Config | bin B | vs post-#157 | verify |
|---|------:|---:|:------:|
| `01_baseline_Oz` | 4330 | **−120** | PASS |
| `02_Os` | 4605 | **−120** | PASS |
| `03_O3` | 12688 | 0 | PASS |
| `04_O2` | 8654 | 0 | PASS |
| `05_Oz_static_stack` | 2911 | **−84** | PASS |
| `06_Oz_no_licm_cse` | 3867 | **−121** | PASS |
| `07_Oz_no_lsr` | 4696 | **−120** | PASS |
| `08_Oz_gc_sections` | 4310 | **−120** | PASS |
| `09_Oz_prod_like` | **2721** | **−85** | PASS |
| `10_Oz_no_licm_cse_lsr` | 4223 | **−121** | PASS |
| `11_Oz_no_licm_cse_gc` | 3847 | **−121** | PASS |
| `12_Oz_no_omit_fp` | 3691 | **−114** | PASS |
| `13_Oz_no_omit_fp_no_licm_cse_gc` | **3373** | **−115** | PASS |

11/13 configs improved by 84–121 B.  Production knob `09_Oz_prod_like`
moved from 2806 B to **2721 B**.  Best non-static-stack
`13_Oz_no_omit_fp_no_licm_cse_gc` from 3488 B to **3373 B**.

### z80-utils test-runner

| Total | PASS | FAIL | FATAL | SKIP |
|------:|-----:|-----:|------:|-----:|
| 990 | 685 | 42 | 56 | 207 |

Identical to baseline.  No regressions.

### Per-function deltas (01_baseline_Oz)

| Function | post-#157 | post-#162-p2 | Δ | notes |
|---|---:|---:|---:|---|
| `rj_sb_inv` | 156 | **36** | **−120** | matches ANSI variant; `llvm.fshl.i8` ×3 recognised |
| `rj_xtime` | ~51 | 20 | −31 | (estimate, was reported 51 B / 2.83× in ANALYSIS.md) |
| `gf_log` | 153 | 153 | 0 | callee peek didn't match within 8-inst scan window |
| `gf_alog` | 27 | 27 | 0 | (small; not a peek target) |
| `gf_mulinv` | 21 | 21 | 0 | (callee, body simplifies away) |
| `rj_sbox` | 22 | 22 | 0 | (no K&R-narrow path that fires) |
| `aes_mc_inv` | 460 | 460 | 0 | BSS-spill cluster, not a call-arg problem |
| `aes_mixColumns` | (FP-dep) | (FP-dep) | 0 | similar |

### Residual structural gap

`gf_log` and `gf_alog` still carry their K&R-narrow K&R-call shape but
the callee body has more complex prologue (likely 16-bit table lookups
or icmp-against-i16 patterns) that the peek doesn't recognise within
the 8-instruction scan window.  Future work: widen the scan, or move
the peek to a KnownBits-across-ABI analysis.

### Per-function (clang K&R) at default vs `-fno-omit-FP`

| Function | default | `-fno-omit-FP` | Δ B |
|---|------:|------:|------:|
| `aes_mc_inv` | 460 | **330** | −130 |
| `aes_expDecKey` | 604 | **495** | −109 |
| `aes_expandEncKey` | 529 | **442** | −87 |
| `aes_shiftRows` | 271 | **200** | −71 |
| `aes_sr_inv` | 271 | **200** | −71 |
| `aes_mixColumns` | 300 | **236** | −64 |
| `gf_log` | 153 | **113** | −40 |
| `aes_sb_inv` | 127 | 101 | −26 |
| `aes_subBytes` | 127 | 101 | −26 |
| `aes_addRoundKey` | 135 | 116 | −19 |
| `rj_sb_inv` | 156 | 150 | −6 |
| `aes_done` | 54 | 58 | **+4** |
| (others) | unchanged | unchanged | 0 |

Net: −649 B summed (out of 4450 B function-level total — −14.6%).
Tested all 4 corpus cells: PASS.  Gap vs zsdcc shrinks K&R +846 → +201,
ANSI +637 → +4 (essentially tied).

## llvm-z80 HEAD: `fix-165-icmp-and-mask-outside-user` merged (post-#165)

Captured 2026-05-15 session 73.  Lands ravn/llvm-z80#165 in two parallel
extensions to the TruncInstCombine outside-graph user allowlist:

* **Icmp with non-constant Other operand** (companion of #160) — when
  Other is provably narrow via KnownBits (e.g. `(and W, 2^M - 1)`),
  the icmp narrows alongside the graph.  Cost-gate: `Other->hasOneUse()`.

* **And-mask outside-user** (the dominant blocker in gf_log) — accept
  `(and X, Const)` where X is in-graph and Const fits in the narrow
  type.  Rewritten as `(zext (and Xnarrow, ConstTrunc) to OrigTy)` so
  downstream consumers keep their original type.  InstCombine
  canonicalises the zext-and-consumer chains afterward.

Also fixes a latent ordering bug: phi-erase RAUW'd in-graph phis with
poison BEFORE the rewrite loops, leaving outside-graph users with
poison operands.  Pending* rewrites now run first, then phi-erase.

### AES corpus

| Config | bin B | vs post-#162-p2 | verify |
|---|------:|---:|:------:|
| `01_baseline_Oz` | 4205 | **−125** | PASS |
| `02_Os` | 4480 | **−125** | PASS |
| `03_O3` | 12559 | **−129** | PASS |
| `04_O2` | 8529 | **−125** | PASS |
| `05_Oz_static_stack` | 2855 | **−56** | PASS |
| `06_Oz_no_licm_cse` | 3815 | **−52** | PASS |
| `07_Oz_no_lsr` | 4571 | **−125** | PASS |
| `08_Oz_gc_sections` | 4185 | **−125** | PASS |
| `09_Oz_prod_like` | **2695** | **−26** | PASS |
| `10_Oz_no_licm_cse_lsr` | 4171 | **−52** | PASS |
| `11_Oz_no_licm_cse_gc` | 3795 | **−52** | PASS |
| `12_Oz_no_omit_fp` | 3606 | **−85** | PASS |
| `13_Oz_no_omit_fp_no_licm_cse_gc` | **3328** | **−45** | PASS |

All 13 configs improved (−26 to −129 B).  Production knob
`09_Oz_prod_like` moved from 2721 B to **2695 B**.

Runtime tstates: dropped from 65M to 15M on baseline_Oz (4× speedup),
22M → 15M on the production knob (30% speedup).  Cause: gf_log's
16-bit phi loop became an 8-bit loop, AES-256 decryption inner loop
~3× faster.

### z80-utils test-runner

| Total | PASS | FAIL | FATAL | SKIP |
|------:|-----:|-----:|------:|-----:|
| 990 | 685 | 42 | 56 | 207 |

Identical to baseline (clang suite).  No regressions.

### Per-function deltas (01_baseline_Oz)

| Function | post-#162-p2 | post-#165 | Δ | notes |
|---|---:|---:|---:|---|
| `gf_log` | 153 | **28** | **−125** | 5.4×; chain narrowed end-to-end |
| `gf_alog` | 27 | 27 | 0 | already small |
| `gf_mulinv` | 21 | 21 | 0 | callee narrowing was already done |
| `rj_sb_inv` | 36 | 36 | 0 | already at parity (session 72) |
| `rj_sbox` | 22 | 22 | 0 | no new path fires |
| `rj_xtime` | 20 | 20 | 0 | already narrowed (session 72) |
| `aes_mc_inv` | 460 | 460 | 0 | BSS-spill cluster, separate work |
| `aes_mixColumns` | 300 | 300 | 0 | similar |

### Residual structural gap

`aes_mc_inv` (460 B) and `aes_mixColumns` (300 B) remain the largest
AES gap-vs-zsdcc functions, both BSS-spill heavy.  These are #89/#27
regalloc cluster work, orthogonal to trunc-narrowing.

## How to re-capture if HEAD moves

The two-step:
1. Build native clang: `ninja -C build-macos clang llc`
   (full paths: see `reference_z80_tool_paths.md` in memory)
2. `cd tasks/aes256-corpus && make clean && make sweep_clang`
   for the corpus, then run the test-runner per the invocation above.

A/B against the previous baseline by stashing the patch under test,
running through the same recipe, comparing both tables here.

The patch oracle gate is:
- test-runner PASS/FAIL/FATAL/SKIP counts unchanged (or improved)
- all previously-PASS sweep configs still PASS
- size deltas are non-positive (don't ship size regressions on baseline)
