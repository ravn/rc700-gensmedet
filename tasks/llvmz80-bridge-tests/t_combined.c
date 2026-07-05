// EXPECT: acc=45 tag=run label=done
// All three dotted-symbol families in one translation unit:
//   - static local  -> _accumulate.acc          (family 3)
//   - string labels -> L_.str, L_.str.1, ...     (family 2)
//   - loop/branch    -> .LBB0_N                   (family 1)
#include <stdio.h>

static int accumulate(int x) {
    static int acc;    // -> _accumulate.acc
    acc += x;
    return acc;
}

int main(void) {
    int total = 0;
    for (int i = 0; i <= 9; i++) {   // .LBB loop
        if (i != 4)                  // .LBB branch operand
            total = accumulate(i);   // 0+1+2+3+5+6+7+8+9 = 41, +4 skipped
        else
            total = accumulate(i);   // still add 4 -> full 0..9 = 45
    }
    const char *tag   = "run";       // L_.str
    const char *label = "done";      // L_.str.1
    printf("acc=%d tag=%s label=%s\n", total, tag, label);
    return 0;
}
