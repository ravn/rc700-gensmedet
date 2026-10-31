		cseg

;		S u b r	o u t i	n e

abs_arg		equ	(word ptr 4)[bp]

_abs:		; CODE XREF: D_GTEXT+C2p
		call	__csv0
		mov	ax, abs_arg
		cmp	ax, 0
		jl	abs1
		jmp	abs3


abs1:					; CODE XREF: _abs+9j
		mov	ax, abs_arg
		neg	ax
		mov	sp, bp
		pop	bp
		retn	


abs2:
		jmp	abs4


abs3:					; CODE XREF: _abs+Bj
		mov	ax, abs_arg
		mov	sp, bp
		pop	bp
		retn	


abs4:					; CODE XREF: _abs+17j
		mov	sp, bp
		pop	bp
		retn	




clamp_limit2	equ	8[bp]
clamp_limit1	equ	6[bp]
clamp_val	equ	4[bp]

;		S u b r	o u t i	n e

_clamp:		; CODE XREF: v_opnwk+CDp v_opnwk+116p
					; ...
		call	__csv0
		mov	ax, clamp_val
		cmp	ax, clamp_limit1
		jl	clamp1
		jmp	clamp3


clamp1:					; CODE XREF: _clamp+9j
		mov	ax, clamp_limit1
		mov	sp, bp
		pop	bp
		retn	


clamp2:
		jmp	clamp7


clamp3:					; CODE XREF: _clamp+Bj
		mov	ax, clamp_val
		cmp	ax, clamp_limit2
		jg	clamp4
		jmp	clamp6


clamp4:					; CODE XREF: _clamp+1Ej
		mov	ax, clamp_limit2
		mov	sp, bp
		pop	bp
		retn	


clamp5:
		jmp	clamp7


clamp6:					; CODE XREF: _clamp+20j
		mov	ax, clamp_val
		mov	sp, bp
		pop	bp
		retn	




clamp7:					; CODE XREF: _clamp+15j _clamp+2Aj
		mov	sp, bp
		pop	bp
		retn	


arg2		equ	(word ptr 6)[bp]
arg1		equ	(word ptr 4)[bp]

;		S u b r	o u t i	n e

_multiply:		; CODE XREF: v_cellarray+13Bp
					; vst_direction+3Bp ...
		call	__csv0
		push	word ptr arg2
		push	word ptr arg1
		pop	ax
		pop	si
		mul	si
		mov	sp, bp
		pop	bp
		retn	



		mov	sp, bp
		pop	bp
		retn	



;		S u b r	o u t i	n e

_min:
		call	__csv0
		mov	ax, arg1
		cmp	ax, arg2
		jl	min1
		jmp	min3


min1:					; CODE XREF: _min+9j
		mov	ax, arg1
		mov	sp, bp
		pop	bp
		retn	


min2:
		jmp	min4


min3:					; CODE XREF: _min+Bj
		mov	ax, arg2
		mov	sp, bp
		pop	bp
		retn	




min4:					; CODE XREF: _min+15j
		mov	sp, bp
		pop	bp
		retn	



;		S u b r	o u t i	n e

max:
		call	__csv0
		mov	ax, arg1
		cmp	ax, arg2
		jg	max1
		jmp	max3


max1:					; CODE XREF: max+9j
		mov	ax, arg1
		mov	sp, bp
		pop	bp
		retn	


max2:
		jmp	max4


max3:					; CODE XREF: max+Bj
		mov	ax, arg2
		mov	sp, bp
		pop	bp
		retn	




max4:					; CODE XREF: max+15j
		mov	sp, bp
		pop	bp
		retn	


div_remainder	equ	(word ptr  8)[bp]
div_rem1	equ	(word ptr -2)[bp]

;		S u b r	o u t i	n e

_divide:		; CODE XREF: v_cellarray+B4p
					; v_cellarray+F4p ...
		call	__csv

		db	2

		mov	si, arg2
		push	si
		mov	ax, arg1
		pop	si
		or	si, si
		jz	div1
		cwd	
		idiv	si

div1:					; CODE XREF: _divide+Ej
		mov	div_rem1,	ax
		push	word ptr arg2
		push	word ptr div_rem1
		pop	ax
		pop	si
		mul	si
		push	ax
		mov	ax, arg1
		pop	si
		sub	ax, si
		push	ax
		mov	si, div_remainder
		pop	ax
		mov	[si], ax
		mov	ax, div_rem1
		mov	sp, bp
		pop	bp
		retn	




