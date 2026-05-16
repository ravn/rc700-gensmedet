; snios_payload.asm -- RAM-resident BIOS jump table, SNIOS jump
; table, handoff trampoline, and bring-up debug instrumentation.
;
; This blob is INCBIN'd into PROM1, copied by slave_entry to its
; runtime org address, then jumped into.  Once the trampoline's
; OUT (0x18), A executes, PROM1 is unmapped and only this RAM
; copy is reachable.
;
; LAYOUT (org 0xED00):
;
;   0xED00..0xED32  BIOS jump table (17 entries x 3 bytes = 51 B).
;                   This is the "resident BIOS" cpnos.com NDOS looks
;                   for via `lhld reboot+1` -> follows JMP WBOOT at
;                   0x0000 back to 0xED03.  NDOS COLDST overwrites
;                   the WBOOT/CONST/CONIN/CONOUT/LIST/LISTST slots
;                   with its own handler addresses (saving the
;                   originals into NDOS's tlbios for fall-through).
;
;   0xED33..0xED4A  SNIOS jump table (8 entries x 3 bytes = 24 B).
;                   Fixed-ABI address cpnos.com's cpnios-shim.asm
;                   pins (NIOS EQU 0xED33).  Same layout cpnos-in-c
;                   uses; cpnos-in-c's payload.ld asserts identity.
;
;   0xED4B..        Trampoline (handoff_entry) + impls + CFGTBL.
;                   Trampoline does:
;                     1. LDIR zp_init (8 B) -> 0x0000
;                        (JMP 0xED03 / IOBYTE / drive / JMP 0xE716)
;                     2. OUT (0x18), A    ; RAMEN: PROMs unmap
;                     3. LD SP, 0x100
;                     4. JP 0xDD80         ; NDOS COLDST
;
; INSTRUMENTATION:
;   Each BIOS/SNIOS handler emits a single debug character to
;   SIO-B at entry so an external capture shows NDOS's call
;   sequence post-handoff (previously '>' appeared then silence).
;   CONOUT additionally forwards its char-in-C argument verbatim
;   to SIO-B, so NDOS's BDOS printf output becomes visible there
;   even though we don't yet drive the CRT post-PROM-disable.
;
; Debug-char map (each handler emits exactly one):
;   '>'  trampoline entry (legacy marker; pre-handoff)
;   'b'  bios_boot         (cold reboot vector)
;   'w'  bios_wboot        (NDOS will overwrite this slot)
;   (no marker for CONST / CONIN -- hot polled paths during CCP,
;    spam would drown the SIO-B capture)
;   (no marker for CONOUT -- char itself is the marker)
;   'L'  bios_list / list-stub family
;   'h'  bios_home
;   'D'  bios_seldsk
;   'T'  bios_settrk
;   'X'  bios_setsec
;   'M'  bios_setdma
;   'R'  bios_read
;   'W'  bios_write
;   't'  bios_sectran
;   'A'  snios_ntwkin
;   'a'  snios_ntwkst
;   'c'  snios_cnftbl
;   'S'  snios_sndmsg       (still a stub -- returns 0xFE)
;   'r'  snios_rcvmsg       (still a stub -- returns 0xFE)
;   'e'  snios_ntwker
;   'B'  snios_ntwkbt
;   'd'  snios_ntwkdn
;
; PORTS:
;   SIO-B data = 0x09
;   SIO-B ctrl = 0x0B (RR0 bit 2 = TX_BUF_EMPTY)
;   RAMEN      = 0x18 (write any byte -> PROMs unmapped)

	.z80
	org	0xED00

PORT_SIO_A_DATA	equ	0x08
PORT_SIO_A_CTRL	equ	0x0A
PORT_SIO_B_DATA	equ	0x09
PORT_SIO_B_CTRL	equ	0x0B
SIO_RX_CHAR_AVAIL equ	0x01
SIO_TX_BUF_EMPTY equ	0x04
PORT_RAMEN	equ	0x18

; CP/NET frame delimiter bytes (DRI CP/NET 1.2 / asynchronous wire
; protocol, ASCII control codes).
SOH		equ	0x01
STX		equ	0x02
ETX		equ	0x03
EOT		equ	0x04
ENQ		equ	0x05
ACK		equ	0x06
NAK		equ	0x15

NDOS_ADDR	equ	0xDD80
NDOS_COLDST	equ	0xDD83		; NDOS + 3 = `JMP COLDST` inside
					; cpnos.com.  NDOS+0 is `JMP NDOSE`
					; (BDOS dispatcher), NOT cold start --
					; first attempt at phase 4b jumped
					; there and NDOSE returned 0xFFFF
					; through random C register, eventually
					; reached `JMP 0` -> our impl_wboot.
BDOS_ADDR	equ	0xE716

; ---- BIOS jump table (17 entries; public ABI) ----------------------
; cpnos.com NDOS COLDST walks this at runtime, overwriting the
; WBOOT/CONST/CONIN/CONOUT/LIST/LISTST slots (template tlbios at
; cpndos+0x37) and skipping zero entries (PUNCH/READER/HOME/SELDSK/
; SETTRK/SETSEC/SETDMA/READ/WRITE/SECTRAN).  Our handler bodies
; below mostly just return + emit one debug char so we can see
; which slots NDOS or BDOS or CCP actually touch.
bios_jt:
	jp	impl_boot		; 0xED00  BOOT
	jp	impl_wboot		; 0xED03  WBOOT
	jp	impl_const		; 0xED06  CONST
	jp	impl_conin		; 0xED09  CONIN
	jp	impl_conout		; 0xED0C  CONOUT
	jp	impl_list		; 0xED0F  LIST
	jp	impl_list		; 0xED12  PUNCH (stub)
	jp	impl_const		; 0xED15  READER (stub)
	jp	impl_home		; 0xED18  HOME
	jp	impl_seldsk		; 0xED1B  SELDSK
	jp	impl_settrk		; 0xED1E  SETTRK
	jp	impl_setsec		; 0xED21  SETSEC
	jp	impl_setdma		; 0xED24  SETDMA
	jp	impl_read		; 0xED27  READ
	jp	impl_write		; 0xED2A  WRITE
	jp	impl_listst		; 0xED2D  LISTST
	jp	impl_sectran		; 0xED30  SECTRAN

; ---- SNIOS jump table (8 entries; public ABI) ----------------------
; NIOS EQU 0xED33 in cpnos-build/src/cpnios-shim.asm; this address
; is contractual.
snios_jt:
	jp	snios_ntwkin		; 0xED33
	jp	snios_ntwkst		; 0xED36
	jp	snios_cnftbl		; 0xED39
	jp	snios_sndmsg		; 0xED3C
	jp	snios_rcvmsg		; 0xED3F
	jp	snios_ntwker		; 0xED42
	jp	snios_ntwkbt		; 0xED45
	jp	snios_ntwkdn		; 0xED48

; ---- Handoff trampoline at 0xED4B ----------------------------------
; Entry point: PROM1 init JPs here AFTER the LDIR copy completes.
; We're already running from RAM (the LDIR put us here), so the
; OUT (0x18), A that disables the PROMs is safe.
handoff_entry:
	; Debug: '>' marker pre-PROM-disable so a SIO-B capture shows
	; the trampoline reached this point (matches the legacy
	; pre-phase-4b marker so the user's polling scripts still see
	; the same handoff signal).
	ld	a, '>'
	call	emit_a

	; Copy 8-byte zero-page seed to 0x0000.  Writes go to RAM
	; underneath PROM0 (RAM is always there; PROM is just a
	; read-only overlay).  Once we OUT 0x18 below, the PROM goes
	; away and these RAM bytes become visible to the CPU.
	ld	hl, zp_init
	ld	de, 0x0000
	ld	bc, 8
	ldir

	; Copy 51-byte BIOS-JT to NDOSRL+0x300 = NDOS-0x100 = 0xDC80.
	; cpnos-in-c does this in resident_handoff; NDOS COLDST may
	; expect to find / patch the JT at that fixed offset inside
	; cpnos.com's data area (even though ZP[1..2] also points at
	; our in-place JT at 0xED03 -- cargo-cult cpnos-in-c until we
	; have evidence it's redundant).
	ld	hl, bios_jt
	ld	de, NDOS_ADDR - 0x100
	ld	bc, 51
	ldir

	; (50 Hz CTC-CH2 cursor-sync ISR parked: interrupts wouldn't stay
	; enabled across NDOS/CCP/PPAS execution and the bus RETI trick
	; didn't restart firing.  Cursor sync is now done per-conout call
	; via co_sync_cursor.)

	; PROM disable.  After this instruction PROM0+PROM1 are
	; unmapped; we must keep running from RAM only.
	xor	a
	out	(PORT_RAMEN), a

	; Standard CP/M cold-boot housekeeping: SP at top of TPA
	; bottom, then JP to NDOS first byte (which is JMP COLDST).
	ld	sp, 0x0100
	jp	NDOS_COLDST

; ---- Zero-page seed copied to 0x0000 .. 0x0007 ---------------------
; Standard CP/M zero page:
;   0x0000-2: JMP WBOOT  -> 0xED03 (bios_wboot slot)
;   0x0003:   IOBYTE     -> 0
;   0x0004:   drive/user -> 4 (E: drive 0, matches cpnos-in-c default)
;   0x0005-7: JMP BDOS   -> 0xE716
zp_init:
	db	0xC3
	db	low (bios_jt + 3)
	db	high (bios_jt + 3)
	db	0x00			; IOBYTE
	db	0x04			; drive/user
	db	0xC3
	db	low BDOS_ADDR
	db	high BDOS_ADDR

; ---- Tiny SIO-B emit (debug instrumentation) -----------------------
; Emit char in A to SIO-B; preserves all caller registers.
emit_a:
	push	af			; save char + flags
	push	bc
.ea_w:
	in	a, (PORT_SIO_B_CTRL)
	and	SIO_TX_BUF_EMPTY
	jr	z, .ea_w
	pop	bc
	pop	af
	out	(PORT_SIO_B_DATA), a
	ret

; ---- BIOS implementations ------------------------------------------
; Each emits a single debug char so a SIO-B capture documents the
; handler-call sequence post-handoff.  Bodies are minimal -- enough
; to keep NDOS / CCP from crashing on garbage returns, not to
; deliver real disk I/O (which CP/NOS routes through SNIOS anyway).

impl_boot:
	; Cold-boot vector.  Rare; if NDOS or CCP reaches here we spin
	; -- silent (debug 'b' marker removed for size).
.b_hang:
	jr	.b_hang

impl_wboot:
	; NDOS overwrites this slot at COLDST with nwboot; only reachable
	; in the gap before COLDST patches the JT.  Spin silently.
.w_hang:
	jr	.w_hang

impl_const:
	; CONST: peek the keyboard ring.  Return A = 0xFF if at least
	; one byte queued, else A = 0.  NDOS overwrites this slot with
	; nconst at COLDST, but nconst falls back to BIOS CONST via the
	; tlbios snapshot for local-console polling.  No debug marker:
	; CCP polls this 1000x/s and the spam would drown the SIO-B
	; capture used by polypascal_test.lua.
	ld	a, (kbd_head)
	or	a
	ret	z
	ld	a, 0xFF
	ret

impl_conin:
	; CONIN: dequeue one byte from kbd_ring; block (spin) until a
	; byte is available.  The MAME polypascal_test.lua harness
	; writes keystrokes directly into the ring via cpu memory taps;
	; in production PIO-A would be wired through a real ISR.  Same
	; no-debug-marker rationale as impl_const.  Preserves no callee-
	; save registers beyond what NDOS's nconin assumes (A only is
	; the return).
