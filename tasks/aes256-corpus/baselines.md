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
