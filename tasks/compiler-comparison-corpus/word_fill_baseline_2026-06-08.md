# `bench_word_fill` baseline — 2026-06-08

Captured on macbook against llvm-z80 main `3e83675` (workspace HEAD at
session start) and z88dk zsdcc 4.5.0.  Production-like flags (sweep.sh
matches the AES `09_Oz_prod_like` cell).

This bench targets ravn/llvm-z80#99 (XFAIL
`llvm/test/CodeGen/Z80/issue-97a-bc-pingpong-i16-counter.ll`): the i16
counter + walking i16 pointer regalloc shape.

## Harness numbers (sweep.sh)

| compiler | bin  | bench_run text | tstates  | verify |
|----------|-----:|---------------:|---------:|:------:|
| clang    | 178  |  79 (0x4F)     |  210,147 | PASS   |
| zsdcc    | 526  |  55 (counted)  |  128,796 | PASS   |

clang/zsdcc ratio: **+63 % slower** (210,147 / 128,796 = 1.632).

Both compilers self-report cycle counts via z88dk-ticks's ED FE syscall
trap (see `[[reference_ticks_canonical_exit_trap]]`).  `test_main.c`
loads match status into L (0=PASS, 1=FAIL) and traps; ticks's process
exit code IS the L register, and stdout prints `Ticks: <N>` which the
harness parses.  No more `-counter` cap on zsdcc.

bin is the full image; `bench_run text` is the function body only
(clang: llvm-nm; zsdcc: counted from the emitted .s — see Appendix).
The +12 B clang bin growth from the prior 166 is the trap inline-asm
in test_main.c (`xor a; .byte 0xED, 0xFE` plus the L-load).

## Per-iteration T-state comparison (hand-counted from emitted asm)

| loop                  | clang ts/iter | zsdcc ts/iter | clang slowdown |
|-----------------------|--------------:|--------------:|---------------:|
| Loop 1 (fill)         | 148           | 52            | **2.85x**      |
| Loop 2 (sum)          | 169           | 139           | 1.22x          |

At N=512 iterations:

| loop          | clang total | zsdcc total | delta      |
|---------------|------------:|------------:|-----------:|
| Loop 1        |  75,776     | 26,624      |  +49,152   |
| Loop 2        |  86,528     | 71,168      |  +15,360   |
| **Sum**       | 162,304     | 97,792      | **+66 %**  |

Hand-counted Loop 1 + Loop 2 (~162 k) plus harness / prologue overhead
matches the measured clang total (210,147).  zsdcc measured 128,796 ts;
the hand-counted ~98 k for just the two loops plus its CRT prologue
matches at the same scale.  The harness ratio (+63 %) is within 5
percentage points of the hand-counted +66 %.

## Why clang is slow here

Loop 1 emitted by clang HEAD:

```asm
    ld  iy,_buf            ; pointer in IY (index reg of last resort)
    ld  de,512             ; counter in DE
.L1:
    ld  l,e ; ld h,d       ; counter test via HL
    ld  a,l ; or h
    jr  z,.exit
    push iy ; pop bc       ; pointer IY -> BC for advance
    inc bc ; inc bc        ; advance +2
    push iy ; pop hl       ; pointer IY -> HL for store
    ld (hl),e ; inc hl
    ld (hl),d
    dec de                 ; counter--
    push bc ; pop iy       ; advanced pointer BC -> IY
    jr .L1
```

The pointer ends up in IY (heaviest 16-bit reg, 14-15 ts per push/pop)
and gets shuttled IY <-> BC <-> HL three times per iteration.  The
counter is in DE.  Neither in HL because the loop body needs HL free
for the store and the counter test consumes HL transiently.

Loop 1 emitted by SDCC (canonical):

```asm
    ld  bc,0x0200          ; counter in BC
    ld  hl,_buf            ; pointer in HL
.L1:
    ld  (hl),c ; inc hl    ; store + advance
    ld  (hl),b ; inc hl
    dec bc                 ; counter--
    ld  a,b ; or a,c       ; counter test
    jr  NZ,.L1
```

Tight.  Counter in BC, pointer in HL, no shuttling.

The XFAIL writeup describes the fix as a sister **HLReg single-register
class** for the pointer vreg, sibling of the existing BCReg counter
class (added by `Z80SplitDjnzCounters`).  Pointer pinned to HL frees
the coalescer from dragging it through BC/IY.

## What "fixed" looks like

When #99 closes, the baseline should collapse to roughly:

- clang Loop 1 ts/iter -> ~52 (parity with SDCC)
- clang Loop 1 total -> ~26 k (down from 76 k, -65 %)
- clang bench_run text -> ~55 B (parity with SDCC, down from 79 B)
- clang bench_run total ts -> ~110 k (down from 210 k, -47 %)

Loop 2 (the sum loop) will move proportionally less because the IY
spill of the accumulator is a separate gap (the `__sfrend_bench_run`
slot reload/store every iter — sibling regalloc issue, may or may not
collapse with the same HLReg fix).

## Reproduction

```bash
cd rc700-gensmedet/tasks/compiler-comparison-corpus
BENCH=word_fill ./sweep.sh
cat sweep/results.tsv
```

Asm to read:
- clang: `sweep/llvm_z80_word_fill_bench.o` (objdump or llvm-objdump -d)
- zsdcc: `sweep/zsdcc_word_fill.s`

## Appendix: zsdcc bench_run byte count (manual from .s)

```
prologue:    call ___sdcc_enter_ix (3) + push af (1)
             ld bc,0x0200 (3) + ld hl,_buf (3)               = 10 B
loop 1 body: ld(hl),c + inc hl + ld(hl),b + inc hl           =  4 B
             dec bc + ld a,b + or a,c + jr NZ                =  5 B
between:     ld de,0 + ld bc,N + ld hl,_buf                  =  9 B
loop 2 body: ld a,(hl) + ld (ix-2),a + inc hl                =  5 B
             ld a,(hl) + ld (ix-1),a + inc hl                =  5 B
             ld a,(ix-2) + add a,e + ld e,a                  =  5 B
             ld a,(ix-1) + adc a,d + ld d,a                  =  5 B
             dec bc + ld a,b + or a,c + jr NZ                =  5 B
epilogue:    pop af + pop ix + ret                           =  3 B
total                                                          55 B
```
