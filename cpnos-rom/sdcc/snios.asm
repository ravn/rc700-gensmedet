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
    ; Phase 1 of #75: trivial JT bodies moved to snios_c.c.
    EXTERN _snios_ntwkin_impl
    EXTERN _snios_ntwkst_impl
    EXTERN _snios_cnftbl_impl
    EXTERN _snios_ntwker_impl
    EXTERN _snios_ntwkbt_impl
    ; Phase 2 of #75: NTWKDN / ERRRTN / SNDERR1 moved to snios_c.c.
    EXTERN _snios_ntwkdn_impl
    EXTERN _snios_errrtn_impl
    EXTERN _snios_snderr1_impl
    ; Phase 3 of #75: byte-I/O wrappers moved to snios_c.c.
    EXTERN _snios_sendby
    EXTERN _snios_recvby
    EXTERN _snios_recvbt
    ; Phase 4 of #75: checksum helpers moved to snios_c.c.
    ; NETOUT/PREOUT collapsed into a single C function.
    EXTERN _snios_netout
    EXTERN _snios_netin
    EXTERN _snios_msgin
    EXTERN _snios_msgout

;----------------------------------------------------------------
;  SNIOS jump table  (first 24 bytes — public ABI for NDOS)
;----------------------------------------------------------------
    SECTION RESIDENT_SNIOS_JT
    PUBLIC _snios_jt
    PUBLIC _snios_ntwkin, _snios_ntwkst, _snios_cnftbl
    PUBLIC _snios_sndmsg, _snios_rcvmsg
    PUBLIC _snios_ntwker, _snios_ntwkbt, _snios_ntwkdn

; JT entries route through wrappers when MIRROR_SIOB build instruments
; them.  The JT layout (3 bytes/entry, +0/+3/+6/+9/+0C/+0F/+12/+15)
; is fixed by the NDOS ABI -- can only put `jp X` here.
_snios_jt:
_snios_ntwkin:  jp _snios_ntwkin_impl ; +00 NETWORK INITIALIZATION
_snios_ntwkst:  jp _snios_ntwkst_impl ; +03 NETWORK STATUS
_snios_cnftbl:  jp _snios_cnftbl_impl ; +06 RETURN CONFIG TABLE ADDRESS
_snios_sndmsg:  jp SNDMSG_DISPATCH    ; +09 SEND MESSAGE ON NETWORK
_snios_rcvmsg:  jp RCVMSG_DISPATCH    ; +0C RECEIVE MESSAGE FROM NETWORK
_snios_ntwker:  jp _snios_ntwker_impl ; +0F NETWORK ERROR
_snios_ntwkbt:  jp _snios_ntwkbt_impl ; +12 NETWORK WARM BOOT
_snios_ntwkdn:  jp _snios_ntwkdn_impl ; +15 NETWORK SHUTDOWN

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

; (NTWKIN_W instrumentation wrapper removed in Phase 51A.3 -- issue
;  #60 closed.  -18 B RESIDENT_SNIOS.  bios_log_byte / bios_log_buf
;  in resident.c are kept for now; removing them triggers a yet-
;  unidentified slave warm-boot loop -- see ravn/rc700-gensmedet#72.)

; SENDBY / RECVBY / RECVBT moved to snios_c.c (Phase 3 of #75).
; Asm callers below now `call _snios_sendby` etc.

; NETOUT / PREOUT / NETIN / MSGIN / MSGOUT moved to snios_c.c (Phase 4 of #75).
; Asm callers below now `call _snios_netout` (NETOUT/PREOUT collapsed),
; `call _snios_netin`, `call _snios_msgin`, `call _snios_msgout`.

;================================================
;= SNDMSG - SEND MESSAGE ON NETWORK             =
;================================================
SNDMSG:
    ld   a, (_cfgtbl + CFG_NETST)
    and  ACTIVE
    jp   z, _snios_snderr1_impl
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
    call _snios_sendby
    ld   d, TMRETRY
ENQRSP:
    call _snios_recvbt
    jr   nc, GOTENQ
    dec  d
    jr   nz, ENQRSP
    jr   SNDTMO
GOTENQ:
    call CHKACK
    ld   c, SOH
    ld   e, 5
    call _snios_msgout
    xor  a
    sub  d
    ld   c, a
    call _snios_netout
    call GETACK
    dec  hl
    ld   e, (hl)
    inc  hl
    inc  e
    ld   c, STX
    call _snios_msgout
    ld   c, ETX
    call _snios_netout
    xor  a
    sub  d
    ld   c, a
    call _snios_netout
    ld   a, EOT
    call _snios_sendby
    jp   GETACK

GETACK:
    call _snios_recvbt
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
    jp   _snios_errrtn_impl

;================================================
;= RCVMSG - RECEIVE MESSAGE FROM NETWORK        =
;================================================
RCVMSG:
    ld   a, (_cfgtbl + CFG_NETST)
    and  ACTIVE
    jp   z, _snios_snderr1_impl
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
    jp   _snios_errrtn_impl

RECV:
    ld   hl, (MSGADR)
    ld   d, TMRETRY
RCVFST:
    call _snios_recvbt
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
    call _snios_sendby

    call _snios_recvby
    ret  c
    and  0x7F
    cp   SOH
    ret  nz
    ld   d, a

    ld   e, 5
    call _snios_msgin
    ret  c

    call _snios_netin
    ret  c
    jr   nz, BADCKS

    call SNDACK

    call _snios_recvby
    ret  c
    and  0x7F
    cp   STX
    ret  nz
    ld   d, a

    dec  hl
    ld   e, (hl)
    inc  hl
    inc  e

    call _snios_msgin
    ret  c

    call _snios_recvby
    ret  c
    and  0x7F
    cp   ETX
    ret  nz
    add  a, d
    ld   d, a

    call _snios_netin
    ret  c
    call _snios_recvby
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
    call _snios_sendby
    pop  af
    ret

BADCKS:
    ld   a, NAK
    jp   _snios_sendby

; ERRRTN / SNDERR1 / NTWKDN moved to snios_c.c (Phase 2 of #75).
; NTWKIN / NTWKST / CNFTBL / NTWKER / NTWKBT moved to snios_c.c (Phase 1 of #75).

;================================================
;= _snios_sndmsg_force - C-callable bridge to    =
;= SNDMS0 (SNDMSG entry that bypasses the        =
;= cfgtbl.netst.ACTIVE check).  HL = msg ptr     =
;= per sdcccall(1); copies into BC for SNDMS0.   =
;================================================
    PUBLIC _snios_sndmsg_force
_snios_sndmsg_force:
    ld   b, h
    ld   c, l
    jp   SNDMS0

;----------------------------------------------------------------
;  Local scratch — uninitialised, written before every read inside
;  every entry point in this file.  Moved out of RESIDENT_DATA into
;  bss_compiler 2026-05-08 so the 3 zero bytes don't burn PROM space
;  -- BSS-clear zeroes them anyway, and resident was at the F7FF cap.
;----------------------------------------------------------------
    SECTION bss_compiler
MSGADR: defs 2
RETCNT: defs 1
