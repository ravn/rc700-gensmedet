/*
 * hal.h — Hardware Abstraction Layer for RC702 CP/M BIOS
 *
 * Port I/O compiles to inline IN/OUT on all Z80 backends:
 *   clang:       __attribute__((address_space(2)))
 *   sdcc/sccz80: __sfr __at
 *   HOST_TEST:   no-op stubs
 */

#ifndef HAL_H
#define HAL_H

#include <stdint.h>

/* ================================================================
 * Port I/O — DEFPORT macro, same approach as autoload-in-c/rom.h
 * ================================================================ */

/* RC702 I/O port addresses */
#define PORT_CRT_PARAM    0x00
#define PORT_CRT_CMD      0x01
#define PORT_FDC_STATUS   0x04
#define PORT_FDC_DATA     0x05
#define PORT_SIO_A_DATA   0x08
#define PORT_SIO_B_DATA   0x09
#define PORT_SIO_A_CTRL   0x0A
#define PORT_SIO_B_CTRL   0x0B
#define PORT_CTC0         0x0C
#define PORT_CTC1         0x0D
#define PORT_CTC2         0x0E
#define PORT_CTC3         0x0F
#define PORT_PIO_A_DATA   0x10
#define PORT_PIO_B_DATA   0x11
#define PORT_PIO_A_CTRL   0x12
#define PORT_PIO_B_CTRL   0x13
#define PORT_SW1          0x14

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
#define PORT_BELL         0x1C
#define PORT_CTC2_CH0     0x44
#define PORT_CTC2_CH1     0x45
#define PORT_CTC2_CH2     0x46
#define PORT_CTC2_CH3     0x47
#define PORT_HD_DATA      0x60
#define PORT_HD_ERROR     0x61
#define PORT_HD_SECCT     0x62
#define PORT_HD_SECNO     0x63
#define PORT_HD_CYLLO     0x64
#define PORT_HD_CYLHI     0x65
#define PORT_HD_SDH       0x66
#define PORT_HD_STATUS    0x67
/* Am9517A DMA controller — base address 0xF0
 *
 * Channel assignments (compile-time configurable):
 *   CH0 = hard disk (WD1000)
 *   CH1 = floppy (NEC µPD765)
 *   CH2 = display data (Intel 8275 CRT)
 *   CH3 = display attributes (Intel 8275 CRT)
 *
 * To reassign channels (e.g. for memory-to-memory DMA), change the
 * DMA_CH_* defines below.  All port addresses, mode register values,
 * and mask register values are derived automatically. */

#define DMA_CH_HD      0   /* hard disk */
#define DMA_CH_FLOPPY  1   /* floppy disk controller */
#define DMA_CH_DISPLAY 2   /* 8275 CRT display data */
#define DMA_CH_DISATTR 3   /* 8275 CRT display attributes */

/* Am9517A register encoding (derived from channel number) */
#define DMA_ADDR_PORT(ch)   (0xF0 + 2 * (ch))      /* channel address register */
#define DMA_WC_PORT(ch)     (0xF0 + 2 * (ch) + 1)  /* channel word count register */
#define DMA_MASK_SET(ch)    (0x04 | (ch))           /* single mask: disable channel */
#define DMA_MASK_CLR(ch)    (ch)                    /* single mask: enable channel */
#define DMA_MODE_MEM2IO(ch) (0x48 | (ch))           /* single mode, mem→IO (8237 "read") */
#define DMA_MODE_IO2MEM(ch) (0x44 | (ch))           /* single mode, IO→mem (8237 "write") */

/* Port addresses derived from channel assignments */
#define PORT_DMA_FLP_ADDR  DMA_ADDR_PORT(DMA_CH_FLOPPY)
#define PORT_DMA_FLP_WC    DMA_WC_PORT(DMA_CH_FLOPPY)
#define PORT_DMA_DSP_ADDR  DMA_ADDR_PORT(DMA_CH_DISPLAY)
#define PORT_DMA_DSP_WC    DMA_WC_PORT(DMA_CH_DISPLAY)
#define PORT_DMA_ATR_ADDR  DMA_ADDR_PORT(DMA_CH_DISATTR)
#define PORT_DMA_ATR_WC    DMA_WC_PORT(DMA_CH_DISATTR)

