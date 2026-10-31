		cseg

;
; The code generator used for some of this driver emits an alternative
; encoding for MOV AX, SI and MOV SI, AX
;
CodeMacro	MOVAX_SI
		db	89h
		db	0F0h
EndM

CodeMacro	MOVSI_AX
		db	89h
		db	0C6h
EndM

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
		mov	ax, es:(Word Ptr -2)[bx+si]
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
		mov	ax, es:(Word Ptr -2)[bx+si]
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
		mov	ax, es:(Word Ptr -2)[bx+si]
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
		mov	es:(Word Ptr -2)[bx+si], ax
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
		mov	es:(Word Ptr -2)[bx+si], ax
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
		mov	es:(Word Ptr -2)[bx+si], ax
		pop	si
		pop	es
		pop	bp
		retn	




;		S u b r	o u t i	n e

SCREEN:		; CODE XREF: cseg:0069p
		call	__csv

		db	2

		xor	ax, ax
		push	ax
		mov	ax, 3
		push	ax
		call	_write_contrl
		add	sp, 4
		mov	ax, 1
		push	ax
		call	_read_contrl
		inc	sp
		inc	sp
		push	ax
		jmp	scr_switch

v_opnwk:	call	d_opnwk
		jmp	v_nop
;
v_clswk:	jmp	v_nop
;
v_clrwk:	call	d_clrwk
		jmp	v_nop
;
v_updwk:	jmp	v_nop
;
v_esc:		call	d_esc
		jmp	v_nop
;
v_pline:	xor	ax, ax
		push	ax
		call	d_pline
		inc	sp	
		inc	sp
		jmp	v_nop
;
v_pmarker:	call	d_pmarker
		jmp	v_nop
;
v_gtext:	call	m_gtext
		jmp	v_nop
;
v_fillarea:	mov	ax, 1
		push	ax
		call	d_pline
		inc	sp
		inc	sp
		jmp	v_nop
;
v_cellarray:	call	d_cellarray
		jmp	v_nop
;
v_gdp:		call	d_gdp
		jmp	v_nop
;
vst_height:	mov	ax, 0Fh
		push	ax
		xor	ax, ax
		push	ax
		mov	si, 7
		push	si
		mov	ax, 2
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		pop	si
		or	si, si
		jz	vst_height1
		cwd
		idiv	si
vst_height1:
;;;		sub	ax, 1
		SUBAXW	1	
		push	ax
		call	_clamp
		add	sp, 6
;;;		mov	text_height, ax
		SAXW	text_height
		mov	ax, 2
		push	ax
		mov	ax, 3
		push	ax
		call	_write_contrl
		add	sp, 4
;;;		mov	ax, text_height
;;;		add	ax, 1
		LAXW	text_height
		ADDAXW	1
		push	ax
		mov	ax, 5	;Write 5 * height to ptsout
		pop	si
		mul	si
		push	ax
		mov	ax, 1
		push	ax
		call	_write_ptsout
		add	sp, 4

;;;		mov	ax, text_height
;;;		add	ax, 1
		LAXW	text_height
		ADDAXW	1
		push	ax
		mov	ax, 7	;Write 7 * height to ptsout
		pop	si
		mul	si
		push	ax
		mov	ax, 2
		push	ax
		call	_write_ptsout
		add	sp, 4

;;;		mov	ax, text_height
;;;		add	ax, 1
		LAXW	text_height
		ADDAXW	1
		push	ax
		mov	ax, 6	;Write 6 * height to ptsout
		pop	si
		mul	si
		push	ax
		mov	ax, 3
		push	ax
		call	_write_ptsout
		add	sp, 4

;;;		mov	ax, text_height
;;;		add	ax, 1
		LAXW	text_height
		ADDAXW	1
		push	ax
		mov	ax, 8	;Write 8 * height to ptsout
		pop	si
		mul	si
		push	ax
		mov	ax, 4
		push	ax
		call	_write_ptsout
		add	sp, 4
		jmp	v_nop
;
vst_direction:	
		mov	si, 450
		push	si
		mov	ax, 1
		push	ax
		call	_read_intin	; (angle + 450)
		inc	sp
		inc	sp
;;;		add	ax, 900
		ADDAXW	900
		pop	si
		or	si, si
		jz	vst_dir1
		cwd
		idiv	si
vst_dir1:	ANDAXW	7
		SAXW	text_direction
		mov	ax, 450
		push	ax
		LAXW	text_direction
		SUBAXW	2
		ANDAXW	7
		pop	si
		mul	si
		push	ax
		mov	ax, 1
		push	ax
		call	_write_intout
		add	sp, 4
		jmp	v_nop
;
vs_color:	jmp	v_nop

vsl_type:
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
		mov	ax, 1	
		push	ax
		call	_write_intout
		add	sp, 4
		jmp	v_nop
;
vsl_width:	mov	ax, 1	
		push	ax
		mov	ax, 3
		push	ax
		call	_write_contrl
		add	sp, 4
		mov	ax, 1
		push	ax
		mov	ax, 1
		push	ax
		call	_write_ptsout
		add	sp, 4
		xor	ax, ax	
		push	ax
		mov	ax, 2
		push	ax
		call	_write_ptsout
		add	sp, 4
		jmp	v_nop
;
vsl_color:
		mov	ax, NUM_COLORS-1
		push	ax
		xor	ax, ax
		push	ax
		mov	ax, 1	
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
		mov	ax, 1
		push	ax
		call	_write_intout
		add	sp, 4
		jmp	v_nop
;

vsm_type:
		mov	ax, 1
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
		mov	ax, 1	
		push	ax
		call	_write_intout
		add	sp, 4
		jmp	v_nop
;
vsm_height:	mov	ax, 0Fh
		push	ax
		xor	ax, ax
		push	ax
		mov	si, 5
		push	si
		mov	ax, 2
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		pop	si
		or	si, si
		jz	vsm_height1
		cwd
		idiv	si
vsm_height1:
;;;		sub	ax, 1
		SUBAXW	1	
		push	ax
		call	_clamp
		add	sp, 6
;;;		mov	marker_height, ax
		SAXW	marker_height
		mov	ax, 1
		push	ax
		mov	ax, 3
		push	ax
		call	_write_contrl
		add	sp, 4
		xor	ax, ax
		push	ax
		mov	ax, 1
		push	ax
		call	_write_ptsout
		add	sp, 4
		LAXW	marker_height
		ADDAXW	1	
		push	ax
		mov	ax, 5
		pop	si
		mul	si
		push	ax
		mov	ax, 2
		push	ax
		call	_write_ptsout
		add	sp, 4
		jmp	v_nop

vsm_color:
		mov	ax, NUM_COLORS-1
		push	ax
		xor	ax, ax
		push	ax
		mov	ax, 1
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
		mov	ax, 1	
		push	ax
		call	_write_intout
		add	sp, 4
		jmp	v_nop
;
vst_font:	mov	ax, 1
		push	ax
		mov	ax, 1
		push	ax
		call	_write_intout
		add	sp, 4
		jmp	v_nop

vst_color:
		mov	ax, NUM_COLORS-1
		push	ax
		xor	ax, ax
		push	ax
		mov	ax, 1
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
		mov	ax, 1
		push	ax
		call	_write_intout
		add	sp, 4
		jmp	v_nop
;
;
vsf_style:
		mov	ax, 1
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
		push	fill_style
		mov	ax, 1
		push	ax
		call	_write_intout
		add	sp, 4
		jmp	v_nop


vsf_interior:
		mov	ax, 1
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
		mov	ax, 1
		push	ax
		call	_write_intout
		add	sp, 4
		jmp	v_nop

;
vsf_color:
		mov	ax, NUM_COLORS-1
		push	ax
		xor	ax, ax
		push	ax
		mov	ax, 1
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
		mov	ax, 1
		push	ax
		call	_write_intout
		add	sp, 4
		jmp	v_nop
;
vqc_index	equ	(word ptr (-2))[bp]

vq_color:	mov	ax, 1
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
		mov	vqc_index, ax
		mov	ax, vqc_index
		cmp	ax, 0
		jl	vq_color1
		jmps	vq_color2
;
vq_color1:	jmp	vq_color3
;
vq_color2:	mov	ax, vqc_index
		cmp	ax, NUM_COLORS - 1
		jg	vq_color3
		jmp	vq_color4
;
vq_color3:	mov	ax, -1
		push	ax
		mov	ax, 1
		push	ax
		call	_write_ptsout
		add	sp, 4
		jmp	vq_color5
;
vq_color4:	push	word ptr vqc_index
		mov	ax, 1
		push	ax
		call	_write_ptsout
		add	sp, 4
		mov	ax, vqc_index
		shl	ax, 1
		push	ax
		lea	si, initreds
		pop	ax
		add	si, ax
		push	word ptr [si]
		mov	ax, 2
		push	ax
		call	_write_ptsout
		add	sp, 4

		mov	ax, vqc_index
		shl	ax, 1
		push	ax
		lea	si, initgreens
		pop	ax
		add	si, ax
		push	word ptr [si]
		mov	ax, 3
		push	ax
		call	_write_ptsout
		add	sp, 4

		mov	ax, vqc_index
		shl	ax, 1
		push	ax
		lea	si, initblues
		pop	ax
		add	si, ax
		push	word ptr [si]
		mov	ax, 4
		push	ax
		call	_write_ptsout
		add	sp, 4
vq_color5:	jmp	v_nop

vq_cellarray:	call	dq_cellarray
		jmp	v_nop
;
vrq_locator:	call	drq_locator
		jmp	v_nop
;
vrq_valuator:	jmp	v_nop
;
vrq_choice:	call	drq_choice
		jmp	v_nop

vrq_string:	call	drq_string
		jmp	v_nop

vswr_mode:
		mov	ax, 1
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
		mov	ax, 1	
		push	ax
		call	_write_intout
		add	sp, 4
		jmp	v_nop

vsin_mode:	xor	ax, ax
		push	ax
		xor	ax, ax
		push	ax
		call	_write_intout
		add	sp, 4
		jmp	v_nop

		jmp	v_nop

scr_switch:				; CODE XREF: SCREEN+20j
		call	_switch

		dw	33	
		dw	33, 32, 31, 30, 29, 28, 27, 26, 25, 24, 23, 22, 21, 20
		dw	19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6
		dw	5, 4, 3, 2, 1
sw_screen	dw	offset v_nop         - offset sw_screen 	
		dw	offset vsin_mode     - offset sw_screen - 2
		dw	offset vswr_mode     - offset sw_screen - 4
		dw	offset vrq_string    - offset sw_screen - 6
		dw	offset vrq_choice    - offset sw_screen - 8
		dw	offset vrq_valuator  - offset sw_screen - 0Ah
		dw	offset vrq_locator   - offset sw_screen - 0Ch
		dw	offset vq_cellarray  - offset sw_screen - 0Eh
		dw	offset vq_color      - offset sw_screen - 10h
		dw	offset vsf_color     - offset sw_screen - 12h
		dw	offset vsf_interior  - offset sw_screen - 14h
		dw	offset vsf_style     - offset sw_screen - 16h
		dw	offset vst_color     - offset sw_screen - 18h
		dw	offset vst_font      - offset sw_screen - 1Ah
		dw	offset vsm_color     - offset sw_screen - 1Ch
		dw	offset vsm_height    - offset sw_screen - 1Eh
		dw	offset vsm_type      - offset sw_screen - 20h
		dw	offset vsl_color     - offset sw_screen - 22h
		dw	offset vsl_width     - offset sw_screen - 24h
		dw	offset vsl_type      - offset sw_screen - 26h
		dw	offset vs_color      - offset sw_screen - 28h
		dw	offset vst_direction - offset sw_screen - 2Ah
		dw	offset vst_height    - offset sw_screen - 2Ch
		dw	offset v_gdp         - offset sw_screen - 2Eh
		dw	offset v_cellarray   - offset sw_screen - 30h
		dw	offset v_fillarea    - offset sw_screen - 32h
		dw	offset v_gtext       - offset sw_screen - 34h
		dw	offset v_pmarker     - offset sw_screen - 36h
		dw	offset v_pline       - offset sw_screen - 38h
		dw	offset v_esc         - offset sw_screen - 3Ah
		dw	offset v_updwk       - offset sw_screen - 3Ch
		dw	offset v_clrwk       - offset sw_screen - 3Eh
		dw	offset v_clswk       - offset sw_screen - 40h
		dw	offset v_opnwk       - offset sw_screen - 42h


