                                        ; Start of file scope inline assembly
	GLOBAL	_nmi_handler
_nmi_handler:
	retn
	SECTION	code_compiler
                                        ; End of file scope inline assembly
	GLOBAL	_start                          ; -- Begin function start
_start:                                 ; @start
; %bb.0:                                ; %entry
	;APP
	di
	;NO_APP
	;APP
	ld	sp,49151
	;NO_APP
	call	_reloc_zx0
	ld	hl,__bss_start
	ld	de,0
	ld	bc,__bss_size
	call	___z80_memset_builtin
	call	_main_relocated
	ret
                                        ; -- End function
	GLOBAL	_banner_string                  ; @banner_string
_banner_string:
	DEFM	" RC700 ROA375 CL 2026-09-27 23.57 5fc4891/ravn\000"

	EXTERN	___z80_memset_builtin
	EXTERN	__bss_size
	EXTERN	__bss_start
	EXTERN	_llvm_memset_p0_i16
	EXTERN	_main_relocated
	EXTERN	_reloc_zx0
