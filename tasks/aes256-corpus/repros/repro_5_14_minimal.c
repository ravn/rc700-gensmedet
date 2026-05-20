/*
 * Minimal isolated repro for ravn/z88dk#5 + #14 cluster.
 *
 * Hypothesis: bug fires in `--sdcccall 1 + K&R + --nogcse` parameter
 * lowering for register-passed K&R-int-promoted pointers.  Symptom:
 * writes through an absolute-address pointer assigned AFTER a
 * K&R-prototype call are dropped.
 *
 * Build matrix (build_matrix_5_14.sh in same dir):
 *   01: K&R     + --sdcccall 1 + (default GCSE)  -> expect PASS
 *   02: K&R     + --sdcccall 1 + --nogcse         -> expect FAIL (#5)
 *   03: K&R     + --sdcccall 0 + --nogcse         -> expect PASS
 *   04: ANSI    + --sdcccall 1 + --nogcse         -> expect PASS
 *   05: ANSI    + --sdcccall 1 + (default GCSE)   -> expect PASS
 *
 * Verifier: write byte 0xA5 to 0xC000.  z88dk-ticks RAM dump byte
 * at 0xC000 = 0xA5 means store hit RAM (PASS); anything else is FAIL.
 *
 * NOTE: function defined BEFORE main() so K&R signature is visible at
 * call site -- avoids the empty-parens-declaration zsdcc ICE which is
 * a separate bug (SDCCast.c:982 "Setting of register parameter vs.
 * other parameter not yet implemented for functions without prototype").
 */

typedef unsigned char uint8_t;

#define RESULT_ADDR 0xC000

typedef struct {
    uint8_t pad[32];
} ctx_t;

/* K&R-style function: definition is the only declaration.  Caller in
 * main() sees this and follows K&R default-promotion rules. */
void touch_struct(c) ctx_t *c;
{
    c->pad[0] = 1;
}

int main(void) {
    ctx_t ctx;
    uint8_t *r;

    /* Struct-pointer-arg call -- mimics aes256_encrypt_ecb shape. */
    touch_struct(&ctx);

    /* Late-assigned absolute-address pointer.  No prior use. */
    r = (uint8_t *)RESULT_ADDR;

    /* Write that #5 reports as dropped under --sdcccall 1 + --nogcse. */
    r[0] = 0xA5;

    return 0;
}
