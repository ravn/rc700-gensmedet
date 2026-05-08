/* cpnos-rom cold-boot driver.
 *
 * Runs entirely from RAM at 0xED00+ after the PROM0 relocator has
 * reconstructed the payload in place.  No more LMA-vs-VMA dance —
 * what the compiler sees is what executes.
 *
 * Entry: _cpnos_cold_entry.  Tail call from relocator.s's `jp`.
 *   1. init_hardware — CTC, SIO-A/B, PIO, DMA, 8275, IM2 IVT.
 *   2. cfgtbl_init  — populate non-zero CFGTBL fields (everything else
 *      stays zero from BSS power-on).
 *   3. netboot       — fetch CCP+NDOS image from the master.
 *   4. PROM disable (OUT 0x18) — safe, we're executing from 0xED00.
 *   5. CP/M zero-page setup (JP WBOOT at 0x0000, JP BDOS at 0x0005).
 *   6. SNIOS — drain SIO RX, seed NETST=ACTIVE.
 *   7. Enable interrupts (CRT refresh ISR wakes the display).
 *   8. Jump to CP/NOS entry at CPNOS_NDOS_ADDR (Phase A: 0xE080;
 *      pre-Phase-A: 0xD000).  cpnios-shim.asm pins NIOS directly at
 *      cpnos-rom's resident _snios_jt symbol (0xED33), so step 7's
 *      runtime memcpy that used to copy snios_jt to a fixed 0xEA00
 *      slot is no longer needed.
 */

#include <stdint.h>
#include "hal.h"
#include "compiler/compat.h"
#include "transport.h"
#include "cpnos_addrs.h"     /* CPNOS_BDOS_ADDR — extracted from cpnos.sym */
#include "cpnos_buildinfo.h" /* BUILD_INFO_STR — regenerated every build;
                              * found via -I$(BUILDDIR) on the compile line */

extern void init_hardware(void);
extern void cfgtbl_init(void);
#if MIRROR_SIOB && defined(__SDCC)
extern void boot_probe(uint8_t tag);
#endif
#include "cfgtbl.h"

/* BIOS jump table base = BIOS_BASE.  `_bios_boot` is the first entry
 * label exported from bios_jt.s and pinned at the start of .payload
 * by payload.ld.  Reference it as a C array so the source-of-truth
 * for BIOS_BASE stays in payload.ld -- moving BIOS_BASE only requires
 * updating the ORIGIN + the matching ASSERT, never literal addresses
 * in C.  Z80 ABI prepends `_`, so the C-visible name is `bios_boot`
 * and the linker symbol is `_bios_boot`. */
extern uint8_t bios_boot[];
extern uint8_t snios_ntwkin(void);
extern void enable_interrupts(void);
extern NORETURN void jump_to(uint16_t addr);
extern NORETURN void enter_coldst(void);

#if defined(PIO_SPEED_TEST) || defined(PIO_LOOPBACK_TEST)
extern void     transport_pio_send_byte(uint8_t c);
extern uint16_t transport_pio_recv_byte(uint16_t timeout_ticks);
extern uint8_t  pio_test_done;            /* defined in transport_pio.c */
#endif

#ifdef PIO_SPEED_TEST
/* Speed test (Option P — bench).  100 * 4 * 256 = 102400 bytes ≈
 * 100 KiB.  Variant selected by PIO_SPEED_TEST value (1/2/3).
 *
 * Three nested uint8_t loops in variants 1+3 sidestep a clang Z80
 * backend bug where uint16_t loop counters get read from an
 * uninitialised static-stack slot rather than the live register
 * (see disasm of the earlier uint16_t-inner version: `ld hl,
 * ($eaXX)` instead of `ld h,b; ld l,c`).  Three 8-bit loops make
 * every counter fit in a single 8-bit register, avoiding the
 * affected codegen path. */
