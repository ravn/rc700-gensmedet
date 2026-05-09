/* cpnos-rom interrupt helpers + IM2 ISRs.
 *
 * Z80 IM2 interrupt handling for display refresh + keyboard + PIO-B.
 * IVT lives at 0xEC00 (set up by init.c).  Each entry is a 16-bit
 * pointer to one of the ISR symbols below.
 *
 * Register preservation: every ISR PUSHes only the register pairs it
 * actually clobbers, then POPs them on exit.  Crucially the ISRs do
 * NOT touch the Z80 shadow set (BC'/DE'/HL'/AF') — userspace programs
 * (PolyPascal-compiled binaries, BDS C, WordStar) stash persistent
 * runtime state there and any EX AF,AF' / EXX in an ISR would silently
 * corrupt that state on every interrupt.  None of the ISR bodies use
 * IX/IY.  PolyPascal v3 is a native Z80 compiler (precursor to Turbo
 * Pascal); its compiled programs use the shadow regs as cheap register-
 * bank state across tight inner loops.
 *
 * Phase 3 step 2 (2026-04-26): replaced isr.s.  Co-location with
 * resident.c's BSS vars (kbd_ring, pio_par_*, curx/cury, cur_dirty)
 * is the win — the ISRs and the BSS they touch live in the same
 * compilation unit family now.
 *
 * 2026-04-29: switched from EX AF,AF' + EXX bracket to explicit
 * PUSH/POP per ISR.  EXX swaps the shadow bank into main; userspace
 * code that holds live state in the shadow bank (every PolyPascal v3
 * compiled binary — 216 EXX + 208 EX AF,AF' instructions in PPAS.COM
 * itself) loses that state on every VRTC IRQ.  The new sequence is
 * +6 bytes overall (isr_crt unchanged in size, isr_pio_kbd +4,
 * isr_pio_par +2) but keeps the shadow regs free for userspace.
 *
 * All ISRs live in `.resident.isr` so they survive the OUT (0x18)
 * PROM disable.  The init helpers below (set_i_reg / enable_im2 /
 * enable_interrupts / disable_interrupts) are also resident so they
 * can be called from resident contexts (warm boot path) without a
 * PROM-vs-RAM dance.
 *
 * Cross-compiler note (Phase 1, dual-build): inline asm uses globally-
 * unique labels (e.g. `_isr_crt_no_dirty`) instead of GAS-style
 * numeric local labels (`1:`/`8:`/`jr nz, 8f`).  Numeric local labels
 * differ between clang's GAS-Z80 parser and SDCC's z80asm parser; the
 * unique-label form works in both.  The labels intentionally start
 * with `_` so they don't collide with normal C identifiers and also
 * don't get mangled differently by the two compilers.  See
 * cpnos-rom/compiler/compat.h for the ASM_VOLATILE / __naked /
 * SECTION_RESIDENT_ISR macros.
 */

#include <stdint.h>
#include "compiler/compat.h"
#include "hal.h"   /* FRAME_COUNTER_ADDR */

/* BSS symbols touched by inline asm in this file but defined elsewhere.
 * SDCC's asm emitter only generates EXTERN directives for C-level
 * extern declarations — references in inline-asm strings are invisible
 * to it.  Declare them here at file scope so SDCC emits the right
 * EXTERNs.  Defined in resident.c (kbd_*) and transport_pio.c
 * (pio_rx_*); pio_rx_buf_page is a linker-defined constant
 * (sdcc/sections.asm / payload.ld -> 0xF7). */
#define KBD_RING_SIZE 16
extern uint8_t kbd_ring[KBD_RING_SIZE];
extern volatile uint8_t kbd_head;
extern volatile uint8_t kbd_tail;
extern volatile uint8_t pio_rx_head;
extern volatile uint8_t pio_rx_tail;
extern volatile uint8_t cur_dirty;   /* defined in resident.c */
extern uint8_t curx;
extern uint8_t cury;
/* Linker-defined constant — value is the high byte of pio_rx_buf
 * address, used in inline asm via `ld h, _pio_rx_buf_page`.  Declared
 * here so SDCC emits an asm-level EXTERN directive; the value comes
 * from sdcc/sections.asm (defc) at link time. */
