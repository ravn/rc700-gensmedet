// Issue 6b: Missing INC (HL) / DEC (HL) idiom
volatile unsigned char counter;
void test_inc_mem(void) { counter++; }