#define PIO_SPEED_OUTER 100
#define PIO_SPEED_MID   4
#define PIO_SPEED_BYTES ((unsigned long)PIO_SPEED_OUTER * \
                         PIO_SPEED_MID * 256UL)

#if PIO_SPEED_TEST == 1
/* Variant 1: TX, C function-call per byte.  Pattern `outer ^
 * inner_low`; verifies the function-call codepath of
 * transport_pio_send_byte. */
static void pio_loopback_test(void) {
    for (uint8_t outer = 0; outer < PIO_SPEED_OUTER; ++outer) {
        for (uint8_t mid = 0; mid < PIO_SPEED_MID; ++mid) {
            uint8_t inner = 0;
            do {
                transport_pio_send_byte((uint8_t)(outer ^ inner));
                ++inner;
            } while (inner != 0);
        }
    }
    pio_test_done = 1;
}
#endif

#if PIO_SPEED_TEST == 2
/* Variant 2: TX, inline OTIR.  Z80's tightest output instruction
 * (`OUT (C),(HL); INC HL; DEC B; JR NZ`, 21 T/byte).  First byte
 * goes through the C path to establish Mode 0; remaining 102399
 * bytes are blasted via inline asm.  Pattern is a 32-byte ramp
 * 0..31 in .rodata (32-byte buffer keeps .data small enough to fit
 * the payload budget, and OTIR-with-B=32 works the same way).
 * Pattern repeats every 32 bytes: byte at offset i = i & 0x1F.
 *
 * 25 outer * 128 mid * 32 inner OTIR = 102400 bytes total. */
const uint8_t pio_speed_buf[32] = {
    0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15,
   16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31
};

static void pio_loopback_test(void) {
    /* Inline Mode 0 setup + OTIR.  Avoids transport_pio_send_byte's
     * function-call overhead and the extra byte 0 it would emit
     * before OTIR.  3200 OTIR chunks * 32 bytes = 102400 bytes total.
     *
     * 0x03 = ICW: disable IE (Mode 0 STB pulses set m_ip; we re-clear
     *        on Mode 1 entry but here we just want to silence them).
     * 0x0F = mode 0 select (output).
     * The chip's set_mode(MODE_OUTPUT) immediately fires out_pb_cb
     * with m_output (0 after reset) — that leading 0x00 is the
     * documented chip-emulation prefix, stripped on the host side.
     *
     * Per-byte cost:
     *   OTIR  21 T  (per byte)
     *   chunk reload (HL=buf, B=32, dec/jr) ~25 T total per 32-byte chunk
     *   = 21.78 T/byte avg; theoretical 4 MHz / 21.78 = 184 KiB/s. */
    __asm__ volatile(
        /* PIO-B Mode 0 setup */
        "ld   a, 0x03\n\t"            /* ICW: IE disable */
        "out  (0x13), a\n\t"
        "ld   a, 0x0F\n\t"            /* mode 0 select */
        "out  (0x13), a\n\t"
        /* OTIR loop */
        "ld   c, 0x11\n\t"            /* data port */
        "ld   d, 25\n\t"              /* outer chunks */
        "1:\n\t"
        "ld   e, 128\n\t"             /* mid chunks */
        "2:\n\t"
        "ld   hl, _pio_speed_buf\n\t"
        "ld   b, 32\n\t"              /* bytes per OTIR */
        "otir\n\t"
        "dec  e\n\t"
        "jr   nz, 2b\n\t"
        "dec  d\n\t"
        "jr   nz, 1b\n\t"
        : : : "a", "b", "c", "d", "e", "hl", "memory"
    );
    pio_test_done = 1;
}
#endif

#if PIO_SPEED_TEST == 3
/* Variant 3: RX.  ISR-driven; the test simply enables PIO-B input
 * mode and busy-waits for pio_test_done to flip.  isr_pio_par
 * increments uint16_t pio_rx_count per byte and sets pio_test_done
 * on wrap (65536 bytes received).  This bypasses the ring-buffer
 * starvation problem: at high RX rates the chip's BRDY toggle in
 * data_read drives back-to-back strobes, leaving the mainline
 * (recv_byte loop) too few cycles to drain the 32-byte ring.  Just
 * counting in ISR — and signalling done from ISR — measures pure
 * chip+ISR throughput without that bottleneck.
 *
 * Test target: 65536 bytes (= 64 KiB).  Host sends exactly this and
 * waits for pio_test_done. */
