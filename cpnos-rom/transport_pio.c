/* cpnos-rom transport backend: PIO-B parallel (Option P).
 *
 * Frame-level CP/NET 1.2 transport over the RC702's Z80-PIO Port B
 * (J3 in real hardware).  Half-duplex with mode-switch:
 *   pio_send_msg -> Mode 0 (output) + OTIR
 *   pio_recv_msg -> Mode 1 (input)  + INIR
 *
 * Speed bench results (session 30, 4 MHz Z80, MAME real-time):
 *   OTIR-driven TX: 156 KiB/s   (21 T/byte instruction-only)
 *   INIR-driven RX: 148 KiB/s   (21 T/byte, chip self-clocked)
 *
 * Wire layout: blast the SCB raw — Mode 0/1 hardware handshake gives
 * per-byte delivery guarantees that subsume the SIO ENQ/ACK/SOH
 * envelope.  No framing bytes; receiver knows to read 5 hdr +
 * (SIZ+1) payload + 1 CKS = SIZ + 7 wire bytes (DRI SIZ-minus-1
 * convention).
 *
 * Frame size cap: total wire bytes must fit in one OTIR/INIR (B
 * register, 8-bit, 0 means 256 iterations).  CP/NET in our codebase
 * is well under this — biggest is READ-SEQ at 171 B (netboot_mpm).
 * The DRI spec ceiling of 262 B is unreachable through any function
 * the slave actually issues; we cap at 256 for code size.
 *
 * Interrupt policy: chip's PIO IE flip-flop is OFF during INIR/OTIR,
 * but the Z80 IFF stays ON.  Block instructions sample INT between
 * iterations so CRT VRTC interrupts (DMA refresh) keep firing
 * mid-burst.  No `di`/`ei` around the bursts — we never blind the
 * system.
 *
 * Direction state: starts in INPUT (init.c leaves PIO-B in Mode 1 +
 * IRQ).  send_msg flips to OUTPUT, blasts, leaves in OUTPUT.  recv_msg
 * flips back to INPUT.  Mode 1 -> Mode 0 transition emits one
 * stale-latch byte (m_output after reset = 0; documented chip
 * artifact, ravn/mame#7) which the peer strips by recognising the
 * SCB header signature.
 *
 * See docs/cpnet_fast_link.md (Option P design) and
 * docs/cpnet_pio_speed_results.md (the bench).
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
#ifndef TRANSPORT_PROXY
/* IRQ ring buffer for envelope-on-PIO modes (sio / pio-irq).  Skipped
 * in TRANSPORT=pio-proxy because that mode uses raw OTIR/INIR frames
 * (transport_pio_vt) — no byte-level recv path, so the ring is dead
 * weight and the 256 B at 0xF700 freed for the larger payload. */
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

/* Frame-level PIO transport (raw SCBs, paired with cpnet_pio_server.py
 * --upstream on the host).  Compiled only in TRANSPORT=pio-proxy
 * builds where cpnet_dispatch.c sets active_transport =
 * &transport_pio_vt.  In TRANSPORT=pio-irq / sio builds these are
 * unreferenced and we'd waste payload space carrying them — payload
 * already runs to within ~30 B of 0xF700 (pio_rx_bss), so adding
 * ~130 B of unreachable frame code overflows.  Guard at compile time. */
#ifdef TRANSPORT_PROXY
RESIDENT
uint8_t pio_send_msg(uint8_t *msg) {
    pio_b_set_output();
    /* body_len = 5 hdr + (SIZ+1) payload.  uint8_t suffices: SIZ <=
     * 255 means body <= 261 — but we cap frames at 256-wire-byte
     * (one OTIR), so body_len <= 255 here.  Stick to uint8_t for the
     * loop counter so clang DJNZs it. */
    uint8_t body_len = (uint8_t)(6U + msg[SIZ]);
    uint8_t cks = 0;
    for (uint8_t i = 0; i < body_len; ++i) cks += msg[i];
    msg[body_len] = (uint8_t)(0U - cks);
    uint8_t b = (uint8_t)(body_len + 1U);
    __asm__ volatile(
        "ld   c, 0x11\n\t"
        "otir\n\t"
        : "+{hl}"(msg), "+{b}"(b)
        :
        : "a", "c", "memory"
    );
    return 0;
}

