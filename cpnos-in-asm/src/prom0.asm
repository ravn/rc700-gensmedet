; cpnos-in-asm phase 1: PROM0 (0x0000 - 0x07FF).
;
; Cold-boot entry.  Does the minimum hardware setup needed to make
; the display readable, then jumps to PROM1 at 0x2000.  This validates
; the PROM0 -> PROM1 control transfer; no protocol logic.
;
; Setup mirrors src/relocator.c's reloc_display_init[] in cpnos-in-c
; (the same minimal-init sequence used there for early failure messages):
;   - 8237 DMA ch2 configured for autoinit mem->IO from display RAM.
;   - 8275 CRT given geometry + start commands so the controller runs.
; Stack lives at 0xEC00 (below display RAM, above any PROM).

	.z80
	org	0x0000

reset:
	di
	ld	sp, 0xEC00

	; Walk a (port,value) table; 15 pairs * OUT (C),A.
	ld	hl, dma_crt_init
	ld	b, 15
init_loop:
	ld	c, (hl)
	inc	hl
	ld	a, (hl)
	inc	hl
	out	(c), a
	djnz	init_loop

	jp	0x2000		; enter PROM1

	; -------- DMA + CRT init port table --------
	; Identical byte sequence to reloc_display_init[] (cpnos-in-c
	; relocator.c).  15 pairs:
	;   F8 20 : 8237 master clear
	;   FB 5A : ch2 single mem->IO autoinit (0x58|2)
	;   FC 00 : DMA CLBP reset
	;   F4 00 F4 F8 : ch2 base = 0xF800 (DISPLAY_ADDR)
	;   F5 CF F5 07 : ch2 word count = 1999 (DISPLAY_SIZE - 1)
	;   FA 02 : DMA SMSK unmask ch2
	;   01 00 4F 98 7A 6D : 8275 reset + 4 geometry params
	;   01 E0 : 8275 enable interrupts (harmless under DI)
	;   01 23 : 8275 start display
dma_crt_init:
	db	0xF8, 0x20
	db	0xFB, 0x5A
	db	0xFC, 0x00
	db	0xF4, 0x00
	db	0xF4, 0xF8
	db	0xF5, 0xCF
	db	0xF5, 0x07
	db	0xFA, 0x02
	db	0x01, 0x00
	db	0x00, 0x4F
	db	0x00, 0x98
	db	0x00, 0x7A
	db	0x00, 0x6D
	db	0x01, 0xE0
	db	0x01, 0x23

	; Padding to 2048 bytes is applied by the Makefile after zmac
	; emits the .cim — zmac chokes on `ds <expr>` with a forward-
	; relative `$` here ("Value error") even though the value is
	; constant.  Pure shell pad sidesteps the issue.

	end	reset
