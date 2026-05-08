; cpnos-rom reset vector -- z88dk SDCC port of reset.s.
;
; Runs at cold boot with undefined SP -- must set one before any C
; code gets pushed onto it.  Then tail-jump into the C relocator
; (relocator.c, in INIT_CODE) which copies the chunks to RAM, zeroes
; the BSS extents, verifies the resident checksum, and jumps to
; _cpnos_cold_entry.
;
; SP = 0xEC00: stack lives BELOW the resident range 0xEE00..0xF7FF.
;
; This matters because the relocator's checksum pass (after memcpy +
; BSS clear) word-sums the entire resident range and compares against
; the patched magic 0xCAFE.  Under SDCC, _memset is a library call
; that pushes registers around; if the stack lived inside the
; resident region, those pushes would corrupt the bytes the checksum
; is about to read.
;
; (Under clang Z80 __builtin_memset lowers to inline LDIR-from-self
;  with ZERO stack pushes, so clang's reset.s can park SP at 0xF700
;  without hitting this trap.  See payload.ld __stack_top.)
;
; SP = __stack_top, which the linker resolves from cpnos.com's NDOSRL
; symbol at build time (cpnos_layout.asm, generated from cpnos.sym).
; First push lands at NDOSRL-1, in TPA proper (0x0100..NDOSRL-1) which
; is genuinely unused at boot.  Stack at or above NDOSRL would stomp
; cpnos.com's variable storage -- bug fixed by Path 6.1.  HARD RULE
; feedback_no_literal_addresses.md: never literal an SP value here;
; if cpnos-build's DATA_BASE shifts, __stack_top tracks automatically.
;
; This SP value clears every hazard simultaneously:
;   - resident region (relocator's checksum reads it)
;   - BSS-clear extents (relocator's memset wipes them)
;   - cpnos.com CODE region (netboot LDIR overwrites)
;   - cpnos.com NDOSRL data (NDOS reads at COLDST)
;   - IVT page (must stay intact once EI is on)
; Stack lives just below NDOSRL during init+netboot+resident_handoff.

    SECTION RESET

    EXTERN _relocate
    EXTERN __stack_top

    PUBLIC _reset
_reset:
    di
    ld   sp, __stack_top
    jp   _relocate
