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
#include "compiler/compat.h"

/* ISRs + helpers from isr.s. */
extern void isr_crt(void);
extern void isr_noop(void);
extern void isr_pio_kbd(void);
extern void isr_pio_par(void);
extern void set_i_reg(uint8_t page);
extern void enable_im2(void);
/* Defined in resident.c.  SDCC's asm emitter only attaches EXTERN
 * directives for file-scope `extern` declarations — block-scope ones
 * compile but link as undefined symbols. */
extern void clear_screen(void);

/* IVT at __ivt_start (page-aligned, supplied by payload.ld).  Each
 * slot is 2 bytes, so slot N lives at __ivt_start + 2N.
 *   slot 0..3  (vec 0x00..0x06): CTC channels 0..3 (ch2 = CRT refresh)
 *   slot 8..10 (vec 0x10..0x14): SIO-B rx/tx/extstatus (polled, slots
 *                                 installed as noop for the daisy chain)
 *   slot 16    (vec 0x20):       PIO-A keyboard
 *   slot 17    (vec 0x22):       PIO-B (unused)
 *
 * 2026-05-08: IVT moved from 0xF500 (above resident) to 0xEA00 (in the
 * cpnos.com→resident gap opened by Path 6's CODE_BASE shift) to mirror
 * the SDCC layout and free 36 B of scratch BSS.  Page placement is
 * owned by the linker (.ivt SECTION at 0xEA00 in payload.ld); the
 * ASSERTs in payload.ld catch overlap with cpnos.com / .payload /
 * .scratch_bss / stack.  IVT_ADDR derives the page byte for `I`
 * register loading, no literal address in C. */
extern uint8_t _ivt_start[];
#define IVT_ADDR     ((uint16_t)(uintptr_t)_ivt_start)
#define IVT_ENTRIES  18
#define IVT_PIO_A    16
#define IVT_PIO_B    17

/* Unified port-init table.  Each pair (port, value) is written in
 * order with OUT (C),A.  Centralises ~30 scattered port writes into
 * one table + one loop — smaller than inline port_out calls. */
SECTION_INIT_RODATA
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

    /* PIO-B (CP/NET fast link, J3): vector=0x22, mode 1 input,
     * IE ON.  Each chip strobe (real byte from the bridge) fires
     * isr_pio_par via IM2 vector 0x22; the ISR reads PORT_PIO_B_DATA
     * (clearing chip m_ip) and pushes the byte into pio_rx_buf for
     * snios's transport_pio_recv_byte to pop.  No polling on
     * PORT_PIO_B_DATA, so there's no "0xFF data byte vs empty FIFO"
     * conflation — empty queue is signalled by head==tail, real bytes
     * (any value 0x00..0xFF) sit in the queue.  See
     * tasks/session34-direct-pio-stall-rootcause.md. */
    PORT_PIO_B_CTRL, 0x22,
    PORT_PIO_B_CTRL, 0x4F,
    PORT_PIO_B_CTRL, 0x83,

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

SECTION_INIT_TEXT
static void setup_ivt(void) {
    /* 18 x 16-bit slots at IVT_ADDR (page-aligned).  All slots default
     * to isr_noop; CTC ch2 (slot 2) gets the CRT refresh ISR. */
    /* Pointer-walk + countdown: clang otherwise uses a 16-bit BC
     * counter for the 18-iteration loop because uint16_t* indexing
     * widens i to 16-bit pointer arithmetic. */
    volatile uint16_t *ivt = (volatile uint16_t *)IVT_ADDR;
    for (uint8_t n = IVT_ENTRIES; n; --n) {
        *ivt++ = (uint16_t)(uintptr_t)&isr_noop;
    }
    ivt = (volatile uint16_t *)IVT_ADDR;
    ivt[2] = (uint16_t)(uintptr_t)&isr_crt;
    ivt[IVT_PIO_A] = (uint16_t)(uintptr_t)&isr_pio_kbd;
    ivt[IVT_PIO_B] = (uint16_t)(uintptr_t)&isr_pio_par;
    set_i_reg(IVT_ADDR >> 8);
    enable_im2();
}

SECTION_INIT_TEXT
void init_hardware(void) {
    /* IVT + IM2 first so any stray interrupt lands on isr_noop rather
     * than the reset vector.  Interrupts stay disabled; resident_entry
     * does EI after PROM disable. */
    setup_ivt();

    /* Apply the unified port-init table — CTC, SIO-A/B, PIO-A, DMA,
     * 8275.  All interrupts are still globally DI.  Pointer-walk
     * with countdown so clang generates a DJNZ-style 8-bit loop
     * rather than a 16-bit pointer compare. */
    const uint8_t *p = port_init;
    for (uint8_t n = sizeof(port_init) / 2; n; --n) {
        uint8_t port = *p++;
        uint8_t value = *p++;
        _port_out(port, value);
    }

    /* Drain any stray RX on the SIOs (RRs can latch error bits from
     * reset that block subsequent transmits until cleared by read). */
    (void)_port_in(PORT_SIO_A_CTRL);
    (void)_port_in(PORT_SIO_B_CTRL);

    /* Clear display with spaces so subsequent CONOUT output is
     * readable against a blank background.  Call into resident.c's
     * clear_screen instead of inlining a 4th copy of the LDIR set. */
    clear_screen();

    /* Visible bring-up marker: 'I' at BOOT_MARK index 0 (display row 0,
     * col 60).  Single char instead of "INIT OK" -- the 7-byte rodata
     * + 7-iteration write loop was ~18 B for marginal value;
     * cpnos_cold_entry already paints the boot-strip after this. */
    BOOT_MARK(0, 'I');
}
