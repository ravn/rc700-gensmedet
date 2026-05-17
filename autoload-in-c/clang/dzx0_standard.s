; ZX0 v1 "Standard" decoder by Einar Saukas (68 B) + reloc wrapper.
;
; Source: z88dk libsrc/compress/zx0/z80/dzx0_standard.asm,
;         also verbatim in cpnos-in-asm/src/prom1.asm.
;
; The compressed .text payload (incbin'd in clang/text_compressed.s)
; is at __text_zx0_start in ROM; _reloc_zx0 loads HL/DE and falls
; through to dzx0_standard, which decompresses into RAM at __code_start.
;
; Clobbers: AF, BC, DE, HL, AF'.  Uses stack (push/pop, ex (sp),hl).

	.section .zx0_decoder,"ax",@progbits

	.globl	_reloc_zx0
_reloc_zx0:
	ld	hl, __text_zx0_start
	ld	de, __code_start
	; fall through into dzx0_standard

	.globl	dzx0_standard
dzx0_standard:
	ld	bc, 0xFFFF		; preserve default offset 1
	push	bc
	inc	bc
	ld	a, 0x80
dzx0s_literals:
	call	dzx0s_elias		; obtain length
	ldir				; copy literals
	add	a, a			; copy-from-last-offset or new-offset?
	jr	c, dzx0s_new_offset
	call	dzx0s_elias		; obtain length
dzx0s_copy:
	ex	(sp), hl		; preserve source, restore offset
	push	hl			; preserve offset
	add	hl, de			; calculate destination - offset
	ldir				; copy from offset
	pop	hl			; restore offset
	ex	(sp), hl		; preserve offset, restore source
	add	a, a			; copy-from-literals or new-offset?
	jr	nc, dzx0s_literals
dzx0s_new_offset:
	call	dzx0s_elias		; obtain offset MSB
	ex	af, af'
	pop	af			; discard last offset
	xor	a			; adjust for negative offset
	sub	c
	ret	z			; check end marker
	ld	b, a
	ex	af, af'
	ld	c, (hl)			; obtain offset LSB
	inc	hl
	rr	b			; last offset bit becomes first length bit
	rr	c
	push	bc			; preserve new offset
	ld	bc, 1			; obtain length
	call	nc, dzx0s_elias_backtrack
	inc	bc
	jr	dzx0s_copy
dzx0s_elias:
	inc	c			; interlaced Elias gamma coding
dzx0s_elias_loop:
	add	a, a
	jr	nz, dzx0s_elias_skip
	ld	a, (hl)			; load another group of 8 bits
	inc	hl
	rla
dzx0s_elias_skip:
	ret	c
dzx0s_elias_backtrack:
	add	a, a
	rl	c
	rl	b
	jr	dzx0s_elias_loop
