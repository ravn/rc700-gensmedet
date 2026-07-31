/* SEM702 flip test (rc702sem702).
 *
 * 1. Load the ROA296 letter font into the SEM702 RAM chargen (0xD1/0xD2/0xD3).
 * 2. Switch the console to semigraphics mode (BIOS control code 0x84) so the
 *    following characters are rendered from the SEM702 (GPA0=1), print A-Z /
 *    a-z / 0-9, switch back (0x80).  -> screenshot A: upright letters.
 * 3. Reprogram the SEM702 one glyph at a time, top-to-bottom flipped, with a
 *    short pause between glyphs.  Because each character re-renders from
 *    m_sem702_ram every frame, the on-screen characters flip progressively
 *    (roughly in character-code order) instead of all at once.
 *    -> screenshot B: upside-down letters.
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

/* Program one SEM702 glyph; when flip != 0, mirror lines 0..CELL_LINES-1. */
static void load_glyph(int ch, int flip)
{
    int line, src;
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

static void load_all(int flip)
{
    int ch;
    for (ch = 0; ch < 128; ch++)
        load_glyph(ch, flip);
}

/* short pause (a couple of seconds) -- long enough to see a phase and for the
 * MAME lua to snapshot, but not so long the flip seems slow to start */
static void hold(void)
{
    unsigned int i, j;
    for (i = 0; i < 4; i++)
        for (j = 0; j < 60000u; j++) { }
}

/* ~short pause between glyphs (progressive flip) */
static void tick(void)
{
    unsigned int j;
    for (j = 0; j < 12000u; j++) { }
}

int main(void)
{
    const char *s;
    int ch;

    load_all(0);                    /* SEM702 = ROA296 (upright) */

    conout(0x84);                   /* -> semigraphics (SEM702) */
    for (s = "SEM702 FLIP TEST\r\n"; *s; s++) conout(*s);
    for (s = "ABCDEFGHIJKLMNOPQRSTUVWXYZ\r\n"; *s; s++) conout(*s);
    for (s = "abcdefghijklmnopqrstuvwxyz\r\n"; *s; s++) conout(*s);
    for (s = "0123456789 Regnecentralen\r\n"; *s; s++) conout(*s);
    conout(0x80);                   /* -> normal */

    MARKER = 1;
    hold();                         /* screenshot A */

    /* Flip one glyph at a time so the on-screen characters flip in sequence
     * (each screen cell re-renders live, so cells sharing a code flip as that
     * code's glyph is reprogrammed). */
    for (ch = 0; ch < 128; ch++) {
        load_glyph(ch, 1);
        if (ch == 64) MARKER = 3;   /* midway: ~half the glyphs flipped */
        tick();
    }

    MARKER = 2;
    hold();                         /* screenshot B */
    for (;;) { }
    return 0;
}
