;-----------------------------------------------------------------
; cpnos-in-c SDCC PROM1-only line program — bootstrap.
;
; Mirrors clang-prom1lineprog/bootstrap.s but in z88dk z80asm syntax.
;
; Lives at PROM1 ROM 0x2000.  autoload-in-c PROM0 reads the jump
; target at 0x2000 (a 2-byte little-endian word) and the 6-byte
; signature at 0x2002, then jumps to bootstrap_entry.
;
; Boot flow:
;   1. DI + set SP (per linker symbol __stack_top).
;   2. ZX0-decompress resident payload to RAM 0xED00.
;   3. ZX0-decompress init code to RAM 0xC000.
;   4. JP 0xC000 -> cpnos_cold_entry; that function pre-fills outcon
;      + arms _prom1_only_sentinel at the C side (shared with two-
;      PROM cold path, see init.c::cpnos_cold_entry).
;
; Resident's install_locale_tables() in resident_handoff overlays
; the real US-ASCII outcon + Danish inconv from cpnos.img after
; netboot lands them at 0xDC00.
;-----------------------------------------------------------------

    EXTERN _dzx0_standard
    EXTERN __payload_zx0_start
    EXTERN __init_zx0_start
    EXTERN _cpnos_cold_entry

    PUBLIC bootstrap_entry

    SECTION LINEPROG_HEADER
    ; 0x2000: jump target read by autoload-in-c (.word = 2 B little-endian)
    defw bootstrap_entry
    ; 0x2002: 6-byte signature
    defm " RC702"

    SECTION LINEPROG_ENTRY

bootstrap_entry:
    di
    ld   sp, 0xF680             ; matches clang-prom1lineprog stack top

    ; Decompress resident payload to 0xED00.  Must happen first
    ; because init code (decompressed next) calls resident helpers.
    ld   hl, __payload_zx0_start
    ld   de, 0xED00
    call _dzx0_standard

    ; Decompress init at 0xC000.  cpnos_cold_entry is the first
    ; symbol in INIT_CODE -- its runtime address is exactly 0xC000.
    ld   hl, __init_zx0_start
    ld   de, 0xC000
    call _dzx0_standard

    ; Tail-call into init.  cpnos_cold_entry is NORETURN; it pre-
    ; fills outcon + arms the sentinel itself (init.c session
    ; 73j-late consolidation), runs hw bring-up + netboot, ending
    ; in resident_handoff which RAMENs and JPs to NDOS at 0xDD80.
    ;
    ; Use the linker-resolved symbol rather than literal 0xC000:
    ; SDCC's z88dk linker does not guarantee cpnos_cold_entry is
    ; the first symbol in INIT_CODE.  In this build it lands at
    ; ~0xC1A1; clang's link orders sections so that the symbol is
    ; at 0xC000, but we should not rely on link-order coincidence.
    jp   _cpnos_cold_entry
