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

/* IVT at 0xF100; each slot is 2 bytes, so slot N lives at 0xF100+2N.
 *   slot 0..3  (vec 0x00..0x06): CTC channels 0..3 (ch2 = CRT refresh)
 *   slot 8..10 (vec 0x10..0x14): SIO-B rx/tx/extstatus (polled, slots
 *                                 installed as noop for the daisy chain)
 *   slot 16    (vec 0x20):       PIO-A keyboard
 *   slot 17    (vec 0x22):       PIO-B (unused)
 */
/* IVT moved from 0xF100 to 0xEC00 in session 33 follow-up: with
 * BIOS_BASE at 0xED00, .resident code spans 0xED00..~0xF250 and
 * 0xF100..0xF123 fell inside that range, so the old IVT slot would
 * have been overwritten by memcpy (or stomped resident code if IVT
 * were written first).  0xEC00 sits in the 0xEB20..0xED00 gap
 * between BSS (0xEA20..0xEB20) and RESIDENT (0xED00..), with enough
 * room for 18 × 2-byte entries. */
/* IVT location provided by the linker script (cpnos_rom.ld) so the
 * ld ASSERTs and setup_ivt() stay in sync.  If .resident or BSS grows
 * to overlap _ivt_start.._ivt_end, the link fails at build time (issue
 * #35) instead of silently stomping the vector table at boot. */
extern uint8_t _ivt_start[];
#define IVT_ADDR     ((uint16_t)(uintptr_t)_ivt_start)
#define IVT_ENTRIES  18
#define IVT_PIO_A    16

/* Unified port-init table.  Each pair (port, value) is written in
 * order with OUT (C),A.  Centralises ~30 scattered port writes into
 * one table + one loop — smaller than inline port_out calls. */
static const uint8_t port_init[] = {
    /* CTC ch0: vector=0, SIO-A baud timer. */
    PORT_CTC0, 0x00,   PORT_CTC0, 0x47,   PORT_CTC0, 0x01,
    /* CTC ch1: SIO-B baud timer. */
    PORT_CTC1, 0x47,   PORT_CTC1, 0x01,
    /* CTC ch2: CRT VRTC counter, IRQ armed. */
    PORT_CTC2, 0xD7,   PORT_CTC2, 0x01,

    /* SIO-A: WR0 reset, WR4 x16/1-stop/no-parity, WR3 Rx-enable,
     * WR5 Tx-enable/RTS, WR1 no-interrupts (polled). */
    PORT_SIO_A_CTRL, 0x18,
    PORT_SIO_A_CTRL, 0x04, PORT_SIO_A_CTRL, 0x44,
    PORT_SIO_A_CTRL, 0x03, PORT_SIO_A_CTRL, 0xE1,
    PORT_SIO_A_CTRL, 0x05, PORT_SIO_A_CTRL, 0x6A,
    PORT_SIO_A_CTRL, 0x01, PORT_SIO_A_CTRL, 0x00,

    /* SIO-B: same + WR2=0x10 (interrupt vector base). */
    PORT_SIO_B_CTRL, 0x18,
    PORT_SIO_B_CTRL, 0x02, PORT_SIO_B_CTRL, 0x10,
    PORT_SIO_B_CTRL, 0x04, PORT_SIO_B_CTRL, 0x44,
    PORT_SIO_B_CTRL, 0x03, PORT_SIO_B_CTRL, 0xE1,
    PORT_SIO_B_CTRL, 0x05, PORT_SIO_B_CTRL, 0x6A,
    PORT_SIO_B_CTRL, 0x01, PORT_SIO_B_CTRL, 0x00,

    /* PIO-A (keyboard): vector=0x20, mode 1 input + ICW, EI. */
    PORT_PIO_A_CTRL, 0x20,
    PORT_PIO_A_CTRL, 0x4F,
    PORT_PIO_A_CTRL, 0x83,

    /* 8237 DMA: master clear, ch2+ch3 single-mode mem->IO autoinit. */
    PORT_DMA_CMD,  0x20,
    PORT_DMA_MODE, 0x58 | 2,
    PORT_DMA_MODE, 0x58 | 3,
    /* Clear byte-pointer FF, ch2 base/wc for display. */
    PORT_DMA_CLBP,      0,
    PORT_DMA_CH2_ADDR,  DISPLAY_ADDR & 0xFF,
    PORT_DMA_CH2_ADDR,  DISPLAY_ADDR >> 8,
    PORT_DMA_CH2_WC,    (DISPLAY_SIZE - 1) & 0xFF,
    PORT_DMA_CH2_WC,    (DISPLAY_SIZE - 1) >> 8,
    PORT_DMA_CH3_WC,    0,
    PORT_DMA_CH3_WC,    0,
    /* Unmask ch2 and ch3. */
    PORT_DMA_SMSK,      0x02,
    PORT_DMA_SMSK,      0x03,

    /* 8275 CRT: reset + geometry + start. 80x25, 7 scan lines/row,
     * CM=01 blink underline — matches rcbios/MAME expectation. */
    PORT_CRT_CMD,   0x00,
    PORT_CRT_PARAM, 0x4F,
    PORT_CRT_PARAM, 0x98,
    PORT_CRT_PARAM, 0x7A,
    PORT_CRT_PARAM, 0x6D,
    PORT_CRT_CMD,   0x80,
    PORT_CRT_PARAM, 0,
    PORT_CRT_PARAM, 0,
    PORT_CRT_CMD,   0xE0,
    PORT_CRT_CMD,   0x23,
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

void init_hardware(void) {
    /* IVT + IM2 first so any stray interrupt lands on isr_noop rather
     * than the reset vector.  Interrupts stay disabled; resident_entry
     * does EI after PROM disable. */
    setup_ivt();

    /* Apply the unified port-init table — CTC, SIO-A/B, PIO-A, DMA,
     * 8275.  All interrupts are still globally DI. */
    for (uint8_t i = 0; i < sizeof(port_init); i += 2) {
        _port_out(port_init[i], port_init[i + 1]);
    }

    /* Drain any stray RX on the SIOs (RRs can latch error bits from
     * reset that block subsequent transmits until cleared by read). */
    (void)_port_in(PORT_SIO_A_CTRL);
    (void)_port_in(PORT_SIO_B_CTRL);

    /* Clear display with spaces so subsequent CONOUT output is
     * readable against a blank background.  Call into resident.c's
     * clear_screen instead of inlining a 4th copy of the LDIR set. */
    extern void clear_screen(void);
    clear_screen();

    /* FDC SPECIFY: program uPD765 head-movement timing.  Must run
     * once before any recal/seek/read — the FDC powers up with
     * undefined SRT/HUT/HLT timing values. */
    extern void fdc_init(void);
    fdc_init();
}
