/*
 * probe.c -- raw fcntl-layer probe for the clang CP/M write bug.
 *
 * Bypasses stdio (fopen/fputc/fclose) AND the clang stdio shims entirely.
 * Calls the low-level open()/write()/close() directly -- these are pure C
 * (code_compiler) whose internal bdos() calls the disassembly shows are
 * correctly stack-marshalled.  Prints every return value so we can see exactly
 * where the write path fails.
 *
 * Expected (working): open fd>=0, write=1, close=0, then a fresh open("rb")-
 * equivalent (O_RDONLY) fd>=0 and read=1 byte 'X'.
 */
#include <stdio.h>
#include <fcntl.h>
#include "cpm_clang_shim.h"   /* only bdos()/stdio macros; open/write/close untouched */

#pragma printf = "%s %d"

#define FN "WP.DAT"

int main(void)
{
    int fd, r;
    char buf[1];

    printf("P1 start\n");
    fd = open(FN, O_WRONLY | O_TRUNC | O_CREAT, 0);
    printf("P2 open(w)=%d\n", fd);
    if (fd < 0) { printf("P open FAIL\n"); return 1; }
    buf[0] = 'X';
    r = write(fd, buf, 1);
    printf("P3 write=%d\n", r);
    r = close(fd);
    printf("P4 close=%d\n", r);

    fd = open(FN, O_RDONLY, 0);
    printf("P5 open(r)=%d\n", fd);
    if (fd >= 0) {
        buf[0] = 0;
        r = read(fd, buf, 1);
        printf("P6 read=%d byte=%d\n", r, buf[0]);
        close(fd);
    }
    printf("P done\n");
    return 0;
}
