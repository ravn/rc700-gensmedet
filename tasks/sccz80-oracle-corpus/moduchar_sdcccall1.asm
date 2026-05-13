; __moduchar — 8-bit unsigned remainder, SDCC sdcccall-1 ABI.
;
; Replaces z88dk's stock libsrc/l/sdcc/__moduchar.asm which uses
; stack-passed args (sdcccall 0). The two ABIs are incompatible — if
; SDCC compiles user code under --sdcccall 1 and link picks up z88dk's
; stock helper, the helper pops random stack bytes as "args" and
; silently miscompiles.
;
; This file must come BEFORE the z88dk stdlib on the link line so the
; linker resolves __moduchar to this version.
;
; ABI (SDCC sdcccall 1, verified empirically against zsdcc's emitted
; call sites in corpus.c.lis):
;   IN:  A = dividend (x in x % y)
;        L = divisor  (y)
;   OUT: A = remainder
;        E = remainder (SDCC's caller reads E into A for 8-bit return)
;        HL = remainder, zero-extended to 16-bit
;   MAY TRASH: B, C, D, H

    SECTION code_compiler
    PUBLIC __moduchar

__moduchar:
    ld   c, a        ; C = saved dividend
    ld   a, 0        ; A = working remainder
    ld   b, 8        ; 8 iterations (bits)
moduchar_loop:
    sla  c           ; shift dividend MSB -> carry
    rla              ; remainder = (remainder << 1) | carry
    cp   l           ; compare remainder vs divisor
    jr   c, moduchar_skip    ; remainder < divisor -> no subtract
    sub  l           ; remainder -= divisor
moduchar_skip:
    djnz moduchar_loop
    ld   e, a        ; E = remainder
    ld   h, 0
    ld   l, a        ; HL = zero-extended remainder
    ret