.ci_wait:
	ld	a, (kbd_head)
	or	a
	jr	z, .ci_wait
	; Dequeue: byte at kbd_ring[0]; shift remaining (kbd_head-1)
	; bytes down by one.  Small ring (16 B), so cost is bounded
	; and we save the head pointer + wrap arithmetic.
	push	bc
	push	de
	push	hl
	ld	a, (kbd_ring)		; A = oldest byte
	ld	c, a			; save in C across LDIR
	ld	a, (kbd_head)
	dec	a
	ld	(kbd_head), a
	or	a
	jr	z, .ci_done		; ring now empty -> no shift
	ld	b, 0
	ld	hl, kbd_ring + 1
	ld	de, kbd_ring
	ldir
.ci_done:
	ld	a, c
	pop	hl
	pop	de
	pop	bc
	ret

; ---- CRT framebuffer ABI (state owned by prom1.asm, persists in RAM
; across PROM disable; consumed here by impl_conout) ---------------
; Pinned at 0xF400 -- inside the SNIOS RESERVED AREA (0xED00..0xF7FF),
; clear of snios_payload's actual bytes (currently end ~0xF080).
; See feedback_slave_state_outside_tpa.md + feedback_state_address_phase_audit.md.
DOT_CURSOR	equ	0xF400		; 16-bit display address
DOT_COL		equ	0xF402		; 8-bit
DOT_ROW		equ	0xF403		; 8-bit
PORT_CRT_CMD	equ	0x01
PORT_CRT_PARAM	equ	0x00
CRT_CMD_LOADCUR	equ	0x80
DSP_BASE	equ	0xF800		; display memory start (80 x 24 x 1 B)
DSP_COLS	equ	80
DSP_ROWS	equ	24

