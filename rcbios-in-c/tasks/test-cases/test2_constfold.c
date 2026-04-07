// Issue 2: Constant expression not folded
unsigned char buf[100];
unsigned char *get_ptr(void) {
    return &buf[50];
}
