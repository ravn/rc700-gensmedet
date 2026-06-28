/*
 * rom.c — RC702 autoload PROM: all CODE-section C source
 *
 * Single translation unit for the Z80 ROM build, enabling cross-function
 * inlining, dead code elimination, and better register allocation.
 *
 * Section order:
 *   1. HAL functions (FDC wait loops, delay)
 *   2. Initialization (post-relocation entry, peripherals, CRT banner)
 *   3. Format tables and geometry
 *   4. FDC driver (commands, result handling, read/seek)
 *   5. Boot logic (signature check, disk read, main)
 *   6. Interrupt service routines
 *   7. Sentinel (code_end marker)
 *
 * Separately compiled units (different link order or codeseg):
 *   - boot_rom.c  — BOOT section at 0x0000 (entry, init_fdc, banner string, NMI)
 *   - intvec.c    — IVT at 0x7000, linked first
 *   - sections.asm — linker section layout
 */

// ReSharper disable CppJoinDeclarationAndAssignment
#include <string.h>
#include "rom.h"

/* Wait for FDC ready-to-write, then write val to data register.
 * Polls MSR until RQM=1 and DIO=0 (CPU->FDC direction). */
void fdc_write_when_ready(byte val) {
    word t = 0;
    do {
        if ((fdc_status() & 0b11000000) == 0b10000000) {
            fdc_data_write(val);
            return;
        }
    } while (++t);
}

/* Wait for FDC ready-to-read, then read from data register.
 * Polls MSR until RQM=1 and DIO=1 (FDC->CPU direction).
 * Returns 0xFF on timeout (instead of valid data).
 */
byte fdc_read_when_ready(void) {
    word t = 0;
    do {
        if ((fdc_status() & 0b11000000) == 0b11000000) {
            return fdc_data_read();
        }
    } while (++t);
    return 0xFF;
}

/* ================================================================
 * delay_ms() — compiler-independent millisecond delay.
 *
 * SDCC: uses z88dk's z80_delay_ms() (hand-tuned asm, cycle-counted,
 *       calibrated via CRT_CPU_CLOCK_HZ=4000000 on the zcc command line).
 *
 * Clang: inline asm delay loop with known T-state count.
 *        Inner loop: DEC E; JR NZ = 16T per iteration (verified with ticks).
 *        Total: outer × inner × 256 × 16 T-states.
 *
 * Both are compiler-independent — no DELAY_T calibration needed.
 * ================================================================ */

#ifdef __SDCC

/* z88dk's z80_delay_ms: cycle-counted delay, calibrated via
 * CRT_CPU_CLOCK_HZ=4000000 on the zcc command line.
 * Declared here instead of #include <z80.h> because the arch/z80.h
 * header uses __smallc/__z88dk_fastcall qualifiers that zsdcc's
 * --c1mode --sdcccall 1 pipeline doesn't handle correctly. */
extern void z80_delay_ms(unsigned int ms);
#define delay_ms(ms) z80_delay_ms(ms)

/* Short runtime-variable delay for FDC timing (fdc_result_delay, fdc_isr_delay).
 * delay(0, N) is a no-op (outer=0 returns immediately). */
void delay(byte outer, byte inner) {
    if (!outer) return;
    do {
        byte mid = inner;
        do {
            byte k = 0;
            do { __asm__(""); } while (--k);
        } while (--mid);
    } while (--outer);
}

#else /* clang — inline asm delay with known timing */

#define Z80_MHZ  4
#define _DELAY_T 16   /* dec e; jr nz = 4+12 = 16T (verified with z88dk-ticks) */
#define _DELAY_TSTATES(ms)   ((long)(ms) * Z80_MHZ * 1000)
#define _DELAY_INNER_1(ms)   (_DELAY_TSTATES(ms) / (256L * _DELAY_T))
#define _DELAY_INNER_2(ms)   (_DELAY_TSTATES(ms) / (2L * 256 * _DELAY_T))

#define delay_ms(ms) \
    delay( \
        (_DELAY_INNER_1(ms) <= 255) ? 1 : 2, \
        (byte)((_DELAY_INNER_1(ms) <= 255) ? _DELAY_INNER_1(ms) : _DELAY_INNER_2(ms)) \
    )

/* Low-level delay: outer × inner × 256 × 16T.
 * Also used for short runtime-variable delays (fdc_result_delay, fdc_isr_delay). */
void delay(byte outer, byte inner) {
    if (!outer) return;
    do {
        byte mid = inner;
        do {
            byte k = 0;
            do {
                __asm__ volatile("");  /* optimization barrier */
            } while (--k);
        } while (--mid);
    } while (--outer);
}

#endif /* __SDCC / clang */

/* ================================================================
 * 2. Initialization
 * ================================================================ */

/* set_i_reg() provided by compiler-specific intrinsic headers */


/* Combined PIO/CTC/DMA/CRT initialization.
 * Macros expand to direct __sfr port writes on Z80. */
static void init_pio(void) {
    /* Z80 PIO — Port A = keyboard input, Port B = parallel output */
    pio_write_a_ctrl(0x02); /* Port A: interrupt vector = 0x02 */
    pio_write_b_ctrl(0x04); /* Port B: interrupt vector = 0x04 */
    pio_write_a_ctrl(0x4F); /* Port A: mode 1 (input) */
    pio_write_b_ctrl(0x0F); /* Port B: mode 0 (output) */
    pio_write_a_ctrl(0x83); /* Port A: interrupt — enable, AND, active high */
    pio_write_b_ctrl(0x83); /* Port B: interrupt — enable, AND, active high */
}

