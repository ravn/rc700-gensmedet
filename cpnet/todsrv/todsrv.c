/* todsrv.c -- master-side TOD responder for CP/NOS slaves.
 *
 * Runs under MP/M (or CP/M with CP/NET) on z80pack cpmsim, alongside
 * SERVER.RSP.  Listens for incoming CP/NET messages via BDOS function
 * 67 (RCVMSG), filters on FMT = 0x80, reads host wall time via cpmsim
 * ports 25/26, and replies via BDOS function 66 (SNDMSG) with FMT =
 * 0x81 and an ASCII date string payload.
 *
 * Build:  make
 * Output: TODSRV.COM (z88dk +cpm sccz80 -create-app).
 *
 * Wire format:
 *   Request:  FMT=0x80, DID=us, SID=requester, FNC=any, SIZ=0, MSG=(empty)
 *   Reply:    FMT=0x81, DID=requester, SID=us, FNC=(echo), SIZ=N-1,
 *             MSG = N-byte ASCII date string ("YYYY-MM-DD HH:MM:SS UTC\r\n")
 *
 * The slave (cpnos-in-c) iterates the reply payload through impl_conout
 * verbatim -- no parsing, no decoding, no SCB semantics.
 *
 * Architectural unknown: whether cpnet-z80's NDOS routes non-server
 * incoming messages to a user-space BDOS-67 caller before SERVER.RSP's
 * per-requester process intercepts them.  If TODSRV's BDOS 67 returns
 * with status indicating "no message" or "filtered out", we will need
 * to fall back to a tap.lua MITM or a host-side TCP responder.  This
 * program is the empirical test: install on mpm-net2, run, observe.
 */

#include <stdio.h>
#include <stdlib.h>     /* inp, outp */
#include <string.h>
#include <cpm.h>        /* bdos() */

#define CLKCMD          25
#define CLKDAT          26

/* CP/NET BDOS functions */
#define NSEND           66    /* SEND MESSAGE ON NETWORK */
#define NRECV           67    /* RECEIVE MESSAGE FROM NETWORK */
#define GETVER          12

#define FMT_REQ         0x80
#define FMT_RSP         0x81

#define MAX_MSG         128

/* CP/NET message header layout (5 bytes + payload). */
struct cpnet_msg {
    unsigned char fmt;
    unsigned char did;
    unsigned char sid;
    unsigned char fnc;
    unsigned char siz;
    unsigned char msg[MAX_MSG];
};

static struct cpnet_msg rxbuf;
static struct cpnet_msg txbuf;

static unsigned char rtc_read(unsigned char field)
{
    outp(CLKCMD, field);
    return (unsigned char)inp(CLKDAT);
}

/* Convert a BCD byte (high nibble = tens, low nibble = units; high may
 * exceed 9 per the cpmsim RTC's nibble-packing) to a 2-digit decimal
 * count in the range 0..159. */
static unsigned int decode_packed(unsigned char b)
{
    return ((b >> 4) & 0x0F) * 10u + (b & 0x0F);
}

/* Format ASCII date string into dst, terminated CR/LF.  Returns the
 * number of bytes written (not including any NUL). */
static unsigned int format_date(char *dst)
{
    unsigned char sec, min, hr, dl, dh, dom, mon, yr;
    unsigned int days, year_full;

    sec = rtc_read(0);
    min = rtc_read(1);
    hr  = rtc_read(2);
    dl  = rtc_read(3);
    dh  = rtc_read(4);
    dom = rtc_read(5);
    mon = rtc_read(6);
    yr  = rtc_read(7);
    (void)days; (void)dl; (void)dh;
    days = ((unsigned int)dh << 8) | dl;
    year_full = 1900 + decode_packed(yr);

    /* "YYYY-MM-DD HH:MM:SS UTC\r\n" (no NUL, 25 bytes incl. CR/LF).
     * mon is 0-indexed in tm_mon, so +1 for display.  All time fields
     * are BCD (00-59 for sec/min, 00-23 for hr) and fit clean printf
     * %02x; year already decoded. */
    sprintf(dst,
            "%u-%02u-%02x %02x:%02x:%02x UTC\r\n",
            year_full,
            (unsigned int)(decode_packed(mon) + 1),
            dom, hr, min, sec);
    return (unsigned int)strlen(dst);
}

int main(void)
{
    unsigned int ver;
    unsigned int reply_len;

    /* Check that CP/NET is loaded.  GETVER returns BDOS version in HL;
     * bit 1 of the high byte indicates CP/NET presence (per CP/NET 1.2
     * Reference Manual). */
    ver = (unsigned int)bdos(GETVER, 0);
    if ((ver & 0x0200) == 0) {
        printf("TODSRV: CP/NET not detected (BDOS version %04x)\r\n", ver);
        return 1;
    }

    printf("TODSRV: listening for FMT 0x%02x requests on CP/NET\r\n",
           FMT_REQ);
    printf("TODSRV: will reply with FMT 0x%02x + ASCII date string\r\n",
           FMT_RSP);

    for (;;) {
        /* Receive a message via BDOS 67.  Whether this actually delivers
         * non-server-FMT messages to user-space is the open question. */
        memset(&rxbuf, 0, sizeof rxbuf);
        if (bdos(NRECV, (int)&rxbuf) != 0) {
            /* Non-zero return = error.  Be patient -- this might fire
             * if the NDOS is configured to deliver-or-error rather
             * than block.  In that case we'd want a back-off here. */
            continue;
        }
        if (rxbuf.fmt != FMT_REQ) {
            /* Not a TOD request -- shouldn't happen if NDOS filters
             * correctly, but skip just in case. */
            continue;
        }

        /* Build the reply. */
        txbuf.fmt = FMT_RSP;
        txbuf.did = rxbuf.sid;          /* back to original sender */
        txbuf.sid = rxbuf.did;          /* us */
        txbuf.fnc = rxbuf.fnc;          /* echo FNC */
        reply_len = format_date((char *)txbuf.msg);
        txbuf.siz = (unsigned char)(reply_len - 1);  /* CP/NET SIZ encoding: N-1 */

        if (bdos(NSEND, (int)&txbuf) != 0) {
            printf("TODSRV: NSEND error\r\n");
            /* Soldier on. */
        }
    }
    /* not reached */
}
