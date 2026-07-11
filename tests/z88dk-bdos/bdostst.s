	GLOBAL	___fseek
	GLOBAL	_remove
	GLOBAL	_ftell
	GLOBAL	_sprintf
	GLOBAL	_fputc
	GLOBAL	___fopen
	GLOBAL	_fgetc
	GLOBAL	___memset
	GLOBAL	_fclose
	GLOBAL	_strlen
	GLOBAL	_bdos_callee
	GLOBAL	___strcat
	GLOBAL	_printf
	GLOBAL	_fprintf
	GLOBAL	___rename
	SECTION code_compiler
	GLOBAL	_main                           ; -- Begin function main
_main:                                  ; @main
; %bb_0:
	push	ix
	ld	ix,__sfrend_main
	ld	hl,L__str_1
	ld	de,L__str
	call	___fopen
	ex	de,hl
	ld	(_logfp),hl
	ld	hl,L__str_2
	call	_cout
	ld	hl,(_logfp)
	ld	a,l
	or	h
	jr	z,LBB0_2
; %bb_1:
	ex	de,hl
	ld	hl,L__str_2
	push	hl
	ex	de,hl
	push	hl
	call	_fprintf
	pop	af
	pop	af
LBB0_2:
	ld	hl,12
	ld	de,0
	call	_bdos_callee
	ld	d,0
	ld	b,d
	ld	a,e
	or	b
	add	a,255
	sbc	a,a
	and	1
	and	1
	ld	e,a
	ld	hl,L__str_3
	push	hl
	ld	hl,1
	call	_check
	ld	hl,25
	ld	de,0
	call	_bdos_callee
	ld	a,e
	and	240
	ld	e,a
	ld	d,0
	ld	b,d
	or	b
	sub	1
	sbc	a,a
	and	1
	and	1
	ld	e,a
	ld	hl,L__str_4
	push	hl
	ld	hl,2
	call	_check
	ld	hl,L__str_5
	call	_cout
	ld	hl,32
	ld	de,255
	call	_bdos_callee
	ld	a,e
	and	240
	ld	e,a
	ld	d,0
	ld	(__sfrend_main-82),de
	ld	hl,L__str_6
	call	_cout
	ld	de,0
	ld	hl,(__sfrend_main-82)
	ld	a,h
	xor	d
	ld	b,a
	ld	a,l
	xor	e
	or	b
	sub	1
	sbc	a,a
	and	1
	and	1
	ld	e,a
	ld	d,0
	ld	hl,L__str_7
	push	hl
	ld	hl,3
	call	_check
	ld	hl,L__str_8
	call	_cout
	ld	hl,6
	ld	de,255
	call	_bdos_callee
	ld	d,0
	ld	(__sfrend_main-82),de
	ld	hl,L__str_9
	call	_cout
	ld	de,0
	ld	hl,(__sfrend_main-82)
	ld	a,h
	xor	d
	ld	b,a
	ld	a,l
	xor	e
	or	b
	sub	1
	sbc	a,a
	and	1
	and	1
	ld	e,a
	ld	d,0
	ld	hl,L__str_10
	push	hl
	ld	hl,4
	call	_check
	ld	bc,0
LBB0_3:                                ; =>This Inner Loop Header: Depth=1
	ld	a,b
	xor	7
	ld	d,a
	ld	a,c
	xor	208
	or	d
	jr	z,LBB0_5
; %bb_4:                                ;   in Loop: Header=BB0_3 Depth=1
	ld	hl,_buf
	add	hl,bc
	ex	de,hl
	ld	a,c
	ld	(de),a
	inc	bc
	jr	LBB0_3
LBB0_5:
	ld	hl,L__str_12
	ld	de,L__str_11
	call	___fopen
	ld	hl,0
	ld	(__sfrend_main-88),de
	ld	a,d
	xor	h
	ld	b,a
	ld	a,e
	xor	l
	or	b
	add	a,255
	sbc	a,a
	and	1
	ld	(ix+-82),a
	and	1
	ld	e,a
	ld	d,0
	ld	hl,L__str_13
	push	hl
	ld	hl,5
	call	_check
	ld	a,(ix+-82)
	xor	1
	jr	nz,LBB0_12