static void pio_loopback_test(void) {
    /* Force PIO-B into Mode 1 + IE enabled + IP cleared.  We can't
     * use transport_pio_recv_byte (its first call sets up Mode 1),
     * so do it inline.  Same sequence as transport_pio.c's
     * pio_b_set_input(): mode 1, ICW with mask-follows + IE enable,
     * mask = 0 to atomically clear m_ip. */
    __asm__ volatile(
        "ld   a, 0x4F\n\t"        /* mode 1 input */
        "out  (0x13), a\n\t"
        "ld   a, 0x97\n\t"        /* ICW: enable + mask follows */
        "out  (0x13), a\n\t"
        "ld   a, 0x00\n\t"        /* mask: no PB bits masked */
        "out  (0x13), a\n\t"
        : : : "a"
    );
    /* Busy-wait for ISR to flip pio_test_done after 65536 bytes. */
    while (pio_test_done == 0) { }
}
#endif

#if PIO_SPEED_TEST == 4
/* Variant 4: RX via tight INIR busy-poll, NO interrupts.
 *
 * Host sends [0xAA sentinel byte] + [65536 data bytes].  Z80 polls
 * the data port until it sees 0xAA (consumes the sentinel), then runs
 * INIR for 65536 bytes.  The sentinel gives a clean "start" boundary
 * so we don't time the host-side TCP setup/buffer-fill phase.
 *
 * Z80-PIO Mode 1 input chip behaviour (from MAME z80pio.cpp::data_read):
 *
 *   case MODE_INPUT:
 *     if (!m_stb)
 *       m_input = m_device->m_in_pb_cb(0);   // re-fetch from peripheral
 *     data = m_input;
 *     set_rdy(false);
 *     set_rdy(true);
 *     break;
 *
 * Each CPU IN to the data port:
 *   1. (m_stb is 1 from previous strobe) returns m_input -> latched byte N
 *   2. set_rdy(false); set_rdy(true) toggles BRDY
 *   3. bridge's rdy_w(1) sees rising edge with data, calls strobe_w(0); strobe_w(1)
 *   4. chip strobe(0): m_input = bridge.read() -> pops byte N+1 from FIFO
 *   5. chip strobe(1): trigger_interrupt() (m_ip=true) + set_rdy(false)
 *
 * IE is disabled (0x03) so trigger_interrupt does NOT fire an IRQ —
 * m_ip is set but the chip never asserts INT.  Each subsequent IN
 * returns the freshly latched byte.  Net effect: one byte per IN,
 * no ISR overhead.  Z80 cost is just INIR's 21 T-states/byte =
 * 4 MHz / 21 = 190 KiB/s theoretical.
 *
 * Discard buffer at 0xC000 (TPA region — unused while test runs;
 * NDOS/CCP get re-loaded on warm-boot anyway).  256 chunks of 256
 * bytes each via INIR with B=0 (= 256 iter) gives 65536 bytes
 * total. */
