; cpnos-rom BIOS jump table
;
; Standard CP/M 2.2 BIOS 17-entry table, placed at BIOS_BASE (currently
; 0xDD00; was 0xED00 Phase 19, 0xF200 pre-session-33, 0xF580 earlier).
; CCP+BDOS (and in NOS mode, NDOS) call these offsets; the addresses
; are the BIOS's public ABI and must not drift between builds.
;
; The linker script KEEPs section .resident.jumptable at the very start
; of the .resident region (VMA 0xDD00), so `_bios_boot` equals BIOS_BASE.
; payload.ld asserts `_bios_boot == ORIGIN(PAYLOAD)` at link time.
;
; cpnos-build/src/cpbios.asm has `rbboot equ 0DD00h` hardcoded for the
; CP/NOS shim's tail-calls into our JT — that constant must track
; this base (rebuild cpnos.com after any move).
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
_bios_const:    jp _impl_const
_bios_conin:    jp _impl_conin
_bios_conout:   jp _impl_conout
_bios_list:     jp _bios_stub_ret
_bios_punch:    jp _bios_stub_ret
_bios_reader:   jp _bios_stub_ret
_bios_home:     jp _bios_stub_ret
_bios_seldsk:   jp _impl_seldsk
_bios_settrk:   jp _impl_settrk
_bios_setsec:   jp _impl_setsec
_bios_setdma:   jp _impl_setdma
_bios_read:     jp _impl_read
_bios_write:    jp _impl_disk_err
_bios_listst:   jp _bios_stub_ret
_bios_sectran:  jp _bios_stub_ret          ; identity in NOS-only build

; ------------------------------------------------------------------
; Disk BIOS glue — ABI-thin asm bodies for the JT entries above.
;
; These live outside the jumptable section because the JT must be
; exactly 51 bytes (17 × 3 byte JP).  They hide the ABI mismatch
; between CP/M's register convention (drive in C, track/sec/DMA in
; BC, DPH return in HL) and clang-z80's sdcccall(1), by never going
; through C at all for the trivial cases.
;
; State vars dsk_track, dsk_sector, dsk_dma are C globals declared
; in resident.c so the eventual impl_read (commit 2) reads them from
; the same storage the setters write.
; ------------------------------------------------------------------

    .section .resident.disk, "ax", @progbits
    .global _impl_seldsk
    .global _impl_settrk
    .global _impl_setsec
    .global _impl_setdma

; impl_seldsk — CP/M passes drive in C, expects DPH in HL.
; Drive 0 (A:)      → return HL=0; NDOS has already intercepted for
;                     network drives before the JT is reached, so
;                     0 here is "not present".
; Drive 1 (B:)      → return HL=&dph_b; the local 8" maxi floppy.
; Drive 2..15       → return HL=0; no other local drives.
_impl_seldsk:
    ld   a, c               ; drive from CP/M
    cp   1                  ; B:?
    jr   nz, .Lseldsk_none
    ld   hl, _dph_b
    ret
.Lseldsk_none:
    ld   hl, 0
    ret

; impl_settrk / impl_setsec / impl_setdma — CP/M passes BC.
; We just mirror it into a BSS word.  Nothing reads these yet in
; this commit; impl_read in the next commit consumes them.
_impl_settrk:
    ld   (_dsk_track), bc
    ret
_impl_setsec:
    ld   (_dsk_sector), bc
    ret
_impl_setdma:
    ld   (_dsk_dma), bc
    ret
