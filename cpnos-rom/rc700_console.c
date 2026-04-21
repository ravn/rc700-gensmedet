/* rc700_console.c — RC700 console state machine.
 *
 * Handles control chars 0x00..0x1F and the 0x06-prefixed XY cursor
 * addressing sequence from the RC700 console protocol.  Printable
 * chars (>= 0x20) go straight to display RAM at 0xF800.
 *
 * Excluded (background-attribute bits — caller's request):
 *   0x13 enter background, 0x14 return to foreground, 0x15 clear fg.
 *
 * Placement: static helpers live in .resident_pre (VMA 0xF000..0xF1FF)
 * so the BIOS jump table at the fixed 0xF200 ABI address stays intact.
 * The two public entry points (rc700_console_putc / _init) live in
 * .resident (0xF200+) alongside the JT.  Cross-section calls resolve
 * at link time.
 *
 * Simplifications vs rcbios-in-c/bios.c:
 *   - No outcon[] national conversion (passthrough)
 *   - 8275 cursor updated synchronously (no deferred cur_dirty flag)
 *   - No iobyte/serial mirror — caller does that
 *   - No bgflg/bgstar/graph state (beyond tracking the sticky bit)
 *
 * State is kept in .scratch_bss (default-zero at cold boot).
 */

#include <stdint.h>
#include <stddef.h>
#include "hal.h"
#include "rc700_console.h"

/* Runtime memory helpers (runtime.s). */
extern void *memcpy(void *dst, const void *src, size_t n);
extern void *memmove(void *dst, const void *src, size_t n);
extern void *memset(void *s, int c, size_t n);

#ifdef __ELF__
#define RESIDENT     __attribute__((section(".resident"), used))
#define RESIDENT_PRE __attribute__((section(".resident_pre"), used))
#else
#define RESIDENT
#define RESIDENT_PRE
#endif

#define SCRN_COLS      80
#define SCRN_ROWS      25
#define SCRN_SIZE      ((uint16_t)(SCRN_COLS * SCRN_ROWS))  /* 2000 */
#define ROW24_OFFSET   ((uint16_t)((SCRN_ROWS - 1) * SCRN_COLS))  /* 1920 */
#define COL79          (SCRN_COLS - 1)

#define PORT_BELL      0x1C

static volatile uint8_t * const screen = (volatile uint8_t *)DISPLAY_ADDR;

/* Persistent state (default-zero in BSS).  cury and cursy are kept
 * coherent (cury == cursy * SCRN_COLS) so no runtime division. */
static uint8_t  curx;      /* 0..79 */
static uint16_t cury;      /* byte offset of row: 0, 80, ..., 1920 */
static uint8_t  cursy;     /* row index 0..24 (cury / 80) */
static uint8_t  xflg;      /* XY addressing state: 0=off, 2=want1st, 1=want2nd */
static uint8_t  adr0;      /* first XY coord while xflg==1 */
static uint8_t  graph;     /* sticky semigraphics mode flag */

RESIDENT_PRE
static void crt_update_cursor(void) {
    _port_out(PORT_CRT_CMD,   0x80);   /* load cursor position */
    _port_out(PORT_CRT_PARAM, curx);
    _port_out(PORT_CRT_PARAM, cursy);
}

RESIDENT_PRE
static void scroll_up(void) {
    memcpy((void *)(uintptr_t)DISPLAY_ADDR,
           (void *)(uintptr_t)(DISPLAY_ADDR + SCRN_COLS),
           ROW24_OFFSET);
    memset((void *)(uintptr_t)(DISPLAY_ADDR + ROW24_OFFSET), ' ', SCRN_COLS);
}

RESIDENT_PRE
static void home(void) {
    curx = 0;
    cury = 0;
    cursy = 0;
}

RESIDENT_PRE
static void carriage_return(void) {
    curx = 0;
}

RESIDENT_PRE
static void cursor_down(void) {
    if (cury < ROW24_OFFSET) { cury += SCRN_COLS; cursy++; }
    else                     { scroll_up(); }
}

RESIDENT_PRE
static void cursor_up(void) {
    if (cury != 0) { cury -= SCRN_COLS; cursy--; }
    else           { cury = ROW24_OFFSET; cursy = SCRN_ROWS - 1; }
}

RESIDENT_PRE
static void cursor_right(void) {
    if (curx < COL79) {
        curx++;
    } else {
        curx = 0;
        cursor_down();
    }
}

RESIDENT_PRE
static void cursor_left(void) {
    if (curx != 0) {
        curx--;
    } else {
        curx = COL79;
        cursor_up();
    }
}

RESIDENT_PRE
static void tab(void) {
    /* RC700 convention: hardware tab = 4 cursor-right steps. */
    cursor_right();
    cursor_right();
    cursor_right();
    cursor_right();
}

RESIDENT_PRE
static void clear_screen(void) {
    memset((void *)(uintptr_t)DISPLAY_ADDR, ' ', SCRN_SIZE);
    curx = 0;
    cury = 0;
    cursy = 0;
}

