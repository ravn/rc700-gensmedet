// Issue 6c: Missing DJNZ idiom - pure countdown, loop body doesn't use counter
void sink(void);
void test_djnz_pure(void) {
    unsigned char n = 5;
    do {
        sink();
    } while (--n);
}
