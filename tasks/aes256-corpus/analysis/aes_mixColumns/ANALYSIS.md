# aes_mixColumns codegen gap — clang vs zsdcc

Function: AES forward mix-columns. 6 byte register-class locals
(`i, a, b, c, d, e`), 4-iteration loop over a 16-byte buffer, 4
inlined `rj_xtime` call sites in clang (or 4 actual calls in
zsdcc).

## Headline

| Compiler | Bytes | Notes |
|---|---:|---|
| **clang -Oz** | **530** | 25-byte SP-relative frame, 0 IX uses, 46 `add hl,sp` recomputations |
| **zsdcc** | **241** | 11-byte IX frame, 44 `(ix±N)` uses, rj_xtime as function (4 calls) |
| **Gap** | **+289 B (2.20×)** | |

## Same root cause as aes_mc_inv

This is the **same spill-storm pattern** as `aes_mc_inv`
([analysis](../aes_mc_inv/ANALYSIS.md), issue
[ravn/llvm-z80#157](https://github.com/ravn/llvm-z80/issues/157)),
at smaller scale:

| Pattern stat | aes_mc_inv | aes_mixColumns |
|---|---:|---:|
| clang SP-recomputes | 77 | 46 |
| clang IX uses | 0 | 0 |
| zsdcc IX uses | 52 | 44 |
| clang push-af prologue | 13 | 12 |
| clang frame size | 27 B | 25 B |
| zsdcc frame size | 11 B | 11 B |

## Interesting deviation: clang's frame size is disproportionate

aes_mixColumns has only **6 byte register-class locals** (vs
aes_mc_inv's 9). On Z80 with 7 GPRs, 6 locals *should* fit without
spilling at all. zsdcc's frame is 11 B because it keeps the pointer
arg + i16 loop counter spilled by ABI choice, but the byte locals
stay in registers.

clang allocates a 25-byte frame — only 2 bytes smaller than for
aes_mc_inv with 9 locals. The extra slots must be temporaries from
the 4 inlined `rj_xtime` call sites and intermediate i16 pointer
arithmetic for the `buf[i]..buf[i+3]` accesses.

So this function has a **second issue layered on the spill-storm
encoding**: clang's regalloc decides to spill values that would
otherwise stay in registers, because the inlined rj_xtime expansion
introduces additional live ranges that conflict with what regalloc
chose for the loop-invariant values.

This is "regalloc quality" rather than "spill encoding" — orthogonal
to the IX-vs-SP-relative encoding fix. Both are part of Phase 3
Cluster A regalloc work (open
[ravn/llvm-z80#89](https://github.com/ravn/llvm-z80/issues/89),
[#27](https://github.com/ravn/llvm-z80/issues/27)).

## Quantified savings from IX-frame fix alone

Encoding savings: 2 B × 46 spills = **~92 B** out of the 289 B gap.
That's 32% of the gap, leaving the rest to regalloc-quality issues
(frame size shrinkage from 25 B → ~11 B + slot reuse).

If frame-size reduction landed: 14 B × ~3-5 fewer spilled values =
~30-70 B additional. So IX-frame + good regalloc could close 40-50%
of the 289 B gap.

The remaining ~150 B is likely:
- Inlining vs call tradeoff (clang inlines 4 rj_xtime; zsdcc calls).
  Each inlined site is ~20 B; 4 × 20 = 80 B of additional body.
  Without spill cheapness, the inline-vs-call tradeoff favours call.
- 16-bit pointer arithmetic redo per buf[i] access — zsdcc loads
  `buf` ptr once into HL/DE in the prologue and reuses; clang
  computes it from the frame each iteration.

## Inlining tradeoff — emerging pattern

Across both `aes_mc_inv` and `aes_mixColumns`, clang inlines all
`rj_xtime` call sites and zsdcc keeps them as function calls. With
clang's current spill encoding making register state expensive to
maintain, inlining ADDS pressure rather than saves work.

If the IX-frame fix lands (cheaper spills), inlining becomes a
better tradeoff. Until then, **the inlining heuristic should be
biased toward keeping calls** on Z80 under high pressure.

This is potentially a separate `-mllvm` cost-model issue worth
filing once the spill-encoding fix is in place.

## Codegen excerpts

Prologue, clang (24 B):
```
push af  (× 12)        ; 24 B reserved
dec sp                 ; 25 B total
ld e,l ld d,h          ; save HL → DE
ld hl,0 add hl,sp      ; recompute HL = SP+0
ld (hl),e inc hl ld (hl),d  ; store arg
```

Prologue, zsdcc (13 B):
```
push ix
ld ix,0
add ix,sp              ; IX = SP (frame pointer)
ld hl, -11
add hl, sp
ld sp, hl              ; reserve 11 B
ld (ix-11), 0x00       ; i = 0
```

zsdcc's prologue is 13 B and includes `i = 0` initialisation in the
frame. clang's 25 B prologue does NOT include the loop counter
init — that happens later, with its own SP-recompute.

## Conclusion

`aes_mixColumns` is a smaller-scale instance of the same root cause
as `aes_mc_inv`: clang's high-pressure spill encoding (5 B/access
SP-relative recompute) is structurally worse than zsdcc's
IX-relative addressing (3 B/access), AND clang's regalloc allocates
more slots than necessary.

Recorded as additional evidence on
[ravn/llvm-z80#157](https://github.com/ravn/llvm-z80/issues/157)
rather than filing a duplicate issue. The minimal reproducer for #157
(`repros/repro_aes_mc_inv_spill_storm.c`) covers this case too —
the same pattern shape recurs at smaller scale here.
