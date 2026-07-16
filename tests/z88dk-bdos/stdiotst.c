/*
 * stdiotst.c -- standard-library file-I/O exerciser for a program built by
 * llvm-z88dk (zcc +cpm -compiler=llvmz80), run on the REAL RC702 BDOS via MAME.
 *
 * Complements bdostst.c (which drives the surface via fputc/fgetc) by using the
 * BLOCK primitives fread/fwrite.  It exercises ONLY standard C stdio semantics
 * that CP/M 2.2 actually implements -- write data, read it back, seek, measure
 * size, overwrite existing bytes in place, rename, remove -- and compares the
 * result against KNOWN content (i&0xFF pattern via memcmp).  It deliberately
 * does NOT probe Unix-only behaviour that CP/M 2.2 does not provide (sparse
 * zero-fill of unwritten gaps: gap content is unspecified on CP/M 2.2).
 *
 * There is no ISO C "file size" call, so size is taken with fseek(SEEK_END)+
 * ftell (record-granular on CP/M 2.2, so it rounds up to a 128-byte multiple).
 *
 * Output mirrors bdostst.c: per-check "[PASS]/[FAIL] n desc" to the console
 * (printf is line-buffered on this C-BIOS; do NOT fflush -- it hangs) and to a
 * durable STDIOT.LOG, then a scroll-proof "VERDICT: n/m PASS  fails: ..." line.
 */
#include <stdio.h>
#include <string.h>

#pragma printf = "%s %d %u %02X %ld"

#define DATFILE "STDIOT.DAT"
#define BAKFILE "STDIOT.BAK"
#define LEN     2000              /* > 15 CP/M 128-byte records            */
#define SECSIZE 128
#define RECROUND(n) ((((n)+SECSIZE-1)/SECSIZE)*SECSIZE)

static unsigned char wbuf[LEN];
static unsigned char rbuf[LEN];

static FILE *logfp;
static int   passc, failc;
static char  fails[96];

static void check(int id, int cond, const char *what)
{
    char line[64];
    sprintf(line, "%s %d %s\n", cond ? "[PASS]" : "[FAIL]", id, what);
    printf("%s", line);
    if (logfp) fprintf(logfp, "%s", line);
    if (cond) { passc++; }
    else {
        failc++;
        char n[8]; sprintf(n, "%d ", id);
        if (strlen(fails) + strlen(n) < sizeof(fails) - 1) strcat(fails, n);
    }
}

int main(void)
{
    FILE  *f;
    long   sz;
    int    i, ok;
    size_t n;

    for (i = 0; i < LEN; i++) wbuf[i] = (unsigned char)(i & 0xFF);
    fails[0] = 0;

    logfp = fopen("STDIOT.LOG", "w");
    printf("== llvm-z88dk stdio block/random test ==\n");
    if (logfp) fprintf(logfp, "== llvm-z88dk stdio block/random test ==\n");

    /* ---- block write via fwrite, block read via fread -------------- */
    f = fopen(DATFILE, "wb");
    check(1, f != NULL, "fopen wb");
    if (f) {
        n = fwrite(wbuf, 1, LEN, f);
        check(2, n == (size_t)LEN, "fwrite LEN bytes");
        check(3, fclose(f) == 0, "fclose after write");
    }

    memset(rbuf, 0xFF, LEN);
    f = fopen(DATFILE, "rb");
    check(4, f != NULL, "fopen rb");
    if (f) {
        n = fread(rbuf, 1, LEN, f);
        check(5, n == (size_t)LEN, "fread LEN bytes");
        check(6, memcmp(wbuf, rbuf, LEN) == 0, "fread data == known content");
        check(7, fseek(f, 0L, SEEK_END) == 0, "fseek SEEK_END");
        sz = ftell(f);
        check(8, sz == RECROUND(LEN), "ftell size record-rounded (2048)");
        fclose(f);
    }

    /* ---- random access: overwrite existing bytes, read them back --- */
    /* r+b + fseek + fwrite overwrites bytes that already exist (no hole  */
    /* creation), which is well-defined on CP/M 2.2.                      */
    f = fopen(DATFILE, "r+b");
    check(9, f != NULL, "fopen r+b (update)");
    if (f) {
        unsigned char a = 0xAA, b = 0x55, g;
        ok = 1;
        if (fseek(f, 777L,  SEEK_SET) != 0 || fwrite(&a, 1, 1, f) != 1) ok = 0;
        if (fseek(f, 1234L, SEEK_SET) != 0 || fwrite(&b, 1, 1, f) != 1) ok = 0;
        check(10, ok, "random fwrite at 777 and 1234");
        fclose(f);

        f = fopen(DATFILE, "rb");
        ok = 1;
        fseek(f, 777L,  SEEK_SET); if (fread(&g,1,1,f)!=1 || g!=0xAA) ok = 0;
        fseek(f, 1234L, SEEK_SET); if (fread(&g,1,1,f)!=1 || g!=0x55) ok = 0;
        check(11, ok, "random fread reads updated bytes back");
        fclose(f);
    }

    /* ---- rename then remove --------------------------------------- */
    check(12, rename(DATFILE, BAKFILE) == 0, "rename DAT -> BAK");
    check(13, fopen(DATFILE, "rb") == NULL, "old name gone after rename");
    f = fopen(BAKFILE, "rb");
    check(14, f != NULL, "new name present after rename");
    if (f) fclose(f);
    check(15, remove(BAKFILE) == 0, "remove BAK");
    check(16, fopen(BAKFILE, "rb") == NULL, "removed file is gone");

    {
        char v[80];
        sprintf(v, "VERDICT: %d/%d PASS  fails: %s\n", passc, passc + failc,
                failc ? fails : "(none)");
        printf("%s", v);
        if (logfp) { fprintf(logfp, "%s", v); fclose(logfp); }
    }
    return failc ? 1 : 0;
}