; %bb_6:
	ld	bc,_buf
	ld	hl,2000
	ld	de,0
	ld	(__sfrend_main-86),de
LBB0_7:                                ; =>This Inner Loop Header: Depth=1
                                        ; kill: def $hl killed $hl def $l def $h
	ld	a,l
	or	h
	jr	z,LBB0_11
; %bb_8:                                ;   in Loop: Header=BB0_7 Depth=1
	ld	(__sfrend_main-84),hl
	ld	(__sfrend_main-82),bc
	ld	a,(bc)
	ld	l,a
	ld	h,0
	ld	de,(__sfrend_main-88)
	call	_fputc
	inc	de
	ld	a,e
	or	d
	jr	z,LBB0_10
; %bb_9:                                ;   in Loop: Header=BB0_7 Depth=1
	ld	de,(__sfrend_main-86)
	inc	de
	ld	(__sfrend_main-86),de
LBB0_10:                               ;   in Loop: Header=BB0_7 Depth=1
	ld	hl,(__sfrend_main-84)
	ld	bc,(__sfrend_main-82)
	inc	bc
	dec	hl
	jr	LBB0_7
LBB0_11:
	ld	de,2000
	ld	hl,(__sfrend_main-86)
	ld	a,h
	xor	d
	ld	b,a
	ld	a,l
	xor	e
	or	b
	sub	1
	sbc	a,a
	and	1
	and	1
	ld	e,a
	ld	d,0
	ld	hl,L__str_14
	push	hl
	ld	hl,6
	call	_check
	ld	hl,(__sfrend_main-88)
	call	_fclose
	ld	hl,0
	ld	a,d
	xor	h
	ld	b,a
	ld	a,e
	xor	l
	or	b
	sub	1
	sbc	a,a
	and	1
	and	1
	ld	e,a
	ld	d,0
	ld	hl,L__str_15
	push	hl
	ld	hl,7
	call	_check
LBB0_12:
	ld	hl,_buf
	push	hl
	ld	hl,2000
	ld	de,0
	call	___memset
	ld	hl,L__str_16
	ld	de,L__str_11
	call	___fopen
	ld	hl,0
	ld	(__sfrend_main-86),de
	ld	a,d
	xor	h
	ld	b,a
	ld	a,e
	xor	l
	or	b
	add	a,255
	sbc	a,a
	and	1
	ld	(ix+-82),a
	and	1
	ld	e,a
	ld	d,0
	ld	hl,L__str_17
	push	hl
	ld	hl,8
	call	_check
	ld	a,(ix+-82)
	xor	1
	jp	nz,LBB0_23
; %bb_13:
	ld	iy,_buf
	ld	bc,2000
LBB0_14:                               ; =>This Inner Loop Header: Depth=1
	ld	l,c
	ld	h,b
	ld	a,l
	or	h
	jr	z,LBB0_17
; %bb_15:                               ;   in Loop: Header=BB0_14 Depth=1
	ld	hl,(__sfrend_main-86)
	ld	(__sfrend_main-82),bc
	ld	(__sfrend_main-84),iy
	call	_fgetc
	ld	iy,(__sfrend_main-84)
	ld	bc,(__sfrend_main-82)
	ld	a,d
	cpl
	ld	h,a
	ld	a,e
	cpl
	or	h
	jr	z,LBB0_17
; %bb_16:                               ;   in Loop: Header=BB0_14 Depth=1
	ex	de,hl
	ld	a,l
	ld	(iy+0),a
	inc	iy
	dec	bc
	jr	LBB0_14
