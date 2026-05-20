/*
 * Callee TU.  K&R definition of zero_ctx.  Under `--sdcccall 1`,
 * SDCC silently emits stack-args ABI for the body even though the
 * global flag asks for register-args.  Caller (compiled in separate
 * TU with ANSI prototype) emits register-args.  ABI mismatch ->
 * zero_ctx picks up garbage from the stack as if it were ctx.
 */

typedef unsigned char uint8_t;

typedef struct {
    uint8_t key[32];
    uint8_t enckey[32];
    uint8_t deckey[32];
} ctx_t;

/* K&R-style.  No prototype declaration above; the parameter type
 * is given in the parameter-declaration list after the parentheses. */
void zero_ctx(c) ctx_t *c;
{
    register uint8_t i;
    for (i = 0; i < 32; i++)
        c->key[i] = c->enckey[i] = c->deckey[i] = 0;
}
