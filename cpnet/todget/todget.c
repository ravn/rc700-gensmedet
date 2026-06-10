/* todget.c -- query master for time-of-day via CP/NET FN 105.
 *
 * Runs on the cpnos slave after boot.  Sends FN 105 to the master and
 * prints the reply payload (binary 5 bytes hex + 21-byte ASCII date).
 *
 * Build with z88dk:  make
 * Install on cpnos master disk (D: of mpm-net2), run from E>.
 *
 * Tests the patched SERVER.RSP gettod extension via the slave's full
 * NDOS BDOS 66/67 path (different code path from cpnos boot which
 * uses bare snios primitives).
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <cpm.h>

#define NSEND   66
#define NRECV   67
#define GETVER  12

#define SERVER_DID 0

/* CP/NET message buffer.  Layout matches DRI:
 *   [0] FMT  [1] DID  [2] SID  [3] FNC  [4] SIZ  [5..] DAT */
static unsigned char msg[256];

int main(void)
{
    unsigned int ver;
    unsigned char i, our_sid;

    /* Diagnostic banner: confirms main() reached before any BDOS call. */
    printf("TODGET starting...\r\n");

    /* BDOS-12 version check skipped: z88dk's bdos() returns only A, so
     * we can't see the CP/NET bit (in H) without inline asm.  The asm
     * probe2 test confirmed BDOS reports HL=0x0222 (CP/M 2.2 + CP/NET
     * bit) on this hardware.  Just proceed. */
    (void)ver;

    /* Our slave NID: from the SCB-style network config.  cpnos's
     * default RC702_SLAVEID is 0x01; let's just use that. */
    our_sid = 0x01;

    /* Build FN 105 request */
    msg[0] = 0x00;            /* FMT request */
    msg[1] = SERVER_DID;       /* DID = master */
    msg[2] = our_sid;          /* SID = us */
    msg[3] = 105;              /* FNC = Get Time/Date */
    msg[4] = 0x00;             /* SIZ = 0 (1 byte payload) */
    msg[5] = 0x00;             /* MSG[0] dummy */

    printf("TODGET: sending FMT=%02x DID=%02x SID=%02x FNC=%d SIZ=%d\r\n",
           msg[0], msg[1], msg[2], msg[3], msg[4]);

    /* z88dk's bdos() doesn't reliably surface A; just call and check
     * the round-trip outcome below by reading the reply buffer. */
    (void)bdos(NSEND, (int)msg);
    (void)bdos(NRECV, (int)msg);

    printf("TODGET: reply FMT=%02x DID=%02x SID=%02x FNC=%d SIZ=%d (%d bytes)\r\n",
           msg[0], msg[1], msg[2], msg[3], msg[4], msg[4] + 1);

    printf("TODGET: payload hex: ");
    for (i = 0; i <= msg[4] && i < 32; i++) {
        printf("%02x ", msg[5 + i]);
    }
    printf("\r\n");

    /* If reply size suggests our 26-byte gettod response (SIZ=25),
     * print the ASCII portion starting at offset 5. */
    if (msg[4] >= 25) {
        printf("TODGET: ASCII: ");
        for (i = 5; i <= msg[4]; i++) {
            unsigned char c = msg[5 + i];
            if (c >= 0x20 && c < 0x7F) putchar(c);
            else if (c == '\r') printf("\\r");
            else if (c == '\n') printf("\\n");
            else printf("[%02x]", c);
        }
        printf("\r\n");
    }

    return 0;
}
