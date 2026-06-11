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

    /* Read BDOS version word from HL.  z88dk's bdosh() (not bdos())
     * returns the full HL pair, with H = system type byte (bit 1 set
     * means CP/NET present) and L = version byte (0x22 = CP/M 2.2). */
    ver = (unsigned int)bdosh(GETVER, 0);
    printf("TODGET: BDOS version = 0x%04x (CP/NET = %s)\r\n",
           ver, (ver & 0x0200) ? "yes" : "NO");
    if ((ver & 0x0200) == 0) {
        printf("TODGET: no CP/NET; cannot send FN 105\r\n");
        return 1;
    }

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

    /* z88dk's bdos()/bdosh() both surface HL on return, but cpnos's
     * NDOS handler for BDOS-66/67 (NSEND/NRECV) only sets A — HL is
     * left over from the previous BDOS call.  Drop the return-value
     * checks and validate via the reply buffer instead (FMT=0x01
     * means the master sent a response). */
    (void)bdos(NSEND, (int)msg);
    (void)bdos(NRECV, (int)msg);
    if (msg[0] != 0x01) {
        printf("TODGET: no response (FMT=%02x)\r\n", msg[0]);
        return 2;
    }

    printf("TODGET: reply FMT=%02x DID=%02x SID=%02x FNC=%d SIZ=%d (%d bytes)\r\n",
           msg[0], msg[1], msg[2], msg[3], msg[4], msg[4] + 1);

    printf("TODGET: payload hex: ");
    for (i = 0; i <= msg[4] && i < 32; i++) {
        printf("%02x ", msg[5 + i]);
    }
    printf("\r\n");

    /* Decode the gettod payload (SIZ=25 = 26 byte reply):
     *   MSG[0..1] = days since MP/M epoch (1978-01-01), little-endian
     *   MSG[2..4] = hr / min / sec, each BCD-packed
     *   MSG[5..25] = ASCII "YYYY-MM-DD HH:MM:SS\r\n" (21 bytes)
     * The binary fields and the ASCII string carry the same instant;
     * the ASCII is already human-readable so we print it as-is, and
     * the binary fields are decoded to confirm them.
     */
    if (msg[4] >= 25) {
        unsigned int days;
        unsigned char hr, mn, sc, j;

        days = (unsigned int)msg[5] | ((unsigned int)msg[6] << 8);
        /* BCD -> decimal: high nibble * 10 + low nibble */
        hr = ((msg[7] >> 4) & 0x0F) * 10 + (msg[7] & 0x0F);
        mn = ((msg[8] >> 4) & 0x0F) * 10 + (msg[8] & 0x0F);
        sc = ((msg[9] >> 4) & 0x0F) * 10 + (msg[9] & 0x0F);

        printf("TODGET: binary  : days=%u (since 1978-01-01) %02u:%02u:%02u\r\n",
               days, hr, mn, sc);

        /* ASCII portion: msg[10..30] = "YYYY-MM-DD HH:MM:SS\r\n".
         * Print until CR/LF/EOF so the line is clean. */
        printf("TODGET: master  : ");
        for (j = 10; j <= 30; j++) {
            unsigned char c = msg[j];
            if (c == '\r' || c == '\n' || c < 0x20 || c >= 0x7F) break;
            putchar(c);
        }
        printf("\r\n");
    }

    return 0;
}