impl_conout:
	; CONOUT: char in C.  Writes to BOTH the CRT framebuffer at 0xF800
	; AND mirrors to SIO-B (polypascal_test.lua scrape source).
	; Currently handles CR (0x0D), LF (0x0A), printable advance,
	; col-80 wrap, and row-23 scroll.  Full RC700 control-code set
	; (insert/delete line, XY addressing, bell, clear screen, etc.)
	; is parked: shipping it pushed PROM1 well past 2 KB and had bugs
	; that stalled the slave at boot.  CR/LF + printables cover
	; PolyPascal, CCP, and the polypascal-test workload.
	;
	; NDOS overwrites bios_jt[4] with nconot during COLDST; nconot
	; calls back into this impl via the tlbios snapshot for local
	; console.  CP/M BIOS CONOUT clobbers A/BC/DE/HL freely.
	;
	; No per-conout 8275 cursor sync -- the 50 Hz CTC-CH2 ISR
	; (isr_cursor) pushes (DOT_COL, DOT_ROW) to the chip only when
	; they've changed since the last tick.
	ld	a, c
	call	emit_a			; SIO-B mirror first; preserves C
	ld	a, c
	cp	0x0D
	jr	z, .co_cr
	cp	0x0A
	jr	z, .co_row_inc
	; Printable: write char @ (DOT_CURSOR), advance cursor + col.
	ld	hl, (DOT_CURSOR)
	ld	(hl), a
	inc	hl
	ld	(DOT_CURSOR), hl
	ld	a, (DOT_COL)
	inc	a
	cp	DSP_COLS
	jr	c, .co_save_col
	xor	a			; col=80 -> wrap to row+1 col 0
	ld	(DOT_COL), a
	jr	.co_row_inc
