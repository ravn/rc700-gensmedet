/* bios_jump_vector_table.c — Clang version of BIOS JP table.
 *
 * Same layout as the SDCC version (rcbios-in-c/bios_jump_vector_table.c)
 * but entry points that need CP/M register translation reference shims
 * in bios_shims.s instead of naked functions in bios.c.
 *
 * Functions that don't need register translation (bios_const, bios_conin,
 * bios_home, bios_read, bios_listst, bios_hrdfmt) reference the C
 * functions directly.
 */

#include "../bios.h"

typedef void (*fptr)(void);

typedef struct {
    byte  opcode;
    fptr  target;
} JpEntry;

/* Direct C functions (no register translation needed) */
extern byte bios_const(void);
extern byte bios_conin(void);
extern void bios_home(void);
extern byte bios_read(void);
extern byte bios_listst(void);
extern void bios_hrdfmt(void);

/* Shims in bios_shims.s (register translation) */
extern void bios_boot_shim(void);
extern void bios_wboot_shim(void);
extern void bios_conout_shim(void);
extern void bios_list_shim(void);
extern void bios_punch_shim(void);
extern void bios_reader_shim(void);
extern void bios_seldsk_shim(void);
extern void bios_settrk_shim(void);
extern void bios_setsec_shim(void);
extern void bios_setdma_shim(void);
extern void bios_write_shim(void);
extern void bios_sectran_shim(void);
extern void bios_wfitr_shim(void);
extern void bios_reads_shim(void);
extern void bios_linsel_shim(void);
extern void bios_exit_shim(void);
extern void bios_clock_shim(void);

/* BIOS page — 113 bytes at BIOSAD (0xDA00 for MSIZE=56).
 * Layout must match the SDCC version exactly. */
const struct {
    /* Standard CP/M 2.2 BIOS jump table (17 entries) */
    JpEntry jt_boot;
    JpEntry jt_wboot;
    JpEntry jt_const;
    JpEntry jt_conin;
    JpEntry jt_conout;
    JpEntry jt_list;
    JpEntry jt_punch;
    JpEntry jt_reader;
    JpEntry jt_home;
    JpEntry jt_seldsk;
    JpEntry jt_settrk;
    JpEntry jt_setsec;
    JpEntry jt_setdma;
    JpEntry jt_read;
    JpEntry jt_write;
    JpEntry jt_listst;
    JpEntry jt_sectran;

    /* JTVARS — runtime config, zeroed here, filled at boot */
    JTVars  jtvars;

    /* Extended jump table */
    byte    resv0;
    JpEntry jt_wfitr;
    JpEntry jt_reads;
    JpEntry jt_linsel;
    JpEntry jt_exit;
    JpEntry jt_clock;
    JpEntry jt_hrdfmt;

    /* Reserved */
    byte    reserved[19];
    word    pchsav;
}
/* section(".bios_jt") is the LTO-safe anchor: this table is the frozen CP/M
 * BIOS ABI and MUST sit at exactly BIOSAD (0xDA00).  Under -flto the linker
 * script's per-file matcher `*bios_jump_vector_table.o(.rodata*)` matches
 * nothing (all TUs merged), so without this attribute the table falls into
 * generic .rodata and _jump_ccp lands at 0xDA00 instead -> CCP/BDOS call the
 * wrong BIOS entries -> no A>.  The attribute follows the variable name so it
 * binds to the object, not the anonymous struct type.  bios.h #defines
 * __attribute__ away under SDCC. */
bios_jump_vector_table __attribute__((section(".bios_jt"), used)) = {
    /* Standard JP table — shims for register translation */
    .jt_boot    = { 0xC3, (fptr)bios_boot_shim },
    .jt_wboot   = { 0xC3, (fptr)bios_wboot_shim },
    .jt_const   = { 0xC3, (fptr)bios_const },          /* direct */
    .jt_conin   = { 0xC3, (fptr)bios_conin },          /* direct */
    .jt_conout  = { 0xC3, (fptr)bios_conout_shim },
    .jt_list    = { 0xC3, (fptr)bios_list_shim },
    .jt_punch   = { 0xC3, (fptr)bios_punch_shim },
    .jt_reader  = { 0xC3, (fptr)bios_reader_shim },
    .jt_home    = { 0xC3, (fptr)bios_home },            /* direct */
    .jt_seldsk  = { 0xC3, (fptr)bios_seldsk_shim },
    .jt_settrk  = { 0xC3, (fptr)bios_settrk_shim },
    .jt_setsec  = { 0xC3, (fptr)bios_setsec_shim },
    .jt_setdma  = { 0xC3, (fptr)bios_setdma_shim },
    .jt_read    = { 0xC3, (fptr)bios_read },            /* direct */
    .jt_write   = { 0xC3, (fptr)bios_write_shim },
    .jt_listst  = { 0xC3, (fptr)bios_listst },          /* direct */
    .jt_sectran = { 0xC3, (fptr)bios_sectran_shim },

    /* JTVARS: zero-initialized except fd0_term */
    .jtvars     = { .fd0_term = 0xFF },

    /* Extended JP table */
    .resv0      = 0,
    .jt_wfitr   = { 0xC3, (fptr)bios_wfitr_shim },
    .jt_reads   = { 0xC3, (fptr)bios_reads_shim },
    .jt_linsel  = { 0xC3, (fptr)bios_linsel_shim },
    .jt_exit    = { 0xC3, (fptr)bios_exit_shim },
    .jt_clock   = { 0xC3, (fptr)bios_clock_shim },
    .jt_hrdfmt  = { 0xC3, (fptr)bios_hrdfmt },          /* direct */
};
