/*
 * intvec.c — Z80 IM2 interrupt vector table
 *
 * 16 entries at 0x7000 (page-aligned, I register = 0x70).
 * Placed in INTVEC section via #pragma constseg.
 * Compiled with default codeseg (no --codeseg flag needed).
 */

/* Suppress set_i_reg emission — it's static in rom.h but unused here.
 * Without this guard, SDCC emits set_i_reg (3 bytes) before intvec[],
 * misaligning the IVT away from the required $xx00 page boundary. */
#ifdef __SDCC
#define __INTVEC_ONLY
#endif
#include "rom.h"

/* ISR declarations — defined in rom.c.
 * Declared here (not in rom.h) because SDCC requires __interrupt(n) on
 * declarations to match definitions, and the attribute is per-ISR. */
extern void nothing_int(void);
extern void refresh_crt_dma_50hz_interrupt(void);
extern void floppy_completed_operation_interrupt(void);

typedef void (*isr_t)(void);
extern const isr_t intvec[16];  /* forward decl for -Wmissing-variable-declarations */

#ifdef __SDCC
#pragma constseg CODE
#endif

/* used: LTO must not DCE this array — the Z80 hardware addresses it via the
 * I register (IM2), invisible to the compiler's reference analysis. */
#if defined(__LLVMZ80)
__attribute__((section("intvec_compiler"), used))
#elif defined(__z80__)
__attribute__((used))
#endif
const isr_t intvec[16] = {
    nothing_int,     /*  +0: Dummy */
    nothing_int,     /*  +2: PIO Port A */
    nothing_int,     /*  +4: PIO Port B */
    nothing_int,     /*  +6: Dummy */
    nothing_int,     /*  +8: CTC CH0 */
    nothing_int,     /* +10: CTC CH1 */
    refresh_crt_dma_50hz_interrupt,     /* +12: CTC CH2 — Display refresh */
    floppy_completed_operation_interrupt,     /* +14: CTC CH3 — Floppy completion */
    nothing_int,     /* +16: Dummy */
    nothing_int,     /* +18: Dummy */
    nothing_int,     /* +20: Dummy */
    nothing_int,     /* +22: Dummy */
    nothing_int,     /* +24: Dummy */
    nothing_int,     /* +26: Dummy */
    nothing_int,     /* +28: Dummy */
    nothing_int,     /* +30: Dummy */
};
