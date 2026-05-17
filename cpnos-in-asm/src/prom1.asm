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
PORT_CTC3	equ	0x0F
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

; ---- CP/NET msg buffer (generic frame send/receive) -----------------
; Layout matches cpnos-in-c's `msg[]` -- a 5-byte header followed by
; DAT bytes.  The on-wire framing (SOH/HCS/STX/ETX/CKS/EOT) is
; added/stripped by send_cpnet_msg / recv_cpnet_msg; callers see only
; the bare fields.
;
;   MSG_FMT = msg + 0  request (0) vs response (1)
;   MSG_DID = msg + 1  destination ID
;   MSG_SID = msg + 2  source ID
;   MSG_FNC = msg + 3  function code (BDOS fn or CP/NET special)
;   MSG_SIZ = msg + 4  SIZ; data length is SIZ + 1
;   MSG_DAT = msg + 5  first DAT byte
;
; Max DAT = 256 bytes (SIZ = 0xFF).  Plus the on-wire SOH byte we
; receive into msg-1 to keep checksum accumulation simple in the
; receive path.  Reserve 264 bytes from msg-1 .. msg-1+263.
cpnet_msg	equ	0x3300	; clear of rx_frame_buf 0x3000..0x310B
; Visual netboot-progress state.  At 0x4000 -- clear of any CP/NET
; buffers.  An earlier attempt at 0x32FE collided with recv_cpnet_msg
; writing the received SOH byte to `cpnet_msg - 1` (= 0x32FF),
; corrupting the cursor on first read.
;
; dot_cursor (16-bit) is the next display-memory write position.
; dot_col / dot_row mirror it as col + row so emit_progress_dot can
; issue the 8275 LOAD CURSOR command (cmd 0x80 + col + row) and the
; block cursor visually follows the dot stream -- per user
; suggestion that the cursor track the output the way a BIOS conout
; would.
; Pinned at 0xF400 -- inside the SNIOS RESERVED AREA (0xED00..0xF7FF).
; Earlier placements (0x4000 in TPA, 0xEC00 in BDOS region) BOTH
; violated the "slave state lives inside the snios reserved area"
; rule.  Stays consistent across the prom1 -> snios_payload handoff:
; snios_payload.asm's DOT_* equs resolve to the same addresses.
dot_cursor	equ	0xF400	; 16-bit display address
dot_col		equ	0xF402	; 8-bit
dot_row		equ	0xF403	; 8-bit
MSG_FMT		equ	0
MSG_DID		equ	1
MSG_SID		equ	2
MSG_FNC		equ	3
MSG_SIZ		equ	4
MSG_DAT		equ	5

; CP/NET function codes the slave issues in netboot.
FNC_LOGIN	equ	64
FNC_OPEN	equ	15
FNC_CLOSE	equ	16
FNC_READ_SEQ	equ	20

