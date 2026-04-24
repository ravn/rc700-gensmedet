/* cpnos-rom BIOS implementation (RAM-resident).
 *
 * Linked into the payload at 0xED00+ as part of the single-blob build.
 * Relocator reconstructs the payload from both EPROMs on cold boot
 * (see relocator.s, payload.ld).  Code here starts executing after
 * cpnos_main.c's _cpnos_cold_entry has done PROM disable, zero-page
 * setup, SNIOS wiring, and JP to 0xD000.
 *
 * Contents: BIOS jump-table implementations (CONOUT control codes,
 * keyboard ring, disk stubs, boot/warm-boot handlers).
 */

#include <stdint.h>
#include "hal.h"

/* Historical section tag: keeps these symbols in `.resident`, which
 * the payload linker script places at the start of the payload so
 * the BIOS jump table lands at 0xED00 (ABI-fixed).  The section
 * attribute only applies under the ELF compile path; macOS system
 * clang (Mach-O, driving the IDE's LSP) rejects it. */
#ifdef __ELF__
#define RESIDENT __attribute__((section(".resident"), used))
#else
#define RESIDENT
#endif

/* Busy-wait SIO-B transmit.  Used by impl_conout to mirror every
 * console byte to the null-modem log. */
RESIDENT
static void console_putc(uint8_t c) {
    while ((_port_in(PORT_SIO_B_CTRL) & SIO_RR0_TX_BUF_EMPTY) == 0) { }
    _port_out(PORT_SIO_B_DATA, c);
}

/* Resident tail-call trampoline: `JP (HL)` from snios.s. */
extern void jump_to(uint16_t addr) __attribute__((noreturn));

/* -------------------------------------------------------------------
 * BIOS jump-table implementations.
 *
 * Targets of the `jp nn` entries in bios_jt.s.  Names follow the
 * pattern `impl_<entry>` so the linker resolves the asm references.
 * ------------------------------------------------------------------- */

RESIDENT
void bios_stub_ret(void) { }

RESIDENT
[[noreturn]] void impl_boot(void) {
    /* CP/M cold-boot entry.  cpnos_main tail-called resident_entry
     * directly once already, so the normal boot flow doesn't come
     * through here.  If CP/NOS itself ever jumps here (e.g. during
     * its post-handoff init before it has patched the zero page
     * to point at NDOSRL's BIOS JT), re-run the cpnos stub rather
     * than dropping into a fallback trap.  Was Issue U. */
    jump_to(0xD000);
}

RESIDENT
[[noreturn]] void impl_wboot(void) {
    /* CP/M warm boot.  In CP/NOS the whole OS image is in RAM and
     * re-runnable from its BOOT label at 0xD000, so re-entering the
     * cpnos stub is an acceptable warm-boot.  Was Issue U. */
    jump_to(0xD000);
}

/* PIO-A keyboard ring buffer.  Populated by isr_pio_kbd (isr.s) on each
 * PIO-A interrupt — one keystroke per IRQ.  Drained by impl_conin.
 * Size must be a power of two (mask = SIZE-1).  SIO-B RX is checked
 * first so automated tests driving the serial line see predictable
 * byte ordering; the PIO path only matters when a human types at the
 * physical keyboard, and the ring smooths over the ISR<->poll race. */
#define KBD_RING_SIZE 16
uint8_t kbd_ring[KBD_RING_SIZE];
uint8_t kbd_head;   /* written by ISR */
uint8_t kbd_tail;   /* written by CONIN */

RESIDENT
uint8_t impl_const(void) {
    if (_port_in(PORT_SIO_B_CTRL) & SIO_RR0_RX_CHAR_AVAIL) return 0xFF;
    if (kbd_head != kbd_tail) return 0xFF;
    return 0x00;
}

/* -------------------------------------------------------------------
 * CRT CONOUT — RC700 control code set.
 *
 * Ported from rcbios-in-c/bios.c:specc().  Skips bg/fg overlay codes
 * (0x13/14/15) — they need a BGSTAR bitmap CP/NOS doesn't carry.
 *
 *   0x01 insert line        0x0C clear screen
 *   0x02 delete line        0x0D carriage return
 *   0x05 cursor left (ENQ)  0x18 cursor right
 *   0x06 XY cursor addr     0x1A cursor up
 *   0x07 bell               0x1D home
 *   0x08 cursor left (BS)   0x1E erase to EOL
 *   0x09 TAB (4 rights)     0x1F erase to EOS
 *   0x0A cursor down
 * ------------------------------------------------------------------- */

#define SCRN_COLS 80
#define SCRN_ROWS 25

