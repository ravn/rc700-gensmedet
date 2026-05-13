/*
 * rom.h — Types, constants, port I/O, and declarations for RC702 autoload PROM
 *
 * Single header for the entire ROM build.  Combines hardware abstraction
 * (port macros, intrinsics) with boot state declarations and function
 * prototypes.
 *
 * Register-based calling convention: functions take up to 2 parameters
 * and return values via sdcccall(1) ABI (first param in A/HL, second
 * in E/DE, return in L/HL).
 */

#ifndef ROM_H
#define ROM_H

#include <stdint.h>

/* Map SDCC keywords and attribute macros for other compilers.
 *
 *   __z80__: defined by llvm-z80 cross-compiler (clang --target=z80).
 *   __SDCC : defined by SDCC.
 *   HITECH : defined on the command line for HI-TECH C V4.11
 *            (MS-DOS cross compiler hosted via DOSBox).
 *   none of the above: host compiler / IDE (CLion, clangd) — stub. */

/* SECTION(name): place the following declaration in named linker section.
 * NORETURN     : function does not return.
 * USED         : keep the symbol even if unreferenced. */
#if defined(__z80__) && defined(__ELF__)
#define SECTION(name)  __attribute__((section(name)))
#define NORETURN       __attribute__((noreturn))
#define USED           __attribute__((used))
#elif defined(__z80__)
#define SECTION(name)
#define NORETURN       __attribute__((noreturn))
#define USED
#else
#define SECTION(name)
#define NORETURN
#define USED
#endif

#if defined(__z80__)
/* llvm-z80: map SDCC keywords to clang equivalents */
#define __sfr volatile unsigned char
#define __at(x)
#define __interrupt(n) __attribute__((interrupt))
#define __critical
#define __naked
#elif defined(__SDCC)
/* SDCC keywords are native. */
#elif defined(HITECH)
/* HI-TECH C V4.11 has native `interrupt` and `port` qualifiers and rejects
 * the inline keyword.  __critical / __naked have no equivalent; ISR bodies
 * that need them must wrap with di()/ei() or be written in inline asm. */
#define __sfr unsigned char
#define __at(x)
#define __interrupt(n) interrupt
#define __critical
#define __naked
#define inline
/* V4.11 also lacks _Static_assert; provide the classic typedef trick.
 * Two-stage paste so __LINE__ expands before concatenation. */
#define _STATIC_ASSERT_CAT2(a, b) a##b
#define _STATIC_ASSERT_CAT(a, b)  _STATIC_ASSERT_CAT2(a, b)
#define _Static_assert(c, m) \
    typedef char _STATIC_ASSERT_CAT(_sa_, __LINE__)[(c) ? 1 : -1]
#else
/* Host compiler / IDE — no-op SDCC keywords */
#define __sfr volatile unsigned char
#define __at(x)
#define __interrupt(x)
#define __critical
#define __naked
#endif

typedef uint8_t  byte;
typedef uint16_t word;

/* ================================================================
 * Constants
 * ================================================================ */

/* NEC uPD765 (Intel 8272) FDC command bytes.
 * Datasheet: https://www.cpcwiki.eu/imgs/f/f3/UPD765_Datasheet_OCRed.pdf
 * See also Intel 8272A datasheet (pin-compatible clone). */
#define FDC_SENSE_DRIVE   0x04  /* returns ST3 (drive status) */
#define FDC_RECALIBRATE   0x07  /* seek to track 0 */
#define FDC_SENSE_INT     0x08  /* returns ST0 + PCN after seek/recalibrate */
#define FDC_SEEK          0x0F  /* seek to specified cylinder */
#define FDC_READ_DATA     0x06  /* read sector data via DMA */
#define FDC_READ_ID       0x0A  /* read next sector ID (C/H/R/N) from current
                                 * head position without transferring data.
                                 * Used by disk_autodetect() to determine
                                 * sector size (N) and density (FM vs MFM)
                                 * without knowing the disk format in advance.
                                 * Returns 7 result bytes: ST0, ST1, ST2,
                                 * C, H, R, N — where N = sector size code
                                 * (0=128, 1=256, 2=512, 3=1024 bytes). */
