/*
 * writer.c -- isolation half A (built with clang/llvm-z88dk).
 *
 * Writes a known 3-byte payload "ABC" to WO.DAT and exits WITHOUT reading it
 * back.  A separate, known-good sccz80 reader (reader.c) reads WO.DAT on the
 * same disk.  This localizes the clang file bug to the WRITE path vs the READ
 * path, and removes the clang read shims from the verification half.
 */
#include <stdio.h>
#include "cpm_clang_shim.h"   /* clang ABI shims (z88dk#20,#22); inert on sccz80 */

#pragma printf = "%s %d"

#define FN "WO.DAT"

int main(void)
{
    FILE *f;

    printf("W1 start\n");
    f = fopen(FN, "wb");
    printf("W2 fopen=%d\n", f != NULL);
    if (!f) { printf("W FAIL open\n"); return 1; }
    fputc('A', f);
    fputc('B', f);
    fputc('C', f);
    printf("W3 put3\n");
    fclose(f);
    printf("W4 closed\n");
    return 0;
}
