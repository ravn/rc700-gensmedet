/* cpnos-rom byte-level transport backend (PIO-B parallel) + IM2 ISRs.
 *
 * Two halves merged Phase 60 (2026-05-10) — they shared the
 * RESIDENT_PRE_CODE SDCC codeseg and the PIO-B receive ring buffer
 * (`pio_rx_buf` + head/tail), so co-locating them lets isr_pio_par
 * push directly into the file-static buffer instead of crossing TUs:
 *
 *   1. PIO transport layer (former transport_pio.c body):
 *      - transport_pio_send_byte / transport_pio_recv_byte
 *      - direction-flip workaround for ravn/mame#7
 *      - pio_rx_buf SPSC ring (256-byte page-aligned)
 *
 *   2. IM2 ISR layer (former isr.c body):
 *      - isr_crt   — VRTC, frame counter, deferred 8275 cursor write
 *      - isr_pio_kbd — PIO-A keyboard strobe -> kbd_ring
 *      - isr_pio_par — PIO-B byte strobe -> pio_rx_buf
 *      - isr_noop  — daisy-chain placeholder
 *      - set_i_reg / enable_im2 / enable_interrupts / disable_interrupts
 *
 * Register preservation: every ISR PUSHes only the register pairs it
 * actually clobbers, then POPs them on exit.  Crucially the ISRs do
 * NOT touch the Z80 shadow set (BC'/DE'/HL'/AF') — userspace programs
 * (PolyPascal-compiled binaries, BDS C, WordStar) stash persistent
 * runtime state there and any EX AF,AF' / EXX in an ISR would silently
 * corrupt that state on every interrupt.  None of the ISR bodies use
 * IX/IY.
 *
 * Cross-compiler note: inline asm uses globally-unique labels (e.g.
 * `_isr_crt_no_dirty`) instead of GAS-style numeric local labels —
 * z80asm rejects `1:`/`1f` syntax.  Labels start with `_` so they
 * don't collide with C identifiers and aren't mangled differently
 * by the two compilers.  See compiler/compat.h.
 */
#include <stdbool.h>
#include <stdint.h>
#include "hal.h"           /* FRAME_COUNTER_ADDR, port consts */
#include "compiler/compat.h"
#include "transport.h"

#define RESIDENT      SECTION_RESIDENT
#define RESIDENT_DATA SECTION_RESIDENT_DATA

/* Z80-PIO control-word constants (Zilog datasheet table 4 + ICW form). */
#define PIO_MODE_OUTPUT       0x0F
#define PIO_MODE_INPUT        0x4F
#define PIO_IE_DISABLE        0x03   /* set IE FF: bit7=0 -> IE off */
#define PIO_IE_ENABLE         0x83   /* set IE FF: bit7=1 -> IE on  */
#define PIO_IE_ENABLE_RESET   0x97   /* ICW: enable + mask follows */
#define PIO_INT_MASK_NONE     0x00

#define PIO_DIR_INPUT   0
#define PIO_DIR_OUTPUT  1
static uint8_t pio_b_dir;            /* zeroed BSS = INPUT initially */

/* SCB header offsets (matches netboot_mpm.c). */
#define FMT 0
#define DID 1
#define SID 2
#define FNC 3
#define SIZ 4

/* PING/PONG SCB shape — used by pio_probe. */
#define PING_FNC  0xC0
#define PING_BYTE 'P'
#define PONG_BYTE 'O'

#ifndef RC702_SLAVEID
#define RC702_SLAVEID 0x01
#endif

/* SPSC ring buffer between isr_pio_par (push) and
 * transport_pio_recv_byte (pop).  Size 64 = 0x40, mask 0x3F.  Indices
 * are kept masked at write time so the load sites are a single byte
 * fetch with no extra arithmetic.  Empty: head == tail.  Full slots
 * lost silently; under flow-controlled CP/NET this can't happen, so
 * the ISR doesn't bother to detect it.  Replaces the old 0xFF=empty
 * sentinel which conflated a real 0xFF data byte from mpm-net2 with
 * "no byte yet" (#56). */
