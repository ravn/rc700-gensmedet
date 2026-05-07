; cpnos-rom SNIOS (Slave Network I/O System) — z88dk SDCC port of snios.s.
;
; Mechanical port from clang GAS syntax to z88dk z80asm syntax.
; Wire protocol and register conventions are unchanged.  Sections are
; renamed to match cpnos-rom/sdcc/sections.asm:
;   .resident.snios_jt -> RESIDENT_SNIOS_JT
;   .resident.snios    -> RESIDENT_SNIOS
;   .resident.data     -> RESIDENT_DATA
;
; Wire protocol:
;   Send: ENQ -> ACK -> SOH+header+HCS -> ACK -> STX+data+ETX+CKS+EOT -> ACK
;   Recv: same, inverted
;
; Transport ABI:
;   _xport_send_byte:  arg in A, clobbers A/D, returns void
;   _xport_recv_byte:  arg (timeout_ticks) in HL; returns DE
;                      (D=0, E=byte) on success, DE=0xFFFF on timeout

; Protocol constants
defc SOH = 0x01
defc STX = 0x02
defc ETX = 0x03
defc EOT = 0x04
defc ENQ = 0x05
defc ACK = 0x06
defc NAK = 0x15

; Retry / timeout parameters
defc MAXRETRY = 10
defc TMRETRY  = 100
defc RECV_TIMEOUT_TICKS = 0x8000

; Network status byte flags (binary equivalents in hex)
defc ACTIVE = 0x10                  ; 0b00010000
defc RCVERR = 0x02                  ; 0b00000010
defc SNDERR = 0x01                  ; 0b00000001

; CFGTBL field offsets (must match cfgtbl.c layout)
defc CFG_NETST   = 0
defc CFG_SLAVEID = 1
defc CFG_SIZ     = 43
defc CFG_MSGBUF  = 45

    EXTERN _cfgtbl
    EXTERN _xport_send_byte
    EXTERN _xport_recv_byte

;----------------------------------------------------------------
;  SNIOS jump table  (first 24 bytes — public ABI for NDOS)
;----------------------------------------------------------------
    SECTION RESIDENT_SNIOS_JT
    PUBLIC _snios_jt
    PUBLIC _snios_ntwkin, _snios_ntwkst, _snios_cnftbl
    PUBLIC _snios_sndmsg, _snios_rcvmsg
    PUBLIC _snios_ntwker, _snios_ntwkbt, _snios_ntwkdn

_snios_jt:
_snios_ntwkin:  jp NTWKIN          ; +00 NETWORK INITIALIZATION
_snios_ntwkst:  jp NTWKST          ; +03 NETWORK STATUS
_snios_cnftbl:  jp CNFTBL          ; +06 RETURN CONFIG TABLE ADDRESS
_snios_sndmsg:  jp SNDMSG_DISPATCH ; +09 SEND MESSAGE ON NETWORK
_snios_rcvmsg:  jp RCVMSG_DISPATCH ; +0C RECEIVE MESSAGE FROM NETWORK
_snios_ntwker:  jp NTWKER          ; +0F NETWORK ERROR
_snios_ntwkbt:  jp NTWKBT          ; +12 NETWORK WARM BOOT
_snios_ntwkdn:  jp NTWKDN          ; +15 NETWORK SHUTDOWN

;----------------------------------------------------------------
;  SNIOS body
;----------------------------------------------------------------
    SECTION RESIDENT_SNIOS

    PUBLIC _snios_sndmsg_c
_snios_sndmsg_c:
    ld   b, h
    ld   c, l
    jp   SNDMSG

    PUBLIC _snios_rcvmsg_c
_snios_rcvmsg_c:
    ld   b, h
    ld   c, l
    jp   RCVMSG

SNDMSG_DISPATCH:
    jp   SNDMSG

RCVMSG_DISPATCH:
    jp   RCVMSG

;================================================
;= CHARACTER I/O WRAPPERS                       =
;================================================
SENDBY:
    push hl
    push de
    call _xport_send_byte
    pop  de
    pop  hl
    ret

RECVBY:
    push hl
    push de
RECVBY1:
    ld   hl, 0xFFFF
    call _xport_recv_byte
    ld   a, d
    inc  a
    jr   z, RECVBY1
    ld   a, e
    pop  de
    pop  hl
    or   a
    ret

RECVBT:
    push de
    push hl
    ld   hl, RECV_TIMEOUT_TICKS
    call _xport_recv_byte
    ld   a, d
    inc  a
    ld   a, e
    pop  hl
    pop  de
    scf
    ret  z
    or   a
    ret

;================================================
;= CHECKSUM UTILITIES                           =
;================================================
NETOUT:
PREOUT:
    ld   a, d
    add  a, c
    ld   d, a
    ld   a, c
    jp   SENDBY

NETIN:
    call RECVBY
    ld   b, a
    add  a, d
    ld   d, a
    or   a
    ld   a, b
    ret

MSGIN:
    call NETIN
    ret  c
    ld   (hl), a
    inc  hl
    dec  e
    jr   nz, MSGIN
    ret

MSGOUT:
    ld   d, 0
    call PREOUT
MSOLP:
    ld   c, (hl)
    inc  hl
    call NETOUT
    dec  e
    jr   nz, MSOLP
    ret

;================================================
;= SNDMSG - SEND MESSAGE ON NETWORK             =
;================================================
SNDMSG:
    ld   a, (_cfgtbl + CFG_NETST)
    and  ACTIVE
    jp   z, SNDERR1
