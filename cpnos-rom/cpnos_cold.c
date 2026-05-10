/* cpnos-rom cold-init phase.
 *
 * Runs entirely from PROM (INIT_CODE / INIT_RODATA region) before
 * resident_handoff's `OUT (0x18),A` disables the PROMs.  After that
 * point these bytes are unmapped from the address space; control
 * has tail-called into the RAM-resident `resident_handoff` (in
 * cpnos_main.c).
 *
 * Contains:
 *   - print_banner()       : write the boot banner to SIO-B
 *   - cpnos_cold_entry()   : entry from relocator, drives cold init
 *
 * Split out of cpnos_main.c in Phase 51A (#68) so SDCC can place
 * this file in INIT_CODE while cpnos_main.c stays in RESIDENT_CODE.
 * SDCC's per-file `--codeseg` flag is whole-file; without the split
 * the cold-init bytes would have to live in RAM-resident space.
 * Clang already had per-function `__attribute__((section))` so the
 * split makes both compilers symmetric: each file lives in exactly
 * one section.
 */

#include <stdint.h>
#include "hal.h"
#include "compiler/compat.h"
#include "cpnos_addrs.h"     /* CPNOS_TPA_KB (banner) */
#include "cpnos_buildinfo.h" /* BUILD_INFO_STR */

extern void cfgtbl_init(void);
extern void init_hardware(void);
extern void enable_interrupts(void);
extern void impl_conout(uint8_t c);
extern uint16_t netboot_mpm(void);
extern NORETURN void resident_handoff(uint16_t entry);

/* Banner printed BEFORE netboot so the screen layout is:
 *   row 0 (cursor home): "RC702 CP/NOS NNK WWW-MMM cc yyyy-mm-dd HH:MM hash"
 *   row 1: 25 netboot progress dots followed by CR/LF on EOF
 * Operator sees the OS identity immediately on power-on, then
 * watches dots fill in below it. */
SECTION_INIT_TEXT
static void print_banner(void) {
    /* NNK = TPA size (CPNOS_TPA_KB, build-time from cpnos.sym).
     * WWW-MMM = TRANSPORT_NAME literal (Makefile -DTRANSPORT_NAME='"PIO"'/"SIO").
     * cc = CPNOS_COMPILER_NAME ("clang"/"sdcc"/"hitech"), picked at preprocess time
     * so the banner unambiguously identifies which build is running. */
#define _STR(x) #x
#define STR(x) _STR(x)
    static const SECTION_INIT_RODATA char banner[] =
        "RC702 CP/NOS " STR(CPNOS_TPA_KB) "K "
        TRANSPORT_NAME " " CPNOS_COMPILER_NAME " " BUILD_INFO_STR "\r\n";
    for (const char *p = banner; *p; ++p) impl_conout((uint8_t)*p);
#undef STR
#undef _STR
}

/* Init phase: runs in place from PROM 0 (INIT_CODE region).
 * Tail-called by the relocator after it copies resident bytes to
 * 0xED00.  Calls into resident-RAM helpers (impl_conout, snios_*,
 * runtime stubs) work because the relocator already populated
 * 0xED00+ before JPing here.  PROMs are still mapped through
 * netboot completion; resident_handoff (RAM) does the OUT. */
SECTION_INIT_TEXT
NORETURN void cpnos_cold_entry(void) {
    cfgtbl_init();
    init_hardware();

    /* SNIOS drives PIO byte primitives via the linker's
     * --defsym=_xport_send_byte=_transport_pio_send_byte alias
     * (transport_pio.c).  Mark 'P' so the boot strip indicates the
     * physical wire (PIO) regardless of SNIOS envelope above. */
    BOOT_MARK(7, 'P');

    /* IRQ-driven snios-on-PIO needs IFF on during netboot:
     * isr_pio_par fires per chip strobe and pushes bytes into
     * pio_rx_buf for transport_pio_recv_byte to pop. */
    enable_interrupts();

    /* Banner BEFORE netboot so it appears on row 0; netboot dots
     * flow on row 1 (operator's "OS identity at top, progress
     * below" expectation). */
    print_banner();

    uint16_t entry = netboot_mpm();
    BOOT_MARK(15, entry ? '+' : '-');

    /* Tail call into resident RAM -- everything after this point
     * (PROM disable, snios_ntwkin, nos_handoff, enter_coldst) MUST
     * run from RAM because PROM disable un-maps the INIT_CODE region. */
    resident_handoff(entry);
}
