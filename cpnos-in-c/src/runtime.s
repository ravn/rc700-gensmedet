; runtime.s — Minimal Z80 runtime stubs for freestanding PROM build
;
; Provides memcpy, memset, and __call_iy (indirect call via IY).

	.section .text._memcpy,"ax",@progbits
; void *memcpy(void *dest, const void *src, size_t n)
; sdcccall(1): dest=HL, src=DE, n=stack (2 bytes)
; Callee cleanup: pop n before returning.
; Returns dest in DE.
	.globl	_memcpy
_memcpy:
	pop	iy		; save return address in IY
	pop	bc		; n (callee-cleanup the stack arg)
	; HL=dest, DE=src, BC=n
	ex	de, hl		; DE=dest, HL=src
	ld	a, b
	or	c
	jr	z, .Lmemcpy_done
	ldir
.Lmemcpy_done:
	; return dest in DE (already there)
	jp	(iy)		; return via IY (stack is clean)

	.section .text._memset,"ax",@progbits
; void *memset(void *s, int c, size_t n)
; sdcccall(1): s=HL, c=E (truncated to byte), n=stack (2 bytes)
; Callee cleanup: pop n before returning.
	.globl	_memset
_memset:
	pop	iy		; save return address in IY
	pop	bc		; n (callee-cleanup the stack arg)
	; HL=s, E=c (fill byte), BC=n
	ld	a, b
	or	c
	jr	z, .Lmemset_done
	ld	(hl), e		; store first byte
	dec	bc
	ld	a, b
	or	c
	jr	z, .Lmemset_done
	ld	d, h
	ld	e, l
	inc	de		; DE = s+1
	ldir			; fill rest
.Lmemset_done:
	jp	(iy)		; return via IY (stack is clean)

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

	.section .text._memmove,"ax",@progbits
; void *memmove(void *dest, const void *src, size_t n)
; sdcccall(1): dest=HL, src=DE, n=stack (2 bytes)
; Handles overlapping regions: uses LDDR when dest > src.
	.globl	_memmove
_memmove:
	pop	iy		; save return address
	pop	bc		; n
	; HL=dest, DE=src, BC=n
	ld	a, b
	or	c
	jr	z, .Lmemmove_done
	; Compare dest vs src to choose direction
	push	hl		; save dest for return
	ld	a, h
	cp	d
	jr	c, .Lmemmove_fwd	; dest < src: forward (LDIR)
	jr	nz, .Lmemmove_bwd	; dest > src: backward (LDDR)
	ld	a, l
	cp	e
	jr	c, .Lmemmove_fwd	; dest < src: forward
	jr	z, .Lmemmove_ret	; dest == src: no-op
.Lmemmove_bwd:
	; Backward copy: start from end
	; HL = dest + n - 1, DE = src + n - 1
	add	hl, bc
	dec	hl		; HL = dest + n - 1
	ex	de, hl
	add	hl, bc
	dec	hl		; HL = src + n - 1 (source for LDDR)
	ex	de, hl		; DE = dest + n - 1, HL = src + n - 1
	; Swap: LDDR wants HL=src, DE=dest
	ex	de, hl
	lddr
	jr	.Lmemmove_ret
.Lmemmove_fwd:
	ex	de, hl		; LDIR: HL=src, DE=dest
	ldir
.Lmemmove_ret:
	pop	de		; return original dest in DE
.Lmemmove_done:
	jp	(iy)

	.section .text.__call_iy,"ax",@progbits
; __call_iy — indirect function call via IY register
; Used by the compiler for calls through function pointers.
; IY holds the target address; JP (IY) transfers control.
	.globl	__call_iy
__call_iy:
	jp	(iy)
