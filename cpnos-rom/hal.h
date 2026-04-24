/* cpnos-rom hardware abstraction — port addresses only
 *
 * Port numbers match the RC702/MIC702 I/O map (see autoload-in-c/rom.h
 * and rcbios-in-c/hal.h for the canonical list).  Reads/writes go
 * through clang's address_space(2) which lowers to IN A,(n) / OUT (n),A.
 */
#ifndef CPNOS_HAL_H
#define CPNOS_HAL_H

#include <stdint.h>

#define __io __attribute__((address_space(2)))

static inline uint8_t _port_in(uint16_t p) {
    return *(volatile __io uint8_t *)p;
}
static inline void _port_out(uint16_t p, uint8_t v) {
    *(volatile __io uint8_t *)p = v;
}

/* Canonical RC702 port map (typed: 1-byte I/O addresses) */
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

/* 8237 DMA controller.  Channel assignment on RC702:
 *   ch0 = J8 expansion (unused on-board)
 *   ch1 = µPD765 FDC
 *   ch2 = 8275 CRT display
 *   ch3 = 8275 CRT attribute plane */
enum : uint16_t {
    PORT_DMA_CH1_ADDR = 0xF2,
    PORT_DMA_CH1_WC   = 0xF3,
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

#endif /* CPNOS_HAL_H */
