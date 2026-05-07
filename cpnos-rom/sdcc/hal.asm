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

    PUBLIC __port_in
__port_in:
    ; HL = port (16-bit; low byte is the actual Z80 port number)
    ld   c, l
    in   a, (c)
    ret

    PUBLIC __port_out
__port_out:
    ; HL = port (16-bit), stack: [retaddr (2B), v (1B), caller-data...]
    ld   c, l                ; port -> C, HL freed
    ld   hl, 2
    add  hl, sp              ; HL = &v (at sp+2)
    ld   a, (hl)             ; A = v
    out  (c), a
    ; Callee-cleanup: pop retaddr, eat the 1-byte v, jp (hl).
    pop  hl                  ; HL = retaddr, sp += 2
    inc  sp                  ; eat v, sp += 1
    jp   (hl)                ; return
