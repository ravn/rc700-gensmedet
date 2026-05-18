extern void mem_copy_backwards(unsigned char *dst, unsigned char *src, unsigned short n);
static unsigned char *display = (unsigned char *)0xf800;
static unsigned char cury = 0;

void scroll(unsigned char up) {
    unsigned char *row = display + (unsigned int)cury * 80u;
    if (cury + 1 < 25) {
        unsigned int count = (unsigned int)(24u - cury) * 80u;
        if (up) {
            __builtin_memcpy(row, row + 80, count);
        } else {
            unsigned char *src_e = row + count - 1;
            mem_copy_backwards(src_e + 80, src_e, count);
        }
    }
    __builtin_memset(up ? display + 24*80 : row, ' ', 80);
}
