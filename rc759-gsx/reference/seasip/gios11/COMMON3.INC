		cseg

;		S u b r	o u t i	n e

_switch:		; CODE XREF: vq_curaddress+21p
					; cseg:13B8p ...
		pop	di		; Return address
		pop	ax		; Parameter
		push	es
		mov	bx, cs
		mov	es, bx		; ES = CS
	
		mov	cx, es:[di]	; Count
		mov	bx, cx
		shl	bx, 1		; *2
		add	di, bx		; Add to jump table
		inc	cx
		std	
		repne scasw
		pop	es
	
		add	di, 4
		add	di, bx
;;;		add	di, cs:[di]	; +offset
		ADDPDI
		jmp	di
;




fc_regs		equ	(word ptr  (12))[bp]
fc_addr		equ	(dword ptr  (8))[bp]

;		S u b r	o u t i	n e
; (DWORD addr, WORD *regs)

_far_call:		; CODE XREF: _read_key+39p
					; _getkey+31p ...
		push	ds
		push	es
		push	bp
		mov	bp, sp
		mov	bx, fc_regs
		call	load_regs2
		callf	fc_addr
		pushf	
		call	save_regs2
		pop	ax
		pop	bp
		pop	es
		pop	ds
		retn	





;		S u b r	o u t i	n e

load_regs2:		; CODE XREF: _far_call+8p
		mov	cx, 8

load_regs3:				; CODE XREF: load_regs2+7j
		push	word ptr [bx]
		inc	bx
		inc	bx
		loop	load_regs3
		pop	es
		pop	ds
		pop	di
		pop	si
		pop	dx
		pop	cx
		pop	bx
		pop	ax
		retn	




savereg2_buf	equ	(word ptr (14))[bp]

;		S u b r	o u t i	n e

save_regs2:		; CODE XREF: _far_call+Fp
		push	es
		push	ds
		push	di
		push	si
		push	dx
		push	cx
		push	bx
		push	ax
		mov	bx, savereg2_buf
		mov	cx, 8

save_regs3:				; CODE XREF: save_regs2+13j
		pop	ss:word ptr [bx]
		inc	bx
		inc	bx
		loop	save_regs3
		retn	




farpeek_addr	equ	(dword ptr (4))[bp]

;		S u b r	o u t i	n e

_farpeekw:		; CODE XREF: init_gdosptr+3Ep
					; init_gdosptr+62p
		push	bp
		mov	bp, sp
		push	es
		les	si, farpeek_addr
		mov	ax, es:[si]
		pop	es
		pop	bp
		retn	



int86_oregs	equ	(word ptr (12))[bp]
int86_iregs	equ	(word ptr (10))[bp]
int86_int	equ	(byte ptr  (8))[bp]

;		S u b r	o u t i	n e

__int86:		; CODE XREF: init_gdosptr+1Ep
		push	ds
		push	es
		push	bp
		mov	bp, sp
		mov	ax, int86_oregs
		push	ax
		pushf	
		pop	dx
		push	dx
		push	cs
		call	__intcall





;		S u b r	o u t i	n e

__intcall:
		pop	ax
		sub	ax, 10h
		add	ax, 35h
		push	ax
		and	dh, 0Ch
		push	dx		; Flags
		xor	bx, bx
		mov	es, bx		; 0000:0000
	
		mov	bl, int86_int
		shl	bx, 1
		shl	bx, 1
		push	es:word ptr 2[bx]
		push	es:word ptr [bx]
		mov	bx, int86_iregs
		call	load_regs
		iret	





;		S u b r	o u t i	n e

__intret:
		pushf	
		call	save_regs
		pop	ax
		pop	bp
		pop	bp
		pop	es
	
		pop	ds
		retn	





;		S u b r	o u t i	n e

load_regs:		; CODE XREF: __intcall+21p
		mov	cx, 8

load_regs1:				; CODE XREF: load_regs+7j
		push	word ptr [bx]
		inc	bx
		inc	bx
		loop	load_regs1
		pop	es
		pop	ds
		pop	di
		pop	si
		pop	dx
		pop	cx
		pop	bx
		pop	ax
		retn	




savereg_buf	equ	(word ptr (20))[bp]

;		S u b r	o u t i	n e

save_regs:		; CODE XREF: __intret+1p
		push	es
		push	ds
		push	di
		push	si
		push	dx
		push	cx
		push	bx
		push	ax
		mov	bp, sp
		mov	bx, savereg_buf
		mov	cx, 8

save_regs1:				; CODE XREF: save_regs+15j
		pop	ss:word ptr [bx]
		inc	bx
		inc	bx
		loop	save_regs1
		retn	



		dseg