/* First-byte sentinel-wait budget.  Per-iteration cost ~36 T-states
 * (IN A,(n) + cp + jr + dec + jr).  16384 polls = ~590,000 T =
 * ~150 ms at 4 MHz emulated.  Generous enough for localhost RTT
 * including Python interpreter wake-up (~10 ms wall + MAME speed-up),
 * still fast-fails the SIO-fallback path in well under a second. */
#define PIO_FIRST_BYTE_BUDGET 0x4000U

/* "Buffer empty" sentinel for pio_recv_msg's first-byte polling.  The
 * MAME cpnet_bridge::read() handler returns 0xFF when the input queue
 * is drained (no host bytes yet), so we spin reading the data port
 * until we see something else — that's the first byte (FMT) of the
 * response SCB, which is structurally either 0x00 (request) or 0x01
 * (response) and never 0xFF.  Once FMT lands, INIR reads the rest of
 * the frame whatever the byte values are.
 *
 * This polling-for-FMT is safe in pio-proxy mode because FMT∉{0xFF}.
 * It would NOT be safe to extend to subsequent bytes (cpnos.com has
 * 0xFF data bytes).  See session 33/34 RCA for the original burn. */
#define PIO_RX_EMPTY_VAL 0xFFU

/* Receive a complete CP/NET frame.  Reads 5 header bytes (the first
 * via PORT_PIO_B_DATA polling for non-FF, the next 4 via INIR), then
 * INIR's the (SIZ+2) payload+CKS bytes.  Returns 0 success, 0xFF on
 * timeout. */
RESIDENT
uint8_t pio_recv_msg(uint8_t *msg) {
    pio_b_set_input();
    /* First-byte sentinel-wait — empty PIO-B FIFO returns 0xFF in
     * MAME's bridge; spin until a non-FF byte appears (= FMT of the
     * response).  Bounded budget; see PIO_FIRST_BYTE_BUDGET. */
    uint16_t budget = PIO_FIRST_BYTE_BUDGET;
    uint8_t  first;
    while (budget--) {
        first = _port_in(PORT_PIO_B_DATA);
        if (first != PIO_RX_EMPTY_VAL) goto got_first;
    }
    return 0xFF;
got_first:
    msg[0] = first;
    /* INIR header bytes 1..4 (B=4). */
    {
        uint8_t b4 = 4;
        uint8_t *p = &msg[1];
        __asm__ volatile(
            "ld   c, 0x11\n\t"
            "inir\n\t"
            : "+{hl}"(p), "+{b}"(b4)
            :
            : "a", "c", "memory"
        );
    }
    /* INIR (SIZ+1) payload bytes + 1 CKS. */
    {
        uint8_t bn = (uint8_t)((uint16_t)msg[SIZ] + 2U);
        uint8_t *p = &msg[5];
        __asm__ volatile(
            "ld   c, 0x11\n\t"
            "inir\n\t"
            : "+{hl}"(p), "+{b}"(bn)
            :
            : "a", "c", "memory"
        );
    }
    /* No CKS validation here.  PIO Mode 0/1 hardware handshake gives
     * per-byte delivery; sum-to-zero would only catch a host-side
     * protocol bug, not a wire error.  Probe (pio_probe) does a
     * full validate for confidence; runtime CP/NET trusts the wire. */
    return 0;
}

/* Probe: send PING SCB, recv PONG SCB.  Validates round-trip:
 *   PING:  FMT=0x00 DID=0x00 SID=us FNC=PING_FNC SIZ=0 [P] CKS
 *   PONG:  FMT=0x01 DID=us  SID=0x00 FNC=PING_FNC SIZ=0 [O] CKS
 * Returns true on valid PONG.
 *
 * PING bytes built inline (no .rodata) so they don't depend on
 * link placement — at this point in boot the relocator has just
 * copied the payload and clear_screen hasn't run yet, but
 * literal-byte construction is robust either way.
 *
 * CKS is sum-to-zero (two's complement of the body sum). */
#endif

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
#ifdef TRANSPORT_PROXY
    /* Stub — pio-proxy uses transport_pio_vt frame-level I/O, not
     * byte-level.  This symbol still has to exist because snios.s's
     * SENDBY/RECVBY (envelope code) reference _xport_recv_byte at link
     * time even when the runtime path skips the envelope. */
    (void)timeout_ticks;
    return TRANSPORT_TIMEOUT;
#else
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
#endif
}

/* Speed-test BSS variables (referenced by isr.c).  Kept for the
 * speed-test build only. */
uint16_t pio_rx_count;
uint8_t  pio_test_done;
