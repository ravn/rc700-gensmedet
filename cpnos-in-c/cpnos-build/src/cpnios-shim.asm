	title	'RC702 SNIOS shim — NIOS=0xED33'
;
; Resolves cpndos.z80's `EXTRN NIOS` with a single absolute symbol.
; cpndos calls NIOS+N*3 for N = 0..7
; (NTWKIN/NTWKST/CNFTBL/SNDMSG/RCVMSG/NTWKER/NTWKBT/NTWKDN); those
; addresses resolve directly to 0xED33+N*3, which is the address
; of cpnos-rom's resident _snios_jt symbol (NDOS calls land in the
; resident BIOS without the prior 24-byte memcpy that copied the
; jump table from 0xED33 to a fixed 0xEA00 slot).  Phase A of the
; TPA-grow work (2026-04-30).
;
; Z80 has no alignment requirement on JP target tables, so the
; previous "0xEA00 because page-aligned" choice was historical
; convenience, not a hard constraint.  Pinning NIOS at the actual
; resident location closes the 24-byte slot at 0xEA00 and saves
; the runtime memcpy in cpnos_main.c::nos_handoff().
;
; The literal MUST equal cpnos-rom's `_snios_jt` address (= bios_jt
; base 0xED00 + sizeof(bios_jt) = 0xED00 + 51 = 0xED33).  An
; ASSERT in cpnos-rom/payload.ld catches drift if either side moves.
;
; 2026-05-08: Resident lowered from 0xEE00 to 0xED00 (+256 B
; resident headroom to fit debug probes / future BIOS expansion);
; cpnos.com correspondingly shifted down (CODE_BASE LDD80,
; DATA_BASE LD980 in cpnos-build/Makefile).

NIOS	EQU	0ED33h
	public	NIOS
	end