#define FDC_MFM           0x40  /* OR with command for MFM (double density) */

/* Stringification macros for inline asm constants */
#define STR_(x) #x
#define STR(x)  STR_(x)

/* Memory layout constants */
#if defined(__z80__)
#define INTVEC_ADDR 0x6000      /* IVT base — clang code is larger, needs room before 0x7A00 */
#else
#define INTVEC_ADDR 0x7200      /* IVT base — page-aligned, room for CODE before 0x7A00 */
#endif
#define INTVEC_PAGE (INTVEC_ADDR >> 8)  /* I register value (0x73) */
#define ROM_STACK   0xBFFF      /* Stack set by ROM entry / INIT_RELOCATED */
#define FLOPPYDATA  0x0000      /* Track 0 loaded here by ROM */
#define LEGACYBOOT   0x1000      /* COMAL-80 boot address */
#define PROM1_ADDR  0x2000      /* Secondary PROM (network boot) */
#define DIROFF      0x0B60      /* Directory start in Track 0 */
#define DIREND_HI   0x0D        /* Directory end high byte */
#define DSPSTR_ADDR 0x7A00      /* Display refresh memory (80x25) */
#define DSP_CHARS   0x0780      /* Display buffer size (1920 bytes) */
#define ATTOFF      7           /* Attribute byte offset in dir entry */
#define SECSZ0      0x80        /* Sector size for Track 0 Side 0 (128B) */

/* Boot signature offsets in Track 0 */
#define RC700_SIG_OFF  0x0002   /* " RC700" signature at offset 2 */
#define RC702_SIG_OFF  0x0008   /* " RC702" signature at offset 8 */
#define BOOT_DIR_OFF   0x0B80   /* Directory area for RC702 format */

/* Display buffer — mapped to CRT refresh memory */
#define dspstr         ((byte *)DSPSTR_ADDR)
#define scroll_offset  (*(word *)(DSPSTR_ADDR + 0x07F5))

/* Transfer control to address — never returns.
 * Uses a function pointer call (CALL, not JP).  The dangling return
 * address on the stack is harmless since the target never returns. */
#define jump_to(addr) ((void (*)(void))(addr))()

/* ================================================================
 * Z80 port I/O — inline IN/OUT on all backends
 * ================================================================
 *
 * DEFPORT(name, addr) generates per-port inline functions:
 *   port_in_##name()      — reads port, returns uint8_t
 *   port_out_##name(val)  — writes val to port
 *
 * All backends produce inline IN A,(n) / OUT (n),A — 2 bytes each.
 *   clang:       __attribute__((address_space(2))) pointer dereference
 *   sdcc/sccz80: static __sfr __at inside inline function body
 *   other:       no-op stubs for IDE indexing
 *
 * Usage:  port_in(fdc_status)        — reads FDC status register
 *         port_out(fdc_data, 0x42)   — writes 0x42 to FDC data register
 */

#if defined(__z80__)
/* Port I/O via address_space(2) — the compiler lowers pointer dereferences
 * in address space 2 to Z80 IN A,(n) / OUT (n),A instructions. */
#define __io __attribute__((address_space(2)))
#define DEFPORT(name, addr) \
    static inline uint8_t port_in_##name(void) { \
        return *(volatile __io uint8_t *)(uint8_t)(addr); \
    } \
    static inline void port_out_##name(uint8_t val) { \
        *(volatile __io uint8_t *)(uint8_t)(addr) = val; \
    }
#define port_in(name)       port_in_##name()
#define port_out(name, val) port_out_##name(val)
#elif defined(__SDCC) || defined(__SCCZ80)
/* sdcc emits standalone copies of static inline functions even when
 * unused, wasting space in tight sections like BOOT.  Use __sfr __at
 * declarations (zero code — just defc equates) and read/write them
 * as plain variables.  The port_in/port_out macros handle the mapping. */
