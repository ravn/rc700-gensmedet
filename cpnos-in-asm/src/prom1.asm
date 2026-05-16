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
PORT_SIO_A_DATA	equ	0x08
PORT_SIO_B_DATA	equ	0x09
PORT_SIO_A_CTRL	equ	0x0A
PORT_SIO_B_CTRL	equ	0x0B
PORT_CTC0	equ	0x0C
PORT_CTC1	equ	0x0D
PORT_CTC2	equ	0x0E
SIO_RX_CHAR_AVAIL equ	0x01	; RR0 bit 0
SIO_TX_BUF_EMPTY equ	0x04	; RR0 bit 2

; Wire-split rationale:
;   SIO-B = operator console (banner + interactive control echo).
;   SIO-A = CP/NET transport stream when TRANSPORT=sio.
; Matches cpnos-in-c's TRANSPORT split (the alternative is PIO-B for
; TRANSPORT=pio-irq).  CTC ch0 drives SIO-A's baud clock; ch1 drives
; SIO-B's.  Both SIO chips use identical 8N1 polled-TX programming.

PORT_DMA_CH2_ADDR equ	0xF4
PORT_DMA_CH2_WC  equ	0xF5
PORT_DMA_SMSK	equ	0xFA
PORT_DMA_MODE	equ	0xFB
PORT_DMA_CLBP	equ	0xFC