static void init_ctc(void) {
    /* Z80 CTC — 4 channels */
    ctc0_write(0x08); /* Ch0: interrupt vector base = 0x08 */
    ctc0_write(0x47); /* Ch0: counter, falling edge, TC follows, reset */
    ctc0_write(0x20); /* Ch0: time constant = 32 */
    ctc1_write(0x47); /* Ch1: counter, falling edge, TC follows, reset */
    ctc1_write(0x20); /* Ch1: time constant = 32 */
    ctc2_write(0xD7); /* Ch2 (display): counter, interrupt, TC follows */
    ctc2_write(0x01); /* Ch2: time constant = 1 (every retrace) */
    ctc3_write(0xD7); /* Ch3 (floppy): counter, interrupt, TC follows */
    ctc3_write(0x01); /* Ch3: time constant = 1 (every interrupt) */
}

/* ================================================================
 * SIO-B polled debug output (output-only, no interrupts)
 *
 * Autoload normally never touches the SIO — rcbios still owns the real
 * SIO initialization.  This is a minimal skeleton so we can print debug
 * text very early in autoload.  CTC channel 1 clocks SIO-B; the CONFI
 * block (rcbios boot_confi.c) uses CTC mode 0x47 / count 1 with the SIO
 * in x16 mode for a solid 38400 baud, 8-N-1 — we replicate exactly that.
 *
 * The control-register setup is a fixed byte sequence to one port, so it
 * goes out as a simple block loop (the OTIR idiom).  Character output must
 * still poll RR0 bit 2 (Tx buffer empty) because the Tx buffer is 1 byte
 * deep and the shifter runs at the emulated 38400 baud.
 * ================================================================ */
static const byte sio_b_init_seq[] = {
    0x18,         /* WR0: channel reset */
    0x04, 0x44,   /* WR4: x16 clock, 1 stop bit, no parity */
    0x05, 0xEA,   /* WR5: DTR=1, Tx enable, 8 bits/char, RTS=1 */
    0x01, 0x00,   /* WR1: no interrupts (polled output only) */
};

/* SIO-B debug output is gated by SW1 bit 0 (S01, port 0x14) -- the SAME
 * switch rcbios uses to enable its SIO-B console (see bios.c bios_boot_c).
 * Bit clear (On, default) = debug enabled; bit set (Off) = leave SIO-B
 * untouched so production hardware sees no autoload debug traffic. */
#define siob_debug_on()  ((read_sw1() & SW1_CONSOLE_BIT) == 0)

static void sio_b_debug_init(void) {
    if (!siob_debug_on())
        return;
    ctc1_write(0x47);   /* CTC ch1: counter mode, TC follows, reset */
    ctc1_write(0x01);   /* time constant = 1 -> 38400 baud (x16) */

    /* OTIR: output B control-register bytes from (HL++) to port C.
     * The setup is a fixed byte sequence to one port, so OTIR is the
     * natural idiom (matches rcbios bios_hw_init.c). */
#if defined(__SDCC) || defined(__SCCZ80) || !defined(__z80__)
    for (byte i = 0; i < sizeof sio_b_init_seq; i++)
        sio_b_ctrl_write(sio_b_init_seq[i]);
#else
    const byte *p = sio_b_init_seq;
    word bc = ((word) sizeof sio_b_init_seq << 8) | 0x0B;  /* B=count, C=port */
    __asm__ volatile("otir"
        : "+{hl}" (p), "+{bc}" (bc) :: "memory");
#endif
}

static void sio_b_putc(char c) {
    while ((sio_b_ctrl_read() & 0x04) == 0)   /* RR0 bit2: Tx buffer empty */
        ;
    sio_b_data_write((byte) c);
}

static void sio_b_puts(const char *s) {
    while (*s) {
        if (*s == '\n')
            sio_b_putc('\r');
        sio_b_putc(*s++);
    }
}

static void sio_b_hex8(byte v) {
    static const char hexd[] = "0123456789ABCDEF";
    sio_b_putc(hexd[(v >> 4) & 0x0F]);
    sio_b_putc(hexd[v & 0x0F]);
}

static void sio_b_hex16(word v) {
    sio_b_hex8((byte) (v >> 8));
    sio_b_hex8((byte) v);
}

static void init_dma(void) {
    /* AMD Am9517A / Intel 8237 DMA controller */
    dma_command(0x20); /* master clear + standard configuration */
    dma_mode(0xC0); /* Ch0: cascade mode (WD1000 hard disk) */
    dma_unmask(0); /* Ch0: enable */
    dma_mode(0x4A); /* Ch2: single xfer, read mem->I/O (display) */
}

static void init_crt(void) {
    /* Intel 8275 CRT controller (bits 7-5 = command code) */
    crt_command(0x00); /* reset (expect 4 param bytes) */
    crt_param(0x4F); /*   S=0, H=79: 80 chars/row */
    crt_param(0x98); /*   V=2 vretrace, R=24: 25 rows */
    crt_param(0x9A); /*   L=9 underline, U=10 lines/char */
    crt_param(0x5D); /*   F=0, M=1 transparent, C=01 blink, Z=28 */
    crt_command(0x80); /* load cursor (expect 2 param bytes) */
    crt_param(0x00); /*   column = 0 */
    crt_param(0x00); /*   row = 0 */
    crt_command(0xE0); /* preset counters */
}