.co_save_col:
	ld	(DOT_COL), a
	jp	co_sync_cursor		; tail: push (col,row) to 8275, then ret
.co_cr:
	xor	a
	ld	(DOT_COL), a
	jr	co_recompute
.co_row_inc:
	ld	a, (DOT_ROW)
	inc	a
	cp	DSP_ROWS
	jr	c, .co_row_save		; row < 24: no scroll
	; Scroll: LDIR rows 1..23 up to rows 0..22, fill row 23 spaces.
	ld	hl, DSP_BASE + DSP_COLS
	ld	de, DSP_BASE
	ld	bc, DSP_COLS * (DSP_ROWS - 1)
	ldir
	ld	hl, DSP_BASE + DSP_COLS * (DSP_ROWS - 1)
	ld	(hl), ' '
	ld	d, h
	ld	e, l
	inc	de
	ld	bc, DSP_COLS - 1
	ldir
	ld	a, DSP_ROWS - 1
.co_row_save:
	ld	(DOT_ROW), a
	; fall through to co_recompute

; Recompute DOT_CURSOR from (DOT_ROW, DOT_COL).
;   DOT_CURSOR = DSP_BASE + DOT_ROW * 80 + DOT_COL
co_recompute:
	ld	a, (DOT_ROW)
	ld	h, 0
	ld	l, a
	add	hl, hl			; row*2
	add	hl, hl			; *4
	ld	d, h
	ld	e, l			; DE = row*4
	add	hl, hl			; *8
	add	hl, hl			; *16
	add	hl, de			; *20
	add	hl, hl			; *40
	add	hl, hl			; *80
	ld	de, DSP_BASE
	add	hl, de
	ld	a, (DOT_COL)
	ld	e, a
	ld	d, 0
	add	hl, de
	ld	(DOT_CURSOR), hl
	; fall through to co_sync_cursor

; Push (DOT_COL, DOT_ROW) to the 8275 via LOAD CURSOR.  Called
; tail-style from every impl_conout exit path so the visible block
; cursor always tracks the next-write position.  3 port writes ~= 11 T;
; negligible vs surrounding store + LDIR-scroll cost.
co_sync_cursor:
	ld	a, CRT_CMD_LOADCUR
	out	(PORT_CRT_CMD), a
	ld	a, (DOT_COL)
	out	(PORT_CRT_PARAM), a
	ld	a, (DOT_ROW)
	out	(PORT_CRT_PARAM), a
	ret

