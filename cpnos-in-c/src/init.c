/* cpnos-rom cold-boot init code (runs in place from PROM0, never copied to RAM).
 *
 * Single translation unit covering all four cold-boot phases.  Merged
 * 2026-05-10 (Phase 59) from cfgtbl.c + init.c + netboot_mpm.c +
 * cpnos_cold.c so the compiler sees the full call graph in one TU and
 * cfgtbl_init / init_hardware / netboot_mpm can become file-static.
 *
 * Source order mirrors call order from cpnos_cold_entry:
 *
 *   1. cfgtbl ABI + cfgtbl_init      — populate non-zero CFGTBL fields
 *                                       (slaveid, drive map, FMT/SID/FNC).
 *   2. init_hardware                  — IVT, CTC, SIO-A/B, PIO, DMA, 8275.
 *   3. netboot_mpm + helpers          — CP/NET 1.2 LOGIN/OPEN/READ/CLOSE
 *                                       fetch of A:CPNOS.IMG into TPA.
 *   4. print_banner + cpnos_cold_entry— operator banner + orchestration.
 *
 * Everything in this file lives in INIT_CODE/INIT_RODATA section
 * (PROM-only, freed by `OUT (0x18),A` RAMEN inside resident_handoff).
 * Only `cpnos_cold_entry` is externally visible — payload.ld names it
 * as ENTRY and reset.s tail-calls it.
 */

#include <stdint.h>
#include "hal.h"
#include "compiler/compat.h"
#include "transport.h"
#include "cfgtbl.h"
#include "cpnos_addrs.h"     /* CPNOS_TPA_KB, CPNOS_NDOS_ADDR */
#include "cpnos_buildinfo.h" /* BUILD_INFO_STR */

/* memcpy from runtime.s (clang) or libsdcc_iy (SDCC, declared in
 * <string.h> via compat.h). */
#ifdef __clang__
extern void *memcpy(void *dest, const void *src, unsigned int n);
#endif

/* Resident helper from resident.c.  File-scope declaration so SDCC
 * z88dk emits the matching EXTERN _get_img_base directive in the
 * generated .asm -- function-scope `extern` is silently dropped.
 * Caught session 73j-late during SDCC PROM1-only diagnosis. */
extern uint8_t *get_img_base(void);

/* ---- ISRs + helpers from isr.s. ----------------------------------- */
extern void isr_crt(void);
extern void isr_noop(void);
extern void isr_pio_kbd(void);
extern void isr_pio_par(void);
extern void set_i_reg(uint8_t page);
extern void enable_im2(void);
extern void enable_interrupts(void);

/* ---- Resident-side helpers (run from RAM after relocator copy). --- */
extern void clear_screen(void);
extern void impl_conout(uint8_t c);
extern uint8_t snios_ntwkin(void);
extern NORETURN void resident_handoff(uint16_t entry);

/* Resident BIOS base (linker-emitted, == 0xED00 today).  Used as the
 * upper bound for the netboot LDIR write region so the safety check
 * tracks any future BIOS_BASE move. */
extern uint8_t bios_boot[];

/* IVT at __ivt_start (page-aligned, supplied by payload.ld).  Each
 * slot is 2 bytes, so slot N lives at __ivt_start + 2N.
 *   slot 0..3  (vec 0x00..0x06): CTC channels 0..3 (ch2 = CRT refresh)
 *   slot 8..10 (vec 0x10..0x14): SIO-B rx/tx/extstatus (polled, slots
 *                                 installed as noop for the daisy chain)
 *   slot 16    (vec 0x20):       PIO-A keyboard
 *   slot 17    (vec 0x22):       PIO-B (unused)
 *
 * 2026-05-08: IVT moved from 0xF500 (above resident) to 0xEA00 (in the
 * cpnos.com→resident gap opened by Path 6's CODE_BASE shift) to mirror
 * the SDCC layout and free 36 B of scratch BSS.  Page placement is
 * owned by the linker (.ivt SECTION at 0xEA00 in payload.ld); the
 * ASSERTs in payload.ld catch overlap with cpnos.com / .payload /
 * .scratch_bss / stack.  IVT_ADDR derives the page byte for `I`
 * register loading, no literal address in C. */
extern uint8_t _ivt_start[];
#define IVT_ADDR     ((uint16_t)(uintptr_t)_ivt_start)
#define IVT_ENTRIES  18
#define IVT_PIO_A    16
#define IVT_PIO_B    17