v_nop:					; CODE XREF: v_opnwk+23Bj v_clswk+8j
					; ...
		mov	sp, bp
		pop	bp
		retn	

d_esc:
		call	__csv
		db	6
		mov	ax, 6
		push	ax
		call	_read_contrl
		inc	sp
		inc	sp
		push	ax
		jmp	v_escapes
;
vq_chcells:
		mov	ax, 24
		push	ax
		mov	ax, 1
		push	ax
		call	_write_intout
		add	sp, 4
		mov	ax, 80
		push	ax
		mov	ax, 2
		push	ax
		call	_write_intout
		add	sp, 4
		jmp	v_endesc





;		S u b r	o u t i	n e

v_enter_cur:
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



eeos_row	equ	(word ptr (-6))[bp]

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



curaddr_pos	equ	(word ptr (-6))[bp]

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
		mov	ax, 2
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



curtext_ch	equ	(byte ptr (-2))[bp]
curtext_len	equ	(word ptr (-4))[bp]
curtext_pos	equ	(word ptr (-6))[bp]

;		S u b r	o u t i	n e

v_curtext:
		mov	ax, 4
		push	ax
		call	_read_contrl
		inc	sp
		inc	sp
		mov	curtext_len, ax
		mov	ax, 1	
		mov	curtext_pos, ax

v_curtext1:				; CODE XREF: v_curtext+3Bj
		mov	ax, curtext_pos
		cmp	ax, curtext_len
		jle	v_curtext2
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
		mov	ax, 1
		push	ax
		call	_write_intout
		add	sp, 4
		push	text_curx
		mov	ax, 2
		push	ax
		call	_write_intout
		add	sp, 4
		jmp	v_endesc

vq_tabstatus:	xor	ax, ax
		push	ax
		mov	ax, 1
		push	ax
		call	_write_intout
		add	sp, 4
		jmp	v_endesc

		jmp	v_endesc


v_escapes:				; CODE XREF: v_esc+10j
		call	_switch

		dw	10h
		dw	10h, 0Fh, 0Eh, 0Dh, 0Ch, 0Bh, 0Ah
		dw	9, 8, 7, 6, 5, 4, 2, 3, 1
sw_esctab	dw	offset v_endesc      - offset sw_esctab
		dw	offset vq_tabstatus  - offset sw_esctab - 2
		dw	offset vq_curaddress - offset sw_esctab - 4
		dw	offset v_rvoff       - offset sw_esctab - 6
		dw	offset v_rvon        - offset sw_esctab - 8
		dw	offset v_curtext     - offset sw_esctab - 0Ah
		dw	offset vs_curaddress - offset sw_esctab - 0Ch
		dw	offset v_eeol        - offset sw_esctab - 0Eh
		dw	offset v_eeos        - offset sw_esctab - 10h
		dw	offset v_curhome     - offset sw_esctab - 12h
		dw	offset v_curleft     - offset sw_esctab - 14h
		dw	offset v_curright    - offset sw_esctab - 16h
		dw	offset v_curdown     - offset sw_esctab - 18h
		dw	offset v_curup       - offset sw_esctab - 1Ah
		dw	offset v_exit_cur    - offset sw_esctab - 1Ch
		dw	offset v_enter_cur   - offset sw_esctab - 1Eh
		dw	offset vq_chcells    - offset sw_esctab - 20h

v_endesc:				; CODE XREF: _vq_chcells+1Bj
					; v_enter_cur+28j ...
		mov	sp, bp
		pop	bp
		ret
;
d_gdp:
		call	__csv0
		mov	ax, 6
		push	ax
		call	_read_contrl
		inc	sp
		inc	sp
		push	ax
		jmp	gdp_switch
;
gdp1:		call	d_bar
		jmp	gdpend
gdp2:		jmp	gdpend
gdp3:		jmp	gdpend
gdp4:		jmp	gdpend
gdp5:		jmp	gdpend
gdp6:		jmp	gdpend

gdp_switch:	call	_switch
		dw	5
		dw	5,4,3,2,1
sw_gdptab	dw	offset gdpend - offset sw_gdptab 
		dw	offset gdp5   - offset sw_gdptab - 2
		dw	offset gdp4   - offset sw_gdptab - 4
		dw	offset gdp3   - offset sw_gdptab - 6
		dw	offset gdp2   - offset sw_gdptab - 8
		dw	offset gdp1   - offset sw_gdptab - 10
;
gdpend:		mov	sp, bp
		pop	bp
		ret
;
bar_tmp		equ	(word ptr  (-2))[bp]
bar_y1		equ	(word ptr  (-4))[bp]
bar_x1		equ	(word ptr  (-6))[bp]
bar_y0		equ	(word ptr  (-8))[bp]
bar_x0		equ	(word ptr (-10))[bp]
;
d_bar:		call	__csv
		db	10

		mov	ax, 1
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	bar_x0, ax
		mov	ax, 2
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		push	ax
		mov	ax, YRESMX
		pop	si
		sub	ax, si
		mov	bar_y0, ax
		mov	ax, 3
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	bar_x1, ax
		mov	ax, 4
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		push	ax
		mov	ax, YRESMX
		pop	si
		sub	ax, si
		mov	bar_y1, ax

		mov	ax, bar_x0
		cmp	ax, bar_x1
		jg	bar01
		jmp	bar02
;
bar01:		mov	ax, bar_x1	
		mov	bar_tmp, ax
		mov	ax, bar_x0
		mov	bar_x1, ax
		mov	ax, bar_tmp
		mov	bar_x0, ax
bar02:		mov	ax, bar_y0
		cmp	ax, bar_y1
		jg	bar03
		jmp	bar04
;
bar03:		mov	ax, bar_y1	
		mov	bar_tmp, ax
		mov	ax, bar_y0
		mov	bar_y1, ax
		mov	ax, bar_tmp
		mov	bar_y0, ax
bar04:

;;;		mov	ax, fill_style
		LAXW	fill_style
		cmp	ax, 0
		jz	bar_outline
		jmp	bar_solid

bar_outline:
		lea	si, line_patterns
		push	si
		mov	ax, 2
		push	ax
		mov	ax, CMD_PRAM + 8
		push	ax
		call	send_command
		add	sp, 6

		push	write_mode	
		push	fill_colour
		push	word ptr bar_y1
		push	word ptr bar_x0
		push	word ptr bar_y0
		push	word ptr bar_x0
		call	DRAWLINE
		add	sp, 0Ch
		push	write_mode	
		push	fill_colour
		push	word ptr bar_y1
		push	word ptr bar_x1
		push	word ptr bar_y1
		push	word ptr bar_x0
		call	DRAWLINE
		add	sp, 0Ch
		push	write_mode	
		push	fill_colour
		push	word ptr bar_y0
		push	word ptr bar_x1
		push	word ptr bar_y1
		push	word ptr bar_x1
		call	DRAWLINE
		add	sp, 0Ch
		push	write_mode	
		push	fill_colour
		push	word ptr bar_y0
		push	word ptr bar_x0
		push	word ptr bar_y0
		push	word ptr bar_x1
		call	DRAWLINE
		add	sp, 0Ch
		jmp	bar_end
;
bar_solid:	push	write_mode
		push	fill_colour
		push	fill_interior
		push	fill_style
		push	word ptr bar_y1	
		push	word ptr bar_x1	
		push	word ptr bar_y0	
		push	word ptr bar_x0	
		call	FILLRECT
		add	sp, 10h

bar_end:	mov	sp, bp
		pop	bp
		ret


owk_source	equ	(word ptr (-2))[bp]
owk_rgb		equ	(word ptr (-4))[bp]
owk_count	equ	(word ptr (-6))[bp]

;		S u b r	o u t i	n e

d_opnwk:
		call	__csv
		db	6
		mov	ax, NUM_COLORS - 1
		push	ax
		xor	ax, ax
		push	ax
		mov	ax, 10
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
		push	ax
		call	_clamp
		add	sp, 6
;;;		mov	fill_colour, ax
		SAXW	fill_colour

		mov	ax, NUM_COLORS - 1
		push	ax
		xor	ax, ax
		push	ax
		mov	ax, 3
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
		push	ax
		call	_clamp
		add	sp, 6
;;;		mov	line_colour, ax
		SAXW	line_colour

		mov	ax, NUM_COLORS - 1
		push	ax
		xor	ax, ax
		push	ax
		mov	ax, 5
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
		mov	ax, 7
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
		push	ax
		call	_clamp
		add	sp, 6
;;;		mov	text_colour, ax
		SAXW	text_colour

		mov	ax, 1
;;;		mov	fill_interior, ax
		SAXW	fill_interior

		mov	ax, 3
		push	ax
		xor	ax, ax
		push	ax
		mov	ax, 8
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
		push	ax
		call	_clamp
		add	sp, 6
;;;		mov	fill_style, ax
		SAXW	fill_style

		mov	ax, 7
		push	ax
		mov	ax, 1	
		push	ax
		mov	ax, 12	;Bug? Line type is INTIN(2), not INTIN(12)
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
		push	ax
		call	_clamp
		add	sp, 6
;;;		mov	line_type, ax
		SAXW	line_type

		mov	ax, 5
		push	ax
		mov	ax, 1	
		push	ax
		mov	ax, 4	
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
		push	ax
		call	_clamp
		add	sp, 6
