/*
 * Caller TU.  Sees only the ANSI prototype of zero_ctx().  Under
 * `--sdcccall 1`, emits register-args ABI (arg in HL).
 *
 * The callee TU (repro_abi_mismatch_callee.c) defines zero_ctx in
 * K&R form, which forces SDCC to emit stack-args ABI for the body.
 * Caller / callee disagree -> the bug.
 *
 * Verifier: same as the standalone version -- check whether local
 * got zeroed (PASS) or decoy at 0xC700 got zeroed (BUG).
 */

typedef unsigned char uint8_t;

#define DECOY_ADDR 0xC700

typedef struct {
    uint8_t key[32];
    uint8_t enckey[32];
    uint8_t deckey[32];
} ctx_t;

/* ANSI prototype -- the trigger.  Caller will emit sdcccall 1 ABI. */
void zero_ctx(ctx_t *c);

int main(void) {
    ctx_t local;
    uint8_t i;
    uint8_t *r;

    for (i = 0; i < 96; i++) ((uint8_t *)&local)[i] = 0xAA;
    for (i = 0; i < 96; i++) ((volatile uint8_t *)DECOY_ADDR)[i] = 0xAA;

    r = (uint8_t *)DECOY_ADDR;
    for (i = 0; i < 16; i++) r[i] = 0xBB;

    zero_ctx(&local);

    for (i = 16; i < 32; i++) r[i] = 0xCC;

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