/* =============================================================
 *  1. CFGTBL — DRI CP/NET configuration table
 * =============================================================
 *
 * DRI CFGTBL layout (per cpnet-z80/src/snios.asm:62+):
 *   +0   NETST      Network status byte (0 = offline, 1 = online, plus error bits)
 *   +1   SLAVEID    This node's slave ID (set from RC702_SLAVEID build flag)
 *   +2   A: disk    2 bytes per drive, 16 drives total (A: .. P:), bit 7 of
 *   ...             the low byte = remote-via-network, low nibble = remote drive letter
 *   +34  console    2 bytes, bit 7 = remote console
 *   +36  list       2 bytes, bit 7 = remote list device
 *   +38  bufidx     Buffer index
 *   +39  FMT        outbound message template: 0 (request)
 *   +40  DID        outbound DID: 0 (to master)
 *   +41  SID        outbound SID: 0xFF (SNIOS initialises to our SLAVEID)
 *   +42  FNC        outbound FNC: 5 (LIST)
 *   +43  SIZ        outbound SIZ: 0
 *   +44  MSG[0]     List number (for LST:)
 *   +45..+172  MSGBUF (128-byte message buffer)
 *
 * This is a public ABI — any imported SNIOS object references it by
 * name, and the wire offsets must match the DRI specification.
 */

#ifndef RC702_SLAVEID
#define RC702_SLAVEID 0x70
#endif

/* cfgtbl goes in .scratch_bss (zero-initialised at cold boot).  The
 * non-zero fields are set at runtime by cfgtbl_init() — avoids burning
 * 170+ B of explicit zero bytes in the PROM just to spell out MSGBUF
 * and the unused upper drive slots. */
#define RESIDENT_BSS SECTION_BSS_CFGTBL

static_assert(sizeof(struct cfgtbl) == 210,
              "CFGTBL must be 210 B (173 DRI ABI + 37 netboot tail)");
static_assert(__builtin_offsetof(struct cfgtbl, slaveid) == 1, "SLAVEID @ +1");
static_assert(__builtin_offsetof(struct cfgtbl, console) == 34, "console @ +34");
static_assert(__builtin_offsetof(struct cfgtbl, fmt) == 39, "FMT @ +39");
static_assert(__builtin_offsetof(struct cfgtbl, sid) == 41, "SID @ +41");
static_assert(__builtin_offsetof(struct cfgtbl, msgbuf) == 45, "MSGBUF @ +45");

RESIDENT_BSS
struct cfgtbl cfgtbl;

/* Template for the contiguous slaveid + drive[0..5] block (cfgtbl
 * offsets +1..+13).  Lifted out of cfgtbl_init's per-field stores so
 * the function lowers to a single LDIR -- saves ~30 B of init code
 * versus 7 individual `ld hl,$X; ld (nn),hl` pairs.  Drives A:-D: map
 * to server master (slave 0) drives A:-D: -- NDOS's LOAD for CCP.SPR
 * uses ccpfcb (cpndos.asm:ccpfcb) which hardcodes drive byte 1 (= A:),
 * so A: must be network and must carry CCP.SPR for cold-boot CCP load.
 * E:, F: -> master I:, J: (4 MB hard disks; master XIOS exposes
 * harddisk DPHs at drive numbers 8 and 9 -- see bnkxios-net-2.mac).
 * Disk images seeded by the cpmsim/mpm-net2 launcher from
 * disks/library/mpm-net2-drive[ij].dsk.
 *
 * Workaround for z88dk-zsdcc 4.5.0 constant-folding bug
 * (ravn/z88dk#4).  `(NET_DRV('A', 0x00) >> 8) & 0xFF` should evaluate
 * to 0x00 but SDCC emits 0xFF — sign-extends the 0x80 low byte to
 * 0xFF80 then arithmetic-shifts.  Result: every network drive's
 * server-slave field becomes 0xFF instead of 0x00, NDOS sees no
 * valid master, never sends SNDMSG/RCVMSG, slave warm-boots in a
 * tight cycle.  Clang (LLVM Z80) compiles the macro correctly.
 * Use explicit byte literals; semantics identical, no macro >>8. */
SECTION_INIT_RODATA
static const uint8_t cfgtbl_init_template[13] = {
    RC702_SLAVEID,         /* +1  slaveid */
    0x80, 0x00,            /* +2  drive[0]  A: -> master drive A */
    0x81, 0x00,            /* +4  drive[1]  B: -> master drive B */
    0x82, 0x00,            /* +6  drive[2]  C: -> master drive C */
    0x83, 0x00,            /* +8  drive[3]  D: -> master drive D */
    0x88, 0x00,            /* +10 drive[4]  E: -> master drive I */
    0x89, 0x00,            /* +12 drive[5]  F: -> master drive J */
};

