/* cpnos-rom init code (runs in place from PROM0, never copied to RAM).
 *
 * Brings up CTC + SIO-A/B (netboot transport + console) and (session
 * #30) IVT + CTC ch2 + 8237 DMA + 8275 CRT.  Interrupts stay DISABLED
 * throughout init and through netboot; resident_entry enables them
 * after PROM disable so the CRT refresh ISR can fire without racing
 * SIO poll loops.
 */

#include <stdint.h>
#include "hal.h"

/* ISRs + helpers from isr.s. */
extern void isr_crt(void);
extern void isr_noop(void);
extern void isr_pio_kbd(void);
extern void set_i_reg(uint8_t page);
extern void enable_im2(void);

/* IVT at 0xEE00 (session 30: moved from 0xF100 to free the 0xF000..0xF1FF
 * page for .resident_pre — RC700 console state machine helpers).
 * Each slot is 2 bytes, so slot N lives at IVT_ADDR+2N.
 *   slot 0..3  (vec 0x00..0x06): CTC channels 0..3 (ch2 = CRT refresh)
 *   slot 8..10 (vec 0x10..0x14): SIO-B rx/tx/extstatus (polled, slots
 *                                 installed as noop for the daisy chain)
 *   slot 16    (vec 0x20):       PIO-A keyboard
 *   slot 17    (vec 0x22):       PIO-B (unused)
 */
#define IVT_ADDR     0xEE00
#define IVT_ENTRIES  18
#define IVT_PIO_A    16

static const uint8_t sio_a_init[] = {
    0x18,           /* WR0: channel reset */
    0x04, 0x44,     /* WR4: x16 clock, 1 stop, no parity */
    0x03, 0xE1,     /* WR3: 8-bit Rx, auto enables, Rx enable */
    0x05, 0x6A,     /* WR5: 8-bit Tx, Tx enable, RTS asserted */
    0x01, 0x00      /* WR1: no interrupts (polled) */
};

static const uint8_t sio_b_init[] = {
    0x18,           /* WR0: channel reset */
    0x02, 0x10,     /* WR2: interrupt vector base 0x10 */
    0x04, 0x44,     /* WR4: x16 clock, 1 stop, no parity */
    0x03, 0xE1,     /* WR3: 8-bit Rx, auto enables, Rx enable */
    0x05, 0x6A,     /* WR5: 8-bit Tx, Tx enable, RTS asserted */
    0x01, 0x00      /* WR1: no interrupts (polled) */
};

static void setup_ivt(void) {
    /* 18 x 16-bit slots at IVT_ADDR (page-aligned).  All slots default
     * to isr_noop; CTC ch2 (slot 2) gets the CRT refresh ISR. */
    volatile uint16_t *ivt = (volatile uint16_t *)IVT_ADDR;
    for (uint8_t i = 0; i < IVT_ENTRIES; ++i) {
        ivt[i] = (uint16_t)(uintptr_t)&isr_noop;
    }
    ivt[2] = (uint16_t)(uintptr_t)&isr_crt;
    ivt[IVT_PIO_A] = (uint16_t)(uintptr_t)&isr_pio_kbd;
    set_i_reg(IVT_ADDR >> 8);
    enable_im2();
}

/* PIO-A keyboard: input mode with interrupt on any byte written by the
 * external agent (native keyboard MCU on real HW, MAME's generic keyboard
 * in emulation).  Control word sequence matches rcbios-in-c/bios_hw_init
 * so MAME's rc702 driver sees the same pattern it already handles.
 *
 *   0x20 — interrupt vector (slot 16 in our IVT = IVT_ADDR+0x20)
 *   0x4F — mode 1 (input) + ICW-follows bit (M1=01, ICW=1)
 *   0x83 — enable interrupts (EI=1, ICW selector)
 *
 * Interrupts stay globally DI until resident_entry does EI, so the ISR
 * won't fire mid-init. */
static void init_pio_kbd(void) {
    _port_out(PORT_PIO_A_CTRL, 0x20);
    _port_out(PORT_PIO_A_CTRL, 0x4F);
    _port_out(PORT_PIO_A_CTRL, 0x83);
}