;;;		mov	marker_type, ax
		SAXW	marker_type
		xor	ax, ax
		SAXW	marker_height
		mov	ax, 2
		SAXW	text_direction
		xor	ax, ax
		SAXW	text_height
		mov	ax, 1
		SAXW	write_mode
		xor	ax, ax
		push	ax
		call	_out_2f2
		inc	sp
		inc	sp
		xor	ax, ax
		push	ax
		call	write_command
		inc	sp
		inc	sp
		mov	ax, CMD_BCTRL	;Blank display
		push	ax
		call	write_command
		inc	sp
		inc	sp
		mov	ax, CMD_SYNC	;Set up display parameters
		push	ax
		call	write_command
		inc	sp
		inc	sp
		mov	ax, 1Fh		;Mode control bits
		push	ax
		call	write_param
		inc	sp
		inc	sp	
		mov	ax, 3Eh		;Active display words / line
		push	ax
		call	write_param
		inc	sp
		inc	sp
		mov	ax, 67h		;Horizontal sync width, vsync width
		push	ax
		call	write_param
		inc	sp
		inc	sp
		mov	ax, 8h		;Horizontal front porch width
		push	ax
		call	write_param
		inc	sp
		inc	sp
		mov	ax, 5h		;Horizontal back porch width
		push	ax
		call	write_param
		inc	sp
		inc	sp
		mov	ax, 3h		;Vertical front proch width
		push	ax
		call	write_param
		inc	sp
		inc	sp
		mov	ax, 80h		;Active display lines / video field 
		push	ax
		call	write_param
		inc	sp
		inc	sp
		mov	ax, 45h		;Vertical back porch width
		push	ax
		call	write_param
		inc	sp
		inc	sp
		mov	ax, CMD_VSYNCM	;This controller is the master
		push	ax
		call	write_command
		inc	sp
		inc	sp
		mov	ax, 0FFh
		push	ax
		call	_out_2f6
		inc	sp
		inc	sp
		mov	ax, CMD_ZOOM	;No scaling
		push	ax
		call	write_command
		inc	sp
		inc	sp
		xor	ax, ax
		push	ax
		call	write_param
		inc	sp
		inc	sp
		mov	ax, CMD_BCTRL + 1	;Enable display
		push	ax
		call	write_command
		inc	sp
		inc	sp
		mov	ax, CMD_PRAM		;Initialise parameter RAM:
		push	ax
		call	write_command
		inc	sp
		inc	sp
		xor	ax, ax			;Display start address low
		push	ax
		call	write_param
		inc	sp
		inc	sp
		xor	ax, ax			;Display start address high
		push	ax
		call	write_param
		inc	sp
		inc	sp
		xor	ax, ax			;Display length low
		push	ax
		call	write_param
		inc	sp
		inc	sp
		mov	ax, 30h			;Display length high
		push	ax
		call	write_param
		inc	sp
		inc	sp
		xor	ax, ax
		push	ax
		xor	ax, ax
		push	ax
		xor	ax, ax
		push	ax
		call	_setcurpos		;Home cursor
		add	sp, 6

		mov	ax, CMD_CCHAR		;Set up cursor
		push	ax
		call	write_command
		inc	sp
		inc	sp
		mov	ax, 80h			;Display cursor
		push	ax
		call	write_param
		inc	sp
		inc	sp
		mov	ax, 0E1h		;Steady cursor
		push	ax
		call	write_param
		inc	sp
		inc	sp
		mov	ax, 13h			;Cursor shape
		push	ax
		call	write_param
		inc	sp
		inc	sp
		mov	ax, CMD_PITCH		;Set line pitch
		push	ax
		call	write_command
		inc	sp
		inc	sp
		mov	ax, 40h			;40 words / line
		push	ax
		call	write_param
		inc	sp
		inc	sp
		mov	ax, CMD_FIGS		;Bitmap fill
		push	ax
		call	write_command
		inc	sp
		inc	sp
		xor	ax, ax			;Blank bitmap
		push	ax
		call	write_param
		inc	sp
		inc	sp
		xor	ax, ax			;Blank bitmap
		push	ax
		call	write_param
		inc	sp
		inc	sp
		xor	ax, ax			;Blank bitmap
		push	ax
		call	write_param
		inc	sp
		inc	sp
		mov	ax, CMD_GMASK		;Set graphics mask
		push	ax
		call	write_command
		inc	sp
		inc	sp
		mov	ax, 0FFh
		push	ax
		call	write_param
		inc	sp
		inc	sp
		mov	ax, 0FFh
		push	ax
		call	write_param
		inc	sp
		inc	sp
		mov	ax, CMD_START		;Start filling
		push	ax
		call	write_command
		inc	sp
		inc	sp

		mov	ax, 6
		push	ax
		mov	ax, 3
		push	ax
		call	_write_contrl	; 6 points out
		add	sp, 4
		mov	ax, 45
		push	ax
		mov	ax, 5
		push	ax
		call	_write_contrl	; 45 ints out
		add	sp, 4
		lea	ax, DEV_TAB
		mov	owk_source, ax	; Source
		mov	ax, 1
		mov	owk_count, ax	; Count

cpy_dev_tab:				; CODE XREF: v_opnwk+52j
		mov	ax, owk_count
		cmp	ax, 45
		jle	cpy_dev_tab1
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
		mov	ax, 1
		mov	owk_count, ax

cpy_siz_tab1:				; CODE XREF: v_opnwk+8Bj
		mov	ax, owk_count
		cmp	ax, 0Ch
		jle	cpy_siz_tab2
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


init_types:
		lea	ax, init_scr
		push	ax
		mov	ax, 90
		push	ax
		call	_putstr		; (char	*p, unsigned len)
		add	sp, 4
		mov	sp, bp
		pop	bp
		ret

clrwk_y		equ	(word ptr (-2))[bp]
clrwk_plane	equ	(word ptr (-4))[bp]

d_clrwk:
		call	__csv
		db	4
		mov	ax, CMD_BCTRL	;Blank display
		push	ax
		call	write_command
		inc	sp
		inc	sp
		xor	ax, ax
		mov	clrwk_plane, ax
clearplane:	mov	ax, clrwk_plane
		cmp	ax, 3
		jle	clearplane1
		jmp	clearend
;
clearplane1:	xor	ax, ax
		mov	clrwk_y, ax
clearplane2:	mov	ax, clrwk_y
		cmp	ax, YRESMX + 1
		jle	clearplane3
		jmp	clearplane5
;
clearplane3:	push	word ptr clrwk_plane
		push	word ptr clrwk_y
		xor	ax, ax
		push	ax
		call	_setcurpos
		add	sp, 6
		mov	ax, CMD_FIGS
		push	ax
		call	write_command	;Fill screen with blank
		inc	sp
		inc	sp
		mov	ax, 2
clearplane4:
		push	ax
		call	write_param
		inc	sp
		inc	sp
		mov	ax, 0FFh
		push	ax
		call	write_param
		inc	sp
		inc	sp
		mov	ax, 31h
		push	ax
		call	write_param
		inc	sp
		inc	sp
		mov	ax, CMD_GMASK
		push	ax
		call	write_command
		inc	sp
		inc	sp
		mov	ax, 0FFh
		push	ax
		call	write_param
		inc	sp
		inc	sp
		mov	ax, 0FFh
		push	ax
		call	write_param
		inc	sp
		inc	sp
		mov	ax, CMD_WDAT + WDAT_RESET
		push	ax
		call	write_command
		inc	sp
		inc	sp
		mov	ax, 0FFh
		push	ax
		call	write_param
		inc	sp
		inc	sp
		mov	ax, 0FFh
		push	ax
		call	write_param
		inc	sp
		inc	sp
		mov	ax, clrwk_y
		ADDAXW	200
		mov	clrwk_y, ax
		jmp	clearplane2
;
clearplane5:	lea	si, clrwk_plane
		mov	ax, [si]
		ADDPSI	1
		jmp	clearplane
;
clearend:	mov	ax, CMD_BCTRL + 1	;Enable display
		push	ax
		call	write_command
		inc	sp
		inc	sp
		mov	sp, bp
		pop	bp
		ret

pline_plygn	equ	(word ptr   (4))[bp]	;Polygon (ie, close path)?
pline_y1	equ	(word ptr  (-2))[bp]
pline_x1	equ	(word ptr  (-6))[bp]
pline_y0	equ	(word ptr  (-4))[bp]
pline_x0	equ	(word ptr  (-8))[bp]
pline_lastpt	equ	(word ptr (-10))[bp]
pline_curpt	equ	(word ptr (-12))[bp]

;		S u b r	o u t i	n e

d_pline:	call	__csv
		db	0Ch
;;;		mov	ax, line_type
		LAXW	line_type
		shl	ax, 1
;;;		sub	ax, 2
		SUBAXW	2
		shl	ax, 1
		push	ax
		lea	si, line_patterns
		pop	ax
		add	si, ax
		push	si
		mov	ax, 2
		push	ax
		mov	ax, CMD_PRAM + 8
		push	ax
		call	send_command
		add	sp, 6

		mov	ax, 2
		push	ax
		call	_read_contrl	
		inc	sp
		inc	sp
		push	ax
		mov	ax, 2
		pop	si
		mul	si
;;;		sub	ax, 3
		SUBAXW	3
		mov	pline_lastpt, ax
		mov	ax, 1
		mov	pline_curpt, ax

v_pline1:				; CODE XREF: v_pline+72j
		mov	ax, pline_curpt
		cmp	ax, pline_lastpt
		jle	v_pline2
		jmp	v_pline3


v_pline2:				; CODE XREF: v_pline+22j
		push	word ptr pline_curpt
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	pline_x0, ax
		mov	ax, pline_curpt
		ADDAXW	1
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		push	ax
		mov	ax, YRESMX
		pop	si
		sub	ax, si
		mov	pline_y0, ax
		mov	ax, pline_curpt
		ADDAXW	2
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	pline_x1, ax
		mov	ax, pline_curpt
		ADDAXW	3
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		push	ax
		mov	ax, YRESMX
		pop	si
		sub	ax, si
		mov	pline_y1, ax
		push	write_mode
		push	line_colour
		push	word ptr pline_y1
		push	word ptr pline_x1
		push	word ptr pline_y0
		push	word ptr pline_x0
		call	DRAWLINE
		add	sp, 0Ch
		mov	ax, pline_curpt
		ADDAXW	2
		mov	pline_curpt, ax
		jmp	v_pline1

v_pline3:	mov	ax, pline_plygn	;Doing a polygon? If so, close shape
		or	ax, ax
		jnz	v_pline4
		jmp	pline_end
;
v_pline4:	mov	ax, pline_lastpt
		ADDAXW	2
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	pline_x0, ax
		mov	ax, pline_lastpt
		ADDAXW	3
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		push	ax
		mov	ax, YRESMX
		pop	si
		sub	ax, si
		mov	pline_y0, ax
		mov	ax, 1
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	pline_x1, ax
		mov	ax, 2
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		push	ax
		mov	ax, YRESMX
		pop	si
		sub	ax, si
		mov	pline_y1, ax
		push	write_mode
		push	line_colour
		push	word ptr pline_y1
		push	word ptr pline_x1
		push	word ptr pline_y0
		push	word ptr pline_x0
		call	DRAWLINE
		add	sp, 0Ch
pline_end:	mov	sp, bp
		pop	bp
		ret

marker_max	equ	(word ptr  (-2))[bp]
marker_cur	equ	(word ptr  (-4))[bp]
marker_cyscale	equ	(word ptr  (-6))[bp]
marker_cxscale	equ	(word ptr  (-8))[bp]
marker_y	equ	(word ptr (-10))[bp]
marker_x	equ	(word ptr (-12))[bp]

d_pmarker:	call	__csv
		db	0Ch

		mov	ax, CMD_ZOOM
		push	ax
		call	write_command	
		inc	sp
		inc	sp

		push	marker_height	;Set text scale to marker height
		call	write_param
		inc	sp
		inc	sp
		
		mov	ax, 1
		push	ax
		LAXW	marker_type
		SUBAXW	1
		shl	ax, 1
		push	ax
		lea	si, marker_cx
		pop	ax
		add	si, ax
		push	word ptr [si]
		LAXW	marker_height
		ADDAXW	1
		pop	si
		mul	si		;Marker height * marker CX
		pop	cx
		sar	ax, cl
		mov	marker_cxscale, ax
		mov	ax, 1
		push	ax

		LAXW	marker_type
		SUBAXW	1
		shl	ax, 1
		push	ax
		lea	si, marker_cy
		pop	ax
		add	si, ax
		push	word ptr [si]
		LAXW	marker_height
		ADDAXW	1
		pop	si
		mul	si
		pop	cx
		sar	ax, cl
		mov	marker_cyscale, ax
			
		mov	ax, 2
		push	ax
		call	_read_contrl	; Get marker count
		inc	sp
		inc	sp
		shl	ax, 1
		SUBAXW	1	
		mov	marker_max, ax
		mov	ax, 1
		mov	marker_cur, ax
markloop:	mov	ax, marker_cur
		cmp	ax, marker_max
		jle	markloop1
		jmp	markend
;
markloop1:	push	word ptr marker_cur
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	marker_x, ax	;X
		mov	ax, marker_cur
		ADDAXW	1
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		push	ax
		mov	ax, YRESMX
		pop	si
		sub	ax, si
		mov	marker_y, ax	;Y
		push	write_mode
		mov	ax, 2
		push	ax
		push	mark_colour
		mov	ax, marker_y
		add	ax, marker_cyscale
		push	ax
		mov	ax, marker_x
		sub	ax, marker_cxscale
		push	ax
		LAXW	marker_type
		SUBAXW	1
		push	ax
		lea	si, marker_asc
		pop	ax
		add	si, ax
		mov	al, [si]
		mov	ah, 0
		push	ax
		call	gchar
		add	sp, 0Ch
		mov	ax, 2
		push	ax
		lea	si, marker_cur
		mov	ax, [si]
		pop	cx
		add	ax, cx
		mov	[si], ax
		jmp	markloop
