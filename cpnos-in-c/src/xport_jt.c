/* xport_jt.c — transport dispatch trampolines (clang build — replaces xport_jt.s).
 *
 * Two 3-byte JP-NN entries whose targets are patched at cold-init by
 * install_transport() in init.c based on SW1 bit 2 (S03).  The struct
 * is mutable (not const) so install_transport() can overwrite the target
 * fields directly without pointer-cast tricks.
 *
 * init.c previously treated these as uint8_t[] and patched bytes [1..2].
 * It now uses the struct field `.target` directly — see XportEntry type.
 */
#include <stdint.h>

typedef void (*xport_fptr)(void);
typedef struct { uint8_t op; xport_fptr target; } XportEntry; /* no padding on Z80 */

/* Default targets point at PIO transport so a pre-patch access is safe. */
void transport_pio_send_byte(uint8_t b);
uint16_t transport_pio_recv_byte(uint16_t timeout_ticks);

__attribute__((section(".resident")))
XportEntry xport_send_byte = { 0xC3, (xport_fptr)(void *)transport_pio_send_byte };

__attribute__((section(".resident")))
XportEntry xport_recv_byte = { 0xC3, (xport_fptr)(void *)transport_pio_recv_byte };
