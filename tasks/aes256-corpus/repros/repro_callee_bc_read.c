/*
 * Targeted repro of the ABI mismatch found via #5 deep-dive.
 *
 * Under K&R + --sdcccall 1 + --nogcse, SDCC compiles K&R-defined
 * functions as if they use --sdcccall 0 (stack-args ABI) for parameter
 * receipt, while the caller uses --sdcccall 1 (register-args ABI).
 * Caller and callee disagree.
 *
 * Trigger requires the caller to keep a value alive in BC across the
 * call — caller emits `push bc; call foo; pop bc` for caller-save.
 * The pushed BC then sits at `(ix+4)` in the callee's frame, exactly
 * where the K&R callee expects to find its first arg.  Callee picks
 * up the caller's BC as if it were ctx.
 *
 * To force BC live across the call, this program uses an
 * absolute-address pointer (the classic pattern from ravn/z88dk#5):
 *   r = (uint8_t *)DECOY_ADDR; r[i] = i;
 * then call zero_ctx; then use r again.  Under --nogcse the compiler
 * keeps r in BC = DECOY_ADDR across the call.
 *
 * Verifier:
 *   PASS:  local zeroed, decoy untouched.
 *   BUG:   decoy zeroed instead of local.
 */

typedef unsigned char uint8_t;

#define DECOY_ADDR 0xC700

typedef struct {
    uint8_t key[32];
    uint8_t enckey[32];
    uint8_t deckey[32];
} ctx_t;

/* K&R-style, same body shape as aes_done(ctx) in aes256.c. */
void zero_ctx(c) ctx_t *c;
{
    register uint8_t i;
    for (i = 0; i < 32; i++)
        c->key[i] = c->enckey[i] = c->deckey[i] = 0;
}

int main(void) {
    ctx_t local;
    uint8_t i;
    uint8_t *r;

    /* Pre-fill local + decoy with non-zero pattern. */
    for (i = 0; i < 96; i++) ((uint8_t *)&local)[i] = 0xAA;
    for (i = 0; i < 96; i++) ((volatile uint8_t *)DECOY_ADDR)[i] = 0xAA;

    /* The "late-assigned r" pattern from #5: forces compiler to keep
     * r in BC under --nogcse. */
    r = (uint8_t *)DECOY_ADDR;
    for (i = 0; i < 16; i++) r[i] = 0xBB;

    /* The bug call.  Under --sdcccall 1 + K&R callee, this should
     * zero local.  Under the bug, it zeros via BC = DECOY_ADDR. */
    zero_ctx(&local);

    /* Use r again after the call so the compiler keeps it alive
     * (otherwise dead-store elimination might let r go before the
     *  call site). */
    for (i = 16; i < 32; i++) r[i] = 0xCC;

    /* Snapshot results at 0xC800. */
    ((volatile uint8_t *)0xC800)[0] = local.key[0];
    ((volatile uint8_t *)0xC800)[1] = local.key[31];
    ((volatile uint8_t *)0xC800)[2] = local.enckey[0];
    ((volatile uint8_t *)0xC800)[3] = local.deckey[31];
    ((volatile uint8_t *)0xC800)[4] = ((volatile uint8_t *)DECOY_ADDR)[0];
    ((volatile uint8_t *)0xC800)[5] = ((volatile uint8_t *)DECOY_ADDR)[31];
    ((volatile uint8_t *)0xC800)[6] = ((volatile uint8_t *)DECOY_ADDR)[63];
    ((volatile uint8_t *)0xC800)[7] = ((volatile uint8_t *)DECOY_ADDR)[95];
    ((volatile uint8_t *)0xC800)[8] = 0xEE;

    return 0;
}
