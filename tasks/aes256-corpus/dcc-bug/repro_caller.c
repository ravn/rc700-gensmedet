/*
 * Minimal caller for the dcc separate-compilation miscompile.
 *
 * Compile + link this together with the UNMODIFIED upstream aes256.c as TWO
 * separate translation units (dcc -> M80 -> L80).  It calls only
 * aes256_init() and then inspects two things:
 *
 *   1. ctx.enckey[]  -- after init this MUST equal the input key (init's first
 *      loop does `ctx->enckey[i] = ctx->deckey[i] = k[i]`).  Expected 0..31.
 *   2. key[]         -- the caller's OWN local array, which init must not touch.
 *
 * Observed (dcc, separate compilation):
 *   enc:  0 0 0 ... 0          (key schedule is all zeros -- WRONG)
 *   key after init: key0=58 key5=116 key31=31   (the caller's local key[] has
 *                   been CORRUPTED by the callee -- aes256_init wrote into the
 *                   caller's stack frame)
 *
 * Expected (and what the single-translation-unit build produces):
 *   enc:  0 1 2 ... 31
 *   key after init: key0=0 key5=5 key31=31      (untouched)
 *
 * The corruption proves this is not a wrong-value computation but a memory
 * stomp: executing aes256_init overwrites the caller's `key` local.
 */
typedef unsigned char uint8_t;
typedef struct {
    uint8_t key[32];
    uint8_t enckey[32];
    uint8_t deckey[32];
} aes256_context;

void aes256_init(aes256_context *ctx, uint8_t *k);
int printf();

int main(void) {
    aes256_context ctx;
    uint8_t key[32];
    uint8_t i;

    for (i = 0; i < 32; i++) key[i] = i;

    aes256_init(&ctx, key);

    printf("enc:");
    for (i = 0; i < 32; i++) printf(" %d", ctx.enckey[i]);
    printf("\n");
    printf("key after init: key0=%d key5=%d key31=%d\n", key[0], key[5], key[31]);
    return 0;
}