LBB0_17:
	ld	a,c
	or	b
	sub	1
	sbc	a,a
	and	1
	and	1
	ld	e,a
	ld	d,0
	ld	hl,L__str_18
	push	hl
	ld	hl,9
	call	_check
	ld	d,255
	ld	(ix+-82),d
	ld	bc,_buf
	ld	de,2000
LBB0_18:                               ; =>This Inner Loop Header: Depth=1
	ld	l,e
	ld	h,d
	ld	a,l
	or	h
	jr	z,LBB0_21
; %bb_19:                               ;   in Loop: Header=BB0_18 Depth=1
	push	bc
	pop	iy
	inc	iy
	ld	a,(ix+-82)
	inc	a
	dec	de
	ld	l,c
	ld	h,b
	ld	(ix+-82),a
	cp	(hl)
	push	iy
	pop	bc
	jr	z,LBB0_18
; %bb_20:
	ld	de,0
	jr	LBB0_22
LBB0_21:
	ld	de,1
LBB0_22:
	ld	hl,L__str_19
	push	hl
	ld	hl,10
	call	_check
	ld	hl,(__sfrend_main-86)
	push	hl
	ld	hl,0
	push	hl
	push	hl
	ld	hl,2
	call	___fseek
	ld	hl,0
	ld	a,d
	xor	h
	ld	b,a
	ld	a,e
	xor	l
	or	b
	sub	1
	sbc	a,a
	and	1
	and	1
	ld	e,a
	ld	d,0
	ld	hl,L__str_20
	push	hl
	ld	hl,11
	call	_check
	ld	hl,(__sfrend_main-86)
	call	_ftell
	ld	a,d
	xor	7
	ld	b,a
	ld	a,e
	xor	208
	or	b
	sub	1
	sbc	a,a
	and	1
	ld	d,a
	ld	b,h
	ld	a,l
	or	b
	sub	1
	sbc	a,a
	and	1
	and	d
	and	1
	ld	e,a
	ld	d,0
	ld	hl,L__str_21
	push	hl
	ld	hl,12
	call	_check
	ld	hl,(__sfrend_main-86)
	call	_fclose
LBB0_23:
	ld	hl,L__str_16
	ld	de,L__str_11
	call	___fopen
	ld	l,e
	ld	h,d
	ld	a,l
	or	h
	jp	z,LBB0_29
; %bb_24:
	push	de
	pop	iy
	push	ix
	pop	hl
	ld	de,65456
	add	hl,de
	ex	de,hl
	ld	(__sfrend_main-82),de
	ld	de,0
	ld	(__sfrend_main-80),de
	ld	de,127
	ld	(__sfrend_main-78),de
	ld	de,128
	ld	(__sfrend_main-76),de
	ld	de,129
	ld	(__sfrend_main-74),de
	ld	de,255
	ld	(__sfrend_main-72),de
	ld	de,256
	ld	(__sfrend_main-70),de
	ld	de,777
	ld	(__sfrend_main-68),de
	ld	de,1500
	ld	(__sfrend_main-66),de
	ld	de,1999
	ld	(__sfrend_main-64),de
	ld	de,200
	ld	(__sfrend_main-62),de
	ld	de,1024
	ld	(__sfrend_main-60),de
	ld	hl,12
	ld	(__sfrend_main-84),iy
LBB0_25:                               ; =>This Inner Loop Header: Depth=1
	dec	hl
                                        ; kill: def $hl killed $hl def $l def $h
	ld	a,l
	or	h
	jr	z,LBB0_30
; %bb_26:                               ;   in Loop: Header=BB0_25 Depth=1
	ld	(__sfrend_main-86),hl
	ld	hl,(__sfrend_main-82)
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	a,d
	add	a,a
	sbc	a,a
	ld	c,a
	ld	b,a
	push	iy
	pop	hl
	push	hl
	ld	l,c
	ld	h,b
	push	hl
	ld	l,e
	ld	(__sfrend_main-88),hl
	ex	de,hl
	push	hl
	ld	de,0
	ld	(__sfrend_main-90),de
	ld	hl,0
	call	___fseek
	ex	de,hl
	ld	a,l
	or	h
	jr	nz,LBB0_32