extern uint8_t pio_rx_buf_page;

/* Init-time helpers ------------------------------------------------
 *
 * One-instruction wrappers around the Z80 intrinsics.  Plain C — both
 * compilers reduce these to `LD I, A; RET` / `IM 2; RET` / `EI; RET` /
 * `DI; RET` after inlining the static-inline intrinsic.  No naked
 * needed because the compiler-generated prologue/epilogue is already
 * just RET; saving registers across a one-instruction body is fine.
 */

SECTION_RESIDENT_ISR
void set_i_reg(uint8_t page) { intrinsic_ld_i_a(page); }

SECTION_RESIDENT_ISR
void enable_im2(void)        { intrinsic_im_2(); }

SECTION_RESIDENT_ISR
void enable_interrupts(void) { intrinsic_ei(); }

SECTION_RESIDENT_ISR
void disable_interrupts(void) { intrinsic_di(); }

/* ISRs ------------------------------------------------------------- */

/* No-op ISR for unused IM2 slots.  Must use RETI so the daisy-chained
 * interrupt-priority hardware (CTC, PIO) can advance past this device. */
SECTION_RESIDENT_ISR
void isr_noop(void) __naked {
    ASM_VOLATILE(
        "ei\n\t"
        "reti\n\t"
    );
}

/* CRT refresh ISR.  On each VRTC interrupt:
 *   - ack CRT status read
 *   - mask DMA display+attr channels, clear byte-pointer FF
 *   - (re)load display base address + word count
 *   - (re)load attribute word count = 0 (no attributes used)
 *   - unmask DMA channels
 *   - re-arm CTC ch2 for next frame
 *   - bump 32-bit frame counter at 0xFFFC..0xFFFF (MAME probes read
 *     the low byte to verify the ISR fired; mainline code reads all 4
 *     bytes for a 50 Hz wall-clock-immune timestamp)
 *   - if cur_dirty: push 8275 cursor regs, clear flag (defers per-char
 *     8275 writes from impl_conout to once-per-frame here, eliminating
 *     visible flicker on netboot banner / CCP DIR / etc.)
 *
 * Registers used: A, F, HL.  Save set: AF + HL (4 bytes of PUSH/POP).
 *
 * Mainline writes cur_dirty *after* curx/cury, so reading them here
 * races benignly: we may see a slightly-stale position one frame later,
 * but never a torn pair (single-byte stores are atomic on Z80). */