/* Set the few non-zero fields.  Everything else stayed zero at BSS
 * clear.  Must run before any SNIOS call. */
SECTION_INIT_TEXT
static void cfgtbl_init(void) {
    __builtin_memcpy(&cfgtbl.slaveid, cfgtbl_init_template,
                     sizeof(cfgtbl_init_template));
    cfgtbl.sid = 0xFF;          /* SNIOS rewrites to SLAVEID at init */
    cfgtbl.fnc = 0x05;          /* LIST function */
}


/* =============================================================
 *  2. Hardware bring-up — IVT + port_init table
 * ============================================================= */

/* Unified port-init table.  Each pair (port, value) is written in
 * order with OUT (C),A.  Centralises ~30 scattered port writes into
 * one table + one loop — smaller than inline port_out calls. */
SECTION_INIT_RODATA
static const uint8_t port_init[] = {
    /* CTC ch0: vector=0, SIO-A baud timer. */
    PORT_CTC0, 0x00,   PORT_CTC0, 0x47,   PORT_CTC0, 0x01,
    /* CTC ch1: SIO-B baud timer. */
    PORT_CTC1, 0x47,   PORT_CTC1, 0x01,
    /* CTC ch2: CRT VRTC counter, IRQ armed. */
    PORT_CTC2, 0xD7,   PORT_CTC2, 0x01,

    /* SIO-A: WR0 reset, WR4 x16/1-stop/no-parity, WR3 Rx-enable,
     * WR5 Tx-enable/RTS, WR1 no-interrupts (polled). */
    PORT_SIO_A_CTRL, 0x18,
    PORT_SIO_A_CTRL, 0x04, PORT_SIO_A_CTRL, 0x44,
    PORT_SIO_A_CTRL, 0x03, PORT_SIO_A_CTRL, 0xE1,
    PORT_SIO_A_CTRL, 0x05, PORT_SIO_A_CTRL, 0x6A,
    PORT_SIO_A_CTRL, 0x01, PORT_SIO_A_CTRL, 0x00,

    /* SIO-B: same + WR2=0x10 (interrupt vector base). */
    PORT_SIO_B_CTRL, 0x18,
    PORT_SIO_B_CTRL, 0x02, PORT_SIO_B_CTRL, 0x10,
    PORT_SIO_B_CTRL, 0x04, PORT_SIO_B_CTRL, 0x44,
    PORT_SIO_B_CTRL, 0x03, PORT_SIO_B_CTRL, 0xE1,
    PORT_SIO_B_CTRL, 0x05, PORT_SIO_B_CTRL, 0x6A,
    PORT_SIO_B_CTRL, 0x01, PORT_SIO_B_CTRL, 0x00,

    /* PIO-A (keyboard): vector=0x20, mode 1 input + ICW, EI. */
    PORT_PIO_A_CTRL, 0x20,
    PORT_PIO_A_CTRL, 0x4F,
    PORT_PIO_A_CTRL, 0x83,

    /* PIO-B (CP/NET fast link, J3): vector=0x22, mode 1 input,
     * IE ON.  Each chip strobe (real byte from the bridge) fires
     * isr_pio_par via IM2 vector 0x22; the ISR reads PORT_PIO_B_DATA
     * (clearing chip m_ip) and pushes the byte into pio_rx_buf for
     * snios's transport_pio_recv_byte to pop.  No polling on
     * PORT_PIO_B_DATA, so there's no "0xFF data byte vs empty FIFO"
     * conflation — empty queue is signalled by head==tail, real bytes
     * (any value 0x00..0xFF) sit in the queue.  See
     * tasks/session34-direct-pio-stall-rootcause.md. */
    PORT_PIO_B_CTRL, 0x22,
    PORT_PIO_B_CTRL, 0x4F,
    PORT_PIO_B_CTRL, 0x83,

    /* 8237 DMA: master clear, ch2+ch3 single-mode mem->IO autoinit. */
    PORT_DMA_CMD,  0x20,
    PORT_DMA_MODE, 0x58 | 2,
    PORT_DMA_MODE, 0x58 | 3,
    /* Clear byte-pointer FF, ch2 base/wc for display. */
    PORT_DMA_CLBP,      0,
    PORT_DMA_CH2_ADDR,  DISPLAY_ADDR & 0xFF,
    PORT_DMA_CH2_ADDR,  DISPLAY_ADDR >> 8,
    PORT_DMA_CH2_WC,    (DISPLAY_SIZE - 1) & 0xFF,
    PORT_DMA_CH2_WC,    (DISPLAY_SIZE - 1) >> 8,
    PORT_DMA_CH3_WC,    0,
    PORT_DMA_CH3_WC,    0,
    /* Unmask ch2 and ch3. */
    PORT_DMA_SMSK,      0x02,
    PORT_DMA_SMSK,      0x03,

    /* 8275 CRT: reset + geometry + start. 80x25, 7 scan lines/row,
     * CM=01 blink underline — matches rcbios/MAME expectation. */
    PORT_CRT_CMD,   0x00,
    PORT_CRT_PARAM, 0x4F,
    PORT_CRT_PARAM, 0x98,
    PORT_CRT_PARAM, 0x7A,
    PORT_CRT_PARAM, 0x6D,
    PORT_CRT_CMD,   0x80,
    PORT_CRT_PARAM, 0,
    PORT_CRT_PARAM, 0,
    PORT_CRT_CMD,   0xE0,
    PORT_CRT_CMD,   0x23,
};

