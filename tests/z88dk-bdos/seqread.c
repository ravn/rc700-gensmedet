/*
 * seqread.c -- minimal repro for a z88dk classic CP/M sequential-read bug.
 *
 * Writes N (=300) bytes to a file, closes it, reopens "rb" and reads back
 * byte-by-byte with fgetc() until EOF. On CP/M the file is record-granular
 * (128-byte), so 300 bytes occupy 3 records (384 B) and a sequential read
 * should return all 300 written bytes.
 *
 * OBSERVED (RC702, CP/M 2.2, z88dk classic clib, both sccz80 and llvmz80):
 *   sequential fgetc() returns EOF after exactly 128 bytes (one record),
 *   even though random access (fseek to any offset < N + fgetc) returns the
 *   correct byte. So the data IS on disk; only the sequential record-0 -> 1
 *   advance path fails (read.c len==1 -> cpm_cache_get() BDOS 33 read-random
 *   of record 1 returns error -> read()=0 -> false EOF).
 *
 * Build:  zcc +cpm -compiler=sccz80  --opt-code-size seqread.c -o seqread -create-app
 *     or  zcc +cpm -compiler=llvmz80 --opt-code-size seqread.c -o seqread -create-app
 */
#include <stdio.h>

#pragma printf = "%s %d"

#define FN  "SEQR.DAT"
#define N   300

int main(void)
{
    FILE *f;
    int i, c, got, rnd;

    /* write N bytes: value = index & 0xFF */
    f = fopen(FN, "wb");
    if (!f) { printf("open-w FAIL\n"); return 1; }
    for (i = 0; i < N; i++) fputc(i & 0xFF, f);
    fclose(f);

    /* sequential read-back: capture full pattern, do NOT stop at first bad byte */
    f = fopen(FN, "rb");
    if (!f) { printf("open-r FAIL\n"); return 1; }
    /* WORKAROUND: an explicit fseek(f,0,SEEK_SET) here makes SEQ read
     * correctly -- it sets rnr_dirty and forces the record cache to reload.
     * Without it the first sequential read serves a STALE FCB buffer. */
    got = 0;
    {
        static unsigned char sq[N];
        int nread = 0;
        for (i = 0; i < N; i++) {
            c = fgetc(f);
            if (c == EOF) break;
            sq[i] = (unsigned char)c;
            nread++;
        }
        for (i = 0; i < nread; i++) if (sq[i] == (i & 0xFF)) got++;
        printf("SEQ nread=%d matches=%d\n", nread, got);
        printf("SEQ[42..48]=%d %d %d %d %d %d %d\n",
               sq[42], sq[43], sq[44], sq[45], sq[46], sq[47], (nread>48?sq[48]:-1));
    }

    /* control: full random-access verify (isolates write from seq-read) */
    rnd = 0;
    for (i = 0; i < N; i++) {
        if (fseek(f, (long)i, SEEK_SET) != 0) { printf("RND seek FAIL at %d\n", i); break; }
        c = fgetc(f);
        if (c != (i & 0xFF)) { printf("RND MISMATCH at %d got=%d\n", i, c); break; }
        rnd++;
    }
    printf("RND ok=%d expected=%d\n", rnd, N);
    fclose(f);

    remove(FN);
    printf("VERDICT: %s  fails: %s\n",
           (got == N && rnd == N) ? "PASS" : "FAIL",
           (got == N && rnd == N) ? "none" : "seqread");
    return 0;
}
