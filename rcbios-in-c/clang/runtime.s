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
	.globl	_lddr_copy
_lddr_copy:
	pop	iy
	pop	bc		; n
	lddr
	jp	(iy)
