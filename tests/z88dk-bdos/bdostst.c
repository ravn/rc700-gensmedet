/*
 * bdostst.c -- exercise the CP/M BDOS surface through z88dk's clib.
 *
 * Purpose: prove that a binary built by llvm-z88dk (zcc +cpm
 * -compiler=llvmz80) drives the RC702's real BDOS correctly for the
 * whole practical file-I/O surface -- with heavy emphasis on RANDOM
 * ACCESS, which is the part that is easy to get subtly wrong.
 *
 * Every check calls the ordinary clib entry points a C programmer would
 * use (stdio fopen/fread/fwrite/fseek/ftell/rename/remove, plus the
 * bdos() wrapper for system-info functions).  Under the hood z88dk's cpm
 * layer maps those onto the BDOS calls annotated below, so a green run
 * means the whole clib->BDOS path works on this machine.
 *
 * Output: one [PASS]/[FAIL] line per check to BOTH the console and a
 * durable log file BDOSTST.LOG on drive A: (extracted after the MAME run,
 * so nothing is lost to console scroll), then a compact final verdict
 * line that stays on the 24-row screen:  "VERDICT: n/m PASS  fails: ..."
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <cpm.h>
#include "cpm_clang_shim.h"   /* interim z88dk#20 clang bdos ABI shim */

/* Keep well clear of the default open-file limit (we hold the log open
 * while a second data file is open == 2 concurrent, +stdio streams). */
#pragma printf = "%s %d %u %02X %ld %lu"

static FILE *logfp;
static int   passc, failc;
static char  fails[96];          /* space-separated ids of failed checks */

/* Console line output via printf.  On this C-BIOS, raw BDOS 2 (CPM_WCON)
 * produces NO visible CRT output and fflush(stdout) HANGS, but printf is
 * line-buffered and flushes on the trailing '\n', so each whole line lands
 * on screen the instant it is produced -- a durable per-check trace that
 * survives even if a later check hangs the machine. */
static void cout(const char *s)
{
    printf("%s", s);
}

static void check(int id, int cond, const char *what)
{
    char line[64];
    sprintf(line, "%s %d %s\n", cond ? "[PASS]" : "[FAIL]", id, what);
    cout(line);
    if (logfp) fprintf(logfp, "%s", line);
    if (cond) {
        passc++;
    } else {
        failc++;
        char n[8];
        sprintf(n, "%d ", id);
        if (strlen(fails) + strlen(n) < sizeof(fails) - 1)
            strcat(fails, n);
    }
}

#define DATFILE "BDOSTST.DAT"
#define BAKFILE "BDOSTST.BAK"
#define SPRFILE "BDOSSPAR.DAT"
#define DATLEN  2000             /* spans >15 CP/M 128-byte records */
/* CP/M 2.2 files are RECORD-granular (128-byte). A byte length N occupies
 * ceil(N/128)*128 bytes on disk; the directory stores a record COUNT, not a
 * byte count. There is no byte-exact EOF and no sparse zero-fill. Size checks
 * below assert record-rounded sizes, not Unix byte-exact sizes. */
#define CPM_SECSIZE 128
#define CPM_RECROUND(n) ((((n) + CPM_SECSIZE - 1) / CPM_SECSIZE) * CPM_SECSIZE)

static unsigned char buf[DATLEN];