; cpnos.com lands at CPNOS_NDOS_ADDR = 0xDD80 in RAM (matches
; cpnos-in-c's cpnos_addrs.h).  We load up to bios_boot - 1; today
; bios_boot = 0xED00 (we'll later relocate SNIOS to 0xED33+).
NDOS_ADDR	equ	0xDD80
NDOSE_ADDR	equ	0xDD83
BIOS_BOOT	equ	0xED00

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

	; Decompress snios_payload (ZX0-compressed) to RAM at 0xED00 EARLY,
	; before the netboot CP/NET loop -- so do_netboot can call
	; snios_sndmsg / snios_rcvmsg at their fixed entry points (0xED3C /
	; 0xED3F) instead of carrying duplicate send_cpnet_msg /
	; recv_cpnet_msg implementations in PROM-only code.  ZX0 squeezes
	; the ~1.1 KB payload to ~750 B; with the 69 B decompressor below
	; that's a net ~260 B saved vs raw LDIR.  Standard ZX0 decoder
	; (z88dk libsrc/compress/zx0/z80/dzx0_standard.asm by Einar Saukas).
	ld	hl, snios_payload_blob
	ld	de, 0xED00
	call	dzx0_standard

	; Clear display memory to spaces.  LDIR-from-self idiom.
	ld	hl, 0xF800
	ld	(hl), 0x20
	ld	de, 0xF801
	ld	bc, 1999
	ldir

	; Initialize the conout cursor state at display row 0 col 0
	; (the 8275's block cursor is already there from init_table's
	; LOAD CURSOR sequence).  Emit the banner one char at a time
	; through conout so the block cursor visibly walks across row
	; 0 as each char appears.
	ld	hl, 0xF800
	ld	(dot_cursor), hl
	xor	a
	ld	(dot_col), a
	ld	(dot_row), a

	ld	hl, banner
	ld	b, banner_text_len
.banner_loop:
	ld	d, (hl)
	call	conout
	inc	hl
	djnz	.banner_loop

	; After banner, force cursor to row 1 col 0 ready for the
	; netboot progress dots.
	ld	hl, 0xF850
	ld	(dot_cursor), hl
	xor	a
	ld	(dot_col), a
	ld	a, 1
	ld	(dot_row), a
	ld	a, CRT_CMD_LOADCUR
	out	(PORT_CRT_CMD), a
	xor	a
	out	(PORT_CRT_PARAM), a
	ld	a, 1
	out	(PORT_CRT_PARAM), a

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

	; Phase 4a: full netboot.  LOGIN -> OPEN A:CPNOS.IMG -> READ-SEQ
	; loop -> CLOSE.  cpnos.com bytes land at NDOS_ADDR = 0xDD80 on
	; success.  Failure modes ignored at this layer for now -- next
	; phase will report via SIO-B / dispatch error response decode.
	; The "FETCH OK\r\n" / "FETCH FAIL\r\n" status line goes on SIO-B
	; so the operator (and integration tests) can see whether
	; netboot completed.
	call	do_netboot
	jr	c, .netboot_fail
	ld	hl, msg_fetch_ok
	ld	b, msg_fetch_ok_len
	call	sio_b_emit_string
	; Advance the CRT cursor to a fresh line via CR + LF through
	; conout, so whatever runs next (NDOS) starts on a clean row.
	ld	d, 0x0D
	call	conout
	ld	d, 0x0A
	call	conout

	; Phase 4b handoff.  snios_payload is already in RAM at 0xED00
	; (LDIR'd at the top of slave_entry so do_netboot could call
	; snios_sndmsg / snios_rcvmsg in resident form).  Just jump to
	; the trampoline.  handoff_entry @ 0xED4B = 0xED00 + 51 B
	; BIOS-JT + 24 B SNIOS-JT.  Kept in sync with snios_payload.asm
	; layout; if the JTs ever grow/shrink, this literal must move.
	jp	0xED4B

.netboot_fail:
	ld	hl, msg_fetch_fail
	ld	b, msg_fetch_fail_len
	call	sio_b_emit_string
.netboot_done:

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
	; Netboot-fail fallback.  Originally a SIO-A-to-SIO-B forward +
	; recv/decode/dump CP/NET frames for bring-up debugging
	; (~200 B).  Replaced with halt: when netboot fails we have no
	; useful state to maintain and PROM space is more valuable than
	; the diagnostic loop.  Operator sees "FETCH FAIL" on SIO-B and
	; the slave goes quiet.
	di
.cil_halt:
	halt
	jr	.cil_halt

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

	; Disable CTC ch2 IRQ (was: re-points DMA to 0x7A00) and CTC ch3 IRQ
	; (was: floppy completion -- never fires once slave_entry stops
	; the floppy, but the daisy-chain IUS state from autoload's last
	; service can otherwise block lower-priority channels like ch2).
	db	PORT_CTC2, 0x03
	db	PORT_CTC3, 0x03

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

; ============================================================
;  Generic CP/NET msg send / receive
; ============================================================
;
; Caller populates cpnet_msg fields (FNC, SIZ, DAT[]) and calls
; cpnet_xact.  The helper fills FMT=0, DID=0, SID=0x01, sends the
; full frame on SIO-A with the three-phase ENQ/ACK handshake, then
; waits for the master's response frame and parses it back into
; cpnet_msg.  Returns A = response DAT[0] (BDOS return code) when
; CF = 0; CF = 1 indicates transport failure.

; (send_cpnet_msg + recv_cpnet_msg removed -- snios_payload now sits
; in RAM at 0xED00 before do_netboot runs, so the same primitives are
; available at fixed entry points snios_sndmsg = 0xED3C and
; snios_rcvmsg = 0xED3F.  Saved ~430 B vs carrying duplicate prom1
; copies.  The remaining sio_a_tx_d / sio_a_rx_with_timeout / cpnet_
; wait_ack helpers are still used by recv_cpnet_frame in the
; combined_io_loop fallback below.)

SNIOS_SNDMSG	equ	0xED3C		; resident SNIOS jt slot 3
SNIOS_RCVMSG	equ	0xED3F		; resident SNIOS jt slot 4

; cpnet_xact: fill FMT/DID, run sndmsg+rcvmsg through the resident
; SNIOS routines.  Caller has already set MSG_FNC + MSG_SIZ + MSG_DAT.
; Returns A = response DAT[0] (= BDOS retcode) with CF=0 on success;
; CF=1 on transport failure.  Clobbers: AF, BC, DE, HL.
;
; snios_sndmsg / snios_rcvmsg own the SID rewrite (they patch from
; cfgtbl.slaveid, which is already 0x01 in the resident cfgtbl image)
; and return A=0 success, A=0xFF transport error -- mapped to CF here.
cpnet_xact:
	xor	a
	ld	(cpnet_msg + MSG_FMT), a
	ld	(cpnet_msg + MSG_DID), a
	ld	bc, cpnet_msg
	call	SNIOS_SNDMSG
	inc	a			; 0xFF -> 0 (Z); 0 -> 1 (NZ)
	jr	z, .cx_fail
	ld	bc, cpnet_msg
	call	SNIOS_RCVMSG
	inc	a
	jr	z, .cx_fail
	ld	a, (cpnet_msg + MSG_DAT)
	or	a			; CF = 0; Z reflects A
	ret
.cx_fail:
	scf
	ret

; ============================================================
;  netboot sequence (LOGIN -> OPEN -> READ x N -> CLOSE)
; ============================================================
;
; Mirrors cpnos-in-c/src/init.c netboot_mpm() byte-for-byte.  At
; end, cpnos.com bytes occupy NDOS_ADDR .. NDOS_ADDR + (sectors *
; 128) - 1.  Slave can then JP NDOSE_ADDR after SNIOS-RAM
; relocation + PROM-disable (deferred to next phase).
;
; Returns CF = 0 with HL pointing one past the last loaded byte
; on success; CF = 1 on any BDOS failure.
;
; Side effects: emits dots ('.') on SIO-B per loaded sector.
do_netboot:
	; --- LOGIN ---
	ld	hl, login_pwd
	ld	de, cpnet_msg + MSG_DAT
	ld	bc, 8
	ldir
	ld	a, FNC_LOGIN
	ld	(cpnet_msg + MSG_FNC), a
	ld	a, 7			; SIZ = 8 - 1
	ld	(cpnet_msg + MSG_SIZ), a
	call	cpnet_xact
	ret	c
	or	a
	scf
	ret	nz			; non-zero return code -> fail

	; LOGIN succeeded; emit status line on SIO-B for visibility.
	push	hl
	ld	hl, msg_login_ok
	ld	b, msg_login_ok_len
	call	sio_b_emit_string
	pop	hl

	; --- OPEN A:CPNOS.IMG ---
	call	install_fcb
	ld	a, FNC_OPEN
	ld	(cpnet_msg + MSG_FNC), a
	ld	a, 36			; SIZ = 37 - 1
	ld	(cpnet_msg + MSG_SIZ), a
	call	cpnet_xact
	ret	c
	cp	4
	ccf				; CF = 1 if A >= 4 (not 0..3)
	ret	c

	; --- READ-SEQ loop ---
	ld	hl, NDOS_ADDR		; load pointer
.nb_read:
	push	hl
	; cpnos-in-c's reuse_fcb: rewrite only DAT[0]=user (0).  The FCB
	; body at DAT[1..36] stays from the previous response (which the
	; master populated on OPEN, and which subsequent READ-SEQ
	; responses also update).  Reinstalling the FCB_HEAD here would
	; lose the master-filled fields and break the sequential-read
	; state machine -- the master returns rc=10 "media changed"
	; (which sent us down the FAIL path before this fix).
	xor	a
	ld	(cpnet_msg + MSG_DAT), a
	ld	a, FNC_READ_SEQ
	ld	(cpnet_msg + MSG_FNC), a
	ld	a, 36
	ld	(cpnet_msg + MSG_SIZ), a
	call	cpnet_xact
	pop	hl
	ret	c
	cp	1
	jr	z, .nb_eof		; rc=1 -> EOF
	or	a
	scf
	ret	nz			; rc>1 -> error

	; Response DAT layout: [0]=rc, [1..36]=FCB, [37..164]=128-byte sector
	push	hl
	ld	de, cpnet_msg + MSG_DAT + 37
	ex	de, hl
	pop	de			; DE = load pointer
	ld	bc, 128
	ldir				; copy 128 B sector into RAM
	ex	de, hl			; HL = updated load pointer

	; Emit one '.' on both SIO-B (mirror) and the CRT via conout
	; (cursor follows on display).
	push	hl
	push	de
	push	bc
	ld	d, '.'
	call	sio_b_tx_d
	ld	d, '.'
	call	conout
	pop	bc
	pop	de
	pop	hl

	; Sanity bound: HL must not pass BIOS_BOOT
	ld	a, h
	cp	BIOS_BOOT >> 8
	jr	c, .nb_read
	; H >= 0xED -> at or past BIOS_BOOT; bail.
	scf
	ret

.nb_eof:
	push	hl

	; --- CLOSE ---
	; reuse master-filled FCB (only reset user byte)
	xor	a
	ld	(cpnet_msg + MSG_DAT), a
	ld	a, FNC_CLOSE
	ld	(cpnet_msg + MSG_FNC), a
	ld	a, 36
	ld	(cpnet_msg + MSG_SIZ), a
	call	cpnet_xact		; ignore return (close errors not fatal)

	pop	hl
	or	a			; CF = 0
	ret

; install_fcb: copy 13-byte FCB_HEAD into cpnet_msg + MSG_DAT and
; zero-fill the remaining 24 bytes (DAT[13..36]) so the FCB body
; matches DRI BDOS expectations for OPEN/READ/CLOSE.
install_fcb:
	ld	hl, fcb_head
	ld	de, cpnet_msg + MSG_DAT
	ld	bc, 13
	ldir
	; DE now at cpnet_msg + MSG_DAT + 13.  Zero 24 bytes.
	xor	a
	ld	b, 24
.fz:
	ld	(de), a
	inc	de
	djnz	.fz
	ret

fcb_head:
	db	0			; user number = 0
	db	1			; drive A
	db	"CPNOS   "		; 8-byte filename, space-padded
	db	"IMG"			; 3-byte extension

login_pwd:
	db	"PASSWORD"

; Banner data MUST stay in the first 2 KB of PROM1 (offsets 0..0x7FF
; -- runtime addresses 0x2000..0x27FF).  RC702 / MAME PROM1 socket is
; physically 2 KB; the chip-mirror trick at 0x2800..0x2FFF returns
; PROM1[0..0x7FF] again (= bank2h mirror per
; feedback_rc702_bank2h_mirror.md), not the second 2 KB of a 4 KB
; image.  Keeping the banner BEFORE snios_payload_blob anchors it
; below the 2 KB boundary regardless of how big the payload grows.
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

; SNIOS payload blob.  Bytes produced by src/snios_payload.asm
; (org 0xED20 -- raw bytes start with the trampoline at 0xED20 and
; run through CFGTBL).  PROM1 carries them at this label; slave_entry
; LDIRs them to 0xED20 just before the PROM-disable handoff.
; ---- ZX0 decompressor (standard, 69 B) -----------------------------
; Einar Saukas's ZX0 v1 "standard" decoder.
; Source: z88dk libsrc/compress/zx0/z80/dzx0_standard.asm
;
; Parameters:
;   HL = source (compressed data, the snios_payload_blob below)
;   DE = destination (decompressing, 0xED00)
; Clobbers: AF, BC, DE, HL, AF' (uses the alternate AF set internally).
dzx0_standard:
	ld	bc, 0xFFFF		; preserve default offset 1
	push	bc
	inc	bc
	ld	a, 0x80
dzx0s_literals:
	call	dzx0s_elias		; obtain length
	ldir				; copy literals
	add	a, a			; copy-from-last-offset or new-offset?
	jr	c, dzx0s_new_offset
	call	dzx0s_elias		; obtain length
dzx0s_copy:
	ex	(sp), hl		; preserve source, restore offset
	push	hl			; preserve offset
	add	hl, de			; calculate destination - offset
	ldir				; copy from offset
	pop	hl			; restore offset
	ex	(sp), hl		; preserve offset, restore source
	add	a, a			; copy-from-literals or new-offset?
	jr	nc, dzx0s_literals
dzx0s_new_offset:
	call	dzx0s_elias		; obtain offset MSB
	ex	af, af'
	pop	af			; discard last offset
	xor	a			; adjust for negative offset
	sub	c
	ret	z			; check end marker
	ld	b, a
	ex	af, af'
	ld	c, (hl)			; obtain offset LSB
	inc	hl
	rr	b			; last offset bit becomes first length bit
	rr	c
	push	bc			; preserve new offset
	ld	bc, 1			; obtain length
	call	nc, dzx0s_elias_backtrack
	inc	bc
	jr	dzx0s_copy
dzx0s_elias:
	inc	c			; interlaced Elias gamma coding
dzx0s_elias_loop:
	add	a, a
	jr	nz, dzx0s_elias_skip
	ld	a, (hl)			; load another group of 8 bits
	inc	hl
	rla
dzx0s_elias_skip:
	ret	c
dzx0s_elias_backtrack:
	add	a, a
	rl	c
	rl	b
	jr	dzx0s_elias_loop

; ZX0-compressed snios_payload.  Decompressed by dzx0_standard above
; into runtime RAM at 0xED00.  Compressing the raw ~1.1 KB payload to
; ~750 B + a 69 B decoder = net ~260 B PROM saving.
snios_payload_blob:
	incbin	"snios_payload.zx0"
snios_payload_blob_end:

; (init_header / init_data tables removed -- send_cpnet_init_frame
; and its retry wrapper at the tail of this file are dead code
; superseded by snios_sndmsg in snios_payload.asm.  Phase 3g moved
; the LOGIN frame onto do_netboot which builds the request from
; the FCB / cfgtbl in the resident payload.)

; (send_cpnet_init_header / send_cpnet_init_data removed -- LOGIN is
; now sent via snios_sndmsg in the resident payload.  See do_netboot
; below for the active path.)
;
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

; conout: emit byte D to the CRT and update the cursor.  Recognises
; CR (0x0D) and LF (0x0A) as control characters:
;   CR -> reset col to 0 (carriage return; no row change, no glyph)
;   LF -> increment row    (line feed; no col change, no glyph)
;   other -> write char at current (col, row), advance col, wrap to
;            next row at 80.
; In all cases the 8275 LOAD CURSOR command is re-issued so the
; visible block cursor tracks output.  Mirror of a BIOS conout.
;
; Clobbers: AF only.  Preserves HL, DE, BC (HL load-bearing for the
; banner loop / status-string emitter that hold a source pointer
; there).
conout:
	ld	a, d
	cp	0x0D			; CR?
	jr	z, .co_cr
	cp	0x0A			; LF?
	jr	z, .co_lf
	; Regular printable byte: write to display + advance col.
	push	hl
	ld	hl, (dot_cursor)
	ld	(hl), d
	inc	hl
	ld	(dot_cursor), hl
	pop	hl
	ld	a, (dot_col)
	inc	a
	cp	80
	jr	c, .co_no_wrap
	; Wrap: col = 0, row += 1, advance dot_cursor unchanged (it
	; was already incremented past the just-written byte so it's
	; sitting on the new row's column 0 in display memory).
	xor	a
	ld	(dot_col), a
	push	hl
	ld	a, (dot_row)
	inc	a
	ld	(dot_row), a
	pop	hl
	jr	.co_cursor
.co_no_wrap:
	ld	(dot_col), a
	jr	.co_cursor

.co_cr:
	; Carriage return: col = 0, recompute dot_cursor for new col.
	xor	a
	ld	(dot_col), a
	call	.co_recompute_ptr
	jr	.co_cursor

.co_lf:
	; Line feed: row += 1, recompute dot_cursor for new row.
	ld	a, (dot_row)
	inc	a
	ld	(dot_row), a
	call	.co_recompute_ptr
	jr	.co_cursor

.co_recompute_ptr:
	; dot_cursor = 0xF800 + dot_row * 80 + dot_col
	push	bc
	push	de
	push	hl
	ld	a, (dot_row)
	ld	h, 0
	ld	l, a
	add	hl, hl			; row * 2
	add	hl, hl			; * 4
	ld	d, h
	ld	e, l			; DE = row * 4
	add	hl, hl			; * 8
	add	hl, hl			; * 16
	add	hl, de			; * 20
	add	hl, hl			; * 40
	add	hl, hl			; * 80 = row * 80
	ld	de, 0xF800
	add	hl, de			; HL = 0xF800 + row * 80
	ld	a, (dot_col)
	ld	e, a
	ld	d, 0
	add	hl, de			; HL += col
	ld	(dot_cursor), hl
	pop	hl
	pop	de
	pop	bc
	ret

.co_cursor:
	ld	a, CRT_CMD_LOADCUR
	out	(PORT_CRT_CMD), a
	ld	a, (dot_col)
	out	(PORT_CRT_PARAM), a
	ld	a, (dot_row)
	out	(PORT_CRT_PARAM), a
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

; (recv_cpnet_frame / decode_rx_frame / dump_rx_to_siob removed --
; they were used only by combined_io_loop's CP/NET-bring-up fallback,
; and that loop is now a `halt` on netboot failure.  Saved ~250 B.)

; sio_b_emit_string: HL = start of bytes, B = count.
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

msg_fetch_ok:
	db	0x0D, 0x0A, "FETCH OK", 0x0D, 0x0A
msg_fetch_ok_len equ $ - msg_fetch_ok

msg_fetch_fail:
	db	0x0D, 0x0A, "FETCH FAIL", 0x0D, 0x0A
msg_fetch_fail_len equ $ - msg_fetch_fail
; (send_cpnet_init_frame_retry / send_cpnet_init_frame removed -- both
; dead, see comment above where the init_header/init_data data tables
; used to live.  LOGIN is now driven by snios_sndmsg in the resident
; payload via do_netboot.)

	end	prom1_header
