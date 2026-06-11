/* rtctod.c -- read host RTC via z80pack cpmsim ports 25/26 and print.
 *
 * Runs under CP/M (or MP/M) on a z80pack cpmsim machine.  Demonstrates
 * the bypass path that issue #106's TODSRV.COM uses: read host wall
 * time directly from CLKCMD/CLKDAT, no BDOS 105, no SCB, no MP/M
 * XIOS fix required.
 *
 * Build with z88dk:
 *   make
 * Output: RTCTOD.COM (z88dk +cpm sccz80 -create-app).
 *
 * Host port handler: z80pack/iodevices/rtc80.c
 *
 * Sub-fields exposed by writing the selector to port 25 (CLKCMD) and
 * reading the value back from port 26 (CLKDAT):
 *   0 = seconds         5 = day of month
 *   1 = minutes         6 = month
 *   2 = hours           7 = year (years-since-1900, packed; see below)
 *   3 = days-since-1978-01-01 low byte
 *   4 = days-since-1978-01-01 high byte
 *
 * Default format is BCD; the host RTC supports a decimal mode toggled
 * by writing 255 to CLKCMD.  This program assumes default BCD on
 * entry and does NOT toggle.
 *
 * Year encoding: the year sub-field is computed by the host as
 * to_bcd(tm_year) where tm_year is years-since-1900.  The host's
 * to_bcd packs (val/10) into the HIGH nibble and (val%10) into the
 * LOW nibble.  For 1900-1999 the high nibble is 0-9 (clean BCD);
 * for 2000-2059 the high nibble takes values 10-15 (A-F), which is
 * still lossless and decodes as years-since-1900 = (high*10 + low).
 * Years >= 2060 (tm_year >= 160) overflow the high nibble and wrap.
 *
 * (The comment at iodevices/rtc80.c:45-47 calls the post-1999 form a
 * "Y2K bug" but it's better thought of as a not-strictly-BCD packing
 * that happens to remain decodable through 2059.)
 */

#include <stdio.h>
#include <stdlib.h>     /* inp, outp */

#define CLKCMD  25
#define CLKDAT  26

static unsigned char rtc_read(unsigned char field)
{
    outp(CLKCMD, field);
    return (unsigned char)inp(CLKDAT);
}

/* Decode a "BCD" byte from the host where the high nibble may exceed
 * 9 (representing tens-of-years 10..15 for years 2000..2059). */
static unsigned int decode_packed(unsigned char b)
{
    return ((b >> 4) & 0x0F) * 10u + (b & 0x0F);
}

int main(void)
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

    days = ((unsigned int)dh << 8) | dl;
    year_full = 1900 + decode_packed(yr);

    printf("rtctod -- host RTC via cpmsim ports 25/26\r\n");
    printf("Time (HH:MM:SS BCD):       %02x:%02x:%02x\r\n", hr, min, sec);
    printf("Date (YYYY MM DD BCD):     %u %02x %02x\r\n",
           year_full, mon, dom);
    printf("  (mon is 0-indexed from host's tm_mon: Jan=00, Jun=05)\r\n");
    printf("Days since 1978-01-01:     %u  (16-bit, wraps 2157-06-06)\r\n",
           days);
    return 0;
}
