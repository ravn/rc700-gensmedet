; Function aes_shiftRows
; ---------------------------------
_aes_shiftRows:
	push	ix
	ld	ix,0
	add	ix,sp
	ld	l,(ix+4)
	ld	h,(ix+5)
	inc	hl
	ld	c, (hl)
	ld	a,(ix+4)
	add	a,0x05
	ld	e, a
	ld	a,(ix+5)
	adc	a,0x00
	ld	d, a
	ld	a, (de)
	ld	(hl), a
	ld	a,(ix+4)
	add	a,0x09
	ld	l, a
	ld	a,(ix+5)
	adc	a,0x00
	ld	h, a
	ld	a, (hl)
	ld	(de), a
	ld	a,(ix+4)
	add	a,0x0d
	ld	e, a
	ld	a,(ix+5)
	adc	a,0x00
	ld	d, a
	ld	a, (de)
	ld	(hl), a
	ld	a, c
	ld	(de), a
	ld	l,(ix+4)
	ld	h,(ix+5)
	ld	de,0x000a
	add	hl, de
	ld	c, (hl)
	ld	e,(ix+4)
	ld	d,(ix+5)
	inc	de
	inc	de
	ld	a, (de)
	ld	(hl), a
	ld	a, c
	ld	(de), a
	ld	l,(ix+4)
	ld	h,(ix+5)
	inc	hl
	inc	hl
	inc	hl
	ld	c, (hl)
	ld	a,(ix+4)
	add	a,0x0f
	ld	e, a
	ld	a,(ix+5)
	adc	a,0x00
	ld	d, a
	ld	a, (de)
	ld	(hl), a
	ld	a,(ix+4)
	add	a,0x0b
	ld	l, a
	ld	a,(ix+5)
	adc	a,0x00
	ld	h, a
	ld	a, (hl)
	ld	(de), a
	ld	a,(ix+4)
	add	a,0x07
	ld	e, a
	ld	a,(ix+5)
	adc	a,0x00
	ld	d, a
	ld	a, (de)
	ld	(hl), a
	ld	a, c
	ld	(de), a
	ld	l,(ix+4)
	ld	h,(ix+5)
	ld	de,0x000e
	add	hl, de
	ld	c, (hl)
	ld	a,(ix+4)
	add	a,0x06
	ld	e, a
	ld	a,(ix+5)
	adc	a,0x00
	ld	d, a
	ld	a, (de)
	ld	(hl), a
	ld	a, c
	ld	(de), a
	pop	ix
	pop	hl
	pop	af
	jp	(hl)
;	---------------------------------
