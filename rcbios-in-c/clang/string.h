/* Minimal string.h for freestanding Z80 build.
 * Implementations in runtime.s (sdcccall(1) convention). */
#ifndef _STRING_H
#define _STRING_H

#include <stddef.h>

void *memcpy(void *dest, const void *src, size_t n);
void *memset(void *s, int c, size_t n);
void *memmove(void *dest, const void *src, size_t n);
void *memchr(const void *s, int c, size_t n);
void lddr_copy(void *src_end, void *dst_end, size_t n);

/* Fast block copy: LDIR remainder + 16xLDI unrolled loop.
 * 20% faster than LDIR for copies >= 16 bytes (16T/byte vs 21T/byte).
 * Does NOT handle overlapping regions — use memmove() for those.
 *
 * blocks16  = (n / 16) * 16  — byte count for 16xLDI loop (BC value)
 * remainder = n % 16         — byte count for initial LDIR (0 = skip)
 *
 * Both arguments should be compile-time constants; the function is
 * always inlined so the compiler folds the constants and emits bare
 * LD BC,imm + LDIR / 16xLDI + JP PE with no call overhead. */
static inline void
memcpy_z80(void *dest, const void *src, unsigned short blocks16, unsigned char remainder)
{
#ifdef __z80__
    /* Bind operands to physical pairs via GCC local register variables (the
     * upstream-standard form); clang rejects the braced "+{de}" in C source.
     * The remainder LDIR advances DE/HL past the initial block, so thread the
     * read-write pointers forward into the 16xLDI loop. */
    if (remainder) {
        register void *de       __asm__("de") = dest;
        register const void *hl __asm__("hl") = src;
        register unsigned short bc __asm__("bc") = remainder;
        __asm volatile("ldir" : "+r"(de), "+r"(hl), "+r"(bc) :: "memory");
        dest = de;
        src  = (const void *)hl;
    }
    if (blocks16) {
        register void *de       __asm__("de") = dest;
        register const void *hl __asm__("hl") = src;
        register unsigned short bc __asm__("bc") = blocks16;
        __asm volatile(
            "1: ldi\n ldi\n ldi\n ldi\n ldi\n ldi\n ldi\n ldi\n"
            "   ldi\n ldi\n ldi\n ldi\n ldi\n ldi\n ldi\n ldi\n"
            "   jp pe, 1b"
            : "+r"(de), "+r"(hl), "+r"(bc) :: "memory");
    }
#else
    memcpy(dest, src, blocks16 + remainder);
#endif
}

#endif
