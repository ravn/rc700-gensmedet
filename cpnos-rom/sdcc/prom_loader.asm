; cpnos-rom Option C+ PROM loader (SDCC build).
;
; Hybrid Option C: resident image is split across PROM0 tail and
; PROM1, giving a ~2.5 KB budget vs single-PROM Option C's 2 KB.
; Two LDIRs copy the chunks to RAM, then JP to _cpnos_cold_entry.
;
; PROM disable (OUT 0x18,A) does NOT happen here — we are still
; executing from PROM0.  PROM disable lives in resident_handoff
; (cpnos_main.c) which runs from RAM.
;
; PROM image layout:
;   PROM0  0x0000..0x03FF  reset + this loader (~30 B + 0xFF pad)
;   PROM0  0x0400..0x07FF  RESIDENT_PRE_CODE chunk (1024 B max)
;   PROM1  0x2000..0x2600  RESIDENT_JUMPTABLE+body (1536 B max)
;   PROM1  0x2600..0x27FF  unused (would clobber display RAM if copied)
;
; RAM layout after the two LDIRs (PROM still mapped):
;   0xEE00..0xF1FF  RESIDENT_PRE (cold-init code: init.c, netboot_mpm.c)
;   0xF200          _bios_boot (BIOS jump table — CP/M ABI)
;   0xF200..0xF7FF  RESIDENT_JUMPTABLE+body
;
; Entry: SP set by reset.asm, PROMs mapped, all interrupts off.

    SECTION INIT_CODE

    EXTERN _cpnos_cold_entry

    PUBLIC _relocate
_relocate:
    ; Chunk A: PROM0 tail -> RAM 0xEE00 (RESIDENT_PRE).
    ld   hl, 0x0400
    ld   de, 0xEE00
    ld   bc, 0x0400
    ldir
    ; DE is now 0xF200, ready for chunk B.
    ; Chunk B: PROM1 -> RAM 0xF200 (RESIDENT body, BIOS jt at start).
    ld   hl, 0x2000
    ld   bc, 0x0600
    ldir

    ; Clear scratch BSS at 0xEC00..0xEDFF.  bss_compiler / bss_clib /
    ; bss_string all live here (sections.asm pins them in this chain).
    ; Without this, RAM contents at boot are whatever cpnos.com's load
    ; sequence happened to leave behind — violating the C-language
    ; contract that BSS variables start zero-initialised.  Done HERE
    ; (in the non-relocated loader, before any relocated C runs) so
    ; nothing reads the stale values.
    ;
    ; LDIR-from-self trick: zero the first byte, then LDIR (HL) -> (DE)
    ; with HL pointing one byte before DE.  Each iteration reads the
    ; just-written 0x00 and propagates it.  Cheaper than seeding a
    ; ROM-resident zero buffer.
    ld   hl, 0xEC00
    ld   (hl), 0
    ld   de, 0xEC01
    ld   bc, 0x01FF             ; 0xEDFF - 0xEC01 + 1 = 0x01FF
    ldir

    jp   _cpnos_cold_entry
