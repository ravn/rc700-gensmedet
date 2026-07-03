/* boot_entry.c — Cold boot initialization (BOOT_CODE section).
 *
 * Compiled with --codeseg BOOT_CODE so code runs at physical addresses
 * after the BOOT data sections, not at BIOS runtime address.
 * Executes before BIOS relocation.
 *
 * The ROM (ROA375) loads Track 0 to address 0x0000, sets SP to 0xBFFF,
 * and jumps to the boot pointer at offset 0.  That points to coldboot().
 *
 * Memory layout during coldboot execution:
 *
 *   Physical (loaded by ROM)       Runtime (after relocation)
 *   ─────────────────────────      ──────────────────────────
 *   0x0000  BOOT header (128B)     0x0000  CP/M zero page
 *   0x0080  CONFI defaults (128B)  ──→ CFG_ADDR (0xD500, CCP area)
 *   0x0100  Conv tables (384B)     ──→ 0xF680 (OUTCON/INCONV)
 *   0x0280  Boot code (this file)  (discarded after boot)
 *   0x02CE+ BIOS binary            ──→ 0xDA00 (BIOS_BASE)
 *                                      0xDA00  JP table + JTVARS (113B)
 *                                      0xDA71+ BIOS code
 *                                      BSS     ──→ zeroed by coldboot
 *                                      0xF600  IVT + interrupt stack
 *                                      0xF680  OUTCON/INCONV (384B)
 *                                      0xF800  Display memory (80×25)
 *
 * All memcpy/memset calls MUST be inlined by sdcc (no library available).
 * The Makefile checks boot_entry.c.lis for any call _mem* and fails.
 */

#include <string.h>
#include <intrinsic.h>
#include "hal.h"
#include "bios.h"

/* Force LDIR inlining for clang. With -ffreestanding, clang treats memcpy
 * as a regular extern function and emits CALL instead of inlining LDIR.
 * The __builtin_memcpy form always lowers via the Z80 backend's G_MEMCPY
 * → LDIR path. SDCC inlines memcpy() from <string.h> automatically. */
#ifdef __clang__
#define memcpy __builtin_memcpy
#endif

/* Linker symbols for section boundaries.
 * z88dk linker defines these with double underscore; C adds another
 * underscore prefix, so we use single underscore here → ___name in asm. */
extern byte _BOOT_CODE_tail;
extern byte _BIOS_head;
extern byte _bss_compiler_head;
extern word _bss_compiler_size;
extern word _sentinel_addr;     /* sentinel word at end of .data, before .bss */
#define SENTINEL_VALUE 0x1842

/* Data blocks in BOOT_DATA section (defined in boot_confi.c) */
extern const byte confi_on_disk[128];
extern const byte conv_tables[384];

/* Hardware init (in BIOS section, runs after relocation) */
extern void bios_hw_init(void);

/* Cold boot body — called from coldboot() to relocate. SP not set yet so no stack-using functions allowed.
 * Relocates BIOS, copies config data, zeroes BSS.
 *
 * sdcc inlines memcpy as LDIR and memset as LDIR (large) or DJNZ (small).
 * No library functions are linked — verified in the .asm listing. */
__attribute__((section(".boot_code"), used))
void relocate_bios(void)
{
    /* Zero BSS FIRST.  Critical ordering: BSS is unavailable as a spill
     * target until cleared, because +static-stack uses BSS slots in this
     * function's frame area, which overlaps the area being cleared (#51,
     * #53). By doing the clear first, no other operation can spill to
     * BSS before the clear runs.
     *
     * Use linker symbol expressions directly so the compiler resolves
     * them as link-time constants instead of computing via local vars. */
    _bss_compiler_head = 0;
    memcpy(&_bss_compiler_head + 1,
           &_bss_compiler_head,
           (word)&_bss_compiler_size - 1);

    /* Relocate BIOS section from physical to runtime address.
     * BIOS binary starts right after the last BOOT sub-section. */
    memcpy((void *)BIOS_BASE,
           &_BOOT_CODE_tail,
           (word)&_bss_compiler_head - BIOS_BASE);

    /* Copy CONFI defaults to CCP area (init-only) */
    memcpy((void *)CFG_ADDR, confi_on_disk, 128);

    /* Copy conversion tables to runtime address */
    memcpy((void *)CONV_ADDR, conv_tables, 384);
}

/* Verify relocation: the sentinel word at the end of .data (just before
 * .bss) must survive the BSS clear.  If it's been zeroed, the BSS clear
 * overwrote preceding sections — the BIOS is corrupt and must not run.
 *
 * Called from coldboot() after relocate_bios(), before jumping to the
 * relocated BIOS code.  See issue #51. */
__attribute__((section(".boot_code"), used))
void verify_relocation(void)
{
    if (_sentinel_addr != SENTINEL_VALUE)
        // ReSharper disable once CppDFAEndlessLoop
        for (;;) hal_halt();  /* hang — display will show nothing */
}

/* Forward declaration — bios_boot() never returns. */
extern void bios_boot(void);

/* Cold boot entry point.  Called by ROM via boot pointer at offset 0.
 * __naked: no prologue/epilogue.
 *
 * The ROM sets SP to 0xBFFF (safe TPA memory below CCP).  Interrupts
 * are disabled throughout — bios_boot() eventually enables them after
 * setting SP to the BIOS private stack at 0xF500. */
#ifndef __clang__
void coldboot(void) __naked
{
    intrinsic_di();
    relocate_bios();
    verify_relocation();
    bios_hw_init();
    bios_boot();                       /* sets SP to 0xF500, never returns */
}
#endif
/* clang: coldboot is in clang/bios_shims.s */
