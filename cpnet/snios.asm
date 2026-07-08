; RC702 CP/NET SNIOS (Slave Network I/O System)
; DRI binary serial protocol over BIOS READER/PUNCH/READS
;
; Implements the standard DRI CP/NET serial framing:
;   Send: ENQ → ACK → SOH+header+HCS → ACK → STX+data+ETX+CKS+EOT → ACK
;   Recv: ENQ → ACK → SOH+header+HCS → ACK → STX+data+ETX+CKS+EOT → ACK
;
; Character I/O calls BIOS READER/PUNCH/READS through the standard
; jump table at DA00h (56K system). No direct hardware access.
;
; Assembled at ORG 0000h for SPR relocation.
; build_snios.py assembles twice and generates the relocation bitmap.
;

	.Z80

; BIOS entry points (56K system, BIOS base = DA00h)
B$PUNCH	EQU	0DA12H		; BIOS PUNCH (send byte in C via SIO Ch.A)
B$READ	EQU	0DA15H		; BIOS READER (receive byte from SIO Ch.A)
B$RSTA	EQU	0DA4DH		; BIOS READS (reader status, 0=not ready)
B$CONOUT EQU	0DA0CH		; BIOS CONOUT (send char in C to console)

; RC702 ports — used by PIO transport (see byte-IO dispatcher below).
; Mirrors cpnos-in-c/src/transport_pio.c (the cpnos-side equivalent).
PIO_B_DATA	EQU	011H		; PIO ch.B data register
PIO_B_CTRL	EQU	013H		; PIO ch.B control register
SW1		EQU	014H		; DIP-switch bank 1