;
markend:	mov	ax, CMD_ZOOM
		push	ax
		call	write_command	;Reset zoom
		inc	sp
		inc	sp
		xor	ax, ax
		push	ax
		call	write_param
		inc	sp
		inc	sp
		mov	sp, bp
		pop	bp
		ret
;


gtext_count	equ	(word ptr  (-2))[bp]
gtext_index	equ	(word ptr  (-4))[bp]
gtext_scale	equ	(word ptr  (-6))[bp]
gtext_height	equ	(word ptr  (-8))[bp]
gtext_dy	equ	(word ptr (-10))[bp]
gtext_dx	equ	(word ptr (-12))[bp]
gtext_y		equ	(word ptr (-14))[bp]
gtext_x		equ	(word ptr (-16))[bp]

;		S u b r	o u t i	n e

m_gtext:
		call	__csv
		db	16
		LAXW	text_direction
		ANDAXW	1
		or	ax, ax
		jnz	d_gtext1
		jmp	d_gtext3
;
d_gtext1:	mov	si, 0Ah		;Scale height when doing text
		push	si		;vertically, to compensate for 
		mov	ax, 7		;the aspect ratio
		push	ax
		push	text_height
		pop	ax
		pop	si
		mul	si
		pop	si
		or	si, si
		jz	d_gtext2
		cwd
		idiv	si
d_gtext2:	mov	gtext_height, ax
		jmp	d_gtext4
;
d_gtext3:	LAXW	text_height
		mov	gtext_height, ax
d_gtext4:	mov	ax, CMD_ZOOM
		push	ax
		call	write_command	;Set text scale to text height
		inc	sp
		inc	sp
		push	word ptr gtext_height
		call	write_param
		inc	sp
		inc	sp
		mov	ax, gtext_height
;;;		add	ax, 1
		ADDAXW	1
		mov	gtext_scale, ax
		mov	ax, 6
		push	ax
		push	word ptr gtext_scale
		pop	ax
		pop	si
		mul	si
		mov	gtext_height, ax
		LAXW	text_direction
		shl	ax, 1
		push	ax
		lea	si, yincrements	
		pop	ax
		add	si, ax
		push	word ptr[si]
		push	word ptr gtext_height
		pop	ax
		pop	si
		mul	si
		mov	gtext_dx, ax

		LAXW	text_direction
		shl	ax, 1
		push	ax
		lea	si, xincrements	
		pop	ax
		add	si, ax
		push	word ptr[si]
		push	word ptr gtext_height
		pop	ax
		pop	si
		mul	si
		mov	gtext_dy, ax

		mov	ax, 1
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	gtext_x, ax
		mov	ax, 2
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		push	ax
		mov	ax, YRESMX
		pop	si
		sub	ax, si
		mov	gtext_y, ax
		LAXW	text_direction
		shl	ax, 1
		push	ax
		lea	si, xincrements
		pop	ax
		add	si, ax
		push	word ptr [si]
		push	word ptr gtext_scale
		pop	ax
		pop	si
		mul	si
		push	ax
		mov	ax, gtext_x
		pop	si
		sub	ax, si
		mov	gtext_x, ax

		LAXW	text_direction
		shl	ax, 1
		push	ax
		lea	si, yincrements
		pop	ax
		add	si, ax
		push	word ptr [si]
		push	word ptr gtext_scale
		pop	ax
		pop	si
		mul	si
		push	ax
		mov	ax, gtext_y
		pop	si
		add	ax, si
		mov	gtext_y, ax

		mov	ax, 4
		push	ax
		call	_read_contrl
		inc	sp
		inc	sp
		mov	gtext_count, ax
		mov	ax, 1
		mov	gtext_index, ax
text_loop:	mov	ax, gtext_index
		cmp	ax, gtext_count
		jle	textloop1
		jmp	text_end
;
textloop1:	push	write_mode
		push	text_direction
		push	text_colour
		push	word ptr gtext_y
		push	word ptr gtext_x
		push	word ptr gtext_index
		call	_read_intin
		inc	sp
		inc	sp
		push	ax
		call	gchar
		add	sp, 0Ch
		push	word ptr gtext_dx
		lea	si, gtext_x
		mov	ax, [si]
		pop	cx
		add	ax, cx
		mov	[si], ax
		push	word ptr gtext_dy
		lea	si, gtext_y
		mov	ax, [si]
		pop	cx
		add	ax, cx
		mov	[si], ax
		lea	si, gtext_index
		mov	ax, [si]
		ADDPSI	1
		jmp	text_loop
;
text_end:	mov	ax, CMD_ZOOM
		push	ax
		call	write_command	;Reset scaling
		inc	sp	
		inc	sp
		xor	ax, ax
		push	ax
		call	write_param
		inc	sp
		inc	sp
		mov	sp, bp
		pop	bp
		ret

;		S u b r	o u t i	n e
vca_index	equ	(word ptr  (-2))[bp]
vca_col		equ	(word ptr  (-4))[bp]
vca_row		equ	(word ptr  (-6))[bp]
vca_cury	equ	(word ptr  (-8))[bp]
vca_nextx	equ	(word ptr (-10))[bp]
vca_nexty	equ	(word ptr (-12))[bp]
vca_x		equ	(word ptr (-14))[bp]
vca_height	equ	(word ptr (-16))[bp]
vca_width	equ	(word ptr (-18))[bp]
vca_mode	equ	(word ptr (-20))[bp]
vca_y1		equ	(word ptr (-22))[bp]
vca_x1		equ	(word ptr (-24))[bp]
vca_y0		equ	(word ptr (-26))[bp]
vca_x0		equ	(word ptr (-28))[bp]
vca_rows	equ	(word ptr (-30))[bp]
vca_cols	equ	(word ptr (-32))[bp]
vca_pitch	equ	(word ptr (-34))[bp]



d_cellarray:
		call	__csv
		db	34

		mov	ax, 6
		push	ax
		call	_read_contrl
		inc	sp
		inc	sp
		mov	vca_pitch, ax
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
		mov	vca_rows, ax

		mov	ax, 1
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	vca_x0, ax
		mov	ax, 2
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	vca_y0, ax
		mov	ax, 3
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	vca_x1, ax
		mov	ax, 4
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	vca_y1, ax
		mov	ax, 9
		push	ax
		call	_read_contrl
		inc	sp
		inc	sp
		mov	vca_mode, ax

		mov	ax, vca_x1
		sub	ax, vca_x0
		mov	vca_width, ax
		mov	ax, vca_y1
		sub	ax, vca_y0
		mov	vca_height, ax
		mov	ax, YRESMX
		sub	ax, vca_y1
		mov	vca_cury, ax
		xor	ax, ax
		mov	vca_row, ax
ca01:		mov	ax, vca_row
		cmp	ax, vca_rows
		jl	ca02
		jmp	ca_end
;
ca02:		mov	si, vca_rows
		push	si
		push	word ptr vca_height
		mov	ax, vca_row
		ADDAXW	1
		pop	si
		mul	si
		pop	si
		or	si, si
		jz	ca03
		cwd
		idiv	si
ca03:		push	ax
		mov	si, vca_y1
		pop	ax
		sub	si, ax
		push	si
		mov	ax, YRESMX
		pop	si
		sub	ax, si
		mov	vca_nexty, ax
		mov	si, vca_rows
		SUBSIW	1	
		push	si
		mov	ax, vca_row
		pop	si
		cmp	ax, si
		jl	ca04
		jmp	ca05
;
ca04:		mov	ax, vca_height
		cmp	ax, vca_rows
		jg	ca06
ca05:		jmp	ca07

ca06:		lea	si, vca_nexty
		mov	ax, [si]
		ADDPSI	1
ca07:		push	word ptr vca_pitch
		push	word ptr vca_row
		pop	ax
		pop	si
		mul	si
		ADDAXW	1
		mov	vca_index, ax
		mov	ax, vca_x0
		mov	vca_x, ax
		xor	ax, ax
		mov	vca_col, ax
ca08:		mov	ax, vca_col
		cmp	ax, vca_cols
		jl	ca09
		jmp	ca15
;
ca09:		mov	si, vca_cols
		push	si
		push	word ptr vca_width
		mov	ax, vca_col
		ADDAXW	1
		pop	si
		mul	si
		pop	si
		or	si, si
		jz	ca10
		cwd
		idiv	si	
ca10:		add	ax, vca_x0
		mov	vca_nextx, ax
		mov	si, vca_cols
		SUBSIW	1
		push	si
		mov	ax, vca_col
		pop	si
		cmp	ax, si
		jl	ca11
		jmp	ca12
;
ca11:		mov	ax, vca_width
		cmp	ax, vca_cols
		jg	ca13
ca12:		jmp	ca14
;
ca13:		lea	si, vca_nextx
		mov	ax, [si]
		SUBPSI	1
ca14:		push	word ptr vca_mode
		push	word ptr vca_index
		call	_read_intin
		inc	sp
		inc	sp
		push	ax
		xor	ax, ax
		push	ax
		mov	ax, 1
		push	ax
		push	word ptr vca_nexty
		push	word ptr vca_nextx
		push	word ptr vca_cury
		push	word ptr vca_x
		call	FILLRECT
		add	sp, 10h
		lea	si, vca_index
		mov	ax, [si]
		ADDPSI	1
		mov	ax, vca_nextx
		mov	vca_x, ax
		lea	si, vca_col
		mov	ax, [si]
		ADDPSI	1
		jmp	ca08
;	
ca15:		mov	ax, vca_nexty
		mov	vca_cury, ax
		lea	si, vca_row
		mov	ax, [si]
		ADDPSI	1
		jmp	ca01

ca_end:		mov	sp, bp
		pop	bp
		ret
;

vqca_result	equ	(word ptr  (-2))[bp]
vqca_cur_col	equ	(word ptr  (-4))[bp]
vqca_cur_row	equ	(word ptr  (-6))[bp]
vqca_cell_y	equ	(word ptr  (-8))[bp]
vqca_cell_w	equ	(word ptr (-10))[bp]
vqca_cell_h	equ	(word ptr (-12))[bp]
vqca_cell_x	equ	(word ptr (-14))[bp]
vqca_height	equ	(word ptr (-16))[bp]
vqca_width	equ	(word ptr (-18))[bp]
vqca_y1		equ	(word ptr (-20))[bp]
vqca_x1		equ	(word ptr (-22))[bp]
vqca_y0		equ	(word ptr (-24))[bp]
vqca_x0		equ	(word ptr (-26))[bp]
vqca_rowcount	equ	(word ptr (-28))[bp]
vqca_colcount	equ	(word ptr (-30))[bp]
vqca_maxresult	equ	(word ptr (-32))[bp]

dq_cellarray:
		call	__csv
		db	32
		mov	ax, 4
		push	ax
		call	_read_contrl
		inc	sp
		inc	sp
		mov	vqca_maxresult, ax
		mov	ax, 6
		push	ax
		call	_read_contrl
		inc	sp
		inc	sp
		mov	vqca_colcount, ax
		mov	ax, 7
		push	ax
		call	_read_contrl
		inc	sp
		inc	sp
		mov	vqca_rowcount, ax

		mov	ax, 1
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	vqca_x0, ax
		mov	ax, 2
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	vqca_y0, ax
		mov	ax, 3
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	vqca_x1, ax
		mov	ax, 4
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	vqca_y1, ax
		mov	ax, vqca_x1
		sub	ax, vqca_x0
		mov	vqca_width, ax	;Width
		mov	ax, vqca_y1
		sub	ax, vqca_y0
		mov	vqca_height, ax	;Height
		mov	ax,YRESMX
		sub	ax,vqca_y1
		mov	vqca_cell_y, ax
		xor	ax, ax
		mov	vqca_cur_row, ax
vqca1:
		mov	ax, vqca_cur_row
		cmp	ax, vqca_rowcount
		jl	vqca2
		jmp	vqca18
;
vqca2:		mov	si, vqca_rowcount
		push	si
		push	word ptr vqca_height
		mov	ax, vqca_cur_row
		ADDAXW	1
		pop	si
		mul	si
		pop	si
		or	si, si
		jz	vqca3
		cwd
		idiv	si
