; cpnos-in-asm phase 2a: PROM1 (0x2000 - 0x27FF).
;
; ARCHITECTURE NOTE (session 73e, user clarification):
;   - PROM0 socket holds autoload-in-c (the production autoload PROM).
;   - autoload programs DMA + 8275 CRT + CTC + DMA + PIO, attempts floppy
;     boot, fails (no diskette), then calls prom1_if_present() which:
;       1. Reads " RC702" at PROM1 + 0x0002 to authenticate
;       2. Jumps via *(word *)0x2000 (jump-target stored at PROM1 byte 0)
;   - Hardware is fully initialised when control reaches us, EXCEPT
;     for SIO -- autoload does not program SIO since it never uses it
;     during cold boot.  We init SIO ourselves below.
;   - Side effect: autoload's load_chargen() reads our PROM1 bytes as
;     a SEM702 font.  Display rendering will be garbled until phase 3+
;     loads a real font; the bytes WRITTEN to display RAM are still
;     correct (so the CRT byte-level test still passes).
;
; Phase 2a goal: banner reaches both CRT (byte level) and SIO-B (visible
; to the polypascal-test harness).

	.z80
	org	0x2000

PORT_CTC1	equ	0x0D
PORT_SIO_B_DATA	equ	0x09
PORT_SIO_B_CTRL	equ	0x0B
SIO_TX_BUF_EMPTY equ	0x04	; RR0 bit 2

; ---- PROM1 header (autoload-in-c signature contract) ----------------
; Byte 0..1: jump target (little-endian, read by autoload's
;            `jump_to(*(word *)0x2000)`).
; Byte 2..7: " RC702" -- the 6-byte signature autoload's
;            prom1_if_present() compares via compare_6bytes.
prom1_header:
	dw	slave_entry		; little-endian jump target
	db	" RC702"		; signature autoload looks for

; ---- Slave entry (referenced by the header above) -------------------
slave_entry:
	; SIO-B init (autoload does not program SIO).  Mirrors
	; cpnos-in-c init.c port_init[] for the SIO-B half.
	; CTC ch1 = 0x47 / TC=1 -> drives SIO-B baud (RX/TX clock).
	ld	hl, sio_init_table
	ld	b, sio_init_table_pairs
sio_init_loop:
	ld	c, (hl)
	inc	hl
	ld	a, (hl)
	inc	hl
	out	(c), a
	djnz	sio_init_loop

	; Clear display memory to spaces.  DSPSTR_ADDR = 0x7A00 per
	; autoload-in-c rom.h; 80x25=2000 bytes programmed by autoload's
	; init_crt + VRTC ISR.  LDIR-from-self idiom.
	ld	hl, 0x7A00
	ld	(hl), 0x20
	ld	de, 0x7A01
	ld	bc, 1999
	ldir

	; Stamp the banner on CRT row 0 (LDIR, no CRLF on screen).
	ld	hl, banner
	ld	de, 0x7A00
	ld	bc, banner_text_len
	ldir

	; Stream banner (with CRLF) via SIO-B polled TX.
	ld	hl, banner
	ld	b, banner_len
sio_tx_loop:
sio_tx_wait:
	in	a, (PORT_SIO_B_CTRL)
	and	SIO_TX_BUF_EMPTY
	jr	z, sio_tx_wait
	ld	a, (hl)
	out	(PORT_SIO_B_DATA), a
	inc	hl
	djnz	sio_tx_loop

halt:
	jr	halt

; ---- Init port table ------------------------------------------------
; CTC ch1 drives SIO-B baud; SIO-B itself configured 8N1 polled.  Both
; CTC and SIO programmed here because autoload didn't.
sio_init_table:
	db	PORT_CTC1, 0x47			; counter/timer, TC follows
	db	PORT_CTC1, 0x01			; TC = 1
	db	PORT_SIO_B_CTRL, 0x18		; WR0: channel reset
	db	PORT_SIO_B_CTRL, 0x02, PORT_SIO_B_CTRL, 0x10	; WR2 = 0x10
	db	PORT_SIO_B_CTRL, 0x04, PORT_SIO_B_CTRL, 0x44	; WR4 = clk/16 8N1
	db	PORT_SIO_B_CTRL, 0x03, PORT_SIO_B_CTRL, 0xE1	; WR3 = RX enable
	db	PORT_SIO_B_CTRL, 0x05, PORT_SIO_B_CTRL, 0x6A	; WR5 = TX enable
	db	PORT_SIO_B_CTRL, 0x01, PORT_SIO_B_CTRL, 0x00	; WR1 = no IRQ
sio_init_table_end:
sio_init_table_pairs equ (sio_init_table_end - sio_init_table) / 2

banner:
	db	"RC702 CP/NOS asm phase 2a alive"
banner_text_len	equ	$ - banner
	db	0x0D, 0x0A		; CRLF for SIO-B only
banner_len	equ	$ - banner

	end	prom1_header
