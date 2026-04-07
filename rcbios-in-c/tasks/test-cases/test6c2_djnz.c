// Issue 6c: Missing DJNZ idiom - simple countdown
volatile unsigned char sink;
void test_djnz(void) {
    unsigned char n = 10;
    do {
        sink = n;
    } while (--n);
}