#define PIO_RX_BUF_SIZE 256
#define PIO_RX_BUF_MASK 0xFF
/* IRQ ring buffer for byte-level PIO transport. */
volatile uint8_t pio_rx_head;   /* ISR writes only */
volatile uint8_t pio_rx_tail;   /* mainline writes only */
/* Page-aligned 256-byte ring.  ISR builds `&buf[head]` as `ld h,
 * _pio_rx_buf_page; ld l, head` — only correct if the buffer is
 * page-aligned (low byte 0).  Both compilers derive _pio_rx_buf_page
 * from HIGH(_pio_rx_buf) so the constant cannot drift from the
 * placement: clang via payload.ld (.pio_rx_bss NOLOAD region at 0xF700);
 * SDCC via sections.asm (bss_pio_rx section, align 256, defs 256).
 * The SDCC build defines the symbol in sections.asm, so transport_pio.c
 * just declares it extern.  Clang allocates here through the section
 * attribute. */
#if defined(__clang__) && defined(__z80__)
SECTION_PIO_RX_BSS volatile uint8_t pio_rx_buf[PIO_RX_BUF_SIZE];
#else
extern volatile uint8_t pio_rx_buf[PIO_RX_BUF_SIZE];
#endif

RESIDENT
static void pio_b_set_output(void) {
    if (pio_b_dir == PIO_DIR_OUTPUT) return;
    _port_out(PORT_PIO_B_CTRL, PIO_IE_DISABLE);
    _port_out(PORT_PIO_B_CTRL, PIO_MODE_OUTPUT);
    pio_b_dir = PIO_DIR_OUTPUT;
}

RESIDENT
static void pio_b_set_input(void) {
    if (pio_b_dir == PIO_DIR_INPUT) return;
    /* Mode 1 select latches direction; ICW 0x97 + mask 0x00
     * atomically clears m_ip (Mode 0 strobes will have set it).
     * Final 0x83 re-asserts IE on, so isr_pio_par fires once per
     * real chip strobe and pushes the latched byte into pio_rx_buf
     * for snios's transport_pio_recv_byte to pop. */
    _port_out(PORT_PIO_B_CTRL, PIO_MODE_INPUT);
    _port_out(PORT_PIO_B_CTRL, PIO_IE_ENABLE_RESET);
    _port_out(PORT_PIO_B_CTRL, PIO_INT_MASK_NONE);
    _port_out(PORT_PIO_B_CTRL, PIO_IE_ENABLE);
    pio_b_dir = PIO_DIR_INPUT;
}


/* ---- Byte-level PIO transport ---------------------------------
 * snios.s (PIO-only experiment) calls these for every envelope byte.
 *
 * Stale-prefix mitigation on Mode 1->Mode 0 transitions: MAME's
 * z80pio.cpp::set_mode(MODE_OUTPUT) immediately fires
 * out_pb_callback with the chip's current m_output latch.  After a
 * direction flip there's a stale value from the previous send sitting
 * in m_output; if we just `_port_out(CTRL, MODE_OUTPUT)` and then
 * `_port_out(DATA, c)`, the peer sees stale_byte + c.  When the peer
 * is mpm-net2's SERVER.RSP, that stale byte breaks the protocol
 * (received between ACK and SOH, mpm-net2 doesn't tolerate it).
 * Workaround: write the data byte to the data port BEFORE the mode
 * switch.  That updates m_output while still in input mode (the
 * chip latches it without emitting), then the mode switch fires the
 * callback with the byte we actually want to send.  No stale prefix.
 * (See ravn/mame#7 for the underlying chip-emulation behaviour.) */
/* ravn/llvm-z80#131/#133: the function preserves D, E, H, L, B, C
 * from its callers' perspective.  The clang attribute on the *definition*
 * makes Z80FrameLowering emit prologue push / epilogue pop for any of
 * these registers the body actually modifies (clang chose D as scratch
 * to stash the incoming `c` argument, so D in particular needs the
 * save).  Together with the matching declaration in snios_c.c (read by
 * Z80CallLowering for caller-side RegMask narrowing), this lets SNIOS
 * state-machine callers keep values alive in those registers across
 * the call. */
RESIDENT
PRESERVES_REGS_CLANG("d", "e", "h", "l", "b", "c")
void transport_pio_send_byte(uint8_t c) {
    if (pio_b_dir == PIO_DIR_OUTPUT) {
        _port_out(PORT_PIO_B_DATA, c);
        return;
    }
    _port_out(PORT_PIO_B_CTRL, PIO_IE_DISABLE);
    _port_out(PORT_PIO_B_DATA, c);              /* preload m_output */
    _port_out(PORT_PIO_B_CTRL, PIO_MODE_OUTPUT); /* fires callback with c */
    pio_b_dir = PIO_DIR_OUTPUT;
}

