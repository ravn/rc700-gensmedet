/* qsort_disk.c -- random-access disk file regression for cpnos / CP/NET.
 *
 * Sorts NREC fixed 128-byte records IN PLACE ON DISK with an iterative
 * quicksort.  Every comparison and every swap touches the file through the
 * CP/M random-record BDOS calls F_READRAND (33) / F_WRITERAND (34) -- under
 * cpnos those travel over CP/NET to the MP/M master's disk.  This is the
 * random-access counterpart to the sequential FILECOPY test.
 *
 * Raw 36-byte FCB + direct bdos() (not stdio): z88dk classic stdio cannot
 * random-write an existing file ("rb+" fwrite returns 0), and F_READRAND/
 * F_WRITERAND are exactly what a random-access test should exercise anyway.
 *
 * Record layout (self-verifying): record for key k has
 *     rec[j] = (unsigned char)(k + j)   for j = 0 .. 127
 * so rec[0] == k and every other byte is a deterministic function of the key.
 * After sorting we read every record back and check BOTH that the keys are
 * strictly ascending AND that each record's 128 bytes still match its key --
 * catching torn / mis-addressed random writes, not just wrong order.
 *
 * Initial on-disk order is the permutation key[i] = (i*5 + 13) mod NREC
 * (5 is coprime to 32, so keys 0..NREC-1 each appear once, well mixed).
 *
 * Output (console; mirrored to SIO-B under cpnos MIRROR_SIOB):
 *     "QSORT OK <NREC>"      on success
 *     "QSORT FAIL <reason>"  otherwise
 *
 * Built through zcc +cpm for both classic (sccz80) and clang (llvmz80);
 * <cpm.h> supplies bdos() and the CPM_* function codes for both.
 */
#include <stdio.h>
#include <cpm.h>

#define NREC   32
#define RECSZ  128

#define F_DELETE   19
#define F_MAKE     22
#define F_OPEN     15
#define F_CLOSE    16
#define F_SETDMA   26
#define F_READRAND 33
#define F_WRITERAND 34

/* raw 36-byte FCB: drive, "QSORT   DAT", then zeroed control fields.
 * bytes 33..35 (ranrec) are set per random op. */
static unsigned char fcb[36] = {
    0,
    'Q','S','O','R','T',' ',' ',' ',
    'D','A','T',
    0, 0, 0, 0,
    0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,   /* disk map (16) */
    0,                                   /* current record */
    0, 0, 0                              /* r0, r1, r2 */
};

static unsigned char pv[RECSZ];   /* pivot record         */
static unsigned char ea[RECSZ];   /* swap scratch A / seed*/
static unsigned char eb[RECSZ];   /* element / swap B     */

static int lo_stk[NREC + 2];
static int hi_stk[NREC + 2];

static void make_rec(unsigned char *r, unsigned char k)
{
    int j;
    for (j = 0; j < RECSZ; j++)
        r[j] = (unsigned char)(k + j);
}

static void set_ranrec(int i)
{
    fcb[33] = (unsigned char)(i & 0xFF);
    fcb[34] = (unsigned char)((i >> 8) & 0xFF);
    fcb[35] = 0;
}

/* read record i into buf; return 1 on success (BDOS ret 0) */
static int get_rec(int i, unsigned char *buf)
{
    bdos(F_SETDMA, (int)buf);
    set_ranrec(i);
    return bdos(F_READRAND, (int)fcb) == 0;
}

/* write buf to record slot i; return 1 on success */
static int put_rec(int i, unsigned char *buf)
{
    bdos(F_SETDMA, (int)buf);
    set_ranrec(i);
    return bdos(F_WRITERAND, (int)fcb) == 0;
}

static int swap_recs(int a, int b)
{
    if (!get_rec(a, ea)) return 0;
    if (!get_rec(b, eb)) return 0;
    if (!put_rec(a, eb)) return 0;
    if (!put_rec(b, ea)) return 0;
    return 1;
}

int main(void)
{
    int i, sp, lo, hi, ii, jj;
    unsigned char pivotkey, prevkey;

    /* fresh file */
    bdos(F_DELETE, (int)fcb);
    if (bdos(F_MAKE, (int)fcb) == 0xFF) { printf("QSORT FAIL make\r\n"); return 1; }

    /* 1. seed NREC records in permuted key order (random write) */
    for (i = 0; i < NREC; i++) {
        make_rec(ea, (unsigned char)((i * 5 + 13) % NREC));
        if (!put_rec(i, ea)) { printf("QSORT FAIL seed %d\r\n", i); return 1; }
    }

    /* 2. in-place quicksort on disk (iterative, Lomuto, last-elem pivot) */
    sp = 0;
    lo_stk[sp] = 0; hi_stk[sp] = NREC - 1; sp++;
    while (sp > 0) {
        sp--; lo = lo_stk[sp]; hi = hi_stk[sp];
        while (lo < hi) {
            if (!get_rec(hi, pv)) { printf("QSORT FAIL rd-pivot\r\n"); return 1; }
            pivotkey = pv[0];
            ii = lo;
            for (jj = lo; jj < hi; jj++) {
                if (!get_rec(jj, eb)) { printf("QSORT FAIL rd-elem\r\n"); return 1; }
                if (eb[0] <= pivotkey) {
                    if (ii != jj && !swap_recs(ii, jj)) { printf("QSORT FAIL swap\r\n"); return 1; }
                    ii++;
                }
            }
            if (ii != hi && !swap_recs(ii, hi)) { printf("QSORT FAIL swap-pivot\r\n"); return 1; }
            if (ii - lo < hi - ii) {
                if (lo <= ii - 1) { lo_stk[sp] = lo;     hi_stk[sp] = ii - 1; sp++; }
                lo = ii + 1;
            } else {
                if (ii + 1 <= hi) { lo_stk[sp] = ii + 1; hi_stk[sp] = hi;     sp++; }
                hi = ii - 1;
            }
        }
    }

    /* 3. verify: strictly ascending keys AND intact record bytes */
    prevkey = 0;
    for (i = 0; i < NREC; i++) {
        unsigned char k;
        int j;
        if (!get_rec(i, ea)) { printf("QSORT FAIL rd-verify\r\n"); return 1; }
        k = ea[0];
        for (j = 1; j < RECSZ; j++) {
            if (ea[j] != (unsigned char)(k + j)) {
                printf("QSORT FAIL torn rec %d\r\n", i); return 1;
            }
        }
        if (i > 0 && k <= prevkey) { printf("QSORT FAIL order %d\r\n", i); return 1; }
        prevkey = k;
    }

    bdos(F_CLOSE, (int)fcb);
    bdos(F_DELETE, (int)fcb);
    printf("QSORT OK %d\r\n", NREC);
    return 0;
}
