// EXPECT: sum=20 hits=5
// Family 1: basic-block labels .LBB0_N appear both as definitions (`.LBB0_2:`)
// and in operands of conditional jumps (`jr z,.LBB0_6`).  copt strips the
// leading dot on a standalone token; the comma-glued operand form is covered
// by the leading-wildcard rule / fixlabels.  Loops + a branch exercise both.
#include <stdio.h>

int main(void) {
    int sum = 0, hits = 0;
    for (int i = 0; i < 5; i++) {   // 0+1+2+3+4 = 10, hits = 5
        sum += i;
        hits++;
    }
    for (int i = 0; i < 5; i++) {   // +2 five times -> +10 -> 20
        if (sum < 100) sum += 2;    // conditional -> .LBB operand jump
    }
    printf("sum=%d hits=%d\n", sum, hits);
    return 0;
}