vqca3:		push	ax
		mov	si, vqca_y1
		pop	ax
		sub	si, ax
		push	si
		mov	ax, YRESMX
		pop	si
		sub	ax, si
		mov	vqca_cell_h, ax
		mov	si, vqca_rowcount
		SUBSIW	1
		push	si
		mov	ax, vqca_cur_row
		pop	si
		cmp	ax, si
		jl	vqca4
		jmp	vqca5
;
vqca4:		mov	ax, vqca_height
		cmp	ax, vqca_rowcount
		jg	vqca6
vqca5:		jmp	vqca7
;
vqca6:		lea	si, vqca_cell_h
		mov	ax, [si]
		ADDPSI	1
vqca7:		push	word ptr vqca_colcount
		push	word ptr vqca_cur_row
		pop	ax
		pop	si
		mul	si
		ADDAXW	1
		mov	vqca_result, ax
		mov	ax, vqca_x0
		mov	vqca_cell_x, ax
		xor	ax, ax
		mov	vqca_cur_col, ax
vqca_row:	mov	ax, vqca_cur_col	
		cmp	ax, vqca_colcount
		jl	vqca9
		jmp	vqca_endrow
;
vqca9:		mov	si,vqca_colcount
		push	si
		push	word ptr vqca_width
		mov	ax, vqca_cur_col
		ADDAXW	1
		pop	si
		mul	si
		pop	si
		or	si, si
		jz	vqca10
		cwd
		idiv	si
vqca10:		add	ax, vqca_x0
		mov	vqca_cell_w, ax
		mov	si, vqca_colcount
		SUBSIW	1
		push	si
		mov	ax, vqca_cur_col
		pop	si
		cmp	ax, si
		jl	vqca11
		jmp	vqca12
;
vqca11:		mov	ax, vqca_width
		cmp	ax, vqca_colcount
		jg	vqca13
vqca12:		jmp	vqca14
;
vqca13:		lea	si, vqca_cell_w
		mov	ax, [si]
		SUBPSI	1
vqca14:		mov	ax, vqca_result
		cmp	ax, vqca_maxresult
		jg	vqca15
		jmp	vqca16
;
vqca15:		jmp	vqca_endrow
;
vqca16:		push	word ptr vqca_cell_h
		push	word ptr vqca_cell_w
		push	word ptr vqca_cell_y
		push	word ptr vqca_cell_x
		call	read_pixel
		add	sp, 8
		shl	ax, 1
		push	ax
		lea	si, RMAP_COL
		pop	ax
		add	si, ax
		push	word ptr [si]
		push	word ptr vqca_result
		call	_write_intout
		add	sp, 4
		lea	si, vqca_result
		mov	ax, [si]
		ADDPSI	1
		mov	ax, vqca_cell_w
		mov	vqca_cell_x, ax
		lea	si, vqca_cur_col
		mov	ax,[si]
		ADDPSI	1
		jmp	vqca_row
;
vqca_endrow:	mov	ax, vqca_cell_h
		mov	vqca_cell_y, ax
		lea	si, vqca_cur_row
		mov	ax,[si]
		ADDPSI	1
		jmp	vqca1

vqca18:		push	word ptr vqca_colcount
		mov	ax, 8
		push	ax
		call	_write_contrl
		add	sp, 4
		push	word ptr vqca_rowcount
		mov	ax, 9
		push	ax
		call	_write_contrl
		add	sp, 4
		xor	ax, ax
		push	ax
		mov	ax, 10
		push	ax
		call	_write_contrl
		add	sp, 4
		mov	sp, bp
		pop	bp
		ret
;
rpix_h0		equ	(word ptr    10)[bp]
rpix_w0		equ	(word ptr     8)[bp]
rpix_y0		equ	(word ptr     6)[bp]
rpix_x0		equ	(word ptr     4)[bp]

rpix_planedata	equ	(word ptr  (-8))[bp]
rpix_result	equ	(word ptr (-10))[bp]
rpix_pixel	equ	(word ptr (-12))[bp]
rpix_plane	equ	(word ptr (-14))[bp]
rpix_y		equ	(word ptr (-18))[bp]
rpix_x		equ	(word ptr (-20))[bp]


read_pixel:	call	__csv
		db	20
		mov	ax, 1
		push	ax
		mov	ax, rpix_y0
		add	ax, rpix_h0
		pop	cx
		sar	ax, cl
		mov	rpix_y, ax	;y + (h / 2)
		mov	ax, 1
		push	ax
		mov	ax, rpix_x0
		add	ax, rpix_w0	;x + (w / 2)
		pop	cx
		sar	ax, cl
		mov	rpix_x, ax	;(rpix_x, rpix_y) is centre of box
		xor	ax, ax
		mov	rpix_plane, ax
read_pixel1:	mov	ax, rpix_plane
		cmp	ax, 3		;Plane number?
		jle	read_pixel2
		jmp	read_pixel3
;
read_pixel2:	push	word ptr rpix_plane
		push	word ptr rpix_y
		push	word ptr rpix_x
		call	_GETPIXEL
		add	sp, 6
		push	ax
		mov	ax, rpix_plane
		shl	ax, 1
		push	ax
		lea	si, rpix_planedata
		pop	ax
		add	si, ax
		pop	ax
		mov	[si], ax
		lea	si, rpix_plane
		mov	ax, [si]
		ADDPSI	1
		jmp	read_pixel1
;
read_pixel3:	xor	ax, ax
		mov	rpix_result, ax
		mov	ax, rpix_x
		ANDAXW	0Fh
		mov	rpix_pixel, ax
		mov	ax, 3
		mov	rpix_plane, ax
read_pixel4:	mov	ax, rpix_plane
		cmp	ax, 0
		jge	read_pixel5
		jmp	read_pixel6
;
read_pixel5:	mov	ax, 1
		push	ax
		push	word ptr rpix_pixel
		mov	ax, rpix_plane
		shl	ax, 1
		push	ax
		lea	si, rpix_planedata
		pop	ax
		add	si, ax
		push	word ptr [si]
		pop	ax
		pop	cx
		shr	ax, cl
		MOVSI_AX
;;;		mov	si, ax
		pop	ax
		and	si, ax
		push	si
		mov	ax, 1
		push	ax
		mov	ax, rpix_result
		pop	cx
		shl	ax, cl
		pop	si
		or	ax, si
		mov	rpix_result,ax
		lea	si, rpix_plane
		mov	ax,[si]
		SUBPSI	1
		jmp	read_pixel4
;
read_pixel6:	mov	ax, rpix_result
		mov	sp, bp
		pop	bp
		ret
;
		mov	sp, bp
		pop	bp
		ret



locator_button	equ	(word ptr  (-2))[bp]
locator_ch	equ	(word ptr  (-4))[bp]
locator_crossy	equ	(word ptr  (-6))[bp]
locator_crossx	equ	(word ptr  (-8))[bp]
locator_chy	equ	(word ptr (-10))[bp]
locator_chx	equ	(word ptr (-12))[bp]
locator_finish	equ	(word ptr (-14))[bp]
locator_delta	equ	(word ptr (-16))[bp]
locator_y0	equ	(word ptr (-18))[bp]
locator_x0	equ	(word ptr (-20))[bp]
locator_y	equ	(word ptr (-22))[bp]
locator_x	equ	(word ptr (-24))[bp]
locator_number	equ	(word ptr (-26))[bp]




drq_locator:	call	__csv
		db	26
		xor	ax, ax
		push	ax
		mov	ax, 5
		push	ax
		call	_write_contrl
		add	sp, 4
		mov	ax, 1
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
		mov	ax, 1
		push	ax
		call	_read_ptsin
		inc	sp
		inc	sp
		mov	locator_x, ax
		mov	ax, 2
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
		lea	si, line_patterns
		push	si
		mov	ax, 2
		push	ax
		mov	ax, CMD_PRAM + 8
		push	ax
		call	send_command
		add	sp, 6
;
; Draw the crosshair
;
		mov	ax, 3
		push	ax
		mov	ax, 5
		push	ax
		mov	ax, YRESMX
		sub	ax, locator_y
		push	ax
		push	word ptr locator_crossx
		mov	ax, YRESMX
		sub	ax, locator_y
		push	ax
		push	word ptr locator_chx
		call	DRAWLINE
		add	sp, 12
		mov	ax, 3
		push	ax
		mov	ax, 5
		push	ax
		mov	ax, YRESMX
		sub	ax, locator_crossy
		push	ax
		push	word ptr locator_x
		mov	ax, YRESMX
		sub	ax, locator_chy
		push	ax
		push	word ptr locator_x
		call	DRAWLINE
		add	sp, 12

		mov	ax, locator_x
		mov	locator_x0, ax
		mov	ax, locator_y
		mov	locator_y0, ax
		lea	si, locator_ch
		push	si
		call	_getkey
		inc	sp
		inc	sp
		mov	ax, locator_ch
		ANDAXW	0FFh
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
		mov	ax, locator_ch
		cmp	ax, 0FFFFh
		jnz	locator12
		jmp	locator13


locator12:				; CODE XREF: cseg:1334j
		mov	ax, locator_ch
		ANDAXW	0FFh
		mov	locator_button, ax
locator13:	mov	ax, locator_button
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


locator16:
		push	word ptr locator_delta
		lea	si, locator_x
		mov	ax, [si]
		pop	cx
		sub	ax, cx
		mov	[si], ax
		jmp	locator25


locator17:
		push	word ptr locator_delta
		lea	si, locator_x
		mov	ax, [si]
		pop	cx
		add	ax, cx
		mov	[si], ax
		jmp	locator25


locator18:
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


locator22:
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
sw_locator	dw	offset locator22 - offset sw_locator
		dw	offset locator18 - offset sw_locator - 2 
		dw	offset locator17 - offset sw_locator - 4 
		dw	offset locator16 - offset sw_locator - 6 
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
		lea	si, line_patterns
		push	si
		mov	ax, 2
		push	ax
		mov	ax, CMD_PRAM + 8
		push	ax
		call	send_command
		add	sp, 6
;
; Undraw the crosshair
;
		mov	ax, 3
		push	ax
		mov	ax, 5
		push	ax
		mov	ax, YRESMX
		sub	ax, locator_y0
		push	ax
		push	word ptr locator_crossx
		mov	ax, YRESMX
		sub	ax, locator_y0
		push	ax
		push	word ptr locator_chx
		call	DRAWLINE
		add	sp, 12
		mov	ax, 3
		push	ax
		mov	ax, 5
		push	ax
		mov	ax, YRESMX
		sub	ax, locator_crossy
		push	ax
		push	word ptr locator_x0
		mov	ax, YRESMX
		sub	ax, locator_chy
		push	ax
		push	word ptr locator_x0
		call	DRAWLINE
		add	sp, 12

		mov	ax, locator_finish
		or	ax, ax
		jnz	locator32
		jmps	j_locator_loop


locator32:				; CODE XREF: cseg:1460j
		jmps	locator33


j_locator_loop:				; CODE XREF: cseg:1462j
		jmp	locator_loop


locator33:				; CODE XREF: cseg:1464j
		mov	ax, 1
		push	ax
		mov	ax, 5
		push	ax
		call	_write_contrl
		add	sp, 4
		mov	ax, 1
		push	ax
		mov	ax, 3
		push	ax
		call	_write_contrl
		add	sp, 4
		push	word ptr locator_x
		mov	ax, 1
		push	ax
		call	_write_ptsout
		add	sp, 4
		push	word ptr locator_y
		mov	ax, 2
		push	ax
		call	_write_ptsout
		add	sp, 4
		push	word ptr locator_button
		mov	ax, 1	
		push	ax
		call	_write_intout
		add	sp, 4
		mov	sp, bp
		pop	bp
		ret



choice_ch	equ	(byte ptr (-2))[bp]
choice_chw	equ	(word ptr (-4))[bp]
choice_val	equ	(word ptr (-6))[bp]

