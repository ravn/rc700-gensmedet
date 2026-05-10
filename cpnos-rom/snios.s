; cpnos-rom SNIOS (Slave Network I/O System)
;
; Ported from cpnet/snios.asm (DRI binary serial protocol) to GNU-as
; syntax for clang integrated assembly.  Two adaptations vs the DRI
; source:
;
;  1. Character I/O goes direct to the C transport layer
;     (_transport_send_byte / _transport_recv_byte), not through
;     hardcoded BIOS READER/PUNCH/READS vectors.  There is no
;     ring-buffered BIOS reader in cpnos-rom — transport_sio.c is the
;     byte layer.
;
;  2. CFGTBL lives in cfgtbl.c (as `_cfgtbl`) — this file references it
;     via `extern`.  MSGBUF is at `_cfgtbl + 45`.  Local scratch
;     (MSGADR, RETCNT) is kept here in .resident.data.
;
; Wire protocol is unchanged:
;   Send: ENQ -> ACK -> SOH+header+HCS -> ACK -> STX+data+ETX+CKS+EOT -> ACK
;   Recv: same, inverted
;
; Transport ABI (from llvm-z80 clang, confirmed via disasm):
;   _transport_send_byte:  arg in A, clobbers A/D, returns void
;   _transport_recv_byte:  arg (timeout_ticks) in HL; returns in DE
;                          (D=0, E=byte) on success, DE=0xFFFF on timeout
;
; Jump table is exposed at `_snios_jt` (first 24 bytes of the SNIOS
; resident chunk).  NDOS reaches it via its hook into the CP/NOS cold
; boot sequence (wiring is next session's work).

; Protocol constants
    .equ SOH, 0x01
    .equ STX, 0x02
    .equ ETX, 0x03
    .equ EOT, 0x04
    .equ ENQ, 0x05
    .equ ACK, 0x06
    .equ NAK, 0x15

; Retry / timeout parameters
    .equ MAXRETRY, 10
    .equ TMRETRY,  100
    .equ RECV_TIMEOUT_TICKS, 0x8000

; Network status byte flags
    .equ ACTIVE, 0b00010000
    .equ RCVERR, 0b00000010
    .equ SNDERR, 0b00000001

; CFGTBL field offsets (must match cfgtbl.c layout)
    .equ CFG_NETST,   0
    .equ CFG_SLAVEID, 1
    .equ CFG_SIZ,     43
    .equ CFG_MSGBUF,  45

    .extern _cfgtbl
    ; SNIOS byte-level transport — single indirection through
    ; _xport_send_byte / _xport_recv_byte.  The Makefile's TRANSPORT=
    ; flag aliases these (via ld --defsym) to the chip-specific
    ; primitives:
    ;   TRANSPORT=sio      -> _transport_send_byte / _transport_recv_byte
    ;   TRANSPORT=pio-irq  -> _transport_pio_send_byte / _transport_pio_recv_byte
    ; SNIOS envelope code is unchanged across modes; only the chip
    ; ports differ (SIO 0x08/0x0A vs PIO 0x11/0x13).
    .extern _xport_send_byte
    .extern _xport_recv_byte
    ; SNDMSG / RCVMSG are defined later in this file; no externs needed.
    ; Phase 1 of #75: trivial JT bodies moved to snios_c.c.
    .extern _snios_ntwkin_impl
    .extern _snios_ntwkst_impl
    .extern _snios_cnftbl_impl
    .extern _snios_ntwker_impl
    .extern _snios_ntwkbt_impl
    ; Phase 2 of #75: NTWKDN / ERRRTN / SNDERR1 moved to snios_c.c.
    .extern _snios_ntwkdn_impl
    .extern _snios_errrtn_impl
    .extern _snios_snderr1_impl
    ; Phase 3 of #75: byte-I/O wrappers moved to snios_c.c.
    .extern _snios_sendby
    .extern _snios_recvby
    .extern _snios_recvbt
    ; Phase 4 of #75: checksum helpers moved to snios_c.c.
    ; NETOUT and PREOUT collapse into a single C function (they were
    ; alias labels at the same address in the original asm).
    .extern _snios_netout
    .extern _snios_netin
    .extern _snios_msgin
    .extern _snios_msgout

;----------------------------------------------------------------
;  SNIOS jump table  (first 24 bytes — public ABI for NDOS)
;----------------------------------------------------------------
    .section .resident.snios_jt,"ax",@progbits
    .global _snios_jt
    .global _snios_ntwkin, _snios_ntwkst, _snios_cnftbl
    .global _snios_sndmsg, _snios_rcvmsg
    .global _snios_ntwker, _snios_ntwkbt, _snios_ntwkdn

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
    .section .resident.snios,"ax",@progbits

;----------------------------------------------------------------
;  C-callable wrappers.
;
;  The SNIOS jump table is the DRI ABI — NDOS passes the message
;  buffer pointer in BC.  cpnos-rom C code uses sdcccall(1), which
;  passes the first 16-bit arg in HL.  These wrappers bridge the
;  two conventions without disturbing the DRI-facing entries.
;----------------------------------------------------------------
    .global _snios_sndmsg_c
_snios_sndmsg_c:
    ld   b, h
    ld   c, l
    jp   SNDMSG

    .global _snios_rcvmsg_c
_snios_rcvmsg_c:
    ld   b, h
    ld   c, l
    jp   RCVMSG

;----------------------------------------------------------------
;  jt dispatch trampolines.  NDOS reaches the SNDMSG/RCVMSG slots
;  through the resident jt copy at 0xEA00 with msg pointer in BC.
;  SNDMSG / RCVMSG (defined above) take the pointer in BC already,
;  so the trampolines are pure tail-calls -- no register juggling
;  and no detour through a C-side vtable dispatcher.
;----------------------------------------------------------------
SNDMSG_DISPATCH:
    jp   SNDMSG

RCVMSG_DISPATCH:
    jp   RCVMSG

; SENDBY / RECVBY / RECVBT moved to snios_c.c (Phase 3 of #75).
; Asm callers below now `call _snios_sendby` etc.

; NETOUT / PREOUT / NETIN / MSGIN / MSGOUT moved to snios_c.c (Phase 4 of #75).
; Asm callers below now `call _snios_netout` (NETOUT/PREOUT collapsed into one
; C function -- they were alias labels at the same asm address), `call
; _snios_netin`, `call _snios_msgin`, `call _snios_msgout`.

;================================================
;= SNDMSG - SEND MESSAGE ON NETWORK             =
;================================================
; BC = message buffer address
; Returns: A = 0 on success, 0xFF on error
SNDMSG:
    ld   a, (_cfgtbl + CFG_NETST)
    and  ACTIVE
    jp   z, _snios_snderr1_impl     ; not active
SNDMS0:
    ld   h, b
    ld   l, c
    ld   (MSGADR), hl
    ; Ensure SID is correct
    ld   a, (_cfgtbl + CFG_SLAVEID)
    inc  bc
    inc  bc
    ld   (bc), a                    ; store SID in msg[2]

RESEND:
    ld   a, MAXRETRY
    ld   (RETCNT), a
SEND:
    ld   hl, (MSGADR)
    ; Send ENQ
    ld   a, ENQ
    call _snios_sendby
    ; Wait for ACK (with timeout retries)
    ld   d, TMRETRY
ENQRSP:
    call _snios_recvbt
    jr   nc, GOTENQ
    dec  d
    jr   nz, ENQRSP
    jr   SNDTMO
GOTENQ:
    call CHKACK
    ; Send SOH + 5 header bytes + HCS
    ld   c, SOH
    ld   e, 5
    call _snios_msgout                     ; SOH FMT DID SID FNC SIZ
    ; Send header checksum (two's complement of running sum)
    xor  a
    sub  d
    ld   c, a
    call _snios_netout
    ; Wait for ACK
    call GETACK
    ; Send STX + data bytes + ETX + CKS + EOT
    dec  hl                         ; back to SIZ field
    ld   e, (hl)
    inc  hl
    inc  e                          ; 0 means 1 byte
    ld   c, STX
    call _snios_msgout
    ld   c, ETX
    call _snios_netout                     ; ETX is part of checksum
    xor  a
    sub  d
    ld   c, a
    call _snios_netout                     ; CKS
    ld   a, EOT
    call _snios_sendby
    jp   GETACK                     ; tail-call, A=0 success (from CHKACK)

; GETACK - Wait for ACK, retry on timeout or NAK.
GETACK:
    call _snios_recvbt
    jr   c, SNDRET                  ; timeout -> retry
CHKACK:
    and  0x7F
    sub  ACK
    ret  z                          ; got ACK, A=0
; Fall through to retry
SNDRET:
    pop  hl                         ; discard return address
    ld   hl, RETCNT
    dec  (hl)
    jr   nz, SEND
SNDTMO:
    ld   a, SNDERR
    jp   _snios_errrtn_impl

;================================================
;= RCVMSG - RECEIVE MESSAGE FROM NETWORK        =
;================================================
; BC = message buffer address
; Returns: A = 0 on success, 0xFF on error
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
    ; Wait for ENQ (with timeout retries)
    ld   d, TMRETRY
RCVFST:
    call _snios_recvbt
    jr   nc, GOTFST
    dec  d
    jr   nz, RCVFST
    pop  hl                         ; discard RECALL return
    jr   RCVTMO
GOTFST:
    and  0x7F
    cp   ENQ
    jr   nz, RECV                   ; not ENQ, keep looking

    ; Got ENQ, send ACK
    ld   a, ACK
    call _snios_sendby

    ; Receive SOH
    call _snios_recvby
    ret  c
    and  0x7F
    cp   SOH
    ret  nz                         ; not SOH -> retry
    ld   d, a                       ; init HCS with SOH

    ; Receive 5 header bytes
    ld   e, 5
    call _snios_msgin
    ret  c

    ; Receive and check HCS
    call _snios_netin
    ret  c
    jr   nz, BADCKS

    ; Header OK, send ACK
    call SNDACK

    ; Receive STX
    call _snios_recvby
    ret  c
    and  0x7F
    cp   STX
    ret  nz
    ld   d, a                       ; init CKS with STX

    ; Get data length from SIZ field (HL points past header)
    dec  hl
    ld   e, (hl)
    inc  hl
    inc  e                          ; 0 means 1 byte

    ; Receive data bytes
    call _snios_msgin
    ret  c

    ; Receive ETX
    call _snios_recvby
    ret  c
    and  0x7F
    cp   ETX
    ret  nz
    add  a, d
    ld   d, a                       ; fold ETX into CKS

    ; Receive and check data checksum
    call _snios_netin
    ret  c
    ; Receive EOT
    call _snios_recvby
    ret  c
    and  0x7F
    cp   EOT
    ret  nz
    ld   a, d
    or   a
    jr   nz, BADCKS

    ; Message received OK
    pop  hl                         ; discard RECALL return
    ; Check DID matches our node
    ld   hl, (MSGADR)
    inc  hl                         ; -> DID
    ld   a, (_cfgtbl + CFG_SLAVEID)
    inc  a                          ; 0xFF -> 0 (accept any during init)
    jr   z, SNDACK
    dec  a
    sub  (hl)
    jr   z, SNDACK                  ; DID matches, A=0
    ld   a, 0xFF                    ; bad DID
SNDACK:
    push af
    ld   a, ACK
    call _snios_sendby
    pop  af
    ret

BADCKS:
    ld   a, NAK
    jp   _snios_sendby              ; send NAK and return to retry

; ERRRTN / SNDERR1 / NTWKDN moved to snios_c.c (Phase 2 of #75).
; NTWKIN / NTWKST / CNFTBL / NTWKER / NTWKBT moved to snios_c.c (Phase 1 of #75).

;================================================
;= _snios_sndmsg_force - C-callable bridge to    =
;= SNDMS0 (SNDMSG entry that bypasses the        =
;= cfgtbl.netst.ACTIVE check).  HL = msg ptr     =
;= per sdcccall(1); copies into BC for SNDMS0.   =
;================================================
    .global _snios_sndmsg_force
_snios_sndmsg_force:
    ld   b, h
    ld   c, l
    jp   SNDMS0

;----------------------------------------------------------------
;  Local scratch — lives in .resident.data so it is 0-initialised
;  at LMA time and becomes RAM at VMA.
;----------------------------------------------------------------
    .section .resident.data,"aw",@progbits
MSGADR: .2byte 0
RETCNT: .byte 0
