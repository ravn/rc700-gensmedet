; cpnos-in-asm phase 1: PROM1 (0x2000 - 0x27FF).
;
; Entered by PROM0 via JP 0x2000.  Stamps a banner into display memory
; at 0xF800 (top-left of CRT) and busy-loops.  Phase 1 success criterion:
; banner visible in a MAME boot screenshot.
;
; No protocol logic, no transport, no NDOS.  This validates:
;   - zmac toolchain produces a working raw binary
;   - prom1.bin lands in the MAME PROM1 slot
;   - PROM0's JP 0x2000 transfers control here
;   - the operator can see the slave is alive

	.z80
	org	0x2000

slave_entry:
	; Clear display memory (0xF800..0xFFCF, 2000 bytes) to spaces
	; (0x20) before stamping the banner.  RAM at power-on is whatever
	; was last there; MAME shows 0x00 which renders as font-glyph 0.
	; LDIR-from-self idiom: write one space at dst, then copy
	; (count-1) bytes from dst -> dst+1.
	ld	hl, 0xF800
	ld	(hl), 0x20
	ld	de, 0xF801
	ld	bc, 1999
	ldir

	; Stamp the banner at row 0, column 0.
	ld	hl, banner
	ld	de, 0xF800
	ld	bc, banner_end - banner
	ldir

halt:
	jr	halt

banner:
	db	"RC702 CP/NOS asm phase 1 alive"
banner_end:

	; Padding to 2048 bytes is applied by the Makefile after zmac
	; emits the .cim.

	end	slave_entry
