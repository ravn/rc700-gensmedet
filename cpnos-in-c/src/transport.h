/* cpnos-rom transport abstraction
 *
 * Two byte-level transports (SIO async 38400, PIO Mode 0/1 parallel)
 * plus a frame-level vtable so SNIOS/netboot can switch between them
 * at runtime without source changes.
 *
 * Selection at boot: cpnos_main probes PIO first (sends a CP/NET
 * PING SCB through PIO-B; on PONG within ~100 ms the PIO transport
 * wins).  Falls back to SIO if no peer responds.
 *
 * Vtable shape: send_msg / recv_msg take a complete CP/NET 1.2 SCB
 * (FMT/DID/SID/FNC/SIZ + payload + CKS, DRI SIZ-minus-1 convention).
 * The transport adds whatever wire envelope it needs (SIO does
 * ENQ/ACK/SOH/CKS/EOT; PIO blasts the SCB raw because Mode 0/1
 * hardware handshake handles per-byte reliability).
 *
 * The byte-level transport_send_byte/transport_recv_byte API stays
 * for SNIOS internals (the SOH envelope is per-byte) — those names
 * remain bound to the SIO backend.
 */
#ifndef CPNOS_TRANSPORT_H
#define CPNOS_TRANSPORT_H

#include <stdbool.h>
#include <stdint.h>
#include "compiler/compat.h"

/* recv_byte timeout sentinel.  Protocol layers treat -1/0xFFFF as timeout. */
#define TRANSPORT_TIMEOUT 0xFFFF

/* SIO byte-level (used by SNIOS for the wire envelope).
 *
 * PRESERVES_REGS_CLANG matches the xport_send_byte declaration in
 * snios_c.c (which becomes _transport_send_byte under
 * TRANSPORT=sio via --defsym alias).  The matching definition-side
 * annotation in transport_sio.c triggers ravn/llvm-z80#133 layer 1
 * (Z80FrameLowering push de / pop de around the body's `ld d,a`
 * scratch use).  Without the definition annotation, SIO callers
 * silently rely on the body's coincidental restore of D=c (because
 * `c` is what gets stashed in D anyway) — fragile and not a real
 * preservation guarantee.  See ravn/rc700-gensmedet#97 Part C. */
void transport_send_byte(uint8_t c) PRESERVES_REGS_CLANG("d", "e", "h", "l", "b", "c");
/* No preserves attribute on recv: clang's body uses A, HL, DE for
 * return value; B and C are honest-preserved but SNIOS callers don't
 * hold meaningful state in BC across recv calls (state-machine routes
 * pointer/counter work through other regs), so declaring would be
 * zero net win.  Cross-references the audit in snios_c.c:96-111. */
uint16_t transport_recv_byte(uint16_t timeout_ticks);

/* The transport is fixed at build time: SNIOS envelope on top of
 * byte transport (sio / pio-irq via linker --defsym aliases on
 * _xport_send_byte / _xport_recv_byte).
 *
 * cpnet_send_msg / cpnet_recv_msg are #define aliases of the actual
 * implementation functions, so callers just emit a direct call (3 B
 * tail-call) instead of the vtable indirection that used to live in
 * cpnet_dispatch.c (deleted 2026-04-30).  Saved ~38 B in the payload. */
extern uint8_t snios_sndmsg_c(uint8_t *msg);
extern uint8_t snios_rcvmsg_c(uint8_t *msg);
#define cpnet_send_msg snios_sndmsg_c
#define cpnet_recv_msg snios_rcvmsg_c

#endif