/* SEM702 character generator: define a 64-glyph 2x3-block subset.
 *
 * The SEM702 ("Semigrafik Memory") is a RAM-based character generator
 * board that replaces the standard ROA327 ROM character generator in
 * socket IC82 -- see docs/RC702tech.pdf and the Comal80 example at
 * approx. line 17191 of docs/RC702tech.txt.  Ports:
 *   0xD1 (chargen_char) -- character number 0..127
 *   0xD2 (chargen_dot)  -- dot line 0..15
 *   0xD3 (chargen_data) -- pixel byte (LSB-first; dot 0 on the left)
 *
 * This function defines 64 sextant (2x3) block glyphs at the same
 * codepoints they occupy in ROA327, so a SEM702-equipped machine
 * renders identically to a ROA327 machine in that range:
 *
 *   0x20..0x3F -- patterns  0..31
 *   0x60..0x7F -- patterns 32..63
 *
 * All other codepoints are blanked.  A machine with the original ROA327
 * ROM still installed in IC82 silently ignores the OUT writes (the
 * ports go nowhere on that variant), so this is safe to run always --
 * no SW1 gating needed.
 *
 * Encoding (verified by xxd against ROA327 bytes at offsets 0x200..,
 * and against MAME's display_pixels which treats bit 0 of a chargen
 * byte as the LEFTMOST pixel):
 *   - 7-dot-wide cell.  Left half = 4 dots (byte mask 0x0F, bits 0..3);
 *     right half = 3 dots (mask 0x70, bits 4..6).  Both = 0x7F.
 *   - 16 line slots per char; active zones top=0..2, mid=3..6, bot=7..10.
 *   - Pattern N bit layout (matches ROA327; bit 0 = top-LEFT, the cell
 *     filled by ROA327 char 0x21 = pattern 1 = bytes 0x0F on lines 0..2):
 *       bit 0 top-left    bit 1 top-right
 *       bit 2 mid-left    bit 3 mid-right
 *       bit 4 bot-left    bit 5 bot-right
 */
static void define_sextants(void)
{
    /* half[(R<<1)|L] where L = pattern bit covering left half (bit 0/2/4),
     * R = bit covering right half (bit 1/3/5). */
    static const byte half[4] = { 0x00, 0x0F, 0x70, 0x7F };
    byte ch;
    for (ch = 0; ch < 128; ch++) {
        byte pattern, top = 0, mid = 0, bot = 0;
        byte line;
        if (ch >= 0x20 && ch <= 0x3F)
            pattern = ch - 0x20;
        else if (ch >= 0x60 && ch <= 0x7F)
            pattern = (byte)(ch - 0x60 + 32);
        else
            pattern = 0xFF;  /* blank: leave top/mid/bot = 0 */
        if (pattern != 0xFF) {
            top = half[pattern & 0x03];
            mid = half[(pattern >> 2) & 0x03];
            bot = half[(pattern >> 4) & 0x03];
        }
        port_out(chargen_char, ch);
        port_out(chargen_dot, 0);
        for (line = 0; line < 16; line++) {
            port_out(chargen_data,
                     line < 3 ? top
                   : line < 7 ? mid
                   : line < 11 ? bot
                   : (byte)0);
            /* ALINE must be set explicitly before each AWR write -- both
             * software sources we have (this routine, ultimately from
             * PHE358A.MAC's LDGEN, and the Comal80 example in
             * docs/RC702tech.txt) do so; no evidence the chip
             * auto-increments.
             * TODO(physical-machine): verify on real SEM702 hardware
             * whether ALINE auto-increments after AWR; MAME's strict-latch
             * model can't distinguish the two behaviours. */
            port_out(chargen_dot, (byte)((line + 1) & 0x0F));
        }
    }
}

/* Banner string lives in BOOT section (boot_rom.c). */
#ifdef __SDCC
#include "sdcc/build_stamp.h"
#else
#include "clang/banner.h"
#endif
#define BANNER_LENGTH BUILD_BANNER_LENGTH
extern const char banner_string[];
#define BANNER_PTR ((const byte *)banner_string)

/* Stamp the SW1 DIP-switch byte on display row 0, right-justified so
 * it shares the line with the boot banner.  Format (22 chars):
 *
 *   "SW1 12345678: 01101000"
 *
 * The "12345678" header lines up each bit with its switch number; the
 * 8 digits beneath show position per switch (S1=bit 0, S8=bit 7).
 * Switch On => bit reads 0 (the active convention used by autoload,
 * rcbios, and docs/SW1_BIT_MAP.md).  Placed at columns 58..79 so the
 * 31-char banner at columns 0..30 has clear breathing room.
 *
 * Reading happens once at boot; the field is informational only and
 * isn't re-read after this point.
 *
 * Compact form keeps PROM0 well under the 2048 B socket limit -- a
 * per-switch "S1:ON " form previously cost ~167 B compiled for ~50 B
 * of header + 8 B of dynamic bits here. */
static void display_sw1_status(void) {
    byte sw = read_sw1();
    char *p = (char *)dspstr + 80 - 22; /* row 0, col 58 */
    static const char prefix[] = "SW1 12345678: ";
    byte i;

    memcpy(p, prefix, sizeof prefix - 1);
    p += sizeof prefix - 1;

    for (i = 0; i < 8; i++) {
        *p++ = (char)('0' + ((sw >> i) & 1));
    }
}

/* Copy banner from BOOT ROM to display, stamp SW1 status on row 1,
 * and start CRT controller.  Programs DMA ch2 with display address
 * before starting CRT so the first frame renders immediately without
 * waiting for the ISR.
 *
 * Clears the full 80x25 display buffer to space (0x20) BEFORE the
 * memcpy banner because dspstr is power-on RAM (0x00 in MAME, also
 * 0x00 on real hardware after warm reset), and ROA296 renders byte
 * 0x00 as a Danish accented glyph that produces a visible dot-
 * pattern flicker across the whole screen during the autoload-to-
 * cpnos handoff window (~250 ms emulated; visible frame-by-frame in
 * MAME captures).  memset is 80 * 25 = 2000 bytes; LDIR-lowered by
 * clang so the cost is trivial. */
static void display_banner_and_start_crt(void) {
    memset(dspstr, 0x20, 80 * 25);
    memcpy(dspstr, BANNER_PTR, BANNER_LENGTH);
    display_sw1_status();
    /* Pre-program DMA ch2 for first frame (ISR takes over for subsequent frames) */
    dma_mask(2);                     /* disable ch2 during programming */
    dma_clear_bp();                  /* reset byte pointer flip-flop */
    dma_ch2_addr(DSPSTR_ADDR);      /* display buffer address */
    dma_ch2_wc(80 * 25 - 1);        /* word count (N-1) */
    dma_unmask(2);                   /* enable ch2 */
    crt_command(0x23);               /* start display: burst=0, 8 DMA cycles */
}