; %bb_27:                               ;   in Loop: Header=BB0_25 Depth=1
	ld	de,(__sfrend_main-82)
	inc	de
	inc	de
	ld	(__sfrend_main-82),de
	ld	hl,(__sfrend_main-84)
	call	_fgetc
	ld	h,0
	ld	a,d
	xor	h
	ld	d,a
	ld	a,e
	ld	hl,(__sfrend_main-88)
	xor	l
	or	d
	ld	iy,(__sfrend_main-84)
	ld	hl,(__sfrend_main-86)
	jr	z,LBB0_25
; %bb_28:
	ld	de,0
	jr	LBB0_31
LBB0_29:
	ld	hl,L__str_23
	push	hl
	ld	hl,13
	ld	de,0
	call	_check
	jr	LBB0_33
LBB0_30:
	ld	de,1
LBB0_31:
	ld	(__sfrend_main-90),de
LBB0_32:
	ld	hl,L__str_22
	push	hl
	ld	hl,13
	ld	de,(__sfrend_main-90)
	call	_check
	ld	hl,(__sfrend_main-84)
	call	_fclose
LBB0_33:
	ld	hl,L__str_24
	ld	de,L__str_11
	call	___fopen
	ld	hl,0
	ld	(__sfrend_main-82),de
	ld	a,d
	xor	h
	ld	b,a
	ld	a,e
	xor	l
	or	b
	add	a,255
	sbc	a,a
	and	1
	ld	(ix+-84),a
	and	1
	ld	e,a
	ld	d,0
	ld	hl,L__str_25
	push	hl
	ld	hl,14
	call	_check
	ld	a,(ix+-84)
	xor	1
	jp	nz,LBB0_39
; %bb_34:
	ld	hl,(__sfrend_main-82)
	push	hl
	ld	hl,0
	push	hl
	ld	hl,777
	push	hl
	ld	hl,0
	call	___fseek
	ld	hl,170
	ld	de,(__sfrend_main-82)
	call	_fputc
	ld	hl,(__sfrend_main-82)
	push	hl
	ld	hl,0
	push	hl
	ld	hl,1234
	push	hl
	ld	hl,0
	call	___fseek
	ld	hl,85
	ld	de,(__sfrend_main-82)
	call	_fputc
	ld	hl,(__sfrend_main-82)
	call	_fclose
	ld	hl,L__str_16
	ld	de,L__str_11
	call	___fopen
	ld	(__sfrend_main-82),de
	ex	de,hl
	push	hl
	ld	hl,0
	push	hl
	ld	hl,777
	push	hl
	ld	hl,0
	call	___fseek
	ld	hl,(__sfrend_main-82)
	call	_fgetc
	ld	(__sfrend_main-84),de
	ld	hl,(__sfrend_main-82)
	push	hl
	ld	hl,0
	push	hl
	ld	hl,1234
	push	hl
	ld	hl,0
	call	___fseek
	ld	hl,(__sfrend_main-82)
	call	_fgetc
	ld	bc,0
	ld	hl,(__sfrend_main-84)
                                        ; kill: def $hl killed $hl def $l def $h
	ld	a,l
	sub	170
	or	h
	jr	nz,LBB0_36
; %bb_35:
	ld	hl,85
	ld	a,d
	xor	h
	ld	b,a
	ld	a,e
	xor	l
	or	b
	sub	1
	sbc	a,a
	and	1
	and	1
	ld	c,a
	ld	b,0