SECTION_RESIDENT_ISR
void isr_crt(void) __naked {
    ASM_VOLATILE(
        "push af\n\t"
        "push hl\n\t"

        /* 32-bit frame counter at 0xFFFC..0xFFFF — mirrors rcbios's
         * RTC location (RC702_BIOS_SPECIFICATION.md §3.4).  50 Hz ticks
         * (CRT VRTC).  Wraps at ~993 days.  Used by the file-I/O bench
         * to record frames-to-completion (immune to MAME wall-clock
         * variation), and by the MAME taps as the "did the CRT ISR
         * fire" probe (reading the low byte at 0xFFFC suffices — it
         * passes through 0 once every 5.12 s but the test logs the
         * value alongside other counters so a transient zero is
         * unambiguous).  ~13 bytes; INC (HL) sets Z on zero, so
         * propagate carry by jr nz from each byte. */
        "ld   hl, " CPNOS_STR(FRAME_COUNTER_ADDR) "\n\t"
        "inc  (hl)\n\t"
        "jr   nz, _isr_crt_count_done\n\t"
        "inc  hl\n\t"
        "inc  (hl)\n\t"
        "jr   nz, _isr_crt_count_done\n\t"
        "inc  hl\n\t"
        "inc  (hl)\n\t"
        "jr   nz, _isr_crt_count_done\n\t"
        "inc  hl\n\t"
        "inc  (hl)\n\t"
    "_isr_crt_count_done:\n\t"

        /* Ack CRT status register. */
        "in   a, (0x01)\n\t"        /* PORT_CRT_CMD */

        /* Mask DMA channels 2 + 3. */
        "ld   a, 0x06\n\t"
        "out  (0xFA), a\n\t"
        "ld   a, 0x07\n\t"
        "out  (0xFA), a\n\t"

        /* Clear DMA byte-pointer flip-flop, then write the display
         * source addr's low byte (0x00) -- one `xor a` feeds both OUTs
         * (saves 2 B over a separate `ld a, 0x00`). */
        "xor  a\n\t"
        "out  (0xFC), a\n\t"

        /* Display source addr = 0xF800. */
        "out  (0xF4), a\n\t"        /* low byte 0x00 (A still 0) */
        "ld   a, 0xF8\n\t"
        "out  (0xF4), a\n\t"

        /* Display word count = DISPLAY_SIZE-1 = 0x07CF. */
        "ld   a, 0xCF\n\t"
        "out  (0xF5), a\n\t"
        "ld   a, 0x07\n\t"
        "out  (0xF5), a\n\t"

        /* Attribute word count = 0. */
        "xor  a\n\t"
        "out  (0xF7), a\n\t"
        "out  (0xF7), a\n\t"

        /* Unmask channels 2 + 3. */
        "ld   a, 0x02\n\t"
        "out  (0xFA), a\n\t"
        "ld   a, 0x03\n\t"
        "out  (0xFA), a\n\t"

        /* Re-arm CTC ch2 for the next VRTC. */
        "ld   a, 0xD7\n\t"
        "out  (0x0E), a\n\t"
        "ld   a, 0x01\n\t"
        "out  (0x0E), a\n\t"

        /* Deferred 8275 cursor update. */
        "ld   a, (_cur_dirty)\n\t"
        "or   a\n\t"
        "jr   z, _isr_crt_no_dirty\n\t"
        "xor  a\n\t"
        "ld   (_cur_dirty), a\n\t"
        "ld   a, 0x80\n\t"          /* 8275 "load cursor position" */
        "out  (0x01), a\n\t"
        "ld   a, (_curx)\n\t"
        "out  (0x00), a\n\t"
        "ld   a, (_cury)\n\t"
        "out  (0x00), a\n\t"
    "_isr_crt_no_dirty:\n\t"

        "pop  hl\n\t"
        "pop  af\n\t"
        "ei\n\t"
        "reti\n\t"
    );
}

/* PIO-A keyboard ISR.  Fires on each PIO-A interrupt (one per keystroke
 * with PIO-A in input mode + IRQ enabled).  Reads the byte and enqueues
 * to kbd_ring; drops on full ring.  Ring buffer symbols (kbd_ring /
 * kbd_head / kbd_tail) live in resident.c.
 *
 * Registers used: A, F, BC, HL.  Save set: AF + BC + HL (6 bytes of
 * PUSH/POP).  The key byte is stashed on the stack (PUSH AF early,
 * POP AF after the head/tail logic) instead of in E, and new_head is
 * carried in A rather than D — `cp (hl)` lets us compare against
 * (_kbd_tail) without DE. */
SECTION_RESIDENT_ISR
void isr_pio_kbd(void) __naked {
    ASM_VOLATILE(
        "push af\n\t"
        "push bc\n\t"
        "push hl\n\t"

        "in   a, (0x10)\n\t"        /* PORT_PIO_A_DATA -> A = key */
        "push af\n\t"               /* stash key on stack (A goes high byte) */

        /* new_head = (head + 1) & 0x0F, in A */
        "ld   hl, _kbd_head\n\t"
        "ld   a, (hl)\n\t"
        "inc  a\n\t"
        "and  0x0F\n\t"

        /* if (new_head == tail) drop */
        "ld   hl, _kbd_tail\n\t"
        "cp   (hl)\n\t"
        "jr   z, _isr_pio_kbd_drop\n\t"

        /* head = new_head (A still holds new_head) */
        "ld   (_kbd_head), a\n\t"

        /* HL = &ring[old_head] = ring + ((new_head - 1) & 0x0F) */
        "dec  a\n\t"
        "and  0x0F\n\t"
        "ld   l, a\n\t"
        "ld   h, 0\n\t"
        "ld   bc, _kbd_ring\n\t"
        "add  hl, bc\n\t"

        /* Pop key from stack into A (clobbers F — we no longer need it). */
        "pop  af\n\t"
        "ld   (hl), a\n\t"          /* ring[old_head] = key */
        "jr   _isr_pio_kbd_done\n\t"

    "_isr_pio_kbd_drop:\n\t"
        "pop  af\n\t"               /* drop path: discard the stashed key */
    "_isr_pio_kbd_done:\n\t"

        "pop  hl\n\t"
        "pop  bc\n\t"
        "pop  af\n\t"
        "ei\n\t"
        "reti\n\t"
    );
}