static void pio_loopback_test(void) {
    __asm__ volatile(
        /* PIO-B Mode 1 input, IE disabled, IP cleared.
         * 0x97 + 0x00 (ICW with mask-follows + enable=1) clears m_ip
         * atomically.  Then 0x03 disables IE again — m_ip cleared,
         * m_ie=false, perfect state for busy-poll. */
        "ld   a, 0x4F\n\t"            /* mode 1 input */
        "out  (0x13), a\n\t"
        "ld   a, 0x97\n\t"            /* ICW: mask follows + enable */
        "out  (0x13), a\n\t"
        "ld   a, 0x00\n\t"            /* mask: no PB bits masked */
        "out  (0x13), a\n\t"
        "ld   a, 0x03\n\t"            /* set IE flip-flop = 0 */
        "out  (0x13), a\n\t"

        /* Wait for the host's 0xAA sentinel.  Empty-FIFO reads return
         * 0xFF; busy-spin until something other than 0xFF appears
         * (the sentinel itself).  This consumes the sentinel byte. */
        "2:\n\t"
        "in   a, (0x11)\n\t"
        "cp   0xFF\n\t"
        "jr   z, 2b\n\t"

        /* INIR loop: 256 chunks of 256 bytes -> 65536 data bytes. */
        "ld   c, 0x11\n\t"            /* PIO-B data port */
        "ld   d, 0\n\t"               /* outer chunk counter (0 = 256) */
        "1:\n\t"
        "ld   hl, 0xC000\n\t"         /* discard buffer (TPA, unused) */
        "ld   b, 0\n\t"               /* INIR iterations: 0 = 256 */
        "inir\n\t"                    /* 21 T/byte */
        "dec  d\n\t"
        "jr   nz, 1b\n\t"
        : : : "a", "b", "c", "d", "hl", "memory"
    );
    pio_test_done = 1;
}
#endif

#elif defined(PIO_LOOPBACK_TEST)
/* Bring-up frame test (Option P (3) — design-exploration step).  Sends
 * a 10-byte CP/NET-shaped request frame via PIO-B Mode 0, expects the
 * host to mirror it as a response (FMT toggled to 0x81, DID/SID
 * swapped, payload echoed, checksum recomputed), then validates frame
 * structure on the way back in via Mode 1 input.  Proves the full
 * frame mechanics work over the parallel link before committing to a
 * SNIOS-mirror vs. byte-blast upper-layer shape.
 *
 * Frame layout (CP/NET 1.2 SCB shape, no ENQ/ACK envelope — PIO has
 * hardware handshake that subsumes serial framing reliability):
 *   [0] FMT   0x80 request, 0x81 response
 *   [1] DID   destination ID
 *   [2] SID   source ID
 *   [3] FNC   function code
 *   [4] SIZ   payload length
 *   [5..]     payload (SIZ bytes)
 *   [last]    CKS   sum-to-zero checksum (two's complement of header+payload)
 */

#define PIO_FRAME_LEN 10
static const uint8_t pio_test_request_frame[PIO_FRAME_LEN] = {
    0x80,                        /* FMT: request */
    0x00,                        /* DID: master */
    0x01,                        /* SID: us (matches RC702_SLAVEID) */
    0x05,                        /* FNC: arbitrary, mirrored back */
    0x04,                        /* SIZ: 4-byte payload */
    0xDE, 0xAD, 0xBE, 0xEF,      /* payload */
    0xC4,                        /* CKS: 0x100 - (sum of bytes 0..8) & 0xFF */
};
uint8_t pio_test_recv[PIO_FRAME_LEN];   /* host response lands here (BSS) */
uint8_t pio_test_passed;                /* 1 = frame valid, 0 = invalid (BSS) */