LBB0_36:
	ld	hl,L__str_26
	push	hl
	ld	hl,15
	ld	e,c
	ld	d,b
	call	_check
	ld	hl,(__sfrend_main-82)
	push	hl
	ld	hl,0
	push	hl
	ld	hl,776
	push	hl
	ld	hl,0
	call	___fseek
	ld	hl,(__sfrend_main-82)
	call	_fgetc
	ld	(__sfrend_main-84),de
	ld	hl,(__sfrend_main-82)
	push	hl
	ld	hl,0
	push	hl
	ld	hl,1235
	push	hl
	ld	hl,0
	call	___fseek
	ld	hl,(__sfrend_main-82)
	call	_fgetc
	ld	bc,0
	ld	hl,(__sfrend_main-84)
                                        ; kill: def $hl killed $hl def $l def $h
	ld	a,l
	sub	8
	or	h
	jr	nz,LBB0_38
; %bb_37:
	ld	hl,211
	ld	a,d
	xor	h
	ld	b,a
	ld	a,e
	xor	l
	or	b
	sub	1
	sbc	a,a
	and	1
	and	1
	ld	c,a
	ld	b,0
LBB0_38:
	ld	hl,L__str_27
	push	hl
	ld	hl,16
	ld	e,c
	ld	d,b
	call	_check
	ld	hl,(__sfrend_main-82)
	call	_fclose
	jr	LBB0_40
LBB0_39:
	ld	hl,L__str_28
	push	hl
	ld	hl,15
	ld	de,0
	call	_check
	ld	hl,L__str_29
	push	hl
	ld	hl,16
	ld	de,0
	call	_check
LBB0_40:
	ld	hl,L__str_12
	ld	de,L__str_30
	call	___fopen
	ld	l,e
	ld	h,d
	ld	a,l
	or	h
	jp	z,LBB0_42
; %bb_41:
	ld	l,e
	ld	h,d
	push	hl
	ld	hl,0
	push	hl
	ld	hl,500
	push	hl
	ld	hl,0
	ld	(__sfrend_main-82),de
	call	___fseek
	ld	hl,238
	ld	de,(__sfrend_main-82)
	call	_fputc
	ld	hl,(__sfrend_main-82)
	call	_fclose
	ld	hl,L__str_16
	ld	de,L__str_30
	call	___fopen
	ld	(__sfrend_main-82),de
	ex	de,hl
	push	hl
	ld	hl,0
	push	hl
	push	hl
	ld	hl,2
	call	___fseek
	ld	hl,(__sfrend_main-82)
	call	_ftell
	ld	a,d
	xor	1
	ld	b,a
	ld	a,e
	xor	245
	or	b
	sub	1
	sbc	a,a
	and	1
	ld	d,a
	ld	b,h
	ld	a,l
	or	b
	sub	1
	sbc	a,a
	and	1
	and	d
	and	1
	ld	e,a
	ld	d,0
	ld	hl,L__str_31
	push	hl
	ld	hl,17
	call	_check
	ld	hl,(__sfrend_main-82)
	push	hl
	ld	hl,0
	push	hl
	ld	hl,250
	push	hl
	ld	hl,0
	call	___fseek
	ld	hl,(__sfrend_main-82)
	call	_fgetc
	ld	hl,0
	ld	a,d
	xor	h
	ld	b,a
	ld	a,e
	xor	l
	or	b
	sub	1
	sbc	a,a
	and	1
	and	1
	ld	e,a
	ld	d,0
	ld	hl,L__str_32
	push	hl
	ld	hl,18
	call	_check
	ld	hl,(__sfrend_main-82)
	call	_fclose
	jr	LBB0_43
LBB0_42:
	ld	hl,L__str_33
	push	hl
	ld	hl,17
	ld	de,0
	call	_check
	ld	hl,L__str_33
	push	hl
	ld	hl,18
	ld	de,0
	call	_check
