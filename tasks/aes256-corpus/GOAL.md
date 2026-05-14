# AES-256 corpus — strategic goal

The aes256-corpus exists to drive **clang-z80 (ravn/llvm-z80) up to
zsdcc parity** on real-world Z80 code, and to surface **SDCC bugs**
encountered along the way as filed issues with reproducible test
cases.

Two parallel tracks, each producing a queue of upstream-bound work.

## Track 1 — SDCC: collect compiler failures as issues with test cases

Every zsdcc miscompile or surprising codegen result surfaced by the
flag sweep becomes a separate issue in `ravn/z88dk` with:

- A self-contained minimal C reproducer (stored under
  `aes256-corpus/repros/`)
- Exact build flags + z88dk-ticks invocation
- Expected vs actual output
- Bisection notes when relevant (which sub-flag triggers the bug,
  which sub-flag masks it)

**Goal of the queue:** when SDCC engagement deepens (currently
distant — `project_z80_simple_host_complex` posture), batch the queue
as a single upstream summary for the SDCC maintainers. The issues
under `ravn/z88dk` are the tracking layer; upstream filings are a
later step driven by user decision.

**Current queue** (issues filed against `ravn/z88dk`):

| # | Title | Repro file |
|---|---|---|
| 5 | `--nogcse` drops writes through late-assigned absolute-address pointer | `repros/repro_nogcse_late_r.c` |
| 6 | `-clib=sdcc_ix` produces wrong AES output (silent miscompile) | `repros/repro_clib_ix.c` |

Existing pre-AES queue (from earlier work, not AES-specific):
- ravn/z88dk#1 — zsdcc block-scoped var undefined under deep nesting
- ravn/z88dk#2 — const-qualified 16-bit pointer uses byte-wise load
- ravn/z88dk#3 — missing C23 #embed support
- ravn/z88dk#4 — const-expression `(uint16_t)X >> 8` returns 0xFF

## Track 2 — clang: drive llvm-z80 output to SDCC parity

The aes256.c text-segment size gap is **+1699 B (clang 4660 vs zsdcc
2961, 1.57×)**. Each material per-function gap is a candidate for a
filed llvm-z80 issue with a reduced test case.

Per-function ranking (from `findings.md`, sorted by absolute B-saved
if clang reached zsdcc parity):

| Function | clang | zsdcc | gap B | gap × |
|---|---:|---:|---:|---:|
| **aes_mc_inv** | 863 | 314 | **+549** | 2.75× |
| **aes_mixColumns** | 530 | 241 | **+289** | 2.20× |
| **rj_sb_inv** | 156 | 30 | **+126** | 5.20× ‼ |
| **gf_log** | 153 | 32 | **+121** | 4.78× ‼ |
| aes_shiftRows | 271 | 169 | +102 | 1.60× |
| aes_sr_inv | 271 | 171 | +100 | 1.58× |
| aes_subBytes | 127 | 42 | +85 | 3.02× |
| aes_sb_inv | 127 | 42 | +85 | 3.02× |
| aes_addRoundKey | 135 | 50 | +85 | 2.70× |
| aes256_decrypt_ecb | 216 | 146 | +70 | 1.48× |
| aes256_encrypt_ecb | 228 | 164 | +64 | 1.39× |
| rj_xtime | 51 | 18 | +33 | 2.83× |
| aes_ar_cpy | 123 | 98 | +25 | 1.26× |
| aes256_init | 152 | 137 | +15 | 1.11× |
| aes_expandEncKey | 529 | 523 | +6 | 1.01× ✓ |
| aes_expDecKey | 604 | 603 | +1 | 1.00× ✓ |

Plus three functions where clang **wins**:
- aes_done (54 B vs 89, −35 B, 0.61×)
- rj_sbox (22 B vs 31, −9 B, 0.71×)
- gf_mulinv (21 B vs 31, −10 B, 0.68×)

### Priority targets