;		S u b r	o u t i	n e

drq_choice:
		call	__csv
		db	6
		xor	ax, ax
		push	ax
		mov	ax, 5
		push	ax
		call	_write_contrl
		add	sp, 4
		mov	ax, 1
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
		push	ax
		mov	ax, 1	
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
		mov	ax, 1	
		push	ax
		call	_write_intout
		add	sp, 4
		mov	ax, 1
		push	ax
		mov	ax, 5
		push	ax
		call	_write_contrl
		add	sp, 4

choice5:				; CODE XREF: vrq_choice+40j
					; vrq_choice+6Ej
		mov	sp, bp
		pop	bp
		ret


string_ch	equ	(byte ptr  (-2))[bp]
string_echo	equ	(word ptr  (-4))[bp]
string_chw	equ	(word ptr  (-6))[bp]
string_maxlen	equ	(word ptr  (-8))[bp]
string_len	equ	(word ptr (-10))[bp]


;		S u b r	o u t i	n e

drq_string:
		call	__csv
		db	10
		mov	si, 1
		push	si
		mov	ax, 1
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
		mov	ax, 5
		push	ax
		call	_write_contrl
		add	sp, 4
		mov	sp, bp
		pop	bp
		retn	


string2:				; CODE XREF: vrq_string+11j
		xor	ax, ax
		mov	string_len, ax
		mov	ax, 3
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
		mov	string_echo, ax
		mov	ax, 2
		push	ax
		call	_read_intin
		inc	sp
		inc	sp
		mov	string_maxlen, ax

string3:				; CODE XREF: vrq_string+ECj
		lea	si, string_ch
		push	si
		call	_getkey
		inc	sp
		inc	sp

string3b:
		mov	ax, 0FFh
		push	ax
		mov	al, string_ch
		mov	ah, 0
		pop	si
		and	ax, si
		mov	string_chw, ax

string5:				; CODE XREF: vrq_string+6Cj
		mov	ax, string_chw
		cmp	ax, 0Ah
		jz	string6
		jmps	string7


string6:				; CODE XREF: vrq_string+A1j
		jmp	string8


string7:				; CODE XREF: vrq_string+A3j
		mov	ax, string_chw
		cmp	ax, 0Dh
		jz	string8
		jmp	string12

string8:	mov	ax, string_echo
		or	ax, ax
		jnz	string9
		jmp	string10

string9:
		mov	ax, 0Dh
		push	ax
		call	_putchar
		inc	sp
		inc	sp
		mov	ax, 0Ah
		push	ax
		call	_putchar
		inc	sp
		inc	sp
string10:	jmp	string18

string11:	jmp	string16

string12:	mov	ax, string_len
		cmp	ax, string_maxlen
		jle	string13
		jmp	string16
;
string13:	mov	ax, string_echo
		or	ax, ax
		jnz	string14
		jmp	string15
;
string14:	mov	al, string_ch
		mov	ah, 0
		push	ax
		call	_putchar
		inc	sp
		inc	sp
string15:	lea	si, string_len
		mov	ax, [si]
		ADDPSI	1
		push	word ptr string_chw
		push	word ptr string_len
		call	_write_intout
		add	sp, 4
string16:	mov	ax, string_len
		cmp	ax, string_maxlen
		jle	string17
		jmps	string18
;
string17:	jmp	string3

string18:				; CODE XREF: vrq_string+A6j
					; vrq_string+B4j ...
		push	word ptr string_len
		mov	ax, 5
		push	ax
		call	_write_contrl
		add	sp, 4
		mov	sp, bp
		pop	bp
		ret
;
fillr_mode	equ	(word ptr  (18))[bp]
fillr_ink	equ	(word ptr  (16))[bp]
fillr_pattern	equ	(word ptr  (14))[bp]
fillr_solid	equ	(word ptr  (12))[bp]
fillr_y1	equ	(word ptr  (10))[bp]
fillr_x1	equ	(word ptr   (8))[bp]
fillr_y0	equ	(word ptr   (6))[bp]
fillr_x0	equ	(word ptr   (4))[bp]
fillr_curpat	equ	(word ptr  (-2))[bp]
fillr_op	equ	(word ptr  (-4))[bp]
fillr_plane	equ	(word ptr  (-6))[bp]

;
FILLRECT:	call	__csv
		db	8
		mov	ax, fillr_solid
		cmp	ax, 1
		jz	fillrect1
		jmp	fillrect2
;
fillrect1:	mov	ax, 6
		mov	fillr_pattern, ax
fillrect2:	mov	ax, CMD_ZOOM		;ZOOM
		push	ax
		call	write_command
		inc	sp
		inc	sp
		xor	ax, ax		;No zoom
		push	ax
		call	write_param
		inc	sp
		inc	sp
		mov	ax, fillr_pattern
		shl	ax, 1		;*2
		shl	ax, 1		;*4
		shl	ax, 1		;*8
		SUBAXW	8		;*8-8   Why not DEC AX at the start?
		shl	ax, 1		;*16-16 
		push	ax
		lea	si, fill_patterns
		pop	ax
		add	si, ax
		push	si
		mov	ax, 8
		push	ax
		mov	ax, CMD_PRAM + 8
		push	ax
		call	send_command
		add	sp, 6
		xor	ax, ax
		mov	fillr_plane, ax
fillrect3:	mov	ax, fillr_plane
		cmp	ax, 3
		jle	fillrect4
		jmp	fillrect_end
;
fillrect4:	mov	ax, fillr_mode
		push	ax
		jmp	fillrect19
;
fillrect5:	mov	ax, fillr_ink
		shl	ax, 1
		push	ax
		lea	si, MAP_COL
		pop	ax
		add	si, ax
		push	word ptr [si]
		push	word ptr fillr_plane
		mov	ax, 1
		pop	cx
		shl	ax, cl
		pop	si
		and	ax, si
		or	ax, ax
		jnz	fillrect6
		jmp	fillrect7
;
fillrect6:	mov	ax, 3
		mov	fillr_op, ax
		jmp	fillrect8

fillrect7:	mov	ax, 2
		mov	fillr_op, ax
fillrect8:	jmp	fillrect20
;
fillrect9:	mov	ax, fillr_ink
		shl	ax, 1
		push	ax
		lea	si, MAP_COL		
		pop	ax
		add	si, ax
		push	word ptr [si]
		push	word ptr fillr_plane
		mov	ax, 1
		pop	cx
		shl	ax, cl
		pop	si
		and	ax, si
		or	ax, ax
		jnz	fillrect10
		jmp	fillrect11
;
fillrect10:	mov	ax, 3
		mov	fillr_op, ax
		jmp	fillrect12
;
fillrect11:	mov	ax, 2
		mov	fillr_op, ax
fillrect12:	jmp	fillrect20
;
fillrect13:	mov	ax, fillr_ink
		shl	ax, 1
		push	ax
		lea	si, MAP_COL
		pop	ax
		add	si, ax
		push	word ptr[si]
		push	word ptr fillr_plane
		mov	ax, 1
		pop	cx
		shl	ax, cl
		pop	si
		and	ax, si
		or	ax, ax
		jnz	fillrect14
		jmp	fillrect15
;
fillrect14:	mov	ax, 1
		mov	fillr_op, ax
		jmp	fillrect16
;
fillrect15:	mov	ax, -1
		mov	fillr_op, ax
fillrect16:	jmp	fillrect20
;
fillrect17:	mov	ax, 2
		mov	fillr_op, ax
		jmp	fillrect20
;
fillrect18:	jmp	fillrect20

fillrect19:	call	_switch
		dw	4
		dw	4, 3, 2, 1
sw_fillrect:	
		dw	offset fillrect20 - offset sw_fillrect
		dw	offset fillrect17 - offset sw_fillrect - 2
		dw	offset fillrect13 - offset sw_fillrect - 4
		dw	offset fillrect9  - offset sw_fillrect - 6
		dw	offset fillrect5  - offset sw_fillrect - 8

fillrect20:	mov	ax, fillr_op
		cmp	ax, -1
		jz	fillrect21
		jmp	fillrect22
;
fillrect21:	jmp	fillrect29
;
fillrect22:	mov	ax, CMD_WDAT
		or	ax, fillr_op
		push	ax
		call	write_command	;Set write mode
		inc	sp
		inc	sp
		push	word ptr fillr_plane
		push	word ptr fillr_y0
		push	word ptr fillr_x0
		call	_setcurpos
		add	sp, 6
		mov	ax, CMD_FIGS
		push	ax
		call	write_command
		inc	sp
		inc	sp
		mov	ax, 10h
		push	ax
		call	write_param
		inc	sp
		inc	sp
		mov	ax, fillr_x1
		cmp	ax, fillr_x0
		jg	fillrect23
		jmp	fillrect24
;
fillrect23:	mov	ax, fillr_x1
		sub	ax, fillr_x0
		push	ax
		jmp	fillrect25
;
fillrect24:	xor	ax, ax
		push	ax
fillrect25:	pop	ax
		mov	fillr_curpat, ax
		mov	ax, fillr_curpat
		ANDAXW	0FFh
		push	ax
		call	write_param
		inc	sp
		inc	sp
		mov	ax, 8
		push	ax
		mov	ax, fillr_curpat
		pop	cx
		sar	ax, cl
		ANDAXW	3Fh
		push	ax
		call	write_param
		inc	sp
		inc	sp
		mov	ax, fillr_y1
		cmp	ax, fillr_y0
		jge	fillrect26
		jmp	fillrect27

fillrect26:	mov	ax, fillr_y1
		sub	ax, fillr_y0
		ADDAXW	1
		push	ax
		jmp	fillrect28
;
fillrect27:	mov	ax, 1
		push	ax
fillrect28:	pop	ax
		mov	fillr_curpat, ax
		mov	ax, fillr_curpat
		ANDAXW	0FFh
		push	ax
		call	write_param
		inc	sp
		inc	sp
		mov	ax, 8
		push	ax
		mov	ax, fillr_curpat
		pop	cx
		sar	ax, cl
		ANDAXW	3Fh
		push	ax
		call	write_param
		inc	sp
		inc	sp
		mov	ax, fillr_curpat
		ANDAXW	0FFh
		push	ax
		call	write_param
		inc	sp
		inc	sp
		mov	ax, 8
		push	ax
		mov	ax, fillr_curpat
		pop	cx
		sar	ax, cl
		ANDAXW	3Fh
		push	ax
		call	write_param
		inc	sp
		inc	sp
		mov	ax, CMD_GCHARD
		push	ax
		call	write_command	
		inc	sp
		inc	sp
fillrect29:	lea	si, fillr_plane
		mov	ax, [si]
		ADDPSI	1
		jmp	fillrect3
;
fillrect_end:	mov	sp, bp
		pop	bp
		ret
;
; Draw character on graphics screen
;
gchar_mode	equ	(word ptr  (14))[bp]
gchar_direction	equ	(word ptr  (12))[bp]
gchar_ink	equ	(word ptr  (10))[bp]
gchar_y		equ	(byte ptr   (8))[bp]
gchar_x		equ	(byte ptr   (6))[bp]
gchar_ch	equ	(byte ptr   (4))[bp]
gchar_chaddr	equ	(word ptr  (-2))[bp]
gchar_md7220	equ	(word ptr  (-4))[bp]
gchar_plane	equ	(word ptr  (-6))[bp]
gchar_row	equ	(word ptr  (-8))[bp]


gchar:		call	__csv
		db	8
		xor	ax, ax
		mov	gchar_plane, ax
gchar1:		mov	ax, gchar_plane
		cmp	ax, 3
		jle	gchar2
		jmp	gchar_end
;
gchar2:		mov	ax, gchar_mode
		push	ax
		jmp	gchar17
;
gchar3:		xor	ax, ax
		mov	gchar_md7220, ax
		mov	ax, gchar_ink
		shl	ax, 1
		push	ax
		lea	si, MAP_COL
		pop	ax
		add	si, ax
		push	word ptr [si]
		push	word ptr gchar_plane
		mov	ax, 1
		pop	cx
		shl	ax, cl
		pop	si
		and	ax, si
		or	ax, ax
		jnz	gchar4
		jmp	gchar5
