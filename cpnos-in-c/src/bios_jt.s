; cpnos-rom BIOS jump table
;
; Standard CP/M 2.2 BIOS 17-entry table, placed at BIOS_BASE (currently
; 0xED00; was 0xF200 pre-session-33, and 0xF580 before that).  CCP+BDOS
; (and in NOS mode, NDOS) call these offsets; the addresses are the
; BIOS's public ABI and must not drift between builds.
;
; The linker script KEEPs section .resident.jumptable at the very start
; of the .resident region (VMA 0xED00), so `_bios_boot` equals BIOS_BASE.
; payload.ld asserts `_bios_boot == 0xED00` at link time.
;
; Naming convention: each `bios_<entry>` below is a 3-byte `jp <tgt>`
; trampoline at the JT's fixed offset.  <tgt> is either a shared asm
; stub (`_bios_stub_ret`) or a C function in resident.c named
; `impl_<entry>`.  That pairing makes it obvious which asm vector goes
; with which C body — renames must keep both sides in sync or the link
; fails on an unresolved external.
;
; Most entries in the NOS-only build are thin stubs: CP/NOS routes disk
; I/O through NDOS -> SNIOS, so SELDSK/READ/WRITE never get called for
; network drives. Those slots still have to exist for the standard jump
; offsets to line up, but they land on _bios_stub_ret which just returns.

    .section .resident.jumptable, "ax"
    .global _bios_jt
    .global _bios_boot, _bios_wboot
    .global _bios_const, _bios_conin, _bios_conout
    .global _bios_list, _bios_punch, _bios_reader
    .global _bios_home, _bios_seldsk
    .global _bios_settrk, _bios_setsec, _bios_setdma
    .global _bios_read, _bios_write
    .global _bios_listst, _bios_sectran

_bios_jt:
_bios_boot:     jp _impl_boot
_bios_wboot:    jp _impl_wboot
_bios_const:    jp _bios_const_shim   ; CP/M ABI shim — naked C in resident.c
_bios_conin:    jp _bios_conin_shim
_bios_conout:   jp _bios_conout_shim
_bios_list:     jp _bios_stub_ret
_bios_punch:    jp _bios_stub_ret
_bios_reader:   jp _bios_stub_ret
_bios_home:     jp _bios_stub_ret
_bios_seldsk:   jp _bios_stub_ret
_bios_settrk:   jp _bios_stub_ret
_bios_setsec:   jp _bios_stub_ret
_bios_setdma:   jp _bios_stub_ret
_bios_read:     jp _bios_stub_ret
_bios_write:    jp _bios_stub_ret
_bios_listst:   jp _bios_stub_ret
_bios_sectran:  jp _bios_stub_ret          ; identity in NOS-only build