SECTION_INIT_TEXT
static void setup_ivt(void) {
    /* 18 x 16-bit slots at IVT_ADDR (page-aligned).  All slots default
     * to isr_noop; CTC ch2 (slot 2) gets the CRT refresh ISR.
     *
     * NON-volatile pointer is intentional: this runs once before EI /
     * IM 2, with no other CPU activity, so the compiler is free to
     * reorder/optimize the per-slot stores.  In particular, clang
     * recognizes the constant-pattern-fill loop and lowers it to the
     * Z80 LDIR-overlap idiom (~17 B vs 22 B for a volatile loop;
     * see ravn/llvm-z80#130 comment thread).  Adding `volatile` here
     * blocks LoopIdiomRecognize (volatile stores fail isLegalStore). */
    uint16_t *ivt = (uint16_t *)IVT_ADDR;
    for (uint8_t n = IVT_ENTRIES; n; --n) {
        *ivt++ = (uint16_t)(uintptr_t)&isr_noop;
    }
    ivt = (uint16_t *)IVT_ADDR;
    ivt[2] = (uint16_t)(uintptr_t)&isr_crt;
    ivt[IVT_PIO_A] = (uint16_t)(uintptr_t)&isr_pio_kbd;
    ivt[IVT_PIO_B] = (uint16_t)(uintptr_t)&isr_pio_par;
    set_i_reg(IVT_ADDR >> 8);
    enable_im2();
}

SECTION_INIT_TEXT
static void init_hardware(void) {
    /* IVT + IM2 first so any stray interrupt lands on isr_noop rather
     * than the reset vector.  Interrupts stay disabled; resident_entry
     * does EI after PROM disable. */
    setup_ivt();

    /* Apply the unified port-init table — CTC, SIO-A/B, PIO-A, DMA,
     * 8275.  All interrupts are still globally DI.  Pointer-walk
     * with countdown so clang generates a DJNZ-style 8-bit loop
     * rather than a 16-bit pointer compare. */
    const uint8_t *p = port_init;
    for (uint8_t n = sizeof(port_init) / 2; n; --n) {
        uint8_t port = *p++;
        uint8_t value = *p++;
        _port_out(port, value);
    }

    /* Drain any stray RX on the SIOs (RRs can latch error bits from
     * reset that block subsequent transmits until cleared by read). */
    (void)IO_READ(SIO_A_CTRL);
    (void)IO_READ(SIO_B_CTRL);

    /* Clear display with spaces so subsequent CONOUT output is
     * readable against a blank background.  Call into resident.c's
     * clear_screen instead of inlining a 4th copy of the LDIR set. */
    clear_screen();

    /* Visible bring-up marker: 'I' at BOOT_MARK index 0 (display row 0,
     * col 60).  Single char instead of "INIT OK" -- the 7-byte rodata
     * + 7-iteration write loop was ~18 B for marginal value;
     * cpnos_cold_entry already paints the boot-strip after this. */
    BOOT_MARK(0, 'I');
}


/* =============================================================
 *  3. CP/NET 1.2 netboot of A:CPNOS.IMG into TPA
 * =============================================================
 *
 * Wire sequence (per CPNET_WIRE_PROTOCOL.md):
 *   LOGIN  (fn 64)  DAT = 8-byte password
 *   OPEN   (fn 15)  DAT[0]=user, DAT[1..36]=FCB for A:CPNOS.IMG
 *   loop:
 *     READ_SEQ (fn 20)  DAT[0]=user, DAT[1..36]=FCB (updated from prev resp)
 *     response DAT[0]=retcode (0 ok, 1 EOF, 0xFF err)
 *             DAT[1..36]=updated FCB
 *             DAT[37..164]=128-byte sector
 *     copy 128 bytes to growing DMA pointer
 *   CLOSE  (fn 16)
 */