/* Cursor + XY-addressing state.  Lives in .scratch_bss (zero-init).
 *
 * curx / cury / cur_dirty are non-static so _isr_crt (in isr.s) can
 * reference them directly — the ISR consumes cur_dirty to reprogram
 * the 8275 cursor registers once per vertical retrace instead of on
 * every CONOUT, which was visibly flickering under fast streams. */
uint8_t curx;                 /* 0..79 */
uint8_t cury;                 /* 0..24 */
uint8_t cur_dirty;            /* set by impl_conout, cleared by _isr_crt */
static uint8_t xflg;          /* 0 = normal; 2/1 = awaiting XY coord bytes */
static uint8_t xy_first;      /* first coord saved between XY calls */

/* screen[row*80 + col].  Macro avoids a function-call overhead at each
 * site (clang-z80 doesn't inline small helpers reliably at -Oz). */
#define CELL(x, y)  ((uint8_t *)DISPLAY_ADDR + (uint16_t)(y) * SCRN_COLS + (x))

/* noinline: clang -Oz inlines the LDIR body into both cursor_right and
 * cursor_down, costing ~25 B of duplicated scroll code on top of the
 * standalone symbol.  Forcing one call site shares the body. */
RESIDENT
static __attribute__((noinline)) void scroll_up(void) {
    /* Move rows 1..24 to 0..23, blank row 24. */
    uint8_t *d = (uint8_t *)DISPLAY_ADDR;
    __builtin_memcpy(d, d + SCRN_COLS, (SCRN_ROWS - 1) * (unsigned)SCRN_COLS);
    __builtin_memset(CELL(0, SCRN_ROWS - 1), ' ', SCRN_COLS);
}

/* --- cursor movement ---------------------------------------------- */

RESIDENT
static void cursor_right(void) {
    if (++curx < SCRN_COLS) return;
    curx = 0;
    if (cury + 1 < SCRN_ROWS) cury++;
    else scroll_up();
}

RESIDENT
static void cursor_left(void) {
    if (curx != 0) { curx--; return; }
    curx = SCRN_COLS - 1;
    cury = (cury != 0) ? cury - 1 : SCRN_ROWS - 1;
}

RESIDENT
static void cursor_down(void) {
    if (cury + 1 < SCRN_ROWS) cury++;
    else scroll_up();
}

RESIDENT
static void cursor_up(void) {
    cury = (cury != 0) ? cury - 1 : SCRN_ROWS - 1;
}

RESIDENT
static void home(void) { curx = 0; cury = 0; }

RESIDENT
static void tab(void) {
    cursor_right(); cursor_right(); cursor_right(); cursor_right();
}

/* --- screen ops --------------------------------------------------- */

RESIDENT
/* Non-static so init.c can CALL us at cold-boot instead of inlining
 * a second LDIR-based memset of the 2000-byte display region. */
void clear_screen(void) {
    __builtin_memset((void *)DISPLAY_ADDR, ' ',
                     (unsigned)SCRN_ROWS * SCRN_COLS);
    home();
}

RESIDENT
static void erase_to_eol(void) {
    __builtin_memset(CELL(curx, cury), ' ', SCRN_COLS - curx);
}

RESIDENT
static void erase_to_eos(void) {
    uint16_t pos = (uint16_t)cury * SCRN_COLS + curx;
    __builtin_memset(CELL(curx, cury), ' ',
                     (unsigned)SCRN_ROWS * SCRN_COLS - pos);
}

RESIDENT
static void delete_line(void) {
    /* Shift rows cury+1..24 up to cury..23, blank row 24. */
    if (cury + 1 < SCRN_ROWS) {
        __builtin_memcpy(CELL(0, cury), CELL(0, cury + 1),
                         (unsigned)(SCRN_ROWS - 1 - cury) * SCRN_COLS);
    }
    __builtin_memset(CELL(0, SCRN_ROWS - 1), ' ', SCRN_COLS);
}

RESIDENT
static void insert_line(void) {
    /* Shift rows cury..23 down by one row, blank row cury.  Regions
     * overlap (dst > src) so we need LDDR — inline-asm form is far
     * smaller than memmove (which carries direction-compare logic). */
    if (cury + 1 < SCRN_ROWS) {
        uint16_t count = (uint16_t)(SCRN_ROWS - 1 - cury) * SCRN_COLS;
        const void *src = CELL(SCRN_COLS - 1, SCRN_ROWS - 2);
        void       *dst = CELL(SCRN_COLS - 1, SCRN_ROWS - 1);
        __asm__ volatile("lddr"
            : "+{de}"(dst), "+{hl}"(src), "+{bc}"(count)
            :
            : "memory");
    }
    __builtin_memset(CELL(0, cury), ' ', SCRN_COLS);
}

