;-----------------------------------------------------------------
; cpnos-in-c SDCC PROM1-only line program — section anchors.
;
; Mirrors sdcc/sections.asm but with the PROM-resident sections
; (RESET, INIT_CODE, INIT_RODATA, PAYLOAD_HEADER, PAYLOAD_HEADER_P1)
; dropped -- they belong to the two-PROM cold path.  In their place:
;   LINEPROG_HEADER  0x2000  jump-target + " RC702" signature
;   LINEPROG_ENTRY   0x2008  bootstrap entry (ZX0 decompress + JP)
;   PROM1_BODY       (after bootstrap; INCBIN compressed init + payload)
;
; Resident at 0xED00 is unchanged from sdcc/sections.asm -- the
; resident chain is byte-identical between two-PROM and PROM1-only,
; only the cold path differs.  init is relinked at VMA 0xC000 (RAM)
; for this variant because bootstrap decompresses it there before
; jumping in.
;-----------------------------------------------------------------

    SECTION LINEPROG_HEADER
    org 0x2000

    SECTION LINEPROG_ENTRY

    SECTION INIT_CODE
    org 0xC000

    SECTION INIT_RODATA

    SECTION RESIDENT_JUMPTABLE
    org 0xED00

    SECTION RESIDENT_SNIOS_JT
    SECTION RESIDENT_SNIOS
    SECTION RESIDENT_ISR
    SECTION RESIDENT_PRE_CODE
    SECTION RESIDENT_PRE_RODATA
    SECTION RESIDENT_CODE

    SECTION code_clib
    SECTION code_crt_init
    SECTION code_home
    SECTION code_l_sccz80
    SECTION code_string
    SECTION code_compiler

    SECTION RESIDENT_RODATA

    SECTION rodata_clib
    SECTION rodata_compiler
    SECTION rodata_string
    SECTION data_clib
    SECTION data_compiler

    SECTION RESIDENT_DATA

    SECTION RESIDENT_CHECKSUM

    ; SCRATCH_BSS layout matches clang-prom1lineprog/payload.ld v3:
    ;   0xEB00 .. 0xEBFF  scratch_bss (shrunk from 0x200)
    ;   0xEC00 .. 0xECFF  pio_rx_buf (moved from 0xF700)
    ;   0xF53C .. 0xF60D  cfgtbl (moved out of scratch_bss)
    ;   0xF680 .. 0xF7FF  locale tables (installed from cpnos.img prefix)
    SECTION SCRATCH_BSS
    org 0xEB00

    SECTION bss_compiler
    SECTION bss_clib

    SECTION CFGTBL_BSS
    org 0xF53C

    SECTION PIO_RX_BSS
    org 0xEC00
