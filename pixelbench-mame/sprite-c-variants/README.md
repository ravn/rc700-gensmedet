# Sprite blit — C rewrite experiment

Experiment (2026-08-08): rewrite the RC700 cell-batched `spr_or` sprite blit in
C, two ways — **(1) C outer + tiny asm inner leaf**, and **(2) pure C tuned to
give llvmz80 the best optimization chances** — and measure both against the
hand-written assembly. Every variant is verified **byte-for-byte identical** VRAM
to the generic `putsprite` via the MAME VRAM-diff oracle, and timed on 4000 draws
of an 8×9 ball (60 set pixels / 12 sextant cells) on `rc702sem702 -nothrottle`,
llvmz80 clang `-O3`. Full design context: `../SPRITE_BLIT_DESIGN.md`.

## Measured ladder

| implementation                              | file(s)                          | total T (4000×) | T/sprite | vs generic |
|---------------------------------------------|----------------------------------|----------------:|---------:|-----------:|
| generic `putsprite` (per-pixel)             | z88dk classic                    | 227,425,204     | 56,856   | 1.00×      |
| pure C, naive/branchy                       | `spr_or_baseline.c`              |  48,925,596     | 12,231   | 4.65×      |
| **pure C, llvmz80-tuned**                   | `spr_or_tuned.c`                 |  44,632,980     | 11,158   | **5.10×**  |
| **C outer + asm inner leaf**                | `spr_or_leaf.c` + `blit_band.asm`|  39,295,491     |  9,824   | **5.79×**  |
| full hand asm (shipped in z88dk)            | `../../..` rc700_spriteblit.asm  |  36,342,675     |  9,086   | 6.26×      |

## Findings

1. **A tiny asm inner leaf recovers most of the gap with clear C.** Keeping only
   the register-pressure-critical inner cell loop in asm (3 row bytes resident in
   B,C,D; 6-bit mask in E; read-modify-write using only A+HL so nothing spills)
   takes 100%-C 4.65× up to **5.79×** — ~76% of the way to the full hand-asm
   6.26×, while all the readable structure (unpack, band loop, running base
   pointer, gfx-page assert) stays in C. This is the recommended shape when speed
   matters: `spr_or_leaf.c` (C) + `blit_band.asm` (the leaf).

2. **"Giving llvmz80 its best chance" is not the same as textbook branchless
   tuning.** The naive branchy C is already good (4.65×). Of the three tunings
   tried:
   - walking cell pointer + down-counting loop: **helped** (→4.97×),
   - 256-byte `rev[]` LUT replacing the glyph→mask compare chain: **helped**
     (→5.10×),
   - "branchless" mask build (`swap2[r>>6]`): **backfired badly** (→ 54.7M, worse
     than naive) — the `r>>6` (rlca/rlca/and) plus LUT index costs more than six
     plain bit-test branches on Z80. Keep the branchy mask.
   Net best pure C = `spr_or_tuned.c` at **5.10×**.

3. **The last ~13% (5.79×→6.26×) is per-band C overhead** — filling the 6-byte
   block and the fastcall per band — that the fully-fused hand asm avoids. Not
   worth giving up the C clarity unless every T-state counts; the shipped library
   routine remains the full asm.

## Rebuild / re-measure

Toolchain: native llvmz80 clang via z88dk `+cpm -subtype=rc700 -compiler=llvmz80`.
`LLVMZ80EXE` must point at the clang binary.

```
export PATH=/…/z88dk/bin:$PATH
export ZCCCFG=/…/z88dk/lib/config
export LLVMZ80EXE=/…/llvm-z80/build-macos/bin/clang

# pure-C tuned
zcc +cpm -subtype=rc700 -compiler=llvmz80 -O3 -o bench -m benchp.c spr_or_tuned.c
# C + asm leaf
zcc +cpm -subtype=rc700 -compiler=llvmz80 -O3 -o bench -m benchl.c spr_or_leaf.c blit_band.asm
```

Correctness (`run_cmp.sh`) and throughput (`run_bench.sh`) harnesses live in the
session scratch (`/tmp/pxbench/`); see `../SPRITE_BLIT_DESIGN.md` §9 for the
oracle/bracketing details. The C caller passes a 4-byte block `{x0, y0, spr_lo,
spr_hi}` via `__attribute__((z80_fastcall))`; CP/M `.COM` names must be ≤8 chars
with no underscore.

## ABI note (asm leaf)

`blit_band` is `__z88dk_fastcall`, HL → 6-byte block:
`{r0, r1, r2, wcells, addr_lo, addr_hi}` where `addr = band base + ccol0`. The C
outer fills it per band. The leaf keeps rows in B,C,D, mask in E, and does the
RMW with A+HL only, so the row/mask registers survive across the whole band.

## Larger-sprite test (16×16 chess pawn)
See `LARGER_SPRITE_RESULT.md`. Key finding: the cell-batched blit is **1.33× slower than generic** on the sparse 18%-dense pawn — cell-batching is a **dense-sprite** optimization (density crossover ≈ 1 set pixel/cell), not a general putsprite replacement.
