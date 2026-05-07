; cpnos-rom reset vector — z88dk SDCC port of reset.s.
;
; Runs at cold boot with undefined SP — must set one before any C
; code gets pushed onto it.  Then tail-jump into the asm relocator
; which copies PROM1 to RAM and jumps to _cpnos_cold_entry.
;
; SP = 0xF700: same value as clang __stack_top (payload.ld).  Stack
; grows down through 0xF621..0xF6FF (~223 B; max observed depth ~50 B
; during init).  Sits below PIO_RX BSS at 0xF700+, above the resident
; image's high water mark at 0xF7DF.  Setting SP into PROM-mapped
; RAM at boot is safe because the PROM only shadows 0x0000..0x07FF
; and 0x2000..0x27FF; everything above is real RAM.

    SECTION RESET

    EXTERN _relocate

    PUBLIC _reset
_reset:
    di
    ld   sp, 0xF700
    jp   _relocate
