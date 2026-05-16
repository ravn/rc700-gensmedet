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
;   's'  bios_const
;   'i'  bios_conin
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
	; Cold-boot vector.  Rare; if NDOS or CCP reaches here we
	; just spin so the SIO-B capture shows the 'b' marker.
	ld	a, 'b'
	call	emit_a
.b_hang:
	jr	.b_hang

impl_wboot:
	; NDOS overwrites this slot at COLDST with nwboot (0xE083),
	; so we only see 'w' if cpnos.com somehow falls back to the
	; raw BIOS WBOOT before NDOS patches.  Implementation: spin.
	ld	a, 'w'
	call	emit_a
.w_hang:
	jr	.w_hang

impl_const:
	; CONST: return A = 0 (no console char available).  NDOS
	; overwrites this slot with nconst at COLDST, which polls
	; both the network and the local console; for the brief
	; pre-patch window any reads must return "idle".
	ld	a, 's'
	call	emit_a
	xor	a
	ret

impl_conin:
	; CONIN: return A = 0 (would block in real BIOS).  NDOS
	; overwrites with nconin at COLDST.  If anything calls the
	; raw BIOS CONIN we emit 'i' so we can see it.
	ld	a, 'i'
	call	emit_a
	xor	a
	ret

impl_conout:
	; CONOUT: char in C.  Forward to SIO-B so all NDOS / BDOS /
	; CCP output is captured during bring-up.  NDOS overwrites
	; this slot with nconot during COLDST; once that's in place
	; nconot calls back into the original BIOS CONOUT via tlbios
	; -> so this impl_conout is what NDOS routes hardware output
	; through.  Don't emit a separate debug marker -- the char
	; itself is the marker.
	ld	a, c
	call	emit_a
	ret

impl_list:
	; LIST / PUNCH stubs.  NDOS overwrites LIST with nlist at
	; COLDST.  'L' marker so we see any unexpected hits.
	ld	a, 'L'
	call	emit_a
	ret

impl_home:
	ld	a, 'h'
	call	emit_a
	ret

impl_seldsk:
	; SELDSK: return HL = 0 (no DPH for this drive -- CP/NOS
	; routes everything through SNIOS so SELDSK is purely for
	; NDOS to satisfy the BIOS-JT walk).
	ld	a, 'D'
	call	emit_a
	ld	hl, 0
	ret

impl_settrk:
	ld	a, 'T'
	call	emit_a
	ret

impl_setsec:
	ld	a, 'X'
	call	emit_a
	ret

impl_setdma:
	; SETDMA: BC = DMA addr.  No-op; NDOS tracks DMA itself.
	ld	a, 'M'
	call	emit_a
	ret

impl_read:
	; READ: return A = 1 (error -- no local disks in CP/NOS).
	ld	a, 'R'
	call	emit_a
	ld	a, 1
	ret

impl_write:
	ld	a, 'W'
	call	emit_a
	ld	a, 1
	ret

impl_listst:
	; LISTST: return A = 0 (printer not ready).  NDOS overwrites.
	ld	a, 'L'
	call	emit_a
	xor	a
	ret

impl_sectran:
	; SECTRAN: identity translation.  Input BC = logical sector;
	; HL points to xlt table or 0.  Return HL = BC (no
	; translation in CP/NOS).
	ld	a, 't'
	call	emit_a
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
	ld	a, 'A'
	call	emit_a
	xor	a			; A = 0 = success
	ret

snios_ntwkst:
	ld	a, 'a'
	call	emit_a
	xor	a			; A = 0 = idle
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
	; DEBUG: dump tx byte to SIO-B as '<XX'.
	push	af
	push	bc
	ld	c, a
	ld	a, '<'
	call	emit_a
	ld	a, c
	call	emit_hex_a
	pop	bc
	pop	af
.satx_w:
	in	a, (PORT_SIO_A_CTRL)
	and	SIO_TX_BUF_EMPTY
	jr	z, .satx_w
	pop	af
	out	(PORT_SIO_A_DATA), a
	ret

; Print A as 2 hex digits on SIO-B (debug).  Preserves A and BC.
emit_hex_a:
	push	af
	push	bc
	ld	c, a
	rrca
	rrca
	rrca
	rrca
	and	0x0F
	call	emit_hex_nyb
	ld	a, c
	and	0x0F
	call	emit_hex_nyb
	pop	bc
	pop	af
	ret
emit_hex_nyb:
	add	a, '0'
	cp	'9' + 1
	jr	c, .ehn_d
	add	a, 7			; 'A' - ('9'+1) = 7
.ehn_d:
	jp	emit_a

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
	; DEBUG: mark rx timeout with 'T'.
	push	af
	ld	a, 'T'
	call	emit_a
	pop	af
	scf
	ret
.srx_r:
	in	a, (PORT_SIO_A_DATA)
	pop	bc
	; DEBUG: dump rx byte to SIO-B with '>' prefix.
	push	af
	push	bc
	ld	c, a
	ld	a, '>'
	call	emit_a
	ld	a, c
	call	emit_hex_a
	pop	bc
	pop	af
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
	;   flags = 0x80 | (drive_letter_offset & 0x0F)
	;   A->A: 0x80,00   B->B: 0x81,00  ...  P->P: 0x8F,00
	db	0x80, 0x00		; A:
	db	0x81, 0x00		; B:
	db	0x82, 0x00		; C:
	db	0x83, 0x00		; D:
	db	0x84, 0x00		; E:
	db	0x85, 0x00		; F:
	db	0x86, 0x00		; G:
	db	0x87, 0x00		; H:
	db	0x88, 0x00		; I:
	db	0x89, 0x00		; J:
	db	0x8A, 0x00		; K:
	db	0x8B, 0x00		; L:
	db	0x8C, 0x00		; M:
	db	0x8D, 0x00		; N:
	db	0x8E, 0x00		; O:
	db	0x8F, 0x00		; P:
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

	end	handoff_entry