#define DEFPORT(name, addr) __sfr __at (addr) _sfr_##name;
#define port_in(name)       (_sfr_##name)
#define port_out(name, val) (_sfr_##name = (val))
#elif defined(HITECH)
/* HI-TECH C V4.11 has a native `port` type qualifier that emits IN/OUT
 * directly.  Port addresses are bound at link time by --defsym (see
 * hitech/Makefile); the C source only declares the symbolic names. */
#define DEFPORT(name, addr) port unsigned char _hp_##name;
#define port_in(name)       (_hp_##name)
#define port_out(name, val) (_hp_##name = (val))
#else
#define DEFPORT(name, addr) \
    static inline uint8_t port_in_##name(void) { \
        volatile uint8_t _hw = 0; return _hw; } \
    static inline void port_out_##name(uint8_t val) { (void)val; }
#define port_in(name)       port_in_##name()
#define port_out(name, val) port_out_##name(val)
#endif

/* RC702 I/O port declarations */
DEFPORT(crt_param,    0x00)
DEFPORT(crt_cmd,      0x01)
DEFPORT(fdc_status,   0x04)
DEFPORT(fdc_data,     0x05)
DEFPORT(ctc0,         0x0C)
DEFPORT(ctc1,         0x0D)
DEFPORT(ctc2,         0x0E)
DEFPORT(ctc3,         0x0F)
DEFPORT(pio_a_data,   0x10)
DEFPORT(pio_b_data,   0x11)
DEFPORT(pio_a_ctrl,   0x12)
DEFPORT(pio_b_ctrl,   0x13)
DEFPORT(sw1,          0x14)
DEFPORT(ramen,        0x18)
DEFPORT(bib,          0x1C)
DEFPORT(chargen_char, 0xD1)    /* SEM 702 character generator: character number */
DEFPORT(chargen_dot,  0xD2)    /* SEM 702 character generator: dot line number */
DEFPORT(chargen_data, 0xD3)    /* SEM 702 character generator: pixel data byte */
DEFPORT(dma_ch1_addr, 0xF2)
DEFPORT(dma_ch1_wc,   0xF3)
DEFPORT(dma_ch2_addr, 0xF4)
DEFPORT(dma_ch2_wc,   0xF5)
DEFPORT(dma_ch3_addr, 0xF6)
DEFPORT(dma_ch3_wc,   0xF7)
DEFPORT(dma_cmd,      0xF8)
DEFPORT(dma_smsk,     0xFA)
DEFPORT(dma_mode,     0xFB)
DEFPORT(dma_clbp,     0xFC)

/* Hardware access macros */
#define read_sw1()              port_in(sw1)
#define diskette_size()         ((port_in(sw1) >> 7) & 1)
#define prom_disable()          port_out(ramen, 1)
#define motor(on)               port_out(sw1, (on) ? 1 : 0)
#define beep()                  port_out(bib, 0)

#define fdc_command(cmd)        port_out(fdc_data, (cmd))
#define fdc_status()            port_in(fdc_status)
#define fdc_data_read()         port_in(fdc_data)
#define fdc_data_write(d)       port_out(fdc_data, (d))

#define dma_command(cmd)        port_out(dma_cmd, (cmd))
#define dma_mask(ch)            port_out(dma_smsk, (ch) | 0x04)
#define dma_unmask(ch)          port_out(dma_smsk, (ch))
#define dma_clear_bp()          port_out(dma_clbp, 0)
#define dma_mode(m)             port_out(dma_mode, (m))
#define dma_status()            port_in(dma_cmd)

#define pio_write_a_data(d)     port_out(pio_a_data, (d))
#define pio_write_a_ctrl(d)     port_out(pio_a_ctrl, (d))
#define pio_write_b_data(d)     port_out(pio_b_data, (d))
#define pio_write_b_ctrl(d)     port_out(pio_b_ctrl, (d))