div2:
		mov	sp, bp
		pop	bp
		retn	
;
; Device-specific code
;



;		S u b r	o u t i	n e

init_gdosptr:		; CODE XREF: _read_key+Fp _getkey+Fp
					; ...
		call	__csv0
		lea	si, registers
;;;		add	si, 4
		ADDSIW	4
		mov	ax, 1673h	; CX = 1673h
		mov	[si], ax	; Get table entry for drv 1
		lea	si, registers
		push	si
		lea	si, registers
		push	si
		mov	ax, 0E0h
		push	ax
		call	__int86
		add	sp, 6
		lea	si, registers
;;;		add	si, 0Eh		; Get ES
		ADDSIW	0Eh
		push	word ptr [si]	; Push ES
		lea	si, registers
;;;		add	si, 2		; Get BX
		ADDSIW	2
		push	word ptr [si]	; Push BX
		pop	ax
;;;		add	ax, 1		; ++bx
		ADDAXW	1
		push	ax
		call	_farpeekw	; Get driver entry point offset
		add	sp, 4
;;;		mov	gdos_offset, ax
		SAXW	gdos_offset
		lea	si, registers
;;;		add	si, 0Eh
		ADDSIW	0Eh
		push	word ptr [si]	; Get ES again
		lea	si, registers
;;;		add	si, 2
		ADDSIW	2
		push	word ptr [si]	; Get BX
		pop	ax
;;;		add	ax, 3
		ADDAXW	3
		push	ax
		call	_farpeekw
		add	sp, 4
;;;		mov	gdos_segment, ax	;And driver entry point segment
		SAXW	gdos_segment
		mov	sp, bp
		pop	bp
		retn	


readkey_result	equ	(word ptr 4)[bp]


;		S u b r	o u t i	n e

_read_key:		; CODE XREF: cseg:1323p vrq_choice+47p
		call	__csv0
;;;		mov	ax, gdos_segment
		LAXW	gdos_segment
		cmp	ax, 0FFFFh
		jz	read_key1
		jmp	read_key2


read_key1:				; CODE XREF: _read_key+Aj
		call	init_gdosptr

read_key2:				; CODE XREF: _read_key+Cj
		mov	si, readkey_result
		mov	ax, 0FFFFh
		mov	[si], al
		lea	si, registers
;;;		add	si, 2
		ADDSIW	2
		mov	ax, 303h	; ????
		mov	[si], ax
		lea	si, registers
		push	si
		lea	si, registers
		push	si
		push	gdos_segment
		push	gdos_offset
		call	_far_call	; (DWORD addr, WORD *regs)
		add	sp, 8
		xor	si, si
		push	si
		lea	si, registers
		push	word ptr [si]
		pop	ax
		pop	si
		cmp	ax, si
		jl	read_key3
		jmp	read_key4


read_key3:				; CODE XREF: _read_key+4Cj
		lea	si, registers
;;;		add	si, 6
		ADDSIW	6
		push	word ptr [si]
		pop	ax
;;;		and	ax, 0FFh
		ANDAXW	0FFh
		push	ax
		mov	si, readkey_result
		pop	ax
		mov	[si], al

read_key4:				; CODE XREF: _read_key+4Ej
		mov	sp, bp
		pop	bp
		retn	



		mov	sp, bp
		pop	bp
		retn	



;		S u b r	o u t i	n e

_getkey:		; CODE XREF: cseg:1300p vrq_choice+24p
					; ...
		call	__csv0
;;;		mov	ax, gdos_segment
		LAXW	gdos_segment
		cmp	ax, 0FFFFh
		jz	getkey1
		jmp	getkey2


getkey1:				; CODE XREF: _getkey+Aj
		call	init_gdosptr

getkey2:				; CODE XREF: _getkey+Cj
		lea	si, registers
;;;		add	si, 2
		ADDSIW	2
		mov	ax, 203h	; BX = 0x203
		mov	[si], ax
		lea	si, registers
		push	si
		lea	si, registers
		push	si
		push	gdos_segment
		push	gdos_offset
		call	_far_call	; (DWORD addr, WORD *regs)
		add	sp, 8
		lea	si, registers
;;;		add	si, 6
		ADDSIW	6
		push	word ptr [si]
		pop	ax
