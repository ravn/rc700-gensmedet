# dcc added to the AES-256 comparison (2026-06-27)

dcc (David Lee's CP/M C compiler, `/Users/ravn/z80/dcc`) is now a third
"friend" alongside clang/llvm-z80 and zsdcc on this corpus. Build + measure
with `build_dcc_aes.sh` (mirrors `dcc/scripts/compare3.sh`: dcc -> M80 -> L80
under the runcpm emulator -> `.COM`, wrapped in a 64 KB image and run in
z88dk-ticks to the warm-boot exit; the 35-byte result vector at 0xC000 is
verified exactly as the Makefile does for clang/zsdcc).

## Headline numbers (current toolchains, same harness + test vector)

| compiler | build | binary | runtime (T-states) | verify |
| --- | --- | --- | --- | --- |
| zsdcc (sdcc `-SO3`) | 2-unit, freestanding | 3323 B `.bin` | **12,080,289** | PASS |
| clang (llvm-z80 `-Oz`) | 2-unit, freestanding | **2639 B** `.bin` | 17,024,606 | PASS |
| dcc | 1-unit, +CP/M RTL | 7040 B `.com` | 71,963,277 | PASS |

Runtime is the directly-comparable metric (the AES rounds dominate; startup/RTL overhead is negligible). On runtime, **dcc is ~4.2x slower than clang and ~6.0x slower than zsdcc** — AES-256 is dense 8-bit bit-twiddling (shifts/xors/GF math) across many small functions, which clang's and SDCC's optimizing back-ends handle far better than dcc's straightforward per-statement codegen. clang now also beats zsdcc on size here (2639 vs 3323 B) while remaining ~1.4x slower at runtime.

Size is NOT directly comparable across the row: the dcc figure is a CP/M `.COM` that bundles the dcc runtime library + the test harness, whereas the clang/zsdcc `.bin` figures are freestanding (AES + harness + minimal startup only). Use runtime for the apples-to-apples ranking.

## Finding: dcc miscompiles this code under SEPARATE compilation

When `aes256.c` and `test_main.c` are compiled as **separate** translation units and L80-linked (`TWOFILE=1 build_dcc_aes.sh`), the program runs to completion (writes the 0xA5 end sentinel) but produces **deterministically wrong** ciphertext — `11 fb 2f 84 ...` instead of the known answer `8e a2 b7 ca ...` — so both the encrypt and decrypt self-checks FAIL.

Isolation performed (symptom verified; root cause not yet pinned):

- Reproduces with **both** source variants (`aes256.c` K&R and `aes256_ansi.c` ANSI) — identical wrong output, so it is NOT a K&R-vs-ANSI prototype mismatch.
- Reproduces **with and without** `dccpeep` — so it is NOT the peephole optimizer.
- `aes256.c` calls **no** runtime routines (it is tableless / self-contained), so it is NOT a mislinked RTL function.
- Compiling AES + harness as a **single** translation unit is **correct** (PASS). The only changed variable is single-unit vs separate-unit compilation.

Suspected cause (UNVERIFIED): a dcc separate-compilation calling-convention / argument-passing defect on the cross-unit calls into the AES functions (`aes256_init` / `aes256_encrypt_ecb` / `aes256_decrypt_ecb`), which take a struct pointer + a byte pointer. The headline measurement therefore uses the single-TU build, which exercises the same generated AES code and passes the known-answer test. This is a candidate dcc bug to investigate separately (dcc is an external compiler; not an llvm-z80 issue).

## Repro

```
cd rc700-gensmedet/tasks/aes256-corpus
bash build_dcc_aes.sh            # single-TU, PASS — the headline dcc number
TWOFILE=1 bash build_dcc_aes.sh  # separate-unit, FAIL — reproduces the bug
```

