# aes_mc_inv codegen gap — clang vs zsdcc

Function: AES inverse mix-columns. 9 byte register-class locals,
4-iteration loop over a 16-byte buffer, 4 calls to `rj_xtime`
per iteration.

## Headline

| Compiler | Bytes | Notes |
|---|---:|---|
| **clang -Oz** (baseline) | **863** | 27-byte SP-relative frame, 0 IX uses, 77 `add hl,sp` recomputations, all 4 rj_xtime calls inlined |
| **zsdcc** (cpnos prod flags) | **314** | 11-byte IX frame, 52 `(ix±N)` uses, rj_xtime kept as function (9 calls) |
| **Gap** | **+549 B (2.75×)** | |

## Root cause

clang's default Z80 codegen does NOT use a frame pointer when register
pressure overflows 7 GPRs. It spills to SP-relative slots, and
**re-computes the slot address for every access**:

```
ld hl, N        ; 3 B   load slot offset
add hl, sp      ; 1 B   compute SP+N
ld (hl), a      ; 1 B   store
                ; ---
                ; 5 B per spill access
```

zsdcc sets up IX as a frame pointer once in the prologue, then uses
single-instruction IX-relative addressing for every spill:

```
ld (ix+N), a    ; 3 B   store
                ; ---
                ; 3 B per spill access
```

Savings if clang switched to IX-relative spills: **2 bytes per spill
access × 77 accesses = ~154 bytes**. That alone closes ~28% of the
gap. Combined with a smaller frame (clang allocates 27 B; zsdcc
allocates 11 B — clang's regalloc isn't reusing slots), the
remaining gap is regalloc-quality.

## Prologue overhead

clang:
```
push af  (× 13)   ; 26 B  — 13 × 2-byte instr reserving 2 B each = 14 B encoded
dec sp            ;  1 B  — final byte to reach 27 B frame
ld c,l            ;  1 B
ld b,h            ;  1 B  — save HL (arg) to BC
ld hl, 0          ;  3 B
add hl, sp        ;  1 B
ld (hl), c        ;  1 B
inc hl            ;  1 B
ld (hl), b        ;  1 B  — store HL to frame slot 0..1
                  ; ----
                  ; 24 B prologue
```

zsdcc:
```
push ix           ;  2 B
ld ix, 0          ;  4 B
add ix, sp        ;  2 B  — IX = SP (frame pointer)
ld hl, -11        ;  3 B
add hl, sp        ;  1 B
ld sp, hl         ;  1 B  — reserve 11 B locals
                  ; ----
                  ; 13 B prologue
```

Prologue saving from IX-frame approach: ~11 B per function (24 → 13).

## Inlining vs body bloat

clang inlined all 4 `rj_xtime` call sites. Each inlined site is the
branchless-or-branchful body (`x & 0x80 ? (x << 1) ^ 0x1b : (x << 1)`).
zsdcc kept `rj_xtime` as a function and emitted 9 `call` instructions
(one per static call site, including ones that appear inside the
inlined-by-clang path).

This is NOT the dominant cost. Inlining of a 18-byte function 4 times
across the body is ~50-70 bytes of additional inline body, but the
spill-storm dominates. Whether inlining is a win on Z80 depends on
how many spills are needed per call site — at this register pressure,
keeping the call and saving registers via callee-save would likely be
smaller. Worth a separate measurement.

## Answer to "would IX or IY indexing be better?"

**Yes, IX-relative is significantly better.** Direct estimate of
savings:

- Per-spill encoding: 5 B → 3 B saves 2 B × ~77 sites = **~154 B**
- Prologue: 24 B → 13 B saves **~11 B**
- Frame size reduction (regalloc better at reusing IX-frame slots):
  speculative, possibly **another 30-80 B** if frame went from 27 B
  to 11 B (mirroring zsdcc)
- Inlining decisions might change too (with cheaper spills, the
  inlining-vs-call tradeoff might tip toward inline)

Total plausible savings on `aes_mc_inv` alone: **150-250 B**, which
is 27-45% of the +549 B gap. Pattern recurs across other AES
functions, so closing this fixes multiple gap sites at once.

**IY would be similar** but IY is currently reserved by llvm-z80
([ravn/llvm-z80#38](https://github.com/ravn/llvm-z80/issues/38)
"un-reserve IY" parked). IX is available in principle but the
`+static-stack` feature (which uses IX/static locals) currently
miscompiles AES — see [ravn/llvm-z80#156](https://github.com/ravn/llvm-z80/issues/156).

The cleanest fix path is therefore:

1. Fix #156 (`+static-stack` miscompile on AES), OR
2. Add a separate "IX-frame for high-pressure functions" lowering
   mode that doesn't depend on `+static-stack`, OR
3. (Long term) un-reserve IY (#38) AND give regalloc the IX/IY
   cost-model to decide per-function which to use as frame pointer.

## Side-by-side asm excerpts

Loop header (first iteration's setup), clang:
```
.LBB13_1:
    ld hl, 25
    add hl, sp        ; compute SP+25 (loop counter slot)
    ld e, (hl)
    inc hl
    ld d, (hl)        ; load 16-bit loop counter — 10 bytes for one load
    ld b, d
    ld de, 16
    ld a, c
    sub e
    ld a, b
    sbc a, d
    jp nc, .LBB13_29  ; loop exit
```

Loop header, zsdcc:
```
l_aes_mc_inv_00102:
    ld a, (ix+4)      ; load buf ptr low
    add a, (ix-11)    ; + i
    ld e, a
    ld a, (ix+5)      ; load buf ptr high
    adc a, 0x00
    ld d, a            ; DE = &buf[i] — 12 bytes
```

zsdcc keeps the loop counter at `(ix-11)`, accessing it in 3 bytes
per use. clang stores the i16 counter at SP+25..SP+26 and pays 5
bytes to recompute the address PLUS 2 bytes for the high-byte load.

## Where the cycle cost goes too

Runtime on the corpus: clang 66.1M tstates, zsdcc 14.2M tstates.
The per-spill encoding cost is 4-5 extra tstates per access for the
SP-recompute (LD HL,nn + ADD HL,SP = 10+11 = 21 tstates vs LD A,(IX+N) = 19 tstates) — small per instance, but multiplied across hundreds of spills per AES round × 14 rounds, the cycle cost amplifies sharply.

## Reproducer

See `repros/repro_aes_mc_inv_spill_storm.c` for a self-contained
minimal C file (~30 lines) that triggers the same shape and
reproduces the per-spill encoding gap. Build via the corpus
Makefile's clang/zsdcc recipes; `make sizes` shows the delta.