/* DRI CP/NET frame header offsets. */
#define FMT 0
#define DID 1
#define SID 2
#define FNC 3
#define SIZ 4
#define DAT 5

/* msg[] aliases the cfgtbl outbound message-frame area starting at
 * cfgtbl.fmt (offset +39 inside cfgtbl).  msg[0..4] = fmt/did/sid/
 * fnc/siz, msg[5] = msg0/DAT[0], msg[6..170] = msgbuf[0..127] +
 * netboot_tail[0..36].  Sharing this buffer with SNIOS saves ~163 B
 * BSS over a separate msg[200] static.  Biggest response is
 * READ-SEQ: 5 hdr + 166 data = 171 B; cfgtbl.fmt+0..170 fits. */
#define msg ((uint8_t *)&cfgtbl.fmt)

/* cpnos.com produced by RMAC+LINK is CODE-only (DATA section at
 * NDOSRL is runtime-initialized BSS, not stored in the file).
 * Option β (2026-04-30) placement:
 *   CODE_BASE = 0xE080 (NDOS), DATA_BASE = 0xDC80 (NDOSRL)
 * The .COM file is the CODE section -- linked at CODE_BASE and
 * record-padded to 0xC80 on disk; file offset 0 = memory
 * CPNOS_NDOS_ADDR.  Source of truth is cpnos.sym (extracted into
 * clang/cpnos_addrs.h as CPNOS_NDOS_ADDR).
 *
 * IMG_BASE is decided at runtime via prom1_only_sentinel: PROM1-only
 * builds expect cpnos.img to start with a 384 B locale prefix
 * (outcon[128]+inconv[256]) prepended by cpnos-disk-install-with-locale;
 * the slave loads at CPNOS_NDOS_ADDR - 384 so the prefix lands in TPA
 * scratch just below NDOS and the rest of cpnos.com lands at NDOS_ADDR
 * as usual.  resident_handoff's install_locale_tables() then LDIRs
 * the prefix to its runtime home at 0xF680.  Two-PROM cold-init never
 * sets the sentinel, so IMG_BASE stays at CPNOS_NDOS_ADDR and the
 * netboot reads a normal (un-prefixed) cpnos.img. */
#define LOCALE_PREFIX_SIZE 384
#define ENTRY_ADDR (CPNOS_NDOS_ADDR)

/* MP/M II default password on mpm-net2-1.dsk.  Override at build time
 * with -DRC702_LOGIN_PWD='"OTHER   "' (8 chars, space padded).  The
 * literal landed in .payload (resident rodata) when used as a plain
 * string literal -- pinned into .init.rodata so the byte sequence
 * sits in PROM-only init memory. */
#ifndef RC702_LOGIN_PWD
#define RC702_LOGIN_PWD "PASSWORD"
#endif
SECTION_INIT_RODATA
static const uint8_t login_pwd[8] = RC702_LOGIN_PWD;

/* FCB header for A:CPNOS.IMG, prepended with the user-number byte
 * so install_fcb can do one LDIR instead of a separate byte store
 * + LDIR.  Bytes +13..+36 of the FCB are left zero — msg[] lives
 * in BSS so the zero tail is already there, and install_fcb only
 * runs once before any FCB response has overwritten those slots. */
SECTION_INIT_RODATA
static const uint8_t FCB_HEAD[13] = {
    0x00,                                /* +0  user number = 0 */
    0x01,                                /* +1  drive A (1-based) */
    'C','P','N','O','S',' ',' ',' ',     /* +2..+9  name */
    'I','M','G',                          /* +10..+12 ext */
};

/* Build and send a CP/NET request, then wait for the response.
 * Data must already be in msg[DAT..DAT+dat_len-1].  siz_minus_1 must be
 * dat_len - 1 per DRI convention (SIZ=0 means 1 byte).
 * Returns response retcode (msg[DAT] on success); 0xFE on transport err. */
SECTION_INIT_TEXT
static uint8_t cpnet_xact(uint8_t fnc, uint8_t siz_minus_1) {
    msg[FMT] = 0x00;
    msg[DID] = 0x00;                 /* to master */
    msg[SID] = 0x01;                 /* our slave ID; SNIOS overwrites from CFGTBL */
    msg[FNC] = fnc;
    msg[SIZ] = siz_minus_1;
    if (cpnet_send_msg(msg) != 0) return 0xFE;
    if (cpnet_recv_msg(msg) != 0) return 0xFE;
    return msg[DAT];
}

