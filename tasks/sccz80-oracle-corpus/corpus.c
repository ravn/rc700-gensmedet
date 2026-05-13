/*
 * Z80 codegen oracle micro-corpus
 *
 * Compiles in clang (llvm-z80), zsdcc, and sccz80 without changes.
 * C90-clean: declarations at top of block, no inline keyword, no
 * __attribute__, no __asm__, no _Bool, no nullptr, no compound literals.
 *
 * Each function exercises one Z80 codegen pattern we care about. Run
 * the file through each compiler, then compare per-function .text sizes.
 */

#include <stdint.h>

uint8_t bss_buf[8];
uint8_t flag;

/* 1. Dense switch on uint8_t -- jumptable vs cascaded CP candidate.
 *    SDCC tends to emit JP table; clang's choice varies. */
uint8_t sw_dense(uint8_t x) {
    switch (x) {
    case 0: return 10;
    case 1: return 20;
    case 2: return 30;
    case 3: return 40;
    default: return 0;
    }
}

/* 2. do { ... } while (--n) -- classic DJNZ idiom (2 B vs 4 B per loop). */
uint8_t djnz_count(uint8_t n) {
    uint8_t acc;
    acc = 0;
    do {
        acc++;
    } while (--n);
    return acc;
}

/* 3. Sequential consecutive-address stores -- HL-walked
 *    `ld (hl),v / inc hl` chain candidate. ravn/llvm-z80 #85. */
void seq_bss(void) {
    bss_buf[0] = 0x11;
    bss_buf[1] = 0x22;
    bss_buf[2] = 0x33;
    bss_buf[3] = 0x44;
}

/* 4. 8x8 -> 16 promotion. Pure multiply via Z80 helper. */
uint16_t mul_8x8(uint8_t a, uint8_t b) {
    return (uint16_t)a * (uint16_t)b;
}

/* 5. Conditional flag store -- `_Bool` shape without _Bool. */
void set_flag(uint8_t v) {
    flag = v ? 1 : 0;
}

/* 6. Hand-rolled 8-byte byte-copy loop -- LDIR-recognition candidate.
 *    clang may pattern-match to LDIR or unroll; SDCC will keep the
 *    loop. Avoids stdlib memcpy linkage issues across compilers. */
void copy8(uint8_t *dst, const uint8_t *src) {
    uint8_t i;
    for (i = 0; i < 8; i++) dst[i] = src[i];
}

/* 7. Single-bit test -- BIT n,A candidate. */
uint8_t test_bit3(uint8_t x) {
    return (x & 0x08) ? 1 : 0;
}

/* 8. Constant fill of 8 bytes -- LDIR overlap or unrolled stores. */
void fill_buf(void) {
    uint8_t i;
    for (i = 0; i < 8; i++) bss_buf[i] = 0xAA;
}

/* 9. Compare against 0xFF -- CP $FF vs INC A trick (ravn/llvm-z80 #148). */
uint8_t is_ff(uint8_t x) {
    return (x == 0xFF) ? 1 : 0;
}

/* 10. Loop with index store -- exercises register allocation under
 *     pressure (i live across store, base+i needed for indexing). */
void index_loop(void) {
    uint8_t i;
    for (i = 0; i < 8; i++) bss_buf[i] = i;
}
