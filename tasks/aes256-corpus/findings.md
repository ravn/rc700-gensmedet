# AES-256 corpus — compiler-efficiency findings

Source: <http://z80.eu/downloads/aes256.zip> — byte-oriented AES-256
by Ilya O. Levin with CP/M-compat tweaks by Peter Dassow. ~13 KB C
source; ~20 functions; exercises real-world codegen patterns
(pointer chasing through nested struct fields, 16-byte byte-buffer
loops, sequential XOR/shift/rotate, register pressure from 4-deep
round keys).

The reference `DEMO.COM` in the upstream zip is 9216 B as built by
Peter Dassow's CP/M-targeted compiler. Provenance is NOT preserved
in the zip — see "DEMO.COM provenance" section below.

## Headline — 4-cell baseline + tuned matrix

**Post-session 73k (2026-05-20): full ANSI sweep landed; previous
K&R-vs-ANSI conclusions reframed.**

Baseline = each compiler's untouched default config
(`01_baseline_Oz` for clang `-Oz`; `01_baseline_prod` for zsdcc with
production cpnos-rom flag set).  Tuned = each compiler's smallest
PASS in its 13-config sweep.

```
                       K&R bin    K&R tstates       ANSI bin   ANSI tstates
clang baseline           4111     15,704,339          4047       16,021,371
clang tuned              2695     15,201,006          2636       15,515,354
                       (09_prod_like)               (09_prod_like)
zsdcc baseline           3604     14,185,104          3323       12,080,289
zsdcc tuned              3589     14,178,600          3323       12,080,289
                       (11_max_allocs_100000)       (01_baseline_prod)
```

### Three headline reframings vs older findings

**1. Apples-to-apples reversal — clang wins on size.**  Earlier text
("zsdcc wins by 1.29×") compared zsdcc-tuned vs clang-baseline.
Comparing **smallest PASS to smallest PASS**:

| | clang smallest | zsdcc smallest | clang advantage |
|---|---:|---:|---:|
| K&R | 2695 | 3589 | **−894 B / −24.9%** |
| ANSI | **2636** | 3323 | **−687 B / −20.7%** |

With both compilers at their best flag set, **clang is 20-25%
smaller**.  The micro-corpus result (clang 1.5× smaller) is not
reversed here — it is *reinforced* once the comparison is fair.

**2. Runtime ratio collapsed.**  Old documented value: zsdcc 4.65×
faster than clang on K&R, 4.93× on ANSI.  Current measurement:

| | clang | zsdcc | zsdcc advantage |
|---|---:|---:|---:|
| K&R baseline | 15.70 Mts | 14.19 Mts | **1.11×** |
| K&R tuned | 15.20 Mts | 14.18 Mts | **1.07×** |
| ANSI tuned | 15.52 Mts | 12.08 Mts | **1.28×** |

The 4.65× figure predates the LICM/CSE diagnosis and S3'
(`006ba9607dd1`); current clang baseline runs at 15.7 Mts (was 66.0
Mts).  zsdcc is still faster, but it is a percentage gap, not a
multiplier.  The ANSI ratio is wider than K&R because zsdcc gains
more from ANSI on speed (14.2 → 12.1 Mts, −15%) than clang does
(15.7 → 15.5 Mts, −1%).

**3. SDCC's K&R int-promotion penalty is far worse than clang's.**
ANSI delta at baseline:

| | K&R | ANSI | Δ | Δ % |
|---|---:|---:|---:|---:|
| clang | 4111 | 4047 | −64 | −1.6% |
| zsdcc | 3604 | 3323 | **−281** | **−7.8%** |

zsdcc's iCode allocator cannot see through `int` widening the way
LLVM's AggressiveInstCombine can.  The asymmetry means we should
prefer ANSI sources at the project level — and may motivate a
separate SDCC-side issue for "int-promotion narrowing".

### ravn/z88dk #5 and #6 are K&R-only

Both K&R-FAIL configs PASS cleanly on ANSI:

| Config | K&R | ANSI | Bug |
|---|---|---|---|
| `08_nogcse` | FAIL (3711 / 14.2 Mts) | **PASS** (3368 / 12.08 Mts) | ravn/z88dk#5 |
| `09_clib_ix` | FAIL (4793 / 31.9 Mts — runaway) | **PASS** (4579 / 12.32 Mts) | ravn/z88dk#6 |