/* ================================================================
 * 3. Format tables and geometry
 * ================================================================ */

/* Format parameters for 8" maxi and 5.25" mini diskettes.
 *
 * Indexed by [sector_size_code N][side], where sector size = 128 << N.
 *   eot  = last sector number (EOT parameter for FDC Read Data)
 *   gap3 = gap 3 length in bytes (GPL parameter for FDC Read Data)
 *
 * Side 0 uses FM (single density), side 1 uses MFM (double density),
 * so they have different sector counts and gap sizes. */
typedef struct {
    byte eot;
    byte gap3;
} format_entry;

/* eot_gap3_table[is_mini][N][side] — indexed by disk type, sector size, density */
static const format_entry eot_gap3_table[2][4][2] = {
    /* maxi (8") */
    {   /*    side 0          side 1          N               */
        {{0x1A, 0x07}, {0x34, 0x07}}, /* 0: 128B  26/52 sectors */
        {{0x0F, 0x0E}, {0x1A, 0x0E}}, /* 1: 256B  15/26 sectors */
        {{0x08, 0x1B}, {0x0F, 0x1B}}, /* 2: 512B   8/15 sectors */
        {{0x00, 0x00}, {0x08, 0x35}}, /* 3: 1024B  0/8  sectors */
    },
    /* mini (5.25") */
    {   /*    side 0          side 1          N               */
        {{0x10, 0x07}, {0x20, 0x07}}, /* 0: 128B  16/32 sectors */
        {{0x09, 0x0E}, {0x10, 0x0E}}, /* 1: 256B   9/16 sectors */
        {{0x05, 0x1B}, {0x09, 0x1B}}, /* 2: 512B   5/9  sectors */
        {{0x00, 0x00}, {0x05, 0x35}}, /* 3: 1024B  0/5  sectors */
    },
};

/* Look up format parameters from disk type and sector size code. */
void lookup_sectors_and_gap3_for_current_track(void) {
    const format_entry *fmt = &eot_gap3_table[is_mini][fdc_cmd.size_shift][is_mfm];

    fdc_cmd.eot = fmt->eot;
    fdc_cmd.gap3 = fmt->gap3;
    fdc_cmd.dtl = 0x80;
}

/* Calculate transfer byte count for current track geometry.
 * transfer_bytes = sectors * (128 << N) = sectors << (7 + N) */
void calc_size_of_current_track(void) {
    byte sectors = ((disk_type & 0b10000000) && fdc_cmd.head == 1)
                       ? 10 /* maxi, head 1: only 10 sectors - probably a hack */
                       : fdc_cmd.eot - fdc_cmd.sector + 1;

    word tb = (word) sectors;
    for (byte i = 7 + fdc_cmd.size_shift; i != 0; i--) {
        tb <<= 1;
    }
    dma_transfer_size = tb;
}

/* ================================================================
 * 4. FDC driver — NEC uPD765 (Intel 8272)
 *
 * Main Status Register (fdc_status(), port 0x04):
 *   bit 7:   RQM  — ready for CPU data transfer
 *   bit 6:   DIO  — direction (0=CPU->FDC, 1=FDC->CPU)
 *   bit 5:   EXM  — in execution phase
 *   bit 4:   CB   — command busy
 *   bits 3-0:       drive busy flags
 *
 * Result registers (fdc_result[], via fdc_result_delay_read()):
 *   ST0 [0]: IC (7-6), SE (5), HD (2), US (1-0)
 *   ST1 [1]: error flags (EN, DE, OR, ND, NW, MA)
 *   ST2 [2]: error flags; bit 6 = CM (benign)
 *   ST3 [0]: from Sense Drive — RDY (5), HD+US (2-0)
 *   [3]-[6]: C, H, R, N
 * ================================================================ */

/*
 * wait_floppy_ready() timing model.
 *
 * Must cover worst-case FM track read: 8" at 360 RPM = 166ms/rev.
 * Wait for sector 1 (~1 rev) + read 26 sectors (~1 rev) = 332ms.
 * Require >= 400ms total timeout across 255 iterations.
 *
 * Each of 255 poll iterations does delay_ms(WAITFL_POLL_MS).
 * Original ROM: WAITFL calls DELAY with B=1,C=1 → ~3ms per poll.
 * 255 × 3ms = 765ms total timeout (>= 400ms required).
 */
#define WAITFL_POLL_MS    3

/* Compile-time check: total timeout >= 400ms */
typedef char _waitfl_timeout_check[(255L * WAITFL_POLL_MS >= 400) ? 1 : -1];

/* Send Sense Interrupt Status; ST0 in [0], PCN in [1]. */
void fdc_sense_interrupt(void) {
    fdc_write_when_ready(FDC_SENSE_INT);
    fdc_result.st0 = fdc_read_when_ready();
    if ((fdc_result.st0 & 0b11000000) != 0b10000000) {
        /* IC != 10 (not invalid cmd) */
        fdc_result.st1 = fdc_read_when_ready(); /* PCN (present cylinder) */
    }
}

/* Send Seek command to head/drive dh, cylinder cyl. */
static void fdc_seek(byte head_and_drive, byte cylinder) {
    fdc_write_when_ready(FDC_SEEK);
    fdc_write_when_ready(head_and_drive & 0b00000111); /* HD + US (head + drive) */
    fdc_write_when_ready(cylinder); /* NCN (new cylinder number) */
}

/* Read FDC result phase (up to 7 bytes into fdc_result) and DMA status after. */
void fdc_read_result(void) {
    byte i;
    byte *p = (byte *) &fdc_result;

    for (i = 0; i < 7; i++) {
        p[i] = fdc_read_when_ready();
        /* delay(0, fdc_result_delay); — no-op: outer=0 returns immediately */
        if (!(fdc_status() & 0b00010000)) {
            /* CB=0: no more result bytes */
            p[i + 1] = dma_status();
            return;
        }
    }
    error_saved = 0xFE;
    error_display_halt(0xFE);
}

