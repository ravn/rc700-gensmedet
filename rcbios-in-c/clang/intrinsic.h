/*
 * intrinsic.h — clang-side SDCC keyword-compatibility shim.
 *
 * The Z80 privileged-instruction intrinsics (intrinsic_di/ei/halt/nop/im_2)
 * now live IN THE COMPILER: clang ships <intrinsic.h> in its resource dir
 * (ravn/llvm-z80#42).  This shim chains to it via #include_next, so the
 * definitions come from the compiler — exactly as SDCC gets them from z88dk's
 * <intrinsic.h>.  The SAME source therefore compiles under both toolchains
 * with no #ifdef and no inline assembly on the clang path.
 *
 * This file only adds what is NOT an intrinsic:
 *   - host-clang (CLion indexing) no-op stubs, since the shipped header
 *     #error's on non-Z80 targets;
 *   - SDCC keyword stubs (__naked/__critical/__interrupt/__sdcccall) and the
 *     __asm__(x) neutralizer for SDCC-syntax inline asm in naked bodies.
 */

#ifndef _INTRINSIC_H
#define _INTRINSIC_H

/* ================================================================
 * Z80 privileged-instruction intrinsics — sourced from the compiler.
 * Host clang (CLion) gets no-op stubs; only Z80 clang chains to the
 * shipped <intrinsic.h>.
 * ================================================================ */

#ifdef __z80__
#include_next <intrinsic.h>
#else
static inline void intrinsic_di(void)   {}
static inline void intrinsic_ei(void)   {}
static inline void intrinsic_halt(void) {}
static inline void intrinsic_nop(void)  {}
static inline void intrinsic_im_2(void) {}
#endif

/* ================================================================
 * SDCC keyword stubs for source compatibility
 *
 * These allow bios.c to compile with clang without changes.
 * The naked functions become empty stubs (dead code, gc'd by linker).
 *
 * __critical and __interrupt expand to NOTHING on clang: every ISR body
 * is compiled as a plain (RET-ending) function, and the interrupt framing
 * — register save/restore, EI, RETI — is supplied EXPLICITLY by the
 * assembly wrappers in bios_shims.s that the IVT points at.  This is the
 * same "explicit wrapper" model the __naked ISRs already use.
 *
 * Rationale: clang's __attribute__((interrupt)) emits RETI but no EI, and
 * the RC702 requires every handler to re-enable interrupts before RETI
 * (Z80 RETI does NOT restore IFF).  Relying on the attribute (or on the
 * removed z80_critical attribute) left interrupts permanently disabled
 * after the first ISR -> black screen.  Owning EI/RETI in the wrappers
 * removes that dependency on compiler magic entirely.  See bios_shims.s.
 * ================================================================ */

#define __naked
#define __critical
#define __interrupt(n)
#define __sdcccall(x)

/* Neutralize SDCC-syntax inline asm in naked function bodies.
 * The naked functions are dead code for clang (the jump table
 * points to shims in bios_shims.s instead). */
#define __asm__(x) ((void)0)

#endif /* _INTRINSIC_H */