Both bugs reclassified from "SDCC miscompile" to "SDCC
K&R-with-flag-X miscompile".  Issues updated with the
ANSI-confirmed repro.  Workaround is now obvious: use ANSI
prototypes.  The 33% bloat from `-clib=sdcc_ix` (vs `sdcc_iy`)
remains under ANSI — that part of #6 is a quality issue, separate
from the correctness bug.

## Best PASS configs from the sweeps (post-session 73k refresh)

### clang — K&R

| Config | bin B | tstates | vs baseline |
|---|---:|---:|---|
| `01_baseline_Oz` | 4111 | 15.70M | — |
| `06_Oz_no_licm_cse` | 3815 | 15.54M | −296 B / −1.0% runtime |
| `11_Oz_no_licm_cse_gc` | 3795 | 15.54M | −316 B / −1.0% runtime |
| `12_Oz_no_omit_fp` | 3568 | 15.49M | −543 B / −1.4% runtime |
| `13_Oz_no_omit_fp_no_licm_cse_gc` | 3328 | 15.37M | −783 B / −2.1% runtime |
| `05_Oz_static_stack` | 2830 | 15.26M | −1281 B / −2.8% runtime |
| **`09_Oz_prod_like`** | **2695** | **15.20M** | **−1416 B / −3.2% runtime (smallest PASS)** |

### clang — ANSI

| Config | bin B | tstates | vs baseline |
|---|---:|---:|---|
| `01_baseline_Oz` | 4047 | 16.02M | — |
| `13_Oz_no_omit_fp_no_licm_cse_gc` | 3269 | 15.69M | −778 B / −2.1% runtime |
| `05_Oz_static_stack` | 2766 | 15.58M | −1281 B / −2.8% runtime |
| **`09_Oz_prod_like`** | **2636** | **15.52M** | **−1411 B / −3.1% runtime (smallest PASS)** |

