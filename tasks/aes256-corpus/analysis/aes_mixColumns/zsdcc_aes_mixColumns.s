; Function aes_mixColumns
; ---------------------------------
_aes_mixColumns:
	push	ix
	ld	ix,0
	add	ix,sp
	ld	hl, -11
	add	hl, sp
	ld	sp, hl
	ld	(ix-11),0x00
l_aes_mixColumns_00102:
	ld	a,(ix+4)
	add	a,(ix-11)
	ld	e, a
	ld	a,(ix+5)
	adc	a,0x00
	ld	d, a
	ld	a, (de)
	ld	(ix-10),a
	ld	c,a
	ld	b,(ix-11)
	ld	a, b
	inc	a
	add	a,(ix+4)
	ld	(ix-9),a
	ld	a,0x00
	adc	a,(ix+5)
	ld	l,(ix-9)
	ld	(ix-8),a
	ld	h,a
	ld	a, (hl)
	ld	(ix-7),a
	ld	a, b
	add	a,0x02
	add	a,(ix+4)
	ld	(ix-6),a
	ld	a,0x00
	adc	a,(ix+5)
	ld	l,(ix-6)
	ld	(ix-5),a
	ld	h,a
	ld	a, (hl)
	ld	(ix-4),a
	ld	a, b
	add	a,0x02+1
	add	a,(ix+4)
	ld	(ix-3),a
	ld	a,0x00
	adc	a,(ix+5)
	ld	l,(ix-3)
	ld	(ix-2),a
	ld	h,a
	ld	a, (hl)
	ld	(ix-1),a
	ld	a,(ix-10)
	xor	a,(ix-7)
	ld	h,a
	xor	a,(ix-4)
	xor	a,(ix-1)
	ld	b, a
	push	bc
	push	de
	push	hl
	inc	sp
	call	_rj_xtime
	pop	de
	pop	bc
	xor	a, b
	xor	a, c
	ld	(de), a
	pop	de
	pop	hl
	ld	c,(hl)
	push	hl
	push	de
	ld	a,(ix-7)
	xor	a,(ix-4)
	push	bc
	push	af
	inc	sp
	call	_rj_xtime
	pop	bc
	xor	a, b
	xor	a, c
	pop	de
	pop	hl
	push	hl
	push	de
	ld	(hl), a
	ld	l,(ix-6)
	ld	h,(ix-5)
	ld	c, (hl)
	ld	a,(ix-4)
	xor	a,(ix-1)
	push	bc
	push	af
	inc	sp
	call	_rj_xtime
	pop	bc
	xor	a, b
	xor	a, c
	ld	l,(ix-6)
	ld	h,(ix-5)
	ld	(hl), a
	ld	l,(ix-3)
	ld	h,(ix-2)
	ld	c, (hl)
	ld	a,(ix-1)
	xor	a,(ix-10)
	push	bc
	push	af
	inc	sp
	call	_rj_xtime
	pop	bc
	xor	a, b
	xor	a, c
	ld	l,(ix-3)
	ld	h,(ix-2)
	ld	(hl), a
	ld	a,(ix-11)
	add	a,0x04
	ld	(ix-11),a
	sub	a,0x10
	jp	C, l_aes_mixColumns_00102
	ld	sp, ix
	pop	ix
	pop	hl
	pop	af
	jp	(hl)
