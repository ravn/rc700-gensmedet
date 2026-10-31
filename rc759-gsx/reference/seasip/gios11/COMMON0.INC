		

		jmp	entry

ds_addr		dw	0			; DATA XREF: cseg:0011r cseg:002Cw

caller_ss	equ	(word ptr (2))[bp]
caller_sp	equ	(word ptr (0))[bp]

entry:					; CODE XREF: cseg:0000j
		push	bp
		pushf	
		pop	bp
		push	bp
		push	es
		push	ds
		mov	si, dx		; Parameter
		push	si
		mov	bx, offset gsx_mcb?; Memory required in	paras?
		mov	dx, cs:ds_addr
		mov	es, dx
		or	dx, dx
		jnz	ds_exists	; So, DS doesn't exist...
		push	bx
		and	ch, 0F0h	; Get driver data table
		or	ch, 6
		int	0E0h		; Get driver DSEG address
		mov	dx, es:5[bx]
		mov	es, dx		; Segment allocated
	
		pop	bx
		mov	cs:ds_addr, dx
		mov	di, es:_lbss
		mov	cx, es:_bsslen
		add	es:2[bx], di
		add	es:2[bx], cx
		sub	al, al
		cld	
		rep stosb
	

ds_exists:				; CODE XREF: cseg:001Aj
		mov	cx, ss
		mov	di, sp		;Caller SP
		mov	ax, es:.6
		inc	ax
		and	al, 0FEh
		cli	
		mov	ss, dx
		mov	sp, ax
		push	bp
		popf	
		push	cx		;bp+2
		push	di		;bp+0
		mov	bp, sp
		mov	di, offset p_contrl
		mov	cx, 0Ah
		cld	
		rep movsw
		mov	ds, dx
		call	SCREEN
		mov	sp, bp
		jmps	gsxret


no_memory:				; CODE XREF: __csv+Fj
		mov	cl, 9
		mov	dx, offset aNoMemory
		int	0E0h		; used by BASIC	while in interpreter
		mov	ax, 8000h
		mov	bl, numeric_error
		or	bl, bl
		jz	gsxret
		js	show_numerr
		or	ax, ax
		jz	gsxret

show_numerr:				; CODE XREF: cseg:0082j
		push	ax

show_numerr1:				; CODE XREF: cseg:00B4j
		mov	dx, caller_ss
		mov	si, 4
		lea	bx, numeric_error

show_numerr2:				; CODE XREF: cseg:00A4j
		mov	al, dl
		mov	cl, 4
		shr	dx, cl
		and	al, 0Fh
		add	al, 90h
		daa	
		adc	al, 40h
		daa	
		dec	si
		mov	[bx+si], al
		jnz	show_numerr2
		mov	dx, bx
		mov	cl, 9
		int	0E0h		; used by BASIC	while in interpreter
		cmp	caller_sp, bp
		jbe	gsxret1
		mov	bp, caller_sp
		jmps	show_numerr1


gsxret1:				; CODE XREF: cseg:00AFj
		pop	ax

gsxret:					; CODE XREF: cseg:006Ej cseg:0080j
					; ...
		pop	di
		pop	cx
		cli	
		mov	ss, cx
		mov	sp, di
		pop	dx
		pop	ds
		pop	es
	
		popf	
		pop	bp
		retf	



;		S u b r	o u t i	n e

__csv0:		; CODE XREF: _absp _clampp ...
		pop	si
		xor	ax, ax
		jmps	__csv1




;		S u b r	o u t i	n e
; Attributes: noreturn

__csv:		; CODE XREF: SCREENp draw_markerp
					; ...
		pop	si
		cld	
		lods	cs:byte ptr [si]
		mov	ah, 0

__csv1:					; CODE XREF: __csv0+3j	cseg:00E0j
		push	bp
		mov	bp, sp
		sub	sp, ax
		cmp	sp, stack_base
		jbe	no_memory
		jmp	si


		pop	si
		cld	
		lods	cs:word ptr [si]
		jmps	__csv1



read_index	equ	(word ptr (4))[bp]

;		S u b r	o u t i	n e

_read_contrl:		; CODE XREF: SCREEN+14p v_esc+4p
					; ...
		push	bp
		mov	bp, sp
		push	es
		push	si
		les	si, dword ptr p_contrl
		mov	bx, read_index
		shl	bx, 1
		mov	ax, es:[bx+si]
		pop	si
		pop	es
		pop	bp
		retn	





;		S u b r	o u t i	n e

_read_intin:		; CODE XREF: v_opnwk+92p v_opnwk+C7p
					; ...
		push	bp
		mov	bp, sp
		push	es
		push	si
		les	si, dword ptr p_intin
		mov	bx, read_index
		shl	bx, 1
		mov	ax, es:[bx+si]
		pop	si
		pop	es
		pop	bp
		retn	





;		S u b r	o u t i	n e

_read_ptsin:		; CODE XREF: v_pline+33p v_pline+41p
					; ...
		push	bp
		mov	bp, sp
		push	es
		push	si
		les	si, dword ptr p_ptsin
		mov	bx, read_index
		shl	bx, 1
		mov	ax, es:[bx+si]
		pop	si
		pop	es
		pop	bp
		retn	




write_value	equ	(word ptr (6))[bp]
write_index	equ	(word ptr (4))[bp]

;		S u b r	o u t i	n e

_write_contrl:		; CODE XREF: SCREEN+Bp	v_opnwk+8p
					; ...
		push	bp
		mov	bp, sp
		push	es
		push	si
		les	si, dword ptr p_contrl
		mov	bx, write_index
		shl	bx, 1
		mov	ax, write_value
		mov	es:[bx+si], ax
		pop	si
		pop	es
		pop	bp
		retn	





;		S u b r	o u t i	n e

_write_intout:		; CODE XREF: v_opnwk+43p _vq_chcells+7p
					; ...
		push	bp
		mov	bp, sp
		push	es
		push	si
		les	si, dword ptr p_intout
		mov	bx, write_index
		shl	bx, 1
		mov	ax, write_value
		mov	es:[bx+si], ax
		pop	si
		pop	es
		pop	bp
		retn	





;		S u b r	o u t i	n e

_write_ptsout:		; CODE XREF: v_opnwk+7Cp vst_height+92p
					; ...
		push	bp
		mov	bp, sp
		push	es
		push	si
		les	si, dword ptr p_ptsout
		mov	bx, write_index
		shl	bx, 1
		mov	ax, write_value
		mov	es:[bx+si], ax
		pop	si
		pop	es
		pop	bp
		retn	



scr_func	equ	(word ptr (-76))[bp]

;		S u b r	o u t i	n e

SCREEN:		; CODE XREF: cseg:0069p
		call	__csv

		db	4Eh

		xor	ax, ax
		push	ax
		mov	ax, 2
		push	ax
		call	_write_contrl
		add	sp, 4
		xor	ax, ax
		push	ax
		call	_read_contrl
		inc	sp
		inc	sp
		mov	scr_func, ax
		mov	ax, scr_func
		push	ax
		jmp	scr_switch



owk_rgb		equ	(word ptr (-72))[bp]
owk_count	equ	(word ptr (-74))[bp]
owk_source	equ	(word ptr (-78))[bp]

;		S u b r	o u t i	n e

v_opnwk:
		mov	ax, 6
		push	ax
		mov	ax, 2
		push	ax
		call	_write_contrl	; 6 points out
		add	sp, 4
		mov	ax, 45
		push	ax
		mov	ax, 4
		push	ax
		call	_write_contrl	; 45 ints out
		add	sp, 4
		lea	ax, DEV_TAB
		mov	owk_source, ax	; Source
		xor	ax, ax
		mov	owk_count, ax	; Count

cpy_dev_tab:				; CODE XREF: v_opnwk+52j
		mov	ax, owk_count
		cmp	ax, 45
		jl	cpy_dev_tab1
		jmp	cpy_siz_tab


cpy_dev_tab1:				; CODE XREF: v_opnwk+2Ej
		lea	si, owk_source
		mov	ax, [si]
;;;		add	word ptr [si], 2
		ADDPSI	2
