; sections.asm -- Section layout for RC702 autoload PROM using zcc +z80 -compiler=llvmz80
;
; _BOOT is placed at 0x0000 in ROM, containing reset entry, decompressor, and the
; compressed payload.
; CODE and all sub-sections are ORG'd at 0x6000 (RAM target address for payload).
; IM2 requires intvec_compiler at 0x6000 (page-aligned, I=0x60).

	SECTION	_BOOT
	ORG	0x0000

	SECTION CODE
	ORG	0x6000
	SECTION intvec_compiler
	SECTION code_compiler
	SECTION rodata_compiler
	SECTION data_compiler
	SECTION bss_compiler
	SECTION _code_sentinel