static void pio_loopback_test(void) {
    /* TX: blast the request frame at the host.  No ENQ/ACK envelope
     * because PIO Mode 0/1 hardware handshake guarantees byte
     * delivery; the per-byte STB+BRDY round-trip is the wire-level
     * reliability mechanism. */
    for (uint8_t i = 0; i < PIO_FRAME_LEN; ++i) {
        transport_pio_send_byte(pio_test_request_frame[i]);
    }
    /* RX: drain the response frame.  Each recv polls for ~150 ms
     * emulated (uint16_t max ticks); harness echoes immediately so
     * the first byte arrives well within the first call's budget. */
    for (uint8_t i = 0; i < PIO_FRAME_LEN; ++i) {
        uint16_t r = transport_pio_recv_byte(0xFFFFU);
        pio_test_recv[i] = (uint8_t)r;
    }
    /* Validate response shape and checksum.  ok == 1 only if every
     * field matches the expected mirror semantics. */
    uint8_t sum = 0;
    for (uint8_t i = 0; i < PIO_FRAME_LEN; ++i) sum += pio_test_recv[i];
    uint8_t ok = (pio_test_recv[0] == 0x81)               /* FMT response */
              && (pio_test_recv[1] == 0x01)               /* DID was SID */
              && (pio_test_recv[2] == 0x00)               /* SID was DID */
              && (pio_test_recv[3] == 0x05)               /* FNC echoed */
              && (pio_test_recv[4] == 0x04)               /* SIZ echoed */
              && (pio_test_recv[5] == 0xDE)
              && (pio_test_recv[6] == 0xAD)
              && (pio_test_recv[7] == 0xBE)
              && (pio_test_recv[8] == 0xEF)
              && (sum == 0);                              /* CKS sum-to-zero */
    pio_test_passed = ok;
    pio_test_done = 1;
}
#endif

/* Netboot: two implementations, one selected by SERVER=mpm|proxy in
 * the Makefile.  Default is mpm — standard CP/NET 1.2 LOGIN / OPEN /
 * READ / CLOSE against z80pack MP/M II. */
#ifdef NETBOOT_LEGACY
extern uint16_t netboot(void);
#define NETBOOT() netboot()
#else
extern uint16_t netboot_mpm(void);
#define NETBOOT() netboot_mpm()
#endif

/* Boot orchestration after netboot: signon + BIOS-JT copy + ZP[0..7].
 * Replaces cpbios.asm's `boot:` routine.  Keeps everything in C so the
 * JT base / signon string / IOBYTE convention live alongside the impls
 * they coordinate with.
 *
 * cpnos.com's tiny entry stub at NDOS finishes ZP setup with ZP[5..7]
 * (= JP BDOS+6, where BDOS's address is a cpnos.com link-time symbol)
 * and falls through to NDOS+3 = COLDST.  Phase A (2026-04-30) lifted
 * NDOS from 0xD000 to 0xE080 (TPA grew 51 -> 55 KB strict). */
extern void impl_conout(uint8_t c);

/* Banner is printed BEFORE NETBOOT() so the screen layout is:
 *   row 0 (cursor home): "RC702 CP/NOS WWW-MMM yyyy-mm-dd HH:MM hash"
 *   row 1: 25 netboot progress dots followed by CR/LF on EOF
 * Operator sees the OS identity immediately on power-on, then watches
 * the dots fill in below it.  Previously the banner was printed by
 * nos_handoff() AFTER netboot, so the dots appeared on row 0 and the
 * banner on row 1 — backwards from what operators expect. */
SECTION_INIT_TEXT
static void print_banner(void) {
    /* "RC702 CP/NOS NNK WWW-MMM cc yyyy-mm-dd HH:MM hash\r\n".
     * NNK is the TPA size in KB (CPNOS_TPA_KB, build-time from
     * cpnos.sym).  WWW-MMM is the TRANSPORT_NAME literal (define
     * via Makefile -DTRANSPORT_NAME='"PIO-IRQ"' / "SIO" / "PIO-PRX").
     * `cc` is CPNOS_COMPILER_NAME ("clang" / "sdcc" / "hitech") —
     * picked at preprocess time so the banner unambiguously identifies
     * which build produced the running image, regardless of how it was
     * deployed.  All three pieces stringify at compile time. */
#define _STR(x) #x
#define STR(x) _STR(x)
    static const SECTION_INIT_RODATA char banner[] =
        "RC702 CP/NOS " STR(CPNOS_TPA_KB) "K "
        TRANSPORT_NAME " " CPNOS_COMPILER_NAME " " BUILD_INFO_STR "\r\n";
    for (const char *p = banner; *p; ++p) impl_conout((uint8_t)*p);
#undef STR
#undef _STR
}