;
gchar4:		mov	ax, 1
		push	ax
		mov	ax, 7
		push	ax
		mov	ax, 3
		push	ax
		mov	ax, 20h
		push	ax
		mov	al, gchar_ch
		mov	ah, 0
		pop	si
		sub	ax, si
		pop	cx
		shl	ax, cl
		pop	si
		add	ax, si
		pop	si
		imul	si
		push	ax
		lea	si, font
		pop	ax
		add	si, ax
		MOVAX_SI	
		mov	gchar_chaddr, ax
		jmp	gchar6
;
gchar5:
		lea	si, font+7
		MOVAX_SI	
		mov	gchar_chaddr, ax
gchar6:		jmp	gchar18
;
gchar7:		mov	ax, gchar_ink
		shl	ax, 1
		push	ax
		lea	si, MAP_COL
		pop	ax
		add	si, ax
		push	word ptr [si]
		push	word ptr gchar_plane
		mov	ax, 1
		pop	cx
		shl	ax, cl
		pop	si
		and	ax, si
		or	ax, ax
		jnz	gchar8
		jmp	gchar9
;
gchar8:		mov	ax, 3
		mov	gchar_md7220, ax
		jmp	gchar10
;
gchar9:		mov	ax, 2
		mov	gchar_md7220, ax
gchar10:	mov	ax, 1
		push	ax
		mov	ax, 7
		push	ax
		mov	ax, 3
		push	ax
		mov	ax, 20h
		push	ax
		mov	al, gchar_ch
		mov	ah, 0
		pop	si
		sub	ax, si
		pop	cx
		shl	ax, cl
		pop	si
		add	ax, si
		pop	si
		imul	si
		push	ax
		lea	si, font
		pop	ax
		add	si, ax
		MOVAX_SI	
		mov	gchar_chaddr, ax
		jmp	gchar18
;
gchar11:	mov	ax, 1
		mov	gchar_md7220, ax
		mov	ax, gchar_ink
		shl	ax, 1
		push	ax
		lea	si, MAP_COL
		pop	ax
		add	si, ax
		push	word ptr [si]
		push	word ptr gchar_plane
		mov	ax, 1
		pop	cx
		shl	ax, cl
		pop	si
		and	ax, si
		or	ax, ax
		jnz	gchar12
		jmp	gchar13
;
gchar12:	mov	ax, 1
		push	ax
		mov	ax, 7
		push	ax
		mov	ax, 3
		push	ax
		mov	ax, 20h
		push	ax
		mov	al, gchar_ch
		mov	ah, 0
		pop	si
		sub	ax, si
		pop	cx
		shl	ax, cl
		pop	si
		add	ax, si
		pop	si
		imul	si
		push	ax
		lea	si, font
		pop	ax
		add	si, ax
		MOVAX_SI	
		mov	gchar_chaddr, ax
		jmp	gchar14
;
gchar13:	lea	si, font+7
		MOVAX_SI	
		mov	gchar_chaddr,ax
gchar14:	jmp	gchar18
;
gchar15:	mov	ax, 2
		mov	gchar_md7220, ax
		mov	ax, 1
		push	ax
		mov	ax, 7
		push	ax
		mov	ax, 3
		push	ax
		mov	ax, 20h
		push	ax
		mov	al, gchar_ch
		mov	ah, 0
		pop	si
		sub	ax, si
		pop	cx
		shl	ax, cl
		pop	si
		add	ax, si
		pop	si
		imul	si
		push	ax
		lea	si, font
		pop	ax
		add	si, ax
		MOVAX_SI
		mov	gchar_chaddr, ax
		jmp	gchar18

gchar16:	jmp	gchar18

gchar17:	call	_switch
		dw	4
		dw	4, 3, 2, 1
sw_gchar:
		dw	offset gchar18 - offset sw_gchar
		dw	offset gchar15 - offset sw_gchar - 2
		dw	offset gchar11 - offset sw_gchar - 4
		dw	offset gchar7  - offset sw_gchar - 6
		dw	offset gchar3  - offset sw_gchar - 8
;
gchar18:	mov	ax, CMD_PRAM + 8
		push	ax
		call	write_command	;Set pattern at PRAM+8
		inc	sp
		inc	sp
		xor	ax, ax
		mov	gchar_row, ax
gchar19:	mov	ax, gchar_row
		cmp	ax, 7
		jle	gchar20
		jmp	gchar21
;
gchar20:	lea	si, gchar_chaddr
		mov	ax, [si]
		SUBPSI	1
		MOVSI_AX
		mov	al, [si]
		mov	ah, 0
		push	ax
		call	write_param
		inc	sp
		inc	sp
		lea	si, gchar_row
		mov	ax, [si]
		ADDPSI	1
		jmp	gchar19
;
gchar21:	mov	ax, CMD_WDAT
		or	ax, gchar_md7220
		push	ax
		call	write_command	;Set write mode
		inc	sp
		inc	sp
		mov	ax, CMD_FIGS
		push	ax
		call	write_command
		inc	sp
		inc	sp
		mov	ax, 10h
		or	ax, gchar_direction
		push	ax
		call	write_param
		inc	sp
		inc	sp
		mov	ax, 1
		mov	gchar_row, ax
gchar22:	mov	ax, gchar_row
		cmp	ax, 6
		jle	gchar23
		jmp	gchar24
;
gchar23:	mov	ax, gchar_row
		shl	ax, 1
		push	ax
		lea	si, text_params
		pop	ax
		add	si, ax
		push	word ptr [si]
		call	write_param
		inc	sp
		inc	sp
		lea	si, gchar_row
		mov	ax, [si]
		ADDPSI	1
		jmp	gchar22
;
gchar24:	push	word ptr gchar_plane
		push	word ptr gchar_y
		push	word ptr gchar_x
		call	_setcurpos
		add	sp, 6
		mov	ax, CMD_GCHARD
		push	ax
		call	write_command
		inc	sp
		inc	sp
		lea	si, gchar_plane
		mov	ax, [si]
		ADDPSI	1
		jmp	gchar1

gchar_end:	mov	sp, bp
		pop	bp
		ret	
;

drawline_mode	equ	(word ptr  (14))[bp]
drawline_ink	equ	(word ptr  (12))[bp]
drawline_y1	equ	(word ptr  (10))[bp]
drawline_x1	equ	(word ptr   (8))[bp]
drawline_y0	equ	(word ptr   (6))[bp]
drawline_x0	equ	(word ptr   (4))[bp]

drawline_op	equ	(word ptr  (-2))[bp]
drawline_addr	equ	(word ptr  (-4))[bp]
drawline_step2	equ	(word ptr  (-6))[bp]
drawline_step1	equ	(word ptr  (-8))[bp]
drawline_octant	equ	(word ptr (-10))[bp]
drawline_deltay	equ	(word ptr (-12))[bp]
drawline_deltax	equ	(word ptr (-14))[bp]
drawline_plane	equ	(word ptr (-16))[bp]
drawline_params	equ	(word ptr (-34))[bp]

DRAWLINE:	call	__csv
		db	22h
		mov	ax, drawline_x1
		sub	ax, drawline_x0
		mov	drawline_deltax, ax
		mov	ax, drawline_y1
		sub	ax, drawline_y0
		mov	drawline_deltay, ax
		push	word ptr drawline_deltay
		push	word ptr drawline_deltax
		call	octant
		add	sp, 4
		mov	drawline_octant, ax
		push	word ptr drawline_deltax
		call	_abs
		inc	sp
		inc	sp
		mov	drawline_deltax, ax
		push	word ptr drawline_deltay
		call	_abs
		inc	sp
		inc	sp
		mov	drawline_deltay, ax
		mov	ax, drawline_deltax
		cmp	ax, drawline_deltay
		jg	drawline1
		jmp	drawline2
;
drawline1:	mov	ax, drawline_deltax
		push	ax
		jmp	drawline3
;
drawline2:	mov	ax, drawline_deltay
		push	ax
drawline3:	pop	ax
		mov	drawline_step1, ax
		mov	ax, drawline_deltax
		cmp	ax, drawline_deltay
		jl	drawline4
		jmp	drawline5
;
drawline4:	mov	ax, drawline_deltax
		push	ax
		jmp	drawline6
;
drawline5:	mov	ax, drawline_deltay
		push	ax
drawline6:	pop	ax
		mov	drawline_step2, ax
		mov	ax, 8
		or	ax, drawline_octant
		push	ax
		lea	si, drawline_params
		pop	ax
		mov	[si], ax
		mov	ax, drawline_step1
		ANDAXW	0FFh
		push	ax
		lea	si, drawline_params+2
		pop	ax
		mov	[si], ax
		mov	ax, 8
		push	ax
		mov	ax, drawline_step1
		pop	cx
		sar	ax, cl
		ANDAXW	3Fh
		push	ax
		lea	si, drawline_params+4
		pop	ax
		mov	[si], ax
		push	word ptr drawline_step2
		mov	ax, 2
		pop	si
		mul	si
		sub	ax, drawline_step1
		mov	drawline_addr, ax
		mov	ax, drawline_addr
		ANDAXW	0FFh
		push	ax
		lea	si, drawline_params+6
		pop	ax
		mov	[si], ax
		mov	ax, 8
		push	ax
		mov	ax, drawline_addr
		pop	cx
		sar	ax, cl
		ANDAXW	03Fh
		push	ax
		lea	si, drawline_params+8
		pop	ax
		mov	[si], ax
		mov	ax, drawline_step2
		sub	ax, drawline_step1
		push	ax
		mov	ax, 2
		pop	si
		mul	si
		mov	drawline_addr, ax
		mov	ax, drawline_addr
		ANDAXW	0FFh
		push	ax
		lea	si, drawline_params+10
		pop	ax
		mov	[si], ax
		mov	ax, 8
		push	ax
		mov	ax, drawline_addr
		pop	cx
		sar	ax, cl
		ANDAXW	3Fh
		push	ax
		lea	si, drawline_params+12
		pop	ax
		mov	[si], ax
		push	word ptr drawline_step2
		mov	ax, 2
		pop	si
		mul	si
		mov	drawline_addr, ax
		mov	ax, drawline_addr
		ANDAXW	0FFh
		push	ax
		lea	si, drawline_params+14
		pop	ax
		mov	[si], ax
		mov	ax, 8
		push	ax
		mov	ax, drawline_addr
		pop	cx
		sar	ax, cl
		ANDAXW	03Fh
		push	ax
		lea	si, drawline_params+16
		pop	ax
		mov	[si], ax
		xor	ax, ax
		mov	drawline_plane, ax
drawline7:	mov	ax, drawline_plane
		cmp	ax, 3
		jle	drawline8
		jmp	line_end
;
drawline8:	mov	ax, drawline_mode
		push	ax
		jmp	drawline19
;
drawline9:	mov	ax, drawline_ink
		shl	ax, 1
		push	ax
		lea	si, MAP_COL
		pop	ax
		add	si, ax
		push	word ptr [si]
		push	word ptr drawline_plane
		mov	ax, 1
		pop	cx	
		shl	ax, cl
		pop	si
		and	ax, si
		or	ax, ax
		jnz	drawline10
		jmp	drawline11
;
drawline10:	mov	ax, 3
		mov	drawline_op, ax
		jmp	drawline12
;
drawline11:	mov	ax, 2
		mov	drawline_op, ax
drawline12:	jmp	drawline20
;
drawline13:	mov	ax, drawline_ink
		shl	ax, 1
		push	ax
		lea	si, MAP_COL
		pop	ax
		add	si, ax
		push	word ptr [si]
		push	word ptr drawline_plane
		mov	ax, 1
		pop	cx
		shl	ax, cl
		pop	si
		and	ax, si
		or	ax, ax
		jnz	drawline14
		jmp	drawline15
