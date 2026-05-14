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

## Headline — 4-cell baseline matrix

```
Variant   zsdcc bin  clang bin   gap B      ×    zsdcc ts    clang ts      ×
K&R            3604       5114   +1510  1.42×    14185104    66121724   4.66×
ANSI           3336       4375   +1039  1.31×    12118593    59725323   4.93×
```

ANSI vs K&R: clang.bin **−14.5%**, zsdcc.bin **−7.4%**.

zsdcc wins this real-world workload by **42% on size / 4.66× on
runtime** under K&R; by **31% / 4.93×** under ANSI. This
**reverses** the micro-corpus result in
`sccz80-oracle-corpus/findings-2026-05-13.md` where clang was 1.5×
smaller than zsdcc on synthetic patterns.

The reversal is the headline finding. The micro-corpus measured
clang's strengths (mid-end identity recognition, branchless boolify,
LDIR-overlap fill). AES is dominated by clang's weaknesses: regalloc
churn under high pressure, BSS spill traffic, the LICM+CSE
pessimization (open issue #128), the K&R int-promotion cascade
(filed as #158 + #160 + the propagation-into-callers Effect 3), the
silent miscompile in ANSI chained rotates (#159), and the
`+static-stack` AES miscompile (#156).

Observation worth flagging: under ANSI, the clang/zsdcc runtime
ratio actually **gets worse** (4.66× → 4.93×) even though both
compilers run faster. zsdcc benefits more proportionally on runtime
than clang does. Suggests the K&R int-promotion was masking some
zsdcc runtime overhead that's now visible — orthogonal to the size
analysis. Worth a small follow-up investigation.

## Best PASS configs from the sweeps

### clang

| Config | bin B | tstates | vs baseline |
|---|---:|---:|---|
| `01_baseline_Oz` | 5114 | 66.1M | — |
| **`06_Oz_no_licm_cse`** | **4733** | **31.6M** | −381 B / −52.2% runtime |
| **`11_Oz_no_licm_cse_gc`** | **4682** | 31.6M | −432 B / −52.2% runtime (smallest PASS) |
| `10_Oz_no_licm_cse_lsr` | 5089 | 31.6M | −25 B / −52.2% runtime |
| `07_Oz_no_lsr` | 5480 | 66.1M | +366 B, no speed change |

The clear win: `-mllvm -disable-machine-licm -mllvm -disable-machine-cse`.
**−7.4% size + −52.2% runtime in a single flag pair.** Validates
[ravn/llvm-z80#128](https://github.com/ravn/llvm-z80/issues/128)
("MachineLICM and MachineCSE pessimize at -Oz on Z80") with
much sharper numeric evidence than the original cpnos-rom data.

Adding `-ffunction-sections -fdata-sections --gc-sections` on top
saves another 51 B (config 11). LSR helps on AES (+366 B without
it), counter to the cpnos-rom production decision to disable it —
worth re-measuring on cpnos-rom (open task).

### zsdcc

| Config | bin B | tstates | vs baseline |
|---|---:|---:|---|
| `01_baseline_prod` | 3604 | 14.2M | — |
| **`11_max_allocs_100000`** | **3589** | 14.2M | −15 B (smallest PASS) |
| `02_sdcccall_0` | 3682 | 14.2M | +78 B (stack-arg ABI cost) |
| `05_SO0` (no peephole) | 3802 | 15.4M | +198 B / +8.4% runtime |

Findings:
- **`--sdcccall 1`** is worth ~2% size over stack-arg ABI on this
  workload (smaller win than micro-corpus saw, because helper-call
  ABI mismatch isn't reached).
- **`--max-allocs-per-node 100000`** earns ~0.4% size over the
  production 25000 — diminishing returns; production setting is
  near-optimum.
- **`--no-peep`, `--all-callee-saves`, `--reserve-regs-iy`
  (keep_frame_ptr)**: byte-identical to baseline → these knobs have
  no effect on AES-shape code under production flags.
- **`-SO0`** costs ~5% size / 8% speed → peephole is real value.
- **`--opt-code-speed`** is 81 B BIGGER than `--opt-code-size`
  *and* only 1.2% faster → not a useful trade on this workload.

## Filed issues (this corpus's queue, none fixed)

### ravn/llvm-z80 (5 issues)

| # | Title | Manifestation on corpus | Repro |
|---|---|---|---|
| **#156** | `+static-stack` miscompile (ret pops corrupted return addr) | clang +static-stack FAILs AES decrypt; would be −1.7 KB if fixed | `repros/repro_clang_static_stack.c` |
| **#157** | Spill-storm under high register pressure (SP-recompute per access) | aes_mc_inv +549 B, aes_mixColumns +289 B, gf_log +121 B | `repros/repro_aes_mc_inv_spill_storm.c` + `analysis/aes_mc_inv/ANALYSIS.md` |
| **#158** | K&R int-promotion blocks u8 rotate recognition (body bloat) | rj_sb_inv 156 B vs 16 B ANSI (5.20× ratio) | `repros/repro_rj_sb_inv_bisect.c` |
| **#159** | Silent miscompile in ANSI chained u8 rotates (uses uninit E reg) | ANSI rj_sb_inv produces wrong output despite 16 B clean code | `analysis/EXPERIMENT_full_ansi.md` bisection record |
| **#160** | K&R callee declaration bloats CALLER's regalloc 87% | mc_loop 460→863 B from `f`'s declaration style alone | `repros/repro_kr_callee_propagates.c` |

Cross-cutting: also validates open issue
[**#128**](https://github.com/ravn/llvm-z80/issues/128) (MachineLICM/CSE
pessimize on Z80) with **−52% runtime** on AES, much sharper than
the original cpnos-rom evidence.

### ravn/z88dk (2 issues)

| # | Title | Manifestation | Repro |
|---|---|---|---|
| **#5** | zsdcc `--nogcse` drops late-assigned absolute-pointer writes after struct-arg call | All writes through `r = (uint8_t *)0xC000;` elided | `repros/repro_nogcse_late_r.c` |
| **#6** | zsdcc `-clib=sdcc_ix` silently miscompiles AES output | Wrong ciphertext, 33% larger code | `repros/repro_clib_ix.c` |

### Strategic frame

Per `GOAL.md`: two-track mission. Clang track is upstream-LLVM work
on int-promotion narrowing + regalloc quality. SDCC track is
upstream-SDCC work on the two correctness bugs.

Until the issues are fixed, the workarounds are:
- **Clang track**: use ANSI prototypes where possible. Even with #159
  blocking one function, the corpus-wide ANSI variant saves 14.5%
  binary size (5114 → 4375 B). Production cpnos-rom is already
  ANSI; aes256.c is the upstream-K&R source kept for provenance.
- **SDCC track**: avoid `--nogcse` and `-clib=sdcc_ix`. Stick with
  the production `-clib=sdcc_iy --sdcccall 1` recipe.

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

1. **Adopt `-mllvm -disable-machine-licm -mllvm -disable-machine-cse`
   as the corpus baseline** — already in production cpnos-rom flags
   per CLAUDE.md.
2. **Re-measure cpnos-rom with LSR enabled** — AES shows LSR helps;
   production currently disables it. Worth a sweep on actual
   cpnos-rom workload before flipping the default.
3. **Add AES to the regular regression suite** — runtime tstate
   metric is a much sharper signal than size alone.
4. **Find the DEMO.COM-producing compiler** — try other HiTech flags,
   BDS C, Aztec C.
5. **Continue down the priority queue**: aes_shiftRows / aes_sr_inv
   (+102 / +100 B each), then aes_subBytes / aes_sb_inv /
   aes_addRoundKey (+85 B each). Per the per-function survey, all
   are #157 variants — confirm and add as evidence comments to #157
   without filing duplicate issues.
6. **Investigate why zsdcc gets a bigger runtime ratio improvement
   under ANSI than clang** (4.66× → 4.93×). Probably reveals an
   SDCC peephole that's K&R-blocked. Worth a brief bisect.
7. **Wait on the 5 llvm-z80 + 2 z88dk filed issues**. Re-run
   `make test` and `make sweep` after each fix to capture FAIL→PASS
   transitions and size deltas.
8. **Extend sweeps to ANSI variant** — currently sweeps target
   K&R only. Doubling sweep time is justified once we have an upstream
   fix landing that affects both variants differently.

## How to interpret the sweep tables

`clang-flag-sweep.md` and `sdcc-flag-sweep.md` are checked into git.
After any compiler change, `make sweep` updates both and a
`git diff` surfaces any size or runtime regression on a specific
flag combination. PASS/FAIL column also catches correctness
regressions.
