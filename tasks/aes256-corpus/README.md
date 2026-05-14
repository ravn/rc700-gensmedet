# AES-256 corpus — compiler-efficiency benchmark

Real-world C workload for measuring clang/llvm-z80 vs zsdcc codegen
efficiency on a non-trivial program. Complements the synthetic
`sccz80-oracle-corpus/` micro-corpus.

Source: http://z80.eu/downloads/aes256.zip — byte-oriented AES-256 by
Ilya O. Levin (literatecode.com), with CP/M-compat tweaks by Peter
Dassow (z80.eu).

The reference DEMO.COM in `aes256-original.zip` is 9216 B as built by
Peter Dassow's CP/M-targeted compiler (probably HiTech zc; provenance
not preserved in the upstream zip).

## What's in here

| File | Purpose |
|---|---|
| `aes256.c` | Upstream AES-256 implementation (three K&R prototypes converted to ANSI for SDCC parser; see comments in-file) |
| `test_main.c` | Freestanding harness: known-answer encrypt+decrypt, writes 35-byte result vector at 0xC000 |
| `demo_original.c` | Original demo.c from upstream zip, kept for provenance (uses stdio printf — needs a CP/M target to link, unlike our test harness) |
| `aes256-original.zip` | Upstream zip, byte-faithful |
| `DEMO.COM` | Reference binary from the upstream zip (9216 B) |
| `Makefile` | Build + test recipes for both compilers |
| `flag_sweep.sh` | clang flag-sweep driver |
| `flag_sweep_sdcc.sh` | zsdcc flag-sweep driver |
| `clang-flag-sweep.md` | **persistent table** of clang flag results — diff this in git to catch regressions |
| `sdcc-flag-sweep.md`  | **persistent table** of zsdcc flag results — same |
| `findings.md` | Analysis of the headline result + outlier per-function gap |

## Targets

| Make target | What it does |
|---|---|
| `make` / `make test` | Build both compilers, run in z88dk-ticks, verify the result vector + report runtime tstates |
| `make sweep` | Re-run BOTH flag sweeps and regenerate both `*-flag-sweep.md` tables |
| `make sweep_clang` | Re-run just the clang sweep |
| `make sweep_sdcc` | Re-run just the sdcc sweep |
| `make sizes` | Report per-compiler binary + per-function text sizes |
| `make clean` | Remove all build artifacts |

## How verification works

`test_main.c`:
1. Sets up demo.c's test vector (`buf[i] = i*16+i`, `key[i] = i`)
2. Encrypts with `aes256_init` + `aes256_encrypt_ecb`
3. Writes ciphertext + PASS sentinel (1 if matches known answer) to 0xC000..0xC010
4. Decrypts with `aes256_init` + `aes256_decrypt_ecb`
5. Writes plaintext + PASS sentinel (1 if equals original) to 0xC011..0xC021
6. Writes 0xA5 end-of-test sentinel at 0xC022
7. Returns from main (crt0 halts)

Result vector at 0xC000 (35 bytes):

| Offset | Bytes | Meaning |
|---|---|---|
| 0x00..0x0F | 16 | Ciphertext from encrypt — must equal `8e a2 b7 ca ...` |
| 0x10 | 1 | enc-matches-expected sentinel (1 = PASS) |
| 0x11..0x20 | 16 | Plaintext from decrypt — must equal `00 11 22 ... ff` |
| 0x21 | 1 | dec-matches-original sentinel (1 = PASS) |
| 0x22 | 1 | end-of-test sentinel 0xA5 |

A test PASSes if all three of {enc=01, dec=01, end=a5} are present.

## How tstate measurement works

`z88dk-ticks` exits when `pc == end` (or counter limit). Both compilers'
post-main HALT address is extracted at build time:

- **clang**: `_done` symbol address from `clang.elf` via `llvm-nm`
  (fixed at 0x0007 by `reset_clang.s` layout)
- **zsdcc**: byte-pattern scan of `zsdcc.bin` for `e5 f3 e1 76`
  (`push hl; di; pop hl; halt` — z88dk +z80 crt0 post-main HALT site;
  HALT itself is at pattern start + 3, fixed at 0x00B7 in current builds)

Counter limit is 100M tstates as a safety deadline (PASS configs are
14M–66M, so 100M is well above; FAIL configs that never reach `end`
fall through and report `tstates=100000003`).

## Why this corpus exists

The micro-corpus in `sccz80-oracle-corpus/` measures clang vs zsdcc on
hand-picked synthetic patterns: clang wins 1.5×. AES-256 measures both
compilers on real-world code: **zsdcc wins 1.42× on size and 4.66× on
runtime**.

The reversal isolates the open Phase 3 Cluster A regalloc issues
(#89, #27) and the MachineLICM+CSE pessimization (#128) as the
dominant codegen gaps for real workloads on this backend. Each flag
sweep row is a controlled experiment confirming or refuting one
hypothesis about which knob matters.

See `findings.md` for the per-function breakdown and analysis.

## Workflow

1. Edit code or land a compiler change.
2. `make sweep`
3. `git diff *-flag-sweep.md` — regression appears as a Δbin/Δtstates change.
4. If regression: bisect against the row that moved.
5. If improvement: commit the new table as the rolling baseline.

## Not in scope

This corpus is purely about codegen efficiency on a fixed C program.
It does NOT cover:

- Different AES variants (we use byte-oriented "tableless"; the
  `BACK_TO_TABLES` define exists in `aes256.c` but is not measured)
- Different optimisation levels for zsdcc beyond what `flag_sweep_sdcc.sh`
  enumerates
- Different crypto algorithms (would need a separate corpus dir)
- Real CP/M integration (the test harness HALTs in ticks, doesn't run
  on RC702 hardware — see cpnos-rom for that)
