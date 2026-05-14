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

## Hypothesis disproved: K&R is NOT the IX trigger

Tested `aes_subBytes` (1-pointer-arg) in both K&R and ANSI
prototype variants:

```c
void aes_subBytes_kr(buf) unsigned char *buf;
{ register uint8_t i = 16; while (i--) buf[i] = rj_sbox(buf[i]); }

void aes_subBytes_ansi(uint8_t *buf)
{ register uint8_t i = 16; while (i--) buf[i] = rj_sbox(buf[i]); }
```

Result: **both 125 B, identical**. Converting K&R to ANSI does NOT
unlock the IX-frame mode for single-pointer-arg functions.

## The actual IX-mode trigger: pointer arg count

clang's Z80 backend appears to choose IX-frame mode when the
function's register-pressure-at-entry overflows the available
register pairs (HL, DE, BC). With 2+ pointer args (each i16 = 16
bits = needs a register pair), pressure is high enough that
spilling to a frame pointer becomes the right tradeoff.

With 1 pointer arg, the parameter fits in HL — but then clang's
local register allocation immediately spills HL to the stack and
goes SP-relative for the rest. This is the dominant pattern in
the +1699 B gap.

## What this means for the priority queue

- The K&R-to-ANSI source workaround **does NOT close the gap**.
  Don't bother converting aes256.c wholesale.
- The remaining gap is squarely the **regalloc-quality / IX-frame
  heuristic** in [ravn/llvm-z80#157](https://github.com/ravn/llvm-z80/issues/157).
  The fix is upstream-clang work; no source workaround helps.
- Confirms #157 is THE issue to close to make AES competitive.

## What's still useful in this branch

- **#158** (K&R int-promotion) remains valid for the rotate-chain
  pattern in `rj_sb_inv` — that one IS K&R-driven and ANSI fixes
  it. Just not the spill-storm gap.
- The per-function analysis docs document the variation in #157
  manifestation: from "small function, mild spill" (gf_log) to
  "huge function, full spill-storm" (aes_mc_inv).

## Note on filed issues

- **[ravn/llvm-z80#157](https://github.com/ravn/llvm-z80/issues/157)** — spill-storm under high register pressure. Confirmed in aes_mc_inv, aes_mixColumns, gf_log, and the smaller AES functions.
- **[ravn/llvm-z80#158](https://github.com/ravn/llvm-z80/issues/158)** — K&R int-promotion disabling u8 rotate recognition. Specific to rj_sb_inv-like patterns.

A **third issue** for the IX-frame-mode heuristic should be filed
once we confirm the experiment.
