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

/* Map SDCC keywords for other compilers.
 * __z80__: defined by llvm-z80 cross-compiler (clang --target=z80).
 * __SDCC: defined by SDCC.
 * Neither: host compiler / IDE (CLion, clangd) — stub everything. */
#if defined(__z80__) || defined(__LLVMZ80)
/* llvm-z80: map SDCC keywords to clang equivalents */
#define __sfr volatile unsigned char
#define __at(x)
#define __interrupt(n) __attribute__((interrupt))
#define __critical
#define __naked        __attribute__((naked))
#define NORETURN __attribute__((noreturn))
#define ISR_BODY_INLINE static __attribute__((always_inline)) inline
#define ALWAYS_INLINE static __attribute__((always_inline)) inline
#elif defined(__SDCC)
#define NORETURN
#define ISR_BODY_INLINE static inline
#define ALWAYS_INLINE static inline
#else
/* Host compiler / IDE — no-op SDCC keywords */
#define __sfr volatile unsigned char
#define __at(x)
#define __interrupt(x)
#define __critical
#define __naked
#define NORETURN __attribute__((noreturn))
#define ISR_BODY_INLINE static inline
#define ALWAYS_INLINE static inline
#endif

typedef uint8_t  byte;
typedef uint16_t word;

#if defined(__clang__)
/* Under -ffreestanding, Clang generates library calls (call _memcpy, call _memset)
 * pulling in compiler-rt. __builtin_memcpy generates @llvm.memcpy which Z80 lowers
 * directly to inline LDIR. For memset, writing the 1st byte and copying via
 * self-overlapping LDIR produces 100% inline Z80 code with zero library calls:
 *   e.g. memset(0x7830, ' ', 2000) -> ld (0x7830), ' '; ldir 0x7830->0x7831, 1999 */
#undef memcpy
#define memcpy(d, s, n) __builtin_memcpy((d), (s), (n))
#undef memset
#define memset(d, c, n) do { \
    size_t _n = (size_t)(n); \
    if (_n != 0) { \
        byte *_dst = (byte *)(d); \
        *_dst = (byte)(c); \
        if (_n > 1) \
            __builtin_memcpy(_dst + 1, _dst, _n - 1); \
    } \
} while (0)
#endif

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
#if defined(__z80__) || defined(__LLVMZ80)
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
/* Display refresh memory (80x25 = 2000 bytes).
 * clang: code relocates to 0x6000 (INTVEC_ADDR), so the framebuffer sits just
 * below 0x8000 — 0x7830..0x8000 — keeping it entirely in the original 32 KB
 * RAM (the roa375-era top-of-RAM placement; roa375 itself used 0x7800).  The
 * old 0x7A00 crossed 0x8000 into the upper RAM that only exists on 64 KB
 * machines.
 * SDCC: code relocates to 0x7200, which would overlap 0x7830, so its (MAME-only,
 * 64 KB-emulated) build keeps the display at 0x7A00. */
#if defined(__z80__) || defined(__LLVMZ80)
#define DSPSTR_ADDR 0x7830
#else
#define DSPSTR_ADDR 0x7A00
#endif
#define DSP_CHARS   0x07D0      /* Display buffer size (2000 bytes = 80x25) */
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
 * Uses inline assembly on clang/llvmz80 to perform a clean jump (push addr; ret)
 * without an indirect C function call.  Indirect function pointer calls map to
 * CallsExternalNode in LLVM's CallGraph, creating a cycle that forces callers
 * to allocate reentrant frame pointers (IX).
 * Fallback to function pointer call for SDCC / SCCZ80. */
#if defined(__z80__) || defined(__LLVMZ80)
#define jump_to(addr) do { \
    __asm__ volatile("push %0\n\tret" : : "r"((word)(addr))); \
    __builtin_unreachable(); \
} while (0)
#else
#define jump_to(addr) ((void (*)(void))(addr))()
#endif

/* ================================================================
 * Z80 port I/O — inline IN/OUT on all backends
 * ================================================================
 *
 * DEFPORT(name, addr) declares a port address constant `name`;
 * port_in(name) / port_out(name, val) then do the actual IN/OUT.
 *
 * All backends produce inline IN A,(n) / OUT (n),A — 2 bytes each.
 *   clang:       inline asm with "a"/"i" constraints (accumulator +
 *                immediate port), letting the register allocator place
 *                the value/result instead of forcing a memory access
 *   sdcc/sccz80: static __sfr __at inside inline function body
 *   other:       no-op stubs for IDE indexing
 *
 * Usage:  port_in(fdc_status)        — reads FDC status register
 *         port_out(fdc_data, 0x42)   — writes 0x42 to FDC data register
 */