;
drawline14:	mov	ax, 1
		mov	drawline_op, ax
		jmp	drawline16
;
drawline15:	mov	ax, -1
		mov	drawline_op, ax
drawline16:	jmp	drawline20
;
drawline17:	mov	ax, 2
		mov	drawline_op, ax
		jmp	drawline20
;
drawline18:	jmp	drawline20
;
drawline19:	call	_switch
		dw	4
		dw	4, 3, 2, 1
sw_drawline:
		dw	offset drawline20 - offset sw_drawline
		dw	offset drawline17 - offset sw_drawline - 2	
		dw	offset drawline13 - offset sw_drawline - 4	
		dw	offset drawline9  - offset sw_drawline - 6	
		dw	offset drawline9  - offset sw_drawline - 8	

drawline20:	mov	ax, drawline_op
		cmp	ax, -1
		jz	drawline21
		jmp	drawline22
;
drawline21:	jmp	drawline23
;
drawline22:	mov	ax, CMD_WDAT
		or	ax, drawline_op
		push	ax
		call	write_command
		inc	sp
		inc	sp
		lea	ax, drawline_params
		push	ax
		mov	ax, 9
		push	ax
		mov	ax, CMD_FIGS
		push	ax
		call	send_command
		add	sp, 6
		push	drawline_plane
		push	drawline_y0
		push	drawline_x0
		call	_setcurpos
		add	sp, 6
		mov	ax, CMD_FIGD
		push	ax
		call	write_command
		inc	sp
		inc	sp
drawline23:	lea	si, drawline_plane
		mov	ax, [si]
		ADDPSI	1
		jmp	drawline7
;
line_end:	mov	sp, bp
		pop	bp
		ret
;
oct_deltay	equ	6[bp]
oct_deltax	equ	4[bp]

octant:		call	__csv0
		mov	ax, oct_deltax
		cmp	ax, 0
		jg	octant1
		jmp	octant15
;
octant1:	mov	ax, oct_deltay
		cmp	ax, 0
		jg	octant2
		jmp	octant7
;
octant2:	mov	ax, oct_deltay
		cmp	ax, oct_deltax
		jg	octant3
		jmp	octant4
;
octant3:	xor	ax, ax
		push	ax
		jmp	octant5
;
octant4:	mov	ax, 1
		push	ax
octant5:	pop	ax
		mov	sp, bp
		pop	bp
		ret
;
octant6:	jmp	octant14
octant7:	mov	ax, oct_deltay
		cmp	ax, 0
		jz	octant8
		jmp	octant10
;
octant8:	mov	ax, 2
		mov	sp, bp
		pop	bp
		ret
;
octant9:	jmp	octant14
;
octant10:	mov	si, oct_deltax
		push	si
		mov	ax, oct_deltay
		neg	ax
		pop	si
		cmp	ax, si
		jl	octant11
		jmp	octant12
;
octant11:	mov	ax, 2
		push	ax
		jmp	octant13
;
octant12:	mov	ax, 3
		push	ax
octant13:	pop	ax
		mov	sp, bp
		pop	bp
		ret
;
octant14:	jmp	octant_end
;
octant15:	mov	ax, oct_deltax
		cmp	ax, 0
		jz	octant16
		jmp	octant21
;
octant16:	mov	ax, oct_deltay
		cmp	ax, 0
		jg	octant17
		jmp	octant18
;
octant17:	xor	ax, ax
		push	ax
		jmp	octant19
;
octant18:	mov	ax, 4
		push	ax
octant19:	pop	ax
		mov	sp, bp
		pop	bp
		ret
;
octant20:	jmp	octant_end
;
octant21:	mov	ax, oct_deltay
		cmp	ax, 0
		jg	octant22
		jmp	octant27
;
octant22:	mov	si, oct_deltay
		push	si
		mov	ax, oct_deltax
		neg	ax
		pop	si
		cmp	ax, si
		jg	octant23
		jmp	octant24
;
octant23:	mov	ax, 6
		push	ax
		jmp	octant25
;
octant24:	mov	ax, 7
		push	ax
octant25:	pop	ax
		mov	sp, bp
		pop	bp
		ret
;
octant26:	jmp	octant_end
;
octant27:	mov	ax, oct_deltay
		cmp	ax, 0
		jz	octant28
		jmp	octant30
;
octant28:	mov	ax, 6
		mov	sp, bp
		pop	bp
		ret
;
octant29:	jmp	octant_end
;
octant30:	mov	ax, oct_deltax
		neg	ax
		push	ax
		mov	ax, oct_deltay
		neg	ax
		pop	si
		cmp	ax, si
		jg	octant31
		jmp	octant32
;
octant31:	mov	ax, 4
		push	ax
		jmp	octant33
;
octant32:	mov	ax, 5
		push	ax
octant33:	pop	ax
		mov	sp, bp
		pop	bp
		ret
;
octant_end:	mov	sp, bp
		pop	bp
		ret
;
scp_plane	equ	(word ptr  (8))[bp]
scp_y		equ	(word ptr  (6))[bp]
scp_x		equ	(word ptr  (4))[bp]
scp_addrhi	equ	(word ptr (-2))[bp]
scp_addrlo	equ	(word ptr (-4))[bp]

_setcurpos:	call	__csv
		db	4
		mov	ax, 4
		push	ax
		mov	ax, scp_x
		pop	cx
		sar	ax, cl
		push	ax
		mov	ax, 40h
		push	ax
		push	scp_y
		pop	ax
		pop	si
		mul	si	
		pop	si
		add	ax, si
		cwd
		mov	scp_addrhi, dx
		mov	scp_addrlo, ax
		mov	ax, CMD_CURS
		push	ax
		call	write_command
		inc	sp
		inc	sp
		mov	ax, 0FFh
		cwd
		push	dx
		push	ax
		push	scp_addrhi
		push	scp_addrlo
		pop	ax
		pop	dx
		pop	si
		pop	di
		and	ax, si
		and	dx, di		;32-bit arithmetic just to get one
		push	dx		;byte of a DWORD. Ouch!
		push	ax
		call	write_param
		add	sp, 4

		mov	ax, 0FFh
		cwd
		push	dx
		push	ax
		mov	ax, 8
		cwd
		push	dx
		push	ax
		push	scp_addrhi
		push	scp_addrlo
		pop	ax
		pop	dx
		pop	cx
		pop	bx
		call	sar_dxax
		pop	si
		pop	di
		and	ax, si
		and	dx, di		;Ouch again!
		push	dx
		push	ax
		call	write_param
		add	sp, 4
		mov	ax, 4
		push	ax
		mov	ax, scp_x
		ANDAXW	0Fh
		pop	cx
		shl	ax, cl
		or	ax, scp_plane
		push	ax
		call	write_param
		inc	sp
		inc	sp
		mov	sp, bp
		pop	bp
		ret
;
gpix_plane	equ	(word ptr  (8))[bp]
gpix_y		equ	(word ptr  (6))[bp]
gpix_x		equ	(word ptr  (4))[bp]
gpix_result	equ	(word ptr (-2))[bp]

_GETPIXEL:	call	__csv
		db	2
		push	gpix_plane
		push	gpix_y
		mov	ax, gpix_x
		ANDAXW	0FFF0h
		push	ax
		call	_setcurpos
		add	sp, 6
		lea	ax, getpix_params	
		push	ax
		mov	ax, 3
		push	ax
		mov	ax, CMD_FIGS
		push	ax
		call	send_command
		add	sp, 6
		mov	ax, CMD_RDAT
		push	ax
		call	write_command
		inc	sp
		inc	sp
		call	read_param
		ANDAXW	0FFh
		mov	gpix_result, ax
		mov	ax, 8
		push	ax
		call	read_param
		pop	cx
		shl	ax, cl
		push	ax
		mov	ax, gpix_result
		pop	si
		or	ax, si
		mov	gpix_result, ax
		mov	ax, gpix_result
		mov	sp, bp
		pop	bp
		ret
		
		mov	sp, bp
		pop	bp
		ret
;
; Write to the 7220's command register.
;
wc_value	equ	(word ptr  (4))[bp]
wc_byte		equ	(byte ptr (-2))[bp]
;
write_command:	call	__csv
		db	2
		mov	ax, wc_value
		ANDAXW	0FFh
		mov	wc_byte, al
wc_1:		mov	ax, GDC_PARAM
		push	ax
		call	_inportb
		inc	sp
		inc	sp
		ANDAXW	2	;'Busy' bit?
		or	ax, ax
		jnz	wc_2
		jmp	wc_3
wc_2:		jmp	wc_1	;Spaghetti junction we have here
wc_3:		mov	al, wc_byte
		mov	ah, 0
		push	ax
		mov	ax, GDC_COMMAND
		push	ax
		call	_outportb
		add	sp, 4
		mov	sp, bp
		pop	bp
		ret

wp_value	equ	(word ptr  (4))[bp]
wp_byte		equ	(byte ptr (-2))[bp]
;
write_param:	call	__csv
		db	2
		mov	ax, wp_value
		ANDAXW	0FFh
		mov	wp_byte, al
wp_1:		mov	ax, GDC_PARAM
		push	ax
		call	_inportb
		inc	sp
		inc	sp
		ANDAXW	2	;'Busy' bit?
		or	ax, ax
		jnz	wp_2
		jmp	wp_3
wp_2:		jmp	wp_1	
wp_3:		mov	al, wp_byte
		mov	ah, 0
		push	ax
		mov	ax, GDC_PARAM
		push	ax
		call	_outportb
		add	sp, 4
		mov	sp, bp
		pop	bp
		ret
;
rp_result	equ	(word ptr (-2))[bp]

read_param:	call	__csv
		db	2
rp_1:		xor	si, si
		push	si
		mov	ax, GDC_PARAM
		push	ax
		call	_inportb
		inc	sp
		inc	sp
		ANDAXW	1	;GDC has data for host?
		pop	si
		cmp	ax, si
		jz	rp_2
		jmp	rp_3
rp_2:		jmp	rp_1
rp_3:		mov	ax, GDC_COMMAND
		push	ax
		call	_inportb
		inc	sp
		inc	sp
		mov	rp_result, ax
		mov	ax, rp_result
		mov	sp, bp
		pop	bp
		ret

		mov	sp, bp
		pop	bp
		ret
;
_out_2f2:	call	__csv
		db	2
		mov	ax, wc_value
		ANDAXW	0FFh
		mov	wc_byte, al
		mov	al, wc_byte
		mov	ah, 0
		push	ax
		mov	ax, 02F2h	;XXX
		push	ax
		call	_outportb
		add	sp, 4
		mov	sp, bp
		pop	bp
		ret
;
_out_2f6:	call	__csv
		db	2
		mov	ax, wc_value
		ANDAXW	0FFh
		mov	wc_byte, al
		mov	al, wc_byte
		mov	ah, 0
		push	ax
		mov	ax, 02F6h	;XXX
		push	ax
		call	_outportb
		add	sp, 4
		mov	sp, bp
		pop	bp
		ret

sendc_params	equ	(word ptr  (8))[bp]
sendc_parcount	equ	(word ptr  (6))[bp]
sendc_command	equ	(word ptr  (4))[bp]
sendc_n		equ	(word ptr (-2))[bp]

send_command:	call	__csv
		db	2
		push	sendc_command
		call	write_command
		inc	sp
		inc	sp
		xor	ax,ax 
		mov	sendc_n, ax
sendc_1:	mov	ax, sendc_n
		cmp	ax, sendc_parcount
		jl	sendc_2
		jmp	sendc_end
;
sendc_2:	mov	ax, sendc_n
		shl	ax, 1
		push	ax
		mov	si, sendc_params
		pop	ax
		add	si, ax
		push	word ptr [si]
		call	write_param
		inc	sp
		inc	sp
		lea	si, sendc_n
		mov	ax, [si]
		ADDPSI	1
		jmp	sendc_1
;
sendc_end:	mov	sp, bp
		pop	bp
		ret
	
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
		db	0
		db	0