#define crt_param(d)            port_out(crt_param, (d))
#define crt_command(d)          port_out(crt_cmd, (d))
#define crt_status()            port_in(crt_cmd)

/* DI/EI/IM2/set_i_reg intrinsics */
#ifdef __SDCC
#include <intrinsic.h>
static void set_i_reg(byte page) {
    (void) page;  /* sdcccall(1) passes byte in A */
    __asm__("ld i, a\n");
}
#elif defined(__z80__)
#include "clang/intrinsic.h"
static inline void intrinsic_im_2(void) { __asm__ volatile("im 2"); }
#elif defined(HITECH)
/* V4.11 inline asm syntax: asm("string") at statement level. */
static void intrinsic_di(void)   { asm("    di"); }
static void intrinsic_ei(void)   { asm("    ei"); }
static void intrinsic_im_2(void) { asm("    im 2"); }
static void set_i_reg(byte page) { (void) page; asm("    ld i,a"); }
#else
static inline void intrinsic_di(void) {}
static inline void intrinsic_ei(void) {}
static inline void intrinsic_im_2(void) {}
static inline void set_i_reg(byte page) { (void) page; }
#endif
#define ei()  intrinsic_ei()
#define di()  intrinsic_di()

/* Set stack pointer — must be first operation in entry point.
 * SDCC: inline asm with # prefix for immediates.
 * Clang: inline asm without # prefix. */
#ifdef __SDCC
#define SET_SP(addr) __asm__("ld sp, #" STR(addr) "\n")
#elif defined(__z80__)
#define SET_SP(addr) __asm__ volatile("ld sp, " STR(addr))
#elif defined(HITECH)
#define SET_SP(addr) asm("    ld sp," STR(addr))
#else
#define SET_SP(addr) ((void)0)
#endif

/* CTC channel writes */
#define ctc0_write(d)           port_out(ctc0, (d))
#define ctc1_write(d)           port_out(ctc1, (d))
#define ctc2_write(d)           port_out(ctc2, (d))
#define ctc3_write(d)           port_out(ctc3, (d))

/* DMA channel address/word count — two consecutive port writes.
 * The local word _t avoids double-loading the argument from memory:
 * volatile I/O stores prevent CSE of the surrounding loads. */
#define dma_ch1_addr(a) do { word _t=(a); port_out(dma_ch1_addr,(byte)_t); port_out(dma_ch1_addr,(byte)(_t>>8)); } while(0)
#define dma_ch1_wc(w)   do { word _t=(w); port_out(dma_ch1_wc,(byte)_t);   port_out(dma_ch1_wc,(byte)(_t>>8));   } while(0)
#define dma_ch2_addr(a) do { word _t=(a); port_out(dma_ch2_addr,(byte)_t); port_out(dma_ch2_addr,(byte)(_t>>8)); } while(0)
#define dma_ch2_wc(w)   do { word _t=(w); port_out(dma_ch2_wc,(byte)_t);   port_out(dma_ch2_wc,(byte)(_t>>8));   } while(0)
#define dma_ch3_addr(a) do { word _t=(a); port_out(dma_ch3_addr,(byte)_t); port_out(dma_ch3_addr,(byte)(_t>>8)); } while(0)
#define dma_ch3_wc(w)   do { word _t=(w); port_out(dma_ch3_wc,(byte)_t);   port_out(dma_ch3_wc,(byte)(_t>>8));   } while(0)

/* ================================================================
 * Stuff in boot.c
 * ================================================================ */

void fdc_write_when_ready(byte val);
byte fdc_read_when_ready(void);
void delay(byte outer, byte inner);

/* ================================================================
 * Boot state — extern declarations
 * ================================================================ */

/*
 * Individual globals, initialized to zero.
 * Z80: BSS is inside CODE (no separate ORG), so variables are part of
 * the PROM payload — copied to RAM by start() as zeros.
 */

