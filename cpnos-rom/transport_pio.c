/* cpnos-rom byte-level transport backend: PIO-B parallel.
 *
 * Byte-level CP/NET 1.2 transport over the RC702's Z80-PIO Port B
 * (J3 in real hardware).  Implements transport_pio_send_byte and
 * transport_pio_recv_byte; SNIOS drives the per-byte SOH/ENQ/ACK
 * envelope on top.
 *
 * Direction state: starts in INPUT (init.c leaves PIO-B in Mode 1 +
 * IRQ).  send_byte flips to OUTPUT (with the stale-prefix workaround
 * for ravn/mame#7).  recv_byte flips to INPUT and pops bytes from
 * the IRQ-driven 256-byte ring buffer at 0xF700.
 *
 * Receive path: isr_pio_par (in isr.c) pushes each chip-strobed byte
 * into the page-aligned ring at 0xF700.  transport_pio_recv_byte
 * polls head != tail and returns the next byte, or
 * TRANSPORT_TIMEOUT after the caller-specified tick budget.
 */
#include <stdbool.h>
#include <stdint.h>
#include "hal.h"
#include "compiler/compat.h"
#include "transport.h"

#define RESIDENT      SECTION_RESIDENT
#define RESIDENT_DATA SECTION_RESIDENT_DATA

/* Z80-PIO control-word constants (Zilog datasheet table 4 + ICW form). */
#define PIO_MODE_OUTPUT       0x0F
#define PIO_MODE_INPUT        0x4F
#define PIO_IE_DISABLE        0x03   /* set IE FF: bit7=0 -> IE off */
#define PIO_IE_ENABLE         0x83   /* set IE FF: bit7=1 -> IE on  */
#define PIO_IE_ENABLE_RESET   0x97   /* ICW: enable + mask follows */
#define PIO_INT_MASK_NONE     0x00

#define PIO_DIR_INPUT   0
#define PIO_DIR_OUTPUT  1
static uint8_t pio_b_dir;            /* zeroed BSS = INPUT initially */

/* SCB header offsets (matches netboot_mpm.c). */
#define FMT 0
#define DID 1
#define SID 2
#define FNC 3
#define SIZ 4

/* PING/PONG SCB shape — used by pio_probe. */
#define PING_FNC  0xC0
#define PING_BYTE 'P'
#define PONG_BYTE 'O'

#ifndef RC702_SLAVEID
#define RC702_SLAVEID 0x01
#endif

/* SPSC ring buffer between isr_pio_par (push) and
 * transport_pio_recv_byte (pop).  Size 64 = 0x40, mask 0x3F.  Indices
 * are kept masked at write time so the load sites are a single byte
 * fetch with no extra arithmetic.  Empty: head == tail.  Full slots
 * lost silently; under flow-controlled CP/NET this can't happen, so
 * the ISR doesn't bother to detect it.  Replaces the old 0xFF=empty
 * sentinel which conflated a real 0xFF data byte from mpm-net2 with
 * "no byte yet" (#56). */
#define PIO_RX_BUF_SIZE 256
#define PIO_RX_BUF_MASK 0xFF
/* IRQ ring buffer for byte-level PIO transport. */
volatile uint8_t pio_rx_head;   /* ISR writes only */
volatile uint8_t pio_rx_tail;   /* mainline writes only */
/* Page-aligned 256-byte ring.  ISR builds `&buf[head]` as `ld h,
 * _pio_rx_buf_page; ld l, head` — only correct if the buffer is
 * page-aligned (low byte 0).  Both compilers derive _pio_rx_buf_page
 * from HIGH(_pio_rx_buf) so the constant cannot drift from the
 * placement: clang via payload.ld (.pio_rx_bss NOLOAD region at 0xF700);
 * SDCC via sections.asm (bss_pio_rx section, align 256, defs 256).
 * The SDCC build defines the symbol in sections.asm, so transport_pio.c
 * just declares it extern.  Clang allocates here through the section
 * attribute. */