/* BIOS-JT copy lands at NDOSRL + 0x300 inside cpnos.com's data area.
 * NDOSRL = NDOS - 0x400, so the copy address is NDOS - 0x100.  NDOS
 * COLDST walks the table via ZP[0001..0002], replacing slots 1..5 + 15
 * with NDOS wrapper addresses.  Other slots (BOOT/PUNCH/READER/HOME/
 * SELDSK..WRITE/SECTRAN) keep their resident-JT targets -- unreachable
 * in CP/NOS so they land harmlessly on bios_stub_ret. */
#define BIOS_JT_COPY_ADDR (CPNOS_NDOS_ADDR - 0x100)

/* CP/M zero-page seed copied to 0x0000..0x0007 by resident_handoff
 * AFTER PROM disable.  MUST live in .resident.data (RAM-resident,
 * relocated by the relocator from PROM bytes to 0xED00+) so the LDIR
 * source address survives PROM disable.  Pinned via section attr +
 * `used` so the linker keeps it; payload.ld ASSERTs the symbol's
 * address is inside the resident range, turning a future move into
 * .init.rodata into a link-time error.  The `zp_init_data` name is
 * file-scope (no static + no dot in symbol) so linker-script
 * ASSERTs can reference it directly. */
SECTION_RESIDENT_DATA
const uint8_t zp_init_data[8] = {
    0xC3,
    (uint8_t)((BIOS_JT_COPY_ADDR + 3) & 0xFF),
    (uint8_t)(((BIOS_JT_COPY_ADDR + 3) >> 8) & 0xFF),
    0x00,                                  /* IOBYTE */
    0x04,                                  /* drive/user (E:) */
    0xC3,
    (uint8_t)(CPNOS_BDOS_ADDR & 0xFF),
    (uint8_t)((CPNOS_BDOS_ADDR >> 8) & 0xFF),
};

/* Resident handoff -- runs from RAM at 0xED00+ AFTER the init phase
 * (which lives in PROM-resident .init).  This is split out so it
 * survives PROM disable: cpnos_cold_entry above lives in .init and
 * gets unmapped the moment PROMs go off, so the OUT (0x18),A
 * instruction itself, plus everything after it, must execute from
 * RAM.  Tail-called by cpnos_cold_entry() with `entry` = 0 on
 * netboot failure, otherwise NDOS's cold-start vector. */