/* Wait for floppy interrupt (floppy_flag set by ISR).
 * Returns 0=ok, 1=timeout. */
byte wait_fdc_ready(byte timeout) {
    while (--timeout) {
        delay_ms(WAITFL_POLL_MS);
        if (floppy_operation_completed_flag) {
            intrinsic_di();
            floppy_operation_completed_flag = 0;
            intrinsic_ei();
            return 0;
        }
    }
    // after repeated tries timing out, fdc did not complete.
    return 1;
}

/* Forward declarations for tail-call fall-through reordering */
static byte verify_seek_result(byte expected_pcn);

static void get_floppy_ready(void);

static void boot_from_floppy_or_jump_prom1(void);

/* Seek to fdc_cmd.cylinder and verify.
 * Placed before verify_seek_result for tail-call fall-through (saves 3 bytes). */
byte fdc_select_drive_cylinder_head(void) {
    fdc_seek((byte)((fdc_cmd.head << 2) | drive_select), fdc_cmd.cylinder);
    return verify_seek_result(fdc_cmd.cylinder);
}

/* Wait for seek/recalibrate interrupt, verify ST0 and PCN.
 * Returns 0=ok, 1=timeout, 2=wrong drive or cylinder. */
static byte verify_seek_result(byte expected_pcn) {
    if (wait_fdc_ready(0xFF)) {
        return 1;
    }
    if ((drive_select + 0b00100000) != fdc_result.st0 || /* SE+drive */ /* TODO:  Should this be an and? */
        expected_pcn != fdc_result.st1) {
        /* verify PCN */
        return 2;
    }
    return 0;
}

/* Issue FDC read command with parameter block.
 * For Read Data, sends 7-byte block: C, H, R, N, EOT, GPL, DTL. */
void fdc_write_full_cmd(byte cmd) {
    byte mfm_flag = is_mfm ? FDC_MFM : 0;
    byte dh = (byte)((fdc_cmd.head << 2) | drive_select);

    intrinsic_di();
    fdc_write_when_ready(cmd + mfm_flag); /* command (+MFM if double density) */
    fdc_write_when_ready(dh); /* head/drive select */

    if ((cmd & 0b00001111) == FDC_READ_DATA) {
        /* 7-byte parameter block: C, H, R, N, EOT, GPL, DTL */
        byte i;
        for (i = 0; i < sizeof(fdc_cmd); i++) {
            fdc_write_when_ready(((byte *) &fdc_cmd)[i]);
        }
    }
    intrinsic_ei();
}

/* Check FDC result status.  Returns 0=ok, 1=retry, 2=give up. */
byte check_fdc_result(void) {
    if ((fdc_result.st0 & 0b11000011) == drive_select && /* ST0: IC=00 + drive */
        fdc_result.st1 == 0 && /* ST1: no errors */
        (fdc_result.st2 & 0b10111111) == 0) {
        /* ST2: ignore CM */
        return 0;
    } else {
        retry_count--;
        return (retry_count == 0) ? 2 : 1;
    }
}

/* File-scope global to avoid IX frame pointer in retry loop. */
static byte saved_fdc_command;

/* Returns 0=ok, 1=error. */
byte fdc_get_result_bytes(byte cmd, byte retries) {
    byte r;
    saved_fdc_command = cmd;
    retry_count = retries;

    while (1) {
        /* clear floppy interrupt flag */
        intrinsic_di();
        floppy_operation_completed_flag = 0;
        intrinsic_ei();

        if ((saved_fdc_command & 0b00001111) != FDC_READ_ID) {
            /* program DMA channel 1 for fdc transfer */
            intrinsic_di();
            dma_mask(1); /* disable Ch1 during programming */
            dma_mode(0x45); /* Ch1: demand, incr, write I/O->mem */
            dma_clear_bp(); /* reset byte pointer flip-flop */
            dma_ch1_addr(dma_transfer_address); /* transfer destination address */
            dma_ch1_wc(dma_transfer_size - 1); /* word count (N-1) */
            dma_unmask(1); /* enable Ch1 */
            intrinsic_ei();
        }

        fdc_write_full_cmd(saved_fdc_command);

        if (wait_fdc_ready(0xFF)) {
            return 1;
        }

        r = check_fdc_result();
        if (r == 0) {
            return 0;
        }
        if (r == 2) {
            return 1;
        }
    }
}

/* Auto-detect disk format by reading sector ID.
 * Tries FM first, then MFM.  Returns 0=ok, 1=error. */
byte fdc_detect_sector_size_and_density(void) {
    is_mfm = 0;

    while (1) {
        if (fdc_select_drive_cylinder_head() != 0) {
            return 1;
        }

        dma_transfer_size = 4;
        if (fdc_get_result_bytes(FDC_READ_ID, 1) == 0) {
            break;
        }
        if (is_mfm) {
            return 1;
        }
        is_mfm = 1; /* switch to MFM and retry */
    }

    fdc_cmd.size_shift = fdc_result.size_code & 0b00000111;
    lookup_sectors_and_gap3_for_current_track();
    calc_size_of_current_track();
    return 0;
}

/* ================================================================
 * 5. Boot logic
 * ================================================================ */

/* Boot state variables — initialized to zero; preinit() sets non-zero.
 *
 * fdc_cmd is a 8-byte struct sent sequentially by floppy_read_track(). */
fdc_result_block fdc_result = {0};
byte drive_select = 0;
byte fdc_isr_delay = 0;
byte fdc_result_delay = 0;
fdc_command_block fdc_cmd = {0};
volatile byte floppy_operation_completed_flag = 0;
byte is_mini = 0;
byte is_mfm = 0;
static byte is_double_sided = 0;
byte disk_type = 0;
byte more_tracks_to_read = 0;
byte retry_count = 0;
word dma_transfer_address = 0;
word dma_transfer_size = 0;
word bytes_left_to_read = 0;
byte error_saved = 0;

