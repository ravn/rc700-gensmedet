; runtime.s — project-local Z80 runtime primitives NOT provided by
; llvm-z80's compiler-rt archive (z80_rt.a).
;
; memcpy/memset/memchr/memmove/__call_iy/___umodqi3 were removed 2026-07-08:
; they are all in z80_rt.a (build-macos/lib/z80/), now linked as a last-resort
; archive on the ld.lld line.  Archive semantics pull in only the members the
; codegen actually references, so nothing is duplicated.
;
; lddr_copy stays here: it is a project-specific primitive (src_end/dst_end
; backward-copy ABI for screen scroll) with no compiler-rt equivalent — the
; archive's memmove takes src_start/dst_start, a different calling convention.

	.section .text._lddr_copy,"ax",@progbits
; void lddr_copy(void *src_end, void *dst_end, size_t n)
; sdcccall(1): HL=src_end, DE=dst_end, n=stack
; Backward block copy via LDDR. Caller must ensure n > 0.
;
; KEPT DELIBERATELY (2026-07-08), not replaceable by __builtin_memmove.
; The llvm-z80 memmove->LDDR lowering now DOES fold the bios.c screen-scroll
; shape to inline LDDR with constant end pointers (three folds landed on
; llvm-z80 main: runtime-base direction, runtime-term cancellation,
; constant-address-base immediate).  But for the TWO-site insert_line scroll,
; inline is still +39 B vs this shared 5-byte helper: memmove(start,size) must
; synthesize end pointers, guard size==0 (LDDR BC=0 -> 65536-byte copy), and
; pin HL/DE/BC, and that glue is paid per site — a shared helper amortizes it.
; This helper hard-codes the answer (caller passes constant end pointers, an
; external `if(count)` guards zero, one shared body).  Full analysis:
; llvm-z80/tasks/session-2026-07-08-memmove-lddr-lowering.md and entries
; B23/B24 in llvm-z80/tasks/known-suboptimal-codegen.md.  SDCC uses a
; hand-rolled backward byte loop (bios.c, z88dk memmove is sdcccall(0)-only).
	.globl	_lddr_copy
_lddr_copy:
	pop	iy
	pop	bc		; n
	lddr
	jp	(iy)
