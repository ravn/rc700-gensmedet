/* xport_jt.c — transport dispatch functions (clang build).
 *
 * Dispatches between PIO (default) and SIO byte transport based directly
 * on SW1 bit 2 (port 0x14, S03: On=0=PIO, Off=1=SIO).
 *
 * Implemented as __naked functions that tail-jump to the active transport.
 * Reading port 0x14 directly takes 2 B (in a, (0x14)) + 2 B (and 4), exactly
 * matching ld a,(RAM) + or a (4 B), but eliminates the global variable and
 * cold-init patching completely.
 */
#include <stdint.h>
#include "compiler/compat.h"
#include "hal.h"

#define STR_HELPER(x) #x
#define STR(x) STR_HELPER(x)

void transport_pio_send_byte(uint8_t b);
uint16_t transport_pio_recv_byte(uint16_t timeout_ticks);
void transport_send_byte(uint8_t b);
uint16_t transport_recv_byte(uint16_t timeout_ticks);

/* Retain address references to both backends so --gc-sections keeps them alive. */
__attribute__((section(".resident.data"), used))
static void *_transport_refs[] = {
    (void *)transport_pio_send_byte,
    (void *)transport_pio_recv_byte,
    (void *)transport_send_byte,
    (void *)transport_recv_byte,
};

__attribute__((section(".resident"), naked))
void xport_send_byte(uint8_t b) {
    __asm__ volatile (
        "push af\n\t"
        "in   a, (" STR(PORT_SW1) ")\n\t"
        "and  " STR(SW1_TRANSPORT_BIT) "\n\t"
        "jr   nz, 1f\n\t"
        "pop  af\n\t"
        "jp   _transport_pio_send_byte\n"
        "1:\n\t"
        "pop  af\n\t"
        "jp   _transport_send_byte\n"
    );
}

__attribute__((section(".resident"), naked))
uint16_t xport_recv_byte(uint16_t timeout_ticks) {
    __asm__ volatile (
        "in   a, (" STR(PORT_SW1) ")\n\t"
        "and  " STR(SW1_TRANSPORT_BIT) "\n\t"
        "jp   nz, _transport_recv_byte\n\t"
        "jp   _transport_pio_recv_byte\n"
    );
}