RESIDENT
uint16_t transport_pio_recv_byte(uint16_t timeout_ticks) {
    pio_b_set_input();
    while (timeout_ticks--) {
        uint8_t t = pio_rx_tail;
        if (pio_rx_head != t) {
            uint8_t b = pio_rx_buf[t];
            pio_rx_tail = (uint8_t)(t + 1);   /* wraps at 256 */
            return b;
        }
    }
    return TRANSPORT_TIMEOUT;
}

/* Speed-test BSS variables (legacy harness).  Kept allocated for the
 * speed-test build only — no current callers in the merged TU. */
uint16_t pio_rx_count;
uint8_t  pio_test_done;


/* =============================================================
 *  IM2 ISR layer  (formerly isr.c, merged Phase 60)
 *
 *  IVT lives at 0xEA00 (set up by init.c).  Each entry is a 16-bit
 *  pointer to one of the ISR symbols below.  All ISRs live in
 *  `.resident.isr` so they survive the OUT (0x18) PROM disable.
 *
 *  Phase 3 step 2 (2026-04-26): replaced isr.s.  Co-location with
 *  transport_pio.c's pio_rx_buf and resident.c's BSS (kbd_ring,
 *  curx/cury, cur_dirty) is the win — the ISRs and the BSS they
 *  touch live in the same compilation-unit family.
 *
 *  2026-04-29: switched from EX AF,AF' + EXX bracket to explicit
 *  PUSH/POP per ISR.  EXX swaps the shadow bank into main; userspace
 *  code that holds live state in the shadow bank (every PolyPascal
 *  v3 compiled binary — 216 EXX + 208 EX AF,AF' instructions in
 *  PPAS.COM itself) loses that state on every VRTC IRQ.  The new
 *  sequence is +6 bytes overall but keeps the shadow regs free for
 *  userspace.
 * ============================================================= */

/* BSS symbols referenced by inline asm but defined in resident.c.
 * SDCC's asm emitter only generates EXTERN directives for C-level
 * extern declarations — references in inline-asm strings are
 * invisible to it.  Declare them here at file scope so SDCC emits
 * the right EXTERNs.  pio_rx_head / pio_rx_tail are file-locals
 * defined above (transport_pio_send_byte's ring), so no extern. */
#define KBD_RING_SIZE 16
extern uint8_t kbd_ring[KBD_RING_SIZE];
extern volatile uint8_t kbd_head;
extern volatile uint8_t kbd_tail;
extern volatile uint8_t cur_dirty;   /* defined in resident.c */
extern uint8_t curx;
extern uint8_t cury;
/* Linker-defined constant — value is the high byte of pio_rx_buf
 * address, used in inline asm via `ld h, _pio_rx_buf_page`.  Declared
 * here so SDCC emits an asm-level EXTERN directive; the value comes
 * from sdcc/sections.asm (defc) at link time. */
extern uint8_t pio_rx_buf_page;

/* Init-time helpers — one-instruction wrappers around the Z80
 * intrinsics.  Plain C — both compilers reduce these to `LD I, A; RET`
 * / `IM 2; RET` / `EI; RET` / `DI; RET` after inlining the
 * static-inline intrinsic.  No naked needed because the
 * compiler-generated prologue/epilogue is already just RET; saving
 * registers across a one-instruction body is fine. */

SECTION_RESIDENT_ISR
void set_i_reg(uint8_t page) { intrinsic_ld_i_a(page); }

SECTION_RESIDENT_ISR
void enable_im2(void)        { intrinsic_im_2(); }

SECTION_RESIDENT_ISR
void enable_interrupts(void) { intrinsic_ei(); }

SECTION_RESIDENT_ISR
void disable_interrupts(void) { intrinsic_di(); }

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
 * PUSH/POP). */
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
 * into the snios receive ring (pio_rx_buf, head/tail above).
 *
 * Registers used: A, F, HL.  Save set: AF + HL (4 bytes of PUSH/POP).
 * The byte is stashed on the stack between the head/tail check and the
 * ring write; new_head is carried in A; pio_rx_buf is page-aligned so
 * `ld h, _pio_rx_buf_page; ld l, head` builds &ring[head] without BC.
 * Userspace BC/DE/shadow registers all stay intact across the IRQ. */
SECTION_RESIDENT_ISR
void isr_pio_par(void) __naked {
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
}