/* --- XY addressing (ctrl-F, then two coord bytes) ----------------- */

RESIDENT
static void start_xy(void) { xflg = 2; home(); }

RESIDENT
static void xy_step(uint8_t c) {
    uint8_t val = (c & 0x7F) - 32;       /* coord bytes are offset by ' ' */
    if (--xflg != 0) {
        xy_first = val;                  /* first byte: save X */
        return;
    }
    /* Second byte: Y, then place cursor.  Out-of-range coord bytes
     * clamp to 0 — the previous 3×-unrolled "mod SCRN_ROWS" could
     * not reach val < 25 from e.g. val=224 (raw binary 0 sent as
     * coord underflows), and the resulting wild val made CELL()
     * write outside display RAM.  Clamp is safer and smaller. */
    if (val >= SCRN_ROWS)      val = 0;
    if (xy_first >= SCRN_COLS) xy_first = 0;
    curx = xy_first;
    cury = val;
}

/* --- control-byte dispatch (0x00..0x1F) --------------------------- */

RESIDENT
static void specc(uint8_t c) {
    switch (c) {
    case 0x01: insert_line();          break;
    case 0x02: delete_line();          break;
    case 0x05: cursor_left();          break;  /* ENQ = BS */
    case 0x06: start_xy();             break;
    case 0x07: _port_out(PORT_BIB, 0); break;  /* bell */
    case 0x08: cursor_left();          break;
    case 0x09: tab();                  break;
    case 0x0A: cursor_down();          break;
    case 0x0C: clear_screen();         break;
    case 0x0D: curx = 0;               break;
    case 0x18: cursor_right();         break;
    case 0x1A: cursor_up();            break;
    case 0x1D: home();                 break;
    case 0x1E: erase_to_eol();         break;
    case 0x1F: erase_to_eos();         break;
    default:                           break;  /* unhandled ctrl: drop */
    }
}

/* --- public CONIN / CONOUT ---------------------------------------- */

RESIDENT
uint8_t impl_conin(void) {
    for (;;) {
        if (_port_in(PORT_SIO_B_CTRL) & SIO_RR0_RX_CHAR_AVAIL) {
            return _port_in(PORT_SIO_B_DATA);
        }
        if (kbd_head != kbd_tail) {
            uint8_t c = kbd_ring[kbd_tail];
            kbd_tail = (kbd_tail + 1) & (KBD_RING_SIZE - 1);
            return c;
        }
    }
}

RESIDENT
void impl_conout(uint8_t c) {
    /* Serial mirror first — captures the raw byte stream for null-modem
     * logs regardless of what we do to the CRT side. */
    console_putc(c);

    if (xflg != 0) {
        xy_step(c);
    } else if (c == '\n') {
        /* Treat LF as CR+LF for compatibility with code that emits bare
         * LFs (CCP and the netboot status line do this).  rcbios's specc
         * keeps LF as cursor-down only, but rcbios's CCP path differs. */
        cursor_down();
        curx = 0;
    } else if (c == '\r') {
        /* Hot-path CR inline alongside LF — CR/LF are the most common
         * control codes (line framing) and must not pay the specc
         * jumptable dispatch cost.  0x0A and 0x0D cannot appear as
         * start_xy coord bytes (those are ASCII-offset >= 0x20), so
         * short-circuiting them here is safe for the xy state machine. */
        curx = 0;
    } else if (c < 0x20) {
        specc(c);
    } else {
        *CELL(curx, cury) = c;
        cursor_right();
    }
    /* Defer 8275 cursor register update to _isr_crt (next VRTC): reduces
     * visible cursor flicker under fast streams and saves ~40 T per
     * character on the hot path.  The ISR reads curx/cury and clears
     * cur_dirty atomically wrt the mainline's single-store pattern. */
    cur_dirty = 1;
}

/* Disk BIOS state — written by the SETTRK/SETSEC/SETDMA asm impls
 * in bios_jt.s, read by impl_read (added in the next commit).  Kept
 * as globals so the asm side can reference them by their mangled
 * names without going through a pointer dance.
 *
 * dsk_track / dsk_sector: CP/M passes these as 16-bit BC values.
 * dsk_dma: 16-bit DMA destination address.  CP/M defaults to 0x0080. */
uint16_t dsk_track;
uint16_t dsk_sector;
uint8_t *dsk_dma;

RESIDENT
uint8_t impl_disk_err(void) {
    /* READ/WRITE error stub.  Drive A: goes through NDOS (never hits
     * us); drive B: will call impl_read once the host-sector blocking
     * layer lands — this stub covers drives 2..15 and impl_write. */
    return 1;
}
