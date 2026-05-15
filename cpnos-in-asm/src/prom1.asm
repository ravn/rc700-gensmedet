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

PORT_CRT_PARAM	equ	0x00
PORT_CRT_CMD	equ	0x01
PORT_CTC1	equ	0x0D
PORT_CTC2	equ	0x0E
PORT_SIO_B_DATA	equ	0x09
PORT_SIO_B_CTRL	equ	0x0B
SIO_RX_CHAR_AVAIL equ	0x01	; RR0 bit 0
SIO_TX_BUF_EMPTY equ	0x04	; RR0 bit 2

PORT_DMA_CH2_ADDR equ	0xF4
PORT_DMA_CH2_WC  equ	0xF5
PORT_DMA_SMSK	equ	0xFA
PORT_DMA_MODE	equ	0xFB
PORT_DMA_CLBP	equ	0xFC

; 8275 commands.  Bits 7..5 select the command; remaining bits carry
; parameters baked into the byte for cmd-with-immediate-params.
CRT_CMD_RESET	equ	0x00	; 000xxxxx: reset (expects 4 params)
CRT_CMD_LOADCUR	equ	0x80	; 100xxxxx: load cursor (expects col, row)
CRT_CMD_STOP	equ	0x40	; 010xxxxx: stop display
CRT_CMD_PRESET	equ	0xE0	; 111xxxxx: PRESET COUNTERS.
				;
				; Per the i8275 datasheet (as quoted in
				; MAME's i8275_device::write() at
				; src/devices/video/i8275.cpp): "internal
				; timing counters are preset, corresponding
				; to a screen display position at the top
				; left corner.  Two character clocks are
				; required for this operation.  The
				; counters will remain in this state until
				; any other command is given."
				;
				; Concretely the 8275 has three internal
				; counters that together describe "where on
				; the screen is the beam right now":
				;   - character counter  (column within a
				;     scan line; 0..H)
				;   - line counter       (scan line within
				;     a character row; 0..L)
				;   - character-row counter (row within a
				;     frame; 0..R)
				; STOP freezes scanning but does NOT touch
				; these counters -- they hold whatever
				; mid-frame value they had when the STOP
				; command landed.  Without an explicit
				; PRESET between STOP and START, the next
				; START resumes scanning from that frozen
				; position (e.g. row 12 mid-frame) instead
				; of from top-left.  This was the original
				; "banner at row 12" symptom in MAME before
				; we added the PRESET step.
				;
				; PRESET makes the next START deterministic:
				; counters go to 0/0/0 and remain there
				; until the START releases them.
CRT_CMD_START	equ	0x23	; 001xxxxx: start display.  bits 4..3
				; = 00 = burst=0 (8 DMA cycles/burst),
				; bits 2..0 = 011 = 24-clock spacing.
				; Identical to autoload's start command.

; 8275 reset parameters (4 bytes written after CRT_CMD_RESET).
; Geometry matches autoload exactly; only P4's cursor format changes.
;
; Each byte is broken into named bit fields below.  Every numeric
; field stored in the 8275 is encoded "N - 1" (the chip adds 1 to
; produce the actual count), so the "= N count" comment is the
; observable value while the bits show what's literally written.
;
; Two CRT-timing acronyms appear below:
;   VRTC = Vertical Retrace.   Time between drawing the last visible
;          row of a frame and the first visible row of the next frame,
;          while the electron beam flies from screen bottom back to
;          screen top.  Display is blanked during these rows; CPU /
;          DMA can use the gap to set up the next frame.  The 8275
;          measures it in CHARACTER ROWS.
;   HRTC = Horizontal Retrace.  Time between drawing the rightmost
;          character of a scan line and the leftmost character of the
;          next scan line, while the beam flies right-to-left.
;          Display is blanked during these clocks.  The 8275 measures
;          it in CHARACTER CLOCKS within a single scan line.
;
; ---- P1 (Horizontal): SHHHHHHH ----
;   bit 7   = S = 0           ; 0 -> no spaced rows
;   bits 6-0 = H = 0x4F = 79  ; 79 + 1 = 80 chars per row
;   -> P1 = 0x4F
CRT_P1_GEOM_H	equ	0x4F