static const char msg_rc702[] = " RC702";

/* Infinite loop — never returns.
 * Disable floppy interrupt (CTC ch3) to prevent the floppy ISR from
 * blocking the CRT refresh ISR with its delay loop.
 * Mask DMA ch1 (floppy) to stop stray DMA transfers.
 * Then enable interrupts so the CRT DMA ISR keeps refreshing. */
NORETURN void halt_forever(void) {
    ctc3_write(0x03);   /* disable CTC ch3 interrupt, reset */
    dma_mask(1);
    intrinsic_ei();
    for (;;);
}

/* Copy 'len' bytes to display buffer, then halt forever.
 * Macro so 'len' is compile-time constant — sdcc inlines as LDIR.
 * 'len' must NOT include NUL terminator.
 *
 * Halt messages land on row 2 (offset 80*2 = 160).  Row 0 holds the
 * boot banner (left) and SW1 status (right, see display_sw1_status);
 * row 1 is intentionally blank as a visual separator.  Keep future
 * status lines off row 2 — any messages overlapping it will scribble
 * over a still-running halt message. */
#define halt_msg(msg, len) do { memcpy(dspstr + 80 * 2, (msg), (len)); halt_forever(); } while(0)

/* Compare 6 bytes.  A __naked DJNZ version would save only 1 byte
 * (sdcc uses DEC C/JR NZ = 3 bytes vs DJNZ = 2 bytes, but setup is same).
 * sdcccall(1) passes HL=a, DE=b which is ideal for DJNZ loop, but
 * not worth the readability cost for 1 byte.
 *
 * Pointer-increment generates compact sdcc output
 * (17 bytes, no IX frame) vs memcmp library call (24 bytes more). */
byte compare_6bytes(const byte *a, const byte *b) {
    byte i = 6;
    do {
        if (*a++ != *b++) {
            return 1;
        }
    } while (--i);
    return 0;
}

/* Check directory entry: 4-byte name match + attribute byte check. */
byte check_sysfile(const byte *dir, const char *pattern) {
    dir++; /* skip initial bye´te (dir[0]) */

    byte i = 4;
    do {
        if (*dir++ != *pattern++) {
            return 1;
        }
    } while (--i);

    /* dir now at dir[5], check attribute at dir[8] */
    if ((dir[3] & 0b00111111) != 0x13) {
        return 1;
    }
    return 0;
}

/* Display error and halt (unless disk_type indicates retry). */
void error_display_halt(byte code) {
    error_saved = code;
    intrinsic_ei();
    if (disk_type & 0b00000001) {
        return;
    }
    beep();
    halt_msg("**DISKETTE ERROR** ", 19);
}

/*
 * Verify Track 0 data and boot.
 *
 * Checks two signatures in Track 0:
 *   0x0002: " RC700" — ID-COMAL: search dir for SYSM/SYSC, then floppy_legacy_boot
 *   0x0008: " RC702" — CP/M: jump via vector at 0x0000
 *   neither: halt with error
 *
 * File-scope global (boot_dir) avoids IX frame pointer. */
static byte *boot_dir;

/* DEBUG BREAKPOINT HOOK.
 *
 * Deliberately non-inlined, externally visible symbol so the MAME Lua
 * debugger can `bpset` on its address (read from the autoload .map) and stop
 * right after the BIOS image has been loaded from disk to 0x0000, just before
 * the jump into the BIOS cold-boot vector — the point at which we want to
 * inspect memory placement.  It also dumps a placement summary over SIO-B so
 * the same information is visible without attaching the debugger. */
__attribute__((noinline, used))
void autoload_bios_loaded_bp(void);
__attribute__((noinline, used))
void autoload_bios_loaded_bp(void) {
    /* SIO-B debug dump is gated by the same SW1 console switch as the rest
     * of the autoload SIO-B output (and rcbios' console).  When the switch
     * is off SIO-B was never initialized (sio_b_debug_init returned early),
     * so emitting here would block forever polling Tx-ready -- skip it.
     * The empty-asm bpset target below stays UNconditional so the MAME
     * debugger can still break right after the BIOS load regardless. */
    if (siob_debug_on()) {
        sio_b_puts("\nautoload: BIOS loaded from disk.\n");
        sio_b_puts("boot_ptr @0000 = ");
        sio_b_hex16(*(volatile word *) 0x0000);
        sio_b_puts("\nsig @0008      = ");
        for (byte i = 0; i < 6; i++)
            sio_b_putc(((const char *) 0x0008)[i]);
        sio_b_puts("\nfirst16 @0000  =");
        for (byte i = 0; i < 16; i++) {
            sio_b_putc(' ');
            sio_b_hex8(((const byte *) 0x0000)[i]);
        }
        sio_b_putc('\n');
    }
    __asm__ volatile("");   /* stable bpset target — do not fold away */
}

static NORETURN void boot_floppy_or_prom(void) {
    if (compare_6bytes((const byte *) RC700_SIG_OFF, (const byte *) " RC700") == 0) {
        boot_dir = (byte *) BOOT_DIR_OFF;
        while ((word) boot_dir < 0x0D00) {
            if (*boot_dir == 0) {
                boot_dir += 0x20;
                continue;
            }
            if (check_sysfile(boot_dir, "SYSM") == 0) {
                boot_dir += 0x20;
                if (*boot_dir != 0 &&
                    check_sysfile(boot_dir, "SYSC") == 0) {
                    floppy_legacy_boot();
                }
            }
            break;
        }
        halt_msg(" **NO SYSTEM FILES** ", 21);
    }

    if (compare_6bytes((const byte *) RC702_SIG_OFF, (const byte *) msg_rc702) == 0) {
        autoload_bios_loaded_bp();
        jump_to(*(volatile word *) 0x0000);
    }

    /* Intentional: readable-disk-no-recognised-signature halts here and
     * does NOT fall back to prom1_if_present().  Unlike the four
     * floppy-failure paths upstream of this function (drive-not-ready,
     * format-undetectable, both sides + recalibrate failures), which
     * all chain to PROM1, a Track 0 we successfully read but cannot
     * recognise is treated as an inserted stranger's disk -- we refuse
     * to silently jump into PROM1 (potentially a CP/NET lineprog that
     * the operator did not intend to run).  Policy confirmed 2026-05-17.
     * See tasks/timeline.md session 73j follow-up #8. */
    halt_msg(" **NO KATALOG** ", 16);
}

