; delay.asm -- Calibrated timing delay loop for RC702 autoload (llvmz80 backend)
;
; Under zcc +z80 -compiler=llvmz80 (__smallc convention), arguments are passed on stack:
;   void delay(byte outer, byte inner);
;   [SP+4] = outer (low byte)
;   [SP+2] = inner (low byte)
;   [SP+0] = return address
;
; Innermost loop is 16 T-states:
;   dec c        ; 4T
;   jr nz, inner ; 12T (taken), 7T (fallthrough)

	SECTION code_compiler
	PUBLIC _delay
_delay:
	ld	hl, 4
	add	hl, sp
	ld	a, (hl)		; A = outer
	or	a
	ret	z		; outer == 0: early return
	dec	hl
	dec	hl
	ld	l, (hl)		; L = inner
delay_outer:
	ld	b, l
delay_mid:
	ld	c, 0
delay_inner:
	dec	c
	jr	nz, delay_inner
	djnz	delay_mid
	dec	a
	jr	nz, delay_outer
	ret