; ---- Slim BIOS stubs ------------------------------------------------
; Debug-char emits in these handlers were size-cost > benefit: CP/NOS
; never invokes SELDSK/SETTRK/SETSEC/SETDMA/READ/WRITE for network
; drives (NDOS routes everything through SNDMSG/RCVMSG), and NDOS
; overwrites LIST/LISTST at COLDST anyway -- the markers couldn't fire
; unless something was already broken.  Bodies are minimal; SELDSK
; returns HL=0, READ/WRITE return A=1 (error), LISTST returns A=0,
; SECTRAN returns HL=BC.  Saved ~52 B vs. emit_a-per-handler.
impl_list:
impl_home:
impl_settrk:
impl_setsec:
impl_setdma:
bios_ret:
	ret

impl_seldsk:
	ld	hl, 0
	ret

impl_read:
impl_write:
	ld	a, 1
	ret

impl_listst:
	xor	a
	ret

impl_sectran:
	ld	h, b
	ld	l, c
	ret

; ---- SNIOS implementations -----------------------------------------
; Stubs with debug markers.  SNDMSG/RCVMSG remain 0xFE returns
; until phase 4c wires real SIO-A frame send/receive into RAM.
; CFGTBL fields used:
;   - slaveid (RC702 = 0x01)
;   - rest zero -- NDOS doesn't read most of cfgtbl at COLDST.

snios_ntwkin:
	; NTWKIN: set cfgtbl.netst = CFG_NETST_ACTIVE (0x10) so NDOS's
	; subsequent sndmsg/rcvmsg gate passes.  'A' marker on SIO-B
	; (load-bearing -- the per-handler emit_a delays were masking
	; some timing-sensitive path; without them PRIMES stalls at 97).
	ld	a, 'A'
	call	emit_a
	ld	a, 0x10
	ld	(cfgtbl), a
	xor	a
	ret

snios_ntwkst:
	ld	a, 'a'
	call	emit_a
	xor	a
	ret

snios_cnftbl:
	ld	a, 'c'
	call	emit_a
	ld	hl, cfgtbl
	ret

; ---- SNDMSG / RCVMSG (real) ----------------------------------------
; NDOS calls these with BC = pointer to a 5-byte msg header followed
; by SIZ+1 DAT bytes:
;   BC+0: FMT    (0 = request, 1 = response)
;   BC+1: DID    (destination -- 0 for master)
;   BC+2: SID    (source -- our slaveid; we patch this in case NDOS
;                 left it as 0xFF or a stale value)
;   BC+3: FNC    (BDOS function code)
;   BC+4: SIZ    (DAT length minus 1; range 0..0xFF -> 1..256 bytes)
;   BC+5..      : DAT bytes
;
; DRI SNIOS return ABI (cpndos.prn line 0297-029B):
;     sdmsge: call nios+9
;             inr a            ; A++ -- if A was 0xFF, becomes 0 -> Z
;             rnz              ; not-zero (= success or non-FF) returns
;             jmp ndend        ; A was 0xFF -> transport error path
; So return A = 0 for success, A = 0xFF for transport error (RCVMSG
; identical convention).  Stub previously returned 0xFE which slipped
; past `inr a` -> 0xFF -> rnz -> NDOS thought call succeeded but
; msgbuf was unchanged, so the SrSr retry loop spun.

; Working scratch RAM (post-PROM-disable, free area between cpnet_msg
; buffer staging and display memory).  SNDMSG buffers the outbound
; frame in cfgtbl.msgbuf -- already allocated, no extra BSS needed.
; RCVMSG writes inbound bytes through the caller's (BC) pointer.

; NDOS calls SNDMSG / RCVMSG with msg ptr in BC and expects BC, DE,
; HL preserved across the call (standard CP/M SNIOS register ABI;
; cpnos-in-c's C bridges preserve them automatically via sdcccall(1)
; callee-saves).  Earlier session debug pinned a `SrSrSr` retry loop
; on corrupted BC between paired SNDMSG / RCVMSG calls: NDOS issued
; `lxi b, msgtop; call sdmsge; <decide>; call rvmsge` and our body
; clobbered BC before rvmsge ran, so the response was written to
; junk memory and NDOS retried forever.  Outer wrapper push/pops fix.
snios_sndmsg:
	push	bc
	push	de
	push	hl
	call	snios_sndmsg_body
	pop	hl
	pop	de
	pop	bc
	ret
