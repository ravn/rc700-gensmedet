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
; Pushes go to 0xEBFE..0xEBFF and below.  That's plain RAM at boot --
; PROM only shadows 0x0000..0x07FF and 0x2000..0x27FF; everything
; else is real RAM.  cpnos.com loads later at 0xDF80..0xEC00 (top
; exclusive), but at relocator time that region is unused, so a few
; bytes of stack scribble in 0xEBxx is harmless.  By the time
; cpnos_cold_entry runs, the resident handoff sets up its own stack.

    SECTION RESET

    EXTERN _relocate

    PUBLIC _reset
_reset:
    di
    ld   sp, 0xEC00
    jp   _relocate