/* PIO-B parallel ISR.  Fires once per chip strobe (= once per byte
 * delivered by the bridge) when chip IE is on.  Reads the latched
 * byte from PORT_PIO_B_DATA (the IN itself clears chip IP), pushes
 * into the snios receive ring (pio_rx_buf, head/tail in
 * transport_pio.c).  Mirrors the isr_pio_kbd pattern.
 *
 * Legacy harness counters (pio_par_byte, pio_par_count, pio_rx_count,
 * pio_test_done) are no longer touched here — they were for the
 * host-send / speed-rx test modes which don't use the IRQ-driven
 * recv ring.  --gc-sections drops the unused BSS allocations.
 *
 * Registers used: A, F, HL.  Save set: AF + HL (4 bytes of PUSH/POP).
 * The byte is stashed on the stack between the head/tail check and the
 * ring write; new_head is carried in A; pio_rx_buf is page-aligned so
 * `ld h, _pio_rx_buf_page; ld l, head` builds &ring[head] without BC.
 * Userspace BC/DE/shadow registers all stay intact across the IRQ. */
SECTION_RESIDENT_ISR
void isr_pio_par(void) __naked {
#ifdef TRANSPORT_PROXY
    /* In TRANSPORT=pio-proxy the PIO-B IRQ never fires (init.c keeps
     * the chip's IE bit clear for that mode), but we still publish a
     * vector so the IVT slot resolves.  This stub is just iret. */
    ASM_VOLATILE(
        "ei\n\t"
        "reti\n\t"
    );
#else
    ASM_VOLATILE(
        "push af\n\t"
        "push hl\n\t"

        "in   a, (0x11)\n\t"        /* PORT_PIO_B_DATA -> A; clears chip IP */
        "push af\n\t"               /* stash the byte on the stack */

        /* SPSC ring push for snios.  256-byte buffer at page-aligned
         * address (0xF700 per payload.ld), so HL = page<<8 | head is
         * a single 16-bit address.  uint8_t wrap is free — no mask.
         * new_head = (uint8_t)(head + 1), in A. */
        "ld   hl, _pio_rx_head\n\t"
        "ld   a, (hl)\n\t"
        "inc  a\n\t"

        /* if (new_head == tail) drop — ring full, byte lost. */
        "ld   hl, _pio_rx_tail\n\t"
        "cp   (hl)\n\t"
        "jr   z, _isr_pio_par_drop\n\t"

        /* head = new_head; ring[old_head] = byte.  Page-aligned 256-byte
         * buf — H = buf>>8 (0xf7) is a constant; L = old_head. */
        "ld   (_pio_rx_head), a\n\t"
        "dec  a\n\t"                 /* A = old_head (uint8 wrap) */
        "ld   l, a\n\t"
        "ld   h, _pio_rx_buf_page\n\t"

        "pop  af\n\t"                /* recover stashed byte into A */
        "ld   (hl), a\n\t"           /* ring[old_head] = byte */
        "jr   _isr_pio_par_done\n\t"

    "_isr_pio_par_drop:\n\t"
        "pop  af\n\t"                /* drop path: discard the stashed byte */
    "_isr_pio_par_done:\n\t"

        "pop  hl\n\t"
        "pop  af\n\t"
        "ei\n\t"
        "reti\n\t"
    );
#endif
}
