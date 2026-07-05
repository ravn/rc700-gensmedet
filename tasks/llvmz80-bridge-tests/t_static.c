// EXPECT: 1 2 3 total=6
// Family 3: static locals mangle to `_func.var` (e.g. _counter.n) — a dotted
// symbol that is NEITHER .L* nor L_*, so the pre-fix bridge left the dot in
// and z80asm rejected `ld hl,(_counter.n)` / `_counter.n:` with a syntax error.
#include <stdio.h>

static int counter(void) {
    static int n;      // -> _counter.n
    return ++n;
}

int main(void) {
    int a = counter();
    int b = counter();
    int c = counter();
    printf("%d %d %d total=%d\n", a, b, c, a + b + c);
    return 0;
}
