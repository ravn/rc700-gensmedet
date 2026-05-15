; cpnos-rom hal helpers — SDCC sdcccall(1) implementations of
; _port_in / _port_out.  Z80 ABI prepends an underscore to C names,
; so the asm symbols are `__port_in` / `__port_out` (two underscores).
;
; Narrowed to 8-bit port (#76) — Z80 IN/OUT instructions are
; fundamentally 8-bit on the wire, and RC702 doesn't decode A8-A15
; for I/O, so the wider uint16_t form had no functional effect.
;
; sdcccall(1) parameter passing for `f(uint8_t p, uint8_t v)`:
;   p      -> A
;   v      -> L
;   ret    -> A for u8, HL for u16
;   no stack manipulation (both u8 args fit in registers)

    SECTION RESIDENT_CODE

    ; OUT (C),A puts BC on the Z80 address bus during the I/O cycle:
    ; B drives A8-A15, C drives A0-A7.  On RC702 the upper byte is not
    ; decoded for I/O, so B stays at whatever value happens to be there
    ; -- no need to set it.  IN A,(n) on Z80 puts A (the register) on
    ; A8-A15, also nondeterministic.  Both helpers stay minimal:
    ;   __port_in  = 4 bytes (LD C,A / IN A,(C) / RET)
    ;   __port_out = 5 bytes (LD C,A / LD A,L / OUT (C),A / RET)

    PUBLIC __port_in
__port_in:
    ld   c, a                ; port number into C; B is don't-care on RC702
    in   a, (c)
    ret

    PUBLIC __port_out
__port_out:
    ld   c, a                ; port number into C; B is don't-care on RC702
    ld   a, l                ; A = v (sdcccall(1) 2nd u8 arg in L)
    out  (c), a
    ret
