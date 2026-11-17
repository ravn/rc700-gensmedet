/*
 * intrinsic.h — Clang/LLVM-Z80 equivalents of SDCC intrinsics.
 *
 * SDCC provides <intrinsic.h> with intrinsic_di(), intrinsic_ei(), etc.
 * This header provides the same functions for Clang via inline assembly.
 */

#ifndef _INTRINSIC_H
#define _INTRINSIC_H

#if defined(__has_builtin) && __has_builtin(__builtin_z80_di)
static inline void intrinsic_di(void) {
    __builtin_z80_di();
}

static inline void intrinsic_ei(void) {
    __builtin_z80_ei();
}

static inline void intrinsic_halt(void) {
    __builtin_z80_halt();
}

static inline void intrinsic_nop(void) {
    __builtin_z80_nop();
}
#else
static inline void intrinsic_di(void) {
    __asm__ volatile("di");
}

static inline void intrinsic_ei(void) {
    __asm__ volatile("ei");
}

static inline void intrinsic_halt(void) {
    __asm__ volatile("halt");
}

static inline void intrinsic_nop(void) {
    __asm__ volatile("nop");
}
#endif

static inline void set_i_reg(unsigned char page) {
    __asm__ volatile("ld i, a" : : "a"(page));
}

#endif /* _INTRINSIC_H */
