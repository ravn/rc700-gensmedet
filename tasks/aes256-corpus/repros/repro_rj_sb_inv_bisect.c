/*
 * Bisection: what makes clang lose the rotate-pattern recognition
 * on the full rj_sb_inv vs the minimal rj_sb_inv_like?
 *
 * Suspects:
 *  A. The K&R-style function definition
 *  B. The tail call to gf_mulinv at the end
 *  C. Some interaction with surrounding context (TU-wide effects)
 */

typedef unsigned char uint8_t;

extern uint8_t gf_mulinv(uint8_t);

/* A. K&R style — what aes256.c actually has. */
uint8_t rj_sb_inv_kr(x)
uint8_t x;
{
    uint8_t y, sb;
    y = x ^ 0x63;
    sb = y = (y << 1) | (y >> 7);
    y = (y << 2) | (y >> 6); sb ^= y;
    y = (y << 3) | (y >> 5); sb ^= y;
    return sb;
}

/* B. ANSI style + tail call to extern */
uint8_t rj_sb_inv_tail(uint8_t x)
{
    uint8_t y, sb;
    y = x ^ 0x63;
    sb = y = (y << 1) | (y >> 7);
    y = (y << 2) | (y >> 6); sb ^= y;
    y = (y << 3) | (y >> 5); sb ^= y;
    return gf_mulinv(sb);
}

/* C. K&R style + tail call — the full rj_sb_inv shape */
uint8_t rj_sb_inv_full(x)
uint8_t x;
{
    uint8_t y, sb;
    y = x ^ 0x63;
    sb = y = (y << 1) | (y >> 7);
    y = (y << 2) | (y >> 6); sb ^= y;
    y = (y << 3) | (y >> 5); sb ^= y;
    return gf_mulinv(sb);
}
