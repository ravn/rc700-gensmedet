/*
 * AVR cycle-count harness for gf_log() — bug 4 unpark Phase 1.
 * Brackets gf_log(0..255) with Timer1 + overflow counter (Timer1 prescaler =
 * clk/1, so one tick = one cycle).  Reports total cycles via simavr console
 * (GPIOR0 = 0x3E) as ASCII hex.
 *
 * No <avr/io.h> dependency — register addresses written directly via
 * volatile pointers (atmega328p datasheet, §15 Timer/Counter 1).
 *
 * Methodology:
 *   - Timer1 is 16-bit free-running with no prescaler (TCCR1B = 0x01).
 *     One tick = one cycle.
 *   - Before the hot loop, write 'S' to console as a wall-clock marker.
 *   - After the hot loop, sum overflows<<16 + TCNT1, emit as 8 hex digits.
 *   - Volatile sink prevents the optimizer from eliding gf_log() calls.
 *   - Loop count = 256 calls.  At ~3 K cycles per call → ~768 K cycles total,
 *     well above simavr startup overhead (~5 K), so the measurement is
 *     dominated by gf_log itself.
 */

#include <stdint.h>
#include "/Users/ravn/z80/simavr/simavr/sim/avr/avr_mcu_section.h"

#define F_CPU 16000000UL
AVR_MCU_SIMAVR_CONSOLE(0x3E);
AVR_MCU(F_CPU, "atmega328p");

/* atmega328p I/O register addresses (datasheet §35.1 register summary).
 * Reading TCNT1 (low first, then high) is atomic via the AVR's internal
 * TEMP register — must read low first to latch the high byte. */
#define TCCR1A   (*(volatile uint8_t  *)0x80)
#define TCCR1B   (*(volatile uint8_t  *)0x81)
#define TCNT1L   (*(volatile uint8_t  *)0x84)
#define TCNT1H   (*(volatile uint8_t  *)0x85)
#define TIFR1    (*(volatile uint8_t  *)0x36)
#define TOV1_BIT 0x01

/* External: K&R gf_log from aes256.c (tableless path). */
extern uint8_t gf_log(uint8_t x);

static volatile uint8_t *console = (volatile uint8_t *)0x3E;
static void putch(char c) { *console = c; }
static void putstr(const char *s) { while (*s) putch(*s++); }
static void puthex(uint8_t v) {
    const char hex[] = "0123456789abcdef";
    putch(hex[(v >> 4) & 0xF]);
    putch(hex[v & 0xF]);
}
static void puthex16(uint16_t v) {
    puthex((uint8_t)(v >> 8));
    puthex((uint8_t)(v & 0xFF));
}
static void puthex32(uint32_t v) {
    puthex16((uint16_t)(v >> 16));
    puthex16((uint16_t)(v & 0xFFFF));
}

static uint16_t read_tcnt1(void) {
    uint8_t lo, hi;
    lo = TCNT1L;        /* low first → AVR latches high into TEMP */
    hi = TCNT1H;
    return ((uint16_t)hi << 8) | lo;
}

/* Volatile sink prevents the optimizer from eliding gf_log() calls. */
volatile uint8_t sink;

int main(void) {
    uint16_t i;
    uint16_t overflows;
    uint32_t cycles;
    uint16_t final_tcnt;

    putstr("gf_log AVR cycle oracle\n");

    /* Timer1: clk/1, no prescaler.  Tick = cycle. */
    TCCR1A = 0;
    TCCR1B = 0x01;

    overflows = 0;
    TCNT1L = 0;
    TCNT1H = 0;
    TIFR1 = TOV1_BIT;   /* clear overflow (write-1-to-clear) */

    putch('S');

    for (i = 0; i < 256; i++) {
        sink = gf_log((uint8_t)i);
        if (TIFR1 & TOV1_BIT) {
            overflows++;
            TIFR1 = TOV1_BIT;
        }
    }

    final_tcnt = read_tcnt1();
    cycles = ((uint32_t)overflows << 16) | final_tcnt;

    putch('E');
    putstr("\nCYCLES=");
    puthex32(cycles);
    putstr("\n");

    for (;;) {}
}
