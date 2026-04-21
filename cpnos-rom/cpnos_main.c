/* cpnos-rom cold-boot driver (Phase 1 seed)
 *
 * Runs from PROM0 after reset.s sets up the scratch stack.  Phase 1
 * responsibilities (this file grows to meet them):
 *   1. HW init: SIO-A/B, CTC, PIO, IVT stub
 *   2. Netboot: request CCP+BDOS from server, load into RAM
 *   3. Copy resident chunk from ROM (LMA) to RAM (VMA 0xF200)
 *   4. OUT (0x18),A  — disable both PROMs
 *   5. Jump to resident_entry() (or to CCP cold start once netboot works)
 *
 * This seed implements only steps 3, 4, 5 to verify the LMA→VMA copy.
 * Init code runs in place from ROM — no self-relocation hop (unlike the
 * current autoloader which bounces through 0x7000 because it reads
 * Track 0 into 0x0000).  Single-pass relocation: LMA→VMA once.
 */

#include <stdint.h>

/* Linker symbols — clang Z80 prepends one underscore, so C "_x" maps to
 * asm "__x" which matches the linker script's "__x" definitions. */
extern uint8_t _resident_lma[];
extern uint8_t _resident_start[];
extern uint8_t _resident_end[];
extern uint8_t _resident_pre_lma[];
extern uint8_t _resident_pre_start[];
extern uint8_t _resident_pre_end[];

[[noreturn]] extern void resident_entry(uint16_t entry);
extern void init_hardware(void);            /* init.c, runs from ROM */
extern uint16_t netboot(void);              /* netboot.c, ROM-only */

[[noreturn]] void cpnos_main(void) {
    /* Bring up CTC + SIO-A/B.  (PIO, IVT, DMA, CRT are Phase 2.) */
    init_hardware();

    /* Copy both resident sections from ROM (LMA) to high RAM (VMA)
     * BEFORE netboot: netboot's transport functions live there.
     *   .resident_pre  LMA PROM1 (0x2000) -> VMA 0xF000 (console helpers)
     *   .resident      LMA PROM0 tail     -> VMA 0xF200 (JT + SNIOS + ...)
     */
    {
        uint8_t *src = _resident_pre_lma;
        uint8_t *dst = _resident_pre_start;
        while (dst < _resident_pre_end) {
            *dst++ = *src++;
        }
    }
    {
        uint8_t *src = _resident_lma;
        uint8_t *dst = _resident_start;
        while (dst < _resident_end) {
            *dst++ = *src++;
        }
    }

    /* Try to netboot.  Server streams CCP+BDOS into RAM and returns an
     * entry point; if absent, recv times out and entry == 0. */
    uint16_t entry = netboot();

    /* Hand off to resident code.  It disables the PROMs (safe from
     * 0xF200 — execution continues from RAM) and either jumps to the
     * loaded entry or falls back to a diagnostic banner.  cpnos_main
     * never runs again after this; the PROM is gone and so is the
     * init code that lives underneath it. */
    resident_entry(entry);
}
