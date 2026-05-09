; cpnos-rom SDCC runtime helpers.
;
; _memmove_callee — overlap-safe memmove, callee-cleanup ABI.
;
; z88dk's <string.h> rewrites every memmove(d,s,n) call to
; memmove_callee(d,s,n) (see libsrc/string/c/sdcc_ix/memmove_callee.asm
; in z88dk).  The library version is ~150 B (trampoline + asm_memmove +
; asm0/1_memcpy split for size-zero handling).  This tight version
; trades a bit of speed for ~33 B and overrides the library symbol;
; cpnos-rom calls memmove from at most two sites (rc700_console.c
; scroll_up_at, resident.c insert_line) so the speed delta is
; irrelevant — code density wins.
;
; Calling convention (z88dk callee-cleanup):
;   stack on entry: [ret_lo, ret_hi, dst_lo, dst_hi, src_lo, src_hi,
;                    n_lo, n_hi]   (caller pushed n, src, dst, then CALL)
;   on exit: stack holds only the return address; HL = original dst.

SECTION RESIDENT_CODE

PUBLIC _memmove_callee

_memmove_callee:
    pop  iy            ; save return address
    pop  de            ; DE = dst
    pop  hl            ; HL = src
    pop  bc            ; BC = n
    push iy            ; restore return address

    ld   a, b
    or   c
    ret  z             ; n == 0: nothing to copy

    ; Choose direction.  dst < src -> forward LDIR; dst > src -> LDDR.
    ld   a, d
    cp   h
    jr   c, fwd        ; dst_hi < src_hi
    jr   nz, bwd       ; dst_hi > src_hi
    ld   a, e
    cp   l
    jr   c, fwd        ; dst_lo < src_lo
    ret  z             ; dst == src: no-op
bwd:
    ; LDDR wants HL=src+n-1, DE=dst+n-1.
    add  hl, bc
    dec  hl            ; HL = src + n - 1
    ex   de, hl        ; DE = src+n-1, HL = dst
    add  hl, bc
    dec  hl            ; HL = dst + n - 1
    ex   de, hl        ; DE = dst+n-1, HL = src+n-1
    lddr
    ret
fwd:
    ; LDIR wants HL=src, DE=dst.  Already in those registers.
    ldir
    ret
