/* ANSI counterpart to repro_5_14_minimal.c -- same semantics, full prototypes. */

typedef unsigned char uint8_t;

#define RESULT_ADDR 0xC000

typedef struct {
    uint8_t pad[32];
} ctx_t;

void touch_struct(ctx_t *c);

int main(void) {
    ctx_t ctx;
    uint8_t *r;

    touch_struct(&ctx);

    r = (uint8_t *)RESULT_ADDR;
    r[0] = 0xA5;

    return 0;
}

void touch_struct(ctx_t *c)
{
    c->pad[0] = 1;
}
