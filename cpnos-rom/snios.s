; cpnos-rom SNIOS — JT trampoline only.
;
; The full SNIOS body (NTWKIN/NTWKST/CNFTBL/NTWKER/NTWKBT/NTWKDN/
; ERRRTN/SNDERR1, SENDBY/RECVBY/RECVBT, NETOUT/NETIN/MSGIN/MSGOUT,
; SNDMSG/RCVMSG state machines and helpers) is in snios_c.c (#75
; Phases 1-6).  This file only holds:
;
;   1. The 24-byte SNIOS jump table at the JT slot, with each entry
;      a 3-byte `jp` to the C implementation.  ABI-fixed by NDOS.
;   2. Two BC->HL calling-convention bridges for the SNDMSG/RCVMSG
;      JT entries.  NDOS calls SNDMSG/RCVMSG with msg ptr in BC;
;      sdcccall(1) C functions take it in HL.

    .extern _cfgtbl
    .extern _snios_ntwkin_impl
    .extern _snios_ntwkst_impl
    .extern _snios_cnftbl_impl
    .extern _snios_ntwker_impl
    .extern _snios_ntwkbt_impl
    .extern _snios_ntwkdn_impl
    .extern _snios_sndmsg_c
    .extern _snios_rcvmsg_c

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
_snios_sndmsg:  jp _snios_sndmsg_jt   ; +09 SEND MESSAGE ON NETWORK
_snios_rcvmsg:  jp _snios_rcvmsg_jt   ; +0C RECEIVE MESSAGE FROM NETWORK
_snios_ntwker:  jp _snios_ntwker_impl ; +0F NETWORK ERROR
_snios_ntwkbt:  jp _snios_ntwkbt_impl ; +12 NETWORK WARM BOOT
_snios_ntwkdn:  jp _snios_ntwkdn_impl ; +15 NETWORK SHUTDOWN

;----------------------------------------------------------------
;  BC -> HL calling-convention bridges for SNDMSG / RCVMSG.
;
;  NDOS reaches these via `_snios_jt + 9` / `+12` with the message
;  buffer pointer in BC.  The C implementations take the pointer
;  in HL (sdcccall(1)).  4 bytes per bridge: ld h,b; ld l,c; jp X.
;----------------------------------------------------------------
    .section .resident.snios,"ax",@progbits

_snios_sndmsg_jt:
    ld   h, b
    ld   l, c
    jp   _snios_sndmsg_c

_snios_rcvmsg_jt:
    ld   h, b
    ld   l, c
    jp   _snios_rcvmsg_c