/* Copy the 13-byte FCB header (user-number byte + 12-byte FCB)
 * into msg.  The 24-byte zero tail is already zero in BSS. */
SECTION_INIT_TEXT
static void install_fcb(void) {
    __builtin_memcpy(&msg[DAT], FCB_HEAD, 13);
}

/* Rewrite only DAT[0]=user.  FCB is already in msg[DAT+1..DAT+36] from
 * the previous response — caller should not touch it between calls. */
SECTION_INIT_TEXT
static void reuse_fcb(void) {
    msg[DAT] = 0;                    /* user number */
}

/* Tiny helper, called twice from netboot_mpm.  Forced noinline; without
 * it clang re-inlines the body at each site (the inliner doesn't know
 * we prefer 3-byte call over 10-byte body duplication on Z80). */
SECTION_INIT_TEXT
NOINLINE static void crlf(void) {
    impl_conout(0x0d);
    impl_conout(0x0a);
}

SECTION_INIT_TEXT
static uint16_t netboot_mpm(void) {
    BOOT_MARK(8, 'N');               /* entered netboot_mpm */
    /* Arm SNIOS.  Drains SIO RX and flips CFGTBL.NETST.ACTIVE. */
    if (snios_ntwkin() != 0) return 0;
    BOOT_MARK(9, 'I');               /* NTWKIN ok */

    /* --- LOGIN ----------------------------------------------------- */
    __builtin_memcpy(&msg[DAT], login_pwd, 8);
    if (cpnet_xact(64, 7) != 0) return 0;
    BOOT_MARK(10, 'L');              /* LOGIN ok */

    /* --- Print master wall-clock via FN 105 (custom SERVER.RSP gettod)
     * Reply: 5 B binary SCB-DAT then 21 B ASCII "YYYY-MM-DD HH:MM:SS\r\n".
     * KNOWN ISSUE 2026-06-10: server returns neterr (FF 0C) for this FNC
     * despite gettod being correctly assembled in fnctab[55]/fncptr[17].
     * See tasks/gettod-dispatch-mystery.md.  Code is left in place so
     * the print will start working once the dispatch bug is found.
     * Inline asm to stay under .init's 640 B budget. */
    cpnet_xact(105, 0);
    ASM_VOLATILE(
        "ld   hl, _cfgtbl + 39 + 5 + 5\n\t" /* &msg[DAT+5] */
        "ld   b, 21\n"
        "1:\n\t"
        "ld   a, (hl)\n\t"
        "push hl\n\t"
        "push bc\n\t"
        "call _impl_conout\n\t"
        "pop  bc\n\t"
        "pop  hl\n\t"
        "inc  hl\n\t"
        "djnz 1b\n"
    );

    /* --- OPEN A:CPNOS.IMG ----------------------------------------- */
    install_fcb();
    /* BDOS OPEN returns directory code 0..3 on success, 0xFF on
     * not-found; MP/M passes that raw return through (issue #40). */
    if (cpnet_xact(15, 36) >= 0x04) return 0;
    BOOT_MARK(11, 'O');              /* OPEN ok */

    /* --- READ-SEQ loop -------------------------------------------- */
    /* Runtime IMG_BASE: PROM1-only build shifts down by 384 B for
     * the locale prefix; two-PROM does too once both relocators
     * set the sentinel.  Branch lives in get_img_base() (.resident)
     * to keep this .init function under the 640 B cap.  File-scope
     * extern (top of init.c) so SDCC's z88dk back-end emits the
     * EXTERN _get_img_base directive in the generated .asm. */
    uint8_t *dma = get_img_base();
    for (;;) {
        reuse_fcb();
        uint8_t rc = cpnet_xact(20, 36);
        if (rc == 1) break;          /* EOF */
        if (rc != 0) return 0;       /* error */
        BOOT_MARK(12, 'R');          /* first/each READ ok (idempotent) */
        /* Response: DAT[0]=rc, DAT[1..36]=FCB, DAT[37..164]=128B sector. */
        __builtin_memcpy(dma, &msg[DAT + 37], 128);
        dma += 128;
        impl_conout('.');            /* one dot per 128-byte sector */
        /* Safety: refuse to overflow into our resident BIOS.  cpnos.com's
         * load region runs up to `bios_boot` (0xED00 today; was 0xEE00
         * pre-Path-6 on 2026-05-08, hence the prior literal that drifted
         * out of sync — #80).  Strict `>`: dma == bios_boot means the
         * last 128 B sector landed exactly at the limit (loaded into
         * bios_boot-128 .. bios_boot-1), which is fine — the next
         * READ-SEQ returns EOF and breaks.  Routing through the linker
         * symbol so any future BIOS_BASE move auto-tracks. */
        if (dma > bios_boot) return 0;
    }
    BOOT_MARK(13, 'E');              /* EOF reached */
    crlf();

    /* --- print build stamp from last 32 B of payload --------------
     * stamp_cpnos.py writes 31 ASCII bytes + 0x00 sentinel into the
     * trailing 0x1A padding of cpnos.com.  The text is the build
     * timestamp + git hash + optional locale tag (e.g.
     * "2026-05-17 19:14 0aa5e7e da_US").  The locale tag rides here
     * rather than on print_banner's row 0 because the slave PROM
     * doesn't know which locale tables the master's cpnos.img
     * carries until netboot completes.  dma now points one past the
     * last loaded byte, so the stamp lives at dma-32..dma-1. */
    {
        const uint8_t *s = dma - 32;
        for (uint8_t i = 0; i < 31 && s[i] != 0; ++i) impl_conout(s[i]);
        crlf();
    }

    /* --- CLOSE ---------------------------------------------------- */
    reuse_fcb();
    (void)cpnet_xact(16, 36);        /* ignore — file close errors are not fatal */
    BOOT_MARK(14, 'C');              /* CLOSE done */

    return ENTRY_ADDR;
}


