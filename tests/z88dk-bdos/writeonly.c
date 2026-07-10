/*
 * writeonly.c -- minimal repro for the llvm-z88dk CP/M file-WRITE bug.
 *
 * Under -compiler=llvmz80 (clang), fopen("wb")+fputc+fclose appears to issue
 * NO BDOS make(22)/write(21) and hangs at fclose; the same source works under
 * -compiler=sccz80. This isolates the write path from the 23-check test.
 *
 * Build:  zcc +cpm -compiler=llvmz80 --opt-code-size writeonly.c ... -create-app
 *     or  zcc +cpm -compiler=sccz80  --opt-code-size writeonly.c    -create-app
 */
#include <stdio.h>
#include "cpm_clang_shim.h"   /* interim clang ABI shim (z88dk#20, #22); inert on sccz80 */

#pragma printf = "%s %d"

#define FN "WO.DAT"

int main(void)
{
    FILE *f;

    printf("A start\n");
    f = fopen(FN, "wb");
    printf("B fopen=%d\n", f != NULL);
    if (!f) { printf("Z open FAIL\n"); return 1; }
    fputc('X', f);
    printf("C after fputc\n");
    fclose(f);
    printf("D after fclose\n");

    f = fopen(FN, "rb");
    printf("E reopen=%d\n", f != NULL);
    if (f) { printf("F byte=%d\n", fgetc(f)); fclose(f); }
    remove(FN);
    printf("VERDICT done\n");
    return 0;
}