LBB0_43:
	ld	hl,L__str_34
	call	_remove
	ld	hl,L__str_34
	ld	de,L__str_11
	call	___rename
	ld	hl,0
	ld	a,d
	xor	h
	ld	b,a
	ld	a,e
	xor	l
	or	b
	sub	1
	sbc	a,a
	and	1
	and	1
	ld	e,a
	ld	d,0
	ld	hl,L__str_35
	push	hl
	ld	hl,19
	call	_check
	ld	hl,L__str_16
	ld	de,L__str_11
	call	___fopen
	ld	hl,0
	ld	(__sfrend_main-84),de
	ld	a,d
	xor	h
	ld	b,a
	ld	a,e
	xor	l
	or	b
	sub	1
	sbc	a,a
	and	1
	ld	(ix+-82),a
	and	1
	ld	e,a
	ld	d,0
	ld	hl,L__str_36
	push	hl
	ld	hl,20
	call	_check
	ld	a,(ix+-82)
	or	a
	jr	nz,LBB0_45
; %bb_44:
	ld	hl,(__sfrend_main-84)
	call	_fclose
LBB0_45:
	ld	hl,L__str_16
	ld	de,L__str_34
	call	___fopen
	ld	hl,0
	ld	(__sfrend_main-84),de
	ld	a,d
	xor	h
	ld	b,a
	ld	a,e
	xor	l
	or	b
	add	a,255
	sbc	a,a
	and	1
	ld	(ix+-82),a
	and	1
	ld	e,a
	ld	d,0
	ld	hl,L__str_37
	push	hl
	ld	hl,21
	call	_check
	ld	a,(ix+-82)
	xor	1
	jr	nz,LBB0_47
; %bb_46:
	ld	hl,(__sfrend_main-84)
	call	_fclose
LBB0_47:
	ld	hl,L__str_34
	call	_remove
	ld	hl,0
	ld	a,d
	xor	h
	ld	b,a
	ld	a,e
	xor	l
	or	b
	sub	1
	sbc	a,a
	and	1
	and	1
	ld	e,a
	ld	d,0
	ld	hl,L__str_38
	push	hl
	ld	hl,22
	call	_check
	ld	hl,L__str_16
	ld	de,L__str_34
	call	___fopen
	ld	hl,0
	ld	(__sfrend_main-84),de
	ld	a,d
	xor	h
	ld	b,a
	ld	a,e
	xor	l
	or	b
	sub	1
	sbc	a,a
	and	1
	ld	(ix+-82),a
	and	1
	ld	e,a
	ld	d,0
	ld	hl,L__str_39
	push	hl
	ld	hl,23
	call	_check
	ld	a,(ix+-82)
	or	a
	jr	nz,LBB0_49
; %bb_48:
	ld	hl,(__sfrend_main-84)
	call	_fclose
LBB0_49:
	ld	hl,L__str_30
	call	_remove
	ld	hl,(_passc)
	ex	de,hl
	ld	hl,(_failc)
	ld	c,l
	ld	b,h
	add	hl,de
	push	hl
	pop	iy
	ld	l,c
	ld	h,b
	ld	a,l
	or	h
	jr	z,LBB0_51
; %bb_50:
	ld	hl,_fails
	jr	LBB0_52
LBB0_51:
	ld	hl,L__str_41
LBB0_52:
	push	hl
	push	iy
	pop	hl
	push	hl
	ex	de,hl
	push	hl
	ld	hl,L__str_40
	push	hl
	push	ix
	pop	hl
	ld	bc,65456
	add	hl,bc
	ld	(__sfrend_main-82),hl
	push	hl
	call	_sprintf
	pop	af
	pop	af
	pop	af
	pop	af
	pop	af
	ld	hl,(__sfrend_main-82)
	call	_cout
	ld	hl,(_logfp)
	ld	a,l
	or	h
	jr	z,LBB0_54
; %bb_53:
	ex	de,hl
	push	ix
	pop	hl
	ld	bc,65456
	add	hl,bc
	push	hl
	ld	hl,L__str_42
	push	hl
	ex	de,hl
	push	hl
	call	_fprintf
	pop	af
	pop	af
	pop	af
	ld	hl,(_logfp)
	call	_fclose
LBB0_54:
	ld	hl,(_failc)
	ld	b,h
	ld	a,l
	or	b
	add	a,255
	sbc	a,a
	and	1
	and	1
	ld	e,a
	ld	d,0
	pop	ix
	ret
                                        ; -- End function