NORETURN
static void resident_handoff(uint16_t entry) {
    /* Disable the PROMs -- exposes RAM underneath for the TPA and
     * netboot-loaded image.  We're at 0xED00 (RAM); still running. */
    _port_out(PORT_RAMEN, 0x00);
    BOOT_MARK(16, 'P');                /* PROMs disabled */

    /* Restore cfgtbl.fnc to LIST (0x05) -- netboot's cpnet_xact left
     * it at the last function code (16 = CLOSE).  cfgtbl shares its
     * outbound message-frame area with netboot's msg[] (saves 163 B
     * BSS), but cfgtbl_init's fnc=5 invariant must hold for SNIOS's
     * post-netboot LIST behaviour.  fnc=5 is the cfgtbl_init value;
     * keep them in sync if cfgtbl_init is touched. */
    cfgtbl.fnc = 0x05;

    /* Prime SNIOS: drain SIO RX, seed NETST=ACTIVE, clear SIZ.  NDOS's
     * own NTWKIN may re-run this; idempotent. */
    snios_ntwkin();

    /* No snios_jt memcpy: cpnos-build/src/cpnios-shim.asm pins NIOS
     * directly at our resident _snios_jt symbol (0xED33) via the LINK
     * EQU.  NDOS calls land in resident BIOS without a runtime copy. */

#if defined(PIO_SPEED_TEST) || defined(PIO_LOOPBACK_TEST)
    /* PIO-B bring-up test runs after IRQs are on so the receive ring
     * fills via isr_pio_par.  Skipped if netboot failed -- without
     * netboot we can't trust resident state. */
    if (entry != 0) {
        pio_loopback_test();
    }
#endif

    if (entry != 0) {
        /* 1. Copy 17-entry resident BIOS JT (51 B at 0xED00) into NDOS's
         *    data area at NDOS - 0x100 = NDOSRL + 0x300.  NDOS COLDST
         *    walks this via ZP[1..2] and rewrites BDOS-related slots
         *    with its own intercept addresses.
         * 2. LDIR zp_init_data[8] (in .resident.data, pinned by
         *    payload.ld ASSERT) into the now-RAM zero page.
         * 3. enter_coldst (resident asm helper) loads SP=0x100 and
         *    JPs to NDOS+3 (COLDST). */
        __builtin_memcpy((void *)BIOS_JT_COPY_ADDR, bios_boot, 51);

        /* TODO (cpnos-rom dual-compile, Phase 2): clang Z80 register-
         * class constraints don't parse under SDCC.  Same gap as the
         * LDDR site in resident.c::insert_line.  Replacement plan: a
         * shared `mem_copy_forward(dst, src, count)` helper exported
         * from runtime.s (per-compiler asm body, same C signature).
         * See tasks/sdcc-port.md. */
#if defined(__clang__) && defined(__z80__)
        const void *src = zp_init_data;
        void       *dst = (void *)0;
        unsigned    n   = sizeof(zp_init_data);
        __asm__ volatile("ldir"
            : "+{de}"(dst), "+{hl}"(src), "+{bc}"(n)
            :
            : "memory");
#else
        /* SDCC: clang's "+{de}"/"+{hl}"/"+{bc}" register-class
         * constraints don't parse.  Inline LDIR with literal addresses
         * keeps the size cost identical to clang's version.  Without
         * this copy NDOS COLDST jumps via uninitialised ZP and the
         * slave hangs after BOOT_MARK 'P'. */
        ASM_VOLATILE(
            "ld   hl, _zp_init_data\n\t"
            "ld   de, 0\n\t"
            "ld   bc, 8\n\t"          /* sizeof(zp_init_data) */
            "ldir\n\t"
        );
#endif

        BOOT_MARK(18, 'J');             /* about to JP NDOS COLDST */
#if MIRROR_SIOB && defined(__SDCC)
        /* Probe pre-handoff buffer state (issue #57). */
        boot_probe('H');
#endif
        enter_coldst();
    }
    for (;;) { }
}

/* Init phase: runs in place from PROM 0 0x0100..0x0??? (.init).
 * Tail-called by the relocator after it copies resident bytes to
 * 0xED00.  Calls into resident-RAM helpers (impl_conout, snios_*,
 * runtime stubs) work because the relocator already populated
 * 0xED00+ before JPing here.  PROMs are still mapped through
 * netboot completion; resident_handoff (RAM) does the OUT. */
SECTION_INIT_TEXT
NORETURN void cpnos_cold_entry(void) {
    cfgtbl_init();
    init_hardware();

    /* SNIOS drives PIO byte primitives via the linker's
     * --defsym=_xport_send_byte=_transport_pio_send_byte alias
     * (transport_pio.c).  Mark 'P' so the boot strip indicates the
     * physical wire (PIO) regardless of SNIOS envelope above. */
    BOOT_MARK(7, 'P');

    /* IRQ-driven snios-on-PIO needs IFF on during netboot:
     * isr_pio_par fires per chip strobe and pushes bytes into
     * pio_rx_buf for transport_pio_recv_byte to pop. */
    enable_interrupts();

    /* Banner BEFORE netboot so it appears on row 0; netboot dots flow
     * on row 1 (operator's "OS identity at top, progress below"
     * expectation). */
    print_banner();

    uint16_t entry = NETBOOT();
    BOOT_MARK(15, entry ? '+' : '-');

    /* Tail call into resident RAM -- everything after this point
     * (PROM disable, snios_ntwkin, nos_handoff, enter_coldst) MUST
     * run from RAM because PROM disable un-maps the .init region. */
    resident_handoff(entry);
}
