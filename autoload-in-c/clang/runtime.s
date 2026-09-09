; runtime.s — Minimal Z80 runtime stubs for freestanding PROM build
;
; Provides memchr and __call_iy (indirect call via IY).
;
; memcpy / memset / memmove are NOT defined here: the compiler emits calls to
; the CallingConv::Z80_Builtin routines __z80_memcpy_builtin /
; __z80_memset_builtin / __z80_memmove_builtin, which — together with the C
; entry points _memcpy/_memset/_memmove — are provided by
; compiler-rt/lib/builtins/z80/{memcpy,memset,memmove}.asm and linked in via the
; Makefile.  Defining them here too would collide with those (duplicate symbol),
; and hand-rolled C-only versions would miss the __z80_*_builtin entry the
; backend actually calls.

	.section .text._memchr,"ax",@progbits
; void *memchr(const void *s, int c, size_t n)
; sdcccall(1): s=HL, c=E (truncated to byte), n=stack (2 bytes)
; Callee cleanup: pop n before returning.
; Returns pointer to match in DE, or NULL (DE=0).
; Uses CPIR: HL=source, A=search byte, BC=count.
	.globl	_memchr
_memchr:
	pop	iy		; save return address in IY
	pop	bc		; n (callee-cleanup the stack arg)
	; HL=s, E=c, BC=n
	ld	a, b
	or	c
	jr	z, .Lmemchr_notfound
	ld	a, e		; A = search byte
	cpir			; compare A with (HL++), dec BC, repeat until match or BC=0
	jr	nz, .Lmemchr_notfound
	; Found: HL points one past the match, back up
	dec	hl
	ex	de, hl		; return in DE
	jp	(iy)
.Lmemchr_notfound:
	ld	de, 0		; return NULL
	jp	(iy)

	.section .text.__call_iy,"ax",@progbits
; __call_iy — indirect function call via IY register
; Used by the compiler for calls through function pointers.
; IY holds the target address; JP (IY) transfers control.
	.globl	__call_iy
__call_iy:
	jp	(iy)
