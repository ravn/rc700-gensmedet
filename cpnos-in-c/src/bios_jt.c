/* bios_jt.c — BIOS jump table for the clang/LLVM-Z80 build.
 *
 * Replaces bios_jt.s.  Uses the { 0xC3, target } JpEntry pattern from
 * rcbios-in-c/bios_jump_vector_table.c — a packed struct whose first byte is
 * the Z80 JP opcode and second/third bytes are the linker-resolved target
 * address.  Placed in .resident.jumptable so the linker script KEEP brings it
 * to the very start of the .resident region (VMA 0xEE00 = BIOS_BASE).
 *
 * Linker ASSERTs (payload.ld) verify _bios_boot == 0xEE00, CONOUT at +12,
 * SECTRAN at +48.  The inline-asm aliases below export _bios_boot,
 * _bios_conout, _bios_sectran as linker symbols without changing payload.ld.
 */
#include <stdint.h>
#include "compiler/compat.h"

typedef void (*bios_fptr)(void);
typedef struct { uint8_t op; bios_fptr target; } __attribute__((packed)) JpEntry;

/* Forward declarations — implementations in resident.c */
void impl_boot(void);
void impl_wboot(void);
void bios_const_shim(void);
void bios_conin_shim(void);
void bios_conout_shim(void);
void bios_stub_ret(void);

__attribute__((section(".resident.jumptable")))
const struct {
    JpEntry boot;       /* +00  0xEE00 */
    JpEntry wboot;      /* +03  0xEE03 */
    JpEntry const_;     /* +06  0xEE06 */
    JpEntry conin;      /* +09  0xEE09 */
    JpEntry conout;     /* +12  0xEE0C */
    JpEntry list;       /* +15  0xEE0F */
    JpEntry punch;      /* +18  0xEE12 */
    JpEntry reader;     /* +21  0xEE15 */
    JpEntry home;       /* +24  0xEE18 */
    JpEntry seldsk;     /* +27  0xEE1B */
    JpEntry settrk;     /* +30  0xEE1E */
    JpEntry setsec;     /* +33  0xEE21 */
    JpEntry setdma;     /* +36  0xEE24 */
    JpEntry read;       /* +39  0xEE27 */
    JpEntry write;      /* +42  0xEE2A */
    JpEntry listst;     /* +45  0xEE2D */
    JpEntry sectran;    /* +48  0xEE30 */
} bios_jt = {
    .boot    = { 0xC3, impl_boot },
    .wboot   = { 0xC3, impl_wboot },
    .const_  = { 0xC3, bios_const_shim },
    .conin   = { 0xC3, bios_conin_shim },
    .conout  = { 0xC3, bios_conout_shim },
    .list    = { 0xC3, bios_stub_ret },
    .punch   = { 0xC3, bios_stub_ret },
    .reader  = { 0xC3, bios_stub_ret },
    .home    = { 0xC3, bios_stub_ret },
    .seldsk  = { 0xC3, bios_stub_ret },
    .settrk  = { 0xC3, bios_stub_ret },
    .setsec  = { 0xC3, bios_stub_ret },
    .setdma  = { 0xC3, bios_stub_ret },
    .read    = { 0xC3, bios_stub_ret },
    .write   = { 0xC3, bios_stub_ret },
    .listst  = { 0xC3, bios_stub_ret },
    .sectran = { 0xC3, bios_stub_ret },
};

/* Export legacy linker symbols so payload.ld ASSERTs keep working unchanged. */
__asm__(".global _bios_boot\n_bios_boot = _bios_jt");
__asm__(".global _bios_wboot\n_bios_wboot = _bios_jt + 3");
__asm__(".global _bios_conout\n_bios_conout = _bios_jt + 12");
__asm__(".global _bios_sectran\n_bios_sectran = _bios_jt + 48");
