# rj_sb_inv codegen gap — clang vs zsdcc

Function: AES inverse S-box (tableless variant). Three rotate-and-XOR
operations on a uint8_t, then a tail call to gf_mulinv. K&R-style
function definition in aes256.c.

## Headline

| Compiler | Bytes | Notes |
|---|---:|---|
| **clang -Oz** | **156** | 16-bit shift sequences via `add hl,hl`, mask-and-OR for each rotate |
| **zsdcc** | **30** | One `rlca` per rotate, chained directly in A |
| **Gap** | **+126 B (5.20× ratio !!)** | |

## Root cause: K&R function-definition style disables u8 rotate recognition

Bisection (see `repros/repro_rj_sb_inv_bisect.c`):

| Variant | clang B | K&R style | Tail call to extern |
|---|---:|---|---|
| `rj_sb_inv_kr` | **147** | YES | no |
| `rj_sb_inv_tail` | **16** | no (ANSI) | YES |
| `rj_sb_inv_full` | **150** | YES | YES |

The K&R-style function definition is the entire cause. With ANSI
prototypes, clang produces 16 bytes — **MATCHES zsdcc** on this
pattern. With K&R, clang produces 147-150 bytes.

## Mechanism

K&R parameter:
```c
uint8_t rj_sb_inv(x)
uint8_t x;
{ ... }
```

The function declaration has no prototype, so the parameter undergoes
**default argument promotion** to `int` (16-bit on Z80) at the ABI
boundary. The `uint8_t x;` inner declaration is just the K&R-style
parameter type tag, but at the IR level, clang treats `x` as `i16`
(or `i8` zero-extended to `i16` in the calling convention).

Then `(x << 1) | (x >> 7)`:
- ANSI: clang's mid-end sees `(i8)x << 1 | (i8)x >> 7` → known
  8-bit rotate pattern → lowers to `rlca`
- K&R: clang's mid-end sees `(i16)x << 1 | (i16)x >> 7` (16-bit
  shifts on a 16-bit value) → doesn't pattern-match to 8-bit
  rotate → emits literal `add hl,hl` + masks + OR

Then the 8-bit truncation on assignment (`y = ...`) just stores
the low byte of HL, but the optimization opportunity is already
lost upstream.

## Codegen excerpts

ANSI `rj_sb_inv_tail` (16 B body, clang):
```
xor 99             ; A = x ^ 0x63
rlca               ; ROTL 1 — first rotate
ld d, a            ; sb = y
rlca rlca          ; ROTL 2 (second rotate, starting from y after ROTL 1)
xor d              ; sb ^= y
ld d, a            ; save new sb
ld a, e            ; reload y (wait, this is suspicious — y after ROTL 1?)
rlca rlca rlca     ; ROTL 3 from y
xor d              ; sb ^= y
jp _gf_mulinv      ; tail call
```

(Actually checking the asm again — clang's ANSI output has a small
quirk: it reloads `y` from `e` rather than using the running rotated
`a`. Possibly an artifact of how the source spells the chain. Still
16 bytes total, near-optimal.)

K&R `rj_sb_inv_kr` (147 B body, clang excerpt):
```
push af ; push af              ; 2 B frame
ld c,l ld b,h                  ; save parameter (in HL) to BC
ld b, 0                        ; clear high byte... but B was just loaded?
ld l,c ld h,b                  ; HL = (0 << 8) | C  → 16-bit zero-ext
add hl, hl                     ; HL = x << 1 (as 16-bit)
ex de, hl                      ; DE = x << 1
ld l, c ld h, b                ; HL = x (zero-ext)
ld a, l                        ; A = x
rlca                           ; A = ROTL(x) — gets the high bit into bit 0
and 1                          ; A = (x >> 7) (mask)
ld b, a                        ; save the >> 7 result
ld l, h ld h, 0                ; HL = high byte of (x << 1) (= bit 7 of x)
add hl, hl                     ; multiply by 2... why?
ld a, l                        ; A = low byte
or b                           ; OR with the bit 7
ld l, a                        ; save
ld a, e                        ; A = low byte of x << 1
and 254                        ; mask off bit 0 (we'll set it from >> 7)
or l                           ; merge
...
```

Several layers of compounded inefficiency:
1. **Zero-extension dance** — `ld c,l; ld b,h; ld b,0; ld l,c; ld h,b`
   is 5 bytes to extract the low byte of an i16 parameter into HL with
   high byte zero. ANSI's `xor 99` is 2 bytes total.
2. **16-bit shift via add hl,hl** instead of 8-bit `rlca` — 1 byte
   either way, but `add hl,hl` doesn't fold with the `>> 7` part to a
   single rotate.
3. **Manual mask-and-OR** for the rotate join — `rlca; and 1; or b`
   instead of clean `rlca` (which puts the rotated-out bit into both
   the carry AND bit 0 of A).

## Impact across aes256.c

aes256.c uses K&R for almost every function (only 3 were converted
to ANSI manually for SDCC parser compatibility:
`aes256_init`, `aes256_encrypt_ecb`, `aes256_decrypt_ecb`).

Every other function has the same K&R-mode int-promotion issue to
some degree. Functions that do u8 rotates/shifts on parameters are
hit hardest:

| Function | Has K&R? | Has u8 rotate/shift on param? | Notes |
|---|---|---|---|
| rj_sbox | YES | YES (4 rotates) | 22 B clang (small, well-handled) |
| **rj_sb_inv** | YES | YES (3 rotates) | **156 B / 5.2× ratio** |
| rj_xtime | YES | YES (`x << 1`) | 51 B / 2.83× |
| gf_alog | YES | YES (atb <<= 1) | 27 B / 0.9× (small) |
| **gf_log** | YES | YES | **153 B / 4.78× ratio** |
| gf_mulinv | YES | (calls gf_alog/log) | 21 B / 0.68× ✓ |

The **gf_log** function (4.78× gap) likely has the same root cause —
let it be the next investigation target.

Some of the smaller K&R functions (rj_sbox, gf_mulinv) handle the
K&R promotion well because their body shape doesn't trip the rotate
pattern. rj_sb_inv hits it because of the multi-rotate chain.

## Proposed fix area

clang mid-end / GISel combiner: recognize that an int-promoted u8
parameter has guaranteed-zero high byte, and narrow `(u8) (rotl_i16(zext(u8), N))` patterns to 8-bit ROTL. The C frontend's
"K&R parameters get default argument promotion" is correct
per-spec, but the optimization pass should still see through it.

Until fixed: **mechanically converting all K&R function definitions
in aes256.c to ANSI prototypes** would close most of the rj_sb_inv +
gf_log + rj_xtime gaps. We've already done this for 3 of ~20
functions; doing it for all of them is a low-risk source change.

But that's a source workaround. The clang fix is the right path.

## Reproducer

See `repros/repro_rj_sb_inv_rotate.c` (the original 14-byte rotl1
test) and `repros/repro_rj_sb_inv_bisect.c` (the K&R-vs-ANSI
3-variant bisection). Build with the corpus baseline flags.
