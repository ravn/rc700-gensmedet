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

PORT_SIO_B_DATA	equ	0x09
PORT_SIO_B_CTRL	equ	0x0B
SIO_TX_BUF_EMPTY equ	0x04
PORT_RAMEN	equ	0x18

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

snios_sndmsg:
	; STUB: return transport error.  Phase 4c: wire real
	; SIO-A send (HCS / STX / DAT / ETX / CKS / EOT framing)
	; here, operating on msg pointer in BC.
	ld	a, 'S'
	call	emit_a
	ld	a, 0xFE
	ret

snios_rcvmsg:
	ld	a, 'r'
	call	emit_a
	ld	a, 0xFE
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

; ---- CFGTBL (DRI CP/NET v1.2 minimal) ------------------------------
; cpnos.com NDOS COLDST calls snios_cnftbl, gets HL = cfgtbl, does
; `inx h; shld contad` -- so contad = cfgtbl + 1 = the SID slot
; address.  NDOS uses contad later to read SLAVEID, ROUTE entries,
; etc.  Only slaveid is set; everything else stays zero until NDOS
; exercises it.
cfgtbl:
	db	0x01			; +00  slaveid (RC702_SLAVEID)
	; 63 zero bytes (pad to 64 B total).  zmac's `ds N, 0`
	; raises a Value error here regardless of expression form;
	; use explicit db list (same workaround as prom0.asm /
	; prom1.asm).
	db	0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
	db	0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
	db	0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
	db	0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0

	end	handoff_entry
