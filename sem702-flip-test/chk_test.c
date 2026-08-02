/* SEM702 chargen validation (rc702sem702), two independent phases.
 *
 * Purpose: prove the SEM702 RAM chargen write+render path end-to-end, with the
 * font DATA decoupled from the write PATH, per the debugging procedure:
 *
 *   Phase A  Fill ALL 128 redefinable glyphs (codes 0x00-0x7F) with a fixed
 *            1-pixel CHECKERBOARD, switch to semigraphics, and print every
 *            printable redefinable code (0x20-0x7E).  On screen every cell --
 *            letters AND spaces alike -- must show the same checkerboard,
 *            tiling seamlessly.  This validates the write path and the 8275
 *            cell height with a constant pattern that has NO dependence on any
 *            font file.  -> screenshot A.
 *
 *   Phase B  Read the real ROA296 font (2048 B = 128 glyphs x 16 dot-lines)
 *            from the file ROA296.BIN into RAM, then reprogram each glyph from
 *            that buffer.  The same printed text must now show the ROA296
 *            letters upright.  This validates the file->RAM->screen data path.
 *            -> screenshot B.
 *
 * marker at 0xBF00: 1 = phase A ready, 2 = phase B ready (for the MAME lua).
 * progress at 0xBF01: coarse trace of where main() has got to.
 */
#include <cpm.h>
#include <stdio.h>
#include <video/sem702.h>

#define GLYPH_LINES 16                 /* ROA296 stores 16 dot-lines per glyph */
#define NGLYPH      128                /* SEM702 RAM chargen = codes 0x00-0x7F  */
#define FONT_BYTES  (NGLYPH * GLYPH_LINES)

#define MARKER   (*(volatile unsigned char *)0xBF00)
#define PROGRESS (*(volatile unsigned char *)0xBF01)

static unsigned char font[FONT_BYTES];         /* ROA296 image read from file  */

static void conout(unsigned char ch) { bdos(2, ch); }

/* Fill all glyphs with a 1-pixel checkerboard: even dot-lines light the even
 * columns (bit0,2,4,6 -> 0x55), odd dot-lines the odd columns (bit1,3,5 ->
 * 0x2a).  bit0 is the leftmost pixel (display_pixels draws BIT(gfx,0) first),
 * so this is a true 1x1 checkerboard that tiles across adjacent cells. */
static void load_checkerboard(void)
{
    unsigned char buf[GLYPH_LINES];
    int ch, line;

    for (line = 0; line < GLYPH_LINES; line++)
        buf[line] = (line & 1) ? 0x2a : 0x55;

    for (ch = 0; ch < NGLYPH; ch++) {
        sem702_loadglyph((unsigned char)ch, buf, GLYPH_LINES);
        PROGRESS = (unsigned char)ch;
    }
}

/* Reprogram every glyph from the ROA296 image already read into font[]. */
static void load_from_font(void)
{
    int ch;
    for (ch = 0; ch < NGLYPH; ch++) {
        sem702_loadglyph((unsigned char)ch, &font[ch * GLYPH_LINES], GLYPH_LINES);
        PROGRESS = (unsigned char)ch;
    }
}

/* Read ROA296.BIN (2048 bytes) into font[].  Returns 0 on success. */
static int read_font_file(void)
{
    FILE *fp;
    int got;

    fp = fopen("ROA296.BIN", "rb");
    if (!fp)
        return 1;
    got = fread(font, 1, FONT_BYTES, fp);
    fclose(fp);
    return (got == FONT_BYTES) ? 0 : 2;
}

/* Print every printable redefinable code (0x20-0x7e) in rows of 32, then a
 * trailing newline.  In semigraphics mode each of these cells renders from the
 * SEM702 RAM, so this is what makes the reprogrammed glyphs visible. */
static void print_redefinable(void)
{
    unsigned int c;

    for (c = 0x20; c <= 0x7e; c++) {
        conout((unsigned char)c);
        if (((c - 0x20 + 1) & 31) == 0) {        /* 32 chars per row */
            conout('\r');
            conout('\n');
        }
    }
    conout('\r');
    conout('\n');
}

/* Real-work pause so clang cannot optimise it away (volatile sink). */
static void hold(void)
{
    static volatile unsigned int sink;
    unsigned int i, j;
    for (i = 0; i < 8; i++)
        for (j = 0; j < 60000u; j++)
            sink = sink + 1;
}

int main(void)
{
    int rc;

    PROGRESS = 0xA0;

    /* ---- Phase A: checkerboard everything, then show it ---- */
    load_checkerboard();
    PROGRESS = 0xA1;

    conout(0x84);                                /* -> semigraphics (SEM702) */
    for (const char *s = "SEM702 CHECKERBOARD (0x20-0x7E)\r\n"; *s; s++) conout(*s);
    print_redefinable();
    conout(0x80);                                /* -> normal */

    MARKER = 1;
    hold();                                      /* screenshot A */

    /* ---- Phase B: load real ROA296 from file, reprogram per glyph ---- */
    rc = read_font_file();
    PROGRESS = (unsigned char)(0xB0 | (rc & 0x0f));
    if (rc == 0)
        load_from_font();
    PROGRESS = 0xB8;

    conout(0x84);                                /* -> semigraphics (SEM702) */
    for (const char *s = "SEM702 ROA296 FROM FILE\r\n"; *s; s++) conout(*s);
    print_redefinable();
    conout(0x80);                                /* -> normal */

    MARKER = 2;
    hold();                                      /* screenshot B */

    PROGRESS = 0xFF;
    for (;;) { }
    return 0;
}
