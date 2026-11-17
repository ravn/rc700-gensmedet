; sections.asm — Section layout for zsdcc + zx0 autoload PROM.
;
;   _BOOT            0x0000  Reset vector, NMI (0x0066), dzx0_standard, text_compressed
;   CODE             0x6000  Decompressed payload in RAM:
;     (IVT data)               16 function pointers (intvec.c)
;     code_compiler            Compiled C code
;     rodata_compiler          Const strings, tables, banner
;     data_compiler            Initialized data
;     code_l_sccz80            z88dk sccz80 runtime helpers (e.g. l_jphl)
;     code_l_sdcc              z88dk sdcc runtime helpers (e.g. ___sdcc_call_hl)
;     code_clib                z88dk C library helpers
;     code_string              z88dk string helpers
;     bss_compiler             Uninitialized variables (cleared in RAM by boot.asm)

	SECTION	_BOOT
	ORG	0x0000

	SECTION	CODE
	ORG	0x6000
	SECTION	code_compiler
	SECTION	rodata_compiler
	SECTION	data_compiler
	SECTION	code_l_sccz80
	SECTION	code_l_sdcc
	SECTION	code_clib
	SECTION	code_string

	SECTION	BSS
	SECTION	bss_compiler

