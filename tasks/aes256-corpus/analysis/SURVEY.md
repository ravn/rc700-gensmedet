# Per-function survey — clang vs zsdcc on aes256.c

Pattern-counting across all functions, after individual analysis of
the top 4 priority targets (`aes_mc_inv`, `aes_mixColumns`,
`rj_sb_inv`, `gf_log`).

## Pattern counts (clang baseline `-Oz`, zsdcc cpnos production flags)

| Function | clang asm B | SP-recomputes | IX uses | push-af | calls | zsdcc asm B | IX uses | calls | K&R? |
|---|---:|---:|---:|---:|---:|---:|---:|---:|:--:|
| `aes_subBytes` | 109 | 10 | **0** | 4 | 1 | 32 | 2 | 1 | ✓ |
| `aes_sb_inv` | 109 | 10 | **0** | 4 | 1 | 32 | 2 | 1 | ✓ |
| `aes_addRoundKey` | 116 | 12 | **0** | 5 | 0 | 37 | 4 | 0 | ✓ |
| `aes_ar_cpy` | 73 | 1 | **22** | 0 | 0 | 65 | 12 | 0 | ✓ |
| `aes_shiftRows` | 214 | 23 | **0** | 3 | 0 | 101 | 24 | 0 | ✓ |
| `aes_sr_inv` | 214 | 23 | **0** | 3 | 0 | 103 | 24 | 0 | ✓ |
| `aes_mixColumns` | 430 | 46 | **0** | 12 | 0 | 129 | 44 | 4 | ✓ |
| `aes_mc_inv` | 693 | 77 | **0** | 13 | 0 | 177 | 52 | 9 | ✓ |
| `rj_xtime` | 50 | 3 | **0** | 1 | 0 | 16 | 1 | 1 | ✓ |
| `rj_sbox` | 25 | 0 | **0** | 0 | 1 | 23 | 1 | 2 | ✓ |
| `rj_sb_inv` | (147) | many | **0** | 2 | 1 | 30 | 1 | 1 | ✓ |
| `gf_alog` | 35 | 0 | **0** | 0 | 0 | 26 | 1 | 1 | ✓ |
| `gf_log` | (153) | many | **0** | 1 | 0 | 32 | 0 | 0 | ✓ |
| `gf_mulinv` | 23 | 0 | **0** | 0 | 2 | 25 | 1 | 3 | ✓ |
| `aes_done` | 50 | 2 | **0** | 1 | 0 | 54 | 10 | 0 | **ANSI** |
| `aes256_init` | 90 | 0 | **25** | 4 | 1 | 73 | 21 | 1 | **ANSI** |
| `aes256_encrypt_ecb` | 104 | 1 | **47** | 0 | 8 | 107 | 10 | 11 | **ANSI** |
| `aes256_decrypt_ecb` | 99 | 1 | **45** | 0 | 9 | 94 | 9 | 10 | **ANSI** |

`(asm B)` ≠ binary B; the asm-byte count is roughly proportional to
final binary size but not the same. Binary sizes from `findings.md`.

## Pattern

The IX-vs-no-IX correlation in the table is with **pointer arg
count**, NOT with K&R-vs-ANSI:

- Functions with **1 pointer arg**: 0 IX uses (whether K&R or ANSI)
- Functions with **2+ pointer args**: many IX uses
- Functions with **0 pointer args** (gf_alog, gf_log, gf_mulinv,
  rj_sbox, rj_sb_inv, rj_xtime — all take a u8 by value, not by
  pointer): 0 IX uses

## Hypothesis: K&R blocks the IX-frame mode

**Single-function test result** (aes_subBytes, 1-pointer-arg):

```c
void aes_subBytes_kr(buf) unsigned char *buf;
{ register uint8_t i = 16; while (i--) buf[i] = rj_sbox(buf[i]); }

void aes_subBytes_ansi(uint8_t *buf)
{ register uint8_t i = 16; while (i--) buf[i] = rj_sbox(buf[i]); }
```

Both 125 B, identical. Looked like the K&R hypothesis was wrong.

## Updated finding: K&R DOES matter at corpus scale (just not via IX)

A full-corpus ANSI-conversion experiment
(`analysis/EXPERIMENT_full_ansi.md`) showed:

- clang.bin: 5114 → **4239 B (−17%)** with all K&R → ANSI
- zsdcc.bin: 3604 → 3323 B (−8%)
- Clang vs zsdcc gap: 1.57× → **1.41× (35% of gap closed)**

But where the savings actually came from is NOT what the single-
function test suggested:

| Function | Δ from K&R → ANSI | Notes |
|---|---:|---|
| `aes_mc_inv` | **−403 B** (47%) | Complex w/many locals; propagation? |
| `aes_mixColumns` | **−230 B** (43%) | Same |
| `rj_sb_inv` | −140 B (90% smaller) | #158 — u8 rotate chain |
| `rj_xtime` | −38 B | #158 same pattern |
| `gf_log` | −23 B | #158 modest |
| 1-arg pointer (`aes_subBytes` etc.) | 0..−2 B | No effect (matches single-fn test) |
| 2-arg pointer (`aes_expandEncKey`) | −16 B | Modest |

The aes_subBytes test was a representative sample of its CLASS
(1-pointer-arg, simple loop) but not of the corpus. The **biggest
savings come from aes_mc_inv and aes_mixColumns**, which are NOT
hit by #158 directly — they call rj_xtime inlined, and ANSI on the
inlined callees somehow propagates to caller codegen quality.

This is a **fourth distinct optimisation pattern** (separate from
#157 spill-storm, #158 K&R rotate, #159 ANSI rotate-chain
miscompile): ANSI prototypes on inlined u8-callees materially
improve the caller's regalloc choices.

## What this means for the priority queue

- **K&R → ANSI source workaround DOES close ~35% of the gap** when
  applied corpus-wide. But:
- **Currently blocked by #159** — clang silently miscompiles ANSI
  `rj_sb_inv`. Until fixed, full-ANSI variant cannot ship.
- After #159 fix: ANSI conversion becomes a viable workaround for
  35% of the gap; the remaining 65% is the genuine #157 spill-storm.

## Filed issues recap

- [#157](https://github.com/ravn/llvm-z80/issues/157) — spill-storm
  (regalloc quality + SP-relative spill encoding)
- [#158](https://github.com/ravn/llvm-z80/issues/158) — K&R
  int-promotion blocking u8 rotate recognition (correctness OK,
  bloat 5–10×)
- [#159](https://github.com/ravn/llvm-z80/issues/159) — ANSI
  chained u8 rotates produce wrong output (silent miscompile via
  uninit `E` register read)

A fourth issue (ANSI-propagation to inlined callees, the
aes_mc_inv −403 B finding) is worth filing once #159 is unblocked.

## Note on filed issues

- **[ravn/llvm-z80#157](https://github.com/ravn/llvm-z80/issues/157)** — spill-storm under high register pressure. Confirmed in aes_mc_inv, aes_mixColumns, gf_log, and the smaller AES functions.
- **[ravn/llvm-z80#158](https://github.com/ravn/llvm-z80/issues/158)** — K&R int-promotion disabling u8 rotate recognition. Specific to rj_sb_inv-like patterns.

A **third issue** for the IX-frame-mode heuristic should be filed
once we confirm the experiment.
