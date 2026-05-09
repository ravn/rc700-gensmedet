/* cpnos-rom hardware abstraction — port addresses and port I/O.
 *
 * Port numbers match the RC702/MIC702 I/O map (see autoload-in-c/rom.h
 * and rcbios-in-c/hal.h for the canonical list).
 *
 * The .c files always call `_port_in(p)` / `_port_out(p, v)` with a
 * port number and value.  The same call-shape works for compile-time
 * constants and for runtime-selected ports (the port_init iteration
 * loop in init.c uses the runtime form).
 *
 * Backends:
 *   clang z80    : inline IN A,(n) / OUT (n),A via address_space(2)
 *   SDCC (zsdcc) : extern function in hal_sdcc.s (OUT (C),A / IN A,(C))
 *   HiTech zc    : TODO — currently #error until verified on real zc
 *   host clang   : LSP/IDE no-op stubs (compiles, doesn't run)
 *
 * Per the clarity-in-c-code rule the call shape is identical across
 * backends.  No DEFPORT macros, no per-port-name expansion: a reader
 * sees `_port_out(PORT_RAMEN, 0)` and that's exactly what runs.
 */
#ifndef CPNOS_HAL_H
#define CPNOS_HAL_H

#include <stdint.h>

/* ================================================================
 * Backend selection: _port_in / _port_out.
 *
 * Same signature in every backend:
 *     uint8_t _port_in (uint8_t port);
 *     void    _port_out(uint8_t port, uint8_t value);
 *
 * Z80 IN/OUT instructions are fundamentally 8-bit (port on A0-A7).
 * On RC702, A8-A15 are not decoded for I/O, so the wider type that
 * was previously used (uint16_t, "for historical reasons") has no
 * functional effect.  Narrowing to uint8_t matches the actual hardware
 * (#76).  Backends use 8-bit port directly: clang's address_space(2)
 * lowers to `IN A,(n)`/`OUT (n),A` for constants and `IN A,(C)`/
 * `OUT (C),A` for runtime ports; SDCC's hal.asm uses the (C) form.
 * ================================================================ */

#if defined(__clang__) && defined(__z80__)
/* clang Z80 backend: address_space(2) lowers to IN/OUT directly. */
#define __io __attribute__((address_space(2)))
static inline uint8_t _port_in(uint8_t p) {
    return *(volatile __io uint8_t *)(uint16_t)p;
}
static inline void _port_out(uint8_t p, uint8_t v) {
    *(volatile __io uint8_t *)(uint16_t)p = v;
}

#elif defined(__SDCC) || defined(__SCCZ80)
/* SDCC / sccz80: __sfr requires a constant address, so per-port
 * helpers don't compose into a runtime-port call.  Instead provide
 * extern functions implemented in hal_sdcc.s — same call-shape,
 * costs ~17 T-states per call (CALL + asm body + RET) versus ~12 T
 * inline.  Fine on boot init paths.  Hot-path SDCC code can still
 * use __sfr __at directly if it must shave the call. */
extern uint8_t _port_in (uint8_t p);
extern void    _port_out(uint8_t p, uint8_t v);

#elif defined(__HITECH__) || defined(HI_TECH_C)
/* HiTech C (zc / Hi-Tech Z80 C, ravn/hitech via ghcr.io/ravn/hitech).
 * TODO: port helper API not yet verified.  Likely candidates are
 * inp(port) / outp(port, val) (matching MS-DOS conio) or per-port
 * builtins.  Until validated, fail loud rather than guess.
 *
 * When implementing: keep the _port_in / _port_out signatures so
 * the .c sources compile unchanged. */
#error "cpnos-rom: HiTech C port not yet implemented (see hal.h)"

#else
/* Host clang on macOS (CLion LSP, no real Z80 target).  Stubs let
 * the IDE parse the sources cleanly — no diagnostics, no codegen. */
static inline uint8_t _port_in(uint8_t p) { (void)p; return 0; }
static inline void    _port_out(uint8_t p, uint8_t v) { (void)p; (void)v; }
#endif

/* ================================================================
 * Canonical RC702 port map (typed: 1-byte I/O addresses)
 * ================================================================ */