; PIO mode-control byte values (Z80 PIO datasheet section "Control
; Word Format"; see also docs/SW1_BIT_MAP.md).
PIO_MODE_OUTPUT	EQU	00FH		; Mode 0 (output)
PIO_MODE_INPUT	EQU	04FH		; Mode 1 (input)
PIO_IE_DISABLE	EQU	003H		; interrupt-enable FF: bit7=0 → off
PIO_IE_ENABLE	EQU	083H		; interrupt-enable FF: bit7=1 → on
PIO_IE_ENA_RST	EQU	097H		; ICW: enable + mask byte follows
PIO_INT_MASK	EQU	000H		; mask = 0 → all bits enabled

; IVT slot 17 (PIO-B IRQ) — rcbios's setup_ivt() seeds this with
; isr_pio_par (a stub, since PIO-B is in OUTPUT mode by default in
; rcbios).  In PIO transport mode we overwrite the slot with
; ISR_PIO_RX to redirect arrivals into our ring buffer.
IVT_PIO_B_OFF	EQU	022H		; 17 × 2 = 0x22

; Protocol constants
SOH	EQU	01H		; Start of Header
STX	EQU	02H		; Start of Data
ETX	EQU	03H		; End of Data
EOT	EQU	04H		; End of Transmission
ENQ	EQU	05H		; Enquire
ACK	EQU	06H		; Acknowledge
NAK	EQU	15H		; Negative Acknowledge

; Slave node ID (must match server configuration)
SLAVEID	EQU	01H		; our node on the network

; Retry and timeout parameters
MAXRETRY EQU	10		; max send/receive retries
TMRETRY	EQU	100		; timeout retries per attempt

; Network status byte flags
ACTIVE	EQU	00010000B	; SLAVE LOGGED IN ON NETWORK
RCVERR	EQU	00000010B	; ERROR IN RECEIVED MESSAGE
SNDERR	EQU	00000001B	; UNABLE TO SEND MESSAGE

	ORG	0

;================================================
;= SNIOS JUMP TABLE (MUST BE FIRST)             =
;= NDOS calls through these offsets              =
;================================================
	JP	NTWKIN		; +00 NETWORK INITIALIZATION
	JP	NTWKST		; +03 NETWORK STATUS
	JP	CNFTBL		; +06 RETURN CONFIG TABLE ADDRESS
	JP	SNDMSG		; +09 SEND MESSAGE ON NETWORK
	JP	RCVMSG		; +0C RECEIVE MESSAGE FROM NETWORK
	JP	NTWKER		; +0F NETWORK ERROR
	JP	NTWKBT		; +12 NETWORK WARM BOOT
	JP	NTWKDN		; +15 NETWORK SHUTDOWN

;================================================
;= SLAVE CONFIGURATION TABLE                    =
;= MUST MATCH CP/NET CFGTBL LAYOUT              =
;================================================
CFGTBL:	DB	0		; +0  NETWORK STATUS BYTE
	DB	0FFH		; +1  SLAVE PROCESSOR ID (FFh = accept any DID during init)
	DS	2		; +2  A: DISK DEVICE (BIT7=0 = LOCAL)
	DS	2		; +4  B:
	DS	2		; +6  C:
	DS	2		; +8  D:
	DS	2		; +10 E:
	DS	2		; +12 F:
	DS	2		; +14 G:
	DS	2		; +16 H:
	DS	2		; +18 I:
	DS	2		; +20 J:
	DS	2		; +22 K:
	DS	2		; +24 L:
	DS	2		; +26 M:
	DS	2		; +28 N:
	DS	2		; +30 O:
	DS	2		; +32 P:
	DS	2		; +34 CONSOLE DEVICE (BIT7=0 = LOCAL)
	DS	2		; +36 LIST DEVICE (BIT7=0 = LOCAL)
	DS	1		; +38 BUFFER INDEX
	DB	0		; +39 FMT
	DB	0		; +40 DID
	DB	0FFH		; +41 SID (CP/NOS MUST STILL INITIALIZE)
	DB	5		; +42 FNC (LST: FUNCTION CODE)
	DS	1		; +43 SIZ
	DS	1		; +44 MSG(0) LIST NUMBER
MSGBUF:				; +45 MSG(1)..MSG(128)
	DS	128		; (don't disturb LST: header above)

MSGADR:	DS	2		; MESSAGE ADDRESS (SCRATCH)
RETCNT:	DS	1		; RETRY COUNTER

; PIO transport state (NTWKIN initializes if SW1 bit 2 selects PIO).
PIO_DIR:	DS	1	; 0 = input, 1 = output (PIO-B mode flip)
PIO_HEAD:	DS	1	; ISR_PIO_RX write head into PIO_RING
PIO_TAIL:	DS	1	; RECVBY_PIO read tail
PIO_RING:	DS	256	; SPSC ring; head/tail wrap mod 256 (each DS-reserved byte is 0x00 in the loaded image, which is fine — ring starts empty)

; Retransmit counters — wrapping uint8; zeroed by CP/NET loader on cold start.
; Reported to console by ERRRTN on protocol failure so they appear in the
; SIO-B mirror log.  Readable externally (Lua debugscript) at runtime.
TX_RETRY_CNT:	DS	1	; increments at SNDRET (send-side retransmit)
RX_RETRY_CNT:	DS	1	; increments at RECALL retry (recv-side retransmit)

;================================================
;= CHARACTER I/O DISPATCHERS                    =
;================================================
; SENDBY / RECVBY / RECVBT are 3-byte `JP nn` trampolines.  NTWKIN
; patches the target at +1 to either *_SIO (default, BIOS-driven) or
; *_PIO (direct PIO-B + IRQ ring buffer) based on SW1 bit 2.  Once
; patched, dispatch is zero overhead -- the call lands on the JP,
; which tail-jumps to the chosen impl, which returns directly to the
; original caller.  Same pattern cpnos-in-c uses in xport_aliases.asm.
;
; Preservation contract is the SAME for both impls -- callers may
; clobber A but expect HL and DE preserved.

SENDBY:	JP	SENDBY_SIO	; +1/+2 patched by NTWKIN if PIO

RECVBY:	JP	RECVBY_SIO

RECVBT:	JP	RECVBT_SIO

;================================================
;= SIO IMPLEMENTATIONS (BIOS PUNCH/READER)      =
;================================================

; SENDBY_SIO - Send byte in A via BIOS PUNCH.
; Preserves: HL, DE (BIOS PUNCH may clobber them per CP/M 2.2 spec;
; MSGOUT's loop counter in E and checksum in D must survive).
SENDBY_SIO:
	PUSH	HL
	PUSH	DE
	LD	C,A
	CALL	B$PUNCH		; BIOS PUNCH WAITS FOR TX READY
	POP	DE
	POP	HL
	RET

; RECVBY_SIO - Receive one byte (busy wait, no timeout)
; Returns: A = byte, CY clear
; Preserves: HL, DE (BIOS READER/READS use HL internally)
RECVBY_SIO:
	PUSH	HL
	PUSH	DE
RCVBY1:	CALL	B$RSTA		; BIOS READER STATUS
	OR	A
	JR	Z,RCVBY1
	CALL	B$READ		; READ BYTE FROM RING BUFFER
	POP	DE
	POP	HL
	OR	A		; CLEAR CARRY
	RET

; RECVBT_SIO - Receive one byte with timeout
; Returns: A = byte, CY clear on success; CY set on timeout
RECVBT_SIO:
	PUSH	DE
	PUSH	HL
	LD	HL,8000H	; TIMEOUT COUNTER
RCVWT1:	CALL	B$RSTA		; BIOS READER STATUS
	OR	A
	JR	NZ,RCVWT3	; DATA AVAILABLE
	DEC	HL
	LD	A,H
	OR	L
	JR	NZ,RCVWT1	; KEEP POLLING
	; Timeout expired
	POP	HL
	POP	DE
	SCF			; SIGNAL TIMEOUT
	RET
RCVWT3:	CALL	B$READ		; READ BYTE FROM RING BUFFER
	POP	HL
	POP	DE
	OR	A		; CLEAR CARRY (SUCCESS)
	RET

;================================================
;= PIO IMPLEMENTATIONS (direct PIO ch.B + IRQ)  =
;================================================
; Mirrors cpnos-in-c/src/transport_pio.c.  PIO-B is in Mode 1 (input)
; by default once NTWKIN has fired; SENDBY_PIO flips to Mode 0 (output)
; on first send (PIO_DIR latches the state so subsequent sends skip
; the mode-switch).  ISR_PIO_RX captures incoming bytes into PIO_RING
; while in input mode; RECVBY_PIO / RECVBT_PIO drain that ring.
;
; Preservation: HL, DE (per the SENDBY/RECVBY/RECVBT contract).

; SENDBY_PIO - Send byte in A out PIO-B.
; First call after a recv flips Mode 1 -> Mode 0; subsequent calls
; just write DATA.  See cpnos transport_pio.c lines 130-145 for the
; "preload before mode switch" rationale (works on real silicon and
; MAME's cpnet_bridge wire-once it's running).
SENDBY_PIO:
	PUSH	HL
	PUSH	DE
	LD	E,A		; save data byte
	LD	A,(PIO_DIR)
	DEC	A
	JR	Z,SENDP1	; already in output (PIO_DIR == 1)
	LD	A,PIO_IE_DISABLE
	OUT	(PIO_B_CTRL),A
	LD	A,E		; data preload (latches m_output)
	OUT	(PIO_B_DATA),A
	LD	A,PIO_MODE_OUTPUT
	OUT	(PIO_B_CTRL),A	; fires callback with our data
	LD	A,1
	LD	(PIO_DIR),A
	POP	DE
	POP	HL
	RET
SENDP1:	LD	A,E
	OUT	(PIO_B_DATA),A
	POP	DE
	POP	HL
	RET

; RECVBY_PIO - Receive one byte with timeout.
; Returns: A = byte, CY clear on success; CY set on timeout.
; Identical to RECVBT_PIO — mid-frame byte loss (e.g. from MAME's stuck-IUS
; emulation bug) must not deadlock the slave.  Timeout allows RCVMSG to retry
; the frame via RECALL rather than spinning forever (previous behaviour).
; Timeout budget: ~82 ms (HL=0x8000 * ~10 T-states / 4 MHz) — same as
; RECVBT_PIO and the SIO RECVBT_SIO equivalent.
RECVBY_PIO:
	JP	RECVBT_PIO

; RECVBT_PIO - Receive one byte with timeout.
; Returns: A = byte, CY clear on success; CY set on timeout.
; Timeout counter parallel to SIO version (HL = 0x8000).  Each
; iteration is ~10 T-states; 32768 iters * 10 / 4MHz ≈ 82 ms before
; CY set.  Matches snios TMRETRY=100 outer loop budget.
RECVBT_PIO:
	PUSH	DE
	PUSH	HL
	CALL	PIO_TO_INPUT
	LD	HL,8000H	; TIMEOUT COUNTER
RECVPT1:
	LD	A,(PIO_HEAD)
	LD	E,A
	LD	A,(PIO_TAIL)
	CP	E
	JR	NZ,RECVPT2	; got a byte
	DEC	HL
	LD	A,H
	OR	L
	JR	NZ,RECVPT1
	; Timeout expired
	POP	HL
	POP	DE
	SCF
	RET
RECVPT2:
	; Ring has data; read at tail, advance tail mod 256.
	LD	HL,PIO_RING
	LD	D,0
	LD	E,A		; A = PIO_TAIL value
	ADD	HL,DE
	LD	A,(HL)
	INC	E
	LD	HL,PIO_TAIL
	LD	(HL),E
	POP	HL
	POP	DE
	OR	A		; CLEAR CARRY (success)
	RET

; PIO_TO_INPUT - Switch PIO-B back to Mode 1 input if currently in
; output mode.  Idempotent (no-op when already input).  Preserves
; all registers except A and flags.
PIO_TO_INPUT:
	LD	A,(PIO_DIR)
	OR	A
	RET	Z		; already input
	LD	A,PIO_MODE_INPUT
	OUT	(PIO_B_CTRL),A
	LD	A,PIO_IE_ENA_RST
	OUT	(PIO_B_CTRL),A
	LD	A,PIO_INT_MASK
	OUT	(PIO_B_CTRL),A
	LD	A,PIO_IE_ENABLE
	OUT	(PIO_B_CTRL),A
	XOR	A
	LD	(PIO_DIR),A
	RET

; ISR_PIO_RX - PIO-B IRQ handler (installed at IVT slot 17 by NTWKIN's
; PIO-mode branch).  Reads one byte from PIO_B_DATA, pushes into the
; SPSC ring at PIO_HEAD, advances head (wraps mod 256).  No ring-full
; check -- 256 B is far more than the longest CP/NET frame; head
; overrunning tail would drop bytes silently, but the master's wire
; pace keeps the ring drained.
ISR_PIO_RX:
	PUSH	AF
	PUSH	BC
	PUSH	DE
	PUSH	HL
	IN	A,(PIO_B_DATA)	; A = arrived byte
	LD	C,A		; stash data while we compute address
	LD	A,(PIO_HEAD)
	LD	E,A
	INC	A
	LD	(PIO_HEAD),A	; advance head (wraps mod 256, 8-bit)
	LD	D,0
	LD	HL,PIO_RING
	ADD	HL,DE		; HL = PIO_RING + head
	LD	(HL),C		; store data byte
	POP	HL
	POP	DE
	POP	BC
	POP	AF
	EI
	RETI

;================================================
;= CHECKSUM UTILITIES                           =
;= D = running checksum accumulator             =
;================================================

; NETOUT - Send byte C, accumulate checksum in D
NETOUT:	LD	A,D
	ADD	A,C
	LD	D,A		; UPDATE CHECKSUM
	LD	A,C
	JP	SENDBY		; SEND RAW BYTE

; NETIN - Receive byte, accumulate checksum in D
; Returns: A = byte, D updated, Z flag reflects checksum; CY set on timeout.
; CY from RECVBY is now propagated — MSGIN's RET C guard and all other
; callers that check RET C after NETIN now correctly abort on timeout.
NETIN:	CALL	RECVBY		; GET RAW BYTE (CY set on timeout)
	RET	C		; PROPAGATE TIMEOUT — skip checksum update
	LD	B,A
	ADD	A,D		; ADD TO CHECKSUM
	LD	D,A
	OR	A		; SET Z FLAG FROM CHECKSUM
	LD	A,B		; RESTORE BYTE
	RET

; MSGIN - Receive E bytes into (HL), accumulate checksum
; Returns: CY set on timeout
MSGIN:	CALL	NETIN
	RET	C		; TIMEOUT
	LD	(HL),A
	INC	HL
	DEC	E
	JR	NZ,MSGIN
	RET

; MSGOUT - Send preamble C, then E bytes from (HL), init checksum
; D = 0 on entry (initialized here), accumulates checksum
MSGOUT:	LD	D,0		; INIT CHECKSUM
	CALL	PREOUT		; SEND PREAMBLE (C), UPDATE D
MSOLP:	LD	C,(HL)
	INC	HL
	CALL	NETOUT
	DEC	E
	JR	NZ,MSOLP
	RET

; PREOUT - Send byte C, accumulate checksum in D
PREOUT:	LD	A,D
	ADD	A,C
	LD	D,A		; UPDATE CHECKSUM
	LD	A,C
	JP	SENDBY		; SEND RAW BYTE

;================================================
;= SNDMSG - SEND MESSAGE ON NETWORK             =
;================================================
; BC = message buffer address
; Returns: A = 0 on success, 0FFh on error
SNDMSG:	LD	A,(CFGTBL)	; CHECK NETWORK STATUS
	AND	ACTIVE
	JP	Z,SNDERR1	; NOT ACTIVE
SNDMS0:	LD	H,B
	LD	L,C		; HL = MESSAGE ADDRESS
	LD	(MSGADR),HL
	; Ensure SID is correct
	LD	A,(CFGTBL+1)
	INC	BC
	INC	BC
	LD	(BC),A		; STORE SID

RESEND:	LD	A,MAXRETRY
	LD	(RETCNT),A
SEND:	LD	HL,(MSGADR)
	; Send ENQ
	LD	A,ENQ
	CALL	SENDBY
	; Wait for ACK (with timeout retries)
	LD	D,TMRETRY
ENQRSP:	CALL	RECVBT
	JR	NC,GOTENQ
	DEC	D
	JR	NZ,ENQRSP
	JR	SNDTMO		; TIMEOUT
GOTENQ:	CALL	CHKACK
	; Send SOH + 5 header bytes + HCS
	LD	C,SOH
	LD	E,5
	CALL	MSGOUT		; SEND SOH FMT DID SID FNC SIZ
	; Send header checksum (two's complement)
	XOR	A
	SUB	D
	LD	C,A
	CALL	NETOUT		; SEND HCS
	; Wait for ACK
	CALL	GETACK
	; Send STX + data bytes + ETX + CKS + EOT
	DEC	HL		; BACK TO SIZ FIELD
	LD	E,(HL)
	INC	HL
	INC	E		; 0 MEANS 1 BYTE
	LD	C,STX
	CALL	MSGOUT		; SEND STX + DATA
	LD	C,ETX
	CALL	PREOUT		; SEND ETX (PART OF CHECKSUM)
	; Send data checksum
	XOR	A
	SUB	D
	LD	C,A
	CALL	NETOUT		; SEND CKS
	; Send EOT
	LD	A,EOT
	CALL	SENDBY
	; Wait for final ACK
	CALL	GETACK
	RET			; A=0 SUCCESS (FROM CHKACK)

; GETACK - Wait for ACK, retry on timeout or NAK
GETACK:	CALL	RECVBT
	JR	C,SNDRET	; TIMEOUT → RETRY
CHKACK:	AND	7FH
	SUB	ACK
	RET	Z		; GOT ACK, A=0
; Fall through to retry
SNDRET:	POP	HL		; DISCARD RETURN ADDRESS
	LD	HL,TX_RETRY_CNT
	INC	(HL)		; COUNT SEND-SIDE RETRANSMIT (wraps at 256)
	LD	HL,RETCNT
	DEC	(HL)
	JR	NZ,SEND		; RETRY
SNDTMO:	LD	A,SNDERR
	JP	ERRRTN

;================================================
;= RCVMSG - RECEIVE MESSAGE FROM NETWORK        =
;================================================
; BC = message buffer address
; Returns: A = 0 on success, 0FFh on error
RCVMSG:	LD	A,(CFGTBL)	; CHECK NETWORK STATUS
	AND	ACTIVE
	JP	Z,SNDERR1	; NOT ACTIVE
RCVMS0:	LD	H,B
	LD	L,C		; HL = MESSAGE ADDRESS
	LD	(MSGADR),HL

RERCV:	LD	A,MAXRETRY
	LD	(RETCNT),A
RECALL:	CALL	RECV		; ON RETURN = RECEIVE ERROR
	; Retry
	LD	HL,RX_RETRY_CNT
	INC	(HL)		; COUNT RECV-SIDE RETRANSMIT (wraps at 256)
	LD	HL,RETCNT
	DEC	(HL)
	JR	NZ,RECALL
RCVTMO:	LD	A,RCVERR
	JP	ERRRTN

RECV:	LD	HL,(MSGADR)
	; Wait for ENQ (with timeout retries)
	LD	D,TMRETRY
RCVFST:	CALL	RECVBT
	JR	NC,GOTFST
	DEC	D
	JR	NZ,RCVFST
	POP	HL		; DISCARD RECALL RETURN
	JR	RCVTMO
GOTFST:	AND	7FH
	CP	ENQ		; ENQUIRE?
	JR	NZ,RECV		; NOT ENQ, KEEP LOOKING

	; Got ENQ, send ACK
	LD	A,ACK
	CALL	SENDBY

	; Receive SOH
	CALL	RECVBY
	RET	C		; TIMEOUT → RECALL RETRY
	AND	7FH
	CP	SOH
	RET	NZ		; NOT SOH → RETRY
	LD	D,A		; INIT HCS WITH SOH

	; Receive 5 header bytes
	LD	E,5
	CALL	MSGIN
	RET	C		; TIMEOUT → RETRY

	; Receive and check HCS
	CALL	NETIN
	RET	C
	JR	NZ,BADCKS	; BAD HEADER CHECKSUM

	; Header OK, send ACK
	CALL	SNDACK

	; Receive STX
	CALL	RECVBY
	RET	C
	AND	7FH
	CP	STX
	RET	NZ		; NOT STX → RETRY
	LD	D,A		; INIT CKS WITH STX

	; Get data length from SIZ field (HL points past header)
	DEC	HL
	LD	E,(HL)
	INC	HL
	INC	E		; 0 MEANS 1 BYTE

	; Receive data bytes
	CALL	MSGIN
	RET	C

	; Receive ETX
	CALL	RECVBY
	RET	C
	AND	7FH
	CP	ETX
	RET	NZ
	ADD	A,D
	LD	D,A		; UPDATE CKS WITH ETX

	; Receive and check data checksum
	CALL	NETIN
	RET	C
	; Receive EOT
	CALL	RECVBY
	RET	C
	AND	7FH
	CP	EOT
	RET	NZ
	; Verify CKS
	LD	A,D
	OR	A
	JR	NZ,BADCKS

	; Message received OK
	POP	HL		; DISCARD RECALL RETURN
	; Check DID matches our node
	LD	HL,(MSGADR)
	INC	HL		; POINT TO DID
	LD	A,(CFGTBL+1)
	INC	A		; FF → 00 (UNINITIALIZED = ACCEPT ALL)
	JR	Z,SNDACK	; ACCEPT ANY DID DURING INIT
	DEC	A		; RESTORE VALUE
	SUB	(HL)
	JR	Z,SNDACK	; DID MATCHES, A=0
	LD	A,0FFH		; BAD DID
SNDACK:	PUSH	AF		; SAVE RETURN CODE
	LD	A,ACK
	CALL	SENDBY
	POP	AF		; RESTORE RETURN CODE
	RET

BADCKS:	LD	A,NAK
	JP	SENDBY		; SEND NAK AND RETURN TO RETRY

;================================================
;= ERROR HANDLING                                =
;================================================
ERRRTN:	LD	HL,CFGTBL
	OR	(HL)
	LD	(HL),A		; SET ERROR BIT IN STATUS
	; Report retransmit counts to console so they appear in the SIO-B
	; mirror log: "CPNET ERR T:xx R:xx\r\n"  (xx = 2-digit hex, no
	; leading zeros stripped so width is fixed and easy to grep).
	PUSH	AF
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	HL,ERRMSG
ERRMSG1: LD	C,(HL)
	INC	HL
	LD	A,C
	OR	A
	JR	Z,ERRMSG2	; END OF STRING
	CALL	B$CONOUT
	JR	ERRMSG1
ERRMSG2: ; Print TX_RETRY_CNT as two hex digits
	LD	A,(TX_RETRY_CNT)
	CALL	PRTHEX
	LD	C,' '
	CALL	B$CONOUT
	LD	C,'R'
	CALL	B$CONOUT
	LD	C,':'
	CALL	B$CONOUT
	LD	A,(RX_RETRY_CNT)
	CALL	PRTHEX
	LD	C,0DH		; CR
	CALL	B$CONOUT
	LD	C,0AH		; LF
	CALL	B$CONOUT
	POP	HL
	POP	DE
	POP	BC
	POP	AF
	CALL	NTWKER		; DEVICE RE-INIT IF NEEDED
SNDERR1:
	LD	A,0FFH
	RET

; PRTHEX — print byte in A as two uppercase hex digits via CONOUT.
; Clobbers: A, C, F.  Preserves: BC (other), DE, HL.
PRTHEX:	PUSH	BC
	LD	C,A
	RRCA
	RRCA
	RRCA
	RRCA
	AND	0FH
	ADD	A,'0'
	CP	'9'+1
	JR	C,PRTH1
	ADD	A,'A'-'0'-10
PRTH1:	CALL	B$CONOUT
	LD	A,C
	AND	0FH
	ADD	A,'0'
	CP	'9'+1
	JR	C,PRTH2
	ADD	A,'A'-'0'-10
PRTH2:	LD	C,A
	CALL	B$CONOUT
	POP	BC
	RET

; Error report prefix string (null-terminated).
ERRMSG:	DB	'C','P','N','E','T',' ','E','R','R',' ','T',':',0

;================================================
;= NTWKIN - NETWORK INITIALIZATION               =
;================================================
; CP/NET 1.2: no handshake needed.  Just drain stale bytes,
; set slave ID and ACTIVE flag.  Login is handled by NDOS (FNC=64).
; Returns: A = 0 on success
;
; Transport selection (mirrors cpnos-in-c convention -- see
; docs/SW1_BIT_MAP.md): SW1 bit 2 (S03):
;   On  (bit clear, default) -> PIO transport (Z80-PIO ch.B + IRQ-driven
;                                ring buffer; mpm-net2 cpnet_bridge)
;   Off (bit set)            -> SIO transport (existing path: BIOS PUNCH/
;                                READER on SIO Ch.A)
;
; Patches the JP-target at SENDBY / RECVBY / RECVBT in place (3-byte
; self-modifying-JP, same pattern cpnos-in-c uses with xport_send_byte).
; Once patched, every CALL SENDBY etc. tail-jumps to the chosen impl
; with zero per-call dispatch overhead.
NTWKIN:
	IN	A,(SW1)
	AND	004H		; bit 2 (S03)
	JR	NZ,NTWKIN_SIO	; bit set = SIO

	; ---- PIO mode ----------------------------------------------
	; Patch the dispatcher JPs to the PIO implementations.  Each
	; SENDBY / RECVBY / RECVBT is a `JP nn` whose nn is the 2 bytes
	; following the opcode; load the PIO impl address and store at
	; the slot's +1 offset.
	LD	HL,SENDBY_PIO
	LD	(SENDBY+1),HL
	LD	HL,RECVBY_PIO
	LD	(RECVBY+1),HL
	LD	HL,RECVBT_PIO
	LD	(RECVBT+1),HL

	; PIO-B chip init.  Mirrors cpnos's pio_b_set_input + isr_pio_par
	; arming.  rcbios's setup_ivt() seeded slot 17 with isr_pio_par
	; (a no-op stub since rcbios defaults PIO-B to OUTPUT) -- we
	; overwrite that slot with our own ISR_PIO_RX, then flip the
	; chip to Mode 1 input + IE on + mask 0 so every STB from the
	; cpnet_bridge fires an IRQ that pushes the byte into PIO_RING.
	DI			; protect IVT patch + chip-state flip
	LD	A,I		; sample current IVT page (rcbios's I)
	LD	H,A
	LD	L,IVT_PIO_B_OFF	; slot 17 byte offset
	LD	DE,ISR_PIO_RX	; relocatable (SPR loader fixes high byte)
	LD	(HL),E
	INC	HL
	LD	(HL),D

	LD	A,PIO_MODE_INPUT
	OUT	(PIO_B_CTRL),A
	LD	A,PIO_IE_ENA_RST	; ICW: enable + mask follows
	OUT	(PIO_B_CTRL),A
	LD	A,PIO_INT_MASK		; mask = 0 (all bits enabled)
	OUT	(PIO_B_CTRL),A
	LD	A,PIO_IE_ENABLE		; latch IE on
	OUT	(PIO_B_CTRL),A

	; Reset ring buffer head=tail=0 + direction state.
	XOR	A
	LD	(PIO_DIR),A	; 0 = input (we're in INPUT mode now)
	LD	(PIO_HEAD),A
	LD	(PIO_TAIL),A
	EI
	JR	NTWKD1		; common slave-id / ACTIVE bits

NTWKIN_SIO:
	; SIO mode: drain BIOS reader ring buffer of any null-modem
	; init zeros captured during boot (must happen before the
	; first protocol exchange).
NTWKDR:	CALL	B$RSTA		; reader status
	OR	A
	JR	Z,NTWKD1	; buffer empty
	CALL	B$READ		; consume and discard
	JR	NTWKDR
NTWKD1:
	; Set slave ID (must match server expectation)
	LD	A,SLAVEID
	LD	(CFGTBL+1),A
	; Mark network active
	LD	A,ACTIVE
	LD	(CFGTBL+0),A
	XOR	A
	LD	(CFGTBL+43),A	; CLEAR SIZ - DISCARD LST OUTPUT
	RET			; A=0 SUCCESS

;================================================
;= REMAINING SNIOS ENTRY POINTS                  =
;================================================

; NTWKST - Return network status
; Returns: A = status byte (errors cleared after read)
NTWKST:	LD	A,(CFGTBL+0)
	LD	B,A
	AND	NOT (RCVERR+SNDERR)
	LD	(CFGTBL+0),A	; CLEAR ERROR BITS
	LD	A,B		; RETURN ORIGINAL STATUS
	RET

; CNFTBL - Return configuration table address
; Returns: HL = CFGTBL address
CNFTBL:	LD	HL,CFGTBL
	RET

; NTWKBT - Called when CCP is reloaded from disk (warm boot)
NTWKBT:	XOR	A
	RET

; NTWKER - Network error handler (device re-init if needed)
NTWKER:	RET

; NTWKDN - Network shutdown
; Sends FNC=FEh to notify server
NTWKDN:	LD	IX,MSGBUF
	LD	(IX+0),0	; FMT = 0
	LD	(IX+3),0FEH	; FNC = 254 (SHUTDOWN)
	LD	(IX+4),0	; SIZ = 0
	LD	BC,MSGBUF
	CALL	SNDMS0		; SEND (BYPASS ACTIVE CHECK)
	XOR	A
	RET

SNIOS_END:

	END
