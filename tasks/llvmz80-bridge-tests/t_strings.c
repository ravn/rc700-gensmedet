// EXPECT: alpha|beta|gamma|delta
// Family 2: string literals become private globals L_.str, L_.str.1,
// L_.str.2, ... (up to 2 dots).  copt's literal `L_.str` rule only handled the
// zero-suffix case; the .N variants relied on fixlabels' dot translation.
#include <stdio.h>

int main(void) {
    const char *w0 = "alpha";   // -> L_.str
    const char *w1 = "beta";    // -> L_.str.1
    const char *w2 = "gamma";   // -> L_.str.2
    const char *w3 = "delta";   // -> L_.str.3
    printf("%s|%s|%s|%s\n", w0, w1, w2, w3);
    return 0;
}
