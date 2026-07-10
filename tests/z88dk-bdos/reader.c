/*
 * reader.c -- isolation half B (built with sccz80, the KNOWN-GOOD compiler).
 *
 * Reads WO.DAT (written by the clang writer.c on the same disk) and prints the
 * bytes it finds.  No clang shims are involved on this side, so its result is a
 * trustworthy oracle for what actually landed on disk:
 *   "R bytes=65 66 67 n=3"  -> clang WRITE is correct; bug is the clang READ path
 *   "R bytes= n=0" / open FAIL -> clang WRITE is broken (empty/missing file)
 */
#include <stdio.h>

#pragma printf = "%s %d"

#define FN "WO.DAT"

int main(void)
{
    FILE *f;
    int c, n;

    printf("R1 start\n");
    f = fopen(FN, "rb");
    printf("R2 fopen=%d\n", f != NULL);
    if (!f) { printf("R FAIL open\n"); return 1; }
    printf("R bytes=");
    n = 0;
    while ((c = fgetc(f)) != -1) { printf("%d ", c); n++; }
    printf("n=%d\n", n);
    fclose(f);
    printf("R done\n");
    return 0;
}
