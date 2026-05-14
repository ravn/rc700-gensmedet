; Function mc_loop
; ---------------------------------
_mc_loop:
	push	ix
	ld	ix,0
	add	ix,sp
	ld	c, l
	ld	b, h
	ld	hl, -15
	add	hl, sp
	ld	sp, hl
	ld	e,c
	ld	d,b
	ld	c,0x00
l_mc_loop_00102:
	ld	a, e
	add	a, c
	ld	(ix-15),a
	ld	a, d
	adc	a,0x00
	ld	(ix-14),a
	pop	hl
	ld	a,(hl)
	push	hl
	ld	(ix-13),a
	ld	b, c
	ld	a, b
	inc	a
	add	a, e
	ld	(ix-12),a
	ld	l,a
	ld	a,0x00
	adc	a,d
	ld	(ix-11),a
	ld	h,a
	ld	a, (hl)
	ld	(ix-10),a
	ld	a, b
	add	a,0x02
	add	a, e
	ld	(ix-9),a
	ld	l,a
	ld	a,0x00
	adc	a,d
	ld	(ix-8),a
	ld	h,a
	ld	a, (hl)
	ld	(ix-7),a
	ld	a, b
	add	a,0x02+1
	add	a, e
	ld	(ix-6),a
	ld	l,a
	ld	a,0x00
	adc	a,d
	ld	(ix-5),a
	ld	h,a
	ld	a, (hl)
	ld	(ix-4),a
	ld	a,(ix-13)
	xor	a,(ix-10)
	ld	(ix-3),a
	xor	a,(ix-7)
	xor	a,(ix-4)
	ld	b, a
	push	bc
	push	de
	ld	a, b
	call	_f
	ld	l, a
	pop	de
	pop	bc
	ld	a, l
	xor	a,(ix-13)
	xor	a,(ix-7)
	push	hl
	push	bc
	push	de
	call	_f
	call	_f
	pop	de
	pop	bc
	pop	hl
	xor	a, b
	ld	(ix-2),a
	ld	a, l
	xor	a,(ix-10)
	xor	a,(ix-4)
	push	bc
	push	de
	call	_f
	call	_f
	pop	de
	pop	bc
	xor	a, b
	ld	(ix-1),a
	pop	hl
	ld	b,(hl)
	push	hl
	push	bc
	push	de
	ld	a,(ix-3)
	call	_f
	pop	de
	pop	bc
	xor	a,(ix-2)
	xor	a, b
	pop	hl
	push	hl
	ld	(hl), a
	ld	l,(ix-12)
	ld	h,(ix-11)
	ld	b, (hl)
	ld	a,(ix-10)
	xor	a,(ix-7)
	push	bc
	push	de
	call	_f
	pop	de
	pop	bc
	xor	a,(ix-1)
	xor	a, b
	ld	l,(ix-12)
	ld	h,(ix-11)
	ld	(hl), a
	ld	l,(ix-9)
	ld	h,(ix-8)
	ld	b, (hl)
	ld	a,(ix-7)
	xor	a,(ix-4)
	push	bc
	push	de
	call	_f
	pop	de
	pop	bc
	xor	a,(ix-2)
	xor	a, b
	ld	l,(ix-9)
	ld	h,(ix-8)
	ld	(hl), a
	ld	l,(ix-6)
	ld	h,(ix-5)
	ld	b, (hl)
	ld	a,(ix-4)
	xor	a,(ix-13)
	push	bc
	push	de
	call	_f
	pop	de
	pop	bc
	xor	a,(ix-1)
	xor	a, b
	ld	l,(ix-6)
	ld	h,(ix-5)
	ld	(hl), a
	ld	a, c
	add	a,0x04
	ld	c,a
	sub	a,0x10
	jp	C, l_mc_loop_00102
	ld	sp, ix
	pop	ix
	ret
	SECTION IGNORE