_cout:                                  ; @cout
; %bb_0:
	push	hl
	ld	hl,L__str_42
	push	hl
	call	_printf
	pop	af
	pop	af
	ret
                                        ; -- End function
_check:                                 ; @check
; %bb_0:
	push	ix
	ld	ix,0
	add	ix,sp
	push	hl
	ld	hl,65460
	add	hl,sp
	ld	sp,hl
	ld	l,(ix+-2)
	ld	h,(ix+-1)
	ld	c,l
	ld	b,h
	ld	l,(ix+4)
	ld	h,(ix+5)
	push	hl
	pop	iy
	ld	(ix+-74),e
	ld	(ix+-73),d
	ex	de,hl
	ld	a,l
	or	h
	jr	z,LBB2_2
; %bb_1:
	ld	de,L__str_44
	jr	LBB2_3
LBB2_2:
	ld	de,L__str_45
LBB2_3:
	push	iy
	pop	hl
	push	hl
	ld	(ix+-78),c
	ld	(ix+-77),b
	ld	l,c
	ld	h,b
	push	hl
	ex	de,hl
	push	hl
	ld	hl,L__str_43
	push	hl
	push	ix
	pop	hl
	ld	bc,65472
	add	hl,bc
	ld	(ix+-76),l
	ld	(ix+-75),h
	push	hl
	call	_sprintf
	pop	af
	pop	af
	pop	af
	pop	af
	pop	af
	ld	l,(ix+-76)
	ld	h,(ix+-75)
	call	_cout
	ld	hl,(_logfp)
	ld	a,l
	or	h
	jr	z,LBB2_5
; %bb_4:
	ex	de,hl
	push	ix
	pop	hl
	ld	bc,65472
	add	hl,bc
	push	hl
	ld	hl,L__str_42
	push	hl
	ex	de,hl
	push	hl
	call	_fprintf
	pop	af
	pop	af
	pop	af
LBB2_5:
	ld	l,(ix+-74)
	ld	h,(ix+-73)
                                        ; kill: def $hl killed $hl def $l def $h
	ld	a,l
	or	h
	jr	z,LBB2_7
; %bb_6:
	ld	hl,(_passc)
	inc	hl
	ld	(_passc),hl
	jr	LBB2_9
LBB2_7:
	ld	hl,(_failc)
	inc	hl
	ld	(_failc),hl
	ld	l,(ix+-78)
	ld	h,(ix+-77)
	push	hl
	ld	hl,L__str_46
	push	hl
	push	ix
	pop	hl
	ld	bc,65464
	add	hl,bc
	ld	(ix+-74),l
	ld	(ix+-73),h
	push	hl
	call	_sprintf
	pop	af
	pop	af
	pop	af
	ld	hl,_fails
	call	_strlen
	ld	(ix+-76),e
	ld	(ix+-75),d
	ld	l,(ix+-74)
	ld	h,(ix+-73)
	call	_strlen
	ex	de,hl
	ld	e,(ix+-76)
	ld	d,(ix+-75)
	add	hl,de
	ld	de,95
	ld	a,l
	sub	e
	ld	a,h
	sbc	a,d
	jr	nc,LBB2_9
; %bb_8:
	push	ix
	pop	hl
	ld	bc,65464
	add	hl,bc
	ld	de,_fails
	call	___strcat
LBB2_9:
	ld	sp,ix
	pop	ix
	pop	hl
	ex	(sp),hl
	ret
                                        ; -- End function
	SECTION rodata_compiler
L__str:
	DEFM	"BDOSTSTLOG"
	DEFB	0x00

L__str_1:
	DEFM	"w"
	DEFB	0x00



L__str_2:
	DEFM	"== llvm-z88dk BDOS/clib test ==\n"
	DEFB	0x00

L__str_3:
	DEFM	"bdos12 version nonzero"
	DEFB	0x00

L__str_4:
	DEFM	"bdos25 current drive in range"
	DEFB	0x00

