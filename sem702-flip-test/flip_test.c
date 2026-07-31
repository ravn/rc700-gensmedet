/* SEM702 flip test (rc702sem702).
 *
 * 1. Load the ROA296 letter font into the SEM702 RAM chargen (0xD1/0xD2/0xD3).
 * 2. Switch the console to semigraphics mode (BIOS control code 0x84) so the
 *    following characters are rendered from the SEM702 (GPA0=1), print A-Z /
 *    a-z / 0-9, switch back (0x80).  -> screenshot A: upright letters.
 * 3. Reprogram the SEM702 with the same font flipped top-to-bottom.  The
 *    already-printed characters re-render each frame from m_sem702_ram, so
 *    they flip in place.  -> screenshot B: upside-down letters.
 *
 * marker at 0xBF00: 1 = phase A ready, 2 = phase B ready (for the MAME lua).
 */
#include <cpm.h>
#include <arch/z80.h>
#include "font296.h"

#define SEM_CHAR 0xD1
#define SEM_LINE 0xD2
#define SEM_DATA 0xD3
#define CELL_LINES 11               /* 8275 shows 11 dot-lines per char */
#define MARKER (*(volatile unsigned char *)0xBF00)

static void conout(unsigned char ch) { bdos(2, ch); }

/* Program the SEM702 with font296; when flip != 0, mirror lines 0..CELL_LINES-1. */
static void load_sem702(int flip)
{
    int ch, line, src;
    for (ch = 0; ch < 128; ch++) {
        z80_outp(SEM_CHAR, (unsigned char)ch);
        for (line = 0; line < 16; line++) {
            z80_outp(SEM_LINE, (unsigned char)line);
            if (flip && line < CELL_LINES)
                src = ch * 16 + (CELL_LINES - 1 - line);
            else
                src = ch * 16 + line;
            z80_outp(SEM_DATA, font296[src]);
        }
    }
}

static void hold(void)
{
    unsigned int i, j;
    for (i = 0; i < 20; i++)
        for (j = 0; j < 60000u; j++) { }
}

int main(void)
{
    const char *s;

    load_sem702(0);                 /* SEM702 = ROA296 (upright) */

    conout(0x84);                   /* -> semigraphics (SEM702) */
    for (s = "SEM702 FLIP TEST\r\n"; *s; s++) conout(*s);
    for (s = "ABCDEFGHIJKLMNOPQRSTUVWXYZ\r\n"; *s; s++) conout(*s);
    for (s = "abcdefghijklmnopqrstuvwxyz\r\n"; *s; s++) conout(*s);
    for (s = "0123456789 Regnecentralen\r\n"; *s; s++) conout(*s);
    conout(0x80);                   /* -> normal */

    MARKER = 1;
    hold();                         /* screenshot A */

    load_sem702(1);                 /* SEM702 = ROA296 flipped */

    MARKER = 2;
    hold();                         /* screenshot B */
    for (;;) { }
    return 0;
}
