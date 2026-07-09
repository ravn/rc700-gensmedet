# Why rcbios keeps hand-written lddr_copy (2026-07-08)

`rcbios-in-c/clang/runtime.s::lddr_copy` (5-byte backward-LDDR helper) is kept
deliberately, NOT because the compiler can't fold memmove.

(As of 2026-07-08 runtime.s contains ONLY `lddr_copy` — memcpy/memset/memchr/
__call_iy/___umodqi3 now come from the compiler's `z80_rt.a`; see
`runtime-helpers-via-archive-2026-07-08.md`.  `lddr_copy` has no compiler-rt
equivalent, so it stays.)

The llvm-z80 compiler was improved this session so `__builtin_memmove` DOES
fold the bios.c screen-scroll shape `memmove(base+K, base, C-i)` to inline
LDDR with constant end pointers (three folds on llvm-z80 main: runtime-base
direction, runtime-term cancellation, constant-address-base immediate).

But for the **two-site** `insert_line` scroll, inline `__builtin_memmove` is
still **+39 B** vs the shared `lddr_copy`.  A flexible `memmove` (start
pointers, size may be 0, any context) bridged to the rigid `LDDR` (end
pointers, BC=0→65536-byte copy, pins HL+DE+BC) costs glue paid **per site**;
a shared helper amortizes it.  Full four-mismatch analysis + the three fold
commits: `llvm-z80/tasks/session-2026-07-08-memmove-lddr-lowering.md`,
entries B23/B24 in `llvm-z80/tasks/known-suboptimal-codegen.md`.

Decision: keep `lddr_copy` (size-optimal for the 2-site pattern).  Do not
re-attempt the __builtin_memmove swap unless insert_line drops to a single
site or the scroll moves off `-flto`.  The compiler folds ship anyway — they
help single-site / other constant-address memmoves.
