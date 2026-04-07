// Issue 1: Redundant BSS reloads (static stack)
// Need enough locals to force spills to BSS
volatile unsigned char g1, g2, g3, g4, g5;
unsigned char test_reload(unsigned char x) {
    unsigned char a = g1;
    unsigned char b = g2;
    unsigned char c = g3;
    unsigned char d = g4;
    unsigned char e = g5;
    if (a + b > c + d)
        return e + x;
    return a + e;
}
