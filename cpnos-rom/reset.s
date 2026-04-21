; cpnos-rom reset vector (Phase 0 skeleton)
;
; Entry at 0x0000 after power-on or reset.
; PROM0 is mapped; PROM1 at 0x2000 also mapped.  RAM is hidden under both
; until OUT (0x18) is executed.  For Phase 0 we just set up a stack in
; high RAM and call cpnos_main() in C.
;
; After Phase 1 the reset vector will:
;   1. DI, set stack
;   2. HW init (SIO/CTC/PIO)
;   3. Netboot: load CCP+BDOS into RAM
;   4. Copy resident BIOS chunk from ROM to 0xF580
;   5. OUT (0x18),A  -> PROM disable
;   6. JP to CCP
;
; NMI vector (0x0066) is a Phase 1 TODO; RC702 does not wire NMI so the
; hardwired location can hold other code or 0xFF padding.

    .section .reset, "ax"
    .global _reset
_reset:
    di
    ld sp, #0xF000              ; init stack below .resident_pre; grows
                                ; down into free RAM (0xEE24..0xF000 =
                                ; 476 B).  Session #30 extended RESIDENT
                                ; down to 0xF000 for RC700 console helpers;
                                ; stack init moved 0xF200 -> 0xF000.
                                ; IVT lives at 0xEE00..0xEE23; stack must
                                ; not dip below that.
    call _cpnos_main
1:  jr 1b                       ; hang if main returns
