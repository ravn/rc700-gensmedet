_rj_sb_inv:
	call	___sdcc_enter_ix
	ld	a,(ix+4)
	xor	a,0x63
	rlca
	ld	l, a
	ld	h, l
	add	hl, hl
	add	hl, hl
	xor	a, h
	ld	c, a
	ld	a, h
	rlca
	rlca
	rlca
	xor	a, c
	push	af
	inc	sp
	call	_gf_mulinv
	pop	ix
	pop	hl
	inc	sp
	jp	(hl)
;	---------------------------------
; Function rj_xtime
; ---------------------------------
