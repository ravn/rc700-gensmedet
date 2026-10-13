; sections.asm — Section layout (linker scaffolding).
;
; All code and data are in C files.  This file declares section
; origins and subsection ordering for the z88dk linker.
;
;   BOOT             0x0000  start(), banner_string, NMI (boot_rom.c)
;   CODE             0x7200  Copied to RAM by start():
;     (IVT data)               16 function pointers (intvec.c)
;     code_compiler            Compiled C code
;     rodata_compiler          Const strings, tables
;     data_compiler            Initialized data (fdc_cmd, fdc_result, etc.)
;     bss_compiler             Uninitialized variables
;     code_sentinel            code_end marker (must be last)

	SECTION	BOOT
	ORG	0x0000

	SECTION	CODE
	ORG	0x7200
	SECTION	code_compiler
	SECTION	rodata_compiler
	SECTION	data_compiler
	SECTION	bss_compiler
	SECTION	code_sentinel

	; NOTE: Payload size (_code_end - _intvec + 1) cannot be computed
	; at link time via DEFC — z80asm asserts on cross-subsection symbol
	; arithmetic.  Computed at runtime in start() instead (+8 bytes).
