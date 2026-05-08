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
; SP=0xD980 (Path 6.1, 2026-05-08): one byte below NDOSRL (cpnos.com's
; DATA region 0xD980..0xDD7F).  Stack grows DOWN from 0xD980 into TPA
; proper (0x0100..0xD97F) which is pre-zeroed at boot and genuinely
; unused until CCP loads transient programs -- by which time
; enter_coldst has reset SP=0x0100 anyway.
;
; The earlier Path 6 value 0xDD80 was off by 1024 bytes: it placed SP
; at the TOP of cpnos.com's CODE region, which is correctly above the
; netboot LDIR target, but each push then wrote DOWN into NDOSRL
; (0xD980..0xDD7F), NOT into "TPA RAM" as the prior comment claimed.
; Symptom: NDOS COLDST read its own variable storage post-handoff,
; saw stack-stomped values, never reached CCP/E>; impl_conout was
; instead called with c=0 in a tight loop, flooding SIO-B with 0x00s.
; (Diagnosed via probe-results-2026-05-08.md; clang's stack at
; 0xF700 in scratch_bss never had this problem.)
;
; This SP value clears every hazard simultaneously:
;   - resident region 0xED00..0xF7FF (relocator's checksum reads it)
;   - BSS-clear extents 0xEA00..0xECFF (relocator's memset wipes them)
;   - cpnos.com load region 0xDD80..0xE9FF (netboot LDIR overwrites)
;   - cpnos.com NDOSRL data 0xD980..0xDD7F (NDOS reads at COLDST)
;   - IVT 0xEA00..0xEA23 (must stay intact once EI is on)
; Stack lives at ~0xD900..0xD97F during init+netboot+resident_handoff,
; far from anything that's actively being read or written.

    SECTION RESET

    EXTERN _relocate

    PUBLIC _reset
_reset:
    di
    ld   sp, 0xD980
    jp   _relocate
