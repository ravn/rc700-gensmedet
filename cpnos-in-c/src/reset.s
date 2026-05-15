; cpnos-rom reset vector (PROM0 at 0x0000).
;
; Runs at cold boot with undefined SP — we must set one before any C
; code gets pushed onto it.  Then tail-jump into the C relocator
; (relocator.c) which does the heavy lifting: two #embed'd payload
; chunks copied to RAM at 0xED00, then jp _cpnos_cold_entry.
;
; SP value comes from __stack_top in the payload's linker script
; (see payload.ld; --defsym from the Makefile makes the symbol
; visible to relocator.elf too).  payload.ld's ASSERTs keep the
; stack from colliding with cpnos.com's load region or the resident
; payload.

    .section .reset, "ax"
    .global _reset
    .extern __stack_top
_reset:
    di
    ld   sp, __stack_top
    jp   _relocate