`09_Oz_prod_like` =
`-Oz -Xclang -target-feature -Xclang +static-stack -mllvm -disable-lsr -mllvm -disable-machine-licm -mllvm -disable-machine-cse -ffunction-sections -fdata-sections`
is the canonical production recipe and dominates on both variants.
The big single-flag-pair win is still `-mllvm -disable-machine-licm
-mllvm -disable-machine-cse` (validates [ravn/llvm-z80#128]) — but
the runtime impact (−1 to −2% post-S3') is much smaller than the
previously-documented −52.2%, which predates session 73b's S3' fix
landing.

LSR helps on K&R (+366 B without it on `07_Oz_no_lsr`) and is
disabled in cpnos-rom production — re-measuring cpnos-rom with LSR
enabled remains the open follow-up.

### zsdcc — K&R

| Config | bin B | tstates | vs baseline |
|---|---:|---:|---|
| `01_baseline_prod` | 3604 | 14.19M | — |
| **`11_max_allocs_100000`** | **3589** | 14.18M | −15 B (smallest PASS) |
| `02_sdcccall_0` | 3682 | 14.19M | +78 B (stack-arg ABI cost) |
| `05_SO0` (no peephole) | 3802 | 15.37M | +198 B / +8.4% runtime |
| `08_nogcse` | 3711 | 14.20M | **FAIL — ravn/z88dk#5** |
| `09_clib_ix` | 4793 | 31.90M | **FAIL — ravn/z88dk#6** |

### zsdcc — ANSI

| Config | bin B | tstates | vs baseline |
|---|---:|---:|---|
| **`01_baseline_prod`** | **3323** | **12.08M** | — (smallest PASS — production is already optimal) |
| `06_SO2` | 3428 | 12.10M | +105 B |
| `02_sdcccall_0` | 3682 | 14.19M | +359 B (stack-arg ABI cost; speed regression too) |
| `08_nogcse` | 3368 | 12.08M | +45 B; now PASS — #5 is K&R-only |
| `09_clib_ix` | 4579 | 12.32M | +1256 B; now PASS — #6 K&R-only correctness, ANSI bloat remains |

Findings (carry over from prior sweep, refined):
- **`--sdcccall 1`** is worth ~2% size on K&R, ~10% on ANSI (the ABI
  win compounds with the int-promotion narrowing).
- **`--max-allocs-per-node 100000`** earns ~0.4% K&R, **zero ANSI**
  (3330 vs 3323).  Drop the suggestion to bump production's 25000.
- **`-SO0`** costs ~5% size / 8% speed on K&R, similar on ANSI —
  peephole continues to deliver real value.
- **`--opt-code-speed`** is +81 B K&R / +12 B ANSI, ~0–2% faster —
  not a useful trade on either variant.

## Filed issues (this corpus's queue, none fixed)

### ravn/llvm-z80 (5 issues)

| # | Title | Manifestation on corpus | Repro |
|---|---|---|---|
| **#156** | `+static-stack` miscompile (ret pops corrupted return addr) | clang +static-stack FAILs AES decrypt; would be −1.7 KB if fixed | `repros/repro_clang_static_stack.c` |
| **#157** | Spill-storm under high register pressure (SP-recompute per access) | aes_mc_inv +549 B, aes_mixColumns +289 B, gf_log +121 B | `repros/repro_aes_mc_inv_spill_storm.c` + `analysis/aes_mc_inv/ANALYSIS.md` |
| **#158** | K&R int-promotion blocks u8 rotate recognition (body bloat) | rj_sb_inv 156 B vs 16 B ANSI (5.20× ratio) | `repros/repro_rj_sb_inv_bisect.c` |
| **#159** | Silent miscompile in ANSI chained u8 rotates (uses uninit E reg) | ANSI rj_sb_inv produces wrong output despite 16 B clean code | `analysis/EXPERIMENT_full_ansi.md` bisection record |
| **#160** | K&R callee declaration bloats CALLER's regalloc 87% (residual after #158 is missed AggressiveInstCombine icmp-sink narrowing) | mc_loop 460→863 B from `f`'s declaration style alone; 77 B residual post-#158 due to surviving `icmp samesign ult i16 X, 128` | `repros/repro_kr_callee_propagates.c` + `repros/repro_160_icmp_narrow_missed.ll` |

Cross-cutting: also validates open issue
[**#128**](https://github.com/ravn/llvm-z80/issues/128) (MachineLICM/CSE
pessimize on Z80) with **−52% runtime** on AES, much sharper than
the original cpnos-rom evidence.

### ravn/z88dk (2 issues — both K&R-only after 73k re-measurement)

| # | Title | Manifestation | Repro | Notes |
|---|---|---|---|---|
| **#5** | zsdcc `--nogcse` drops late-assigned absolute-pointer writes after struct-arg call | K&R: all writes through `r = (uint8_t *)0xC000;` elided.  ANSI: PASS | `repros/repro_nogcse_late_r.c` | **K&R-only** (73k); ANSI sweep `08_nogcse` PASSes at 3368 B |
| **#6** | zsdcc `-clib=sdcc_ix` silently miscompiles AES output | K&R: wrong ciphertext, 33% larger code, runaway tstates.  ANSI: PASS but still 33% larger | `repros/repro_clib_ix.c` | Correctness bug **K&R-only** (73k); size bloat (+1256 B vs `sdcc_iy`) still present on ANSI |

### Strategic frame

Per `GOAL.md`: two-track mission. Clang track is upstream-LLVM work
on int-promotion narrowing + regalloc quality. SDCC track is
upstream-SDCC work on the two correctness bugs.

Until the issues are fixed, the workarounds are:
- **Clang track**: use ANSI prototypes where possible. Corpus-wide
  ANSI saves 1.6% size + 1.4% runtime over K&R at the same flags
  (session 73k refresh).  The much larger pre-session-73b numbers
  (14.5% / 4.9×) are stale; current bin sizes are
  K&R 4111 / ANSI 4047 at `-Oz` baseline.
- **SDCC track**: avoid `--nogcse` and `-clib=sdcc_ix` ON K&R.  Both
  correctness bugs disappear on ANSI sources.  Production cpnos-rom
  is already ANSI, so neither bug currently bites in production —
  but they remain unfixed in SDCC and the upstream issues should be
  resolved.  ANSI cuts size 7.8% over K&R on this workload, so the
  recommendation to keep `-clib=sdcc_iy --sdcccall 1 -Cs"--fomit-frame-pointer"`
  is unchanged.

## Tooling findings (the ticks investigation)

`z88dk-ticks` has exactly two Z80 exit conditions (read from
`src/ticks/ticks.c`): `pc == end` or `st >= counter`. NOT HALT,
NOT `JP 0`, NOT any port output. Bare miscompiles whose escaped
PC wraps 0xFFFF→0x0000 trigger ticks's `if (pc == start) st = 0`
reset (default `start = 0x0000`), so the counter never fires —
ticks runs forever for an apparent 30s+ wallclock per binary.

**Mitigation in this corpus:** `fill_with_jp_done.py` pads each
binary with `c3 LO HI` (= `JP done_addr`) bytes from end-of-code
to 0xBFFD. Any escape into "uninit" RAM lands on a `c3`-prefixed
instruction within at most 2 fetches, jumps to `done_addr`, and
ticks exits via `-end` within a few cycles. Confirmed: turns a
30s/binary hang into a 10 ms exit on the `+static-stack` miscompile.

The fill is applied transparently in both `flag_sweep.sh` and
`flag_sweep_sdcc.sh` (between `objcopy` and `ticks`), so no source
or harness change is required.

## DEMO.COM provenance

The upstream zip's `DEMO.COM` is 9216 B. Hypothesis: HiTech 3.09
since z80.eu/c-compiler.html implies HiTech as the canonical CP/M
C compiler.

Tested: `ghcr.io/ravn/hitech` Docker (HiTech 3.09x) compile of
`aes256.c + demo.c` with `-O` produces **12581 B**, byte-different
from `DEMO.COM` starting at offset 1. So not HiTech 3.09x with
basic `-O`. Probably one of:
- HiTech with different flag combo (`-Z`, `-O1`, etc.)
- HiTech 3.09 (not 3.09x)
- BDS C, Aztec C, or another listed compiler on z80.eu

Pending task to bisect further (low priority — not blocking
anything, just curiosity).

## What we'd do next (per todo.md follow-ups)

1. **Re-measure cpnos-rom with LSR enabled** — AES shows LSR helps;
   production currently disables it. Worth a sweep on actual
   cpnos-rom workload before flipping the default.
2. **Add AES to the regular regression suite** — runtime tstate
   metric is a much sharper signal than size alone.
3. **Find the DEMO.COM-producing compiler** — try other HiTech flags,
   BDS C, Aztec C.
4. **Continue down the per-function priority queue**: `aes_mc_inv`
   +549 B, `aes_mixColumns` +289 B, `rj_sb_inv` +126 B, `gf_log`
   +121 B, then `aes_shiftRows / aes_sr_inv` (+102 / +100 B).  Per
   the per-function survey, all are #157 variants — confirm and add
   as evidence comments to #157 without filing duplicate issues.
5. **File new SDCC issue: K&R int-promotion narrowing.**  Session
   73k showed zsdcc loses 7.8% to K&R vs ANSI (4.9× clang's
   penalty).  Suggests an iCode-allocator pass that fails to narrow
   through promoted-int comparisons / shifts.  Repro: the existing
   K&R vs ANSI AES sweep difference is itself the repro.
6. **Wait on the 5 llvm-z80 + 2 z88dk filed issues**. Re-run
   `make sweep` after each fix to capture FAIL→PASS transitions
   and size deltas.

### Done

- ~~Extend sweeps to ANSI variant~~ — landed session 73k.
  Sweep scripts now accept `AES_SRC`, `TSV_NAME`, `MD_NAME`,
  `MD_TITLE_SUFFIX` env vars; run as
  `AES_SRC=../aes256_ansi.c TSV_NAME=results_ansi.tsv MD_NAME=clang-flag-sweep-ansi.md ./flag_sweep.sh`
  (or the parallel `flag_sweep_sdcc.sh`).
- ~~Adopt `-mllvm -disable-machine-licm -mllvm -disable-machine-cse`
  as the corpus baseline~~ — already in production cpnos-rom flags;
  AES sweep keeps the no-flag baseline (`01_baseline_Oz`) as the
  reference point so the impact of those flags is visible in the
  table delta column.
- ~~`--max-allocs-per-node 100000` re-measurement~~ — session 73k
  ANSI sweep showed zero benefit over the 25000 production setting
  (3330 vs 3323 B).  Production setting is optimal.

## How to interpret the sweep tables

`clang-flag-sweep.md` and `sdcc-flag-sweep.md` are checked into git.
After any compiler change, `make sweep` updates both and a
`git diff` surfaces any size or runtime regression on a specific
flag combination. PASS/FAIL column also catches correctness
regressions.
