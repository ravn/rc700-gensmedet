/*
 * boot_rom.c — BOOT section code.
 *
 * Lives in ROM at ORG 0x0000, accessible until prom_disable().
 *
 * start() is the shared entry point: DI, set SP, copy CODE to RAM,
 * zero BSS, jump to main_relocated.  Clang inlines memcpy/memset
 * as LDIR; SDCC links against its standard library.
 *
 * Compiler-specific parts: linker symbols, banner string, and
 * NMI handler (address 0x0066).
 */

/* Include order matters under HI-TECH C V4.11: rom.h's port declarations
 * must precede <string.h>'s memcpy/memset declarations, otherwise the
 * downstream cgen pass silently emits empty output.  Order-independent
 * for clang and SDCC; only V4.11 is sensitive. */
#include "rom.h"
#include <string.h>

extern void main_relocated(void);

/* ================================================================
 * Compiler-specific: linker symbols, banner, NMI
 * ================================================================ */

#if defined(__z80__)

extern char _code_load[], _code_start[], _code_size[];
extern char _bss_start[], _bss_size[];

/* Banner string — NUL-terminated, referenced by display_banner in CODE.
 * memcpy copies exactly BUILD_BANNER_LENGTH bytes; the NUL is not transferred. */
#include "clang/banner.h"
SECTION(".pagezero.data") USED
const char banner_string[] = BUILD_BANNER;
_Static_assert(sizeof(banner_string) - 1 == BUILD_BANNER_LENGTH, "banner length mismatch");
_Static_assert(BUILD_BANNER_LENGTH <= 80, "banner must fit in one display line");

/* NMI handler — placed at 0x0066 by linker script (.nmi section). */
__asm__(
    ".section .nmi,\"ax\"\n"
    ".globl _nmi_handler\n"
    "_nmi_handler:\n"
    "\tretn\n"
    ".section .text\n"
);

#define RELOC_DST   (_code_start)
#define RELOC_SRC   ((const void *)_code_load)
#define RELOC_SIZE  ((unsigned)_code_size)
#define BSS_DST     (_bss_start)
#define BSS_SIZE    ((unsigned)_bss_size)

#elif defined(__SDCC)

extern byte _BOOT_tail;
extern const byte intvec;
extern const byte code_end;

#define RELOC_DST   ((void *)&intvec)
#define RELOC_SRC   ((const void *)&_BOOT_tail)
#define RELOC_SIZE  ((unsigned)(&code_end - &intvec + 1))
#define BSS_DST     ((void *)0)
#define BSS_SIZE    ((unsigned)0)

#elif defined(HITECH)

/* HI-TECH V4.11: the linker auto-generates standard section-bound symbols.
 * Names below are placeholders — the actual link-time symbols depend on
 * the -A flag and psect specification.  See hitech/Makefile. */
#include "hitech/banner.h"
USED const char banner_string[] = BUILD_BANNER;

extern char _Lcode_load[], _Lcode_start[], _Lcode_end[];
extern char _Lbss_start[], _Lbss_end[];

#define RELOC_DST   ((void *)_Lcode_start)
#define RELOC_SRC   ((const void *)_Lcode_load)
#define RELOC_SIZE  ((unsigned)(_Lcode_end - _Lcode_start))
#define BSS_DST     ((void *)_Lbss_start)
#define BSS_SIZE    ((unsigned)(_Lbss_end - _Lbss_start))

#else
/* IDE fallback — stubs so CLion can parse start() */
#define RELOC_DST   ((void *)0)
#define RELOC_SRC   ((const void *)0)
#define RELOC_SIZE  ((unsigned)0)
#define BSS_DST     ((void *)0)
#define BSS_SIZE    ((unsigned)0)

#endif

/* ================================================================
 * Shared entry point: DI, set SP, relocate CODE, zero BSS, start
 *
 * For Clang: placed at 0x0000 by linker script (ENTRY(_start)).
 * For SDCC: must be the first function in the BOOT section.
 * ================================================================ */

SECTION(".pagezero.text")
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmissing-noreturn"
void start(void) {  /* not marked noreturn: allows tail-call JP to main_relocated */
    // Executing at 0x0000 - be very careful about library routines
    intrinsic_di();
    SET_SP(ROM_STACK);
    memcpy(RELOC_DST, RELOC_SRC, RELOC_SIZE);
    // Now code is in its intended locaiton.
    if (BSS_SIZE)
        memset(BSS_DST, 0, BSS_SIZE);
    // Jump to relocated code.
    main_relocated();
}
#pragma clang diagnostic pop

/* ================================================================
 * SDCC-only: banner and NMI padding
 * ================================================================ */

#ifdef __SDCC

/* Banner string — normal NUL-terminated C string in BOOT section */
#include "sdcc/build_stamp.h"
const char banner_string[] = BUILD_BANNER;

/* Pad to NMI vector at 0x0066 */
void pad_to_nmi_retn(void) __naked {
    __asm__("DEFS 0x0066 - ASMPC, 0xFF\n"
        "retn\n");
}

#endif
