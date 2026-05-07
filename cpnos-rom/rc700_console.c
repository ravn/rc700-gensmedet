/* rc700_console.c — RC700 console state machine.
 *
 * Per-byte interpreter for CP/NOS CONOUT.  Implements the RC700 control
 * code set (cursor moves, line insert/delete, clear-to-EOL/EOS, XY
 * addressing via 0x06), minus the background-bitmap codes 0x13/0x14/0x15
 * which the user explicitly excluded.  Also tracks the 128..191 sticky
 * semigraphics-mode bit so glyphs rendered via that range reach the
 * 8275 char ROM intact.
 *
 * Entry points in .resident (after the BIOS jump table at 0xF200);
 * static helpers are in .resident too — single-section layout keeps
 * the linker script untouched.
 *
 * Size target: cheaper than the old inline CONOUT in resident.c minus
 * redundant helpers (crt_scroll_up, crt_set_cursor) — net increase
 * roughly the new dispatch table + XY absorber.
 */

#include <stdint.h>
#include <stddef.h>
#include "hal.h"
#include "rc700_console.h"

/* rc700_console lands in the .resident_pre region (0xF000..0xF1FF)
 * — below the fixed-ABI BIOS jump table at 0xF200.  cpnos_main copies
 * both resident sections out of PROM before calling into us. */
#ifdef __ELF__
#define RESIDENT __attribute__((section(".resident_pre"), used))
#else
#define RESIDENT
#endif

/* runtime.s has memcpy/memset/memmove used by the scroll and
 * line-insert/delete paths. */
extern void *memcpy(void *dst, const void *src, size_t n);
extern void *memmove(void *dst, const void *src, size_t n);
extern void *memset(void *s, int c, size_t n);

#define SCRN_COLS    80
#define SCRN_ROWS    25
#define SCRN_SIZE    ((uint16_t)(SCRN_COLS * SCRN_ROWS))              /* 2000 */
#define LASTROW_OFF  ((uint16_t)((SCRN_ROWS - 1) * SCRN_COLS))        /* 1920 */
#define COL_LAST     (SCRN_COLS - 1)

/* 0x07 BEL target — BIB port strobes the onboard beeper. */
#define PORT_BEEP    PORT_BIB

static volatile uint8_t * const screen = (volatile uint8_t *)DISPLAY_ADDR;

/* State (default-zero in scratch BSS).  cury and cursy are kept
 * coherent (cury == cursy * 80) so no runtime divide. */
static uint8_t  curx;        /* 0..79 */
static uint16_t cury;        /* byte offset of current row: 0,80,...,1920 */
static uint8_t  cursy;       /* row index 0..24 */
static uint8_t  xflg;        /* XY absorber: 0=off, 2=want X, 1=want Y */
static uint8_t  adr0;        /* stashed X while waiting for Y */
static uint8_t  graph;       /* sticky semigraphics-mode bit — drives the
                              * conv-table translation path in put_glyph
                              * once that table is in place. */

RESIDENT
static void crt_cursor(void) {
    _port_out(PORT_CRT_CMD,   0x80);        /* 8275 load-cursor */
    _port_out(PORT_CRT_PARAM, curx);
    _port_out(PORT_CRT_PARAM, cursy);
}

RESIDENT
static void scroll_up(void) {
    memcpy((void *)DISPLAY_ADDR,
           (void *)(DISPLAY_ADDR + SCRN_COLS),
           LASTROW_OFF);
    memset((void *)(DISPLAY_ADDR + LASTROW_OFF), ' ', SCRN_COLS);
}

RESIDENT
static void cur_down(void) {
    if (cury < LASTROW_OFF) { cury += SCRN_COLS; cursy++; }
    else                    { scroll_up(); }
}

RESIDENT
static void cur_up(void) {
    if (cury != 0) { cury -= SCRN_COLS; cursy--; }
    else           { cury = LASTROW_OFF; cursy = SCRN_ROWS - 1; }
}

RESIDENT
static void cur_right(void) {
    if (curx < COL_LAST) {
        curx++;
    } else {
        curx = 0;
        cur_down();
    }
}

RESIDENT
static void cur_left(void) {
    if (curx != 0) {
        curx--;
    } else {
        curx = COL_LAST;
        cur_up();
    }
}

RESIDENT
static void home(void) {
    curx = 0;
    cury = 0;
    cursy = 0;
}

RESIDENT
static void clear_screen(void) {
    memset((void *)DISPLAY_ADDR, ' ', SCRN_SIZE);
    home();
}

