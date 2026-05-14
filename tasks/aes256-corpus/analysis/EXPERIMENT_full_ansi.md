# Experiment: full K&R → ANSI conversion of aes256.c

Goal: rigorously test whether mass K&R-to-ANSI prototype conversion
closes the +1699 B clang vs zsdcc gap, or only the per-function
slices identified for `rj_sb_inv` / `gf_log` (ravn/llvm-z80#158).

The earlier single-function bisection (aes_subBytes only) found
K&R = ANSI = 125 B identical, leading to the SURVEY.md conclusion
"K&R conversion doesn't close the gap". This experiment tests at
whole-corpus scale.

## Method

Mechanically convert every K&R-style definition in `aes256.c`:

```c
uint8_t gf_log(x)
uint8_t x;
{ ... }
```

→

```c
uint8_t gf_log(uint8_t x)
{ ... }
```

Did this for all 14 K&R functions. The other 4 (`aes256_init`,
`aes256_encrypt_ecb`, `aes256_decrypt_ecb`, plus the 3 already-ANSI
ones we converted earlier for SDCC parser compat) were left alone.

Build baseline and ANSI variants of the corpus with both compilers,
measure binary size + behavioural verification.

## Result: size

| Metric | K&R baseline | Full ANSI | Δ |
|---|---:|---:|---:|
| clang.bin | 5114 | **4239** | **−875 B (−17%)** |
| clang aes256.c text | 4660 | **3785** | −875 B |
| zsdcc.bin | 3604 | **3323** | **−281 B (−8%)** |
| zsdcc aes256.c text | 2961 | **2680** | −281 B |
| Clang vs zsdcc gap | +1699 B (1.57×) | **+1105 B (1.41×)** | **−594 B (35% closed)** |

K&R → ANSI is a substantial source-level workaround that closes
35% of the clang/zsdcc size gap. The earlier conclusion ("K&R
doesn't matter") was correct for the single-pointer-arg function
class but wrong at corpus scale.

## Per-function delta (clang)

| Function | K&R B | ANSI B | Δ | Pattern class |
|---|---:|---:|---:|---|
| `aes_mc_inv` | 863 | **460** | **−403** | Complex w/many locals |
| `aes_mixColumns` | 530 | **300** | **−230** | Same |
| `rj_sb_inv` | 156 | 16 | **−140** | u8-by-value, rotates (#158) ‼ |
| `rj_xtime` | 51 | 13 | **−38** | u8-by-value, shifts |
| `gf_log` | 153 | 130 | −23 | u8-by-value, loop |
| `aes_expandEncKey` | 529 | 513 | −16 | 2-arg pointer |
| `aes_expDecKey` | 604 | 588 | −16 | 2-arg pointer |
| `gf_mulinv` | 21 | 18 | −3 | u8-by-value, simple |
| `rj_sbox` | 22 | 20 | −2 | u8-by-value |
| `aes_sb_inv` | 127 | 125 | −2 | 1-pointer-arg |
| `aes_subBytes` | 127 | 125 | −2 | 1-pointer-arg |
| `aes_addRoundKey` | 135 | 135 | 0 | 2-pointer-arg |
| `aes_ar_cpy` | 123 | 123 | 0 | 3-pointer-arg |
| `aes_shiftRows` | 271 | 271 | 0 | 1-pointer-arg, byte swaps |
| `aes_sr_inv` | 271 | 271 | 0 | 1-pointer-arg, byte swaps |
| (others) | | | 0 | already ANSI |

## Behaviour: ‼ clang FAILed verification under full ANSI

Encrypt produced correct ciphertext. **Decrypt produced wrong
plaintext.** zsdcc PASSed both.

Bisection (selectively reverting individual ANSI functions to K&R):

- Reverted `aes_mc_inv`: still FAIL.
- Reverted `rj_sb_inv`: **PASS**.

So the new ANSI `rj_sb_inv` (16 B) is a silent miscompile. The
small/clean codegen looks like:

```
xor 99
rlca
ld d, a
rlca rlca
xor d
ld d, a
ld a, e          ; ← reads E, which is NEVER ASSIGNED. Uninit register.
rlca rlca rlca
xor d
ret
```

Filed as separate issue [ravn/llvm-z80#159](https://github.com/ravn/llvm-z80/issues/159).

Updated [#158](https://github.com/ravn/llvm-z80/issues/158) with
correction: the "16 B ANSI body" cited there is actually broken.
Until #159 is fixed, neither K&R (bloated but correct) nor ANSI
(small but wrong) is shippable for this rotate pattern.

## Where the 594 B gap-closure comes from

| Class | Functions | Total savings |
|---|---|---:|
| #158 (K&R int-promotion: u8 rotates/shifts on params) | rj_sb_inv (−140), rj_xtime (−38), gf_log (−23), gf_mulinv (−3), rj_sbox (−2) | **−206 B** |
| Mixed (large complex K&R-spill interaction) | aes_mc_inv (−403), aes_mixColumns (−230) | **−633 B** |
| 2-arg pointer K&R helper | aes_expandEncKey (−16), aes_expDecKey (−16) | −32 B |
| Single-pointer-arg & byte-only K&R | aes_subBytes (−2), aes_sb_inv (−2), aes_addRoundKey (0), aes_ar_cpy (0), aes_shiftRows (0), aes_sr_inv (0) | −4 B |
| **Total** | | **−875 B** |

**The "Mixed (complex) class" is the surprise**: aes_mc_inv saves
403 B and aes_mixColumns 230 B from a purely syntactic change.
That's 73% of the total savings.

These two functions have:
- Many byte register-class locals (9 / 6)
- Multiple inlined calls to a function taking a u8 parameter (rj_xtime)
- Tight loop with pointer arithmetic

The K&R declaration shape of those inlined-into-them callees seems
to leak into the caller's regalloc decisions. With ANSI prototypes,
clang's mid-end sees the called functions return/take u8 directly,
which propagates into more compact byte-level codegen up the chain.

This is a third, distinct optimization gap from #157 (spill-storm)
and #158 (K&R int-promotion). Could be summarised as: "ANSI
prototypes on inlined callees materially improve caller codegen
quality even when the caller itself is unchanged."

## Conclusions

1. **K&R → ANSI does close ~35% of the gap** when applied corpus-
   wide. Earlier single-function disproof was a misleading sample.
2. **The biggest savings are NOT from the K&R functions themselves**
   but from the propagation of u8 type info from K&R callees into
   the callers that inline them.
3. **The conversion is currently blocked by clang miscompile #159**.
   Once that's fixed, full-ANSI variant becomes the right baseline.
4. **A fourth optimization path exists** beyond #157/#158/#159:
   ANSI-callee → ANSI-caller propagation. Likely the same root
   cause as #158 (int-promotion crossing inlining boundaries) but
   worth its own minimal repro once #159 is unblocked.

## Files

- `experiments_aes256_mostly_ansi.c` (in corpus root) — the working
  variant with all K&R converted EXCEPT `rj_sb_inv` reverted (so
  it PASSes verification). Reference for future re-measurement
  once #159 is fixed.
- aes256.c itself reverted to K&R original (matches upstream + the
  3 SDCC-compat conversions).
