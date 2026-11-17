; RC702 CP/NET SNIOS (Slave Network I/O System)
; DRI binary serial protocol over SIO (BIOS) or PIO-B (direct hardware)
;
; Implements the standard DRI CP/NET serial framing:
;   Send: ENQ → ACK → SOH+header+HCS → ACK → STX+data+ETX+CKS+EOT → ACK
;   Recv: ENQ → ACK → SOH+header+HCS → ACK → STX+data+ETX+CKS+EOT → ACK
;
; Supports two dedicated transport variants, selected at assembly time:
;   - TRANSPORT_SIO: uses BIOS READER/PUNCH/READS (SIO Ch. A). Zero buffer in SNIOS.
;   - TRANSPORT_PIO: uses Z80-PIO Ch. B + IRQ ring buffer (64 bytes).
;
; Assembled at ORG 0000h for SPR relocation.
; build_snios.py assembles twice and generates the relocation bitmap.
;

	.Z80

CR	EQU	0DH
LF	EQU	0AH

; BIOS entry points (56K system, BIOS base = DA00h)
B$CONOUT EQU	0DA0CH		; BIOS CONOUT (send char in C to console)

	IFDEF	TRANSPORT_SIO
B$PUNCH	EQU	0DA12H		; BIOS PUNCH (send byte in C via SIO Ch.A)
B$READ	EQU	0DA15H		; BIOS READER (receive byte from SIO Ch.A)
B$RSTA	EQU	0DA4DH		; BIOS READS (reader status, 0=not ready)
	ELSE
; RC702 ports — used by PIO transport.
; Mirrors cpnos-in-c/src/transport_pio.c.
PIO_B_DATA	EQU	011H	; PIO ch.B data register
PIO_B_CTRL	EQU	013H	; PIO ch.B control register

; PIO mode-control byte values
PIO_MODE_OUTPUT	EQU	00FH	; Mode 0 (output)
PIO_MODE_INPUT	EQU	04FH	; Mode 1 (input)
PIO_IE_DISABLE	EQU	003H	; interrupt-enable FF: bit7=0 → off
PIO_IE_ENABLE	EQU	083H	; interrupt-enable FF: bit7=1 → on
PIO_IE_ENA_RST	EQU	097H	; ICW: enable + mask byte follows
PIO_INT_MASK	EQU	000H	; mask = 0 → all bits enabled

; IVT slot 17 (PIO-B IRQ) — rcbios's setup_ivt() seeds this with isr_pio_par
IVT_PIO_B_OFF	EQU	022H	; 17 × 2 = 0x22
	ENDIF

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

	IFNDEF	TRANSPORT_SIO
; PIO transport state (NTWKIN initializes).
PIO_DIR:	DS	1	; 0 = input, 1 = output (PIO-B mode flip)
PIO_HEAD:	DS	1	; ISR_PIO_RX write head into PIO_RING
PIO_TAIL:	DS	1	; RECVBY_PIO read tail
PIO_RING:	DS	64	; 64-byte SPSC ring; head/tail wrap mod 64 (AND 3FH)
	ENDIF

; Retransmit counters — wrapping uint8; zeroed by CP/NET loader on cold start.
TX_RETRY_CNT:	DS	1	; increments at SNDRET (send-side retransmit)
RX_RETRY_CNT:	DS	1	; increments at RECALL retry (recv-side retransmit)

;================================================
;= CHARACTER I/O IMPLEMENTATIONS                =
;================================================
; Preservation contract: callers may clobber A and flags, but expect
; HL and DE preserved across byte I/O calls.

	IFDEF	TRANSPORT_SIO

; SENDBY - Send byte in A via BIOS PUNCH.
; Preserves: HL, DE
SENDBY:
	PUSH	HL
	PUSH	DE
	LD	C,A
	CALL	B$PUNCH		; BIOS PUNCH waits for TX ready
	POP	DE
	POP	HL
	RET

; RECVBY - Receive one byte (busy wait, no timeout)
; Returns: A = byte, CY clear
; Preserves: HL, DE
RECVBY:
	PUSH	HL
	PUSH	DE
RCVBY1:	CALL	B$RSTA		; BIOS READER STATUS
	OR	A
	JR	Z,RCVBY1
	CALL	B$READ		; read byte from BIOS ring buffer
	POP	DE
	POP	HL
	OR	A		; clear carry
	RET

; RECVBT - Receive one byte with timeout
; Returns: A = byte, CY clear on success; CY set on timeout
RECVBT:
	PUSH	DE
	PUSH	HL
	LD	HL,8000H	; timeout counter
RCVWT1:	CALL	B$RSTA		; BIOS READER STATUS
	OR	A
	JR	NZ,RCVWT3	; data available
	DEC	HL
	LD	A,H
	OR	L
	JR	NZ,RCVWT1	; keep polling
	; Timeout expired
	POP	HL
	POP	DE
	SCF			; signal timeout
	RET
RCVWT3:	CALL	B$READ		; read byte from BIOS ring buffer
	POP	HL
	POP	DE
	OR	A		; clear carry (success)
	RET

	ELSE