int main(void)
{
    FILE *f;
    long  sz;
    int   i, ok;
    int   ver, drv, usr, cst;

    logfp = fopen("BDOSTST.LOG", "w");   /* BDOS 22 make + 21 write later */

    cout("== llvm-z88dk BDOS/clib test ==\n");
    if (logfp) fprintf(logfp, "== llvm-z88dk BDOS/clib test ==\n");

    /* ---- Group A: system info via direct bdos() ------------------- */
    ver = bdos(CPM_VERS, 0) & 0xFF;      /* BDOS 12: version, 0x22 = 2.2 */
    check(1, ver != 0, "bdos12 version nonzero");

    drv = bdos(CPM_IDRV, 0) & 0xFF;      /* BDOS 25: current drive 0..15 */
    check(2, drv <= 15, "bdos25 current drive in range");

    cout("m3a\n");
    usr = getuid() & 0xFF;               /* BDOS 32: get user number     */
    cout("m3b\n");
    check(3, usr <= 15, "bdos32 user number in range");

    /* ---- Group B: direct console status (non-blocking) ------------ */
    cout("m4a\n");
    cst = bdos(CPM_DCIO, 0xFF) & 0xFF;   /* BDOS 6/0xFF: 0 if no key      */
    cout("m4b\n");
    check(4, cst == 0, "bdos6 console status (no key pending)");

    /* ---- Group C: sequential write then read back ----------------- */
    for (i = 0; i < DATLEN; i++) buf[i] = (unsigned char)(i & 0xFF);

    f = fopen(DATFILE, "wb");            /* BDOS 22 make                 */
    check(5, f != NULL, "fopen wb (create data file)");
    if (f) {
        int wrote = 0;
        for (i = 0; i < DATLEN; i++)                  /* BDOS 21 write   */
            if (fputc(buf[i], f) != EOF) wrote++;
        check(6, wrote == DATLEN, "write 2000 bytes");
        check(7, fclose(f) == 0, "fclose after write");   /* BDOS 16     */
    }

    memset(buf, 0, DATLEN);
    f = fopen(DATFILE, "rb");            /* BDOS 15 open                 */
    check(8, f != NULL, "fopen rb (reopen data file)");
    if (f) {
        int got = 0, c;
        for (i = 0; i < DATLEN; i++) {                /* BDOS 20 read    */
            c = fgetc(f);
            if (c == EOF) break;
            buf[i] = (unsigned char)c;
            got++;
        }
        check(9, got == DATLEN, "read 2000 bytes");
        ok = 1;
        for (i = 0; i < got; i++)           /* verify only bytes actually read */
            if (buf[i] != (unsigned char)(i & 0xFF)) { ok = 0; break; }
        check(10, ok && got == DATLEN, "sequential data verifies");

        /* file size via seek-to-end + ftell. CP/M 2.2 size is RECORD-granular:
         * 2000 B -> 16 records -> 2048 B. A byte-exact 2000 is impossible here. */
        check(11, fseek(f, 0, SEEK_END) == 0, "fseek SEEK_END");
        sz = ftell(f);
        check(12, sz == CPM_RECROUND(DATLEN), "ftell == 2048 (record-rounded)");
        fclose(f);
    }

    /* ---- Group D: RANDOM READ (absolute seeks) -> BDOS 33 ---------- */
    f = fopen(DATFILE, "rb");
    if (f) {
        /* Built at runtime (not rodata) so no .long directives are emitted. */
        int off[11];
        off[0]=0; off[1]=127; off[2]=128; off[3]=129; off[4]=255; off[5]=256;
        off[6]=777; off[7]=1500; off[8]=1999; off[9]=200; off[10]=1024;
        ok = 1;
        for (i = 0; i < 11; i++) {
            int c;
            if (fseek(f, (long)off[i], SEEK_SET) != 0) { ok = 0; break; }
            c = fgetc(f);
            if (c != (off[i] & 0xFF)) { ok = 0; break; }
        }
        check(13, ok, "random SEEK_SET reads (absolute offsets)");
        fclose(f);
    } else {
        check(13, 0, "random SEEK_SET reads (reopen failed)");
    }

    /* ---- Group E: RANDOM WRITE in place -> BDOS 34 ---------------- */
    f = fopen(DATFILE, "r+b");           /* update mode                  */
    check(14, f != NULL, "fopen r+b (update mode)");
    if (f) {
        int a, b, nbr, nba;
        fseek(f, 777L, SEEK_SET);  fputc(0xAA, f);
        fseek(f, 1234L, SEEK_SET); fputc(0x55, f);
        fclose(f);

        f = fopen(DATFILE, "rb");
        fseek(f, 777L, SEEK_SET);  a = fgetc(f);
        fseek(f, 1234L, SEEK_SET); b = fgetc(f);
        check(15, a == 0xAA && b == 0x55, "random writes read back");
        /* neighbours must be untouched (offset&0xFF pattern) */
        fseek(f, 776L, SEEK_SET);  nbr = fgetc(f);
        fseek(f, 1235L, SEEK_SET); nba = fgetc(f);
        check(16, nbr == (776 & 0xFF) && nba == (1235 & 0xFF),
              "neighbours of random writes intact");
        fclose(f);
    } else {
        check(15, 0, "random writes (r+b open failed)");
        check(16, 0, "neighbours intact (r+b open failed)");
    }

    /* ---- Group F: sparse / seek-past-EOF zero fill -> BDOS 40 ------ */
    f = fopen(SPRFILE, "wb");
    if (f) {
        fseek(f, 500L, SEEK_SET);   /* past end of empty file */
        fputc(0xEE, f);
        fclose(f);
        f = fopen(SPRFILE, "rb");
        fseek(f, 0, SEEK_END);
        sz = ftell(f);
        /* offset 500 lands in record 3 (bytes 384..511) -> 4 records = 512 B.
         * CP/M 2.2 is record-granular, so 501 is impossible; expect 512. */
        check(17, sz == CPM_RECROUND(501), "sparse size == 512 (record-rounded)");
        fseek(f, 250L, SEEK_SET);   /* inside the gap */
        i = fgetc(f);
        /* CP/M 2.2 does NOT zero-fill sparse gaps (unlike Unix): the intervening
         * unwritten records hold UNDEFINED content. Only assert the gap byte is
         * readable (record was allocated), not that it is zero. */
        check(18, i != EOF, "sparse gap readable (content undefined on CP/M 2.2)");
        fclose(f);
    } else {
        check(17, 0, "sparse create failed");
        check(18, 0, "sparse create failed");
    }

    /* ---- Group G: rename + delete -> BDOS 23 / 19 ----------------- */
    remove(BAKFILE);                     /* clean any stale copy         */
    check(19, rename(DATFILE, BAKFILE) == 0, "rename DAT -> BAK");
    f = fopen(DATFILE, "rb");
    check(20, f == NULL, "old name gone after rename");
    if (f) fclose(f);
    f = fopen(BAKFILE, "rb");
    check(21, f != NULL, "new name present after rename");
    if (f) fclose(f);

    check(22, remove(BAKFILE) == 0, "remove BAK");
    f = fopen(BAKFILE, "rb");
    check(23, f == NULL, "file gone after remove");
    if (f) fclose(f);
    remove(SPRFILE);

    /* ---- verdict ------------------------------------------------- */
    {
        char v[80];
        sprintf(v, "VERDICT: %d/%d PASS  fails: %s\n",
                passc, passc + failc, failc ? fails : "(none)");
        cout(v);
        if (logfp) {
            fprintf(logfp, "%s", v);
            fclose(logfp);
        }
    }
    return failc ? 1 : 0;
}
