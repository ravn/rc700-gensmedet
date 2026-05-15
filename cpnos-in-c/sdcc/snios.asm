; cpnos-rom SNIOS — JT trampoline only (z88dk z80asm port of snios.s).
;
; The full SNIOS body lives in snios_c.c (#75 Phases 1-6).  This file
; only holds the 24-byte JT (ABI-fixed by NDOS) and two BC->HL
; calling-convention bridges for the SNDMSG/RCVMSG JT entries.
;
; Sections renamed to match cpnos-rom/sdcc/sections.asm:
;   .resident.snios_jt -> RESIDENT_SNIOS_JT
;   .resident.snios    -> RESIDENT_SNIOS

    EXTERN _cfgtbl
    EXTERN _snios_ntwkin_impl
    EXTERN _snios_ntwkst_impl
    EXTERN _snios_cnftbl_impl
    EXTERN _snios_ntwker_impl
    EXTERN _snios_ntwkbt_impl
    EXTERN _snios_ntwkdn_impl
    EXTERN _snios_sndmsg_c
    EXTERN _snios_rcvmsg_c

;----------------------------------------------------------------
;  SNIOS jump table  (first 24 bytes — public ABI for NDOS)
;----------------------------------------------------------------
    SECTION RESIDENT_SNIOS_JT
    PUBLIC _snios_jt
    PUBLIC _snios_ntwkin, _snios_ntwkst, _snios_cnftbl
    PUBLIC _snios_sndmsg, _snios_rcvmsg
    PUBLIC _snios_ntwker, _snios_ntwkbt, _snios_ntwkdn

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
;----------------------------------------------------------------
    SECTION RESIDENT_SNIOS

_snios_sndmsg_jt:
    ld   h, b
    ld   l, c
    jp   _snios_sndmsg_c

_snios_rcvmsg_jt:
    ld   h, b
    ld   l, c
    jp   _snios_rcvmsg_c