#if defined(__z80__) || defined(__LLVMZ80)
/* Port I/O via inline asm.  Previously this used a volatile
 * __attribute__((address_space(2))) pointer dereference, which the
 * legalizer could not lower for a plain (non-address_space) G_STORE
 * feeding it (ravn/llvm-z80 crash: "unable to legalize instruction:
 * G_STORE ... addrspace 2" in fdc_write_when_ready) — reproduced with
 * the exact production build flags (-Oz +static-frame +shadow-regs),
 * not just -O2.  Inline asm with "a" (accumulator) / "i" (immediate
 * port) constraints asks for exactly the two real Z80 instructions
 * and sidesteps the address-space legalizer path entirely.
 * DEFPORT just binds `name` to the port number (an enum constant, so
 * it's usable as the "i" immediate operand below) — no per-port
 * function is generated. */
#define DEFPORT(name, addr) enum { name = (addr) };
#define port_in(name)       __builtin_z80_in((uint8_t)(name))
#define port_out(name, val) __builtin_z80_out((uint8_t)(name), (uint8_t)(val))
#elif defined(__SDCC) || defined(__SCCZ80)
/* sdcc emits standalone copies of static inline functions even when
 * unused, wasting space in tight sections like BOOT.  Use __sfr __at
 * declarations (zero code — just defc equates) and read/write them
 * as plain variables.  The port_in/port_out macros handle the mapping. */
#define DEFPORT(name, addr) __sfr __at (addr) _sfr_##name;
#define port_in(name)       (_sfr_##name)
#define port_out(name, val) (_sfr_##name = (val))
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

/* SW1 DIP switch bit masks (port 0x14).
 * Canonical values in ../sw1_config.mk and docs/SW1_BIT_MAP.md.
 * Switch On = 0 (default), Switch Off = 1. */
#ifndef SW1_CONSOLE_BIT
#define SW1_CONSOLE_BIT       0x01  /* S01: joined SIO-B console / debug */
#endif
#ifndef SW1_LINEPROG_BIT
#define SW1_LINEPROG_BIT      0x02  /* S02: PROM1 lineprog enable check */
#endif
#ifndef SW1_TRANSPORT_BIT
#define SW1_TRANSPORT_BIT     0x04  /* S03: CP/NET transport: 0=PIO, 1=SIO */
#endif
#define SW1_RESERVED_S04_BIT  0x08  /* S04: reserved */
#define SW1_RESERVED_S05_BIT  0x10  /* S05: reserved */
#define SW1_RESERVED_S06_BIT  0x20  /* S06: reserved */
#define SW1_RESERVED_S07_BIT  0x40  /* S07: reserved */
#ifndef SW1_FLOPPY_MINI_BIT
#define SW1_FLOPPY_MINI_BIT   0x80  /* S08: 0=8" maxi (500k), 1=5.25" mini (250k) */
#endif
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
/* __INTVEC_ONLY: defined in intvec.c to suppress set_i_reg emission there.
 * set_i_reg is static, so SDCC emits it in every TU that includes rom.h,
 * even if it's unused. This would push intvec[] away from the $xx00 boundary
 * required for Z80 IM2 (I register must point to exact start of IVT). */
#ifndef __INTVEC_ONLY
static void set_i_reg(byte page) {
    (void) page;  /* sdcccall(1) passes byte in A */
    __asm__("ld i, a\n");
}
#endif
#elif defined(__z80__) || defined(__LLVMZ80)
#include "clang/intrinsic.h"
static inline void intrinsic_im_2(void) { __asm__ volatile("im 2"); }
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
#elif defined(__z80__) || defined(__LLVMZ80)
#define SET_SP(addr) __asm__ volatile("ld sp, " STR(addr))
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

/* delay — static in rom.c (boot_rom.c has its own copy) */

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

/* fmt, fdc — all static in rom.c */

/* boot */
/* display_banner_and_start_crt: static in rom.c (single call site) */
/* error_display_halt, floppy_legacy_boot, prom1_if_present, halt_forever,
 * compare_6bytes, check_sysfile, syscall — all static in rom.c */

/* entry points and linker-visible symbols */
void start(void);
void main_relocated(void);
extern const byte code_end;
#if defined(__z80__) || defined(__LLVMZ80)
extern const char banner_string[];
#endif

#endif /* ROM_H */
