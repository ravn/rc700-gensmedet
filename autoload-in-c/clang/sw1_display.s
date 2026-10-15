; sw1_display.s — compact assembly implementation of display_sw1_status()
;
; Writes "SW1 12345678: " + 8 binary digits (bits 0..7 of port 0x14)
; to row 0, column 58 of the CRT framebuffer (0x7830 + 58 = 0x786A).
;
; Total size: 27 bytes code + 14 bytes string = 41 bytes.

	.section .text._display_sw1_status,"ax",@progbits
	.global _display_sw1_status
	.type _display_sw1_status,@function
_display_sw1_status:
	ld	hl, .Lsw1_prefix
	ld	de, 0x786a		; row 0, col 58 (DSPSTR_ADDR 0x7830 + 58)
	ld	bc, 14			; sizeof("SW1 12345678: ") - 1
	ldir
	in	a, (0x14)		; read SW1 port
	ld	b, 8
.Lsw1_loop:
	rrca
	ld	c, a
	ld	a, 0x30			; '0'
	adc	a, 0			; '0' + carry -> '0' or '1'
	ld	(de), a
	inc	de
	ld	a, c
	djnz	.Lsw1_loop
	ret

	.section .rodata._display_sw1_status,"a",@progbits
.Lsw1_prefix:
	.ascii "SW1 12345678: "
