; cpnos-rom z88dk section layout for SDCC build (Option C+).
;
; Single contiguous resident image at VMA 0xEE00..0xF7FF (2.5 KB),
; physically split across PROM0 tail (0x0400..0x07FF, 1 KB) and
; PROM1 (0x2000..0x25FF, 1.5 KB).  prom_loader copies both chunks
; to RAM at boot.
;
; Layout pinned by clang's payload.ld (we mirror it for source/ABI
; compatibility):
;
;   0xEE00  RESIDENT_JUMPTABLE  _bios_boot — CP/M BIOS jump table base
;   0xEE33  RESIDENT_SNIOS_JT   _snios_jt — DRI SNIOS jt (NDOS ABI)
;   ...     RESIDENT_SNIOS      SNIOS body, ISRs, all other code
;   0xF500  __ivt_start          IVT (Z80 IM2 vector table, 36 B)
;   0xF700  __stack_top          stack base (grows down)
;   0xF800  display memory       hardware-mapped CRT video RAM
;
; Cold-init BSS at 0xEC00..0xEDFF lives in the same RAM region that
; cpnos.com loads into (0xE180..0xEE00).  This works because cold-init
; finishes BEFORE netboot starts overwriting BSS — see cpnos_main.c
; ordering (cfgtbl_init / init_hardware / banner / netboot_mpm).
;
; PROM disable (OUT 0x18,A) does NOT happen in PROM0 — it lives in
; resident_handoff (cpnos_main.c) which runs from RAM after netboot.
;
; Linker-defined constants — clang's payload.ld supplies these via
; `--defsym` / linker-script assignment.  SDCC needs them as PUBLIC
; numeric constants so cross-TU references resolve.

    PUBLIC __ivt_start
    defc __ivt_start = 0xF500    ; IVT base address (page-aligned).
                                 ; KNOWN BUG (task #18): no SECTION
                                 ; reservation backs this — _cursor_down
                                 ; (0xF4FF) and _cursor_up (0xF516)
                                 ; land inside this range.  Fixed at
                                 ; step 7 of the header-driven plan
                                 ; (see /Users/ravn/.claude/plans/
                                 ; harmonic-sleeping-spring.md).

    PUBLIC __ivt_end
    defc __ivt_end = 0xF500 + 18 * 2

    ; _pio_rx_buf_page is derived from HIGH(_pio_rx_buf) AFTER the BSS
    ; chain is laid out — see SECTION bss_pio_rx near the bottom of
    ; this file.  The previous design declared it here as a hardcoded
    ; literal (0xF7) which silently disagreed with where SDCC actually
    ; placed `pio_rx_buf` (0xECEE in bss_compiler), so the ISR's
    ; `ld h, _pio_rx_buf_page; ld l, head` trick built addresses into
    ; resident code instead of into the buffer.  Deriving from HIGH()
    ; of the symbol's actual placement makes the constant impossible
    ; to drift from the buffer location — the linker computes both.

;-----------------------------------------------------------------
; PROM0 — reset vector + tiny prom_loader (lives at 0x0000..)
;-----------------------------------------------------------------

    SECTION RESET
    org 0x0000

    SECTION INIT_CODE
    SECTION INIT_RODATA

;-----------------------------------------------------------------
; RESIDENT — single contiguous block at 0xEE00..0xF7FF (~2.5 KB).
;
; cpnos.com (cpnos-build) hardcodes NIOS = 0xEE33 in cpnios-shim.asm.
; That requires _snios_jt at exactly 0xEE33, which means _bios_boot
; at 0xEE00 (BIOS jt is 51 bytes; SNIOS jt starts immediately after
; at 0xEE00+51 = 0xEE33).  Mirrors clang's _bios_boot=0xEE00 layout.
;
; Section ordering (BIOS_JT first, then SNIOS, then everything else)
; matches clang's payload.ld so the resident image is structurally
; identical between the two builds.  Makefile dd-splits the resulting
; single per-section binary into PROM0 tail (first 1024 B → RAM
; 0xEE00..0xF1FF) and PROM1 (next ≤1536 B → RAM 0xF200..0xF7FF;
; loader caps at 1536 to clear display memory at 0xF800).
;-----------------------------------------------------------------

    SECTION RESIDENT_JUMPTABLE
    org 0xEE00

    SECTION RESIDENT_SNIOS_JT
    SECTION RESIDENT_SNIOS
    SECTION RESIDENT_ISR
    SECTION RESIDENT_PRE_CODE
    SECTION RESIDENT_PRE_RODATA
    SECTION RESIDENT_CODE

    ; --- z88dk runtime sections, pinned INSIDE the resident chain ---
    ;
    ; If we don't declare these, z88dk auto-places them in the next
    ; section chain it sees — which is SCRATCH_BSS at 0xEC00.  Any
    ; library function brought in there (`_memset`, `_memcpy`,
    ; `_memmove`, sccz80 helpers, etc.) lands in unloaded RAM, and
    ; calls jump into uninitialised memory.  By declaring the chain
    ; here we force them into the RAM that prom_loader actually
    ; copies (0xEE00..0xF7FF).  The check_sdcc_layout.py audit at
    ; build time enforces this invariant.
    SECTION code_clib
    SECTION code_crt_init
    SECTION code_home
    SECTION code_l_sccz80
    SECTION code_string
    SECTION code_compiler

    SECTION RESIDENT_RODATA

    ; Runtime RODATA / DATA aliases — same rationale as code_*: any
    ; library function that emits a literal string or table must
    ; resolve into PROM-loaded RAM.
    SECTION rodata_clib
    SECTION rodata_compiler
    SECTION rodata_string
    SECTION data_clib
    SECTION data_compiler

    SECTION RESIDENT_DATA

;-----------------------------------------------------------------
; SCRATCH BSS — VMA 0x0800 (NOLOAD; not in either PROM image).
;
; Clang puts BSS at 0xF524 (a 220 B gap between IVT at 0xF500 and
; pio_rx_buf at 0xF700).  SDCC's BSS is ~500 B and doesn't fit there.
; Putting it at 0xEC00 (the original cpnos_rom.ld scratch region)
; doesn't work either — that overlaps cpnos.com's load region
; (0xE180..0xEE00), and netboot's LDIR clobbers _cfgtbl mid-stream
; once cpnos.com fills past byte 0xA80 (sector 22).  Symptom: SNIOS
; netboot stalls at 22/25 dots because _cfgtbl.netst.ACTIVE gets
; overwritten and SNDMSG returns SNDERR on the next call.
;
; 0x0800..0x0BFF is ideal: RAM at boot (PROM0 only shadows
; 0x0000..0x07FF), unused during cold init, eventually becomes part
; of the user TPA (0x0100..0xCFFF) — by which point the BSS is dead
; (cold-init complete, cpnos.com handed control to NDOS).
;-----------------------------------------------------------------

    SECTION SCRATCH_BSS
    org 0xEC00

    ; PIO-B receive ring — page-aligned 256-byte buffer.  Defined here
    ; (not in transport_pio.c) so the linker can place it page-aligned
    ; AND so _pio_rx_buf_page can be derived from HIGH(_pio_rx_buf)
    ; instead of being a hardcoded literal that can drift from the
    ; actual placement.  Lands first in the BSS chain (BSS @ 0xEC00 is
    ; already page-aligned, so this is at exactly 0xEC00 with zero
    ; alignment slack).  ISR reads via `ld h, _pio_rx_buf_page; ld l,
    ; head` so the buffer MUST be page-aligned for the trick to work.
    SECTION bss_pio_rx
    align 256
    PUBLIC _pio_rx_buf
_pio_rx_buf:
    defs 256

    PUBLIC _pio_rx_buf_page
    defc _pio_rx_buf_page = _pio_rx_buf / 256

    SECTION bss_compiler

    ; BSS aliases the z88dk libs may emit.  These need to be in the
    ; BSS scratch range (zeroed on cold init), not in unrelated RAM.
    SECTION bss_clib
    SECTION bss_string