/* FDC result bytes.  After Read Data / Read ID:
 *   st0, st1, st2, cylinder, head, sector, size_code, dma_status
 * After Sense Drive Status:
 *   st3 (in st0 position)
 * After Sense Interrupt Status:
 *   st0, pcn (present cylinder, in st1 position)
 * The dma_status byte is read from the DMA controller after transfer,
 * not from the FDC itself.
 *
 * See uPD765 datasheet Table 3 for result phase byte definitions:
 *   https://www.cpcwiki.eu/imgs/f/f3/UPD765_Datasheet_OCRed.pdf */

typedef struct {
    byte st0;           /* ST0: IC(7-6), SE(5), EC(4), NR(3), HD(2), US(1-0) */
    byte st1;           /* ST1: EN, DE, OR, ND, NW, MA — or PCN after Sense Int */
    byte st2;           /* ST2: CM(6), DD, WC, SH, SN, BC, MD, MA */
    byte cylinder;      /* C: cylinder number at end of operation */
    byte head;          /* H: head number */
    byte sector;        /* R: sector number */
    byte size_code;     /* N: sector size code (0=128, 1=256, 2=512, 3=1024, etc. we only use 128, 256 and 512) */
    byte dma_status;    /* DMA controller status (read after FDC result phase) */
} fdc_result_block;

extern fdc_result_block fdc_result;
extern byte drive_select;      /* drive select */
extern byte fdc_isr_delay;      /* FDC timeout counter (init=3) */
extern byte fdc_result_delay;      /* FDC wait count (init=4) */
/* FDC command parameter block — 7 contiguous bytes sent by floppy_read_track().
 * Fields map to uPD765 Read Data parameters: C, H, R, N, EOT, GPL, DTL. */
typedef struct {
    byte cylinder;
    byte head;
    byte sector;
    byte size_shift;     /* N value: sector size = 128 << N */
    byte eot;            /* end of track (last sector number) */
    byte gap3;           /* gap 3 length */
    byte dtl;            /* data length (0x80 when N > 0) */
} fdc_command_block;

extern fdc_command_block fdc_cmd;
extern volatile byte floppy_operation_completed_flag; /* floppy interrupt flag (0=idle, 2=done) */
extern byte is_mini;              /* 1=mini/5.25", 0=maxi/8" (from SW1 bit 7) */
extern byte is_mfm;              /* 1=MFM (double density), 0=FM (single) */
extern byte disk_type;      /* disk type flag */
extern byte more_tracks_to_read;      /* more data flag */
extern byte retry_count;      /* retry count */
extern word dma_transfer_address;     /* DMA memory address */
extern word dma_transfer_size;      /* transfer byte count */
extern word bytes_left_to_read;     /* bytes remaining to read */
extern byte error_saved;      /* saved error code */

/* ================================================================
 * Function declarations
 * ================================================================ */

/* init — init_pio/ctc/dma/crt/fdc are all static in rom.c */

/* fmt */
void lookup_sectors_and_gap3_for_current_track(void);

void calc_size_of_current_track(void);

/* fdc */
void fdc_sense_interrupt(void);
/* fdc_seek: static in rom.c (single call site) */
void fdc_read_result(void);
byte fdc_select_drive_cylinder_head(void);
void fdc_write_full_cmd(byte cmd);
byte wait_fdc_ready(byte timeout);
byte check_fdc_result(void);
byte fdc_get_result_bytes(byte cmd, byte retries);
byte fdc_detect_sector_size_and_density(void);

/* boot */
/* display_banner_and_start_crt: static in rom.c (single call site) */
void error_display_halt(byte code);
void floppy_legacy_boot(void);
void prom1_if_present(void);
NORETURN void halt_forever(void);
byte compare_6bytes(const byte *a, const byte *b);
byte check_sysfile(const byte *dir, const char *pattern);
void syscall(word addr, word de);

/* entry points and linker-visible symbols */
void start(void);
void main_relocated(void);
extern const byte code_end;
#if defined(__z80__)
extern const char banner_string[];
#endif

#endif /* ROM_H */
