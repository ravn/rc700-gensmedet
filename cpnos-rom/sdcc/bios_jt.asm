; cpnos-rom BIOS jump table — z88dk SDCC port of bios_jt.s.
;
; Standard CP/M 2.2 BIOS 17-entry table, placed at BIOS_BASE (0xF200).
; CCP+BDOS (and in NOS mode, NDOS) call these offsets; the addresses
; are the BIOS's public ABI and must not drift between builds.
;
; sections.asm pins SECTION RESIDENT_JUMPTABLE at org 0xF200, so
; _bios_boot equals BIOS_BASE.
;
; CP/NOS routes disk I/O through NDOS -> SNIOS, so SELDSK/READ/WRITE
; never get called for network drives.  Those slots still have to
; exist for the standard offsets to line up, but they land on
; _bios_stub_ret which just returns.

    SECTION RESIDENT_JUMPTABLE

    EXTERN _impl_boot
    EXTERN _impl_wboot
    EXTERN _bios_const_shim
    EXTERN _bios_conin_shim
    EXTERN _bios_conout_shim

    PUBLIC _bios_jt
    PUBLIC _bios_boot, _bios_wboot
    PUBLIC _bios_const, _bios_conin, _bios_conout
    PUBLIC _bios_list, _bios_punch, _bios_reader
    PUBLIC _bios_home, _bios_seldsk
    PUBLIC _bios_settrk, _bios_setsec, _bios_setdma
    PUBLIC _bios_read, _bios_write
    PUBLIC _bios_listst, _bios_sectran
    PUBLIC _bios_stub_ret

_bios_jt:
_bios_boot:     jp _impl_boot
_bios_wboot:    jp _impl_wboot
_bios_const:    jp _bios_const_shim     ; CP/M ABI shim — naked C in resident.c
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
_bios_sectran:  jp _bios_stub_ret       ; identity in NOS-only build

; _bios_stub_ret defined HERE (not as `void f(void){}` in resident.c)
; because SDCC's compilation of an empty C function placed it in
; z88dk's `code_l_sccz80` runtime-library section (~0xEDF4), which our
; prom_loader does NOT copy to RAM.  NDOS's calls to unimplemented
; BIOS entries (LIST/PUNCH/SELDSK/READ/WRITE/...) then JP into
; uninitialised RAM, eventually wrapping to a JP 0 warm-boot loop.
;
; Must NOT extend RESIDENT_JUMPTABLE — that shifts _snios_jt off the
; NIOS=0xEE33 address cpnos.com hardcodes.  Park in RESIDENT_CODE
; (lives at 0xF3DC..0xF7A2 in current layout, well within LDIR range).
    SECTION RESIDENT_CODE
_bios_stub_ret:
                ret