L__str_5:
	DEFM	"m3a\n"
	DEFB	0x00

L__str_6:
	DEFM	"m3b\n"
	DEFB	0x00

L__str_7:
	DEFM	"bdos32 user number in range"
	DEFB	0x00

L__str_8:
	DEFM	"m4a\n"
	DEFB	0x00

L__str_9:
	DEFM	"m4b\n"
	DEFB	0x00

L__str_10:
	DEFM	"bdos6 console status (no key pending)"
	DEFB	0x00



L__str_11:
	DEFM	"BDOSTST_DAT"
	DEFB	0x00

L__str_12:
	DEFM	"wb"
	DEFB	0x00

L__str_13:
	DEFM	"fopen wb (create data file)"
	DEFB	0x00

L__str_14:
	DEFM	"write 2000 bytes"
	DEFB	0x00

L__str_15:
	DEFM	"fclose after write"
	DEFB	0x00

L__str_16:
	DEFM	"rb"
	DEFB	0x00

L__str_17:
	DEFM	"fopen rb (reopen data file)"
	DEFB	0x00

L__str_18:
	DEFM	"read 2000 bytes"
	DEFB	0x00

L__str_19:
	DEFM	"sequential data verifies"
	DEFB	0x00

L__str_20:
	DEFM	"fseek SEEK_END"
	DEFB	0x00

L__str_21:
	DEFM	"ftell == 2000 (file size)"
	DEFB	0x00

L__str_22:
	DEFM	"random SEEK_SET reads (absolute offsets)"
	DEFB	0x00

L__str_23:
	DEFM	"random SEEK_SET reads (reopen failed)"
	DEFB	0x00

L__str_24:
	DEFM	"r+b"
	DEFB	0x00

L__str_25:
	DEFM	"fopen r+b (update mode)"
	DEFB	0x00

L__str_26:
	DEFM	"random writes read back"
	DEFB	0x00

L__str_27:
	DEFM	"neighbours of random writes intact"
	DEFB	0x00

L__str_28:
	DEFM	"random writes (r+b open failed)"
	DEFB	0x00

L__str_29:
	DEFM	"neighbours intact (r+b open failed)"
	DEFB	0x00

L__str_30:
	DEFM	"BDOSSPAR_DAT"
	DEFB	0x00

L__str_31:
	DEFM	"sparse file size == 501"
	DEFB	0x00

L__str_32:
	DEFM	"gap of sparse file reads as zero"
	DEFB	0x00

L__str_33:
	DEFM	"sparse create failed"
	DEFB	0x00

L__str_34:
	DEFM	"BDOSTST_BAK"
	DEFB	0x00

L__str_35:
	DEFM	"rename DAT -> BAK"
	DEFB	0x00

L__str_36:
	DEFM	"old name gone after rename"
	DEFB	0x00

L__str_37:
	DEFM	"new name present after rename"
	DEFB	0x00

L__str_38:
	DEFM	"remove BAK"
	DEFB	0x00

L__str_39:
	DEFM	"file gone after remove"
	DEFB	0x00

L__str_40:
	DEFM	"VERDICT: %d/%d PASS  fails: %s\n"
	DEFB	0x00







L__str_41:
	DEFM	"(none)"
	DEFB	0x00

L__str_42:
	DEFM	"%s"
	DEFB	0x00

L__str_43:
	DEFM	"%s %d %s\n"
	DEFB	0x00

L__str_44:
	DEFM	"[PASS]"
	DEFB	0x00

L__str_45:
	DEFM	"[FAIL]"
	DEFB	0x00

L__str_46:
	DEFM	"%d "
	DEFB	0x00

	SECTION IGNORE
	SECTION bss_compiler
__sframe_main:
	DEFS	90
__sfrend_main:
	SECTION bss_compiler
_logfp:
	DEFS 2
_buf:
	DEFS 2000
_passc:
	DEFS 2
_failc:
	DEFS 2
_fails:
	DEFS 96