snios_sndmsg_body:
	ld	a, 'S'
	call	emit_a
	; Patch SID in caller's buffer to our slaveid.
	ld	h, b
	ld	l, c			; HL = msg ptr
	inc	hl			; +1 = DID
	inc	hl			; +2 = SID
	ld	a, (cfgtbl + 1)		; cfgtbl.slaveid
	ld	(hl), a
	; Reset HL to msg ptr for the header send loop below.
	ld	h, b
	ld	l, c

	; Phase 1: ENQ, wait for ACK.
	ld	a, ENQ
	call	snios_sio_a_tx_a
	call	snios_wait_ack
	jr	c, snios_sndmsg_fail

	; Phase 2: SOH + 5-byte header + HCS.
	ld	a, SOH
	ld	e, a			; E = HCS accumulator (seeded with SOH)
	call	snios_sio_a_tx_a
	ld	h, b
	ld	l, c			; HL = msg ptr (after pop)
	ld	b, 5
.sm_hdr:
	ld	a, (hl)
	call	snios_sio_a_tx_accum	; emit A, E += A
	inc	hl
	djnz	.sm_hdr
	xor	a
	sub	e
	call	snios_sio_a_tx_a	; HCS = -sum (mod 256)
	call	snios_wait_ack
	jr	c, snios_sndmsg_fail

	; Phase 3: STX + DAT[0..SIZ] + ETX + CKS + EOT.
	; HL currently points at msg+5 (DAT[0]).  C = msg+5's low byte
	; was lost; re-derive SIZ from msg+4.  Easier: backtrack HL by
	; 1 to get SIZ at msg+4.
	dec	hl			; -> SIZ
	ld	a, (hl)			; A = SIZ
	inc	hl			; -> DAT[0] again
	ld	c, a
	ld	b, 0
	inc	bc			; BC = SIZ + 1 = DAT byte count
	ld	a, STX
	ld	e, a			; CKS seed
	call	snios_sio_a_tx_a
.sm_dat:
	ld	a, (hl)
	call	snios_sio_a_tx_accum
	inc	hl
	dec	bc
	ld	a, b
	or	c
	jr	nz, .sm_dat
	ld	a, ETX
	call	snios_sio_a_tx_accum
	xor	a
	sub	e
	call	snios_sio_a_tx_a	; CKS
	ld	a, EOT
	call	snios_sio_a_tx_a
	call	snios_wait_ack
	jr	c, snios_sndmsg_fail
	xor	a			; A = 0 = success
	ret

snios_sndmsg_fail:
	ld	a, 0xFF			; transport error
	ret

; Persistent slot for caller's msg pointer during RCVMSG.  Lives in
; the snios_payload's RAM region after CFGTBL so the LDIR carries it
; into RAM at handoff.  Initialized to 0 each call.
snios_msg_ptr:
	dw	0

snios_rcvmsg:
	push	bc
	push	de
	push	hl
	call	snios_rcvmsg_body
	pop	hl
	pop	de
	pop	bc
	ret
snios_rcvmsg_body:
	ld	a, 'r'
	call	emit_a
	; Save caller msg ptr (BC) for both phases.
	ld	(snios_msg_ptr), bc

	; Wait for master's ENQ.
	call	snios_sio_a_rx_to
	jp	c, snios_rcvmsg_fail
	and	0x7F
	cp	ENQ
	jp	nz, snios_rcvmsg_fail
	; ACK the ENQ.
	ld	a, ACK
	call	snios_sio_a_tx_a

	; Phase 2: receive SOH + 5-byte header + HCS.  SOH goes into a
	; 1-byte scratch slot (msg[-1] is reserved by NDOS as msgtop and
	; we shouldn't write there).  Remaining 6 bytes (FMT, DID, SID,
	; FNC, SIZ, HCS) land at msg[0..5] -- the HCS spills into msg[5]
	; which gets overwritten by DAT[0] in Phase 3 (matches PROM1's
	; original recv_cpnet_msg pattern).
	call	snios_sio_a_rx_to
	jp	c, snios_rcvmsg_fail
	ld	(snios_rx_soh), a
	ld	e, a			; HCS accumulator seeded with SOH
	ld	hl, (snios_msg_ptr)
	ld	b, 6