enum : uint8_t {
    PORT_CRT_PARAM    = 0x00,
    PORT_CRT_CMD      = 0x01,
    PORT_FDC_STATUS   = 0x04,
    PORT_FDC_DATA     = 0x05,
    PORT_SIO_A_DATA   = 0x08,
    PORT_SIO_B_DATA   = 0x09,
    PORT_SIO_A_CTRL   = 0x0A,
    PORT_SIO_B_CTRL   = 0x0B,
    PORT_CTC0         = 0x0C,
    PORT_CTC1         = 0x0D,
    PORT_CTC2         = 0x0E,
    PORT_CTC3         = 0x0F,
    PORT_PIO_A_DATA   = 0x10,
    PORT_PIO_B_DATA   = 0x11,
    PORT_PIO_A_CTRL   = 0x12,
    PORT_PIO_B_CTRL   = 0x13,
    PORT_SW1          = 0x14,   /* DIP switch read (not ROM disable) */
    PORT_RAMEN        = 0x18,   /* any write disables both PROMs */
    PORT_BIB          = 0x1C
};

/* SIO RR0 bits (status register 0, shared by both channels) */
enum : uint8_t {
    SIO_RR0_RX_CHAR_AVAIL = 0x01,
    SIO_RR0_TX_BUF_EMPTY  = 0x04,
    SIO_RR0_DCD           = 0x08,
    SIO_RR0_CTS           = 0x20
};

/* 8237 DMA controller — channel 2 = CRT display, channel 3 = CRT attr.
 * Narrowed from uint16_t to uint8_t in #76: all values fit in 8 bits;
 * Z80 I/O is 8-bit on the wire; RC702 doesn't decode A8-A15 for I/O. */
enum : uint8_t {
    PORT_DMA_CH2_ADDR = 0xF4,
    PORT_DMA_CH2_WC   = 0xF5,
    PORT_DMA_CH3_ADDR = 0xF6,
    PORT_DMA_CH3_WC   = 0xF7,
    PORT_DMA_CMD      = 0xF8,
    PORT_DMA_SMSK     = 0xFA,
    PORT_DMA_MODE     = 0xFB,
    PORT_DMA_CLBP     = 0xFC
};

#define DISPLAY_ADDR 0xF800
#define DISPLAY_SIZE 2000        /* 80 x 25 */

/* 32-bit frame counter at 0xFFFC..0xFFFF, incremented by isr_crt
 * on every CRT VRTC tick (50 Hz).  Top of the Z80 address space,
 * just above display memory.  Mirrors rcbios's RTC location
 * (RC702_BIOS_SPECIFICATION.md §3.4).  Bench / test harnesses read
 * this as a wall-clock counter immune to MAME's variable speed. */
#define FRAME_COUNTER_ADDR 0xFFFC

/* Boot-progress marker: write a char to display row 0, right-justified
 * starting at column BOOT_MARK_BASE (=60).  Indices 0..18 occupy cols
 * 60..78 — the upper-right corner.  Call only after init_hardware
 * (CRT alive).  Reserved indices 0..6 = "INIT OK" written by
 * init_hardware; 8..14 by netboot_mpm; 15..18 by cpnos_main.
 *
 * Upper-right placement keeps markers visible after nos_handoff prints
 * the "RC702 CP/NOS v1.2" banner on row 1 and after CCP starts writing
 * its prompt at (0,0) — only a long scroll past row 24 ages them out.
 *
 * Build-time gated by BOOT_MARK_ENABLED (Makefile -D, default 1).
 * Set to 0 for a production / size-constrained PROM and the macro
 * collapses to a no-op; about 30-50 B saved.  Useful during bring-up,
 * dead weight once the boot path is solid.
 *
 * The local volatile `_dst` is *not* cosmetic.  Without it clang's
 * Z80 backend folds `((uint8_t*)0xF800)[CONST + const]` as
 * `0xF800 + CONST + const`, dropping any further `+i` runtime offset
 * (UB-class fold — same issue family as ravn/llvm-z80#49).  Forcing
 * the base through a variable defeats the fold. */
#define BOOT_MARK_BASE 60
#ifndef BOOT_MARK_ENABLED
#define BOOT_MARK_ENABLED 1
#endif
#if BOOT_MARK_ENABLED
#define BOOT_MARK(col, ch) do { \
    volatile uint8_t *_dst = (volatile uint8_t *)DISPLAY_ADDR; \
    _dst[BOOT_MARK_BASE + (col)] = (uint8_t)(ch); \
} while (0)
#else
#define BOOT_MARK(col, ch) ((void)0)
#endif

#endif /* CPNOS_HAL_H */