; ---- P2 (Vertical): VV_RRRRRR ----
;   bits 7-6 = V = 10b = 2    ; 2 + 1 = 3 VRTC (vertical retrace) rows
;   bits 5-0 = R = 011000b    ; 24 -> 24 + 1 = 25 character rows per frame
;                = 24 decimal
;   -> P2 = 10_011000b = 0x98
CRT_P2_GEOM_V	equ	0x98

; ---- P3 (Underline / Lines per char row): UUUU_LLLL ----
;   bits 7-4 = U = 1001b = 9  ; underline appears on scan line 9 of each char
;   bits 3-0 = L = 1010b      ; 10 -> 10 + 1 = ? -- actually L counts directly:
;                = 10 decimal ;   10 lines per char row (10x8 char cell)
;   -> P3 = 1001_1010b = 0x9A
CRT_P3_GEOM_UL	equ	0x9A

; ---- P4 (Mode / cursor / HRTC): O_F_CC_ZZZZ ----
;   bit 7   = O  = 0          ; offset_line_counter off
;   bit 6   = F  = 1          ; visible_field_attribute on
;   bits 5-4 = C = 10b        ; cursor format:
;                              ;   00 = blinking reverse video block
;                              ;   01 = blinking underline
;                              ;   10 = NON-BLINKING REVERSE VIDEO BLOCK *
;                              ;   11 = non-blinking underline
;                              ; autoload uses 01 (blinking underline);
;                              ; we want 10 to match cpnos-in-c's relocator.
;                              ; Bit positions per MAME i8275 cursor_format()
;                              ; (src/devices/video/i8275.h: bits 5-4 of P4).
;   bits 3-0 = Z = 1101b = 13 ; HRTC count = (13 + 1) * 2 = 28 char clocks
;   -> P4 = 0_1_10_1101b = 0x6D
CRT_P4_MODE_NB_BLOCK equ 0x6D

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

	; Phase 2b: polled echo loop on SIO-B.  Waits for a byte to
	; arrive on RX, echoes it back on TX, repeats.  Replaces the
	; trailing `jr halt` -- the slave never returns once it enters
	; this loop.
	;
	; Use case: with rcbios in the master and S01=Off (CON_JOINED),
	; SIO-B becomes the duplex console; this loop is the baby step
	; toward the full character console.  Full integration test
	; deferred to phase 3 when we have a host-side driver pushing
	; bytes into MAME's bitbanger via a socket null_modem.
sio_echo_loop:
sio_rx_wait:
	in	a, (PORT_SIO_B_CTRL)
	and	SIO_RX_CHAR_AVAIL
	jr	z, sio_rx_wait
	in	a, (PORT_SIO_B_DATA)
	ld	c, a			; preserve byte across TX wait
sio_echo_tx_wait:
	in	a, (PORT_SIO_B_CTRL)
	and	SIO_TX_BUF_EMPTY
	jr	z, sio_echo_tx_wait
	ld	a, c
	out	(PORT_SIO_B_DATA), a
	jr	sio_echo_loop

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

	; 8275 reset + 4 params.  Reprograms cursor format from
	; autoload's non-blinking underline (P4=0x5D, C=11) to
	; non-blinking block (P4=0x55, C=10).  Geometry params
	; identical to autoload's so the line/row/column counts stay
	; the same.
	db	PORT_CRT_CMD, CRT_CMD_RESET
	db	PORT_CRT_PARAM, CRT_P1_GEOM_H
	db	PORT_CRT_PARAM, CRT_P2_GEOM_V
	db	PORT_CRT_PARAM, CRT_P3_GEOM_UL
	db	PORT_CRT_PARAM, CRT_P4_MODE_NB_BLOCK

	; Load cursor to row 0, column 0 so it lands on the first
	; character of the banner.
	db	PORT_CRT_CMD, CRT_CMD_LOADCUR
	db	PORT_CRT_PARAM, 0x00		; column = 0
	db	PORT_CRT_PARAM, 0x00		; row = 0

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
