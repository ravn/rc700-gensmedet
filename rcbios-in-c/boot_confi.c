/* boot_confi.c — CONFI defaults and conversion tables (BOOT_DATA section).
 *
 * Compiled with --codeseg BOOT_DATA --constseg BOOT_DATA so data lands
 * in the BOOT_DATA section, between the boot sector header and boot code.
 *
 * Disk layout:
 *   0x000-0x07F  BOOT sector (header + padding, in boot_block.c)
 *   0x080-0x0FF  CONFI defaults (128 bytes, this file)
 *   0x100-0x27F  Conversion tables (384 bytes, this file)
 *   0x280+       Boot code (boot_entry.c, BOOT_CODE section)
 */

#include "bios.h"

/* CONFI hardware configuration defaults (128 bytes).
 * Sector 2 of Track 0.  CONFI.COM reads/writes this block.
 * See ConfiBlock typedef in bios.h for field documentation.
 *
 * section(".boot_data") is the LTO-safe anchor: under -flto all TUs merge
 * into one bitcode module, so the linker script's per-file matcher
 * `*boot_confi.o(.rodata*)` matches nothing and this array would fall to
 * generic .rodata at a high runtime address.  relocate_bios() copies FROM
 * this symbol at coldboot (physical 0x0080, where the ROM loaded Track 0),
 * so it MUST land at 0x0080 — otherwise the copy reads uninitialised RAM
 * and CFG/CTC get garbage.  bios.h #defines __attribute__ away under SDCC. */
__attribute__((section(".boot_data"), used))
const byte confi_on_disk[128] = {
    /* CTC channels 0-3 (ports 0x0C-0x0F).
     * Session 17 proved SIO x1 async RX is unreliable for continuous data
     * (samples at bit boundaries, not centers).  Reverted to the
     * CTC count=1 + SIO x16 path that gives a solid 38400 baud. */
    0x47, 0x01,         /* +0x00: ctc_mode0, ctc_count0 (SIO-A: 38400 baud, x16 mode) */
    0x47, 0x01,         /* +0x02: ctc_mode1, ctc_count1 (SIO-B: 38400 baud, x16 mode) */
    0xD7, 0x01,         /* +0x04: ctc_mode2, ctc_count2 (CRT refresh) */
    0xD7, 0x01,         /* +0x06: ctc_mode3, ctc_count3 (FDC) */

    /* SIO channel A init (serial port), 9 bytes */
    0x18,               /* +0x08: WR0 channel reset */
    0x04, 0x44,         /* +0x09: WR4 x16 clock, 1 stop, no parity */
    0x03, 0xE1,         /* +0x0B: WR3 8-bit, auto enables, Rx enable */
    0x05, 0x60,         /* +0x0D: WR5 8-bit Tx, Tx disabled, RTS off */
    0x01, 0x1B,         /* +0x0F: WR1 Rx/Tx/Ext int enable */

    /* SIO channel B init (console), 11 bytes — same register order as main */
    0x18,               /* +0x11: WR0 channel reset */
    0x02, 0x10,         /* +0x12: WR2 int vector base 0x10 */
    0x04, 0x44,         /* +0x14: WR4 x16 clock, 1 stop, no parity */
    0x03, 0xE1,         /* +0x16: WR3 8-bit, auto enables, Rx enable */
    0x05, 0x60,         /* +0x18: WR5 8-bit Tx, Tx disabled */
    0x01, 0x1F,         /* +0x1A: WR1 Rx/Tx/Ext/status affects vector */

    /* DMA mode registers */
    0x48, 0x49, 0x4A, 0x4B,  /* +0x1C: ch0-ch3 single/read */

    /* 8275 CRT controller reset parameters */
    0x4F,               /* +0x20: par[0] 80 chars/row */
    0x98,               /* +0x21: par[1] 25 rows, VRTC timing */
    0x7A,               /* +0x22: par[2] 28 H retrace, 4 V retrace */
    0x6D,               /* +0x23: par[3] 7 lines/char, steady block cursor */

    /* FDC SPECIFY command */
    0x03,               /* +0x24: fdprog_len 3 bytes */
    0x03,               /* +0x25: fdprog_cmd SPECIFY */
    0xDF,               /* +0x26: fdprog_srt SRT=D(3ms), HUT=F(240ms) */
    0x28,               /* +0x27: fdprog_hlt HLT=14(40ms), ND=0(DMA) */

    /* CONFI display settings */
    0x00,               /* +0x28: cursor_num blink reverse block */
    0x00,               /* +0x29: conv_num Danish/Norwegian */
    0x06,               /* +0x2A: baud_a index 6 */
    0x06,               /* +0x2B: baud_b index 6 */
    0x00,               /* +0x2C: xyflg XY cursor addressing */
    0xFA, 0x00,         /* +0x2D: stptim 250 (250x20ms = 5s) */

    /* Drive format table (16 drives + terminator) */
    0x08,               /* +0x2F: A maxi floppy (8" DD) */
    0x08,               /* +0x30: B maxi floppy */
    0x20,               /* +0x31: C hard disk (1MB) */
    0xFF, 0xFF, 0xFF, 0xFF,  /* D-G not present */
    0xFF, 0xFF, 0xFF, 0xFF,  /* H-K not present */
    0xFF, 0xFF, 0xFF, 0xFF,  /* L-O not present */
    0xFF,               /* +0x3F: P not present */
    0xFF,               /* +0x40: terminator */

    /* Hard disk partition */
    0x02,               /* +0x41: ndtab 2 partitions */
    0x02, 0x00, 0x00,   /* +0x42: ndt1 partition descriptor */

    /* CTC2 (HD interface board) */
    0xD7, 0x01, 0x03,   /* +0x45: ctc2 mode/count/reset */

    /* Boot device */
    0x00,               /* +0x48: ibootd boot from floppy */

    /* Padding to 128 bytes (49h used, 77h-49h = 47 bytes padding) */
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0
};

/* Character conversion tables (384 bytes).
 * Sectors 3-5 of Track 0.  Copied to 0xF680 at boot.
 * Selected at build time via KBLANG define (default: Danish).
 * section(".boot_data") anchor required under -flto — see confi_on_disk. */
__attribute__((section(".boot_data"), used))
const byte conv_tables[384] = {
#ifdef SWEDISH
#include "locale/swedish_tables.h"
#elif defined(GERMAN)
#include "locale/german_tables.h"
#elif defined(UK_ASCII)
#include "locale/uk_ascii_tables.h"
#elif defined(US_ASCII)
#include "locale/us_ascii_tables.h"
#elif defined(FRENCH)
#include "locale/french_tables.h"
#elif defined(LIBRARY)
#include "locale/library_tables.h"
#else
#include "locale/danish_tables.h"
#endif
};