/* Check secondary PROM at 0x2000 for RC702 signature; jump or halt.
 *
 * SW1 bit 1 (S02) is the operator-visible PROM1 enable:
 *   On  (bit=0, default) -> check the PROM1 signature; jump to the
 *                           lineprog at 0x2000 if it's there.
 *   Off (bit=1)          -> skip the signature check entirely; halt
 *                           with NO DISKETTE NOR LINEPROG even when a
 *                           lineprog EPROM is socketed.  Lets the
 *                           operator lock out the PROM1 fallback
 *                           without physically pulling the chip.
 */
void prom1_if_present(void) {
    if ((read_sw1() & 0x02) == 0 &&
        compare_6bytes((const byte *) 0x2002, (const byte *) msg_rc702) == 0) {
        jump_to(*(word *)0x2000);
        return;
    }
    halt_msg(" **NO DISKETTE NOR LINEPROG** ", 30);
}

/* Read total_bytes_to_read from floppy, spanning multiple tracks/heads.
 * Queries FDC for track geometry via disk_autodetect(), then reads one
 * track at a time until all bytes are transferred.  Advances head and
 * cylinder automatically.  Enough for CP/M boot (Track 0 both sides);
 * stand-alone systems (e.g. COMAL) may call this again for more data. */
static void fdc_read_data_from_current_location(word total_bytes_to_read) {
    bytes_left_to_read = total_bytes_to_read;

    while (1) {
        byte r = fdc_select_drive_cylinder_head();
        if (r == 1) {
            prom1_if_present();
            return;
        }
        if (r != 0) {
            error_display_halt(0x06);
            return;
        }

        /* calculate transfer size.
         * The 'remaining' local generates smaller code than in-place
         * subtraction: sdcc keeps it in HL (free), and the else-branch
         * uses a simple 16-bit load (6 bytes) instead of += which
         * requires load-add-store (10+ bytes).  Values < 32K so
         * signed comparison is safe. */
        {
            int16_t remaining;
            calc_size_of_current_track();
            remaining = (int16_t) bytes_left_to_read - (int16_t) dma_transfer_size;
            if (remaining > 0) {
                more_tracks_to_read = 1;
                bytes_left_to_read = (word) remaining;
            } else {
                more_tracks_to_read = 0;
                dma_transfer_size = bytes_left_to_read;
                bytes_left_to_read = 0;
            }
        }

        if (fdc_get_result_bytes(FDC_READ_DATA, 5) != 0) {
            error_display_halt(0x28);
            return;
        }

        dma_transfer_address += dma_transfer_size;
        dma_transfer_size = 0;

        /* advance to next head/side or cylinder (inlined nxthds) */
        {
            byte max_head;
            fdc_cmd.sector = 1;
            max_head = is_double_sided;
            if (max_head == fdc_cmd.head) {
                fdc_cmd.head = 0;
                fdc_cmd.cylinder++;
            } else {
                fdc_cmd.head++;
            }
        }

        if (!more_tracks_to_read) {
            return;
        }
    }
}

static void init_fdc(void) {
    delay_ms(391);  /* FDC power-on delay: original ROM uses B=1,C=0xFF ≈ 391ms */
    while (port_in(fdc_status) & 0x1F)
        ;
    fdc_write_when_ready(0x03);  /* Specify command */
    fdc_write_when_ready(0x4F);  /* step rate 3ms, head unload 240ms */
    fdc_write_when_ready(0x20);  /* DMA mode */
}

/* Initialize boot state and start floppy boot.
 * Placed before fldsk1 for tail-call fall-through (saves 3 bytes). */
static void get_floppy_ready(void) {
    fdc_isr_delay = 3;
    fdc_result_delay = 4;
    is_mini = (read_sw1() >> 7) & 1; /* SW1 bit 7: 0=maxi, 1=mini */

    intrinsic_ei();
    motor(1); /* turn on floppy motor */
    retry_count = 5;
    boot_from_floppy_or_jump_prom1();
}

/* Floppy boot sequence: sense, recalibrate, detect, read, boot.
 * Placed before floppy_legacy_boot for tail-call fall-through (saves 3 bytes). */
static void boot_from_floppy_or_jump_prom1(void) {
    byte status;

    delay_ms(391);  /* motor spin-up: original ROM uses B=1,C=0xFF ≈ 391ms */

    /* sense drive status (inlined sense_drive) */
    fdc_write_when_ready(FDC_SENSE_DRIVE);
    fdc_write_when_ready(drive_select);
    fdc_result.st0 = fdc_read_when_ready(); /* ST3 (in st0 position) */
    status = fdc_result.st0 & 0b00100011; /* RDY + HD + US */

    /* recalibrate (inlined fdc_recalibrate + recalibrate_verify) */
    fdc_write_when_ready(FDC_RECALIBRATE);
    fdc_write_when_ready(drive_select);

    if (status != (drive_select + 0b00100000) || /* expect RDY + matching drive */
        verify_seek_result(0) != 0) {
        prom1_if_present();
        return;
    }

    /* detect disk format on both sides (inlined detect_floppy_format) */
    fdc_cmd.cylinder = 0;
    fdc_cmd.head = 1;
    fdc_cmd.sector = 1;
    if (fdc_detect_sector_size_and_density() == 0) {
        is_double_sided = 1; /* side 1 present */
    }
    fdc_cmd.head = 0;
    if (fdc_detect_sector_size_and_density() != 0) {
        prom1_if_present();
        return;
    }

    prom_disable(); /* disable ROM overlay -- now all ram accessible */

    while (1) {
        fdc_read_data_from_current_location(dma_transfer_size);
        if (fdc_cmd.cylinder != 0) {
            break;
        }
        fdc_detect_sector_size_and_density();
    }

    disk_type = 1;
    boot_floppy_or_prom();
}

