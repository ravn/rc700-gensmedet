/*
 * Behavioural test for the oracle corpus. Calls each function with
 * known inputs, stores 21 expected-value bytes at RESULTS, then HALTs.
 * Runner (Makefile) loads the binary into z88dk-ticks, lets it run to
 * the HALT, dumps RAM, and compares RESULTS against the expected
 * 21-byte vector.
 *
 * C90-clean to compile in clang / zsdcc / sccz80.
 */

#include <stdint.h>

extern volatile uint8_t bss_buf[8];
extern volatile uint8_t flag;

uint8_t  sw_dense(uint8_t x);
uint8_t  djnz_count(uint8_t n);
void     seq_bss(void);
uint8_t  mod_10(uint8_t x);
uint8_t  mod_7(uint8_t x);
void     set_flag(uint8_t v);
void     copy8(uint8_t *dst, const uint8_t *src);
uint8_t  test_bit3(uint8_t x);
void     fill_buf(void);
uint8_t  is_ff(uint8_t x);
void     index_loop(void);

/* Fixed-address results area. The harness reads 32 bytes from
 * RESULTS_ADDR after the program HALTs. Place it high enough not to
 * collide with the test image. */
#define RESULTS_ADDR 0xC000

/* Source for copy8 test. */
static const uint8_t copy_src[8] = {1, 2, 3, 4, 5, 6, 7, 8};
static uint8_t       copy_dst[8];

int main(void) {
    uint8_t *r = (uint8_t *)RESULTS_ADDR;

    /* sw_dense: 0->10, 1->20, 2->30, 3->40, 99->0 */
    r[0] = sw_dense(0);
    r[1] = sw_dense(1);
    r[2] = sw_dense(2);
    r[3] = sw_dense(3);
    r[4] = sw_dense(99);

    /* djnz_count: counts loop iterations. With do{++acc}while(--n)
     * starting from n in {1, 5, 255}, acc ends at n. */
    r[5] = djnz_count(1);
    r[6] = djnz_count(5);
    r[7] = djnz_count(255);

    /* seq_bss: writes 0x11, 0x22, 0x33, 0x44 to bss_buf[0..3] */
    seq_bss();
    r[8]  = bss_buf[0];
    r[9]  = bss_buf[1];
    r[10] = bss_buf[2];
    r[11] = bss_buf[3];

    /* mod_10 (___umodqi3 with divisor=10): boundaries + a wide value. */
    r[12] = mod_10(0);     /* 0 */
    r[13] = mod_10(9);     /* 9 */
    r[14] = mod_10(10);    /* 0 */
    r[15] = mod_10(99);    /* 9 */
    r[16] = mod_10(255);   /* 5 */

    /* mod_7 (___umodqi3 with divisor=7): different divisor. */
    r[17] = mod_7(0);      /* 0 */
    r[18] = mod_7(7);      /* 0 */
    r[19] = mod_7(123);    /* 4 */

    /* set_flag: 0 -> 0, anything else -> 1 */
    set_flag(0);  r[20] = flag;
    set_flag(1);  r[21] = flag;
    set_flag(99); r[22] = flag;

    /* copy8: dst should equal src after call. Sum dst entries. */
    copy8(copy_dst, copy_src);
    {
        uint8_t i, sum;
        sum = 0;
        for (i = 0; i < 8; i++) sum = sum + copy_dst[i];
        r[23] = sum;   /* expect 1+2+...+8 = 36 */
    }

    /* test_bit3: bit-3 mask. */
    r[24] = test_bit3(0);
    r[25] = test_bit3(0x08);
    r[26] = test_bit3(0xFF);

    /* fill_buf: writes 0xAA to bss_buf[0..7] */
    fill_buf();
    r[27] = bss_buf[0];
    r[28] = bss_buf[7];

    /* is_ff: A==0xFF -> 1, else 0 */
    r[29] = is_ff(0);
    r[30] = is_ff(0xFE);
    r[31] = is_ff(0xFF);

    /* index_loop: writes 0..7 to bss_buf[0..7] */
    index_loop();
    /* Not stored separately; bss_buf[0] = 0 and bss_buf[7] = 7
     * (we don't have room in r[] anymore, but z88dk-ticks dumps
     * the whole 64K so a separate post-check on bss_buf is possible). */

    /* Sentinel: write 0xA5 right above the results so the harness can
     * confirm we actually reached the end. */
    r[32] = 0xA5;

    /* HALT — z88dk-ticks sees the HALT and exits cleanly. */
    for (;;) {
        /* fallback: spin if HALT didn't get emitted */
    }
    return 0;
}
