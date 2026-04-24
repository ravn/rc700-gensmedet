; cpnos-rom reset vector (PROM0 at 0x0000).
;
; Runs at cold boot with undefined SP — we must set one before any C
; code gets pushed onto it.  Then tail-jump into the C relocator
; (relocator.c) which does the heavy lifting: two #embed'd payload
; chunks copied to RAM at 0xDE00, then jp _cpnos_cold_entry.
;
; SP=0xED00 is the top of the runtime DISKBSS region — the stack
; grows down from there into the 0xEC24..0xED00 gap above the IVT.
;
; Three instructions of glue is all the asm there is.  The rest of
; the relocator lives in C with C23 semantics (#embed, typed arrays).

    .section .reset, "ax"
    .global _reset
_reset:
    di
    ld   sp, 0xED00
    jp   _relocate