/* DMA control registers (fixed, not channel-dependent) */
#define PORT_DMA_CMD      0xF8
#define PORT_DMA_REQ      0xF9
#define PORT_DMA_SMSK     0xFA
#define PORT_DMA_MODE     0xFB
#define PORT_DMA_CLBP     0xFC
#define PORT_DMA_TMP      0xFD
#define PORT_DMA_MASK     0xFF

/* DEFPORT: one macro, three backends.
 *
 * Two API forms:
 *   port_in/port_out(name, val)   — name is a constant identifier (compile-time)
 *   port_in_rt/port_out_rt(p, v)  — p is a runtime byte (port number)
 *
 * The _rt form lets one helper handle multiple ports (e.g., SIO channel A vs B
 * selected at runtime). Requires #44 fix on clang side. */
#if defined(__clang__) && defined(__z80__)
/* Z80 port I/O via compiler builtins: __builtin_z80_in / __builtin_z80_out.
 * Emits direct IN A,(n) / OUT (n),A for constant ports, and IN r,(C) / OUT (C),r for variable. */
#define DEFPORT(name, addr) enum { name = (addr) };
#define port_in(name)       __builtin_z80_in((uint8_t)(name))
#define port_out(name, val) __builtin_z80_out((uint8_t)(name), (uint8_t)(val))
#define port_in_rt(p)       __builtin_z80_in((uint8_t)(p))
#define port_out_rt(p, v)   __builtin_z80_out((uint8_t)(p), (uint8_t)(v))
#elif defined(__SDCC) || defined(__SCCZ80)
#define DEFPORT(name, addr) __sfr __at (addr) _sfr_##name;
#define port_in(name)       (_sfr_##name)
#define port_out(name, val) (_sfr_##name = (val))
/* SDCC has no clean way to do runtime port I/O in pure C —
 * __sfr requires constant addresses. Code that needs runtime port
 * selection must use per-port helpers + a dispatcher (see bios.c
 * sio_wr5 for an example). */
#else
#define DEFPORT(name, addr) \
    static inline uint8_t port_in_##name(void) { \
        volatile uint8_t _hw = 0; return _hw; } \
    static inline void port_out_##name(uint8_t val) { (void)val; }
#define port_in(name)       port_in_##name()
#define port_out(name, val) port_out_##name(val)
#define port_in_rt(p)       ((uint8_t)0)
#define port_out_rt(p, v)   ((void)(p), (void)(v))
#endif