; ---- RAM allocation ------------------------------------------------
; The RC702 has a "bank2h" mirror at 0x2800..0x2FFF that shadows the
; PROM1 image (extended-EPROM 4 KB mode), so the apparent "RAM
; immediately above PROM1" is actually still ROM-shadowed.  Bytes
; written to 0x2800 vanish; reads return prom1.bin[0..0x7FF].
; First investigated this with rx_frame_buf at 0x2800, which made
; recv_cpnet_frame look like it was receiving PROM1's own header
; bytes (08 20 20 52 43 37 30 = "08 20 RC70" = `dw slave_entry +
; " RC702"`) regardless of what the master sent.  See task #66 for
; the diagnostic story.
;
; Safe RAM regions (per MAME's rc702 memory map):
;   0x0800..0x1FFF  (between PROM0 socket and PROM1 socket bank2)
;     -- bank1h covers 0x0800..0x0FFF, so 0x1000..0x1FFF is the
;     usable subrange.
;   0x3000..0xF7FF  (above the bank2h mirror; display at 0xF800)
;
; Use 0x3000 for rx_frame_buf -- well clear of any PROM mirror, well
; below autoload's INTVEC_ADDR (0x6000 on clang) and CODE_BASE
; (0x6000+).  Layout matches the on-wire byte order for easy
; inspection:
;   off  0: SOH
;   off  1..5: FMT DID SID FNC SIZ
;   off  6: HCS
;   off  7: STX
;   off  8..8+SIZ: DAT
;   off  9+SIZ: ETX
;   off 10+SIZ: CKS
;   off 11+SIZ: EOT
; Max frame (SIZ = 255 -> 256 DAT bytes): 12 + 255 = 267 bytes.
rx_frame_buf	equ	0x3000

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

	; Phase 3a/b/d-β: emit one CP/NET INIT request frame on SIO-A
	; with the mandatory ENQ -> wait ACK -> header -> wait ACK ->
	; data -> wait ACK handshake.  send_cpnet_init_frame returns
	; CF = 0 on success, CF = 1 on any timeout / non-ACK; we ignore
	; the result for now (no retry, no error reporting yet --
	; that's phase 3d-γ).  Without a master to ACK, the slave
	; lands one ENQ byte on the SIO-A wire and continues.
	call	send_cpnet_init_frame

	; Phase 2b + 3d-α: combined polled loop.
	;   - SIO-B RX -> SIO-B TX   (operator console echo; phase 2b)
	;   - SIO-A RX -> SIO-B TX   (CP/NET wire visibility; phase 3d-α)
	;     forwards anything a CP/NET master sends back to the operator
	;     console so we can see ENQs / ACKs / response frames during
	;     bring-up.  Bytes are forwarded verbatim; framing visualisation
	;     comes in a later phase.
	; Round-robin: every iteration checks SIO-A first, then SIO-B.
	; Whichever has a byte is serviced; loop continues.  Slave never
	; returns from this loop.
combined_io_loop:
	in	a, (PORT_SIO_A_CTRL)
	and	SIO_RX_CHAR_AVAIL
	jr	z, .check_sio_b
	in	a, (PORT_SIO_A_DATA)
	ld	c, a
	; ENQ (0x05) from the master kicks off the receive-direction
	; state machine; mask bit 7 per spec (control bytes are
	; compared 7-bit so parity-stripping transports survive).
	and	0x7F
	cp	ENQ
	jr	nz, .sio_a_forward
	call	recv_cpnet_frame
	or	a
	jr	nz, combined_io_loop	; receive failed; back to idle
	call	decode_rx_frame		; phase 3g: emit decoded status on SIO-B
	call	dump_rx_to_siob		; followed by raw 0xAA-bracketed dump
	jr	combined_io_loop
.sio_a_forward:
	; Not an ENQ -- forward verbatim to SIO-B as before (phase 3d-α
	; behavior).  Useful for catching stray bytes / late ACKs.
.sio_a_to_b_wait:
	in	a, (PORT_SIO_B_CTRL)
	and	SIO_TX_BUF_EMPTY
	jr	z, .sio_a_to_b_wait
	ld	a, c
	out	(PORT_SIO_B_DATA), a
	jr	combined_io_loop

.check_sio_b:
	in	a, (PORT_SIO_B_CTRL)
	and	SIO_RX_CHAR_AVAIL
	jr	z, combined_io_loop
	in	a, (PORT_SIO_B_DATA)
	ld	c, a
.sio_b_echo_wait:
	in	a, (PORT_SIO_B_CTRL)
	and	SIO_TX_BUF_EMPTY
	jr	z, .sio_b_echo_wait
	ld	a, c
	out	(PORT_SIO_B_DATA), a
	jr	combined_io_loop

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

	; CTC ch0 + ch1 = 0x47/TC=1 drive SIO-A and SIO-B baud clocks
	; respectively.  Same programming for both -- gives a matched
	; baud rate so a wire swap is just a port-number change.
	db	PORT_CTC0, 0x47				; ch0: counter/timer, TC follows
	db	PORT_CTC0, 0x01				; ch0: TC = 1
	db	PORT_CTC1, 0x47				; ch1: counter/timer, TC follows
	db	PORT_CTC1, 0x01				; ch1: TC = 1

	; SIO-A WR0/WR4/WR3/WR5/WR1 (CP/NET transport).  Mirrors
	; cpnos-in-c init.c port_init[] for the SIO-A half.  Note: no
	; WR2 here -- WR2 is the interrupt vector base register, B-side
	; only on the Z80 SIO.
	db	PORT_SIO_A_CTRL, 0x18				; WR0: channel reset
	db	PORT_SIO_A_CTRL, 0x04, PORT_SIO_A_CTRL, 0x44	; WR4 = clk/16 8N1
	db	PORT_SIO_A_CTRL, 0x03, PORT_SIO_A_CTRL, 0xE1	; WR3 = RX enable
	db	PORT_SIO_A_CTRL, 0x05, PORT_SIO_A_CTRL, 0x6A	; WR5 = TX enable
	db	PORT_SIO_A_CTRL, 0x01, PORT_SIO_A_CTRL, 0x00	; WR1 = no IRQ

	; SIO-B WR0/WR2..5/WR1 (operator console).
	db	PORT_SIO_B_CTRL, 0x18				; WR0: channel reset
	db	PORT_SIO_B_CTRL, 0x02, PORT_SIO_B_CTRL, 0x10	; WR2 = 0x10
	db	PORT_SIO_B_CTRL, 0x04, PORT_SIO_B_CTRL, 0x44	; WR4 = clk/16 8N1
	db	PORT_SIO_B_CTRL, 0x03, PORT_SIO_B_CTRL, 0xE1	; WR3 = RX enable
	db	PORT_SIO_B_CTRL, 0x05, PORT_SIO_B_CTRL, 0x6A	; WR5 = TX enable
	db	PORT_SIO_B_CTRL, 0x01, PORT_SIO_B_CTRL, 0x00	; WR1 = no IRQ
init_table_end:
init_table_pairs equ (init_table_end - init_table) / 2

; ---- CP/NET frame emission ----------------------------------------
;
; CP/NET 1.2 control bytes (per the protocol spec).
SOH		equ	0x01		; Start Of Header
STX		equ	0x02		; Start of Data
ETX		equ	0x03		; End of Data
EOT		equ	0x04		; End Of Transmission (frame delimiter,
					; NOT counted in CKS)
ENQ		equ	0x05		; Enquire (slave -> master, request to send)
ACK		equ	0x06		; Acknowledge (master -> slave)
NAK		equ	0x15		; Negative Acknowledge

; LOGIN request body (5-byte CP/NET header + 8-byte password DAT).
; This is the FIRST CP/NET frame the slave sends at boot, mirroring
; cpnos-in-c's netboot_mpm() flow.  mpm-net2 (z80pack) doesn't
; recognise FNC=0xFF as a "get-my-node-id" request -- it expects
; LOGIN (FNC=64) as the first interaction from a slave, with the
; slave's compiled-in SID (0x01 == RC702_SLAVEID convention).
;
;   FMT = 0     request from slave
;   DID = 0     destination = master
;   SID = 0x01  RC702 slave ID (compile-time constant, matches
;               cpnos-in-c's RC702_SLAVEID default).  SNIOS rewrites
;               this from CFGTBL in cpnos-in-c -- we don't have a
;               CFGTBL here yet, so the literal is the source of
;               truth on cpnos-in-asm until phase 3g.
;   FNC = 64    LOGIN (CP/NET protocol function code; see
;               cpnos-in-c/src/init.c netboot_mpm())
;   SIZ = 7     8 bytes of password follow (SIZ+1)
;
; Resulting wire frame, with checksums baked in by send subroutines:
;     01 00 00 01 40 07 B7  02  50 41 53 53 57 4F 52 44  03 8A 04
;     SOH FMT DID SID FNC SIZ HCS STX  P  A  S  S  W  O  R  D  ETX CKS EOT
init_header:
	db	0x00			; FMT
	db	0x00			; DID
	db	0x01			; SID -- RC702 slave 0x01
	db	64			; FNC -- LOGIN
	db	7			; SIZ -- 8 password bytes follow (SIZ+1)
init_header_len equ $ - init_header	; = 5

; LOGIN password.  mpm-net2's default password for slave 0x01 is the
; ASCII string "PASSWORD" (8 chars).  cpnos-in-c overrides this at
; build time via -DRC702_LOGIN_PWD='"OTHER   "' if needed; we hard-
; code the default until cpnos-in-asm grows a build-time override.
init_data:
	db	"PASSWORD"		; 8 ASCII bytes; must match SIZ+1
init_data_len equ $ - init_data		; = 8 (must == SIZ+1)

; send_cpnet_init_header: emit SOH + 5 header bytes + HCS on SIO-A
; (polled TX, CP/NET transport).  HCS is computed at runtime by
; accumulating SOH+header into E and emitting NEG(E) so the seven
; on-wire bytes sum to 0 mod 256, per
; cpnos-shared/docs/CPNET_WIRE_PROTOCOL.md.
;
; Clobbers: AF, BC, DE, HL.
send_cpnet_init_header:
	; Send SOH first; seed the HCS accumulator with it.
	ld	d, SOH			; D = byte to send + sum seed
	ld	e, SOH			; E = running 8-bit sum
	call	sio_a_tx_de_seed	; sends D, leaves E with sum

	; Walk the 5 header bytes, sending each + updating E.
	ld	hl, init_header
	ld	b, init_header_len
.hdr_loop:
	ld	d, (hl)
	call	sio_a_tx_d_accum	; send D, E += D
	inc	hl
	djnz	.hdr_loop

	; HCS = NEG(E) so sum + HCS == 0 mod 256.
	xor	a
	sub	e			; A = 0 - E = -E
	ld	d, a
	jp	sio_a_tx_d		; tail-call: send HCS, return

; send_cpnet_init_data: emit STX + DAT (init_data_len bytes) + ETX +
; CKS + EOT on SIO-A.  CKS = NEG(STX + DAT[0..n-1] + ETX) so the
; bracketed (STX .. CKS) bytes sum to 0 mod 256.  EOT follows raw
; and is NOT included in CKS (it's a frame delimiter).
;
; Clobbers: AF, BC, DE, HL.
send_cpnet_init_data:
	; Send STX; seed CKS accumulator with it.
	ld	d, STX
	ld	e, STX
	call	sio_a_tx_d		; sends D; E still holds STX

	; Walk init_data, sending each + updating E.
	ld	hl, init_data
	ld	b, init_data_len
.dat_loop:
	ld	d, (hl)
	call	sio_a_tx_d_accum
	inc	hl
	djnz	.dat_loop

	; Send ETX and add it to the running sum.
	ld	d, ETX
	call	sio_a_tx_d_accum

	; CKS = NEG(E).
	xor	a
	sub	e
	ld	d, a
	call	sio_a_tx_d

	; Send EOT (raw; not in CKS).
	ld	d, EOT
	jp	sio_a_tx_d		; tail-call: send EOT, return

; sio_a_tx_de_seed: like sio_a_tx_d but assumes E already holds the
; seed sum and just sends D without re-adding (caller has already
; baked D into E).  Used for the very first byte (SOH).
sio_a_tx_de_seed:
	; fall through into sio_a_tx_d (no sum update)

; sio_a_tx_d: send the byte in D on SIO-A (polled TX).  Preserves E.
; SIO-A carries CP/NET frames; SIO-B carries the operator console.
sio_a_tx_d:
.wait:
	in	a, (PORT_SIO_A_CTRL)
	and	SIO_TX_BUF_EMPTY
	jr	z, .wait
	ld	a, d
	out	(PORT_SIO_A_DATA), a
	ret

; sio_a_tx_d_accum: send D, then E += D.  Used by the header loop so
; HCS accumulates as we emit.
sio_a_tx_d_accum:
	call	sio_a_tx_d
	ld	a, e
	add	a, d
	ld	e, a
	ret

; sio_a_rx_with_timeout: poll SIO-A RX with a coarse 16-bit-counter
; timeout.  ~250 ms at 4 MHz with the ~25T inner loop (40000
; iterations).  Returns:
;   CF = 0, A = received byte  on success
;   CF = 1, A undefined          on timeout
; Clobbers: AF only.  BC, DE, HL preserved (BC explicitly via
; push/pop; receive-side callers use BC as a byte-count across
; multiple calls so this preservation is load-bearing).
;
; Coarse counter is intentional -- CP/NET TMRETRY is forgiving (the
; spec lets the slave retry up to 10 whole frames per send), so a
; precise CTC-driven timeout isn't load-bearing.  250 ms is enough
; cushion for MAME's serial-pipeline scheduling jitter.
sio_a_rx_with_timeout:
	push	bc			; caller's loop counter survives
	ld	bc, 40000
.poll:
	in	a, (PORT_SIO_A_CTRL)
	and	SIO_RX_CHAR_AVAIL
	jr	nz, .ready
	dec	bc
	ld	a, b
	or	c
	jr	nz, .poll
	pop	bc
	scf				; CF = 1 -> timeout
	ret
.ready:
	in	a, (PORT_SIO_A_DATA)
	pop	bc
	or	a			; clear CF -> success
	ret

; cpnet_wait_ack: wait for an ACK byte on SIO-A (with timeout).
; Per the CP/NET 1.2 spec the slave masks bit 7 before comparing.
; Returns:
;   CF = 0  on ACK received
;   CF = 1  on timeout OR any non-ACK byte (caller treats both as
;           "frame failed; abandon and possibly retry")
; Clobbers: AF, BC.
cpnet_wait_ack:
	call	sio_a_rx_with_timeout
	ret	c			; timeout -> CF=1
	and	0x7F
	cp	ACK
	ret	z			; ACK -> Z=1 + CF=0
	scf				; non-ACK -> CF=1
	ret

; sio_b_tx_d: send the byte in D on SIO-B (polled TX).  Mirror of
; sio_a_tx_d for the operator console.  Preserves all registers
; except A.
sio_b_tx_d:
.b_wait:
	in	a, (PORT_SIO_B_CTRL)
	and	SIO_TX_BUF_EMPTY
	jr	z, .b_wait
	ld	a, d
	out	(PORT_SIO_B_DATA), a
	ret

; recv_cpnet_frame: caller has already consumed an ENQ on SIO-A.
; Run the master-to-slave receive sequence per CP/NET 1.2:
;
;     master: ENQ                                    [already consumed]
;     slave:  ACK
;     master: SOH FMT DID SID FNC SIZ HCS            7 bytes
;     slave:  ACK if HCS valid, NAK otherwise
;     master: STX DAT[0..SIZ] ETX CKS EOT            5 + SIZ+1 bytes
;     slave:  ACK if CKS valid + EOT correct
;
; Frame is written byte-by-byte into rx_frame_buf in on-wire order:
;   off  0     SOH
;   off  1..5  FMT DID SID FNC SIZ
;   off  6     HCS
;   off  7     STX
;   off  8..   DAT
;   off  8+SIZ ETX
;   off  9+SIZ CKS
;   off 10+SIZ EOT
;
; Returns:
;   A = 0    success; rx_frame_buf holds a complete validated frame
;   A = 0xFF failure at any step (timeout, bad SOH/STX/ETX/EOT, bad
;            HCS, bad CKS).  Master may retry via another ENQ.
; Clobbers: AF, BC, DE, HL.
recv_cpnet_frame:
	; Acknowledge the master's ENQ.
	ld	d, ACK
	call	sio_a_tx_d

	; Receive 7 bytes (SOH + 5 header + HCS) into rx_frame_buf[0..6].
	; Accumulate the sum in E; on valid HCS the sum mod 256 is 0.
	ld	hl, rx_frame_buf
	ld	b, 7
	ld	e, 0
.hdr_rx:
	call	sio_a_rx_with_timeout
	jr	c, .recv_fail
	ld	(hl), a
	inc	hl
	add	a, e
	ld	e, a
	djnz	.hdr_rx

	; Validate SOH at offset 0.
	ld	a, (rx_frame_buf)
	cp	SOH
	jr	nz, .recv_send_nak

	; Validate HCS: sum must be 0 mod 256.
	ld	a, e
	or	a
	jr	nz, .recv_send_nak

	; Send ACK to the header.
	ld	d, ACK
	call	sio_a_tx_d

	; Compute data-section length = SIZ + 1 in BC.  SIZ=255 -> 256.
	ld	a, (rx_frame_buf + 5)
	ld	c, a
	ld	b, 0
	inc	bc			; BC = SIZ + 1; for SIZ=0xFF, BC = 0x0100 = 256

	; Receive STX into rx_frame_buf[7]; seed CKS accumulator with it.
	; HL still points just past the HCS (rx_frame_buf + 7).
	call	sio_a_rx_with_timeout
	jr	c, .recv_fail
	ld	(hl), a
	cp	STX
	jr	nz, .recv_send_nak
	inc	hl
	ld	e, a			; E = STX seed for CKS

	; Read SIZ+1 DAT bytes; accumulate into E.
.dat_rx:
	call	sio_a_rx_with_timeout
	jr	c, .recv_fail
	ld	(hl), a
	inc	hl
	add	a, e
	ld	e, a
	dec	bc
	ld	a, b
	or	c
	jr	nz, .dat_rx

	; Read ETX; accumulate.
	call	sio_a_rx_with_timeout
	jr	c, .recv_fail
	ld	(hl), a
	cp	ETX
	jr	nz, .recv_send_nak
	inc	hl
	add	a, e
	ld	e, a

	; Read CKS; on valid checksum the accumulator + CKS == 0 mod 256.
	call	sio_a_rx_with_timeout
	jr	c, .recv_fail
	ld	(hl), a
	add	a, e
	jr	nz, .recv_send_nak	; CKS invalid
	; Store CKS happened above already via ld (hl), a; advance HL.
	inc	hl

	; Read EOT.
	call	sio_a_rx_with_timeout
	jr	c, .recv_fail
	ld	(hl), a
	cp	EOT
	jr	nz, .recv_send_nak

	; Frame valid.  Send final ACK and return success.
	ld	d, ACK
	call	sio_a_tx_d
	xor	a			; A = 0 -> success
	ret

.recv_send_nak:
	ld	d, NAK
	call	sio_a_tx_d
.recv_fail:
	ld	a, 0xFF
	ret

; decode_rx_frame: phase 3g first slice -- after recv_cpnet_frame
; succeeds, inspect rx_frame_buf and emit a human-readable status
; line on SIO-B for recognised frames.  Currently handles ONE case:
;
;   FMT = 1 (response from master) AND FNC = 64 (LOGIN):
;     DAT[0] = 0  -> emit "LOGIN OK\r\n"
;     DAT[0] != 0 -> emit "LOGIN FAIL\r\n"
;
; Other frames: do nothing.  dump_rx_to_siob (called after this)
; still prints the raw bytes wrapped in 0xAA markers, so unknown
; frames remain visible for inspection.
;
; Clobbers: AF, BC, DE, HL.
decode_rx_frame:
	ld	a, (rx_frame_buf + 1)	; FMT
	cp	1
	ret	nz			; only handle responses
	ld	a, (rx_frame_buf + 4)	; FNC
	cp	64
	ret	nz			; only handle LOGIN responses
	ld	a, (rx_frame_buf + 8)	; DAT[0] = return code
	or	a
	jr	nz, .login_fail
	ld	hl, msg_login_ok
	ld	b, msg_login_ok_len
	jp	sio_b_emit_string
.login_fail:
	ld	hl, msg_login_fail
	ld	b, msg_login_fail_len
	jp	sio_b_emit_string

; sio_b_emit_string: HL = start of bytes, B = count.  Write each
; byte to SIO-B polled.  Returns when count exhausted.
sio_b_emit_string:
.loop:
	ld	d, (hl)
	call	sio_b_tx_d
	inc	hl
	djnz	.loop
	ret

msg_login_ok:
	db	"LOGIN OK", 0x0D, 0x0A
msg_login_ok_len equ $ - msg_login_ok

msg_login_fail:
	db	"LOGIN FAIL", 0x0D, 0x0A
msg_login_fail_len equ $ - msg_login_fail

; dump_rx_to_siob: write the most-recently-received frame to SIO-B
; for visibility.  Length = 12 + SIZ (header 7 + STX 1 + DAT SIZ+1
; + ETX 1 + CKS 1 + EOT 1).  Just streams the bytes raw -- the
; operator hex-dumps the SIO-B capture file to inspect.  Wraps
; the output in a 0xAA marker byte on each side so the dump is
; distinguishable from forwarded raw bytes.
dump_rx_to_siob:
	ld	a, (rx_frame_buf + 5)	; SIZ
	add	a, 12			; 12 + SIZ = total length (max 267)
	jr	c, .dump_long		; SIZ = 0xF4..0xFF wraps
	ld	c, a
	jr	.dump_have_count
.dump_long:
	; SIZ + 12 >= 256.  Use 16-bit count.
	; A holds the low byte (SIZ + 12 mod 256); B will be 1.
	ld	c, a
	ld	b, 1
	jr	.dump_loop_16
.dump_have_count:
	ld	b, 0
.dump_loop_16:
	; Emit 0xAA framing marker.
	ld	d, 0xAA
	call	sio_b_tx_d
	; Stream rx_frame_buf for BC bytes.
	ld	hl, rx_frame_buf
.dump_body:
	ld	d, (hl)
	call	sio_b_tx_d
	inc	hl
	dec	bc
	ld	a, b
	or	c
	jr	nz, .dump_body
	; Trailing 0xAA marker.
	ld	d, 0xAA
	jp	sio_b_tx_d

; send_cpnet_init_frame: emit one full CP/NET INIT request frame on
; SIO-A with the mandatory ENQ/ACK handshake at each phase.
;
; Sequence on the wire:
;   slave:  ENQ                                       (1 byte)
;   master: ACK                                       (1 byte; wait + timeout)
;   slave:  SOH FMT DID SID FNC SIZ HCS               (7 bytes)
;   master: ACK                                       (1 byte; wait + timeout)
;   slave:  STX DAT[0..SIZ] ETX CKS EOT               (5+SIZ+1 bytes)
;   master: ACK                                       (1 byte; wait + timeout)
;
; On timeout or non-ACK at any step: returns CF = 1 (caller may retry
; or give up).  Phase 3d-β does NOT yet implement the MAXRETRY = 10
; whole-frame retry loop described by the spec; the caller in
; slave_entry just abandons the frame for now and falls through to
; the combined poll loop, so unattended-boot in MAME without a
; master simply leaves ENQ on the wire and continues.
;
; Returns CF = 0 on success, CF = 1 on any handshake failure.
; Clobbers: AF, BC, DE, HL.
send_cpnet_init_frame:
	; Phase 1: ENQ + wait ACK.
	ld	d, ENQ
	call	sio_a_tx_d
	call	cpnet_wait_ack
	ret	c

	; Phase 2: header + HCS, wait ACK.
	call	send_cpnet_init_header
	call	cpnet_wait_ack
	ret	c

	; Phase 3: data + CKS + EOT, wait ACK.
	call	send_cpnet_init_data
	jp	cpnet_wait_ack		; tail-call: CF set by ACK wait

banner:
	db	"RC702 CP/NOS asm "
	; build/buildinfo.inc holds one `db "YYYY-MM-DD HH:MM hash"`
	; line, regenerated at parse-time by the Makefile via
	; $(shell .../regen_buildinfo_asm.sh).  Pulled in here so the
	; CRT row 0 + the SIO-B banner stream both carry build identity
	; (matches cpnos-in-c's banner pattern).
	include	"buildinfo.inc"
banner_text_len	equ	$ - banner
	db	0x0D, 0x0A		; CRLF for SIO-B only
banner_len	equ	$ - banner

	end	prom1_header