;;;		and	ax, 0FFh
		ANDAXW	0FFh
		push	ax
		mov	si, readkey_result
		pop	ax
		mov	[si], al
		mov	sp, bp
		pop	bp
		retn	



		mov	sp, bp
		pop	bp
		retn	

putstr_data	equ	(word ptr  6)[bp]
putstr_len	equ	(word ptr  4)[bp]
putstr_pos	equ	(word ptr -2)[bp]

_putstr:				; CODE XREF: v_opnwk+229p v_enter_cur+14p
					; ...
		call	__csv	; (char	*p, unsigned len)

		db	2

		xor	ax, ax
		mov	putstr_pos,	ax

putstr1:				; CODE XREF: cseg:262Cj
		mov	ax, putstr_pos
		cmp	ax, putstr_len
		jl	putstr2
		jmp	putstr_end


putstr2:				; CODE XREF: cseg:2609j
		lea	si, putstr_data
		mov	ax, [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
;;;		mov	si, ax
		MOVSIAX
		mov	al, [si]
		mov	ah, 0
		push	ax
		call	_putchar
		inc	sp
		inc	sp
		lea	si, putstr_pos
		mov	ax, [si]
;;;		add	word ptr [si], 1
		ADDPSI	1
		jmp	putstr1


putstr_end:				; CODE XREF: cseg:260Bj
		mov	sp, bp
		pop	bp
		retn	

		mov	sp, bp
		pop	bp
		retn	


putchar_ch	equ	(byte ptr 4)[bp]

;		S u b r	o u t i	n e

_putchar:		; CODE XREF: v_eeos+33p v_eeos+3Cp
					; ...
		call	__csv0
;;;		mov	ax, gdos_segment
		LAXW	gdos_segment
		cmp	ax, 0FFFFh
		jz	putchar1
		jmp	putchar2


putchar1:				; CODE XREF: _putchar+Aj
		call	init_gdosptr

putchar2:				; CODE XREF: _putchar+Cj
		lea	si, registers
;;;		add	si, 2
		ADDSIW	2
		mov	ax, 603h	; BX :=	0x603
		mov	[si], ax
		mov	ax, 0FFh	; Mask
		push	ax
		mov	al, putchar_ch	; Character
		mov	ah, 0
		pop	si
		and	ax, si		; Mask to 0xFF (pointless!)
		push	ax
		lea	si, registers
;;;		add	si, 6
		ADDSIW	6
		pop	ax
		mov	[si], ax	; DX :=	parameter
		lea	si, registers
		push	si
		lea	si, registers
		push	si
		push	gdos_segment
		push	gdos_offset
		call	_far_call	; (DWORD addr, WORD *regs)
		add	sp, 8
		mov	sp, bp
		pop	bp
		retn	




putchar3:
		mov	sp, bp
		pop	bp
		retn	

rdec_result	equ	(word ptr 10)[bp]
rdec_outbuflen	equ	(word ptr  8)[bp]
rdec_outbuf	equ	(word ptr  6)[bp]
rdec__value	equ	(word ptr  4)[bp]
rdec_outend	equ	(word ptr -2)[bp]
rdec_outptr	equ	(word ptr -4)[bp]
rdec_value	equ	(word ptr -6)[bp]
rdec_digit	equ	(word ptr -8)[bp]

;		S u b r	o u t i	n e

render_decimal:
		call	__csv



		db	8

		xor	si, si
		push	si
		mov	ax, rdec__value
		mov	rdec_value,	ax
		pop	si
		cmp	ax, si
		jl	rdec2
		jmp	rdec3


rdec2:					; CODE XREF: cseg:269Ej
		mov	ax, rdec_value	; Number was negative, render as 
		neg	ax		; positive
		mov	rdec_value, ax

rdec3:					; CODE XREF: cseg:26A0j
		mov	si, rdec_result
		xor	ax, ax
		mov	[si], ax
		mov	ax, rdec_outbuf
		mov	rdec_outptr,	ax
		mov	si, rdec_outbuflen
		shl	si, 1
		push	si
		mov	ax, rdec_outptr
		pop	si
		add	ax, si
;;;		sub	ax, 2
		SUBAXW	2
		mov	rdec_outend,	ax

rdec4:					; CODE XREF: cseg:271Bj
		mov	ax, rdec_outptr
		cmp	ax, rdec_outend
		jbe	rdec5
		jmp	rdec6


rdec5:					; CODE XREF: cseg:26D1j
		lea	si, rdec_digit
		push	si
		mov	ax, 10
		push	ax
		push	word ptr rdec_value
		call	_divide
		add	sp, 6
		mov	rdec_value, ax
		mov	ax, rdec_digit
;;;		add	ax, '0'
		ADDAXW	'0'
		push	ax
		lea	si, rdec_outptr
		mov	ax, [si]
;;;		add	word ptr [si], 2
		ADDPSI	2
;;;		mov	si, ax
		MOVSIAX
		pop	ax
		mov	[si], ax
		jmp	rdec7


rdec6:					; CODE XREF: cseg:26D3j
		mov	si, rdec_result
		mov	ax, 1
		mov	[si], ax
		xor	ax, ax
		mov	sp, bp
		pop	bp
		retn	


rdec7:					; CODE XREF: cseg:2700j
		mov	ax, rdec_value
		cmp	ax, 0
		jnz	rdec8
		jmps	rdec9


rdec8:					; CODE XREF: cseg:2717j
		jmp	rdec4


rdec9:					; CODE XREF: cseg:2719j
		mov	ax, rdec__value
		cmp	ax, 0
		jl	rdeca
		jmp	rdecd


rdeca:					; CODE XREF: cseg:2724j
		mov	ax, rdec_outptr
		cmp	ax, rdec_outend
		jbe	rdecb
		jmp	rdecc


rdecb:					; CODE XREF: cseg:272Fj
		lea	si, rdec_outptr
		mov	ax, [si]
;;;		add	word ptr [si], 2
		ADDPSI	2
;;;		mov	si, ax
		MOVSIAX
		mov	ax, '-'
		mov	[si], ax
		jmp	rdecd


rdecc:					; CODE XREF: cseg:2731j
		mov	si, rdec_result
		mov	ax, 1
		mov	[si], ax
		xor	ax, ax
		mov	sp, bp
		pop	bp
		retn	


rdecd:					; CODE XREF: cseg:2726j cseg:2744j
		mov	si, 2
		push	si
		mov	ax, rdec_outptr
		sub	ax, rdec_outbuf
		pop	si
		or	si, si
		jz	rdece
		xor	dx, dx
		div	si

rdece:					; CODE XREF: cseg:2762j
		mov	rdec_digit,	ax
		mov	ax, rdec_outbuf
		mov	rdec_outptr,	ax
		mov	si, rdec_digit
		shl	si, 1
		push	si
		mov	ax, rdec_outptr
		pop	si
		add	ax, si
;;;		sub	ax, 2
		SUBAXW	2
		mov	rdec_outend,	ax

rdecf:					; CODE XREF: cseg:27BBj
		mov	ax, rdec_outptr
		cmp	ax, rdec_outend
		jb	rdec10
		jmp	rdec11


rdec10:					; CODE XREF: cseg:278Aj
		mov	si, rdec_outptr
		push	word ptr [si]
		pop	ax
		mov	rdec_value,	ax
		mov	si, rdec_outend
		push	word ptr [si]
		lea	si, rdec_outptr
		mov	ax, [si]
;;;		add	word ptr [si], 2
		ADDPSI	2
;;;		mov	si, ax
		MOVSIAX
		pop	ax
		mov	[si], ax
		lea	si, rdec_outend
		mov	ax, [si]
;;;		sub	word ptr [si], 2
		SUBPSI	2
;;;		mov	si, ax
		MOVSIAX
		mov	ax, rdec_value
		mov	[si], ax
		jmp	rdecf


rdec11:					; CODE XREF: cseg:278Cj
		mov	ax, rdec_digit
		mov	sp, bp
		pop	bp
		retn	


rdec12:
		mov	sp, bp
		pop	bp
		retn	

pdec_outlen	equ	(word ptr 10)[bp]
pdec_outptr	equ	(word ptr  8)[bp]
pdec_len	equ	(word ptr  6)[bp]
pdec_buffer	equ	(word ptr  4)[bp]

pdec_bufend	equ	(word ptr -2)[bp]
pdec_bufptr	equ	(word ptr -4)[bp]
pdec_negative	equ	(word ptr -6)[bp]
pdec_result	equ	(word ptr -8)[bp]

parse_decimal:
		call	__csv

		db	8

		mov	si, pdec_len
		shl	si, 1
		push	si
		mov	ax, pdec_buffer
		pop	si
		add	ax, si
		mov	pdec_bufptr,	ax
		mov	ax, pdec_bufptr
		mov	pdec_bufend,	ax

pdec2:					; CODE XREF: cseg:2811j
		mov	si, 20h
		push	si
		mov	si, pdec_bufptr
		push	word ptr [si]
		pop	ax
		pop	si
		cmp	ax, si
		jz	pdec3
		jmps	pdec4


pdec3:					; CODE XREF: cseg:27EFj
		jmp	pdec5


pdec4:					; CODE XREF: cseg:27F1j
		mov	si, 9
		push	si
		mov	si, pdec_bufptr
		push	word ptr [si]
		pop	ax
		pop	si
		cmp	ax, si
		jz	pdec5
		jmp	pdec6


pdec5:					; CODE XREF: cseg:27F3j cseg:2803j
		lea	si, pdec_bufptr
;;;		add	word ptr [si], 2
		ADDPSI	2
		mov	ax, [si]
		jmp	pdec2


pdec6:					; CODE XREF: cseg:2805j
		xor	ax, ax
		mov	pdec_negative,	ax
		mov	si, '-'
		push	si
		mov	si, pdec_bufptr
		push	word ptr [si]
		pop	ax
		pop	si
		cmp	ax, si
		jz	pdec7
		jmp	pdec8


pdec7:					; CODE XREF: cseg:2826j
		mov	ax, 1
		mov	pdec_negative,	ax
		jmp	pdeca


pdec8:					; CODE XREF: cseg:2828j
		mov	si, '+'
		push	si
		mov	si, pdec_bufptr
		push	word ptr [si]
		pop	ax
		pop	si
		cmp	ax, si
		jnz	pdec9
		jmp	pdeca


pdec9:					; CODE XREF: cseg:2841j
		lea	si, pdec_bufptr
;;;		sub	word ptr [si], 2
		SUBPSI	2
		mov	ax, [si]

pdeca:					; CODE XREF: cseg:2831j cseg:2843j
		lea	si, pdec_bufptr
;;;		add	word ptr [si], 2
		ADDPSI	2
		mov	ax, [si]
		xor	ax, ax
		mov	pdec_result,	ax

pdecb:					; CODE XREF: cseg:28A7j
		mov	si, '0'
		push	si
		mov	si, pdec_bufptr
		push	word ptr [si]
		pop	ax
		pop	si
		cmp	ax, si
		jge	pdecc
		jmp	pdecd


pdecc:					; CODE XREF: cseg:286Aj
		mov	si, '9'
		push	si
		mov	si, pdec_bufptr
		push	word ptr [si]
		pop	ax
		pop	si
		cmp	ax, si
		jle	pdece

pdecd:					; CODE XREF: cseg:286Cj
		jmp	pdecf


pdece:					; CODE XREF: cseg:287Cj
		lea	si, pdec_bufptr
		mov	ax, [si]
;;;		add	word ptr [si], 2
		ADDPSI	2
;;;		mov	si, ax
		MOVSIAX
		push	word ptr [si]
		pop	si
;;;		sub	si, 30h
		SUBSIW	30h
		push	si
		mov	ax, 0Ah
		push	ax
		push	word ptr pdec_result
		call	_multiply
		add	sp, 4
		pop	si
		add	ax, si
		mov	pdec_result,	ax
		jmp	pdecb


pdecf:					; CODE XREF: cseg:287Ej
		mov	ax, pdec_negative
		or	ax, ax
		jnz	pdec10
		jmp	pdec11


pdec10:					; CODE XREF: cseg:28AFj
		mov	ax, pdec_result
		neg	ax
		mov	pdec_result,	ax

pdec11:					; CODE XREF: cseg:28B1j
		mov	si, pdec_outptr
		mov	ax, pdec_result
		mov	[si], ax
		push	word ptr pdec_len
		mov	si, 2
		push	si
		mov	ax, pdec_bufptr
		sub	ax, pdec_bufend
		pop	si
		or	si, si
		jz	pdec12
		xor	dx, dx
		div	si

pdec12:					; CODE XREF: cseg:28D4j
		pop	si
		add	ax, si
		push	ax
		mov	si, pdec_outlen
		pop	ax
		mov	[si], ax
		mov	sp, bp
		pop	bp
		retn	


pdec13:
		mov	sp, bp
		pop	bp
		retn	
