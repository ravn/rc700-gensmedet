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

PORT_CRT_CMD	equ	0x01
PORT_CTC1	equ	0x0D
PORT_CTC2	equ	0x0E
PORT_SIO_B_DATA	equ	0x09
PORT_SIO_B_CTRL	equ	0x0B
SIO_TX_BUF_EMPTY equ	0x04	; RR0 bit 2

PORT_DMA_CH2_ADDR equ	0xF4
PORT_DMA_CH2_WC  equ	0xF5
PORT_DMA_SMSK	equ	0xFA
PORT_DMA_MODE	equ	0xFB
PORT_DMA_CLBP	equ	0xFC

; 8275 commands.  Bits 7..5 select the command; remaining bits carry
; parameters baked into the byte for cmd-with-immediate-params.
CRT_CMD_STOP	equ	0x40	; 010xxxxx: stop display
CRT_CMD_PRESET	equ	0xE0	; 111xxxxx: preset counters (reset
				; character counter + character row counter
				; so the next start begins at row 0).
CRT_CMD_START	equ	0x23	; 001xxxxx: start display.  bits 4..3
				; = 00 = burst=0 (8 DMA cycles/burst),
				; bits 2..0 = 011 = 24-clock spacing.
				; Identical to autoload's start command.

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
	; Walk the combined port-init table:
	;   - Disable CTC ch2 IRQ so autoload's VRTC ISR stops firing.
	;     The ISR (refresh_crt_dma_50hz_interrupt) re-programs DMA
	;     ch2 to DSPSTR_ADDR=0x7A00 every frame; we need it silent
	;     before we can pin DMA ch2 at 0xF800.
	;   - Reprogram DMA ch2 base to 0xF800 in AUTOINIT mode (0x5A).
	;     The 8237 reloads its own base register at terminal count,
	;     so no ISR is needed to keep the display refreshed.
	;   - Init CTC ch1 + SIO-B (autoload skips SIO).
	; All up front so the CRT switches sources before anything
	; tries to draw.
	ld	hl, init_table
	ld	b, init_table_pairs
init_loop:
	ld	c, (hl)
	inc	hl
	ld	a, (hl)
	inc	hl
	out	(c), a
	djnz	init_loop

	; Display now refreshes from 0xF800 (CP/M-canonical location;
	; matches the RC702 IVT page constraint
	; project_rc702_ivt_page_constraint).  Autoload's 0x7A00
	; framebuffer is no longer wired to the CRT; the TPA region from
	; 0x7A00 upward is free for cpnos.com / NDOS / programs.

	; Clear display memory to spaces.  LDIR-from-self idiom.
	ld	hl, 0xF800
	ld	(hl), 0x20
	ld	de, 0xF801
	ld	bc, 1999
	ldir

	; Stamp the banner on CRT row 0 (LDIR, no CRLF on screen).
	ld	hl, banner
	ld	de, 0xF800
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
; Display relocate (8275 stop + CTC ch2 quiet + DMA ch2 -> 0xF800
; autoinit + 8275 start) + CTC ch1 baud + SIO-B configuration.
;
; The 8275 stop/start pair is LOAD-BEARING.  Without it the 8275 is
; mid-frame when we reprogram DMA: the first ~12 visible rows still
; show autoload's 0x7A00 contents and only the bottom rows render from
; 0xF800, leaving our banner at row ~12 instead of row 0.  Stop
; freezes the CRT scan; restart begins a clean frame from row 0 against
; the new DMA stream.  Verified visually with snap/cpnos_asm_phase2a.png
; before vs after.
init_table:
	; 8275 stop: pauses CRT scanning + DMA requests so the next
	; restart begins at top-left.
	db	PORT_CRT_CMD, CRT_CMD_STOP

	; Disable CTC ch2 IRQ.  0x03 = control word + sw reset (autoload's
	; rom.c uses this exact value to disable ch3 at boot finish).  Once
	; CTC ch2 is silent, the VRTC ISR stops re-pointing DMA at 0x7A00.
	db	PORT_CTC2, 0x03

	; DMA ch2: mask, set autoinit mode + new base 0xF800 + WC, unmask.
	; Writing to the address/wc registers loads BOTH base and current,
	; so the next byte the CRT requests comes from 0xF800.
	db	PORT_DMA_SMSK,     0x06			; mask ch2 (set mask, ch=2)
	db	PORT_DMA_MODE,     0x5A			; single mem->IO autoinit, ch=2
	db	PORT_DMA_CLBP,     0x00			; clear byte-pointer flip-flop
	db	PORT_DMA_CH2_ADDR, 0x00			; base low  = 0x00
	db	PORT_DMA_CH2_ADDR, 0xF8			; base high = 0xF8 -> 0xF800
	db	PORT_DMA_CH2_WC,   0xCF			; wc low  = (1999 & 0xFF)
	db	PORT_DMA_CH2_WC,   0x07			; wc high = (1999 >> 8)
	db	PORT_DMA_SMSK,     0x02			; unmask ch2 (clear mask, ch=2)

	; 8275 preset counters: resets the character + character-row
	; counters so the next start begins at row 0.  Stop alone does
	; not reset these counters (verified empirically: without preset
	; the banner rendered at row ~12 instead of row 0).
	db	PORT_CRT_CMD, CRT_CMD_PRESET

	; 8275 start: resumes CRT scanning from row 0 against the new
	; DMA stream.  Burst+spacing identical to autoload's start cmd.
	db	PORT_CRT_CMD, CRT_CMD_START

	; CTC ch1 = 0x47/TC=1 drives SIO-B baud.
	db	PORT_CTC1, 0x47				; counter/timer, TC follows
	db	PORT_CTC1, 0x01				; TC = 1

	; SIO-B WR0/WR2..5/WR1 (mirrors cpnos-in-c init.c port_init[]).
	db	PORT_SIO_B_CTRL, 0x18				; WR0: channel reset
	db	PORT_SIO_B_CTRL, 0x02, PORT_SIO_B_CTRL, 0x10	; WR2 = 0x10
	db	PORT_SIO_B_CTRL, 0x04, PORT_SIO_B_CTRL, 0x44	; WR4 = clk/16 8N1
	db	PORT_SIO_B_CTRL, 0x03, PORT_SIO_B_CTRL, 0xE1	; WR3 = RX enable
	db	PORT_SIO_B_CTRL, 0x05, PORT_SIO_B_CTRL, 0x6A	; WR5 = TX enable
	db	PORT_SIO_B_CTRL, 0x01, PORT_SIO_B_CTRL, 0x00	; WR1 = no IRQ
init_table_end:
init_table_pairs equ (init_table_end - init_table) / 2

banner:
	db	"RC702 CP/NOS asm phase 2a alive"
banner_text_len	equ	$ - banner
	db	0x0D, 0x0A		; CRLF for SIO-B only
banner_len	equ	$ - banner

	end	prom1_header
