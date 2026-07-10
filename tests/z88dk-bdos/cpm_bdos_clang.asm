; cpm_bdos_clang.asm -- clang/llvm-z80 register-ABI override for the CP/M
; bdos()/bdosh() entry points (interim shim for z88dk#20).
;
; ROOT CAUSE: under clang, include/sys/compiler.h strips __smallc and
; __z88dk_callee to nothing, so clang passes the fixed 2 args of bdos_callee()
; in registers (func -> HL, arg -> DE).  But the prebuilt classic cpm_clib
; (sccz80-built) reads those args off the STACK, so clang callers hand it
; garbage -> wrong BDOS function number -> RC702 warm-boots.  cpm.h maps
; user bdos()/bdosh() to bdos_callee()/bdosh_callee().  Rather than fight the
; z80asm linker over duplicate symbols, cpm_clang_shim.h redirects the bdos()
; macro to the fresh register-ABI symbols _bdos_clang / _bdosh_clang defined
; here -- no clash with the classic modules, z88dk itself untouched.
; (File I/O in bdostst.c goes through the __ZPROTO clang-ABI stdio variants,
; which z88dk already provides for clang -- only the bdos family is broken.)
;
; VERIFIED green via the MAME BDOS-5 tracer: with this object linked, the
; program issues C=12 (VERSION), C=25 (CURDSK), C=32 (USER, DE=00FF) instead
; of the pre-fix garbage C=25/252/196/0.

	SECTION	code_compiler

	PUBLIC	_bdos_clang
	PUBLIC	_bdosh_clang
	EXTERN	__bdos			; push ix; call BDOS(base+5); pop ix; ret

; int bdos_callee(int func, int arg)  -- clang ABI: func in HL, arg in DE.
; Returns int in DE (llvm-z80 Ret_I16 = DE); negative on BDOS error.
_bdos_clang:
	ld	c, l			; func low byte -> C (BDOS function)
					; DE already holds arg
	call	__bdos
	ld	e, a			; BDOS return code -> E (return low byte)
	rla				; make result negative if error (bit7)
	sbc	a, a
	ld	d, a			; sign-extend -> D (return high byte)
	ret

; int bdosh_callee(int func, int arg) -- clang ABI: func in HL, arg in DE.
; Like bdos_callee but returns raw 16-bit (HW error in MSB), no sign fixup.
_bdosh_clang:
	ld	c, l			; func low byte -> C
					; DE already holds arg
	call	__bdos
	ld	e, a			; return code -> E (low byte)
	ld	d, h			; keep BDOS H (HW error) -> D (high byte)
	ret
