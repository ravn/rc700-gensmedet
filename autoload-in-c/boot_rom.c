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

#include <string.h>
/* Suppress set_i_reg from rom.h — it is not needed in the BOOT section
 * and must NOT appear before start() at 0x0000 (Z80 reset vector). */
#ifdef __SDCC
#define __INTVEC_ONLY
#endif
#include "rom.h"

extern void main_relocated(void);

/* ================================================================
 * Compiler-specific: linker symbols, banner, NMI
 * ================================================================ */

#if defined(__z80__)

extern char _code_load[], _code_start[], _code_size[];
extern char _bss_start[], _bss_size[];

/* ZX0 decompressor + wrapper in clang/dzx0_standard.s.  reloc_zx0()
 * loads HL=__text_zx0_start, DE=__code_start and falls through to
 * dzx0_standard, replacing the prior raw LDIR-via-memcpy copy step
 * with a ZX0 decompression. */
extern void reloc_zx0(void);

/* Banner string — NUL-terminated, referenced by display_banner in CODE.
 * memcpy copies exactly BUILD_BANNER_LENGTH bytes; the NUL is not transferred.
 *
 * Section .textbanner (not .pagezero.data): the linker routes it into the
 * ZX0-compressed .text payload (VMA in RAM), so the banner costs compressed
 * bytes instead of a full uncompressed copy in the scarce pre-NMI ROM.  It is
 * read after decompression via BANNER_PTR = &banner_string, which resolves to
 * the RAM address automatically. */
#include "build_stamp.h"
#ifdef __ELF__
__attribute__((section(".textbanner"), used))
#endif
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

/* SDCC 4.6+ (ravn/z88dk native): --codeseg BOOT generates section _BOOT,
 * whose tail symbol is ___BOOT_tail (C name __BOOT_tail).
 * SDCC 4.1 (z88dk:2.4 Docker): generates section BOOT → __BOOT_tail (C: _BOOT_tail). */
#ifdef __ZSDCC_SECTION_BOOT_UNDERSCORE
extern byte __BOOT_tail;
#define _boot_tail_ptr (&__BOOT_tail)
#else
extern byte _BOOT_tail;
#define _boot_tail_ptr (&_BOOT_tail)
#endif
extern const byte intvec;
extern const byte code_end;

#define RELOC_DST   ((void *)&intvec)
#define RELOC_SRC   ((const void *)_boot_tail_ptr)
/* Copy full PROM slot minus BOOT: 0x1000 - ___BOOT_tail.
 * This includes all library sections (memcpy etc.) that sit above user code. */
#define RELOC_SIZE  ((unsigned)(0x1000u - (unsigned)_boot_tail_ptr))
#define BSS_DST     ((void *)0)
#define BSS_SIZE    ((unsigned)0)

/* Forward declaration so start() (which must be first at 0x0000) can call it. */
static void boot_reloc(void *dst, const void *src, unsigned len) __naked;

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

#ifdef __ELF__
__attribute__((section(".pagezero.text")))
#endif
#ifdef __clang__
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmissing-noreturn"
#endif
void start(void) {  /* not marked noreturn: allows tail-call JP to main_relocated */
    // Executing at 0x0000 - be very careful about library routines
    intrinsic_di();
    SET_SP(ROM_STACK);
#if defined(__ELF__)
    reloc_zx0();
    // BSS is non-empty (> 1 byte). Zero first byte and propagate via LDIR;
    // __bss_start is loaded once into HL without redundant runtime checks.
    __asm__ volatile(
        "ld\thl, __bss_start\n\t"
        "ld\t(hl), 0\n\t"
        "ld\td, h\n\t"
        "ld\te, l\n\t"
        "inc\tde\n\t"
        "ld\tbc, __bss_size - 1\n\t"
        "ldir"
        ::: "a", "b", "c", "d", "e", "h", "l", "memory"
    );
#elif defined(__SDCC)
    /* boot_reloc uses LDIR inline (in _BOOT section) — library memcpy is
     * in CODE section and not yet in RAM when start() runs from ROM. */
    boot_reloc(RELOC_DST, RELOC_SRC, RELOC_SIZE);
    if (BSS_SIZE)
        memset(BSS_DST, 0, BSS_SIZE);
#else
    memcpy(RELOC_DST, RELOC_SRC, RELOC_SIZE);
    if (BSS_SIZE)
        memset(BSS_DST, 0, BSS_SIZE);
#endif
    // Jump to relocated code.
    main_relocated();
}
#ifdef __clang__
#pragma clang diagnostic pop
#endif

/* ================================================================
 * SDCC-only: banner and NMI padding
 * ================================================================ */

#if defined(__SDCC) || defined(__SCCZ80)

/* Banner string — normal NUL-terminated C string in BOOT section */
#include "build_stamp.h"
const char banner_string[] = BUILD_BANNER;

/* Pad to NMI vector at 0x0066 */
void pad_to_nmi_retn(void) __naked {
    __asm__("DEFS 0x0066 - ASMPC, 0xFF\n"
        "retn\n");
}

/* boot_reloc: LDIR copy of CODE from ROM to RAM.
 * Defined AFTER start() so start() lands at 0x0000 (Z80 reset vector).
 * Placed in _BOOT section (same as start), runs from ROM before relocation.
 * Cannot use library memcpy — it's in CODE (not yet in RAM when called).
 *
 * sdcccall(1) on z80: 3-arg function — arg1(dst)→HL, arg2(src)→DE,
 * arg3(len) pushed on stack (overflow). Stack on entry:
 *   [SP+0..1] = return address
 *   [SP+2..3] = len
 * LDIR needs: HL=src, DE=dst, BC=len. */
#ifdef __SDCC
static void boot_reloc(void *dst, const void *src, unsigned len) __naked {
    (void)dst; (void)src; (void)len;
    __asm__(
        "ex de, hl\n"     /* HL=src, DE=dst */
        "push hl\n"       /* save src; stack: [sp]=src,[sp+2]=ret,[sp+4]=len */
        "ld hl, #4\n"
        "add hl, sp\n"    /* HL → &len on stack */
        "ld c, (hl)\n"
        "inc hl\n"
        "ld b, (hl)\n"    /* BC = len */
        "pop hl\n"        /* HL = src again; stack: [sp]=ret,[sp+2]=len */
        "ldir\n"
        "ret\n"           /* caller cleans up pushed len */
    );
}
#endif

#endif
