/* cpnos-rom cold-boot driver.
 *
 * Runs entirely from RAM at 0xDE00+ after the PROM0 relocator has
 * reconstructed the payload in place.  No more LMA-vs-VMA dance —
 * what the compiler sees is what executes.
 *
 * Entry: _cpnos_cold_entry.  Tail call from relocator.s's `jp`.
 *   1. init_hardware — CTC, SIO-A/B, PIO, DMA, 8275, IM2 IVT.
 *   2. cfgtbl_init  — populate non-zero CFGTBL fields (everything else
 *      stays zero from BSS power-on).
 *   3. netboot       — fetch CCP+NDOS image from the master.
 *   4. PROM disable (OUT 0x18) — safe, we're executing from 0xDE00+.
 *   5. CP/M zero-page setup (JP WBOOT at 0x0000, JP BDOS at 0x0005).
 *   6. SNIOS — drain SIO RX, seed NETST=ACTIVE.
 *   7. Copy our SNIOS jump table to 0xEA00 where DRI NDOS expects it.
 *   8. Enable interrupts (CRT refresh ISR wakes the display).
 *   9. Jump to CP/NOS entry at 0xD000.
 */

#include <stdint.h>
#include "hal.h"

extern void init_hardware(void);
extern void cfgtbl_init(void);
extern uint8_t snios_ntwkin(void);
extern void enable_interrupts(void);
extern uint8_t snios_jt[24];
extern void jump_to(uint16_t addr) __attribute__((noreturn));

/* Netboot: two implementations, one selected by SERVER=mpm|proxy in
 * the Makefile.  Default is mpm — standard CP/NET 1.2 LOGIN / OPEN /
 * READ / CLOSE against z80pack MP/M II. */
#ifdef NETBOOT_LEGACY
extern uint16_t netboot(void);
#define NETBOOT() netboot()
#else
extern uint16_t netboot_mpm(void);
#define NETBOOT() netboot_mpm()
#endif

#define NDOS_SNIOS_ADDR  0xEA00  /* NDOS_BASE(0xDE00) + NDOS code_len(0xC00) */

[[noreturn]] void cpnos_cold_entry(void) {
    /* PROMs are still mapped at 0x0000..0x07FF and 0x2000..0x27FF;
     * we're running from RAM at 0xDE00+ so we don't care.  Leave them
     * enabled until step (4) below. */

    cfgtbl_init();
    init_hardware();

    uint16_t entry = NETBOOT();

    /* Disable the PROMs — exposes RAM underneath for the TPA and
     * netboot-loaded image.  We're at 0xDE00+; still running fine. */
    _port_out(PORT_RAMEN, 0x00);

    /* CP/M 2.2 zero page initial setup.  Written here before control
     * jumps to cpnos.com at 0xD000; cpnos.com's own boot routine
     * overwrites most of these with runtime-correct values (BDOS at
     * 0xD9B1, CCP-intercept JT at 0xCF00, etc.).  We pre-fill with
     * reasonable values to keep any pre-cpnos-boot reads safe.
     *
     *   0x0000..0x0002  JP _bios_wboot   (c3 03 DD)
     *   0x0003          IOBYTE (default 0 = all TTY)
     *   0x0004          current drive/user (default 0 = A:, user 0)
     *   0x0005..0x0007  placeholder JP; cpbios.asm overwrites it
     *
     * Inline LDIR: __builtin_memcpy to the literal address 0 is
     * treated as UB by clang and the entire function gets deleted
     * (see ravn/llvm-z80#49). */
    static const uint8_t ZP_INIT[8] = {
        0xC3, 0x03, 0xDE,     /* JP _bios_wboot (BIOS JT at 0xDE00+3) */
        0x00,                  /* IOBYTE */
        0x00,                  /* current drive/user */
        0xC3, 0x06, 0xDE,     /* placeholder; cpnos.com boot overwrites */
    };
    const void *src = ZP_INIT;
    void       *dst = (void *)0;
    unsigned    n   = 8;
    __asm__ volatile("ldir"
        : "+{de}"(dst), "+{hl}"(src), "+{bc}"(n)
        :
        : "memory");

    /* Prime SNIOS: drain SIO RX, seed NETST=ACTIVE, clear SIZ.  NDOS's
     * own NTWKIN may re-run this; idempotent. */
    snios_ntwkin();

    /* Copy our 24-byte SNIOS jump table to the address where DRI
     * NDOS.SPR expects SNIOS to live (NDOS + code_len). */
    __builtin_memcpy((void *)NDOS_SNIOS_ADDR, snios_jt, 24);

    enable_interrupts();

    /* Hand off to cpnos.com's entry at 0xD000 (first byte of the
     * netboot-loaded image = `JP BIOS` vector).  If netboot failed
     * (entry == 0), halt — no useful fallback at this stage. */
    if (entry != 0) {
        jump_to(0xD000);
    }
    for (;;) { }
}
