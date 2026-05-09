; cpnos-rom SDCC runtime helpers.
;
; _mem_copy_backwards_callee — direction-known LDDR for callers that
; statically know dst > src (e.g. resident.c::insert_line).
;
; Caller passes END-pointers (last byte of each region) so this helper
; just does a single LDDR + ret.  No direction check, no add/dec
; preamble.  ~12 B, callee-cleanup z88dk ABI.
;
;     mem_copy_backwards(dst + n - 1, src + n - 1, n)
;
; The general overlap-safe `_memmove_callee` (~33 B) was removed from
; this file when its only caller (resident.c::insert_line) migrated to
; mem_copy_backwards.  rc700_console.c is clang-only; SDCC has no
; remaining call site for the general memmove.  If a future SDCC
; caller emerges with unknown direction, either restore the helper
; here (overrides z88dk libc's 150 B `_memmove_callee`) or refactor
; the caller to use mem_copy_backwards.  Tracked as
; ravn/rc700-gensmedet#77.

SECTION RESIDENT_CODE

PUBLIC _mem_copy_backwards_callee

_mem_copy_backwards_callee:
    pop  iy            ; ret
    pop  de            ; DE = dst_end (1st arg)
    pop  hl            ; HL = src_end (2nd arg)
    pop  bc            ; BC = n      (3rd arg)
    push iy            ; restore ret
    ld   a, b
    or   c
    ret  z             ; n == 0: nothing to copy
    lddr
    ret