By absolute B saved:
1. **`aes_mc_inv`** (+549 B) — largest single function. Inverse mix-
   columns: tight 4-iteration loop with 9 byte locals (`a,b,c,d,e,x,y,z`)
   and double-`rj_xtime` calls. Suspected weakness: high register
   pressure + repeated SP-relative byte spills.
2. **`aes_mixColumns`** (+289 B) — same pattern, shorter (no double
   xtime).
3. **`rj_sb_inv`** (+126 B, **5.2×**) — small function, biggest *ratio*
   gap. The C is a bitwise rotate chain `y<<1|y>>7`, `y<<2|y>>6`,
   `y<<3|y>>5` then XOR. Should generate `rlca; rlca; ...` sequences;
   suspect clang is missing the rotate-pattern peephole.
4. **`gf_log`** (+121 B, **4.78×**) — tight `while` loop with
   carry-chain XOR and break. Suspect flag-recomputation regression
   (per partly-overlapping open llvm-z80#77).

### Process per function

For each priority target:

1. Build with and without each `-mllvm -disable-*` flag from the
   sweep; record which knobs already help. (Done: corpus rows 06,
   10, 11 — global wins. Per-function flag-specific wins TBD.)
2. Read the clang asm output (`llvm-objdump -d` on the .o).
3. Compare to the zsdcc asm output (preserve via `zcc -a`).
4. Identify the specific codegen pattern that's worse.
5. Construct a minimal C reproducer that isolates the pattern.
6. File as `ravn/llvm-z80` issue with the reproducer + size delta
   + suspected fix area (peephole, regalloc, instruction-selection,
   GISel combiner).
7. **Do NOT fix immediately.** Per
   `project_z80_simple_host_complex` + `project_z80_upstream_goal`,
   accumulate the queue; eventually a clean-room reimplementation
   effort lands fixes upstream LLVM (or in ravn/llvm-z80 as a step
   to that).

### Done-when

Each per-function gap closed (clang_size ≤ zsdcc_size + 5%):
- An issue exists in `ravn/llvm-z80` with a reduced reproducer
  and the size-delta documented
- A follow-up commit on the corpus's `clang-flag-sweep.md`
  captures the size move when the fix lands

Track-2 done when total aes256.c text-segment delta `Δbin ≤ 0`
under the best PASS clang config — i.e., clang has reached or
beaten zsdcc on this corpus.

## What we are NOT doing here

- **No fixes in this corpus directory.** All fix work lands in
  `llvm-z80/` (clang) or `z88dk/` (sdcc), driven by separate
  sessions, with re-measurement here as the validation oracle.
- **No PRs upstream.** Even when the fix queue is rich enough
  to summarise upstream, the user makes that call (see
  `feedback_no_pull_requests`).
- **No engagement with the AES algorithm itself.** This corpus
  treats AES as opaque C source. Algorithm-level optimisations
  (e.g. precomputed S-boxes via `BACK_TO_TABLES`) are explicitly
  out of scope — they would change the codegen surface area and
  invalidate the comparison.

## How this aligns with the project plan

Per `CLAUDE.md`:
> Phase 3 Cluster A regalloc 3 of 5 closed (#94, #98, #99); #89 +
> #27 remain as multi-session investigations expected to subsume
> #38. Engagement-mode gate is **one cluster away**.

The AES per-function gap analysis is concrete evidence for which
**Phase 3 Cluster A** patterns matter on real workloads. The biggest
gaps (`aes_mc_inv`, `aes_mixColumns`) are exactly the
pointer-heavy / high-register-pressure code that #89 + #27 target.
Closing those clusters should close most of the AES gap in one go.

Per `project_z80_upstream_goal`:
> Near-term target llvm-z80/llvm-z80 (active fork parent); long-term
> aspiration llvm/llvm-project; collaborate with owner first.

The AES per-function issues filed here are the **first ravn/llvm-z80
queue** of real-world-evidence codegen issues. They feed into the
collaboration model with the upstream owner.
