/* cpnos-rom PROM relocator (C23).
 *
 * Reconstructs the CP/NOS payload at RAM 0xDD00 from two #embed'd
 * binary chunks that sit in PROM0 tail and PROM1, then tail-calls
 * the payload's cold entry.
 *
 * Why two chunks?  The Z80 maps PROM0 at 0x0000..0x07FF and PROM1
 * at 0x2000..0x27FF, with a 6 KB address hole in between.  The
 * payload is a single contiguous blob linked at 0xDD00, but to fit
 * it in the two EPROMs we cut it at the PROM0/PROM1 boundary.  The
 * build splits payload.bin into payload_a.bin (PROM0 tail) and
 * payload_b.bin (PROM1), and this file #embed's each into its own
 * linker-placed section.
 *
 * Entry flow:
 *   reset.s (at 0x0000) DI + SP + jp _relocate  ->  this function
 *   relocate() memcpys payload_a then payload_b  ->  _cpnos_cold_entry
 *
 * The payload's cold entry address is resolved at link time via
 * --defsym (the Makefile extracts it from the payload ELF with nm).
 */
#include <stdint.h>

/* Payload cold-entry symbol.  Defined in the payload ELF; supplied to
 * this link via `--defsym _cpnos_cold_entry=0x...` (see Makefile). */
extern void cpnos_cold_entry(void) __attribute__((noreturn));

/* Chunk A: first (2 KB - relocator size) bytes of payload.  Lives in
 * PROM0 tail, placed by relocator.ld at 0x0080 (after reset vector
 * + whatever code lands in .init below).  The linker script ASSERTs
 * that .init fits below the .prom0_tail base. */
__attribute__((section(".prom0_tail"), used))
static const uint8_t payload_a[] = {
#embed "clang/payload_a.bin" if_empty(0)
};

/* Chunk B: remaining payload bytes.  Lives in PROM1 at 0x2000. */
__attribute__((section(".prom1"), used))
static const uint8_t payload_b[] = {
#embed "clang/payload_b.bin" if_empty(0)
};

/* Tail-called from reset.s.  SP is already set to 0xED00 (top of the
 * post-CP/NOS DISKBSS region, safely above the payload's runtime
 * address).  PROMs are still mapped — the payload disables them later. */
[[noreturn]] void relocate(void) {
    __builtin_memcpy((void *)0xDD00, payload_a, sizeof payload_a);
    __builtin_memcpy((uint8_t *)0xDD00 + sizeof payload_a,
                     payload_b, sizeof payload_b);
    cpnos_cold_entry();
}