.rm_hdr:
	call	snios_sio_a_rx_to
	jp	c, snios_rcvmsg_fail
	ld	(hl), a
	inc	hl
	add	a, e
	ld	e, a
	djnz	.rm_hdr
	; Validate SOH and HCS sum = 0 (mod 256).
	ld	a, (snios_rx_soh)
	cp	SOH
	jp	nz, snios_rcvmsg_fail
	ld	a, e
	or	a
	jp	nz, snios_rcvmsg_fail
	; ACK the header.
	ld	a, ACK
	call	snios_sio_a_tx_a

	; Phase 3: receive STX + DAT[0..SIZ] + ETX + CKS + EOT.  HL is
	; at msg+6 now (one past HCS).  Re-derive msg ptr (msg + 5) =
	; DAT[0] location.  SIZ lives at msg+4.
	ld	hl, (snios_msg_ptr)
	push	hl
	inc	hl
	inc	hl
	inc	hl
	inc	hl			; HL = msg + 4 = SIZ
	ld	a, (hl)			; A = SIZ
	inc	hl			; HL = msg + 5 = DAT[0]
	ld	c, a
	ld	b, 0
	inc	bc			; BC = SIZ + 1 = DAT byte count

	; Expect STX first.
	call	snios_sio_a_rx_to
	jp	c, snios_rcvmsg_fail_pop
	cp	STX
	jp	nz, snios_rcvmsg_fail_pop
	ld	e, a			; CKS seed
.rm_dat:
	call	snios_sio_a_rx_to
	jp	c, snios_rcvmsg_fail_pop
	ld	(hl), a
	inc	hl
	add	a, e
	ld	e, a
	dec	bc
	ld	a, b
	or	c
	jr	nz, .rm_dat
	; ETX
	call	snios_sio_a_rx_to
	jp	c, snios_rcvmsg_fail_pop
	cp	ETX
	jp	nz, snios_rcvmsg_fail_pop
	add	a, e
	ld	e, a
	; CKS
	call	snios_sio_a_rx_to
	jp	c, snios_rcvmsg_fail_pop
	add	a, e
	or	a
	jp	nz, snios_rcvmsg_fail_pop
	; EOT
	call	snios_sio_a_rx_to
	jp	c, snios_rcvmsg_fail_pop
	cp	EOT
	jp	nz, snios_rcvmsg_fail_pop
	pop	hl
	; Final ACK.
	ld	a, ACK
	call	snios_sio_a_tx_a
	xor	a
	ret

snios_rcvmsg_fail_pop:
	pop	hl
snios_rcvmsg_fail:
	ld	a, 0xFF
	ret

; Scratch slot for received SOH byte (one byte, persistent across
; the RCVMSG header phase).
snios_rx_soh:
	db	0

; SIO-A polled TX (RAM-resident equivalent of PROM1's sio_a_tx_d).
; Send A on SIO-A; preserves A, E, HL, BC.
snios_sio_a_tx_a:
	push	af
.satx_w:
	in	a, (PORT_SIO_A_CTRL)
	and	SIO_TX_BUF_EMPTY
	jr	z, .satx_w
	pop	af
	out	(PORT_SIO_A_DATA), a
	ret

; Send A on SIO-A and add A to E (HCS / CKS accumulator).
snios_sio_a_tx_accum:
	call	snios_sio_a_tx_a
	add	a, e
	ld	e, a
	ret

; SIO-A polled RX with timeout (~400ms at 4MHz).  CF=0 + A=byte on
; success; CF=1 on timeout.  Preserves DE, HL.  Generous timeout
; covers MAME's serial-pipeline scheduling jitter (CP/NET TMRETRY
; spec is forgiving).
snios_sio_a_rx_to:
	push	bc
	ld	bc, 0xFFFF		; ~400ms at 4MHz, 25T per iter
.srx_p:
	in	a, (PORT_SIO_A_CTRL)
	and	SIO_RX_CHAR_AVAIL
	jr	nz, .srx_r
	dec	bc
	ld	a, b
	or	c
	jr	nz, .srx_p
	pop	bc
	scf
	ret
.srx_r:
	in	a, (PORT_SIO_A_DATA)
	pop	bc
	or	a
	ret

; Wait for ACK on SIO-A.  CF=0 on ACK; CF=1 on timeout or non-ACK.
snios_wait_ack:
	call	snios_sio_a_rx_to
	ret	c
	and	0x7F
	cp	ACK
	ret	z
	scf
	ret

snios_ntwker:
	ld	a, 'e'
	call	emit_a
	ret

snios_ntwkbt:
	ld	a, 'B'
	call	emit_a
	ret

snios_ntwkdn:
	ld	a, 'd'
	call	emit_a
	ret