#if defined(__clang__) && defined(__z80__)
SECTION_PIO_RX_BSS volatile uint8_t pio_rx_buf[PIO_RX_BUF_SIZE];
#else
extern volatile uint8_t pio_rx_buf[PIO_RX_BUF_SIZE];
#endif

RESIDENT
static void pio_b_set_output(void) {
    if (pio_b_dir == PIO_DIR_OUTPUT) return;
    _port_out(PORT_PIO_B_CTRL, PIO_IE_DISABLE);
    _port_out(PORT_PIO_B_CTRL, PIO_MODE_OUTPUT);
    pio_b_dir = PIO_DIR_OUTPUT;
}

RESIDENT
static void pio_b_set_input(void) {
    if (pio_b_dir == PIO_DIR_INPUT) return;
    /* Mode 1 select latches direction; ICW 0x97 + mask 0x00
     * atomically clears m_ip (Mode 0 strobes will have set it).
     * Final 0x83 re-asserts IE on, so isr_pio_par fires once per
     * real chip strobe and pushes the latched byte into pio_rx_buf
     * for snios's transport_pio_recv_byte to pop. */
    _port_out(PORT_PIO_B_CTRL, PIO_MODE_INPUT);
    _port_out(PORT_PIO_B_CTRL, PIO_IE_ENABLE_RESET);
    _port_out(PORT_PIO_B_CTRL, PIO_INT_MASK_NONE);
    _port_out(PORT_PIO_B_CTRL, PIO_IE_ENABLE);
    pio_b_dir = PIO_DIR_INPUT;
}


/* ---- Byte-level PIO transport ---------------------------------
 * snios.s (PIO-only experiment) calls these for every envelope byte.
 *
 * Stale-prefix mitigation on Mode 1->Mode 0 transitions: MAME's
 * z80pio.cpp::set_mode(MODE_OUTPUT) immediately fires
 * out_pb_callback with the chip's current m_output latch.  After a
 * direction flip there's a stale value from the previous send sitting
 * in m_output; if we just `_port_out(CTRL, MODE_OUTPUT)` and then
 * `_port_out(DATA, c)`, the peer sees stale_byte + c.  When the peer
 * is mpm-net2's SERVER.RSP, that stale byte breaks the protocol
 * (received between ACK and SOH, mpm-net2 doesn't tolerate it).
 * Workaround: write the data byte to the data port BEFORE the mode
 * switch.  That updates m_output while still in input mode (the
 * chip latches it without emitting), then the mode switch fires the
 * callback with the byte we actually want to send.  No stale prefix.
 * (See ravn/mame#7 for the underlying chip-emulation behaviour.) */
RESIDENT
void transport_pio_send_byte(uint8_t c) {
    if (pio_b_dir == PIO_DIR_OUTPUT) {
        _port_out(PORT_PIO_B_DATA, c);
        return;
    }
    _port_out(PORT_PIO_B_CTRL, PIO_IE_DISABLE);
    _port_out(PORT_PIO_B_DATA, c);              /* preload m_output */
    _port_out(PORT_PIO_B_CTRL, PIO_MODE_OUTPUT); /* fires callback with c */
    pio_b_dir = PIO_DIR_OUTPUT;
}

RESIDENT
uint16_t transport_pio_recv_byte(uint16_t timeout_ticks) {
    pio_b_set_input();
    while (timeout_ticks--) {
        uint8_t t = pio_rx_tail;
        if (pio_rx_head != t) {
            uint8_t b = pio_rx_buf[t];
            pio_rx_tail = (uint8_t)(t + 1);   /* wraps at 256 */
            return b;
        }
    }
    return TRANSPORT_TIMEOUT;
}

/* Speed-test BSS variables (referenced by isr.c).  Kept for the
 * speed-test build only. */
uint16_t pio_rx_count;
uint8_t  pio_test_done;
