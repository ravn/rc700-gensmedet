// Issue 6a: Missing CP (HL) / SUB (HL) idiom
volatile unsigned char a, b;
_Bool test_memcmp(void) { return a == b; }
