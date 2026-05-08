; cpnos-rom hal helpers — SDCC sdcccall(1) implementations of
; _port_in / _port_out.  Z80 ABI prepends an underscore to C names,
; so the asm symbols are `__port_in` / `__port_out` (two underscores).
;
; sdcccall(1) parameter passing for `f(uint16_t p, uint8_t v)`:
;   p      -> HL
;   v      -> stack as 1-byte slot (push af; inc sp on caller side)
;   ret    -> A for u8, HL for u16
;   stack  -> callee-cleanup (we pop retaddr, inc sp by 1, jp (hl))

    SECTION RESIDENT_CODE

    ; OUT (C),A puts BC on the Z80 address bus during the I/O cycle:
    ; B drives A8-A15, C drives A0-A7.  We mirror the full 16-bit port
    ; from HL into BC so a partial-decode peripheral that latches the
    ; high address bits sees the same upper byte the caller specified.
    ; Clang lowers `*(volatile __io u8*)0x18 = v` to OUT ($18),A
    ; (D3 18) which puts A (the value) on A8-A15; on RC702 hardware
    ; A8-A15 are not decoded for I/O so it doesn't matter on this
    ; machine, but garbage on the upper byte is a latent risk class
    ; for any test target (MAME with full 16-bit I/O, future port).
    ;
    ; IN A,(n) on Z80 puts A_register on A8-A15, which is also a
    ; nondeterministic value -- no parity gain from setting B = H in
    ; __port_in, so __port_in stays at the byte-cheaper one-LD form.

    PUBLIC __port_in
__port_in:
    ; HL = port (16-bit; low byte is the actual Z80 port number)
    ld   c, l
    in   a, (c)
    ret

    PUBLIC __port_out
__port_out:
    ; HL = port (16-bit), stack: [retaddr (2B), v (1B), caller-data...]
    ld   b, h                ; B = port_high, mirrored on A8-A15
    ld   c, l                ; C = port_low, mirrored on A0-A7
    ld   hl, 2
    add  hl, sp              ; HL = &v (at sp+2)
    ld   a, (hl)             ; A = v
    out  (c), a
    ; Callee-cleanup: pop retaddr, eat the 1-byte v, jp (hl).
    pop  hl                  ; HL = retaddr, sp += 2
    inc  sp                  ; eat v, sp += 1
    jp   (hl)                ; return