static void init_display(void) {
    /* 8237 DMA: master clear, then set ch2 + ch3 to auto-initialize
     * single-mode mem->IO (bit 4 set = autoinit so each terminal count
     * auto-reloads the programmed address + word count).  This lets
     * the 8275 refresh continuously without an ISR reprogramming DMA
     * every VRTC. */
    _port_out(PORT_DMA_CMD, 0x20);
    _port_out(PORT_DMA_MODE, 0x58 | 2);   /* ch2: display data */
    _port_out(PORT_DMA_MODE, 0x58 | 3);   /* ch3: attributes */

    /* Clear byte-pointer FF and program ch2 base/wc for the display. */
    _port_out(PORT_DMA_CLBP, 0);
    _port_out(PORT_DMA_CH2_ADDR, DISPLAY_ADDR & 0xFF);
    _port_out(PORT_DMA_CH2_ADDR, DISPLAY_ADDR >> 8);
    _port_out(PORT_DMA_CH2_WC,   (DISPLAY_SIZE - 1) & 0xFF);
    _port_out(PORT_DMA_CH2_WC,   (DISPLAY_SIZE - 1) >> 8);
    /* Attribute ch3: WC=0, address unused (no attr bytes). */
    _port_out(PORT_DMA_CH3_WC,   0);
    _port_out(PORT_DMA_CH3_WC,   0);

    /* Unmask ch2 and ch3 so the 8275 can pull bytes each VRTC. */
    _port_out(PORT_DMA_SMSK, 0x02);   /* mask clear ch2 */
    _port_out(PORT_DMA_SMSK, 0x03);   /* mask clear ch3 */

    /* Clear display with spaces so subsequent CONOUT output is
     * readable against a blank background. */
    for (uint16_t i = 0; i < DISPLAY_SIZE; ++i) {
        ((volatile uint8_t *)DISPLAY_ADDR)[i] = ' ';
    }

    /* 8275 CRT: reset + geometry + start.  Constants from
     * rcbios-in-c/boot_confi.c (80x25, 7 scan lines/row). */
    _port_out(PORT_CRT_CMD,   0x00);
    _port_out(PORT_CRT_PARAM, 0x4F);
    _port_out(PORT_CRT_PARAM, 0x98);
    _port_out(PORT_CRT_PARAM, 0x7A);
    _port_out(PORT_CRT_PARAM, 0x6D);   /* CM=01 blink underline,
                                        * 7 lines/row — same as rcbios,
                                        * which is what MAME actually
                                        * animates as a visible blink. */
    _port_out(PORT_CRT_CMD,   0x80);
    _port_out(PORT_CRT_PARAM, 0);
    _port_out(PORT_CRT_PARAM, 0);
    _port_out(PORT_CRT_CMD,   0xE0);
    _port_out(PORT_CRT_CMD,   0x23);
}

/* Fill a RAM range with JR $ (18 FE, self-loop) so any stray PC that
 * lands here gets trapped in a tight 2-byte loop instead of walking
 * byte-by-byte through zero-initialised NOPs for thousands of cycles.
 * At odd offsets the CPU sees FE 18 = CP 0x18 and advances one pair,
 * then hits the next 18 FE and loops — still a stop, just one step
 * off the original PC. */
static void fill_trap(uint16_t start, uint16_t end) {
    volatile uint8_t *p = (volatile uint8_t *)(uintptr_t)start;
    volatile uint8_t *q = (volatile uint8_t *)(uintptr_t)end;
    while (p < q) {
        *p++ = 0x18;
        *p++ = 0xFE;
    }
}

void init_hardware(void) {
    /* Pre-fill the memory regions that could otherwise hold stray
     * 0x00 NOPs.  We trap everything outside of:
     *   - PROM windows 0x0000..0x07FF and 0x2000..0x27FF (PROM-mapped
     *     until OUT (0x18); can't write there yet)
     *   - scratch BSS 0xEC00..0xED1F (netboot msgbuf etc.)
     *   - resident VMA 0xF200..0xF7FF
     *   - IVT 0xEE00..0xEE23, cursor+stack 0xF000 down
     *   - display RAM 0xF800.. (gets overwritten by init_display)
     * TPA 0x0100..0xCFFF, unused-between-PROMs 0x0800..0x1FFF and
     * 0x2800..0xCFFF, NDOS-BSS tail 0xEA00..0xEBFF — all get the
     * trap pattern.  CCP/NDOS streaming overwrites 0xD000..0xE9FF
     * later; filling here would just get overwritten, so skip it. */
    fill_trap(0x0800, 0x2000);   /* gap between PROM windows */
    fill_trap(0x2800, 0xD000);   /* gap between PROM1 and CCP base */
    fill_trap(0xEA00, 0xEC00);   /* NDOS spill region + SNIOS JT space */
    fill_trap(0xED20, 0xEE00);   /* after scratch BSS, before IVT */

    /* IVT + IM2 first so any stray interrupt lands on isr_noop rather
     * than the reset vector.  Interrupts stay disabled; resident_entry
     * does EI after PROM disable. */
    setup_ivt();

    /* CTC ch0 vector = 0x00 (applies to ch0..ch3: slots 0..3).
     * ch0/ch1: SIO baud timers.  ch2: CRT refresh (VRTC counter, IRQ
     * armed).  ch3: unused. */
    _port_out(PORT_CTC0, 0x00);
    _port_out(PORT_CTC0, 0x47);
    _port_out(PORT_CTC0, 0x01);
    _port_out(PORT_CTC1, 0x47);
    _port_out(PORT_CTC1, 0x01);
    _port_out(PORT_CTC2, 0xD7);
    _port_out(PORT_CTC2, 0x01);

    for (uint8_t i = 0; i < sizeof(sio_a_init); ++i) {
        _port_out(PORT_SIO_A_CTRL, sio_a_init[i]);
    }
    for (uint8_t i = 0; i < sizeof(sio_b_init); ++i) {
        _port_out(PORT_SIO_B_CTRL, sio_b_init[i]);
    }

    (void)_port_in(PORT_SIO_A_CTRL);
    (void)_port_in(PORT_SIO_B_CTRL);

    init_pio_kbd();

    init_display();
}
