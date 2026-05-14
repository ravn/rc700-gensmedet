/*
 * Minimal reproducer for ravn/llvm-z80#NEW — fshl idiom not recognised
 * on K&R-style u8 rotate chains (residual after #158, distinct from #160).
 *
 * Function rj_sb_inv from aes256.c. Two variants of the same algorithm
 * with byte-identical body; only the declaration style of the parameter
 * differs:
 *
 *   uint8_t rj_sb_inv(x) uint8_t x;   <-- K&R, parameter is i16 in IR
 *   uint8_t rj_sb_inv(uint8_t x)      <-- ANSI, parameter is i8 in IR
 *
 * Build BOTH:
 *   clang --target=z80 -Oz -nostdlib -ffreestanding -std=c89 \
 *         -Wno-deprecated-non-prototype -DKR -S -emit-llvm \
 *         -c repro_rj_sb_inv_kr_fshl_missed.c -o kr.ll
 *   clang --target=z80 -Oz -nostdlib -ffreestanding -std=c89 \
 *         -Wno-deprecated-non-prototype -DANSI -S -emit-llvm \
 *         -c repro_rj_sb_inv_kr_fshl_missed.c -o ansi.ll
 *
 * Compare the IR. ANSI emits 3x `llvm.fshl.i8` intrinsics for the rotate
 * chain — clean recognition. K&R emits 17 i16-typed shl/lshr/and/or ops
 * with explicit `and 0xFE` masking on the wraparound bit. No fshl.
 *
 * Z80 size impact (HEAD post-#160):
 *   K&R  : rj_sb_inv = 156 B
 *   ANSI : rj_sb_inv = 18 B
 *   gap  : +138 B (8.7x)
 */

typedef unsigned char uint8_t;

/* gf_mulinv stub — also K&R-narrow so the call boundary mirrors the
 * real aes256.c chain.  Made non-trivial via __attribute__((noinline))
 * so the call stays in the IR (the trivial `return y` stub would inline
 * away and leave the trunc-at-return as a root, hiding the bug). */
__attribute__((noinline))
uint8_t gf_mulinv(y) uint8_t y;
{
    uint8_t i, r = 0;
    for (i = 0; i < y; i++) r = (r + 1) & 0xFF;
    return r;
}

#ifdef KR
uint8_t rj_sb_inv(x) uint8_t x;
{
    uint8_t y, sb;
    y = x ^ 0x63;
    sb = y = (y<<1)|(y>>7);
    y = (y<<2)|(y>>6); sb ^= y; y = (y<<3)|(y>>5); sb ^= y;
    return gf_mulinv(sb);
}
#else
uint8_t rj_sb_inv(uint8_t x)
{
    uint8_t y, sb;
    y = x ^ 0x63;
    sb = y = (y<<1)|(y>>7);
    y = (y<<2)|(y>>6); sb ^= y; y = (y<<3)|(y>>5); sb ^= y;
    return gf_mulinv(sb);
}
#endif
