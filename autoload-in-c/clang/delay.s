; delay.s — stable assembly implementation of delay(byte outer, byte inner)
;
; Calling convention: sdcccall(0)  outer=A, inner=L
; Timing: outer × inner × 256 × 16T  (dec C + jr nz = 4+12 = 16T per iteration)
; At 4 MHz: 1 ms ≈ 4000 T-states; inner≈244 with outer=1 gives ≈1 ms.
;
; This replaces the C version that LTO's machine outliner was mangling —
; it replaced the __asm__ volatile("") barrier with a call to an outlined
; snippet, breaking the calibrated cycle count and causing FDC timeouts.
;
; TODO: once z88dk integration is stable, replace with z80_delay_ms() which
; is hand-tuned and verified with z88dk-ticks on real hardware.

	.section .text._delay,"ax",@progbits
	.global _delay
_delay:
	or	a
	ret	z			; outer == 0: return immediately
.Ldelay_outer:
	ld	b, l			; B = inner  (mid-loop counter)
.Ldelay_mid:
	ld	c, 0			; C = 0  (k=0 → first dec wraps to 255 → 256 iters)
.Ldelay_inner:
	dec	c
	jr	nz, .Ldelay_inner	; 256 × 16T = 4096T per mid iteration
	djnz	.Ldelay_mid		; dec B + jr nz
	dec	a
	jr	nz, .Ldelay_outer
	ret