; SENDBY - Send byte in A out PIO-B.
; Preserves: HL, DE
SENDBY:
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

; RECVBY - Receive one byte with timeout (same as RECVBT to avoid hanging).
RECVBY:
	JP	RECVBT

; RECVBT - Receive one byte with timeout from PIO_RING.
; Returns: A = byte, CY clear on success; CY set on timeout
RECVBT:
	PUSH	DE
	PUSH	HL
	CALL	PIO_TO_INPUT
	LD	HL,8000H	; timeout counter
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
	; Ring has data; read at tail, advance tail mod 64.
	LD	HL,PIO_RING
	LD	D,0
	LD	E,A		; A = PIO_TAIL value
	ADD	HL,DE
	LD	A,(HL)
	INC	E
	LD	A,E
	AND	3FH		; wrap mod 64
	LD	(PIO_TAIL),A
	LD	A,(HL)		; reload data byte
	POP	HL
	POP	DE
	OR	A		; clear carry (success)
	RET

; PIO_TO_INPUT - Switch PIO-B back to Mode 1 input if currently in output mode.
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

; ISR_PIO_RX - PIO-B IRQ handler.
; Reads one byte from PIO_B_DATA, pushes into PIO_RING mod 64.
ISR_PIO_RX:
	PUSH	AF
	PUSH	BC
	PUSH	DE
	PUSH	HL
	IN	A,(PIO_B_DATA)	; A = arrived byte
	LD	C,A		; stash data while computing address
	LD	A,(PIO_HEAD)
	LD	E,A
	INC	A
	AND	3FH		; advance head mod 64
	LD	(PIO_HEAD),A
	LD	D,0
	LD	HL,PIO_RING
	ADD	HL,DE		; HL = PIO_RING + old head
	LD	(HL),C		; store data byte
	POP	HL
	POP	DE
	POP	BC
	POP	AF
	EI
	RETI

	ENDIF

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
	CALL	NTWKER		; DEVICE RE-INIT IF NEEDED
SNDERR1:
	LD	A,0FFH
	RET

;================================================
;= NTWKIN - NETWORK INITIALIZATION               =
;================================================
NTWKIN:
	; 1. Print startup banner to console
	LD	HL,BANNER_STR
NTWK_BP:
	LD	A,(HL)
	INC	HL
	OR	A
	JR	Z,NTWK_BD
	LD	C,A
	PUSH	HL
	CALL	B$CONOUT
	POP	HL
	JR	NTWK_BP
NTWK_BD:

	IFDEF	TRANSPORT_SIO
	; SIO mode: drain BIOS reader ring buffer of any stale bytes
NTWKDR:	CALL	B$RSTA
	OR	A
	JR	Z,NTWKD1
	CALL	B$READ
	JR	NTWKDR
	ELSE
	; PIO mode: patch IVT slot 17 and configure PIO-B chip
	DI
	LD	A,I
	LD	H,A
	LD	L,IVT_PIO_B_OFF
	LD	DE,ISR_PIO_RX
	LD	(HL),E
	INC	HL
	LD	(HL),D

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
	LD	(PIO_HEAD),A
	LD	(PIO_TAIL),A
	EI
	ENDIF

NTWKD1:
	; Set slave ID and mark network active
	LD	A,SLAVEID
	LD	(CFGTBL+1),A
	LD	A,ACTIVE
	LD	(CFGTBL+0),A
	XOR	A
	LD	(CFGTBL+43),A	; CLEAR SIZ - DISCARD LST OUTPUT
	RET			; A=0 SUCCESS

;================================================
;= REMAINING SNIOS ENTRY POINTS                  =
;================================================

; NTWKST - Return network status
NTWKST:	LD	A,(CFGTBL+0)
	LD	B,A
	AND	NOT (RCVERR+SNDERR)
	LD	(CFGTBL+0),A	; CLEAR ERROR BITS
	LD	A,B		; RETURN ORIGINAL STATUS
	RET

; CNFTBL - Return configuration table address
CNFTBL:	LD	HL,CFGTBL
	RET

; NTWKBT - Called when CCP is reloaded from disk (warm boot)
NTWKBT:	XOR	A
	RET

; NTWKER - Network error handler
NTWKER:	RET

; NTWKDN - Network shutdown (FNC=FEh)
NTWKDN:	XOR	A
	LD	(MSGBUF),A	; FMT = 0
	LD	(MSGBUF+4),A	; SIZ = 0
	LD	A,0FEH		; FNC = 254 (SHUTDOWN)
	LD	(MSGBUF+3),A
	LD	BC,MSGBUF
	CALL	SNDMS0		; SEND (BYPASS ACTIVE CHECK)
	XOR	A
	RET

;================================================
;= BANNER DEFINITION                             =
;================================================
BANNER_STR:
	DB	CR,LF,'RC702 SNIOS ('
	IFDEF	TRANSPORT_SIO
	DB	'SIO) '
	ELSE
	DB	'PIO) '
	ENDIF
	INCLUDE	'buildinfo.inc'
	DB	CR,LF,0

SNIOS_END:

	END
