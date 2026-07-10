; cpm_stdio_clang.asm -- clang/llvm-z80 register-ABI shim for the hand-asm
; classic-clib stdio entries fputc()/fgetc() (interim fix for z88dk#22).
;
; ROOT CAUSE (see z88dk#22): fputc/fgetc in the classic clib are hand-written
; assembler that pops its args off the STACK (__smallc), but clang passes them
; in REGISTERS (fputc: c->HL, fp->DE; fgetc: fp->HL) and there is no clang-ABI
; entry for these hand-asm functions (unlike the C-source fopen/fclose, which
; get recompiled per-compiler).  So a clang caller lands in the stack-ABI
; worker with garbage args -> hang.
;
; This bridges clang's register args into a normal __smallc stack call of the
; existing classic entries (_fputc/_fgetc), then returns the result in DE
; (llvm-z80 Ret_I16 = DE).  cpm_clang_shim.h redirects fputc()/fgetc() (and
; putc/getc) to these fresh symbols; z88dk itself is left untouched.

	SECTION	code_compiler

	PUBLIC	_fputc_clang
	PUBLIC	_fgetc_clang
	PUBLIC	_fclose_clang
	EXTERN	_fputc			; classic __smallc: stack [ret][fp][c], ret HL
	EXTERN	_fgetc			; classic __smallc: stack [ret][fp],     ret HL
	EXTERN	_fclose			; classic #asm:     stack [ret][fp],     ret HL

; int fputc_clang(int c, FILE *fp)  -- clang ABI: c in HL, fp in DE.
; __smallc order for fputc(c,fp): push c first, fp last (fp on top).  The
; classic _fputc leaves both args on the stack (caller cleans), so pop twice.
_fputc_clang:
	push	hl			; arg1: c
	ex	de, hl			; hl = fp
	push	hl			; arg2: fp (top of stack)
	call	_fputc			; classic; result in HL, args still on stack
	pop	de			; discard fp
	pop	de			; discard c
	ex	de, hl			; de = result (clang int return in DE)
	ret

; int fgetc_clang(FILE *fp)  -- clang ABI: fp in HL.
_fgetc_clang:
	push	hl			; arg: fp
	call	_fgetc			; classic; result in HL, arg still on stack
	pop	de			; discard fp
	ex	de, hl			; de = result (clang int return in DE)
	ret

; int fclose_clang(FILE *fp)  -- clang ABI: fp in HL.  fclose is also #asm
; stack-ABI (reads fp off the stack); leaves the arg on the stack, so pop it.
_fclose_clang:
	push	hl			; arg: fp
	call	_fclose			; classic; result in HL, arg still on stack
	pop	de			; discard fp
	ex	de, hl			; de = result (clang int return in DE)
	ret
