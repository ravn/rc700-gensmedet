// Issue 4: Dead push/pop - need a function call between to trigger saves
volatile unsigned char x, y;
void sink(unsigned char v);
void test_dead_pushpop(void) {
    unsigned char a = x;
    unsigned char b = y;
    sink(a);      // call clobbers regs, forces push/pop to save b
    sink(b);
    sink(a + b);
}