SNDMS0:
    ld   h, b
    ld   l, c
    ld   (MSGADR), hl
    ld   a, (_cfgtbl + CFG_SLAVEID)
    inc  bc
    inc  bc
    ld   (bc), a

RESEND:
    ld   a, MAXRETRY
    ld   (RETCNT), a
SEND:
    ld   hl, (MSGADR)
    ld   a, ENQ
    call SENDBY
    ld   d, TMRETRY
ENQRSP:
    call RECVBT
    jr   nc, GOTENQ
    dec  d
    jr   nz, ENQRSP
    jr   SNDTMO
GOTENQ:
    call CHKACK
    ld   c, SOH
    ld   e, 5
    call MSGOUT
    xor  a
    sub  d
    ld   c, a
    call NETOUT
    call GETACK
    dec  hl
    ld   e, (hl)
    inc  hl
    inc  e
    ld   c, STX
    call MSGOUT
    ld   c, ETX
    call PREOUT
    xor  a
    sub  d
    ld   c, a
    call NETOUT
    ld   a, EOT
    call SENDBY
    jp   GETACK

GETACK:
    call RECVBT
    jr   c, SNDRET
CHKACK:
    and  0x7F
    sub  ACK
    ret  z
SNDRET:
    pop  hl
    ld   hl, RETCNT
    dec  (hl)
    jr   nz, SEND
SNDTMO:
    ld   a, SNDERR
    jp   ERRRTN

;================================================
;= RCVMSG - RECEIVE MESSAGE FROM NETWORK        =
;================================================
RCVMSG:
    ld   a, (_cfgtbl + CFG_NETST)
    and  ACTIVE
    jp   z, SNDERR1
RCVMS0:
    ld   h, b
    ld   l, c
    ld   (MSGADR), hl

RERCV:
    ld   a, MAXRETRY
    ld   (RETCNT), a
RECALL:
    call RECV
    ld   hl, RETCNT
    dec  (hl)
    jr   nz, RECALL
RCVTMO:
    ld   a, RCVERR
    jp   ERRRTN

RECV:
    ld   hl, (MSGADR)
    ld   d, TMRETRY
RCVFST:
    call RECVBT
    jr   nc, GOTFST
    dec  d
    jr   nz, RCVFST
    pop  hl
    jr   RCVTMO
GOTFST:
    and  0x7F
    cp   ENQ
    jr   nz, RECV

    ld   a, ACK
    call SENDBY

    call RECVBY
    ret  c
    and  0x7F
    cp   SOH
    ret  nz
    ld   d, a

    ld   e, 5
    call MSGIN
    ret  c

    call NETIN
    ret  c
    jr   nz, BADCKS

    call SNDACK

    call RECVBY
    ret  c
    and  0x7F
    cp   STX
    ret  nz
    ld   d, a

    dec  hl
    ld   e, (hl)
    inc  hl
    inc  e

    call MSGIN
    ret  c

    call RECVBY
    ret  c
    and  0x7F
    cp   ETX
    ret  nz
    add  a, d
    ld   d, a

    call NETIN
    ret  c
    call RECVBY
    ret  c
    and  0x7F
    cp   EOT
    ret  nz
    ld   a, d
    or   a
    jr   nz, BADCKS

    pop  hl
    ld   hl, (MSGADR)
    inc  hl
    ld   a, (_cfgtbl + CFG_SLAVEID)
    inc  a
    jr   z, SNDACK
    dec  a
    sub  (hl)
    jr   z, SNDACK
    ld   a, 0xFF
SNDACK:
    push af
    ld   a, ACK
    call SENDBY
    pop  af
    ret

BADCKS:
    ld   a, NAK
    jp   SENDBY

;================================================
;= ERROR HANDLING                                =
;================================================
ERRRTN:
    ld   hl, _cfgtbl + CFG_NETST
    or   (hl)
    ld   (hl), a
    call NTWKER
SNDERR1:
    ld   a, 0xFF
    ret

;================================================
;= NTWKIN - NETWORK INITIALIZATION               =
;================================================
NTWKIN:
    ld   a, ACTIVE
    ld   (_cfgtbl + CFG_NETST), a
    xor  a
    ld   (_cfgtbl + CFG_SIZ), a
    ret

;================================================
;= Remaining entry points                        =
;================================================
NTWKST:
    ld   a, (_cfgtbl + CFG_NETST)
    ld   b, a
    and  0xFF - (RCVERR | SNDERR)
    ld   (_cfgtbl + CFG_NETST), a
    ld   a, b
    ret

CNFTBL:
    ld   hl, _cfgtbl
    ret

NTWKER:
    ret

NTWKBT:
    xor  a
    ret

NTWKDN:
    ld   ix, _cfgtbl + CFG_MSGBUF
    ld   (ix+0), 0
    ld   (ix+3), 0xFE
    ld   (ix+4), 0
    ld   bc, _cfgtbl + CFG_MSGBUF
    call SNDMS0
    xor  a
    ret

;----------------------------------------------------------------
;  C-ABI trampoline: `void jump_to(uint16_t addr)` — tail-calls
;  through HL (sdcccall(1) first 16-bit arg).
;----------------------------------------------------------------
    PUBLIC _jump_to
_jump_to:
    jp   (hl)

;----------------------------------------------------------------
;  Local scratch — lives in RESIDENT_DATA.
;----------------------------------------------------------------
    SECTION RESIDENT_DATA
MSGADR: defw 0
RETCNT: defb 0