RESIDENT_PRE
static void erase_to_eol(void) {
    memset((void *)(uintptr_t)(DISPLAY_ADDR + cury + curx),
           ' ',
           SCRN_COLS - curx);
}

RESIDENT_PRE
static void erase_to_eos(void) {
    uint16_t pos = cury + curx;
    memset((void *)(uintptr_t)(DISPLAY_ADDR + pos), ' ', SCRN_SIZE - pos);
}

RESIDENT_PRE
static void delete_line(void) {
    if (cury < ROW24_OFFSET) {
        memcpy((void *)(uintptr_t)(DISPLAY_ADDR + cury),
               (void *)(uintptr_t)(DISPLAY_ADDR + cury + SCRN_COLS),
               ROW24_OFFSET - cury);
    }
    memset((void *)(uintptr_t)(DISPLAY_ADDR + ROW24_OFFSET), ' ', SCRN_COLS);
}

RESIDENT_PRE
static void insert_line(void) {
    /* Overlapping forward shift — memmove picks LDDR direction. */
    if (cury < ROW24_OFFSET) {
        memmove((void *)(uintptr_t)(DISPLAY_ADDR + cury + SCRN_COLS),
                (void *)(uintptr_t)(DISPLAY_ADDR + cury),
                ROW24_OFFSET - cury);
    }
    memset((void *)(uintptr_t)(DISPLAY_ADDR + cury), ' ', SCRN_COLS);
}

RESIDENT_PRE
static void start_xy(void) {
    xflg = 2;
    curx = 0;
    cury = 0;
    cursy = 0;
}

RESIDENT_PRE
static uint16_t row_offset(uint8_t row) {
    /* row * 80, shift-add to avoid a library multiply: 80 = 64 + 16 */
    uint16_t r = row;
    return (uint16_t)((r << 6) + (r << 4));
}

RESIDENT_PRE
static void put_printable(uint8_t c) {
    /* 8275 char ROM has 7 address bits: 192..255 fold to 0..63.
     * 128..191 = semigraphics control — bit 2 toggles sticky `graph`.
     * 0..127 normal; when graph is set, write byte as-is. */
    if (c >= 192) c = (uint8_t)(c - 192);
    if (c >= 128) {
        graph = (uint8_t)(c & 0x04);
        return;                 /* mode change; no glyph drawn */
    }
    screen[cury + curx] = c;
    cursor_right();
}

/* Dispatch table + xy absorption live in .resident (post-JT) so the
 * .resident_pre slot (0xF000..0xF1FF = 512 B) fits the helpers. */

RESIDENT
static void xy_absorb(uint8_t c) {
    /* Each of the two bytes after 0x06 is coord + 0x20, high bit stripped.
     * val range after (c & 0x7F) - 0x20 is 0..0x5F.  Explicit subtract
     * chains rather than % to avoid pulling in __umodqi3. */
    uint8_t val = (uint8_t)((c & 0x7F) - 0x20);
    xflg--;
    if (xflg != 0) {
        adr0 = val;             /* first byte = X */
        return;
    }
    uint8_t x = adr0;
    uint8_t y = val;
    if (x >= SCRN_COLS) x = (uint8_t)(x - SCRN_COLS);
    if (y >= SCRN_ROWS) y = (uint8_t)(y - SCRN_ROWS);
    if (y >= SCRN_ROWS) y = (uint8_t)(y - SCRN_ROWS);
    if (y >= SCRN_ROWS) y = (uint8_t)(y - SCRN_ROWS);
    curx = x;
    cursy = y;
    cury = row_offset(y);
}

RESIDENT
static void dispatch_control(uint8_t c) {
    switch (c) {
    case 0x0D: carriage_return();       break;
    case 0x0A: cursor_down();           break;
    case 0x06: start_xy();              break;
    case 0x05: /* ENQ = BS */
    case 0x08: cursor_left();           break;
    case 0x09: tab();                   break;
    case 0x18: cursor_right();          break;
    case 0x1A: cursor_up();             break;
    case 0x0C: clear_screen();          break;
    case 0x1D: home();                  break;
    case 0x1E: erase_to_eol();          break;
    case 0x1F: erase_to_eos();          break;
    case 0x01: insert_line();           break;
    case 0x02: delete_line();           break;
    case 0x07: _port_out(PORT_BELL, 0); break;
    /* 0x13/0x14/0x15: background-attribute codes — intentionally ignored. */
    default:                            break;
    }
}

RESIDENT
void rc700_console_init(void) {
    clear_screen();
    xflg = 0;
    adr0 = 0;
    graph = 0;
    crt_update_cursor();
}

RESIDENT
void rc700_console_putc(uint8_t c) {
    if (xflg != 0) {
        xy_absorb(c);
    } else if (c < 0x20) {
        xflg = 0;
        dispatch_control(c);
    } else {
        put_printable(c);
    }
    crt_update_cursor();
}