;;;		mov	si, ax
		MOVSIAX
		push	word ptr [si]
		push	word ptr owk_count
		call	_write_intout
		add	sp, 4
		lea	si, owk_count
		mov	ax, [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		jmp	cpy_dev_tab


cpy_siz_tab:				; CODE XREF: v_opnwk+30j
		lea	ax, SIZ_TAB
		mov	owk_source, ax
		xor	ax, ax
		mov	owk_count, ax

cpy_siz_tab1:				; CODE XREF: v_opnwk+8Bj
		mov	ax, owk_count
		cmp	ax, 0Ch
		jl	cpy_siz_tab2
		jmp	init_types


cpy_siz_tab2:				; CODE XREF: v_opnwk+67j
		lea	si, owk_source
		mov	ax, [si]
;;;		add	word ptr [si], 2
		ADDPSI	2
;;;		mov	si, ax
		MOVSIAX
		push	word ptr [si]
		push	word ptr owk_count
		call	_write_ptsout
		add	sp, 4
		lea	si, owk_count
		mov	ax, [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		jmp	cpy_siz_tab1


init_types:				; CODE XREF: v_opnwk+69j
		mov	ax, 1
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
;;;		mov	line_type, ax
;;;		mov	ax, line_type
		SAXW	line_type
		LAXW	line_type

		cmp	ax, 1
		jl	init_types1
		jmps	init_types2


init_types1:				; CODE XREF: v_opnwk+A2j
		jmp	init_types3


init_types2:				; CODE XREF: v_opnwk+A4j
;;;		mov	ax, line_type
		LAXW	line_type
		cmp	ax, 7
		jg	init_types3
		jmp	init_types4


init_types3:				; CODE XREF: v_opnwk+A6j v_opnwk+B0j
		mov	ax, 1
;;;		mov	line_type, ax	
		SAXW	line_type

init_types4:				; CODE XREF: v_opnwk+B2j
		mov	ax, NUM_COLORS - 1
		push	ax
		xor	ax, ax
		push	ax
		mov	ax, 2
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
		push	ax
		call	_clamp
		add	sp, 6
;;;		mov	line_colour, ax
		SAXW	line_colour
		mov	ax, 3
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
;;;		mov	marker_type, ax
;;;		mov	ax, marker_type
		SAXW	marker_type
		LAXW	marker_type
		cmp	ax, 1
		jl	init_types5
		jmps	init_types6


init_types5:				; CODE XREF: v_opnwk+EBj
		jmp	init_types7


init_types6:				; CODE XREF: v_opnwk+EDj
;;;		mov	ax, marker_type
		LAXW	marker_type
		cmp	ax, 5
		jg	init_types7
		jmp	init_types8


init_types7:				; CODE XREF: v_opnwk+EFj v_opnwk+F9j
		mov	ax, 3
;;;		mov	marker_type, ax
		SAXW	marker_type
init_types8:				; CODE XREF: v_opnwk+FBj
		mov	ax, NUM_COLORS - 1
		push	ax
		xor	ax, ax
		push	ax
		mov	ax, 4
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
		push	ax
		call	_clamp
		add	sp, 6
;;;		mov	mark_colour, ax
		SAXW	mark_colour
		mov	ax, NUM_COLORS - 1
		push	ax
		xor	ax, ax
		push	ax
		mov	ax, 6
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
		push	ax
		call	_clamp
		add	sp, 6
;;;		mov	text_colour, ax
		SAXW	text_colour
		mov	ax, 7
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
;;;		mov	fill_style, ax
;;;		mov	ax, fill_style
		SAXW	fill_style
		LAXW	fill_style
		cmp	ax, 0
		jl	init_types9
		jmps	init_types10


init_types9:				; CODE XREF: v_opnwk+14Fj
		jmp	init_types11


init_types10:				; CODE XREF: v_opnwk+151j
;;;		mov	ax, fill_style
		LAXW	fill_style
		cmp	ax, 3
		jg	init_types11
		jmp	init_types12


init_types11:				; CODE XREF: v_opnwk+153j v_opnwk+15Dj
		xor	ax, ax
;;;		mov	fill_style, ax
		SAXW	fill_style

init_types12:				; CODE XREF: v_opnwk+15Fj
;;;		mov	ax, fill_style
		LAXW	fill_style
		cmp	ax, 3
		jz	init_types13
		jmp	init_types14


init_types13:				; CODE XREF: v_opnwk+16Fj
		mov	ax, 2
;;;		mov	fill_style, ax
		SAXW	fill_style

init_types14:				; CODE XREF: v_opnwk+171j
		mov	ax, 8
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
;;;		mov	fill_interior, ax
;;;		mov	ax, fill_interior
		SAXW	fill_interior
		LAXW	fill_interior
		cmp	ax, 1
		jl	init_types15
		jmps	init_types16


init_types15:				; CODE XREF: v_opnwk+18Fj
		jmp	init_types17


init_types16:				; CODE XREF: v_opnwk+191j
;;;		mov	ax, fill_interior
		LAXW	fill_interior
		cmp	ax, 5
		jg	init_types17
		jmp	init_types18


init_types17:				; CODE XREF: v_opnwk+193j v_opnwk+19Dj
		mov	ax, 1
;;;		mov	fill_interior, ax
		SAXW	fill_interior

init_types18:				; CODE XREF: v_opnwk+19Fj
		mov	ax, NUM_COLORS - 1
		push	ax
		xor	ax, ax
		push	ax
		mov	ax, 9
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
		push	ax
		call	_clamp
		add	sp, 6
;;;		mov	fill_colour, ax
		SAXW	fill_colour

		if	NUM_COLORS eq 2

		lea	si, palette
		xor	ax, ax
		mov	[si], ax
		lea	si, palette+4
		xor	ax, ax
		mov	[si], ax
		lea	si, palette+8
		xor	ax, ax
		mov	[si], ax
		lea	si, palette+2
		mov	ax, 1000
		mov	[si], ax
		lea	si, palette+6
		mov	ax, 1000
		mov	[si], ax
		lea	si, palette+0Ah
		mov	ax, 1000
		mov	[si], ax

		else	; NUM_COLORS != 2

		xor	ax, ax
		mov	owk_count, ax
init_pal1:	mov	ax, owk_count
		cmp	ax, NUM_COLORS - 1
		jle	init_pal2
		jmp	init_pal3
;
init_pal2:	mov	ax, owk_count
		shl	ax, 1
		push	ax
		lea	si, initreds
		pop	ax
		add	si, ax
		push	word ptr [si]
		pop	ax
		mov	owk_rgb, ax	;Red value
		mov	ax, owk_count
		shl	ax, 1
		push	ax
		lea	si, palette
		pop	ax
		add	si, ax
		mov	ax, owk_rgb	;Red value
		mov	[si], ax
		mov	ax, owk_count
		shl	ax, 1
		push	ax
		lea	si, palette + 6*NUM_COLORS
		pop	ax
		add	si, ax
		mov	ax, owk_rgb	;Red value
		mov	[si], ax
;
; And now go through the whole malarkey again with green and blue
;
		mov	ax, owk_count
		shl	ax, 1
		push	ax
		lea	si, initgreens
		pop	ax
		add	si, ax
		push	word ptr [si]
		pop	ax
		mov	owk_rgb, ax	;Red value
		mov	ax, owk_count
		shl	ax, 1
		push	ax
		lea	si, palette + 2 * NUM_COLORS
		pop	ax
		add	si, ax
		mov	ax, owk_rgb	;Green value
		mov	[si], ax
		mov	ax, owk_count
		shl	ax, 1
		push	ax
		lea	si, palette + 8 * NUM_COLORS
		pop	ax
		add	si, ax
		mov	ax, owk_rgb	;Green value
		mov	[si], ax
	
		mov	ax, owk_count
		shl	ax, 1
		push	ax
		lea	si, initblues
		pop	ax
		add	si, ax
		push	word ptr [si]
		pop	ax
		mov	owk_rgb, ax	;Blue value
		mov	ax, owk_count
		shl	ax, 1
		push	ax
		lea	si, palette + 4 * NUM_COLORS
		pop	ax
		add	si, ax
		mov	ax, owk_rgb	;Green value
		mov	[si], ax
		mov	ax, owk_count
		shl	ax, 1
		push	ax
		lea	si, palette + 16 + 6*NUM_COLORS
		pop	ax
		add	si, ax
		mov	ax, owk_rgb	;Green value
		mov	[si], ax
		lea	si, owk_count
		mov	ax, [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		jmp	init_pal1

		endif


init_pal3:	xor	ax, ax
;;;		mov	text_direction,	ax
		SAXW	text_direction
		mov	ax, 1
;;;		mov	text_height, ax
		SAXW	text_height
		mov	ax, 1
;;;		mov	unknown1, ax
		SAXW	unknown1
		mov	ax, 1
;;;		mov	unknown2, ax
		SAXW	unknown2
		mov	ax, 1
;;;		mov	unknown4, ax
		SAXW	unknown4
		mov	ax, 1
;;;		mov	write_mode, ax
		SAXW	write_mode
		lea	ax, init_scr
		push	ax
		mov	ax, 90
		push	ax
		call	_putstr		; (char	*p, unsigned len)
		add	sp, 4
		if	TWOHEAD
		 call	CLEARMEM
		 call	_cleartext
		 jmp	v_nop

		else
		 mov	ax, 1
		 push	ax
		 call	_GFXMODE	; Enter	with 1 for graphics, 0 for text
		 inc	sp
		 inc	sp
		 call	CLEARMEM
		 jmp	v_nop
		endif





;		S u b r	o u t i	n e

		if	TWOHEAD
v_clswk:
		 jmp	v_nop	

v_clrwk:	 call	CLEARMEM
		 call	_cleartext
		 jmp	v_nop
		else
v_clswk:
		 xor	ax, ax
		 push	ax
		 call	_GFXMODE	; Enter	with 1 for graphics, 0 for text
		 inc	sp
		 inc	sp
		 jmp	v_nop

v_clrwk:
		call	CLEARMEM
		jmp	v_nop


		endif


;		S u b r	o u t i	n e

v_updwk:
		jmp	v_nop





;		S u b r	o u t i	n e

v_esc:
		mov	ax, 5
		push	ax
		call	_read_contrl
		inc	sp
		inc	sp
		mov	scr_func, ax
		mov	ax, scr_func
		push	ax
		jmp	v_escapes





;		S u b r	o u t i	n e

vq_chcells:
		mov	ax, 24
		push	ax
		xor	ax, ax
		push	ax
		call	_write_intout
		add	sp, 4
		mov	ax, 80
		push	ax
		mov	ax, 1
		push	ax
		call	_write_intout
		add	sp, 4
		jmp	v_endesc





;		S u b r	o u t i	n e

v_enter_cur:
		if	TWOHEAD
		 call	CLEARMEM
		else
		 xor	ax, ax
		 push	ax
		 call	_GFXMODE	; Enter	with 1 for graphics, 0 for text
		 inc	sp
		 inc	sp
		endif
		call	_cleartext
		lea	ax, esc_h
		push	ax
		mov	ax, 2
		push	ax
		call	_putstr		; (char	*p, unsigned len)
		add	sp, 4
		mov	ax, 1
;;;		mov	text_cury, ax
		SAXW	text_cury
		mov	ax, 1
;;;		mov	text_curx, ax
		SAXW	text_curx
		jmp	v_endesc





;		S u b r	o u t i	n e

v_exit_cur:
		if	TWOHEAD
		 call	_cleartext
		else
		 mov	ax, 1
		 push	ax
		 call	_GFXMODE	; Enter	with 1 for graphics, 0 for text
		 inc	sp
		 inc	sp
		endif
		call	CLEARMEM
		jmp	v_endesc





;		S u b r	o u t i	n e

v_curup:
		mov	ax, 18h
		push	ax
		mov	ax, 1
		push	ax
		lea	si, text_cury
;;;		add	word ptr [si], 1
		ADDPSI	1
		push	word ptr [si]
		call	_clamp
		add	sp, 6
;;;		mov	text_cury, ax
		SAXW	text_cury
		lea	ax, esc_a
		push	ax
		mov	ax, 2
		push	ax
		call	_putstr		; (char	*p, unsigned len)
		add	sp, 4
		jmp	v_endesc





;		S u b r	o u t i	n e

v_curdown:
		mov	ax, 18h
		push	ax
		mov	ax, 1
		push	ax
		lea	si, text_cury
;;;		sub	word ptr [si], 1
		SUBPSI	1
		push	word ptr [si]
		call	_clamp
		add	sp, 6
;;;		mov	text_cury, ax
		SAXW	text_cury
		lea	ax, esc_b
		push	ax
		mov	ax, 2
		push	ax
		call	_putstr		; (char	*p, unsigned len)
		add	sp, 4
		jmp	v_endesc





;		S u b r	o u t i	n e

v_curright:
		mov	ax, 80
		push	ax
		mov	ax, 1
		push	ax
		lea	si, text_curx
;;;		add	word ptr [si], 1
		ADDPSI	1
		push	word ptr [si]
		call	_clamp
		add	sp, 6
;;;		mov	text_curx, ax
		SAXW	text_curx
		lea	ax, esc_c
		push	ax
		mov	ax, 2
		push	ax
		call	_putstr		; (char	*p, unsigned len)
		add	sp, 4
		jmp	v_endesc





;		S u b r	o u t i	n e

v_curleft:
		mov	ax, 50h
		push	ax
		mov	ax, 1
		push	ax
		lea	si, text_curx
;;;		sub	word ptr [si], 1
		SUBPSI	1
		push	word ptr [si]
		call	_clamp
		add	sp, 6
;;;		mov	text_curx, ax
		SAXW	text_curx
		lea	ax, esc_d
		push	ax
		mov	ax, 2
		push	ax
		call	_putstr		; (char	*p, unsigned len)
		add	sp, 4
		jmp	v_endesc





;		S u b r	o u t i	n e

v_curhome:
		lea	ax, esc_h
		push	ax
		mov	ax, 2
		push	ax
		call	_putstr		; (char	*p, unsigned len)
		add	sp, 4
		mov	ax, 1
;;;		mov	text_cury, ax
		SAXW	text_cury
		mov	ax, 1
;;;		mov	text_curx, ax
		SAXW	text_curx
		jmp	v_endesc



eeos_row	equ	(word ptr (-74))[bp]

;		S u b r	o u t i	n e

v_eeos:
		lea	ax, esc_k
		push	ax
		mov	ax, 2
		push	ax
		call	_putstr		; (char	*p, unsigned len)
		add	sp, 4
;;;		mov	ax, text_cury
		LAXW	text_cury
		cmp	ax, 23
		jle	v_eeos1
		jmp	v_eeos_end


v_eeos1:				; CODE XREF: v_eeos+16j
		lea	ax, esc_y
		push	ax
		mov	ax, 2
		push	ax
		call	_putstr		; (char	*p, unsigned len)
		add	sp, 4
;;;		mov	ax, text_cury
;;;		add	ax, 1Fh
		LAXW	text_cury
		ADDAXW	1Fh
		push	ax
		call	_putchar
		inc	sp
		inc	sp
		mov	ax, 20h
		push	ax
		call	_putchar
		inc	sp
		inc	sp
;;;		mov	ax, text_cury
;;;		add	ax, 1
		LAXW	text_cury
		ADDAXW	1
		mov	eeos_row, ax

v_eeos2:				; CODE XREF: v_eeos+7Ej
		mov	ax, eeos_row
		cmp	ax, 18h
		jle	v_eeos3
		jmp	v_eeos4


v_eeos3:				; CODE XREF: v_eeos+52j
		lea	ax, esc_b
		push	ax
		mov	ax, 2
		push	ax
		call	_putstr		; (char	*p, unsigned len)
		add	sp, 4
		lea	ax, esc_k
		push	ax
		mov	ax, 2
		push	ax
		call	_putstr		; (char	*p, unsigned len)
		add	sp, 4
		lea	si, eeos_row
		mov	ax, [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		jmp	v_eeos2


v_eeos4:				; CODE XREF: v_eeos+54j
		lea	ax, esc_y
		push	ax
		mov	ax, 2
		push	ax
		call	_putstr		; (char	*p, unsigned len)
		add	sp, 4
;;;		mov	ax, text_cury
;;;		add	ax, 1Fh
		LAXW	text_cury
		ADDAXW	1Fh
		push	ax
		call	_putchar
		inc	sp
		inc	sp
;;;		mov	ax, text_curx
;;;		add	ax, 1Fh
		LAXW	text_curx
		ADDAXW	1Fh
		push	ax
		call	_putchar
		inc	sp
		inc	sp

v_eeos_end:				; CODE XREF: v_eeos+18j
		jmp	v_endesc





;		S u b r	o u t i	n e

v_eeol:
		lea	ax, esc_k
		push	ax
		mov	ax, 2
		push	ax
		call	_putstr		; (char	*p, unsigned len)
		add	sp, 4
		jmp	v_endesc



curaddr_pos	equ	(word ptr (-74))[bp]

;		S u b r	o u t i	n e

vs_curaddress:
		lea	ax, esc_y
		push	ax
		mov	ax, 2
		push	ax
		call	_putstr		; (char	*p, unsigned len)
		add	sp, 4
		mov	ax, 18h
		push	ax
		mov	ax, 1
		push	ax
		xor	ax, ax
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
		push	ax
		call	_clamp
		add	sp, 6
		mov	curaddr_pos, ax
		mov	ax, curaddr_pos
;;;		mov	text_cury, ax
		SAXW	text_cury
		mov	ax, curaddr_pos
;;;		add	ax, 1Fh	
		ADDAXW	1Fh
		push	ax
		call	_putchar
		inc	sp
		inc	sp
		mov	ax, 80
		push	ax
		mov	ax, 1
		push	ax
		mov	ax, 1
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
		push	ax
		call	_clamp
		add	sp, 6
		mov	curaddr_pos, ax
		mov	ax, curaddr_pos
;;;		mov	text_curx, ax
		SAXW	text_curx
		mov	ax, curaddr_pos
;;;		add	ax, 1Fh
		ADDAXW	1Fh
		push	ax
		call	_putchar
		inc	sp
		inc	sp
		jmp	v_endesc



curtext_ch	equ	(byte ptr  (-2))[bp]
curtext_len	equ	(word ptr (-70))[bp]
curtext_pos	equ	(word ptr (-74))[bp]

;		S u b r	o u t i	n e

v_curtext:
		mov	ax, 3
		push	ax
		call	_read_contrl
		inc	sp
		inc	sp
		mov	curtext_len, ax
		xor	ax, ax
		mov	curtext_pos, ax

v_curtext1:				; CODE XREF: v_curtext+3Bj
		mov	ax, curtext_pos
		cmp	ax, curtext_len
		jl	v_curtext2
		jmp	v_curtext3


v_curtext2:				; CODE XREF: v_curtext+17j
		push	word ptr curtext_pos
		call	_read_intin
		inc	sp
		inc	sp
		mov	curtext_ch, al
		mov	al, curtext_ch
		mov	ah, 0
		push	ax
		call	_putchar
		inc	sp
		inc	sp
		lea	si, curtext_pos
		mov	ax, [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		jmp	v_curtext1


v_curtext3:				; CODE XREF: v_curtext+19j
		jmp	v_endesc





;		S u b r	o u t i	n e

v_rvon:
		lea	ax, esc_rvon
		push	ax
		mov	ax, 6
		push	ax
		call	_putstr		; (char	*p, unsigned len)
		add	sp, 4
		jmp	v_endesc





;		S u b r	o u t i	n e

v_rvoff:
		lea	ax, esc_rvoff
		push	ax
		mov	ax, 6
		push	ax
		call	_putstr		; (char	*p, unsigned len)
		add	sp, 4
		jmp	v_endesc





;		S u b r	o u t i	n e

vq_curaddress:
		push	text_cury
		xor	ax, ax
		push	ax
		call	_write_intout
		add	sp, 4
		push	text_curx
		mov	ax, 1
		push	ax
		call	_write_intout
		add	sp, 4
		jmp	v_endesc

		jmp	v_endesc


v_escapes:				; CODE XREF: v_esc+10j
		call	_switch

		dw	0Fh
		dw	0Fh, 0Eh, 0Dh, 0Ch, 0Bh, 0Ah, 9, 8, 7, 6, 5, 4, 2, 3, 1
sw_esctab	dw	offset v_endesc      - offset sw_esctab
		dw	offset vq_curaddress - offset sw_esctab - 2
		dw	offset v_rvoff       - offset sw_esctab - 4
		dw	offset v_rvon        - offset sw_esctab - 6
		dw	offset v_curtext     - offset sw_esctab - 8
		dw	offset vs_curaddress - offset sw_esctab - 0Ah
		dw	offset v_eeol        - offset sw_esctab - 0Ch
		dw	offset v_eeos        - offset sw_esctab - 0Eh
		dw	offset v_curhome     - offset sw_esctab - 10h
		dw	offset v_curleft     - offset sw_esctab - 12h
		dw	offset v_curright    - offset sw_esctab - 14h
		dw	offset v_curdown     - offset sw_esctab - 16h
		dw	offset v_curup       - offset sw_esctab - 18h
		dw	offset v_exit_cur    - offset sw_esctab - 1Ah
		dw	offset v_enter_cur   - offset sw_esctab - 1Ch
		dw	offset vq_chcells    - offset sw_esctab - 1Eh

v_endesc:				; CODE XREF: _vq_chcells+1Bj
					; v_enter_cur+28j ...
		jmp	v_nop



pline_count	equ	(word ptr (-70))[bp]
pline_seg	equ	(word ptr (-74))[bp]

;		S u b r	o u t i	n e

v_pline:
		mov	ax, 1
		push	ax
		mov	ax, 1
		push	ax
		call	_read_contrl
		inc	sp
		inc	sp
;;;		sub	ax, 1
		SUBAXW	1
		pop	cx
		shl	ax, cl
		mov	pline_count, ax
		xor	ax, ax
		mov	pline_seg, ax

v_pline1:				; CODE XREF: v_pline+72j
		mov	ax, pline_seg
		cmp	ax, pline_count
		jl	v_pline2
		jmp	v_pline3


v_pline2:				; CODE XREF: v_pline+22j
		push	line_colour
		mov	ax, pline_seg
;;;		add	ax, 3
		ADDAXW	3
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		push	ax
		mov	ax, pline_seg
;;;		add	ax, 2
		ADDAXW	2
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		push	ax
		mov	ax, pline_seg
;;;		add	ax, 1
		ADDAXW	1
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		push	ax
		push	word ptr pline_seg
		call	_read_ptsin
		inc	sp
		inc	sp
		push	ax
		call	DRAWLINE
		add	sp, 0Ah
		mov	ax, 2
		push	ax
		lea	si, pline_seg
		mov	ax, [si]
		pop	cx
		add	ax, cx
		mov	[si], ax
		jmp	v_pline1


v_pline3:				; CODE XREF: v_pline+24j
		jmp	v_nop


pmarker_count	equ	(word ptr (-44))[bp]
pmarker_sltype	equ	(word ptr (-70))[bp]
pmarker_cur	equ	(word ptr (-74))[bp]

;		S u b r	o u t i	n e

v_pmarker:		; Save line type
;;;		mov	ax, line_type
		LAXW	line_type
		mov	pmarker_sltype, ax
		mov	ax, 1		; Set line type	to solid
;;;		mov	line_type, ax
		SAXW	line_type
		mov	ax, 1
		push	ax
		mov	ax, 1
		push	ax
		call	_read_contrl	; Get marker count
		inc	sp
		inc	sp
		pop	cx
		shl	ax, cl
		mov	pmarker_count, ax
		xor	ax, ax
		mov	pmarker_cur, ax

v_pmarker1:				; CODE XREF: v_pmarker+5Cj
		mov	ax, pmarker_cur
		cmp	ax, pmarker_count
		jl	v_pmarker2
		jmp	v_pmarker3


v_pmarker2:				; CODE XREF: v_pmarker+2Cj
		mov	ax, pmarker_cur
;;;		add	ax, 1
		ADDAXW	1
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		push	ax
		push	word ptr pmarker_cur
		call	_read_ptsin
		inc	sp
		inc	sp
		push	ax
		call	draw_marker
		add	sp, 4
		mov	ax, 2
		push	ax
		lea	si, pmarker_cur
		mov	ax, [si]
		pop	cx
		add	ax, cx
		mov	[si], ax
		jmp	v_pmarker1


v_pmarker3:				; CODE XREF: v_pmarker+2Ej
		mov	ax, pmarker_sltype
;;;		mov	line_type, ax
		SAXW	line_type
		jmp	v_nop



v_gtext_buf	equ	(word ptr (-62))[bp]

;		S u b r	o u t i	n e

v_gtext:
		push	text_direction
		push	text_height
		lea	ax, v_gtext_buf
		push	ax
		mov	ax, 3
		push	ax
		call	_read_contrl	
		inc	sp
		inc	sp
		push	ax		;Length parameter
		mov	ax, 1
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		push	ax		;Y parameter
		xor	ax, ax
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		push	ax		;X parameter
		call	D_GTEXT
		add	sp, 0Ch
		jmp	v_nop

fill_sltype	equ	(word ptr (-72))[bp]

v_fillarea:
;;;		mov	ax, fill_style
		LAXW	fill_style
		cmp	ax, 0
		jnz	v_fillarea1
		jmp	area_border


v_fillarea1:				; CODE XREF: v_gtext+39j
		mov	ax, 1
		push	ax
		call	_read_contrl
		inc	sp
		inc	sp
		push	ax		; Number of points in shape
		call	area_fill
		inc	sp
		inc	sp
;
ab_count	equ	(word ptr (-70))[bp]
ab_seg		equ	(word ptr (-74))[bp]
;
area_border:				; CODE XREF: v_gtext+3Bj
;;;		mov	ax, line_type
		LAXW	line_type
		mov	fill_sltype, ax
		mov	ax, 1
;;;		mov	line_type, ax
		SAXW	line_type
		mov	ax, 1
		push	ax
		mov	ax, 1
		push	ax
		call	_read_contrl	; Number of points
		inc	sp
		inc	sp
;;;		sub	ax, 1		; Less 1 gives number of line segments
		SUBAXW	1
		pop	cx
		shl	ax, cl
		mov	ab_count, ax
		xor	ax, ax
		mov	ab_seg, ax

area_border1:				; CODE XREF: v_gtext+CDj
		mov	ax, ab_seg
		cmp	ax, ab_count
		jl	area_border2
		jmp	area_border3


area_border2:				; CODE XREF: v_gtext+7Dj
		push	fill_colour
		mov	ax, ab_seg
;;;		add	ax, 3
		ADDAXW	3
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		push	ax
		mov	ax, ab_seg
;;;		add	ax, 2
		ADDAXW	2
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		push	ax
		mov	ax, ab_seg
;;;		add	ax, 1
		ADDAXW	1
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		push	ax
		push	word ptr ab_seg
		call	_read_ptsin
		inc	sp
		inc	sp
		push	ax
		call	DRAWLINE
		add	sp, 0Ah
		mov	ax, 2
		push	ax
		lea	si, ab_seg
		mov	ax, [si]
		pop	cx
		add	ax, cx
		mov	[si], ax
		jmp	area_border1


area_border3:				; CODE XREF: v_gtext+7Fj
		push	fill_colour
		mov	ax, 1
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		push	ax
		xor	ax, ax
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		push	ax
		mov	ax, ab_count
;;;		add	ax, 1
		ADDAXW	1
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		push	ax
		push	word ptr ab_count
		call	_read_ptsin
		inc	sp
		inc	sp
		push	ax
		call	DRAWLINE
		add	sp, 0Ah
		mov	ax, fill_sltype
;;;		mov	line_type, ax
		SAXW	line_type
		jmp	v_nop

vca_pitch	equ	(word ptr  (-4))[bp]
vca_cellw	equ	(word ptr  (-6))[bp]
vca_y1		equ	(word ptr (-16))[bp]
vca_y0		equ	(word ptr (-18))[bp]
vca_x1		equ	(word ptr (-20))[bp]
vca_x0		equ	(word ptr (-22))[bp]
vca_y		equ	(word ptr (-24))[bp]
vca_x		equ	(word ptr (-26))[bp]
vca_source	equ	(word ptr (-34))[bp]
vca_deltax	equ	(word ptr (-36))[bp]
vca_deltay	equ	(word ptr (-38))[bp]
vca_cols	equ	(word ptr (-40))[bp]
vca_rows	equ	(word ptr (-42))[bp]
vca_mode	equ	(word ptr (-44))[bp]
vca_ink		equ	(word ptr (-46))[bp]
vca_ypos	equ	(word ptr (-70))[bp]
vca_col		equ	(word ptr (-72))[bp]
vca_row		equ	(word ptr (-74))[bp]
vca_tmp		equ	(word ptr (-74))[bp]


;		S u b r	o u t i	n e

v_cellarray:
		xor	ax, ax
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	vca_x0, ax
		mov	ax, 1
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	vca_y0, ax
		mov	ax, 2
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	vca_x1, ax
		mov	ax, 3
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	vca_y1, ax
		mov	ax, 5
		push	ax
		call	_read_contrl
		inc	sp
		inc	sp
		mov	vca_pitch, ax
		mov	ax, 6
		push	ax
		call	_read_contrl
		inc	sp
		inc	sp
		mov	vca_rows, ax
		mov	ax, 7
		push	ax
		call	_read_contrl
		inc	sp
		inc	sp
		mov	vca_cols, ax
		mov	ax, 8
		push	ax
		call	_read_contrl
		inc	sp
		inc	sp
		mov	vca_mode, ax
		mov	ax, vca_mode
		cmp	ax, 1
		jl	cell_array1
		jmps	cell_array2


cell_array1:				; CODE XREF: v_cellarray+65j
		jmp	cell_array3


cell_array2:				; CODE XREF: v_cellarray+67j
		mov	ax, vca_mode
		cmp	ax, 4
		jg	cell_array3
		jmp	cell_array4


cell_array3:				; CODE XREF: v_cellarray+69j
					; v_cellarray+72j
		mov	ax, 1
		mov	vca_mode, ax

cell_array4:				; CODE XREF: v_cellarray+74j
		mov	ax, vca_x1
		sub	ax, vca_x0
;;;		add	ax, 1
		ADDAXW	1
		mov	vca_tmp, ax	; Height of area
		push	word ptr vca_tmp
		mov	ax, 1
		push	ax
		push	word ptr vca_rows
		call	_clamp
		add	sp, 6
		mov	vca_rows, ax	; vca_rows now limited
		mov	ax, vca_tmp
		add	ax, vca_rows
;;;		sub	ax, 1
		SUBAXW	1
		mov	vca_row, ax
		lea	si, vca_col
		push	si
		push	word ptr vca_rows	;Number of rows to return
		push	word ptr vca_tmp	;Height of area
		call	_divide
		add	sp, 6
		mov	vca_deltay, ax
		mov	ax, vca_y1
		sub	ax, vca_y0
;;;		add	ax, 1
		ADDAXW	1
		mov	vca_row, ax
		push	word ptr vca_row
		mov	ax, 1
		push	ax
		push	word ptr vca_cols
		call	_clamp
		add	sp, 6
		mov	vca_cols, ax
		mov	ax, vca_tmp
		add	ax, vca_cols
;;;		sub	ax, 1
		SUBAXW	1
		mov	vca_tmp, ax
		lea	si, vca_col
		push	si
		push	word ptr vca_cols
		push	word ptr vca_tmp
		call	_divide
		add	sp, 6
		mov	vca_deltax, ax
		mov	ax, vca_y1
		mov	vca_y, ax
		xor	ax, ax
		mov	vca_row, ax

cell_array5:				; CODE XREF: v_cellarray+1DEj
		mov	ax, vca_row
		cmp	ax, vca_cols
		jl	cell_array6
		jmp	cell_arrayend


cell_array6:				; CODE XREF: v_cellarray+10Ej
		mov	ax, 1
		mov	vca_cellw, ax

cell_array7:				; CODE XREF: v_cellarray+1D2j
		mov	ax, vca_cellw
		cmp	ax, vca_deltax
		jle	cell_array8
		jmp	cell_array19


cell_array8:				; CODE XREF: v_cellarray+11Fj
		mov	ax, vca_y
		cmp	ax, vca_y0
		jge	cell_array10

cell_array9:				; CODE XREF: _PUTPIXEL+55u
		jmp	cell_array18


cell_array10:				; CODE XREF: v_cellarray+12Aj
		mov	ax, vca_x0
		mov	vca_x, ax
		push	word ptr vca_pitch
		push	word ptr vca_row
		call	_multiply
		add	sp, 4
		mov	vca_source, ax
		mov	ax, 1
		mov	vca_col, ax

cell_array11:				; CODE XREF: v_cellarray+1BDj
		mov	ax, vca_col
		cmp	ax, vca_rows
		jle	cell_array12
		jmp	cell_array18


cell_array12:				; CODE XREF: v_cellarray+150j
		mov	ax, NUM_COLORS-1
		push	ax
		xor	ax, ax
		push	ax
		lea	si, vca_source
		push	word ptr [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		call	_read_intin
		inc	sp
		inc	sp
		push	ax
		call	_clamp
		add	sp, 6
		mov	vca_ink, ax
		mov	ax, 1
		mov	vca_ypos, ax

cell_array13:				; CODE XREF: v_cellarray+1B1j
		mov	ax, vca_ypos
		cmp	ax, vca_deltay
		jle	cell_array14
		jmp	cell_array17


cell_array14:				; CODE XREF: v_cellarray+180j
		mov	ax, vca_x
		cmp	ax, vca_x1
		jle	cell_array15
		jmp	cell_array16


cell_array15:				; CODE XREF: v_cellarray+18Bj
		push	word ptr vca_mode
		push	word ptr vca_ink
		push	word ptr vca_y
		lea	si, vca_x
		push	word ptr [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		call	_PUTPIXEL
		add	sp, 8

cell_array16:				; CODE XREF: v_cellarray+18Dj
		lea	si, vca_ypos
		mov	ax, [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		jmp	cell_array13


cell_array17:				; CODE XREF: v_cellarray+182j
		lea	si, vca_col
		mov	ax, [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		jmp	cell_array11


cell_array18:				; CODE XREF: v_cellarray+12Cj
					; v_cellarray+152j
		lea	si, vca_y
		mov	ax, [si]
;;;		sub	word ptr [si], 1
		SUBPSI	1
		lea	si, vca_cellw
		mov	ax, [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		jmp	cell_array7


cell_array19:				; CODE XREF: v_cellarray+121j
		lea	si, vca_row
		mov	ax, [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		jmp	cell_array5


cell_arrayend:				; CODE XREF: v_cellarray+110j

		if	NEEDSFLUSH
		 push	word ptr vca_mode
		 call	_DRAWFLUSH
		 inc	sp
		 inc	sp
		endif

		jmp	v_nop





;		S u b r	o u t i	n e

v_gdp:
		mov	ax, 5
		push	ax
		call	_read_contrl
		inc	sp
		inc	sp
		mov	scr_func, ax
		mov	ax, scr_func
		cmp	ax, 1
		jz	v_bar
		jmp	v_gdpend


bar_fillshift	equ	(word ptr  (-6))[bp]
bar_fill	equ	(word ptr  (-8))[bp]
bar_pfill	equ	(word ptr (-10))[bp]
bar_y1		equ	(word ptr (-16))[bp]
bar_y0		equ	(word ptr (-18))[bp]
bar_x1		equ	(word ptr (-20))[bp]
bar_x0		equ	(word ptr (-22))[bp]
bar_y		equ	(word ptr (-24))[bp]
bar_sltype	equ	(word ptr (-70))[bp]

;		S u b r	o u t i	n e

v_bar:		; CODE XREF: v_gdp+12j
		xor	ax, ax
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	bar_x0, ax
		mov	ax, 1
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	bar_y0, ax
		mov	ax, 2
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	bar_x1, ax
		mov	ax, 3
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	vca_y1, ax
;;;		mov	ax, fill_style
		LAXW	fill_style
		cmp	ax, 0
		jnz	bar_1
		jmp	bar_outline1


bar_1:					; CODE XREF: v_bar+36j
;;;		mov	ax, fill_style
		LAXW	fill_style
		cmp	ax, 1
		jz	bar_2
		jmp	bar_hollow


bar_2:					; CODE XREF: v_bar+42j
		lea	si, fill_solid
;;;		mov	ax, si
		MOVAXSI
		mov	bar_pfill, ax
		jmp	bar_3


bar_hollow:				; CODE XREF: v_bar+44j
		mov	ax, 2
		push	ax
;;;		mov	ax, fill_interior
;;;		sub	ax, 1
		LAXW	fill_interior
		SUBAXW	1
		pop	cx
		shl	ax, cl
		shl	ax, 1
		push	ax
		lea	si, fill_stripes
		pop	ax
		add	si, ax
;;;		mov	ax, si
		MOVAXSI
		mov	bar_pfill, ax

bar_3:					; CODE XREF: v_bar+50j
		mov	ax, bar_pfill
		mov	bar_fill, ax
		mov	ax, 1
		mov	bar_fillshift, ax
		mov	ax, bar_y0
		mov	bar_y, ax

bar_4:					; CODE XREF: v_bar+E2j
		mov	ax, bar_y
		cmp	ax, bar_y1
		jle	bar_5
		jmp	bar_outline


bar_5:					; CODE XREF: v_bar+89j
		push	write_mode
		push	fill_colour
		xor	ax, ax
		push	ax
		mov	si, bar_fill
		push	word ptr [si]
		push	word ptr bar_y
		push	word ptr bar_x1
		push	word ptr bar_x0
		call	_fill_hline
		add	sp, 0Eh
		mov	ax, bar_fillshift
		cmp	ax, 4
		jl	bar_6
		jmp	bar_7


bar_6:					; CODE XREF: v_bar+B3j
		lea	si, bar_fillshift
		mov	ax, [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		lea	si, bar_fill
		mov	ax, [si]
;;;		add	word ptr [si], 2
		ADDPSI	2
		jmp	bar_8


bar_7:					; CODE XREF: v_bar+B5j
		mov	ax, 1
		mov	bar_fillshift, ax
		mov	ax, bar_pfill
		mov	bar_fill, ax

bar_8:					; CODE XREF: v_bar+CAj
		lea	si, bar_y
		mov	ax, [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		jmp	bar_4


bar_outline:
		if NEEDSFLUSH
		 push	write_mode
		 call	_DRAWFLUSH
		 inc	sp
		 inc	sp
		endif
bar_outline1:
;;;		mov	ax, line_type
		LAXW	line_type
		mov	bar_sltype, ax
		mov	ax, 1
;;;		mov	line_type, ax
		SAXW	line_type
		push	fill_colour
		push	word ptr bar_y0
		push	word ptr bar_x1
		push	word ptr bar_y0
		push	word ptr bar_x0
		call	DRAWLINE
		add	sp, 0Ah
		push	fill_colour
		push	word ptr bar_y1
		push	word ptr bar_x1
		push	word ptr bar_y0
		push	word ptr bar_x1
		call	DRAWLINE
		add	sp, 0Ah
		push	fill_colour
		push	word ptr bar_y1
		push	word ptr bar_x0
		push	word ptr bar_y1
		push	word ptr bar_x1
		call	DRAWLINE
		add	sp, 0Ah
		push	fill_colour
		push	word ptr bar_y0
		push	word ptr bar_x0
		push	word ptr bar_y1
		push	word ptr bar_x0
		call	DRAWLINE
		add	sp, 0Ah
		mov	ax, bar_sltype
;;;		mov	line_type, ax
		SAXW	line_type

v_gdpend:				; CODE XREF: v_gdp+14j
		jmp	v_nop




vsth_reqheight	equ	(word ptr (-48))[bp]
vsth_index	equ	(word ptr (-74))[bp]
vsth_match	equ	(word ptr (-78))[bp]

;		S u b r	o u t i	n e

vst_height:
		mov	ax, 1
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	vsth_reqheight, ax
		xor	ax, ax
;;;		mov	text_height, ax
		SAXW	text_height
		lea	si, char_heights
;;;		mov	ax, si
		MOVAXSI
		mov	vsth_match, ax

vst_height1:				; CODE XREF: vst_height+4Ej
		mov	si, vsth_reqheight
		push	si
		mov	si, vsth_match
		push	word ptr [si]
		pop	ax
		pop	si
		cmp	ax, si
		jg	vst_height2
		jmp	vst_height3


vst_height2:				; CODE XREF: vst_height+28j
		jmp	vst_height5


vst_height3:				; CODE XREF: vst_height+2Aj
		lea	si, text_height
		mov	ax, [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		lea	si, vsth_match
		mov	ax, [si]
;;;		add	word ptr [si], 2
		ADDPSI	2
;;;		mov	ax, text_height
		LAXW	text_height
		cmp	ax, 4
		jle	vst_height4
		jmps	vst_height5


vst_height4:				; CODE XREF: vst_height+4Aj
		jmp	vst_height1


vst_height5:				; CODE XREF: vst_height+2Dj
					; vst_height+4Cj
		mov	ax, 5
		push	ax
		mov	ax, 1
		push	ax
		push	text_height
		call	_clamp
		add	sp, 6
;;;		mov	text_height, ax
;;;		mov	ax, text_height
		SAXW	text_height
		LAXW	text_height
;;;		sub	ax, 1
		SUBAXW	1
		mov	vsth_index, ax
		mov	ax, 2
		push	ax
		mov	ax, 2
		push	ax
		call	_write_contrl
		add	sp, 4
		mov	ax, vsth_index
		shl	ax, 1
		push	ax
		lea	si, char_widths
		pop	ax
		add	si, ax
		push	word ptr [si]
		xor	ax, ax
		push	ax
		call	_write_ptsout
		add	sp, 4
		mov	ax, vsth_index
		shl	ax, 1
		push	ax
		lea	si, char_heights
		pop	ax
		add	si, ax
		push	word ptr [si]
		mov	ax, 1
		push	ax
		call	_write_ptsout
		add	sp, 4
		mov	ax, vsth_index
		shl	ax, 1
		push	ax
		lea	si, cell_widths
		pop	ax
		add	si, ax
		push	word ptr [si]
		mov	ax, 2
		push	ax
		call	_write_ptsout
		add	sp, 4
		mov	ax, vsth_index
		shl	ax, 1
		push	ax
		lea	si, cell_heights
		pop	ax
		add	si, ax
		push	word ptr [si]
		mov	ax, 3
		push	ax
		call	_write_ptsout
		add	sp, 4
		jmp	v_nop




vstd_direction	equ	(word ptr (-72))[bp]
vstd_angle	equ	(word ptr (-74))[bp]

;		S u b r	o u t i	n e

vst_direction:
		lea	si, vstd_angle
		push	si
		mov	ax, 900		; Divide by 900
		push	ax
		xor	ax, ax
		push	ax
		call	_read_intin	; (angle + 450)
		inc	sp
		inc	sp
;;;		add	ax, 450
		ADDAXW	450
		push	ax
		call	_divide
		add	sp, 6
		mov	vstd_direction, ax
		lea	si, text_direction
		push	si
		mov	ax, 4
		push	ax
		push	word ptr vstd_direction
		call	_divide
		add	sp, 6
		mov	vstd_angle, ax
		mov	ax, 900
		push	ax
		push	text_direction
		call	_multiply
		add	sp, 4
		push	ax
		xor	ax, ax
		push	ax
		call	_write_intout
		add	sp, 4
		jmp	v_nop


vsc_index	equ	(word ptr (-74))[bp]


;		S u b r	o u t i	n e

vs_color:
		mov	ax, NUM_COLORS-1
		push	ax
		xor	ax, ax
		push	ax
		xor	ax, ax
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
		push	ax
		call	_clamp
		add	sp, 6
		mov	vsc_index, ax
		mov	ax, 1
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
		push	ax
		mov	ax, vsc_index
		shl	ax, 1
		push	ax
		lea	si, palette
		pop	ax
		add	si, ax
		pop	ax
		mov	[si], ax
		mov	ax, 2
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
		push	ax
		mov	ax, vsc_index
		shl	ax, 1
		push	ax
		lea	si, palette + 2 * NUM_COLORS
		pop	ax
		add	si, ax
		pop	ax
		mov	[si], ax
		mov	ax, 3
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
		push	ax
		mov	ax, vsc_index
		shl	ax, 1
		push	ax
		lea	si, palette + 4 * NUM_COLORS
		pop	ax
		add	si, ax
		pop	ax
		mov	[si], ax
		jmp	v_nop





;		S u b r	o u t i	n e

vsl_type:
		xor	ax, ax
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
;;;		mov	line_type, ax
;;;		mov	ax, line_type
		SAXW	line_type
		LAXW	line_type
		cmp	ax, 1
		jl	vsl_type1
		jmps	vsl_type2


vsl_type1:				; CODE XREF: vsl_type+13j
		jmp	vsl_type3


vsl_type2:				; CODE XREF: vsl_type+15j
;;;		mov	ax, line_type
		LAXW	line_type
		cmp	ax, 7
		jg	vsl_type3
		jmp	vsl_type4


vsl_type3:				; CODE XREF: vsl_type+17j vsl_type+21j
		mov	ax, 1
;;;		mov	line_type, ax	
		SAXW	line_type

vsl_type4:				; CODE XREF: vsl_type+23j
		push	line_type
		xor	ax, ax
		push	ax
		call	_write_intout
		add	sp, 4
		jmp	v_nop





;		S u b r	o u t i	n e

vsl_color:
		mov	ax, NUM_COLORS-1
		push	ax
		xor	ax, ax
		push	ax
		xor	ax, ax
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
		push	ax
		call	_clamp
		add	sp, 6
;;;		mov	line_colour, ax
		SAXW	line_colour
		push	line_colour
		xor	ax, ax
		push	ax
		call	_write_intout
		add	sp, 4
		jmp	v_nop





;		S u b r	o u t i	n e

vsm_type:
		xor	ax, ax
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
;;;		mov	marker_type, ax
;;;		mov	ax, marker_type
		SAXW	marker_type
		LAXW	marker_type
		cmp	ax, 1
		jl	vsm_type1
		jmps	vsm_type2


vsm_type1:				; CODE XREF: vsm_type+13j
		jmp	vsm_type3


vsm_type2:				; CODE XREF: vsm_type+15j
;;;		mov	ax, marker_type
		LAXW	marker_type
		cmp	ax, 5
		jg	vsm_type3
		jmp	vsm_type4


vsm_type3:				; CODE XREF: vsm_type+17j vsm_type+21j
		mov	ax, 3
;;;		mov	marker_type, ax
		SAXW	marker_type

vsm_type4:				; CODE XREF: vsm_type+23j
		push	marker_type
		xor	ax, ax
		push	ax
		call	_write_intout
		add	sp, 4
		jmp	v_nop





;		S u b r	o u t i	n e

vsm_color:
		mov	ax, NUM_COLORS-1
		push	ax
		xor	ax, ax
		push	ax
		xor	ax, ax
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
		push	ax
		call	_clamp
		add	sp, 6
;;;		mov	mark_colour, ax
		SAXW	mark_colour
		push	mark_colour
		xor	ax, ax
		push	ax
		call	_write_intout
		add	sp, 4
		jmp	v_nop





;		S u b r	o u t i	n e

vst_color:
		mov	ax, NUM_COLORS-1
		push	ax
		xor	ax, ax
		push	ax
		xor	ax, ax
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
		push	ax
		call	_clamp
		add	sp, 6
;;;		mov	text_colour, ax
		SAXW	text_colour
		push	text_colour
		xor	ax, ax
		push	ax
		call	_write_intout
		add	sp, 4
		jmp	v_nop





;		S u b r	o u t i	n e

vsf_style:
		xor	ax, ax
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
;;;		mov	fill_style, ax
;;;		mov	ax, fill_style
		SAXW	fill_style
		LAXW	fill_style
		cmp	ax, 0
		jl	vsf_style1
		jmps	vsf_style2


vsf_style1:				; CODE XREF: vsf_style+13j
		jmp	vsf_style3


vsf_style2:				; CODE XREF: vsf_style+15j
;;;		mov	ax, fill_style
		LAXW	fill_style
		cmp	ax, 3
		jg	vsf_style3
		jmp	vsf_style4


vsf_style3:				; CODE XREF: vsf_style+17j
					; vsf_style+21j
		xor	ax, ax
;;;		mov	fill_style, ax
		SAXW	fill_style

vsf_style4:				; CODE XREF: vsf_style+23j
;;;		mov	ax, fill_style
		LAXW	fill_style
		cmp	ax, 3
		jz	vsf_style5
		jmp	vsf_style6


vsf_style5:				; CODE XREF: vsf_style+33j
		mov	ax, 2
;;;		mov	fill_style, ax
		SAXW	fill_style

vsf_style6:				; CODE XREF: vsf_style+35j
		push	fill_style
		xor	ax, ax
		push	ax
		call	_write_intout
		add	sp, 4
		jmp	v_nop





;		S u b r	o u t i	n e

vsf_interior:
		xor	ax, ax
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
;;;		mov	fill_interior, ax
;;;		mov	ax, fill_interior
		SAXW	fill_interior
		LAXW	fill_interior
		cmp	ax, 1
		jl	vsf_interior1
		jmps	vsf_interior2


vsf_interior1:				; CODE XREF: vsf_interior+13j
		jmp	vsf_interior3


vsf_interior2:				; CODE XREF: vsf_interior+15j
;;;		mov	ax, fill_interior
		LAXW	fill_interior
		cmp	ax, 5
		jg	vsf_interior3
		jmp	vsf_interior4


vsf_interior3:				; CODE XREF: vsf_interior+17j
					; vsf_interior+21j
		mov	ax, 1
;;;		mov	fill_interior, ax
		SAXW	fill_interior

vsf_interior4:				; CODE XREF: vsf_interior+23j
		push	fill_interior
		xor	ax, ax
		push	ax
		call	_write_intout
		add	sp, 4
		jmp	v_nop





;		S u b r	o u t i	n e

vsf_color:
		mov	ax, NUM_COLORS-1
		push	ax
		xor	ax, ax
		push	ax
		xor	ax, ax
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
		push	ax
		call	_clamp
		add	sp, 6
;;;		mov	fill_colour, ax
		SAXW	fill_colour
		push	fill_colour
		xor	ax, ax
		push	ax
		call	_write_intout
		add	sp, 4
		jmp	v_nop





;		S u b r	o u t i	n e

vq_color:
		mov	ax, NUM_COLORS - 1
		push	ax
		xor	ax, ax
		push	ax
		xor	ax, ax
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
		push	ax
		call	_clamp
		add	sp, 6
		mov	vsc_index, ax
		push	word ptr vsc_index
		xor	ax, ax
		push	ax
		call	_write_intout
		add	sp, 4
		xor	si, si
		push	si
		mov	ax, 1
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
		pop	si
		cmp	ax, si
		jz	vq_color1
		jmp	vq_color2


vq_color1:				; CODE XREF: vq_color+34j
		mov	ax, vsc_index
		shl	ax, 1
		push	ax
		lea	si, palette
		pop	ax
		add	si, ax
		push	word ptr [si]
		mov	ax, 1
		push	ax
		call	_write_intout
		add	sp, 4
		mov	ax, vsc_index
		shl	ax, 1
		push	ax
		lea	si, palette + 2 * NUM_COLORS
		pop	ax
		add	si, ax
		push	word ptr [si]
		mov	ax, 2
		push	ax
		call	_write_intout
		add	sp, 4
		mov	ax, vsc_index
		shl	ax, 1
		push	ax
		lea	si, palette + 4 * NUM_COLORS
		pop	ax
		add	si, ax
		push	word ptr [si]
		mov	ax, 3
		push	ax
		call	_write_intout
		add	sp, 4
		jmp	vq_color5


vq_color2:				; CODE XREF: vq_color+36j
		mov	ax, vsc_index

		if	NUM_COLORS gt 2

		shl	ax, 1
		push	ax
		lea	si, palette + 6 * NUM_COLORS
		pop	ax
		add	si, ax
		push	word ptr [si]
		mov	ax, 1
		push	ax
		call	_write_intout
		add	sp, 4
		mov	ax, vsc_index
		shl	ax, 1
		push	ax
		lea	si, palette + 8 + 6 * NUM_COLORS
		pop	ax
		add	si, ax
		push	word ptr [si]
		mov	ax, 2
		push	ax
		call	_write_intout
		add	sp, 4
		mov	ax, vsc_index
		shl	ax, 1
		push	ax
		lea	si, palette + 16 + 6 * NUM_COLORS
		pop	ax
		add	si, ax
		push	word ptr [si]

		else	; NUM_COLORS gt 2

		cmp	ax, 0
		jnz	vq_color3
		jmp	vq_color4


vq_color3:				; CODE XREF: vq_color+8Dj
		mov	ax, 1000
		mov	vsc_index, ax

vq_color4:				; CODE XREF: vq_color+8Fj
		push	word ptr vsc_index
		mov	ax, 1
		push	ax
		call	_write_intout
		add	sp, 4
		push	word ptr vsc_index
		mov	ax, 2
		push	ax
		call	_write_intout
		add	sp, 4
		push	word ptr vsc_index
		endif	; NUM_COLORS gt 2

		mov	ax, 3
		push	ax
		call	_write_intout
		add	sp, 4

vq_color5:				; CODE XREF: vq_color+84j
		jmp	v_nop

vqca_col	equ	(word ptr (-4))[bp]
vqca_row	equ	(word ptr (-6))[bp]

vqca_y1		equ	(word ptr (-16))[bp]
vqca_y0		equ	(word ptr (-18))[bp]
vqca_x1		equ	(word ptr (-20))[bp]
vqca_x0		equ	(word ptr (-22))[bp]
vqca_y		equ	(word ptr (-24))[bp]
vqca_x		equ	(word ptr (-26))[bp]

vqca_deltay	equ	(word ptr (-30))[bp]
vqca_deltax	equ	(word ptr (-32))[bp]
vqca_outindex	equ	(word ptr (-34))[bp]

vqca_rows	equ	(word ptr (-40))[bp]
vqca_cols	equ	(word ptr (-42))[bp]
vqca_tempwh	equ	(word ptr (-46))[bp]

vqca_remainder	equ	(word ptr (-70))[bp]
vqca_ccols	equ	(word ptr (-72))[bp]
vqca_crows	equ	(word ptr (-74))[bp]

;		S u b r	o u t i	n e

vq_cellarray:
		xor	ax, ax		;First: Read in the coordinates of the
		push	ax		;screen area into X0, Y0 and X1, Y1
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	vqca_x0, ax
		mov	ax, 1
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	vqca_y0, ax
		mov	ax, 2
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	vqca_x1, ax
		mov	ax, 3
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	vqca_y1, ax
		mov	ax, 5		;Read the number of columns and rows
		push	ax		;to return.
		call	_read_contrl
		inc	sp
		inc	sp
		mov	vqca_cols, ax
		mov	ax, 6
		push	ax
		call	_read_contrl
		inc	sp
		inc	sp
		mov	vqca_rows, ax
		xor	ax, ax		;Write 0 to the error flag
		push	ax
		mov	ax, 9
		push	ax
		call	_write_contrl
		add	sp, 4
		mov	ax, vqca_x1	;Get the width of the area to read,
		sub	ax, vqca_x0	;and clamp it between (1, column count)
;;;		add	ax, 1
		ADDAXW	1
		mov	vqca_tempwh, ax
		push	word ptr vqca_tempwh
		mov	ax, 1
		push	ax
		push	word ptr vqca_cols
		call	_clamp
		add	sp, 6			;Number of elements that will
		mov	vqca_ccols, ax		;be returned in each row.
		lea	si, vqca_remainder	
		push	si
		push	word ptr vqca_ccols	;Calculate horizontal spacing
		mov	ax, vqca_tempwh		;between each column
		add	ax, vqca_cols
;;;		sub	ax, 1
		SUBAXW	1
		push	ax
		call	_divide
		add	sp, 6
		mov	vqca_deltax, ax
		push	word ptr vqca_ccols	;Number of elements populated
		mov	ax, 7			;in each row
		push	ax
		call	_write_contrl
		add	sp, 4
		mov	ax, vqca_y1		;Now do the same for inter-row
		sub	ax, vqca_y0		;spacing, and number of 
;;;		add	ax, 1			;rows returned
		ADDAXW	1
		mov	vqca_tempwh, ax
		push	word ptr vqca_tempwh
		mov	ax, 1
		push	ax
		push	word ptr vqca_rows
		call	_clamp
		add	sp, 6
		mov	vqca_crows, ax
		lea	si, vqca_remainder
		push	si
		push	word ptr vqca_crows
		mov	ax, vqca_tempwh
		add	ax, vqca_rows
;;;		sub	ax, 1
		SUBAXW	1
		push	ax
		call	_divide
		add	sp, 6
		mov	vqca_deltay, ax
		push	word ptr vqca_crows	;Write back number of 
		mov	ax, 8			;populated rows
		push	ax
		call	_write_contrl
		add	sp, 4
		mov	ax, vqca_y1		;Now go from Y0 to Y1
		mov	vqca_y, ax
		xor	ax, ax
		mov	vqca_row, ax

vqca_1:					; CODE XREF: vq_cellarray+16Aj
		mov	ax, vqca_row
		cmp	ax, vqca_crows
		jl	vqca_2
		jmp	vqca_6


vqca_2:					; CODE XREF: vq_cellarray+F5j
		mov	ax, vqca_x0
		mov	vqca_x, ax
		push	word ptr vqca_cols
		push	word ptr vqca_row
		call	_multiply
		add	sp, 4
		mov	vqca_outindex, ax
		xor	ax, ax
		mov	vqca_col, ax

vqca_3:					; CODE XREF: vq_cellarray+151j
		mov	ax, vqca_col
		cmp	ax, vqca_ccols
		jl	vqca_4
		jmp	vqca_5


vqca_4:					; CODE XREF: vq_cellarray+11Aj
		push	word ptr vqca_y
		push	word ptr vqca_x
		call	_GETPIXEL
		add	sp, 4
		push	ax
		lea	si, vqca_outindex
		push	word ptr [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		call	_write_intout
		add	sp, 4
		push	word ptr vqca_deltax
		lea	si, vqca_x
		mov	ax, [si]
		pop	cx
		add	ax, cx
		mov	[si], ax
		lea	si, vqca_col
		mov	ax, [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		jmp	vqca_3


vqca_5:					; CODE XREF: vq_cellarray+11Cj
		push	word ptr vqca_deltay
		lea	si, vqca_y
		mov	ax, [si]
		pop	cx
		sub	ax, cx
		mov	[si], ax
		lea	si, vqca_row
		mov	ax, [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		jmp	vqca_1


vqca_6:					; CODE XREF: vq_cellarray+F7j
		jmp	v_nop


locator_ch	equ	(byte ptr  (-2))[bp]
locator_y0	equ	(word ptr (-12))[bp]
locator_x0	equ	(word ptr (-14))[bp]
locator_crossy	equ	(word ptr (-16))[bp]
locator_chy	equ	(word ptr (-18))[bp]
locator_crossx	equ	(word ptr (-20))[bp]
locator_chx	equ	(word ptr (-22))[bp]
locator_y	equ	(word ptr (-24))[bp]
locator_x	equ	(word ptr (-26))[bp]
locator_delta	equ	(word ptr (-28))[bp]
locator_button	equ	(word ptr (-46))[bp]
locator_finish	equ	(word ptr (-66))[bp]
locator_number	equ	(word ptr (-74))[bp]
locator_prevx	equ	(word ptr (-74))[bp]
locator_prevy	equ	(word ptr (-74))[bp]

vrq_locator:
		xor	ax, ax
		push	ax
		mov	ax, 4
		push	ax
		call	_write_contrl
		add	sp, 4
		xor	ax, ax
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
		mov	locator_number, ax
		mov	ax, locator_number
		cmp	ax, 1
		jnz	locator1
		jmp	locator2


locator1:				; CODE XREF: cseg:11F8j
		mov	ax, locator_number
		cmp	ax, 2
		jnz	locatorend

locator2:				; CODE XREF: cseg:11FAj
		jmp	locator3


locatorend:				; CODE XREF: cseg:1203j
		mov	sp, bp
		pop	bp
		retn	


locator3:				; CODE XREF: cseg:1205j
		xor	ax, ax
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	locator_x, ax
		mov	ax, 1
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	locator_y, ax
		mov	ax, 0Ah
		mov	locator_delta, ax
		xor	ax, ax
		mov	locator_finish, ax

locator_loop:				; CODE XREF: cseg:1466j
		mov	ax, XRESMX
		push	ax
		xor	ax, ax
		push	ax
		mov	ax, locator_x
;;;		sub	ax, CROSSHAIR_W
		SUBAXW	CROSSHAIR_W
		push	ax
		call	_clamp
		add	sp, 6
		mov	locator_chx, ax
		mov	ax, YRESMX
		push	ax
		xor	ax, ax
		push	ax
		mov	ax, locator_y
;;;		sub	ax, CROSSHAIR_H
		SUBAXW	CROSSHAIR_H
		push	ax
		call	_clamp
		add	sp, 6
		mov	locator_chy, ax
		mov	ax, XRESMX
		push	ax
		xor	ax, ax
		push	ax
		mov	ax, locator_x
;;;		add	ax, CROSSHAIR_W
		ADDAXW	CROSSHAIR_W
		push	ax
		call	_clamp
		add	sp, 6
		mov	locator_crossx, ax
		mov	ax, YRESMX
		push	ax
		xor	ax, ax
		push	ax
		mov	ax, locator_y
;;;		add	ax, CROSSHAIR_H
		ADDAXW	CROSSHAIR_H
		push	ax
		call	_clamp
		add	sp, 6
		mov	locator_crossy, ax
		mov	ax, locator_chx
		mov	locator_prevx, ax

locator5:				; CODE XREF: cseg:12BCj
		mov	ax, locator_prevx
		cmp	ax, locator_crossx
		jle	locator6
		jmp	locator7


locator6:				; CODE XREF: cseg:129Aj
		mov	ax, 3
		push	ax
		mov	ax, NUM_COLORS - 1
		push	ax
		push	word ptr locator_y
		push	word ptr locator_prevx
		call	_PUTPIXEL
		add	sp, 8
		lea	si, locator_prevx
		mov	ax, [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		jmp	locator5


locator7:				; CODE XREF: cseg:129Cj
		mov	ax, locator_chy
		mov	locator_prevy, ax

locator8:				; CODE XREF: cseg:12EDj
		mov	ax, locator_prevy
		cmp	ax, locator_crossy
		jle	locator9
		jmp	locator10


locator9:				; CODE XREF: cseg:12CBj
		mov	ax, 3
		push	ax
		mov	ax, NUM_COLORS - 1
		push	ax
		push	word ptr locator_prevy
		push	word ptr locator_x
		call	_PUTPIXEL
		add	sp, 8
		lea	si, locator_prevy
		mov	ax, [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		jmp	locator8


locator10:				; CODE XREF: cseg:12CDj
		if	NEEDSFLUSH
		 mov	ax, 3
		 push	ax
		 call	_DRAWFLUSH
		 inc	sp
		 inc	sp
		endif
		mov	ax, locator_x
		mov	locator_x0, ax
		mov	ax, locator_y
		mov	locator_y0, ax
		lea	si, locator_ch
		push	si
		call	_getkey
		inc	sp
		inc	sp
		mov	ax, 0FFh	; Mask
		push	ax
		mov	al, locator_ch; Key
		mov	ah, 0
		pop	si
		and	ax, si
		mov	locator_button, ax
		mov	ax, locator_button
		cmp	ax, 1Bh
		jz	locator11
		jmp	locator13


locator11:				; CODE XREF: cseg:131Aj
		lea	si, locator_ch
		push	si
		call	_read_key
		inc	sp
		inc	sp
		mov	ax, 0FFFFh
		push	ax
		mov	al, locator_ch
		mov	ah, 0
		pop	si
		cmp	ax, si
		jnz	locator12
		jmp	locator13


locator12:				; CODE XREF: cseg:1334j
		mov	ax, 0FFh
		push	ax
		mov	al, locator_ch
		mov	ah, 0
		pop	si
		and	ax, si
		mov	locator_button, ax

locator13:				; CODE XREF: cseg:131Cj cseg:1336j
		mov	ax, locator_button
		push	ax
		jmp	locator24


locator14:
		push	word ptr locator_delta
		lea	si, locator_y
		mov	ax, [si]
		pop	cx
		add	ax, cx
		mov	[si], ax
		jmp	locator25


locator15:
		push	word ptr locator_delta
		lea	si, locator_y
		mov	ax, [si]
		pop	cx
		sub	ax, cx
		mov	[si], ax
		jmp	locator25


locator_l:
		push	word ptr locator_delta
		lea	si, locator_x
		mov	ax, [si]
		pop	cx
		sub	ax, cx
		mov	[si], ax
		jmp	locator25


locator_r:
		push	word ptr locator_delta
		lea	si, locator_x
		mov	ax, [si]
		pop	cx
		add	ax, cx
		mov	[si], ax
		jmp	locator25

;
; Toggle delta (1 <--> 10) 
;
locator_tdelta:
		mov	ax, locator_delta
		cmp	ax, 0Ah
		jz	locator19
		jmp	locator20


locator19:				; CODE XREF: cseg:1395j
		mov	ax, 1
		mov	locator_delta, ax
		jmp	locator21


locator20:				; CODE XREF: cseg:1397j
		mov	ax, 0Ah
		mov	locator_delta, ax

locator21:				; CODE XREF: cseg:13A0j
		jmp	locator25


locator_selected:
		mov	ax, 1
		mov	locator_finish, ax
		jmp	locator25


locator23:
		jmp	locator25


locator24:				; CODE XREF: cseg:134Cj
		call	_switch

		dw	5
		dw	'R'
		dw	'C'
		dw	'D'
		dw	'B'
		dw	'A'
sw_locator	dw	offset locator_selected - offset sw_locator
		dw	offset locator_tdelta - offset sw_locator - 2 
		dw	offset locator_r - offset sw_locator - 4 
		dw	offset locator_l - offset sw_locator - 6 
		dw	offset locator15 - offset sw_locator - 8 
		dw	offset locator14 - offset sw_locator - 10


locator25:				; CODE XREF: cseg:135Cj cseg:136Cj
					; ...
		mov	ax, XRESMX
		push	ax
		xor	ax, ax
		push	ax
		push	word ptr locator_x
		call	_clamp
		add	sp, 6
		mov	locator_x, ax
		mov	ax, YRESMX
		push	ax
		xor	ax, ax
		push	ax
		push	word ptr locator_y
		call	_clamp
		add	sp, 6
		mov	locator_y, ax
		mov	ax, locator_chx
		mov	locator_prevx, ax

locator26:				; CODE XREF: cseg:1427j
		mov	ax, locator_prevx
		cmp	ax, locator_crossx
		jle	locator27
		jmp	locator28


locator27:				; CODE XREF: cseg:1405j
		mov	ax, 3
		push	ax
		mov	ax, NUM_COLORS - 1
		push	ax
		push	word ptr locator_y0
		push	word ptr locator_prevx
		call	_PUTPIXEL
		add	sp, 8
		lea	si, locator_prevy 
		mov	ax, [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		jmp	locator26


locator28:				; CODE XREF: cseg:1407j
		mov	ax, locator_chy
		mov	locator_prevy, ax

locator29:				; CODE XREF: cseg:1458j
		mov	ax, locator_prevy
		cmp	ax, locator_crossy
		jle	locator30
		jmp	locator31


locator30:				; CODE XREF: cseg:1436j
		mov	ax, 3
		push	ax
		mov	ax, NUM_COLORS - 1
		push	ax
		push	word ptr locator_prevy
		push	word ptr locator_x0
		call	_PUTPIXEL
		add	sp, 8
		lea	si, locator_prevy
		mov	ax, [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		jmp	locator29


locator31:				; CODE XREF: cseg:1438j
		if	NEEDSFLUSH
		 mov	ax, 3
		 push	ax
		 call	_DRAWFLUSH
		 inc	sp
		 inc	sp
		endif
		mov	ax, locator_finish
		or	ax, ax
		jnz	j_locator_done
		jmps	j_locator_loop


j_locator_done:				; CODE XREF: cseg:1460j
		jmps	locator_done


j_locator_loop:				; CODE XREF: cseg:1462j
		jmp	locator_loop


locator_done:				; CODE XREF: cseg:1464j
		mov	ax, 1
		push	ax
		mov	ax, 4
		push	ax
		call	_write_contrl
		add	sp, 4
		mov	ax, 1
		push	ax
		mov	ax, 2
		push	ax
		call	_write_contrl
		add	sp, 4
		push	word ptr locator_x
		xor	ax, ax
		push	ax
		call	_write_ptsout
		add	sp, 4
		push	word ptr locator_y
		mov	ax, 1
		push	ax
		call	_write_ptsout
		add	sp, 4
		push	word ptr locator_button
		xor	ax, ax
		push	ax
		call	_write_intout
		add	sp, 4
		jmp	v_nop


choice_ch	equ	(byte ptr  (-2))[bp]
choice_chw	equ	(word ptr (-46))[bp]
choice_val	equ	(word ptr (-74))[bp]

;		S u b r	o u t i	n e

vrq_choice:
		xor	ax, ax
		push	ax
		mov	ax, 4
		push	ax
		call	_write_contrl
		add	sp, 4
		mov	ax, 1
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
		push	ax
		xor	ax, ax
		push	ax
		call	_write_intout
		add	sp, 4
		lea	si, choice_ch
		push	si
		call	_getkey
		inc	sp
		inc	sp
		mov	ax, 255
		push	ax
		mov	al, choice_ch
		mov	ah, 0
		pop	si
		and	ax, si
		mov	choice_chw, ax
		mov	ax, choice_chw
		cmp	ax, 1Bh
		jz	choice1
		jmp	choice5


choice1:				; CODE XREF: vrq_choice+3Ej
		lea	si, choice_ch
		push	si
		call	_read_key
		inc	sp
		inc	sp
		mov	ax, 255
		push	ax
		mov	al, choice_ch
		mov	ah, 0
		pop	si
		and	ax, si
		mov	choice_val, ax
		mov	ax, choice_val
		cmp	ax, 70h
		jge	choice2
		jmp	choice3


choice2:				; CODE XREF: vrq_choice+61j
		mov	ax, choice_val
		cmp	ax, 79h
		jle	choice4

choice3:				; CODE XREF: vrq_choice+63j
		jmp	choice5


choice4:				; CODE XREF: vrq_choice+6Cj
		mov	ax, choice_val
;;;		sub	ax, 6Fh
		SUBAXW	6Fh
		push	ax
		xor	ax, ax
		push	ax
		call	_write_intout
		add	sp, 4
		mov	ax, 1
		push	ax
		mov	ax, 4
		push	ax
		call	_write_contrl
		add	sp, 4

choice5:				; CODE XREF: vrq_choice+40j
					; vrq_choice+6Ej
		jmp	v_nop




string_ch	equ	(byte ptr  (-2))[bp]
string_echox	equ	(word ptr (-26))[bp]
string_echo	equ	(word ptr (-44))[bp]
string_chw	equ	(word ptr (-46))[bp]
string_pos	equ	(word ptr (-64))[bp]
string_maxlen	equ	(word ptr (-70))[bp]
string_len	equ	(word ptr (-74))[bp]

;		S u b r	o u t i	n e

vrq_string:
		mov	si, 1
		push	si
		xor	ax, ax
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
		pop	si
		cmp	ax, si
		jnz	string1
		jmp	string2


string1:				; CODE XREF: vrq_string+Fj
		xor	ax, ax
		push	ax
		mov	ax, 4
		push	ax
		call	_write_contrl
		add	sp, 4
		mov	sp, bp
		pop	bp
		retn	


string2:				; CODE XREF: vrq_string+11j
		xor	ax, ax
		mov	string_pos, ax
		xor	ax, ax
		mov	string_len, ax
		mov	ax, 1
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
		mov	string_maxlen, ax
		mov	ax, 2
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
		mov	string_echo, ax
		xor	ax, ax
		mov	string_echox, ax

string3:				; CODE XREF: vrq_string+ECj
		lea	si, string_ch
		push	si
		call	_getkey
		inc	sp
		inc	sp

		if	TWOHEAD
		 mov	ax,string_echo
		 cmp	ax, 0
		 jnz	string3a
		 jmp	string3b
;
string3a:	 mov	al, string_ch	;Echo key on text screen
		 mov	ah, 0
		 push	ax
		 call	_putchar
		 inc	sp
		 inc	sp
		endif
string3b:
		mov	ax, 0FFh
		push	ax
		mov	al, string_ch
		mov	ah, 0
		pop	si
		and	ax, si
		mov	string_chw, ax
		if	TWOHEAD
		else
		 mov	ax, string_echo
		 cmp	ax, 0
		 jnz	string4
		 jmp	string5


string4:				; CODE XREF: vrq_string+6Aj
		 xor	ax, ax
		 push	ax
		 mov	ax, 1
		 push	ax
		 lea	si, string_chw
		 push	si
		 mov	ax, 0FFFFh
		 push	ax
		 mov	ax, 1
		 push	ax
		 push	word ptr string_echox
		 call	D_GTEXT
		 add	sp, 0Ch
		 lea	si, cell_widths
		 push	word ptr [si]
		 lea	si, string_echox
		 mov	ax, [si]
		 pop	cx
		 add	ax, cx
		 mov	[si], ax

		endif	;NOT TWOHEAD

string5:				; CODE XREF: vrq_string+6Cj
		mov	ax, string_chw
		cmp	ax, 0Ah
		jz	string6
		jmp	string7


string6:				; CODE XREF: vrq_string+A1j
		jmp	string13


string7:				; CODE XREF: vrq_string+A3j
		mov	ax, string_chw
		cmp	ax, 0Dh
		jz	string8
		jmp	string9


string8:				; CODE XREF: vrq_string+AFj
		jmp	string13


string9:				; CODE XREF: vrq_string+B1j
		mov	si, string_maxlen
		push	si
		mov	ax, string_len
;;;		add	ax, 1
		ADDAXW	1
		pop	si
		cmp	ax, si
		jg	string10
		jmp	string11


string10:				; CODE XREF: vrq_string+C5j
		jmp	string13


string11:				; CODE XREF: vrq_string+C7j
		push	word ptr string_chw
		push	word ptr string_len
		call	_write_intout
		add	sp, 4
		lea	si, string_len
		mov	ax, [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		mov	ax, string_len
		cmp	ax, string_maxlen
		jle	string12
		jmps	string13


string12:				; CODE XREF: vrq_string+E8j
		jmp	string3


string13:				; CODE XREF: vrq_string+A6j
					; vrq_string+B4j ...
		push	word ptr string_len
		mov	ax, 4
		push	ax
		call	_write_contrl
		add	sp, 4
		jmp	v_nop





;		S u b r	o u t i	n e

vswr_mode:
		xor	ax, ax
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
;;;		mov	write_mode, ax
;;;		mov	ax, write_mode
		SAXW	write_mode
		LAXW	write_mode
		cmp	ax, 1
		jl	vswr_mode1
		jmps	vswr_mode2


vswr_mode1:				; CODE XREF: vswr_mode+13j
		jmp	vswr_mode3


vswr_mode2:				; CODE XREF: vswr_mode+15j
;;;		mov	ax, write_mode
		LAXW	write_mode
		cmp	ax, 4
		jg	vswr_mode3
		jmp	vswr_mode4


vswr_mode3:				; CODE XREF: vswr_mode+17j
					; vswr_mode+21j
		mov	ax, 1
;;;		mov	write_mode, ax
		SAXW	write_mode

vswr_mode4:				; CODE XREF: vswr_mode+23j
		push	write_mode
		xor	ax, ax
		push	ax
		call	_write_intout
		add	sp, 4
		jmp	v_nop





;		S u b r	o u t i	n e

vsin_mode:
		mov	ax, 1
		push	ax
		xor	ax, ax
		push	ax
		call	_write_intout
		add	sp, 4
		jmp	v_nop



		jmp	v_nop


scr_switch:				; CODE XREF: SCREEN+20j
		call	_switch

		dw	29
		dw	33, 32, 31, 30, 28, 27, 26, 25, 24, 23, 22, 20
		dw	18, 17, 15, 14, 13
		dw	12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1
sw_screen	dw	offset v_nop         - offset sw_screen 	
		dw	offset vsin_mode     - offset sw_screen - 2
		dw	offset vswr_mode     - offset sw_screen - 4
		dw	offset vrq_string    - offset sw_screen - 6
		dw	offset vrq_choice    - offset sw_screen - 8
		dw	offset vrq_locator   - offset sw_screen - 0Ah
		dw	offset vq_cellarray  - offset sw_screen - 0Ch
		dw	offset vq_color      - offset sw_screen - 0Eh
		dw	offset vsf_color     - offset sw_screen - 10h
		dw	offset vsf_interior  - offset sw_screen - 12h
		dw	offset vsf_style     - offset sw_screen - 14h
		dw	offset vst_color     - offset sw_screen - 16h
		dw	offset vsm_color     - offset sw_screen - 18h
		dw	offset vsm_type      - offset sw_screen - 1Ah
		dw	offset vsl_color     - offset sw_screen - 1Ch
		dw	offset vsl_type      - offset sw_screen - 1Eh
		dw	offset vs_color      - offset sw_screen - 20h
		dw	offset vst_direction - offset sw_screen - 22h
		dw	offset vst_height    - offset sw_screen - 24h
		dw	offset v_gdp         - offset sw_screen - 26h
		dw	offset v_cellarray   - offset sw_screen - 28h
		dw	offset v_fillarea    - offset sw_screen - 2Ah
		dw	offset v_gtext       - offset sw_screen - 2Ch
		dw	offset v_pmarker     - offset sw_screen - 2Eh
		dw	offset v_pline       - offset sw_screen - 30h
		dw	offset v_esc         - offset sw_screen - 32h
		dw	offset v_updwk       - offset sw_screen - 34h
		dw	offset v_clrwk       - offset sw_screen - 36h
		dw	offset v_clswk       - offset sw_screen - 38h
		dw	offset v_opnwk       - offset sw_screen - 3Ah


v_nop:					; CODE XREF: v_opnwk+23Bj v_clswk+8j
					; ...
		mov	sp, bp
		pop	bp
		retn	

		mov	sp, bp
		pop	bp
		retn	

mark_y		equ	(word ptr   (6))[bp]
mark_x		equ	(word ptr   (4))[bp]
mark_x2		equ	(word ptr  (-2))[bp]
mark_y1		equ	(word ptr  (-4))[bp]
mark_y0		equ	(word ptr  (-6))[bp]
mark_x1		equ	(word ptr  (-8))[bp]
mark_x0		equ	(word ptr (-10))[bp]
mark_delta2	equ	(word ptr (-12))[bp]
mark_delta1	equ	(word ptr (-14))[bp]

;		S u b r	o u t i	n e

draw_marker:		; CODE XREF: v_pmarker+48p
		call	__csv

		db	0Eh

;;;		mov	ax, marker_type
		LAXW	marker_type
		cmp	ax, 1
		jz	draw_marker1
		jmp	draw_marker2


draw_marker1:				; CODE XREF: draw_marker+Bj
		mov	ax, 2
		mov	mark_delta1, ax
		mov	ax, 1
		mov	mark_delta2, ax
		jmp	draw_marker3


draw_marker2:				; CODE XREF: draw_marker+Dj
		mov	ax, MARK2_SIZE
		mov	mark_delta1, ax
		mov	ax, MARK2_SIZE / 2
		mov	mark_delta2, ax

draw_marker3:				; CODE XREF: draw_marker+1Cj
		mov	ax, mark_x
		sub	ax, mark_delta2
		mov	mark_x0, ax
		mov	ax, mark_x0
		add	ax, mark_delta1
		mov	mark_x1, ax
		mov	ax, mark_y
		sub	ax, mark_delta2
		mov	mark_y0, ax
		mov	ax, mark_y0
		add	ax, mark_delta1
		mov	mark_y1,	ax
		mov	ax, mark_x0
		cmp	ax, 0
		jl	draw_marker4
		jmps	draw_marker5


draw_marker4:				; CODE XREF: draw_marker+55j
		jmp	draw_marker6


draw_marker5:				; CODE XREF: draw_marker+57j
		mov	ax, mark_y0
		cmp	ax, 0
		jl	draw_marker6
		jmps	draw_marker7


draw_marker6:				; CODE XREF: draw_marker+59j
					; draw_marker+62j
		jmp	draw_marker8


draw_marker7:				; CODE XREF: draw_marker+64j
		mov	ax, mark_x1
		cmp	ax, XRESMX
		jg	draw_marker8
		jmps	draw_marker9


draw_marker8:				; CODE XREF: draw_marker+66j
					; draw_marker+6Fj
		jmp	draw_marker10


draw_marker9:				; CODE XREF: draw_marker+71j
		mov	ax, mark_y1
		cmp	ax, YRESMX
		jg	draw_marker10
		jmp	draw_marker11


draw_marker10:				; CODE XREF: draw_marker+73j
					; draw_marker+7Cj
		mov	sp, bp
		pop	bp
		retn	


draw_marker11:				; CODE XREF: draw_marker+7Ej
;;;		mov	ax, marker_type
		LAXW	marker_type
		cmp	ax, 1
		jz	draw_marker12
		jmps	draw_marker13


draw_marker12:				; CODE XREF: draw_marker+8Cj
		jmp	draw_marker14


draw_marker13:				; CODE XREF: draw_marker+8Ej
;;;		mov	ax, marker_type
		LAXW	marker_type
		cmp	ax, 4
		jz	draw_marker14
		jmp	draw_marker15


draw_marker14:				; CODE XREF: draw_marker+90j
					; draw_marker+9Aj
		push	mark_colour
		push	word ptr mark_y0
		push	word ptr mark_x1
		push	word ptr mark_y0
		push	word ptr mark_x0
		call	DRAWLINE
		add	sp, 0Ah
		push	mark_colour
		push	word ptr mark_y1
		push	word ptr mark_x1
		push	word ptr mark_y0
		push	word ptr mark_x1
		call	DRAWLINE
		add	sp, 0Ah
		push	mark_colour
		push	word ptr mark_y1
		push	word ptr mark_x0
		push	word ptr mark_y1
		push	word ptr mark_x1
		call	DRAWLINE
		add	sp, 0Ah
		push	mark_colour
		push	word ptr mark_y0
		push	word ptr mark_x0
		push	word ptr mark_y1
		push	word ptr mark_x0
		call	DRAWLINE
		add	sp, 0Ah
		jmp	draw_marker23


draw_marker15:				; CODE XREF: draw_marker+9Cj
;;;		mov	ax, marker_type
		LAXW	marker_type
		cmp	ax, 5
		jz	draw_marker16
		jmps	draw_marker17


draw_marker16:				; CODE XREF: draw_marker+101j
		jmp	draw_marker18


draw_marker17:				; CODE XREF: draw_marker+103j
;;;		mov	ax, marker_type
		LAXW	marker_type
		cmp	ax, 3
		jz	draw_marker18
		jmp	draw_marker19


draw_marker18:				; CODE XREF: draw_marker+105j
					; draw_marker+10Fj
		push	mark_colour
		push	word ptr mark_y1
		push	word ptr mark_x1
		push	word ptr mark_y0
		push	word ptr mark_x0
		call	DRAWLINE
		add	sp, 0Ah
		push	mark_colour
		push	word ptr mark_y0
		push	word ptr mark_x1
		push	word ptr mark_y1
		push	word ptr mark_x0
		call	DRAWLINE
		add	sp, 0Ah

draw_marker19:				; CODE XREF: draw_marker+111j
;;;		mov	ax, marker_type
		LAXW	marker_type
		cmp	ax, 2
		jz	draw_marker20
		jmps	draw_marker21


draw_marker20:				; CODE XREF: draw_marker+147j
		jmp	draw_marker22


draw_marker21:				; CODE XREF: draw_marker+149j
;;;		mov	ax, marker_type
		LAXW	marker_type
		cmp	ax, 3
		jz	draw_marker22
		jmp	draw_marker23


draw_marker22:				; CODE XREF: draw_marker+14Bj
					; draw_marker+155j
		mov	ax, mark_y0
		add	ax, mark_delta2
		mov	mark_x2, ax
		push	mark_colour
		push	word ptr mark_x2
		push	word ptr mark_x1
		push	word ptr mark_x2
		push	word ptr mark_x0
		call	DRAWLINE
		add	sp, 0Ah
		mov	ax, mark_x0
		add	ax, mark_delta2
		mov	mark_x2, ax
		push	mark_colour
		push	word ptr mark_y1
		push	word ptr mark_x2
		push	word ptr mark_y0
		push	word ptr mark_x2
		call	DRAWLINE
		add	sp, 0Ah

draw_marker23:				; CODE XREF: draw_marker+F7j
					; draw_marker+157j
		mov	sp, bp
		pop	bp
		retn	



		mov	sp, bp
		pop	bp
		retn	


; [BP] Workfront

;		S u b r	o u t i	n e

afill_count	equ	(word ptr   (4))[bp]	;Number of points
afill_miny	equ	(word ptr  (-8))[bp]	;Minimum Y-coordinate of shape
afill_maxy	equ	(word ptr (-10))[bp]	;Maximum Y-coordinate of shape
afill_pattern	equ	(word ptr (-14))[bp]	;Pattern to use
afill_curpat	equ	(word ptr (-16))[bp]	;Pattern shifted by line
afill_cury	equ	(word ptr (-24))[bp]
afill_y		equ	(word ptr (-38))[bp]
afill_curpoint	equ	(word ptr (-44))[bp]
afill_curinter	equ	(word ptr (-46))[bp]	;Current intersection
afill_intersect	equ	(word ptr (-146))[bp]	;List of intersections

area_fill:		; CODE XREF: v_gtext+48p
		call	__csv

		db	92h

		mov	ax, 7FFFh
		mov	afill_maxy, ax
		mov	ax, 8001h
		mov	afill_miny, ax
		mov	ax, 1
		mov	afill_curpoint, ax
;
; Establish minimum and maximum Y coords
;
afill_getminmax:				; CODE XREF: area_fill+67j
		mov	ax, 1
		push	ax
		mov	ax, afill_count
		pop	cx
		shl	ax, cl		; *2
		push	ax
		mov	ax, afill_curpoint
		pop	si
		cmp	ax, si
		jl	area_fill2
		jmp	afill_gotminmax

area_fill2:				; CODE XREF: area_fill+27j
		push	word ptr afill_curpoint
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	afill_cury, ax
		mov	ax, afill_cury
		cmp	ax, afill_maxy
		jl	area_fill3
		jmp	area_fill4


area_fill3:				; CODE XREF: area_fill+3Dj
		mov	ax, afill_cury
		mov	afill_maxy, ax

area_fill4:				; CODE XREF: area_fill+3Fj
		mov	ax, afill_cury
		cmp	ax, afill_miny
		jg	area_fill5
		jmp	area_fill6


area_fill5:				; CODE XREF: area_fill+4Ej
		mov	ax, afill_cury
		mov	afill_miny, ax

area_fill6:				; CODE XREF: area_fill+50j
		mov	ax, 2
		push	ax
		lea	si, afill_curpoint
		mov	ax, [si]
		pop	cx
		add	ax, cx
		mov	[si], ax
		jmp	afill_getminmax
;
; Min/Max Y coords established
;
afill_gotminmax:				; CODE XREF: area_fill+29j
;;;		mov	ax, fill_style
		LAXW	fill_style
		cmp	ax, 1
		jz	area_fillsolid
		jmp	area_fillshaded


area_fillsolid:				; CODE XREF: area_fill+71j
		lea	si, fill_solid
;;;		mov	ax, si
		MOVAXSI
		mov	afill_pattern, ax
		jmp	area_fill10


area_fillshaded:				; CODE XREF: area_fill+73j
		mov	ax, 2
		push	ax
;;;		mov	ax, fill_interior
		LAXW	fill_interior
;;;		sub	ax, 1
		SUBAXW	1
		pop	cx
		shl	ax, cl
		shl	ax, 1
		push	ax
		lea	si, fill_stripes
		pop	ax
		add	si, ax
;;;		mov	ax, si
		MOVAXSI
		mov	afill_pattern, ax

area_fill10:				; CODE XREF: area_fill+7Fj
		mov	ax, afill_maxy
;;;		and	ax, 3
		ANDAXW	3
		mov	afill_curpoint, ax
		mov	ax, afill_curpoint
;;;		add	ax, 1
		ADDAXW	1
		mov	-12[bp], ax
		mov	si, afill_curpoint
		shl	si, 1
		push	si
		mov	ax, afill_pattern
		pop	si
		add	ax, si
		mov	afill_curpat, ax
		mov	ax, afill_maxy
		mov	afill_y, ax

area_fill11:				; CODE XREF: area_fill+327j
		mov	ax, afill_y
		cmp	ax, afill_miny
		jle	area_fill12
		jmp	area_fillend


area_fill12:				; CODE XREF: area_fill+CFj
		xor	ax, ax
		mov	afill_curinter, ax
		mov	ax, 0FFFFh
		mov	-20[bp], ax
		mov	ax, 4[bp]
;;;		sub	ax, 1
		SUBAXW	1
		mov	-6[bp],	ax
		xor	ax, ax
		mov	-42[bp], ax

area_fill13:				; CODE XREF: area_fill+26Bj
		mov	ax, -42[bp]
		cmp	ax, afill_count
		jle	area_fill14
		jmp	area_fill35


area_fill14:				; CODE XREF: area_fill+F4j
		mov	ax, -42[bp]
		mov	afill_cury, ax
		mov	ax, afill_cury
		cmp	ax, afill_count
		jz	area_fill15
		jmp	area_fill16


area_fill15:				; CODE XREF: area_fill+105j
		mov	ax, -20[bp]
		mov	afill_cury, ax

area_fill16:				; CODE XREF: area_fill+107j
		mov	ax, 1
		push	ax
		mov	ax, afill_cury
		pop	cx
		shl	ax, cl
		mov	-40[bp], ax
		lea	si, -40[bp]
		push	word ptr [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	-36[bp], ax
		lea	si, -40[bp]
		push	word ptr [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	-34[bp], ax
		mov	ax, afill_cury
		cmp	ax, -6[bp]
		jz	area_fill17
		jmp	area_fill18


area_fill17:				; CODE XREF: area_fill+145j
		xor	ax, ax
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	-32[bp], ax
		mov	ax, 1
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	-30[bp], ax
		jmp	area_fill19


area_fill18:				; CODE XREF: area_fill+147j
		lea	si, -40[bp]
		push	word ptr [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	-32[bp], ax
		push	word ptr -40[bp]
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	-30[bp], ax

area_fill19:				; CODE XREF: area_fill+161j
		lea	si, -28[bp]
		push	si
		lea	si, -18[bp]
		push	si
		push	word ptr -30[bp]
		push	word ptr -32[bp]
		push	word ptr -34[bp]
		push	word ptr -36[bp]
		push	word ptr afill_y
		call	fill_sub2
		add	sp, 0Eh
		mov	ax, -18[bp]
		cmp	ax, 1
		jz	area_fill20
		jmp	area_fill34


area_fill20:				; CODE XREF: area_fill+1A3j
		mov	ax, -30[bp]
		sub	ax, -34[bp]
		mov	-22[bp], ax
		mov	ax, -22[bp]
		cmp	ax, 0
		jg	area_fill21
		jmp	area_fill27


area_fill21:				; CODE XREF: area_fill+1B7j
		mov	ax, -20[bp]
		cmp	ax, 0
		jl	area_fill22
		jmp	area_fill23


area_fill22:				; CODE XREF: area_fill+1C2j
		mov	ax, -42[bp]
		mov	-20[bp], ax
		mov	ax, afill_y
		mov	-26[bp], ax
		xor	ax, ax
		mov	-18[bp], ax
		jmp	area_fill26


area_fill23:				; CODE XREF: area_fill+1C4j
		mov	si, -26[bp]
;;;		add	si, 1		; What's wrong with INC SI anyway?
		ADDSIW	1
		push	si
		mov	ax, afill_y
		pop	si
		cmp	ax, si
		jz	area_fill24
		jmp	area_fill25


area_fill24:				; CODE XREF: area_fill+1E9j
		mov	ax, afill_y
		mov	-26[bp], ax
		jmp	area_fill26


area_fill25:				; CODE XREF: area_fill+1EBj
		xor	ax, ax
		mov	-18[bp], ax

area_fill26:				; CODE XREF: area_fill+1D8j
					; area_fill+1F4j
		jmp	area_fill32


area_fill27:				; CODE XREF: area_fill+1B9j
		mov	ax, -20[bp]
		cmp	ax, 0
		jl	area_fill28
		jmp	area_fill29


area_fill28:				; CODE XREF: area_fill+205j
		mov	ax, -42[bp]
		mov	-20[bp], ax
		mov	ax, afill_y
;;;		sub	ax, 1
		SUBAXW	1
		mov	-26[bp], ax
		xor	ax, ax
		mov	-18[bp], ax
		jmp	area_fill32


area_fill29:				; CODE XREF: area_fill+207j
		mov	ax, afill_y
		cmp	ax, -26[bp]
		jz	area_fill30
		jmp	area_fill31


area_fill30:				; CODE XREF: area_fill+228j
		mov	ax, afill_y
;;;		sub	ax, 1
		SUBAXW	1
		mov	-26[bp], ax
		jmp	area_fill32


area_fill31:				; CODE XREF: area_fill+22Aj
		xor	ax, ax
		mov	-18[bp], ax

area_fill32:				; CODE XREF: area_fill+1FCj
					; area_fill+21Fj ...
		mov	ax, -18[bp]
		cmp	ax, 1
		jz	area_fill33
		jmp	area_fill34


area_fill33:				; CODE XREF: area_fill+245j
		lea	si, afill_curinter
		mov	ax, [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		shl	ax, 1
		push	ax
		lea	si, afill_intersect
		pop	ax
		add	si, ax
		mov	ax, -28[bp]
		mov	[si], ax

area_fill34:				; CODE XREF: area_fill+1A5j
					; area_fill+247j
		lea	si, -42[bp]
		mov	ax, [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		jmp	area_fill13


area_fill35:				; CODE XREF: area_fill+F6j
		lea	ax, afill_intersect
		push	ax
		push	word ptr afill_curinter
		call	fill_sub1
		add	sp, 4
		mov	ax, 0FFFEh
		push	ax
		lea	si, afill_curinter
		mov	ax, [si]
		pop	cx
		and	ax, cx
		mov	[si], ax
		xor	ax, ax
		mov	afill_curpoint, ax

area_fill36:				; CODE XREF: area_fill+2EFj
		mov	ax, afill_curpoint
		cmp	ax, afill_curinter
		jl	area_fill37
		jmp	area_fill38


area_fill37:				; CODE XREF: area_fill+295j
		mov	ax, afill_curpoint
		shl	ax, 1
		push	ax
		lea	si, afill_intersect
		pop	ax
		add	si, ax
		push	word ptr [si]
		pop	ax
		mov	-42[bp], ax
		push	write_mode
		push	fill_colour
		mov	ax, -42[bp]
;;;		and	ax, 0Fh
		ANDAXW	0Fh
		push	ax
		mov	si, afill_curpat
		push	word ptr [si]
		push	word ptr afill_y
		mov	ax, afill_curpoint
;;;		add	ax, 1
		ADDAXW	1
		shl	ax, 1
		push	ax
		lea	si, afill_intersect
		pop	ax
		add	si, ax
		push	word ptr [si]
		push	word ptr -42[bp]
		call	_fill_hline
		add	sp, 0Eh
		mov	ax, 2
		push	ax
		lea	si, afill_curpoint
		mov	ax, [si]
		pop	cx
		add	ax, cx
		mov	[si], ax
		jmp	area_fill36


area_fill38:				; CODE XREF: area_fill+297j
		mov	ax, -12[bp]
		cmp	ax, 4
		jl	area_fill39
		jmp	area_fill40


area_fill39:				; CODE XREF: area_fill+2F8j
		lea	si, -12[bp]
		mov	ax, [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		lea	si, afill_curpat
		mov	ax, [si]
;;;		add	word ptr [si], 2
		ADDPSI	2
		jmp	area_fill41


area_fill40:				; CODE XREF: area_fill+2FAj
		mov	ax, 1
		mov	-12[bp], ax
		mov	ax, afill_pattern
		mov	afill_curpat, ax

area_fill41:				; CODE XREF: area_fill+30Fj
		lea	si, afill_y
		mov	ax, [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		jmp	area_fill11


area_fillend:				; CODE XREF: area_fill+D1j

		if	NEEDSFLUSH
		 push	write_mode
		 call	_DRAWFLUSH
		 inc	sp
		 inc	sp
		endif

		mov	sp, bp
		pop	bp
		retn	





;		S u b r	o u t i	n e

fill_sub1:		; CODE XREF: area_fill+276p
		call	__csv

		db	0Ah

		mov	ax, 4[bp]
;;;		sub	ax, 1
		SUBAXW	1
		mov	-10[bp], ax

fill_sub1a:				; CODE XREF: fill_sub1+94j
		mov	ax, -10[bp]
		cmp	ax, 0
		jg	fill_sub1b
		jmp	fill_sub1h


fill_sub1b:				; CODE XREF: fill_sub1+14j
		mov	ax, 6[bp]
		mov	-4[bp],	ax
		mov	ax, -4[bp]
		mov	-2[bp],	ax
		lea	si, -2[bp]
		mov	ax, [si]
;;;		add	word ptr [si], 2
		ADDPSI	2
		xor	ax, ax
		mov	-8[bp],	ax

fill_sub1c:				; CODE XREF: fill_sub1+88j
		mov	ax, -8[bp]
		cmp	ax, -10[bp]
		jl	fill_sub1d
		jmp	fill_sub1g


fill_sub1d:				; CODE XREF: fill_sub1+39j
		mov	si, -2[bp]
		push	word ptr [si]
		mov	si, -4[bp]
		push	word ptr [si]
		pop	ax
		pop	si
		cmp	ax, si
		jg	fill_sub1e
		jmp	fill_sub1f


fill_sub1e:				; CODE XREF: fill_sub1+4Cj
		mov	si, -4[bp]
		push	word ptr [si]
		pop	ax
		mov	-6[bp],	ax
		mov	si, -2[bp]
		push	word ptr [si]
		mov	si, -4[bp]
		pop	ax
		mov	[si], ax
		mov	si, -2[bp]
		mov	ax, -6[bp]
		mov	[si], ax

fill_sub1f:				; CODE XREF: fill_sub1+4Ej
		lea	si, -4[bp]
		mov	ax, [si]
;;;		add	word ptr [si], 2
		ADDPSI	2
		lea	si, -2[bp]
		mov	ax, [si]
;;;		add	word ptr [si], 2
		ADDPSI	2
		lea	si, -8[bp]
		mov	ax, [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		jmp	fill_sub1c


fill_sub1g:				; CODE XREF: fill_sub1+3Bj
		lea	si, -10[bp]
		mov	ax, [si]
;;;		sub	word ptr [si], 1
		SUBPSI	1
		jmp	fill_sub1a


fill_sub1h:				; CODE XREF: fill_sub1+16j
		mov	sp, bp
		pop	bp
		retn	





;		S u b r	o u t i	n e

fill_sub2:		; CODE XREF: area_fill+197p
		call	__csv

		db	2Ah

		mov	si, 14[bp]
		xor	ax, ax
		mov	[si], ax
		mov	ax, 6[bp]
		mov	-18[bp], ax
		mov	ax, 10[bp]
		mov	-16[bp], ax
		mov	ax, 8[bp]
		mov	-14[bp], ax
		mov	ax, 12[bp]
		mov	-12[bp], ax
		mov	ax, -16[bp]
		sub	ax, -18[bp]
		mov	-38[bp], ax
		mov	ax, -12[bp]
		sub	ax, -14[bp]
		mov	-36[bp], ax
		mov	ax, -36[bp]
		cmp	ax, 0
		jz	fill_sub2a
		jmp	fill_sub2b


fill_sub2a:				; CODE XREF: fill_sub2+3Bj
		mov	sp, bp
		pop	bp
		retn	


fill_sub2b:				; CODE XREF: fill_sub2+3Dj
		mov	ax, 4[bp]
		sub	ax, -14[bp]
;;;		and	ax, 8000h
		ANDAXW	08000h
		mov	-8[bp],	ax
		mov	ax, 4[bp]
		sub	ax, -12[bp]
;;;		and	ax, 8000h
		ANDAXW	08000h
		mov	-6[bp],	ax
		xor	si, si
		push	si
		mov	ax, -8[bp]
		and	ax, -6[bp]
		pop	si
		cmp	ax, si
		jz	fill_sub2c
		jmp	fill_sub2h


fill_sub2c:				; CODE XREF: fill_sub2+6Aj
		mov	ax, -14[bp]
		cmp	ax, 4[bp]
		jz	fill_sub2d
		jmp	fill_sub2f


fill_sub2d:				; CODE XREF: fill_sub2+75j
		mov	si, 16[bp]
		mov	ax, -18[bp]
		mov	[si], ax
		mov	si, 14[bp]
		mov	ax, 1
		mov	[si], ax
		mov	sp, bp
		pop	bp
		retn	


fill_sub2e:
		jmp	fill_sub2h


fill_sub2f:				; CODE XREF: fill_sub2+77j
		mov	ax, -12[bp]
		cmp	ax, 4[bp]
		jz	fill_sub2g
		jmp	fill_sub2h


fill_sub2g:				; CODE XREF: fill_sub2+97j
		mov	si, 16[bp]
		mov	ax, -16[bp]
		mov	[si], ax
		mov	si, 14[bp]
		mov	ax, 1
		mov	[si], ax
		mov	sp, bp
		pop	bp
		retn	


fill_sub2h:				; CODE XREF: fill_sub2+6Cj
					; fill_sub2+8Ej ...
		mov	ax, -8[bp]
		cmp	ax, -6[bp]
		jz	fill_sub2i
		jmp	fill_sub2j


fill_sub2i:				; CODE XREF: fill_sub2+B6j
		mov	sp, bp
		pop	bp
		retn	


fill_sub2j:				; CODE XREF: fill_sub2+B8j
		mov	ax, -38[bp]
		cmp	ax, 0
		jge	fill_sub2k
		jmp	fill_sub2l


fill_sub2k:				; CODE XREF: fill_sub2+C5j
		mov	ax, -38[bp]
		push	ax
		jmp	fill_sub2m


fill_sub2l:				; CODE XREF: fill_sub2+C7j
		mov	ax, -38[bp]
		neg	ax
		push	ax

fill_sub2m:				; CODE XREF: fill_sub2+CEj
		pop	ax
		mov	-32[bp], ax
		mov	ax, -36[bp]
		cmp	ax, 0
		jge	fill_sub2n
		jmp	fill_sub2o


fill_sub2n:				; CODE XREF: fill_sub2+E1j
		mov	ax, -36[bp]
		push	ax
		jmp	fill_sub2p


fill_sub2o:				; CODE XREF: fill_sub2+E3j
		mov	ax, -36[bp]
		neg	ax
		push	ax

fill_sub2p:				; CODE XREF: fill_sub2+EAj
		pop	ax
		mov	-30[bp], ax
		xor	ax, ax
		mov	-2[bp],	ax
		mov	ax, -30[bp]
		cmp	ax, -32[bp]
		jg	fill_sub2q
		jmp	fill_sub2r


fill_sub2q:				; CODE XREF: fill_sub2+102j
		mov	ax, -18[bp]
		mov	-8[bp],	ax
		mov	ax, -14[bp]
		mov	-18[bp], ax
		mov	ax, -8[bp]
		mov	-14[bp], ax
		mov	ax, -16[bp]
		mov	-8[bp],	ax
		mov	ax, -12[bp]
		mov	-16[bp], ax
		mov	ax, -8[bp]
		mov	-12[bp], ax
		mov	ax, -32[bp]
		mov	-8[bp],	ax
		mov	ax, -30[bp]
		mov	-32[bp], ax
		mov	ax, -8[bp]
		mov	-30[bp], ax
		mov	ax, 1
		mov	-2[bp],	ax

fill_sub2r:				; CODE XREF: fill_sub2+104j
		mov	ax, 1
		push	ax
		mov	ax, -32[bp]
		pop	cx
		shl	ax, cl
		mov	-28[bp], ax
		mov	ax, 1
		push	ax
		mov	ax, -30[bp]
		pop	cx
		shl	ax, cl
		mov	-26[bp], ax
		mov	ax, -26[bp]
		sub	ax, -28[bp]
		mov	-8[bp],	ax
		mov	ax, 1
		mov	-4[bp],	ax
		mov	si, -36[bp]
		and	si, 8000h
		push	si
		mov	ax, -38[bp]
;;;		and	ax, 8000h
		ANDAXW	08000h
		pop	si
		cmp	ax, si
		jnz	fill_sub2s
		jmp	fill_sub2t


fill_sub2s:				; CODE XREF: fill_sub2+17Ej
		mov	ax, 0FFFFh
		mov	-4[bp],	ax

fill_sub2t:				; CODE XREF: fill_sub2+180j
		mov	ax, -14[bp]
		cmp	ax, -12[bp]
		jle	fill_sub2u
		jmp	fill_sub2v


fill_sub2u:				; CODE XREF: fill_sub2+18Fj
		mov	ax, -18[bp]
		mov	-42[bp], ax
		mov	ax, -14[bp]
		mov	-40[bp], ax
		mov	ax, -16[bp]
		mov	-10[bp], ax
		jmp	fill_sub2w


fill_sub2v:				; CODE XREF: fill_sub2+191j
		mov	ax, -16[bp]
		mov	-42[bp], ax
		mov	ax, -12[bp]
		mov	-40[bp], ax
		mov	ax, -18[bp]
		mov	-10[bp], ax

fill_sub2w:				; CODE XREF: fill_sub2+1A6j
		mov	ax, -26[bp]
		sub	ax, -32[bp]
		mov	-34[bp], ax

fill_sub2x:				; CODE XREF: fill_sub2+24Ej
		mov	ax, -42[bp]
		cmp	ax, -10[bp]
		jnz	fill_sub2y
		jmp	fill_sub2end


fill_sub2y:				; CODE XREF: fill_sub2+1CAj
		mov	ax, -34[bp]
		cmp	ax, 0
		jl	fill_sub2z
		jmp	fill_sub2aa


fill_sub2z:				; CODE XREF: fill_sub2+1D5j
		push	word ptr -26[bp]
		lea	si, -34[bp]
		mov	ax, [si]
		pop	cx
		add	ax, cx
		mov	[si], ax
		jmp	fill_sub2ab


fill_sub2aa:				; CODE XREF: fill_sub2+1D7j
		push	word ptr -8[bp]
		lea	si, -34[bp]
		mov	ax, [si]
		pop	cx
		add	ax, cx
		mov	[si], ax
		lea	si, -40[bp]
		mov	ax, [si]
;;;		add	word ptr [si], 1
		ADDPSI	1

fill_sub2ab:				; CODE XREF: fill_sub2+1E7j
		push	word ptr -4[bp]
		lea	si, -42[bp]
		mov	ax, [si]
		pop	cx
		add	ax, cx
		mov	[si], ax
		mov	ax, -2[bp]
		cmp	ax, 1
		jz	fill_sub2ac
		jmp	fill_sub2ad


fill_sub2ac:				; CODE XREF: fill_sub2+213j
		mov	ax, -42[bp]
		mov	-20[bp], ax
		mov	si, 16[bp]
		mov	ax, -40[bp]
		mov	[si], ax
		jmp	fill_sub2ae


fill_sub2ad:				; CODE XREF: fill_sub2+215j
		mov	si, 16[bp]
		mov	ax, -42[bp]
		mov	[si], ax
		mov	ax, -40[bp]
		mov	-20[bp], ax

fill_sub2ae:				; CODE XREF: fill_sub2+226j
		mov	ax, -20[bp]
		cmp	ax, 4[bp]
		jz	fill_sub2af
		jmp	fill_sub2xx


fill_sub2af:				; CODE XREF: fill_sub2+23Dj
		mov	si, 14[bp]
		mov	ax, 1
		mov	[si], ax
		mov	sp, bp
		pop	bp
		retn	


fill_sub2xx:				; CODE XREF: fill_sub2+23Fj
		jmp	fill_sub2x


fill_sub2end:				; CODE XREF: fill_sub2+1CCj
		mov	sp, bp
		pop	bp
		retn	



dline__ink	equ	(word ptr (12))[bp]
dline__y1	equ	(word ptr (10))[bp]
dline__x1	equ	(word ptr  (8))[bp]
dline__y0	equ	(word ptr  (6))[bp]
dline__x0	equ	(word ptr  (4))[bp]

dline_swapxy	equ	(word ptr  (-2))[bp]
dline_patbit	equ	(word ptr  (-4))[bp]
dline_c1_step	equ	(word ptr  (-6))[bp]
dline_tmp	equ	(word ptr  (-8))[bp]
dline_endcoord	equ	(word ptr (-10))[bp]
dline_y1	equ	(word ptr (-12))[bp]
dline_y0	equ	(word ptr (-14))[bp]
dline_x1	equ	(word ptr (-16))[bp]
dline_x0	equ	(word ptr (-18))[bp]
dline_pattern	equ	(word ptr (-20))[bp]
dline_curpat	equ	(word ptr (-22))[bp]
dline_ink	equ	(word ptr (-24))[bp]
dline_shift2	equ	(word ptr (-26))[bp]
dline_shift1	equ	(word ptr (-28))[bp]
dline_absdeltay	equ	(word ptr (-30))[bp]	;Absolute value of delta-Y
dline_absdeltax	equ	(word ptr (-32))[bp]	;Absolute value of delta-X
dline_step2	equ	(word ptr (-34))[bp]
dline_deltay	equ	(word ptr (-36))[bp]
dline_deltax	equ	(word ptr (-38))[bp]
dline_coord2	equ	(word ptr (-40))[bp]
dline_coord1	equ	(word ptr (-42))[bp]


;		S u b r	o u t i	n e

DRAWLINE:		; CODE XREF: v_pline+5Ep v_gtext+B9p
					; ...
		call	__csv

		db	2Ah

		mov	ax, dline__x0
		mov	dline_x0, ax
		mov	ax, dline__x1
		mov	dline_x1, ax
		mov	ax, dline__y0
		mov	dline_y0, ax
		mov	ax, dline__y1
		mov	dline_y1, ax
		mov	ax, dline_x1
		sub	ax, dline_x0
		mov	dline_deltax, ax
		mov	ax, dline_y1
		sub	ax, dline_y0
		mov	dline_deltay, ax
		mov	ax, dline_deltax
		cmp	ax, 0
		jge	drawline1
		jmp	drawline2


drawline1:				; CODE XREF: DRAWLINE+34j
		mov	ax, dline_deltax
		push	ax
		jmp	drawline3


drawline2:				; CODE XREF: DRAWLINE+36j
		mov	ax, dline_deltax
		neg	ax
		push	ax

drawline3:				; CODE XREF: DRAWLINE+3Dj
		pop	ax
		mov	dline_absdeltax, ax
		mov	ax, dline_deltay
		cmp	ax, 0
		jge	drawline4
		jmp	drawline5


drawline4:				; CODE XREF: DRAWLINE+50j
		mov	ax, dline_deltay
		push	ax
		jmp	drawline6


drawline5:				; CODE XREF: DRAWLINE+52j
		mov	ax, dline_deltay
		neg	ax
		push	ax

drawline6:				; CODE XREF: DRAWLINE+59j
		pop	ax
		mov	dline_absdeltay, ax
		xor	ax, ax
		mov	dline_swapxy,	ax
		mov	ax, dline_absdeltay
		cmp	ax, dline_absdeltax
		jg	drawline7
		jmp	drawline8


drawline7:				; CODE XREF: DRAWLINE+71j
		mov	ax, dline_x0
		mov	dline_tmp, ax
		mov	ax, dline_y0
		mov	dline_x0, ax
		mov	ax, dline_tmp
		mov	dline_y0, ax
		mov	ax, dline_x1
		mov	dline_tmp, ax
		mov	ax, dline_y1
		mov	dline_x1, ax
		mov	ax, dline_tmp
		mov	dline_y1, ax
		mov	ax, dline_absdeltax
		mov	dline_tmp,	ax
		mov	ax, dline_absdeltay
		mov	dline_absdeltax, ax
		mov	ax, dline_tmp
		mov	dline_absdeltay, ax
		mov	ax, 1
		mov	dline_swapxy, ax

drawline8:				; CODE XREF: DRAWLINE+73j
		mov	ax, 1
		push	ax
		mov	ax, dline_absdeltax
		pop	cx
		shl	ax, cl
		mov	dline_shift1, ax
		mov	ax, 1
		push	ax
		mov	ax, dline_absdeltay
		pop	cx
		shl	ax, cl
		mov	dline_shift2, ax
		mov	ax, dline_shift2
		sub	ax, dline_shift1
		mov	dline_tmp, ax
		mov	ax, 1
		mov	dline_c1_step, ax
		mov	si, dline_deltay
		and	si, 8000h
		push	si
		mov	ax, dline_deltax
;;;		and	ax, 8000h
		ANDAXW	08000h
		pop	si
		cmp	ax, si
		jnz	drawline9
		jmp	drawline10


drawline9:				; CODE XREF: DRAWLINE+EDj
		mov	ax, -1
		mov	dline_c1_step, ax

drawline10:				; CODE XREF: DRAWLINE+EFj
		mov	ax, dline_y0
		cmp	ax, dline_y1
		jle	drawline11
		jmp	drawline12


drawline11:				; CODE XREF: DRAWLINE+FEj
		mov	ax, dline_x0
		mov	dline_coord1, ax
		mov	ax, dline_y0
		mov	dline_coord2, ax
		mov	ax, dline_x1
		mov	dline_endcoord, ax
		jmp	drawline13


drawline12:				; CODE XREF: DRAWLINE+100j
		mov	ax, dline_x1
		mov	dline_coord1, ax
		mov	ax, dline_y1
		mov	dline_coord2, ax
		mov	ax, dline_x0
		mov	dline_endcoord, ax

drawline13:				; CODE XREF: DRAWLINE+115j
		mov	ax, dline_shift2
		sub	ax, dline_absdeltax
		mov	dline_step2, ax
;;;		mov	ax, line_type
;;;		sub	ax, 1
		LAXW	line_type
		SUBAXW	1
		shl	ax, 1
		push	ax
		lea	si, line_types
		pop	ax
		add	si, ax
		push	word ptr [si]
		pop	ax
		mov	dline_pattern, ax
		mov	ax, 1
		push	ax
		mov	ax, dline_pattern
		pop	cx
		shl	ax, cl
		mov	dline_curpat, ax
		mov	ax, 2
		mov	dline_patbit, ax
		mov	ax, dline_swapxy
		cmp	ax, 1
		jz	drawline14
		jmp	drawline15


drawline14:				; CODE XREF: DRAWLINE+164j
		push	write_mode
		push	word ptr dline__ink
		push	word ptr dline_coord1
		push	word ptr dline_coord2
		call	_PUTPIXEL
		add	sp, 8
		jmp	drawline16


drawline15:				; CODE XREF: DRAWLINE+166j
		push	write_mode
		push	word ptr dline__ink
		push	word ptr dline_coord2
		push	word ptr dline_coord1
		call	_PUTPIXEL
		add	sp, 8

drawline16:				; CODE XREF: DRAWLINE+17Cj
					; DRAWLINE+25Dj
		mov	ax, dline_coord1
		cmp	ax, dline_endcoord
		jnz	drawline17
		jmp	drawline_end


drawline17:				; CODE XREF: DRAWLINE+198j
		mov	ax, dline_step2
		cmp	ax, 0
		jl	drawline18
		jmp	drawline19


drawline18:				; CODE XREF: DRAWLINE+1A3j
		push	word ptr dline_shift2
		lea	si, dline_step2
		mov	ax, [si]
		pop	cx
		add	ax, cx
		mov	[si], ax
		jmp	drawline20


drawline19:				; CODE XREF: DRAWLINE+1A5j
		push	word ptr dline_tmp
		lea	si, dline_step2
		mov	ax, [si]
		pop	cx
		add	ax, cx
		mov	[si], ax
		lea	si, dline_coord2
		mov	ax, [si]
;;;		add	word ptr [si], 1
		ADDPSI	1

drawline20:				; CODE XREF: DRAWLINE+1B5j
		push	word ptr dline_c1_step
		lea	si, dline_coord1
		mov	ax, [si]
		pop	cx
		add	ax, cx
		mov	[si], ax
		xor	ax, ax
		mov	dline_ink, ax
		xor	si, si
		push	si
		mov	ax, dline_curpat
;;;		and	ax, 8000h
		ANDAXW	08000h
		pop	si
		cmp	ax, si
		jnz	drawline21
		jmp	drawline22


drawline21:				; CODE XREF: DRAWLINE+1EDj
		mov	ax, dline__ink
		mov	dline_ink, ax

drawline22:				; CODE XREF: DRAWLINE+1EFj
		mov	ax, dline_swapxy
		cmp	ax, 1
		jz	drawline23
		jmp	drawline24


drawline23:				; CODE XREF: DRAWLINE+1FEj
		push	write_mode
		push	word ptr dline_ink
		push	word ptr dline_coord1
		push	word ptr dline_coord2
		call	_PUTPIXEL
		add	sp, 8
		jmp	drawline25


drawline24:				; CODE XREF: DRAWLINE+200j
		push	write_mode
		push	word ptr dline_ink
		push	word ptr dline_coord2
		push	word ptr dline_coord1
		call	_PUTPIXEL
		add	sp, 8

drawline25:				; CODE XREF: DRAWLINE+216j
		mov	ax, dline_patbit
		cmp	ax, 16
		jl	drawline26
		jmp	drawline27


drawline26:				; CODE XREF: DRAWLINE+232j
		lea	si, dline_patbit
		mov	ax, [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		mov	ax, 1
		push	ax
		lea	si, dline_curpat
		mov	ax, [si]
		pop	cx
		shl	ax, cl
		mov	[si], ax
		jmp	drawline28


drawline27:				; CODE XREF: DRAWLINE+234j
		mov	ax, 1
		mov	dline_patbit, ax
		mov	ax, dline_pattern
		mov	dline_curpat, ax

drawline28:				; CODE XREF: DRAWLINE+24Ej
		jmp	drawline16


drawline_end:				; CODE XREF: DRAWLINE+19Aj
		if	NEEDSFLUSH
		 push	write_mode
		 call	_DRAWFLUSH
		 inc	sp
		 inc	sp
		endif
		mov	sp, bp
		pop	bp
		retn	



gtext__dir	equ	(word ptr (14))[bp]
gtext__height	equ	(word ptr (12))[bp]
gtext__buf	equ	(word ptr (10))[bp]	;Buffer (if gtext__len < 0)
gtext__len	equ	(word ptr  (8))[bp]	
gtext__y	equ	(word ptr  (6))[bp]
gtext__x	equ	(word ptr  (4))[bp]

gtext_charbits	equ	(word ptr  (-2))[bp]
gtext_curpos	equ	(word ptr  (-4))[bp]
gtext_pixely	equ	(word ptr  (-6))[bp]
gtext_pixelx	equ	(word ptr  (-8))[bp]
gtext_charw	equ	(word ptr (-10))[bp]
gtext_y		equ	(word ptr (-12))[bp]
gtext_x		equ	(word ptr (-14))[bp]
gtext_y1	equ	(word ptr (-16))[bp]
gtext_x1	equ	(word ptr (-18))[bp]
gtext_len	equ	(word ptr (-20))[bp]
gtext_mask	equ	(word ptr (-22))[bp]
gtext_clr	equ	(word ptr (-24))[bp]
gtext_strpos	equ	(word ptr (-26))[bp]
gtext_bit	equ	(word ptr (-28))[bp]
gtext_curchar	equ	(word ptr (-30))[bp]
gtext_vertical	equ	(word ptr (-32))[bp]
gtext_col	equ	(word ptr (-34))[bp]
gtext_row	equ	(word ptr (-36))[bp]
gtext_v1	equ	(word ptr (-38))[bp]
gtext_v2	equ	(word ptr (-40))[bp]

;		S u b r	o u t i	n e

D_GTEXT:		; CODE XREF: v_gtext+29p vrq_string+85p
		call	__csv

		db	28h

		mov	ax, gtext__x
		mov	gtext_x, ax
		mov	ax, gtext__y
		mov	gtext_y, ax
		xor	ax, ax
		mov	gtext_vertical, ax
		xor	si, si
		push	si
		mov	ax, gtext__dir
;;;		and	ax, 1
		ANDAXW	1
		pop	si
		cmp	ax, si
		jnz	gtext1
		jmp	gtext2


gtext1:					; CODE XREF: D_GTEXT+22j
		mov	ax, 1
		mov	gtext_vertical, ax
		mov	ax, gtext__y
		mov	gtext_x, ax
		mov	ax, gtext__x
		mov	gtext_y, ax

gtext2:					; CODE XREF: D_GTEXT+24j
		mov	ax, gtext__dir
		shl	ax, 1
		push	ax
		lea	si, text_v1
		pop	ax
		add	si, ax
		push	word ptr [si]
		pop	ax
		mov	gtext_v1, ax
		mov	ax, gtext__dir
		shl	ax, 1
		push	ax
		lea	si, text_v2
		pop	ax
		add	si, ax
		push	word ptr [si]
		pop	ax
		mov	gtext_v2, ax
		push	word ptr gtext__height
		push	text_v4
		call	_multiply
		add	sp, 4
		mov	gtext_charw, ax
		mov	ax, gtext__dir
		cmp	ax, 2
		jge	gtext3
		jmp	gtext4


gtext3:					; CODE XREF: D_GTEXT+75j
		mov	ax, gtext_charw
		neg	ax
		mov	gtext_charw, ax

gtext4:					; CODE XREF: D_GTEXT+77j
		xor	si, si
		push	si
		mov	ax, gtext__dir
		shl	ax, 1
		push	ax
		lea	si, text_v3
		pop	ax
		add	si, ax
		push	word ptr [si]
		pop	ax
		pop	si
		cmp	ax, si
		jg	gtext5
		jmp	gtext6


gtext5:					; CODE XREF: D_GTEXT+98j
		push	word ptr gtext__height
		lea	si, gtext_y
		mov	ax, [si]
		pop	cx
		add	ax, cx
		mov	[si], ax
		jmp	gtext7


gtext6:					; CODE XREF: D_GTEXT+9Aj
		push	word ptr gtext__height
		lea	si, gtext_y
		mov	ax, [si]
		pop	cx
		sub	ax, cx
		mov	[si], ax

gtext7:					; CODE XREF: D_GTEXT+AAj
		xor	ax, ax
		mov	gtext_curpos, ax
		push	word ptr gtext__len
		call	_abs
		inc	sp
		inc	sp
		mov	gtext_len, ax
		mov	ax, 1
		mov	gtext_strpos, ax

gtext8:					; CODE XREF: D_GTEXT+296j
		mov	ax, gtext_strpos
		cmp	ax, gtext_len
		jle	gtext9
		jmp	gtext_end


gtext9:					; CODE XREF: D_GTEXT+D6j
		mov	ax, gtext__len
		cmp	ax, 0
		jg	gtext10
		jmp	gtext11


gtext10:				; CODE XREF: D_GTEXT+E1j
		push	word ptr gtext_curpos
		call	_read_intin
		inc	sp
		inc	sp
		mov	gtext_curchar, ax
		jmp	gtext12


gtext11:				; CODE XREF: D_GTEXT+E3j
		mov	ax, gtext_curpos
		shl	ax, 1
		push	ax
		mov	si, gtext__buf
		pop	ax
		add	si, ax
		push	word ptr [si]
		pop	ax
		mov	gtext_curchar, ax

gtext12:				; CODE XREF: D_GTEXT+F1j
		mov	ax, 127
		push	ax
		mov	ax, 32
		push	ax
		push	word ptr gtext_curchar
		call	_clamp
		add	sp, 6
;;;		sub	ax, 20h
		SUBAXW	20h
		mov	gtext_curchar, ax
		mov	ax, 3
		push	ax
		mov	ax, gtext_curchar
		pop	cx
		shl	ax, cl		; char * 8
		push	ax
		lea	si, font	; + font
		pop	ax
		add	si, ax
;;;		mov	ax, si
		MOVAXSI
		mov	gtext_charbits,	ax
		mov	ax, gtext_x
		mov	gtext_x1, ax
		mov	ax, gtext_y
		mov	gtext_y1, ax
		mov	ax, 1
		mov	gtext_curchar, ax

gtext13:				; CODE XREF: D_GTEXT+274j
		mov	ax, gtext_curchar
		cmp	ax, 8
		jle	gtext14
		jmp	gtext37


gtext14:				; CODE XREF: D_GTEXT+14Dj
		mov	ax, 1
		mov	gtext_col, ax

gtext15:				; CODE XREF: D_GTEXT+25Fj
		mov	ax, gtext_col
		cmp	ax, gtext__height
		jle	gtext16
		jmp	gtext36


gtext16:				; CODE XREF: D_GTEXT+15Ej
		mov	si, gtext_charbits
		mov	al, [si]
		mov	ah, 0
		mov	gtext_mask, ax
		mov	ax, 1
		mov	gtext_bit, ax

gtext17:				; CODE XREF: D_GTEXT+240j
		mov	ax, gtext_bit
		cmp	ax, 6
		jle	gtext18
		jmp	gtext35


gtext18:				; CODE XREF: D_GTEXT+179j
		mov	ax, gtext_mask
;;;		and	ax, 1
		ANDAXW	1
		mov	gtext_clr, ax
		mov	ax, gtext_clr
		cmp	ax, 0
		jnz	gtext19
		jmp	gtext20


gtext19:				; CODE XREF: D_GTEXT+18Ej
;;;		mov	ax, text_colour
		LAXW	text_colour
		mov	gtext_clr, ax

gtext20:				; CODE XREF: D_GTEXT+190j
		mov	ax, 1
		push	ax
		lea	si, gtext_mask
		mov	ax, [si]
		pop	cx
		sar	ax, cl
		mov	[si], ax
		mov	ax, 1
		mov	gtext_row, ax

gtext21:				; CODE XREF: D_GTEXT+234j
		mov	ax, gtext_row
		cmp	ax, gtext__height
		jle	gtext22
		jmp	gtext34


gtext22:				; CODE XREF: D_GTEXT+1B4j
		mov	ax, gtext_vertical
		cmp	ax, 1
		jz	gtext23
		jmp	gtext24


gtext23:				; CODE XREF: D_GTEXT+1BFj
		mov	ax, gtext_y1
		mov	gtext_pixelx,	ax
		mov	ax, gtext_x1
		mov	gtext_pixely,	ax
		jmp	gtext25


gtext24:				; CODE XREF: D_GTEXT+1C1j
		mov	ax, gtext_x1
		mov	gtext_pixelx,	ax
		mov	ax, gtext_y1
		mov	gtext_pixely,	ax

gtext25:				; CODE XREF: D_GTEXT+1D0j
		mov	ax, gtext_pixelx
		cmp	ax, 0
		jge	gtext26
		jmp	gtext27


gtext26:				; CODE XREF: D_GTEXT+1E5j
		mov	ax, gtext_pixely
		cmp	ax, 0
		jge	gtext28

gtext27:				; CODE XREF: D_GTEXT+1E7j
		jmp	gtext29


gtext28:				; CODE XREF: D_GTEXT+1F0j
		mov	ax, gtext_pixelx
		cmp	ax, XRESMX
		jle	gtext30

gtext29:				; CODE XREF: D_GTEXT+1F2j
		jmp	gtext31


gtext30:				; CODE XREF: D_GTEXT+1FBj
		mov	ax, gtext_pixely
		cmp	ax, YRESMX
		jle	gtext32

gtext31:				; CODE XREF: D_GTEXT+1FDj
		jmp	gtext33


gtext32:				; CODE XREF: D_GTEXT+206j
		push	write_mode
		push	word ptr gtext_clr
		push	word ptr gtext_pixely
		push	word ptr gtext_pixelx
		call	_PUTPIXEL
		add	sp, 8

gtext33:				; CODE XREF: D_GTEXT+208j
		push	word ptr gtext_v1
		lea	si, gtext_x1
		mov	ax, [si]
		pop	cx
		add	ax, cx
		mov	[si], ax
		lea	si, gtext_row
		mov	ax, [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		jmp	gtext21


gtext34:				; CODE XREF: D_GTEXT+1B6j
		lea	si, gtext_bit
		mov	ax, [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		jmp	gtext17


gtext35:				; CODE XREF: D_GTEXT+17Bj
		mov	ax, gtext_x
		mov	gtext_x1, ax
		push	word ptr gtext_v2
		lea	si, gtext_y1
		mov	ax, [si]
		pop	cx
		add	ax, cx
		mov	[si], ax
		lea	si, gtext_col
		mov	ax, [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		jmp	gtext15


gtext36:				; CODE XREF: D_GTEXT+160j
		lea	si, gtext_charbits
		mov	ax, [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		lea	si, gtext_curchar
		mov	ax, [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		jmp	gtext13


gtext37:				; CODE XREF: D_GTEXT+14Fj
		push	word ptr gtext_charw
		lea	si, gtext_x
		mov	ax, [si]
		pop	cx
		add	ax, cx
		mov	[si], ax
		lea	si, gtext_curpos
		mov	ax, [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		lea	si, gtext_strpos
		mov	ax, [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		jmp	gtext8


gtext_end:				; CODE XREF: D_GTEXT+D8j
		if	NEEDSFLUSH
		 push	write_mode
		 call	_DRAWFLUSH
		 inc	sp
		 inc	sp
		endif
		mov	sp, bp
		pop	bp
		retn	




gtext38:
		mov	sp, bp
		pop	bp
		retn	




		dseg
	

_lbss		dw	offset fill_colour	; DATA XREF: cseg:0031r
_bsslen		dw	offset registers + 16 - offset fill_colour	; DATA XREF: cseg:0036r
gsx_mcb?	dw	80h			; DATA XREF: cseg:000Eo
stack_base	dw	80h			; DATA XREF: __csv+Br
p_contrl	dw 	0,0			; DATA XREF: cseg:005Eo _read_contrl+5r
					; ...
p_intin		dw	0,0			; DATA XREF: _read_intin+5r
p_ptsin		dw	0,0			; DATA XREF: _read_ptsin+5r
p_intout	dw	0,0			; DATA XREF: _write_intout+5r
p_ptsout	dw	0,0			; DATA XREF: _write_ptsout+5r
aNoMemory	db	0Dh,0Ah		; DATA XREF: cseg:0072o
		db	'No memory$'
		dw	0
numeric_error	db	0
		db	0,0,0
asc_2C1_12E	db	0Ah
		db	0Dh,'$'
fill_solid	db	0FFh, 0FFh, 0FFh, 0FFh, 0FFh, 0FFh, 0FFh, 0FFh
fill_stripes	db	033h, 033h, 033h, 033h, 033h, 033h, 033h, 033h
		db	000h, 000h, 000h, 000h, 0FFh, 0FFh, 0FFh, 0FFh
		db	0CCh, 0CCh, 066h, 066h, 033h, 033h, 099h, 099h
		db	033h ,033h, 066h, 066h, 0CCh, 0CCh, 099h, 099h
		db	0AAh, 0AAh, 055h, 055h, 0AAh, 0AAh, 055h, 055h
char_widths	dw	5, 10, 15, 20, 25	; DATA XREF: vst_height+86o
char_heights	dw	7, 14, 21, 28, 35	; DATA XREF: vst_height+12o
					; vst_height+9Eo
cell_widths	dw	6, 12, 18, 24, 30	; DATA XREF: vst_height+B7o
					; vrq_string+8Bo
cell_heights	dw	8, 16, 24, 32, 40	; DATA XREF: vst_height+D0o

		if  NUM_COLORS eq 4

initreds	dw	0, 0, 1000, 1000	;Initial red values
initgreens	dw	0, 1000, 0, 1000	;Initial green values
initblues	dw	0, 0, 0, 0		;Initial blue values

		endif

DEV_TAB		dw	XRESMX			; X resolution
		dw	YRESMX			; Y resolution
		dw	1			; Character scaling
		dw	XSIZE			; Pixel	width
		dw	YSIZE			; Pixel	height
		dw	5			; Character sizes
		dw	7			; Line styles
		dw	1			; Line widths
		dw	5			; Marker types
		dw	1			; Marker sizes
		dw	1			; Text fonts
		dw	5			; Area patterns
		dw	5			; Crosshatch patterns
		dw	NUM_COLORS		; Number of colours
		dw	1			; Number of GDPs
		dw	1			; GDP 1	= bar
		dw	0FFFFh, 0FFFFh, 0FFFFh
		dw	0FFFFh, 0FFFFh, 0FFFFh
		dw	0FFFFh, 0FFFFh, 0FFFFh
		dw	3			; GDP attributes
		dw	0FFFFh, 0FFFFh, 0FFFFh
		dw	0FFFFh, 0FFFFh, 0FFFFh
		dw	0FFFFh, 0FFFFh, 0FFFFh

		if 	NUM_COLORS gt 2
		 dw	1			; Colour capability
		else
		 dw	0			; Colour capability
		endif
		dw	1			; Text rotation?
		dw	1			; Polygon fill?
		dw	1			; Cell array?
		dw	NUM_COLORS		; Palette size
		dw	1			; Number of locators
		dw	0			; Number of valuators
		dw	1			; Number of choices
		dw	1			; Number of strings
		dw	2			; Workstation type
SIZ_TAB		dw	0, 7			; DATA XREF: v_opnwk+55o
					; Min char height
		dw	0, 35		; Max char height
		dw	1, 0			; Min line width
		dw	1, 0			; Max line width
		dw	0, 8			; Min marker height
		dw	0, 8			; Max marker height
esc_a		db	1Bh,	'A'             ; DATA XREF: v_curup+1Co
esc_b		db	1Bh,	'B'             ; DATA XREF: v_curdown+1Co
					; v_eeos+57o
esc_c		db	1Bh,	'C'             ; DATA XREF: v_curright+1Co
esc_d		db	1Bh,	'D'             ; DATA XREF: v_curleft+1Co
esc_h		db	1Bh,	'H'             ; DATA XREF: v_enter_cur+Bo
					; v_curhomeo
		db	1Bh,	'J'
esc_k		db	1Bh,	'K'             ; DATA XREF: v_eeoso v_eeos+66o
					; ...
esc_y		db	1Bh,	'Y'             ; DATA XREF: v_eeos+1Bo v_eeos+81o
					; ...
esc_rvon	db	1Bh,	'b', '`'        ; DATA XREF: v_rvono
		db	1Bh,	'c', 'g'
esc_rvoff	db	1Bh,	'b', 'g'        ; DATA XREF: v_rvoffo
		db	1Bh,	'c', '`'
init_scr	db	1Bh,	3Ah, 3Bh, 1Bh, 70h, 0, 1Bh, 3Ah, 3Ch, 1Bh, 71h,	0, 1Bh,	3Ah, 3Dh
					; DATA XREF: v_opnwk+220o
		db	1Bh,	72h, 0,	1Bh, 3Ah, 3Eh, 1Bh, 73h, 0, 1Bh, 3Ah, 3Fh, 1Bh,	74h, 0
		db	1Bh,	3Ah, 40h, 1Bh, 75h, 0, 1Bh, 3Ah, 41h, 1Bh, 76h,	0, 1Bh,	3Ah, 42h
		db	1Bh,	77h, 0,	1Bh, 3Ah, 43h, 1Bh, 78h, 0, 1Bh, 3Ah, 44h, 1Bh,	79h, 0
		db	1Bh,	3Ah, 48h, 1Bh, 41h, 0, 1Bh, 3Ah, 4Bh, 1Bh, 44h,	0, 1Bh,	3Ah, 4Dh
		db	1Bh,	43h, 0,	1Bh, 3Ah, 50h, 1Bh, 42h, 0, 1Bh, 3Ah, 52h, 1Bh,	52h, 0
line_types	dw	0FFFFh		; DATA XREF: DRAWLINE+13Eo
		dw	0F00Fh
		dw	8888h
		dw	0E10Fh
		dw	0C3C3h
		dw	0E247h
		dw	9999h
text_v1		dw	1, 1, 0FFFFh, 0FFFFh
text_v2		dw	1, 0FFFFh, 0FFFFh, 1
text_v3		dw	0FFFFh, 1, 1, 0FFFFh
text_v4		dw	6			; DATA XREF: D_GTEXT+62r