/* =============================================================
 *  4. Cold-boot orchestrator + banner
 * =============================================================
 *
 * Tail-called by the relocator after it copies resident bytes to
 * 0xED00.  Runs entirely from PROM (INIT_CODE / INIT_RODATA region)
 * before resident_handoff's `OUT (0x18),A` disables the PROMs.  After
 * that point these bytes are unmapped from the address space; control
 * has tail-called into the RAM-resident `resident_handoff` (in
 * cpnos_main.c).
 */

/* Banner printed BEFORE netboot so the screen layout is:
 *   row 0 (cursor home): "RC702 CP/NOS NNK WWW-MMM cc yyyy-mm-dd HH:MM hash"
 *   row 1: 25 netboot progress dots followed by CR/LF on EOF
 * Operator sees the OS identity immediately on power-on, then
 * watches dots fill in below it. */
SECTION_INIT_TEXT
static void print_banner(void) {
    /* NNK = TPA size (CPNOS_TPA_KB, build-time from cpnos.sym).
     * WWW-MMM = TRANSPORT_NAME literal (Makefile -DTRANSPORT_NAME='"PIO"'/"SIO").
     * cc = CPNOS_COMPILER_NAME ("clang"/"sdcc"/"hitech"), picked at preprocess time
     * so the banner unambiguously identifies which build is running.
     *
     * The locale tag (da_US / da_DK / ...) intentionally does NOT
     * appear on this banner -- print_banner runs BEFORE netboot, so
     * cpnos.img hasn't been loaded yet and the slave PROM1 has no
     * idea which locale tables the master's cpnos.img is carrying.
     * The locale tag rides on the cpnos.img stamp line instead
     * (printed on row 2 by netboot_mpm's stamp reader). */
#define _STR(x) #x
#define STR(x) _STR(x)
    static const SECTION_INIT_RODATA char banner[] =
        "RC702 CP/NOS " STR(CPNOS_TPA_KB) "K "
        TRANSPORT_NAME " " CPNOS_COMPILER_NAME " " BUILD_INFO_STR "\r\n";
    for (const char *p = banner; *p; ++p) impl_conout((uint8_t)*p);
#undef STR
#undef _STR
}

/* Init phase: runs in place from PROM 0 (INIT_CODE region).
 * Tail-called by the relocator after it copies resident bytes to
 * 0xED00.  Calls into resident-RAM helpers (impl_conout, snios_*,
 * runtime stubs) work because the relocator already populated
 * 0xED00+ before JPing here.  PROMs are still mapped through
 * netboot completion; resident_handoff (RAM) does the OUT. */
extern uint8_t console_joined;       /* resident.c -- gated by SW1 bit 0 */

/* xport_jt.s trampolines: 3-byte JP NN each, NN patched at cold-init. */
extern uint8_t xport_send_byte[];    /* xport_jt.s */
extern uint8_t xport_recv_byte[];
extern void transport_pio_send_byte(uint8_t);
extern uint16_t transport_pio_recv_byte(uint16_t);
/* SIO transport functions use unprefixed names -- historical artefact;
 * see transport_sio.c (transport_send_byte / transport_recv_byte). */
