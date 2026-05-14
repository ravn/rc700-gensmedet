/*
 * Bisect whether gf_log's +121 B / 4.78× gap is the same K&R-
 * int-promotion root cause as rj_sb_inv (llvm-z80#158).
 *
 * gf_log has a uint8_t parameter compared against `atb` in a tight
 * loop with byte shifts and conditional XOR.
 */

typedef unsigned char uint8_t;

/* A: K&R style — what aes256.c has */
uint8_t gf_log_kr(x)
uint8_t x;
{
    uint8_t atb = 1, i = 0, z;
    do {
        if (atb == x) break;
        z = atb;
        atb <<= 1;
        if (z & 0x80) atb ^= 0x1b;
        atb ^= z;
    } while (++i > 0);
    return i;
}

/* B: ANSI prototype, same body */
uint8_t gf_log_ansi(uint8_t x)
{
    uint8_t atb = 1, i = 0, z;
    do {
        if (atb == x) break;
        z = atb;
        atb <<= 1;
        if (z & 0x80) atb ^= 0x1b;
        atb ^= z;
    } while (++i > 0);
    return i;
}
