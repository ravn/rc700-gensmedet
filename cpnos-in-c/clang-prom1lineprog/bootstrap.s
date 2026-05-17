; PROM1-only line program bootstrap for cpnos-in-c.
;
; Lives at ROM 0x2000.  Autoload-in-c's prom1_if_present detects the
; " RC702" signature at 0x2002 and jumps to *(word*)0x2000, i.e. to
; bootstrap_entry below.
;
; Boot flow:
;   1. DI + set SP (same as cpnos-in-asm's slave_entry).
;   2. ZX0-decompress payload to RAM 0xED00 (resident JT live).
;   3. ZX0-decompress init to RAM 0xC000 (init code live).
;   4. Jump to 0xC000 -- cpnos_cold_entry runs hw bring-up, netboot,
;      and tail-calls resident_handoff which OUTs RAMEN and lands
;      execution in NDOS at 0xDD80.

	.section .lineprog_header,"a",@progbits
	; 0x2000: jump target read by autoload-in-c (.word = 2 B little-endian)
	.short	bootstrap_entry
	; 0x2002: 6-byte signature
	.ascii	" RC702"

	.section .lineprog_entry,"ax",@progbits

	.globl	bootstrap_entry
bootstrap_entry:
	di
	ld	sp, 0xF680		; PROM1-only-v3 stack top (was 0xF700;
					; layout moved it to free locale region)
	; Decompress payload first -- resident at 0xED00 must be live
	; before init runs, because init.c calls into resident-side
	; helpers (impl_conout, snios_*, isr_*, set_i_reg, etc.).
	ld	hl, __payload_zx0_start
	ld	de, 0xED00
	call	dzx0_standard
	; Decompress init at 0xC000.  cpnos_cold_entry is the first
	; symbol in .init (objdump confirms _cpnos_cold_entry sits at
	; __init_start), so its runtime address is exactly 0xC000.
	ld	hl, __init_zx0_start
	ld	de, 0xC000
	call	dzx0_standard
	; Pre-fill outcon at 0xF680..0xF6FF with byte-identity (0..0x7F).
	; This makes impl_conout pass chars through during the cold-boot
	; window before install_locale_tables() runs in resident_handoff
	; -- netboot's loading-dot progress on row 1 + any other pre-
	; install conout writes render as their literal byte instead of
	; indexing into a still-zero table (which previously turned the
	; whole cold-boot phase into NUL spew when sentinel=1).  L wraps
	; from 0xFF to 0x00 inside a single 256 B page (HL stays in
	; 0xF6xx), so we only need to test A for the 0x80 sentinel.
	ld	hl, 0xF680
	xor	a
.fill_outcon:
	ld	(hl), a
	inc	l
	inc	a
	jp	p, .fill_outcon
	; Sentinel is NOT written here.  init.c arms it between
	; print_banner() and netboot_mpm(); writing it in bootstrap
	; made impl_conout index a still-empty outcon at 0xF680 during
	; the banner and silently zero-out every character (caught
	; session 73j-locale by the TYPE ASCII.TXT run -- top of
	; display showed only NULs).
	; Tail-call into init.  cpnos_cold_entry is NORETURN; it ends
	; with resident_handoff which RAMENs and JPs to NDOS at 0xDD80.
	jp	0xC000
