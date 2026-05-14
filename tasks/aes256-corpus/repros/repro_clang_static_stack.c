typedef unsigned char uint8_t;

typedef struct {
    uint8_t key[32];
    uint8_t enckey[32];
    uint8_t deckey[32];
} aes256_context;

void aes256_init(aes256_context *ctx, uint8_t *k);
void aes256_encrypt_ecb(aes256_context *ctx, uint8_t *buf);
void aes256_decrypt_ecb(aes256_context *ctx, uint8_t *buf);

int main(void)
{
    uint8_t *r = (uint8_t *)0xC000;
    uint8_t i;
    aes256_context ctx;
    uint8_t key[32], buf[16];

    for (i = 0; i < 16; i++) buf[i] = i * 16 + i;
    for (i = 0; i < 32; i++) key[i] = i;

    aes256_init(&ctx, key);
    aes256_encrypt_ecb(&ctx, buf);
    for (i = 0; i < 16; i++) r[i] = buf[i];

    aes256_init(&ctx, key);
    aes256_decrypt_ecb(&ctx, buf);
    for (i = 0; i < 16; i++) r[17 + i] = buf[i];

    r[34] = 0xA5;
    return 0;
}
