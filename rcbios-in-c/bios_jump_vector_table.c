/* bios_jump_vector_table.c — BIOS JP table + JTVARS + extended JP table (BIOS section).
 *
 * Compiled with --codeseg BIOS --constseg BIOS so the struct lands at
 * the start of the BIOS section (runtime address 0xDA00).
 *
 * The JP entries use { opcode, function_pointer } pairs. sdcc emits
 * DEFB+DEFW with linker-resolved addresses — no runtime init needed.
 *
 * This replaces both the defs 113 in the former crt0.asm and init_bios_jump_vector_table()
 * in bios.c.
 */

#include "bios.h"

typedef void (*fptr)(void);

typedef struct {
    byte  opcode;
    fptr  target;
} JpEntry;

/* Forward declarations for all BIOS entry points */
void bios_boot(void);
void bios_wboot(void);
byte bios_const(void);
byte bios_conin(void);
void bios_conout(void);
void bios_list(void);
void bios_punch(void);
void bios_reader(void);
void bios_home(void);
word bios_seldsk(void);
void bios_settrk(void);
void bios_setsec(void);
void bios_setdma(void);
byte bios_read(void);
byte bios_write(void);
byte bios_listst(void);
word bios_sectran(void);
void bios_wfitr(void);
void bios_reads(void);
void bios_linsel(void);
void bios_exit(void);
void bios_clock(void);
void bios_hrdfmt(void);

/* BIOS page — 113 bytes at 0xDA00.
 *
 * Layout:
 *   0xDA00-0xDA32  Standard CP/M 2.2 JP table (17 × 3 = 51 bytes)
 *   0xDA33-0xDA48  JTVARS (22 bytes, zeroed — filled at boot from CONFI)
 *   0xDA49         Reserved byte (alignment)
 *   0xDA4A-0xDA5B  Extended JP table (6 × 3 = 18 bytes)
 *   0xDA5C-0xDA6E  Reserved (19 bytes)
 *   0xDA6F-0xDA70  Reserved word (was _pchsav)
 */
const struct {
    /* Standard CP/M 2.2 BIOS jump table (17 entries) */
    JpEntry jt_boot;            /* 0xDA00 */
    JpEntry jt_wboot;           /* 0xDA03 */
    JpEntry jt_const;           /* 0xDA06 */
    JpEntry jt_conin;           /* 0xDA09 */
    JpEntry jt_conout;          /* 0xDA0C */
    JpEntry jt_list;            /* 0xDA0F */
    JpEntry jt_punch;           /* 0xDA12 */
    JpEntry jt_reader;          /* 0xDA15 */
    JpEntry jt_home;            /* 0xDA18 */
    JpEntry jt_seldsk;          /* 0xDA1B */
    JpEntry jt_settrk;          /* 0xDA1E */
    JpEntry jt_setsec;          /* 0xDA21 */
    JpEntry jt_setdma;          /* 0xDA24 */
    JpEntry jt_read;            /* 0xDA27 */
    JpEntry jt_write;           /* 0xDA2A */
    JpEntry jt_listst;          /* 0xDA2D */
    JpEntry jt_sectran;         /* 0xDA30 */

    /* JTVARS — runtime config, zeroed here, filled at boot */
    JTVars  jtvars;             /* 0xDA33-0xDA48 (22 bytes) */

    /* Extended jump table */
    byte    resv0;              /* 0xDA49: reserved */
    JpEntry jt_wfitr;           /* 0xDA4A */
    JpEntry jt_reads;           /* 0xDA4D */
    JpEntry jt_linsel;          /* 0xDA50 */
    JpEntry jt_exit;            /* 0xDA53 */
    JpEntry jt_clock;           /* 0xDA56 */
    JpEntry jt_hrdfmt;          /* 0xDA59 */

    /* Reserved */
    byte    reserved[19];       /* 0xDA5C-0xDA6E */
    word    pchsav;             /* 0xDA6F-0xDA70 */
} bios_jump_vector_table = {
    /* Standard JP table */
    .jt_boot    = { 0xC3, (fptr)bios_boot },
    .jt_wboot   = { 0xC3, (fptr)bios_wboot },
    .jt_const   = { 0xC3, (fptr)bios_const },
    .jt_conin   = { 0xC3, (fptr)bios_conin },
    .jt_conout  = { 0xC3, (fptr)bios_conout },
    .jt_list    = { 0xC3, (fptr)bios_list },
    .jt_punch   = { 0xC3, (fptr)bios_punch },
    .jt_reader  = { 0xC3, (fptr)bios_reader },
    .jt_home    = { 0xC3, (fptr)bios_home },
    .jt_seldsk  = { 0xC3, (fptr)bios_seldsk },
    .jt_settrk  = { 0xC3, (fptr)bios_settrk },
    .jt_setsec  = { 0xC3, (fptr)bios_setsec },
    .jt_setdma  = { 0xC3, (fptr)bios_setdma },
    .jt_read    = { 0xC3, (fptr)bios_read },
    .jt_write   = { 0xC3, (fptr)bios_write },
    .jt_listst  = { 0xC3, (fptr)bios_listst },
    .jt_sectran = { 0xC3, (fptr)bios_sectran },

    /* JTVARS: zero-initialized except fd0_term */
    .jtvars     = { .fd0_term = 0xFF },

    /* Extended JP table */
    .resv0      = 0,
    .jt_wfitr   = { 0xC3, (fptr)bios_wfitr },
    .jt_reads   = { 0xC3, (fptr)bios_reads },
    .jt_linsel  = { 0xC3, (fptr)bios_linsel },
    .jt_exit    = { 0xC3, (fptr)bios_exit },
    .jt_clock   = { 0xC3, (fptr)bios_clock },
    .jt_hrdfmt  = { 0xC3, (fptr)bios_hrdfmt },
};