DEFPORT(crt_param,    PORT_CRT_PARAM)
DEFPORT(crt_cmd,      PORT_CRT_CMD)
DEFPORT(fdc_status,   PORT_FDC_STATUS)
DEFPORT(fdc_data,     PORT_FDC_DATA)
DEFPORT(sio_a_data,   PORT_SIO_A_DATA)
DEFPORT(sio_b_data,   PORT_SIO_B_DATA)
DEFPORT(sio_a_ctrl,   PORT_SIO_A_CTRL)
DEFPORT(sio_b_ctrl,   PORT_SIO_B_CTRL)
DEFPORT(ctc0,         PORT_CTC0)
DEFPORT(ctc1,         PORT_CTC1)
DEFPORT(ctc2,         PORT_CTC2)
DEFPORT(ctc3,         PORT_CTC3)
DEFPORT(pio_a_data,   PORT_PIO_A_DATA)
DEFPORT(pio_b_data,   PORT_PIO_B_DATA)
DEFPORT(pio_a_ctrl,   PORT_PIO_A_CTRL)
DEFPORT(pio_b_ctrl,   PORT_PIO_B_CTRL)
DEFPORT(sw1,          PORT_SW1)
DEFPORT(bell,         PORT_BELL)
DEFPORT(ctc2_ch0,     PORT_CTC2_CH0)
DEFPORT(ctc2_ch1,     PORT_CTC2_CH1)
DEFPORT(ctc2_ch2,     PORT_CTC2_CH2)
DEFPORT(ctc2_ch3,     PORT_CTC2_CH3)
DEFPORT(dma_flp_addr, PORT_DMA_FLP_ADDR)
DEFPORT(dma_flp_wc,   PORT_DMA_FLP_WC)
DEFPORT(dma_dsp_addr, PORT_DMA_DSP_ADDR)
DEFPORT(dma_dsp_wc,   PORT_DMA_DSP_WC)
DEFPORT(dma_atr_addr, PORT_DMA_ATR_ADDR)  /* display attributes (currently unused content) */
DEFPORT(dma_atr_wc,   PORT_DMA_ATR_WC)
DEFPORT(dma_cmd,      PORT_DMA_CMD)
DEFPORT(dma_req,      PORT_DMA_REQ)
DEFPORT(dma_smsk,     PORT_DMA_SMSK)
DEFPORT(dma_mode,     PORT_DMA_MODE)
DEFPORT(dma_clbp,     PORT_DMA_CLBP)
DEFPORT(dma_tmp,      PORT_DMA_TMP)
DEFPORT(dma_mask,     PORT_DMA_MASK)
DEFPORT(hd_data,      PORT_HD_DATA)
DEFPORT(hd_error,     PORT_HD_ERROR)
DEFPORT(hd_secct,     PORT_HD_SECCT)
DEFPORT(hd_secno,     PORT_HD_SECNO)
DEFPORT(hd_cyllo,     PORT_HD_CYLLO)
DEFPORT(hd_cylhi,     PORT_HD_CYLHI)
DEFPORT(hd_sdh,       PORT_HD_SDH)
DEFPORT(hd_status,    PORT_HD_STATUS)

/* ================================================================
 * DMA channel helpers, CPU control, sdcc keyword compatibility
 * ================================================================ */

/* DMA channel address/word count (two consecutive port writes, low then high) */
#define hal_dma_flp_addr(a) do { port_out(dma_flp_addr,(uint8_t)(a)); port_out(dma_flp_addr,(uint8_t)((a)>>8)); } while(0)
#define hal_dma_flp_wc(w)   do { port_out(dma_flp_wc,(uint8_t)(w));   port_out(dma_flp_wc,(uint8_t)((w)>>8));   } while(0)
#define hal_dma_dsp_addr(a) do { port_out(dma_dsp_addr,(uint8_t)(a)); port_out(dma_dsp_addr,(uint8_t)((a)>>8)); } while(0)
#define hal_dma_dsp_wc(w)   do { port_out(dma_dsp_wc,(uint8_t)(w));   port_out(dma_dsp_wc,(uint8_t)((w)>>8));   } while(0)
#define hal_dma_atr_wc(w)   do { port_out(dma_atr_wc,(uint8_t)(w));   port_out(dma_atr_wc,(uint8_t)((w)>>8));   } while(0)

/* Inline-asm volatile portability shim.
 *
 * Outputless inline asm in clang must be `__asm__ volatile(...)` to
 * survive DCE after inlining (otherwise the body silently disappears).
 * SDCC's gcc-compat `__asm__("...")` parser does NOT accept the
 * `volatile` keyword — it errors with `syntax error: token -> 'volatile'`.
 * SDCC inline asm is implicitly volatile and never DCE'd, so the
 * keyword is unnecessary there.
 *
 * Use ASM_VOLATILE("...") in shared-source asm blocks. */
#ifdef __clang__
#define ASM_VOLATILE(...) __asm__ volatile(__VA_ARGS__)
#else
#define ASM_VOLATILE(...) __asm__(__VA_ARGS__)
#endif

#if defined(__SDCC) || defined(__SCCZ80)
/* Z80 inline helpers */
#define hal_ei()    __asm__("ei")
#define hal_di()    __asm__("di")
#define hal_halt()  __asm__("halt")
#elif defined(__clang__)
/* clang: keyword stubs and intrinsics from clang/intrinsic.h.
 * Found via -Iclang on the compile command line. */
#include <intrinsic.h>
#define hal_ei()   intrinsic_ei()
#define hal_di()   intrinsic_di()
#define hal_halt() intrinsic_halt()
#endif

#endif /* HAL_H */