; ---- CFGTBL (DRI CP/NET v1.2) --------------------------------------
; Structure layout (cpnos-shared/include/cfgtbl.h):
;   +0    netst     network status (set to ACTIVE at runtime)
;   +1    slaveid   our slave ID (RC702 = 0x01)
;   +2..  drive[16] 16x uint16: lo = flags, hi = master slave ID
;          flag.bit7 = 1  -> network drive (vs local)
;          flag.bit6 = 0  -> "valid"        (forall walks this)
;          flag low nibble = master drive letter offset (A=0 .. P=15)
;   +34   console
;   +36   list
;   ...
;
; CP/NOS has NO LOCAL DISKS (user clarification 2026-05-16): all
; drives MUST be flagged network so NDOSE routes BDOS file calls
; through SNDMSG/RCVMSG.  Map slave drives A:..P: 1:1 onto master
; drives A:..P: with master slave ID = 0x00 (the MP/M master).
;
; cpnos.com NDOS COLDST calls snios_cnftbl, gets HL = cfgtbl, does
; `inx h; shld contad` -- so contad = cfgtbl + 1 = the slaveid slot.
; chkdsk(disk D) then reads byte at cfgtbl + 2 + 2*D.  With 0x80
; the top bit signals "network" and the low nibble (0..15) maps
; to master drive A..P.  Second byte (cfgtbl + 3 + 2*D) is master
; slave ID (= 0 for the MP/M master).
cfgtbl:
	db	0x00			; +00  netst     (NDOS sets at NTWKIN)
	db	0x01			; +01  slaveid   RC702_SLAVEID
	; +02..+33  drive[0..15]:  {flags, master_slave}
	;   flags = 0x80 | (master_drive_offset & 0x0F)
	;   master_slave = 0 (= MP/M master)
	; mpm-net2 only exposes drives A..D (system) and I, J (4 MB hard
	; disks).  Slave drive E -> master drive I, F -> J: that's where
	; cpmsim/mpm-net2 seeds PPAS + PRIMES from
	; disks/library/mpm-net2-drive[ij].dsk.  Mirrors
	; cpnos-in-c/src/init.c cfgtbl_init_template (drives A..F only;
	; leave drives G..P un-flagged so NDOS treats them as local --
	; chkdsk's `RAL` over a zero byte clears CF, returns A=0xFF =
	; "no such drive" instead of bouncing through the network).
	db	0x80, 0x00		; A: -> master A:
	db	0x81, 0x00		; B: -> master B:
	db	0x82, 0x00		; C: -> master C:
	db	0x83, 0x00		; D: -> master D:
	db	0x88, 0x00		; E: -> master I: (4 MB HD)
	db	0x89, 0x00		; F: -> master J: (4 MB HD)
	db	0,    0			; G: unused
	db	0,    0			; H: unused
	db	0,    0			; I: unused
	db	0,    0			; J: unused
	db	0,    0			; K: unused
	db	0,    0			; L: unused
	db	0,    0			; M: unused
	db	0,    0			; N: unused
	db	0,    0			; O: unused
	db	0,    0			; P: unused
	; +34..+38  console, list, bufidx -- left zero (NDOS sets at runtime)
	db	0,0,0,0,0
	; +39..+43  fmt, did, sid, fnc, siz -- outbound msg fields, NDOS sets
	db	0,0,0,0,0
	; +44       msg0
	db	0
	; +45..+63 (msgbuf head, first 19 bytes only; NDOS uses up to
	; +172).  Keep cfgtbl small enough that the whole snios_payload
	; INCBIN fits in PROM1; NDOS won't read past +43 in COLDST
	; before SNDMSG/RCVMSG actually do anything with msgbuf.
	; If a longer scratch area is later needed, expand here.
	db	0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
	db	0,0,0

; ---- Keyboard ring (RAM, post-LDIR) --------------------------------
; kbd_head holds the number of queued bytes (0..16).  kbd_ring is a
; flat 16-byte buffer; oldest byte at offset 0 (FIFO).  Producer
; (Lua harness via cpu memory tap, or PIO-A ISR in a future build)
; writes a byte to kbd_ring[kbd_head] then increments kbd_head.
; Consumer (impl_conin) reads kbd_ring[0], LDIRs the remaining
; (kbd_head - 1) bytes down by one, decrements kbd_head.
;
; Symbol names match cpnos-in-c (`_kbd_head`, `_kbd_ring`) up to the
; leading underscore that the Z80 ABI prepends to C names; zmac
; emits these as plain `kbd_head` / `kbd_ring`, and the asm
; polypascal-test target awk-extracts them from build/snios_payload.sym
; with the same `kbd_head`/`kbd_ring` strings.
kbd_head:
	db	0
kbd_ring:
	db	0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0

	end	handoff_entry
