# gf_log codegen gap — clang vs zsdcc

Function: AES tableless logarithm in GF(2^8). Tight `do/while` loop
comparing parameter `x` against running `atb`; shifts `atb` left,
conditionally XORs with `0x1b`, increments byte counter `i`.

## Headline

| Compiler | Bytes | Notes |
|---|---:|---|
| **clang -Oz** | **153** | Spill-storm, plus K&R int-promotion |
| **zsdcc** | **32** | Everything in registers (A, B, C); inline `bit 7, B` for the high-bit test |
| **Gap** | **+121 B (4.78× ratio !!)** | |

## Root cause: BOTH layered issues

Bisection (`repros/repro_gf_log_kr.c`):

| Variant | clang B | Δ vs K&R |
|---|---:|---:|
| `gf_log_kr` (K&R, what aes256.c has) | **153** | — |
| `gf_log_ansi` (ANSI prototype, same body) | **130** | −23 B |

K&R-vs-ANSI difference is only **−23 B** (15% of the 121 B gap),
unlike `rj_sb_inv` where K&R explained the whole gap. So:

- **Primary** cause: spill-storm (same as
  [ravn/llvm-z80#157](https://github.com/ravn/llvm-z80/issues/157)) —
  even the ANSI version is 130 B vs zsdcc's 32 B (4× ratio).
- **Secondary** cause: K&R int-promotion (same as
  [ravn/llvm-z80#158](https://github.com/ravn/llvm-z80/issues/158)) —
  ~23 B on this function.

The interesting subtlety: gf_log has only **3 byte register-class
locals** (`atb, i, z`) plus the parameter `x` — total 4 byte values.
Z80 has 7 GPRs. This SHOULD fit in registers without spilling. But
clang still allocates an SP-relative frame and spills all four
values.

zsdcc keeps `x` in `(ix+4)` (ABI arg slot), `a` as the running atb,
`B` as a temporary for the high-bit test (`bit 7, B`), and `C` as
the loop counter. Total register usage: A, B, C, plus IX = 4
registers. No frame locals at all — the 11 B "frame" reported is
just the ix-frame-pointer setup, not actual local storage.

## Codegen excerpts

zsdcc full body (32 B):
```
call ___sdcc_enter_ix       ; standard prologue
ld a, 0x01                  ; atb = 1
ld c, 0x00                  ; i = 0
l_gf_log_00105:
    cp a, (ix+4)            ; compare atb against x
    jr z, l_gf_log_00107
    ld b, a                 ; z = atb
    add a, a                ; atb <<= 1
    bit 7, b                ; test (z & 0x80)
    jr z, l_gf_log_00104
    xor a, 0x1b             ; atb ^= 0x1b (if high bit was set)
l_gf_log_00104:
    xor a, b                ; atb ^= z
    inc c                   ; i++
    inc c                   ; (...weird that there are 3 c ops; pre-inc loop semantics)
    dec c
    jr nz, l_gf_log_00105
l_gf_log_00107:
    ld a, c                 ; return i
    pop ix; pop hl; inc sp; jp (hl)   ; standard epilogue
```

clang ANSI body excerpt (still 130 B):
```
_gf_log_ansi:
    push af; push af; push af              ; 3 B frame
    ld hl, 0; add hl, sp; ld (hl), a       ; store x at SP+0  (5 B!)
    ld bc, 1                               ; atb=1, i=0
    ld d, 0
    ld hl, 3; add hl, sp; ld (hl), e       ; store SP+3
    inc hl; ld (hl), d                     ; store SP+4
.LBB1_1:
    ld l, c; ld h, b
    push hl
    ld hl, 2; add hl, sp; ld a, (hl)       ; load x from SP+2 (after the push)
    pop hl
    cp l                                   ; cmp x against ...?
    jr z, .LBB1_6
    push hl; ld hl, 4; add hl, sp
    ld (hl), d                             ; store more
    pop hl
    ...
```

Spill-storm dominates. The K&R version adds another 23 B of
int-promotion zero-extension overhead on top.

## Filing

Both issues already filed:
- Spill-storm (primary): [ravn/llvm-z80#157](https://github.com/ravn/llvm-z80/issues/157)
- K&R int-promotion (secondary): [ravn/llvm-z80#158](https://github.com/ravn/llvm-z80/issues/158)

This analysis is added as a comment on #157 (primary cause) and as
evidence that the regalloc-quality issue affects even functions
with very few byte locals.

## Notable: aes256.c's `do/while` idiom triggers extra spilling

The `do { ... } while (++i > 0)` idiom relies on byte wrap from
0xFF to 0x00 to exit the loop. clang's mid-end may be treating
`++i > 0` as an i16 comparison (since `i` is `uint8_t` and the
comparison's other operand `0` is `int`), which forces i to live
in a 16-bit value somewhere. zsdcc's peepholer recognises the byte
wrap and uses 8-bit decrement + jr nz.

Separate sub-pattern worth probing in a future iteration: do C
idioms relying on integer-promotion-then-truncation get lowered
suboptimally on Z80? Speculative; would need its own bisection.
