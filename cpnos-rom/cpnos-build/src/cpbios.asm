	title	'RC702 BIOS trampoline for CP/NOS 1.2'
;
; Replaces cpnet-z80/dist/src/cpbios.asm (which talks to Altos
; console/list ports 0x1C/0x1E).  On RC702 the console is the 8275
; CRT at 0xF800 and the list device is absent; those live in the
; cpnos-rom resident at VMA 0xED00+.
;
; This module provides:
;   - BIOS jump table (17 × 3-byte JPs) at `BIOS:`
;   - boot code that sets up CP/M zero page, copies the BIOS JT to
;     NDOSRL+0x300 (so CCP calls BIOS through the intercepted copy),
;     prints a signon banner via our resident CONOUT, and jumps to
;     NDOS coldstart.
;   - Thin const/conin/conout/list shims that call into the cpnos-rom
;     resident BIOS at 0xED00..0xED0F.  Register conversion: CP/M
;     passes char in C, returns status/char in A, preserves all other
;     regs.  cpnos-rom uses clang sdcccall(1): arg in A, 8-bit return
;     in L, callee-saved = none.  The shims bridge by pushing BC/DE
;     around the call and translating C↔A and L↔A.
;
;	Copyright (c) 1980..82 Digital Research (original concept)
;	RC702 retarget 2026-04, issue #38
;
true	equ	0ffffh
false	equ	not true
;
; cpnos-rom resident BIOS JT addresses (cpnos_rom.ld asserts these
; are stable: BIOS_BASE + 0/3/6/9/12/15).
rbboot	equ	0DE00h
rbwboot	equ	0DE03h
rbconst	equ	0DE06h
rbconin	equ	0DE09h
rbcout	equ	0DE0Ch
rblist	equ	0DE0Fh
rbseldsk equ	0DE1Bh
rbsettrk equ	0DE1Eh
rbsetsec equ	0DE21h
rbsetdma equ	0DE24h
rbread	equ	0DE27h
rbwrite	equ	0DE2Ah
;
	extrn	NDOS	; Network Disk Operating System
	extrn	BDOS	; Basic Disk Operating System
	extrn	NDOSRL	; NDOS serial number, BIOS jump table
			;  is page aligned at 0300H offset
	CSEG
BIOS:
	public	BIOS
;	jump vector for individual routines
	jmp	boot		; +0
wboote:	jmp	error		; +3  wboot (unused in CP/NOS)
	jmp	cshim	; +6
	jmp	cishim	; +9
	jmp	coshim	; +12
	jmp	lshim	; +15
	jmp	error		; +18 PUNCH
	jmp	error		; +21 READER
	jmp	error		; +24 HOME (BDOS doesn't call; we don't implement)
	jmp	dskshim	; +27 SELDSK  → cpnos-rom impl_seldsk at 0xDD1B
	jmp	trkshim	; +30 SETTRK  → cpnos-rom impl_settrk at 0xDD1E
	jmp	secshim	; +33 SETSEC  → cpnos-rom impl_setsec at 0xDD21
	jmp	dmashim	; +36 SETDMA  → cpnos-rom impl_setdma at 0xDD24
	jmp	rdshim	; +39 READ    → cpnos-rom impl_read at 0xDD27
	jmp	wrshim	; +42 WRITE   → cpnos-rom (currently stub returning error)
	jmp	lsshim	; +45 LISTST
	jmp	error		; +48 SECTRAN (DPH.xlt = NULL for B:, not called)
BIOSlen	equ	$-BIOS
;
cr	equ	0dh
lf	equ	0ah
jpopc	equ	0c3h
buff	equ	0080h
;
signon:
;	db	cr,lf
	db	'RC702 CP/NOS v1.2'
	db	cr,lf,0