/* Boot from floppy: read COMAL boot area to 0x0000 and jump to 0x1000.
 * Reads up to INTVEC_ADDR (0x7000) bytes — enough to fill memory from
 * 0x0000 to just below the IVT.  The original ROM passes HL=INTVEC to
 * RDTRK0 as the byte count. */
void floppy_legacy_boot(void) {
    disk_type = (byte)((is_mini << 7) | disk_type);
    disk_type--;
    fdc_detect_sector_size_and_density();
    dma_transfer_address = FLOPPYDATA;
    fdc_read_data_from_current_location(INTVEC_ADDR);
    disk_type = 1;
    jump_to(LEGACYBOOT);
}

/* BIOS syscall: read sectors from disk.
 * addr = DMA destination, bc = packed cylinder/head/sector. */
void syscall(word addr, word de) {
    byte d = (byte) (de >> 8);
    byte e = (byte) (de & 0b11111111);

    dma_transfer_address = addr;
    fdc_cmd.sector = e & 0b01111111;
    fdc_cmd.cylinder = d & 0b01111111;

    if (fdc_cmd.cylinder == 0) {
        fdc_detect_sector_size_and_density();
    }

    fdc_cmd.head = (d & 0b10000000) ? 1 : 0;
    fdc_read_data_from_current_location(0);

    if ((d & 0b01111111) == 0) {
        fdc_cmd.cylinder = 1;
        fdc_detect_sector_size_and_density();
    }
}

/* ================================================================
 * 6. Interrupt service routines
 *
 * Forward declarations here (not in rom.h) because SDCC requires
 * __interrupt(n) on declarations to match definitions exactly.
 * ================================================================ */
void nothing_int(void) __interrupt(0);
void refresh_crt_dma_50hz_interrupt(void) __critical __interrupt(1);
void floppy_completed_operation_interrupt(void) __critical __interrupt(2);

/* Dummy ISR for unused interrupt vectors (generates EI + RETI). */
void nothing_int(void) __interrupt(0) {
}

/* CRT vertical retrace ISR (CTC Ch2).
 *
 * Programs DMA Ch2 to transfer 2000 bytes from display buffer to the
 * 8275 CRT controller.  The boot ROM never scrolls, so the address and
 * word count are constant.  The BIOS replaces this ISR with its own.
 *
 * The original ROM used two DMA channels (Ch2+Ch3) and scroll_offset
 * for circular-buffer scrolling — not needed here since we don't scroll.
 *
 * __critical keeps interrupts disabled (protects DMA programming).
 * __interrupt(N) generates register save/restore + EI + RETI. */
void refresh_crt_dma_50hz_interrupt(void) __critical __interrupt(1) {
    (void) crt_status(); /* acknowledge CRT interrupt */

    dma_mask(2); /* disable Ch2 during programming */
    dma_clear_bp(); /* reset byte pointer flip-flop */

    dma_ch2_addr(DSPSTR_ADDR); /* Ch2: display buffer base */
    dma_ch2_wc(80 * 25 - 1); /* Ch2: full screen (2000 bytes) */

    dma_unmask(2); /* re-enable Ch2 */

    ctc2_write(0xD7); /* rearm CTC Ch2: counter, interrupt */
    ctc2_write(0x01); /* time constant = 1 (every retrace) */
}

/* Floppy disk ISR (CTC Ch3).
 * Sets floppy_flag, then reads result or senses interrupt. */
void floppy_completed_operation_interrupt(void) __critical __interrupt(2) {
    floppy_operation_completed_flag = 2; /* Only non-zero value */
    /* delay(0, fdc_isr_delay); — no-op: outer=0 returns immediately */
    if (fdc_status() & 0b00010000) {    /* CB=1: result phase ready */
        fdc_read_result();
    } else {
        fdc_sense_interrupt();
    }
}

/* Post-relocation entry point.  Called from start() after LDIR copy.
 * Sets SP, I register, IM2, then calls init_peripherals() + main().
 * __naked because we set SP mid-function.
 * Not marked NORETURN: __naked functions ignore the attribute, and on the
 * call-site in start() it would prevent the tail-call JP optimization. */
#ifdef __clang__
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmissing-noreturn"
#endif
void main_relocated(void) __naked
{
    SET_SP(ROM_STACK);
    set_i_reg(INTVEC_PAGE);
    intrinsic_im_2();
    init_pio();
    init_ctc();
    sio_b_debug_init();   /* DEBUG: bring up SIO-B polled output very early */
    init_dma();
    init_crt();
    /* Always program the SEM702 sextant subset.  Real ROA327 ROM
     * silently ignores writes to ports 0xD1/0xD2/0xD3, so the call is
     * a safe no-op on baseline hardware. */
    define_sextants();
    init_fdc();
    memset(dspstr, ' ', 80 * 25);   /* clear screen */
    display_banner_and_start_crt();
    get_floppy_ready();
    // ReSharper disable once CppDFAEndlessLoop
    for (;;);  // halt if ever getting back here.
}
#ifdef __clang__
#pragma clang diagnostic pop
#endif


/* ================================================================
 * 7. Sentinel — placed in code_sentinel section (after all other
 * sections including data_compiler and bss_compiler).
 * payload_size = code_end - intvec + 1.
 * ================================================================ */
#ifdef __SDCC
#pragma constseg code_sentinel
#endif
const byte code_end = 0xFF;
