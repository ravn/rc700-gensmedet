typedef unsigned char uint8_t;

typedef struct {
    uint8_t key[32];
    uint8_t enckey[32];
    uint8_t deckey[32];
} aes256_context;

void aes256_init(aes256_context *ctx, uint8_t *k);
void aes256_encrypt_ecb(aes256_context *ctx, uint8_t *buf);
void aes256_decrypt_ecb(aes256_context *ctx, uint8_t *buf);
void aes_done(aes256_context *ctx);

#define RESULTS_ADDR 0xC000

static const uint8_t expected_ct[16] = {
    0x8e, 0xa2, 0xb7, 0xca, 0x51, 0x67, 0x45, 0xbf,
    0xea, 0xfc, 0x49, 0x90, 0x4b, 0x49, 0x60, 0x89
};

int main(void) {
    aes256_context ctx;
    uint8_t key[32];
    uint8_t buf[16];
    uint8_t i;
    uint8_t enc_ok, dec_ok;
    uint8_t *r;

    for (i = 0; i < 16; i++) buf[i] = (uint8_t)(i * 16 + i);
    for (i = 0; i < 32; i++) key[i] = i;

    aes256_init(&ctx, key);
    aes256_encrypt_ecb(&ctx, buf);

    r = (uint8_t *)RESULTS_ADDR;
    for (i = 0; i < 16; i++) r[i] = buf[i];

    enc_ok = 1;
    for (i = 0; i < 16; i++) {
        if (buf[i] != expected_ct[i]) { enc_ok = 0; break; }
    }
    r[16] = enc_ok;

    aes256_init(&ctx, key);
    aes256_decrypt_ecb(&ctx, buf);

    for (i = 0; i < 16; i++) r[17 + i] = buf[i];

    dec_ok = 1;
    for (i = 0; i < 16; i++) {
        if (buf[i] != (uint8_t)(i * 16 + i)) { dec_ok = 0; break; }
    }
    r[33] = dec_ok;

    aes_done(&ctx);

    r[34] = 0xA5;
    return 0;
}