;
boot:	; print signon and jump to NDOS coldstart
	lxi	sp,buff+0080h
	lxi	h,signon
	call	prmsg
	mvi	a,jpopc
	sta	0000h
	sta	0005h
	lxi	h,BDOS
	shld	0006h
	xra	a
	sta	0004h
	lxi	h,NDOSRL+0303h
	shld	0001h
	dcx	h
	dcx	h
	dcx	h		; HL = NDOSRL+0300h (CCP's BIOS JT slot)
	lxi	d,BIOS
	mvi	c,BIOSlen
initloop:
	ldax	d
	mov	m,a
	inx	h
	inx	d
	dcr	c
	jnz	initloop
	jmp	NDOS+03h	; NDOS cold-start
;
; Utility
error:
	lxi	h,0ffffh
	mov	a,h
	ret
;
prmsg:	; print zero-terminated string at HL
	mov	a,m
	ora	a
	rz
	push	h
	mov	c,a
	call	coshim
	pop	h
	inx	h
	jmp	prmsg
;
; ---- ABI shims: CP/M BIOS <-> cpnos-rom resident ---------------
;
; CP/M:   CONOUT(c in C),  CONIN(→A), CONST(→A), LIST(c in C),
;         LISTST(→A).  All regs preserved except the A return.
; clang sdcccall(1):  arg in A, 8-bit return in L, all caller-saved.
;
; Without push/pop wrappers the CCP/NDOS loop counters in BC/DE get
; trashed and CCP spins emitting a single char (symptom seen during
; issue #36 rc700_console integration attempt).
; HL is the return register on the clang side so we do NOT preserve
; it; CP/M callers don't expect HL to survive either.
;
; NOTE on sdcccall(1) 8-bit return: clang Z80 sdcccall(1) returns
; 8-bit values in A (NOT L as we initially assumed).  Confirmed
; 2026-04-22 from impl_conin / impl_const disassembly — both end
; with `ld a,d; ret`.  Do NOT do `mov a,l` here: it would overwrite
; the correct return with the stale HL low byte.  (That bug made
; CCP echo `F G H I` = 0x46..0x49 for input `d i r \r` because
; HL happened to track the input-ring scratch address 0xEC46+.)
cshim:
	push	b
	push	d
	call	rbconst	; A = status (0x00 or 0xFF)
	pop	d
	pop	b
	ret
;
cishim:
	push	b
	push	d
	call	rbconin	; A = char
	pop	d
	pop	b
	ret
;
coshim:
	push	b
	push	d
	mov	a,c		; CP/M: char in C; clang: char in A
	call	rbcout
	pop	d
	pop	b
	ret
;
lshim:
	push	b
	push	d
	mov	a,c
	call	rblist
	pop	d
	pop	b
	ret
;
lsshim:
	; No list device on RC702; return "ready" (0xff) so prints
	; don't block.  (Matches original Altos listst behaviour when
	; the port was absent.)
	xra	a
	ret
;
; Disk BIOS shims — tail-call to cpnos-rom's resident BIOS.  Push/pop
; BC/DE around the call because the Altos+DRI ABI expects them
; preserved across BIOS entries, while clang-z80's sdcccall(1) is
; free to clobber them.  Our asm impls at rb{seldsk,settrk,...} don't
; actually clobber BC/DE today, but following the cshim pattern keeps
; the contract safe regardless of how the C-side implementation grows.
;
; SELDSK: drive in C, DPH pointer returned in HL.
dskshim:
	push	b
	push	d
	call	rbseldsk
	pop	d
	pop	b
	ret
;
; SETTRK / SETSEC / SETDMA: 16-bit arg in BC (CP/M convention),
; no return value.
trkshim:
	push	b
	push	d
	call	rbsettrk
	pop	d
	pop	b
	ret
;
secshim:
	push	b
	push	d
	call	rbsetsec
	pop	d
	pop	b
	ret
;
dmashim:
	push	b
	push	d
	call	rbsetdma
	pop	d
	pop	b
	ret
;
; READ / WRITE: no args (state set via SETTRK/SETSEC/SETDMA earlier),
; returns A=0 success, A=1 error.
rdshim:
	push	b
	push	d
	call	rbread
	pop	d
	pop	b
	ret
;
wrshim:
	push	b
	push	d
	call	rbwrite
	pop	d
	pop	b
	ret
;
	end