RESIDENT
static void erase_eol(void) {
    memset((void *)(DISPLAY_ADDR + cury + curx), ' ', SCRN_COLS - curx);
}

RESIDENT
static void erase_eos(void) {
    uint16_t pos = cury + curx;
    memset((void *)(DISPLAY_ADDR + pos), ' ', SCRN_SIZE - pos);
}

RESIDENT
static void delete_line(void) {
    if (cury < LASTROW_OFF) {
        memcpy((void *)(DISPLAY_ADDR + cury),
               (void *)(DISPLAY_ADDR + cury + SCRN_COLS),
               LASTROW_OFF - cury);
    }
    memset((void *)(DISPLAY_ADDR + LASTROW_OFF), ' ', SCRN_COLS);
}

RESIDENT
static void insert_line(void) {
    if (cury < LASTROW_OFF) {
        memmove((void *)(DISPLAY_ADDR + cury + SCRN_COLS),
                (void *)(DISPLAY_ADDR + cury),
                LASTROW_OFF - cury);
    }
    memset((void *)(DISPLAY_ADDR + cury), ' ', SCRN_COLS);
}

RESIDENT
static void start_xy(void) {
    xflg = 2;
    home();
}

RESIDENT
static uint16_t row_offset(uint8_t row) {
    /* row * 80 via shift-add (64 + 16) — no library __mulhi3. */
    uint16_t r = row;
    return (uint16_t)((r << 6) + (r << 4));
}

RESIDENT
static void xy_absorb(uint8_t c) {
    uint8_t v = (uint8_t)((c & 0x7F) - 0x20);
    xflg--;
    if (xflg != 0) { adr0 = v; return; }

    uint8_t x = adr0;
    uint8_t y = v;
    if (x >= SCRN_COLS) x = (uint8_t)(x - SCRN_COLS);
    /* Explicit subtract chain (max coord 0x5F = 95; at most 4 subs
     * of 25 land in range).  Avoids the compiler pulling in a modulo
     * helper from the library. */
    if (y >= SCRN_ROWS) y = (uint8_t)(y - SCRN_ROWS);
    if (y >= SCRN_ROWS) y = (uint8_t)(y - SCRN_ROWS);
    if (y >= SCRN_ROWS) y = (uint8_t)(y - SCRN_ROWS);
    curx = x;
    cursy = y;
    cury = row_offset(y);
}

RESIDENT
static void put_glyph(uint8_t c) {
    /* 8275 char ROM has 7 address bits; 192..255 fold to 0..63.
     * 128..191 = semigraphics-mode toggle; bit 2 becomes the sticky
     * `graph` state.  Once conv-table translation ships, `graph == 0`
     * will run c through the national/semigraphics map before the
     * write; for now both modes pass-through. */
    if (c >= 192) c = (uint8_t)(c - 192);
    if (c >= 128) {
        graph = (uint8_t)(c & 0x04);
        return;
    }
    /* TODO(conv_tables): when graph == 0, translate c via the CONV
     * table before writing.  Reading `graph` here keeps it live for
     * that future hook. */
    uint8_t g = graph;
    (void)g;
    screen[cury + curx] = c;
    cur_right();
}

RESIDENT
static void dispatch_ctrl(uint8_t c) {
    switch (c) {
    case 0x01: insert_line();                break;
    case 0x02: delete_line();                break;
    case 0x05: /* ENQ — treated as BS */
    case 0x08: cur_left();                   break;
    case 0x06: start_xy();                   break;
    case 0x07: _port_out(PORT_BEEP, 0);      break;
    case 0x09: /* TAB = 4 cur_rights */
        cur_right(); cur_right(); cur_right(); cur_right(); break;
    case 0x0A: cur_down();                   break;
    case 0x0C: clear_screen();               break;
    case 0x0D: curx = 0;                     break;
    case 0x18: cur_right();                  break;
    case 0x1A: cur_up();                     break;
    case 0x1D: home();                       break;
    case 0x1E: erase_eol();                  break;
    case 0x1F: erase_eos();                  break;
    /* 0x13/0x14/0x15: background-bitmap codes — intentionally ignored. */
    default: break;
    }
}

RESIDENT
void rc700_console_init(void) {
    clear_screen();
    xflg = 0;
    adr0 = 0;
    graph = 0;
    crt_cursor();
}

RESIDENT
void rc700_console_putc(uint8_t c) {
    if (xflg != 0) {
        xy_absorb(c);
    } else if (c < 0x20) {
        dispatch_ctrl(c);
    } else {
        put_glyph(c);
    }
    crt_cursor();
}
