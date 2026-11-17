; sections.asm — Section layout for zsdcc + zx0 autoload PROM.
;
;   _BOOT            0x0000  Reset vector, NMI (0x0066), dzx0_standard, text_compressed
;   CODE             0x7200  Decompressed payload in RAM:
;     (IVT data)               16 function pointers (intvec.c)
;     code_compiler            Compiled C code
;     rodata_compiler          Const strings, tables, banner
;     data_compiler            Initialized data
;     bss_compiler             Uninitialized variables
;     code_sentinel            Sentinel marker

	SECTION	_BOOT
	ORG	0x0000

	SECTION	CODE
	ORG	0x6000
	SECTION	code_compiler
	SECTION	rodata_compiler
	SECTION	data_compiler
	SECTION	bss_compiler
	SECTION	code_sentinel
