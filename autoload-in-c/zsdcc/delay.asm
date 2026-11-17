; delay.asm -- Calibrated timing delay loop for RC702 autoload (zsdcc backend)
; Calling convention: sdcccall(1) outer in A, inner in L
; Timing: outer × inner × 256 × 16T
; At 4 MHz: 1 ms ≈ 4000 T-states.

	SECTION code_compiler
	PUBLIC _delay
_delay:
	or	a
	ret	z			; outer == 0: return immediately
delay_outer:
	ld	b, l			; B = inner
delay_mid:
	ld	c, 0			; 256 iters
delay_inner:
	dec	c
	jr	nz, delay_inner		; 256 × 16T = 4096T per mid iteration
	djnz	delay_mid
	dec	a
	jr	nz, delay_outer
	ret
