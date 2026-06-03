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
; Resident at 0xEE00 (post-TPA-grow 2026-06-04; was 0xED00).  init is
; relinked at VMA 0xC000 (RAM) for this variant because bootstrap
; decompresses it there before jumping in.
;-----------------------------------------------------------------

    SECTION LINEPROG_HEADER
    org 0x2000

    SECTION LINEPROG_ENTRY

    SECTION INIT_CODE
    org 0xC000

    SECTION INIT_RODATA

    SECTION RESIDENT_JUMPTABLE
    org 0xEE00

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
    ; Mirrors sdcc/sections.asm: 2-byte slot at the very end of the
    ; resident chain; patch_payload_checksum.py overwrites these
    ; bytes post-link so word-additive sum of the resident = 0xCAFE.
    align 2
    PUBLIC __payload_checksum
__payload_checksum:
    defw 0xFFFF

    ; SCRATCH_BSS layout matches clang-prom1lineprog/payload.ld post-
    ; TPA-grow 2026-06-04:
    ;   0xEB00 .. 0xEB23  bss_ivt (36 B IM2 vector table, page-aligned)
    ;   0xEB24 .. 0xEBF5  cfgtbl (210 B; packed into IVT tail to free
    ;                     upper-region space for the shift-up)
    ;   0xEC00 .. 0xECFF  scratch_bss
    ;   0xED00 .. 0xEDFF  pio_rx_buf (page-aligned)
    ;   0xF680 .. 0xF7FF  locale tables (installed from cpnos.img prefix)

    ; IM2 IVT -- 36 B at the head of a page so `I = HIGH(__ivt_start)`
    ; = 0xEB suffices.  Page-aligned by `org 0xEB00`.
    SECTION bss_ivt
    org 0xEB00
    PUBLIC __ivt_start
    PUBLIC __ivt_end
__ivt_start:
    defs 36
__ivt_end:

    ; cfgtbl moved into IVT-page tail (2026-06-04 TPA-grow).  Lives
    ; right after the 36 B IVT vectors, occupying 0xEB24..0xEBF5.
    ; init.c::cfgtbl has SECTION_BSS_CFGTBL attribute which maps to
    ; `bss.cfgtbl` under clang; the SDCC compat shim uses .bss_cfgtbl.
    SECTION bss_cfgtbl
    org 0xEB24

    SECTION SCRATCH_BSS
    org 0xEC00

    SECTION bss_compiler
    SECTION bss_clib
    SECTION bss_string

    ; PIO-B receive ring -- page-aligned 256-byte buffer at 0xED00
    ; (was 0xEC00 pre-TPA-grow).  ISR reads via
    ; `ld h, _pio_rx_buf_page; ld l, head/tail`, so the buffer MUST be
    ; page-aligned and _pio_rx_buf_page is derived from the actual
    ; placement (no hardcoded literal).
    SECTION bss_pio_rx
    org 0xED00
    align 256
    PUBLIC _pio_rx_buf
_pio_rx_buf:
    defs 256

    PUBLIC _pio_rx_buf_page
    defc _pio_rx_buf_page = _pio_rx_buf / 256