extern void transport_send_byte(uint8_t);
extern uint16_t transport_recv_byte(uint16_t);

/* Patch the JP NN trampolines in xport_jt.s based on SW1 bit 2 (S03).
 *   On  (bit=0, default) -> PIO (already the link-time default).
 *   Off (bit=1)          -> SIO (overwrite NN bytes at +1 / +2).
 * The address references to the SIO transport functions here are what
 * keep transport_sio.o alive under --gc-sections in the dual-transport
 * build.
 *
 * Lives in .resident (RAM-loaded by the bootstrap before .init runs)
 * rather than .init -- the .init region is capped at 640 B by the
 * linker script and has no room.  Costs ~0 B in .init (just one CALL)
 * and ~30 B in .resident. */
SECTION_RESIDENT
static void install_transport(void) {
    if (IO_READ(SW1) & 0x04) {
        /* Write the JP-NN target as a single 16-bit store per slot.
         * Pointer-aliasing through uint16_t* lets clang -Oz emit
         * Z80's `LD (nn),HL` (3 B) instead of two `LD (nn),A` (6 B).
         * Z80 has no alignment requirements; the volatile cast keeps
         * the optimiser from rewriting the store back to two bytes. */
        *(volatile uint16_t *)&xport_send_byte[1] =
            (uint16_t)&transport_send_byte;
        *(volatile uint16_t *)&xport_recv_byte[1] =
            (uint16_t)&transport_recv_byte;
    }
}

SECTION_INIT_TEXT
NORETURN void cpnos_cold_entry(void) {
    /* Locale-tables pre-init: byte-identity outcon at 0xF680..0xF6FF
     * + sentinel armed.  This used to live in PROM1-only's bootstrap.s
     * (asm) and the two-PROM relocator.c (clang-only inline asm); both
     * call paths now share this one C site so the SDCC two-PROM build
     * gets locale support without per-compiler asm.
     *
     * Why HERE: cpnos_cold_entry is the first place after the cold
     * paths converge.  print_banner (the next call after these few
     * SW1 reads) goes through impl_conout, which uses the outcon
     * table at 0xF680 when the sentinel is set -- pre-filling with
     * identity bytes lets the banner render as its literal characters
     * before install_locale_tables() overlays the real US-ASCII
     * outcon in resident_handoff.  Sentinel set here also flips
     * get_img_base() into "shift IMG_BASE down by 384 B" mode so
     * netboot lands the cpnos.img locale prefix at 0xDC00.
     *
     * Costs ~25 B init.c .text via the compiled for-loop; within the
     * 640 B .init region budget on both compilers. */
    {
        uint8_t *outcon = (uint8_t *)0xF680;
        for (uint8_t i = 0; i < 128; i++) outcon[i] = i;
        extern uint8_t prom1_only_sentinel;
        prom1_only_sentinel = 0x5A;
    }

    /* Sample SW1 bit 0 (S01) ONCE -- impl_conin / impl_conout are hot.
     * MAME "On" = bit clear = joined console (SIO-B + keyboard input,
     * SIO-B + CRT output); MAME "Off" = bit set = local-only.
     * Must happen before print_banner because that calls impl_conout. */
    console_joined = (IO_READ(SW1) & 0x01) == 0 ? 1 : 0;

    /* SW1 bit 2 (S03): pick the SNIOS byte-transport (PIO vs SIO).
     * Patches the xport_jt.s trampolines in place; must happen before
     * any SNIOS call (netboot is downstream). */
    install_transport();

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

    /* Banner BEFORE netboot so it appears on row 0; netboot dots
     * flow on row 1 (operator's "OS identity at top, progress
     * below" expectation).  In PROM1-only, bootstrap.s has both
     * pre-filled outcon with byte-identity AND armed the sentinel
     * before this point, so impl_conout indexes a valid identity
     * table.  In two-PROM, the sentinel stays 0 (no bootstrap.s on
     * that path) and impl_conout bypasses the table entirely. */
    print_banner();

    uint16_t entry = netboot_mpm();
    BOOT_MARK(15, entry ? '+' : '-');

    /* Tail call into resident RAM -- everything after this point
     * (PROM disable, snios_ntwkin, nos_handoff, enter_coldst) MUST
     * run from RAM because PROM disable un-maps the INIT_CODE region. */
    resident_handoff(entry);
}
