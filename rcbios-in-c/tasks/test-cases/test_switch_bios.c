volatile unsigned char result;
unsigned char iobyte;
unsigned char fn_a(void);
unsigned char fn_b(void);
unsigned char fn_c(void);

// Pattern like bios_const: switch with function calls
unsigned char test_bios_const(void) {
    switch (iobyte & 3) {
    case 0: return fn_a();
    case 1: return fn_b();
    case 2: return fn_c();
    default: return 0;
    }
}

// Pattern like bios_conout: switch with different actions
void test_bios_conout(unsigned char c) {
    switch (iobyte & 3) {
    case 0: fn_a(); fn_b(); break;
    case 1: fn_b(); break;
    case 2: fn_c(); break;
    case 3: break;
    }
}
