/* cpnos-rom transport backend: SIO-A async 38400 (polled).
 *
 * Implements transport.h's byte-level + frame-level API over the
 * RC702's SIO-A channel.  Frame-level (send_msg/recv_msg) wraps the
 * existing SNIOS SOH/STX/ETX/EOT envelope (see snios.s).  Byte-level
 * (transport_send_byte/recv_byte) is the lowest layer SNIOS
 * internally drives the envelope through.
 *
 * Lands in the resident section because netboot calls it after PROM
 * disable.
 */
#include <stdbool.h>
#include <stdint.h>
#include "hal.h"
#include "compiler/compat.h"
#include "transport.h"

#define RESIDENT      SECTION_RESIDENT
#define RESIDENT_DATA SECTION_RESIDENT_DATA

/* ravn/llvm-z80#131/#133 + ravn/rc700-gensmedet#97 Part C: the
 * SNIOS-facing xport_send_byte declaration in snios_c.c declares
 * D preserved.  Under TRANSPORT=sio, --defsym aliases it to this
 * function.  Clang's body uses D as scratch (`ld d,a`) to stash the
 * `c` argument across the IN-loop, then restores D from A before
 * the OUT.  The body-side annotation makes Z80FrameLowering emit
 * push de in prologue and pop de in epilogue (#133 layer 1),
 * so callers' D state genuinely survives.  Body cost +2 B; the
 * caller-side win mirrors the PIO transport's session-58 result. */
RESIDENT
PRESERVES_REGS_CLANG("d", "e", "h", "l", "b", "c")
void transport_send_byte(uint8_t c) {
    while ((_port_in(PORT_SIO_A_CTRL) & SIO_RR0_TX_BUF_EMPTY) == 0) { }
    _port_out(PORT_SIO_A_DATA, c);
}

RESIDENT
uint16_t transport_recv_byte(uint16_t timeout_ticks) {
    while (timeout_ticks--) {
        if (_port_in(PORT_SIO_A_CTRL) & SIO_RR0_RX_CHAR_AVAIL) {
            return _port_in(PORT_SIO_A_DATA);
        }
    }
    return TRANSPORT_TIMEOUT;
}

/* Frame-level send/recv: see snios.s for SNDMSG/RCVMSG and the
 * snios_sndmsg_c / snios_rcvmsg_c wrappers.  cpnet_send_msg in
 * transport.h is a #define alias of those; no vtable dispatch. */
