/*
 * bios.c — RC702 CP/M BIOS in C (REL30)
 *
 * ISRs that switch stacks use __naked wrappers (not __interrupt) because
 * sdcc's __interrupt puts EI at the function START, enabling nested
 * interrupts.  The CRT ISR must run with interrupts disabled to protect
 * DMA programming and the shared sp_sav variable.
 *
 * CONOUT dispatches: escape state
 * (XY addressing), control characters (cursor, scroll, clear), or
 * printable characters (OUTCON conversion, display, advance cursor).
 * BGSTAR (background bitmap): 250-byte position bitmap
 * (1 bit per screen cell). Ctrl-S enters background mode; Ctrl-T
 * returns to foreground; Ctrl-U clears only foreground characters.
 *
 * CONVENTION: __naked shim functions that translate CP/M register-based
 * calling conventions to sdcccall(1) are placed IMMEDIATELY BEFORE their
 * corresponding C body function.  This allows the z88dk peephole
 * optimizer to eliminate the tail call (jp/call) when the body is the
 * next function.  Do not insert other functions between a shim and its
 * body.  Example: bios_list() + bios_list_body(), bios_boot() +
 * bios_boot_c(), bios_linsel() + bios_linsel_body().
 */

// Until Clion is taught about sdcc:
// ReSharper disable CppJoinDeclarationAndAssignment

// ReSharper disable CppDeclaratorNeverUsed
#include <string.h>
#include <intrinsic.h>
#include "hal.h"
#include "bios.h"
#include "builddate.h"

/* Forward declarations */
void bios_conout_c(byte c);
void bios_list_body(byte c);
void bios_punch_body(byte c);
byte bios_reader_body(void);
word bios_seldsk_c(byte drv);
static byte xread(void);
void bios_home(void);

/* ISR forward declarations (needed for IVT array) */
void isr_crt(void) __naked;
void isr_floppy(void) __naked;
void isr_dummy(void) __interrupt(0);
void isr_hd(void) __interrupt(4);
void isr_sio_b_tx(void) __critical __interrupt(8);
void isr_sio_b_ext(void) __critical __interrupt(9);
void isr_sio_b_spec(void) __critical __interrupt(11);
void isr_sio_a_tx(void) __critical __interrupt(12);
void isr_sio_a_ext(void) __critical __interrupt(13);
void isr_sio_a_rx(void) __naked;
void isr_sio_a_spec(void) __critical __interrupt(15);
void isr_pio_kbd(void) __naked;
void isr_pio_par(void) __interrupt(17);

/* ================================================================
 * CONFI configuration block
 *
 * Loaded from disk (Track 0 offset 0x080) by coldboot in boot_entry.c.
 * Copied to 0xD500 (CCP area, valid during init only).
 * bios_hw_init() reads CFG fields to configure CTC, SIO, DMA, CRT, FDC.
 * ================================================================ */

/* ================================================================
 * Disk data tables
 * ================================================================ */

/* Sector translation tables */
const byte tran0[] = {                  /* 8" SS 128 B/S, skew 6 */
    1,7,13,19, 25,5,11,17, 23,3,9,15,
    21,2,8,14, 20,26,6,12, 18,24,4,10, 16,22
};
const byte tran8[] = {                  /* 8" DD 512 B/S, skew 4 */
    1,5,9,13, 2,6,10,14, 3,7,11,15, 4,8,12
};
const byte tran16[] = {                 /* 5.25" DD 512 B/S, skew 2 */
    1,3,5,7, 9,2,4,6, 8
};
const byte tran24[] = {                 /* 8" DD 256 B/S, no translation */
    1,2,3,4, 5,6,7,8, 9,10,11,12,
    13,14,15,16, 17,18,19,20, 21,22,23,24, 25,26
};

/* Disk Parameter Blocks */
const DPB dpb0 = {                      /* 8" SS 128 B/S (IBM standard) */
    26, 3, 7, 0, 242, 63, 192, 0, 16, 2
};
const DPB dpb8 = {                      /* 8" DD 512 B/S (data area) */
    120, 4, 15, 0, 449, 127, 192, 0, 32, 2
};
const DPB dpb16 = {                     /* 5.25" DD 512 B/S */
    26, 3, 7, 0, 242, 63, 192, 0, 16, 0
};
const DPB dpb24 = {                     /* 8" DD 256 B/S (track 0 side 1) */
    104, 4, 15, 0, 471, 127, 192, 0, 32, 0
};

/* Floppy Disk Format descriptors */
const FDF fdf[4] = {
    { 26, 127,  0, 0, 26,  7, 77 },    /* 8" SS 128 B/S (FM) */
    { 30, 511, 64, 2, 15, 27, 77 },    /* 8" DD 512 B/S (MFM) */
    { 26, 127,  0, 0, 26,  7, 77 },    /* 8" SS 128 B/S (T0 S0) */
    { 52, 255, 64, 1, 26, 14, 77 },    /* 8" DD 256 B/S (T0 S1) */
};

/* Floppy System Parameters (16 bytes each) */
const FSPA fspa[4] = {
    { (DPB *)&dpb0,   8,  26, 0, 1, (byte *)tran0,  128, 0, {0} },
    { (DPB *)&dpb8,  16, 120, 3, 3, (byte *)tran8,  255, 0, {0} },
    { (DPB *)&dpb16,  8,  26, 0, 1, (byte *)tran24, 128, 0, {0} },
    { (DPB *)&dpb24,  8, 104, 1, 2, (byte *)tran24, 255, 0, {0} },
};

/* Track offset table (2 floppy drives + 6 reserved for harddisk) */
word trkoff[] = { 2, 2, 0, 0, 0, 0, 0, 0 };

/* ================================================================
 * ISR shared state
 * ================================================================ */

word sp_sav;                  /* saved SP during ISR stack switch */

/* Keyboard ring buffer (REL30) */
static byte kbbuf[KBBUFSZ];
static volatile byte kbhead;   /* write index (ISR updates) */
static volatile byte kbtail;   /* read index (CONIN updates) */
static volatile byte kbstat;   /* 0xFF if buffer non-empty, 0x00 if empty */
static volatile byte cur_dirty; /* non-zero: cursor position needs ISR update */

/* SIO serial ring buffer (REL30)
 * 256-byte page-aligned buffer for SIO Ch.A receiver.
 * Page alignment lets the ISR use H=page, L=index for O(1) addressing.
 * RTS flow control: deassert at RXTHHI used, reassert at RXTHLO used. */
static byte rxbuf[RXBUFSZ];
static volatile byte rxhead;   /* write index (RCA ISR updates) */
static volatile byte rxtail;   /* read index (READER updates) */

/* SIO status flags (0xFF = ready/not busy, 0x00 = busy) */
static volatile byte prtflg = 0xFF;  /* printer (Ch.B TX) ready */
static volatile byte ptpflg = 0xFF;  /* punch (Ch.A TX) ready */

/* SIO status register snapshots */
static volatile byte rr0_a, rr1_a;  /* written by SIO ISRs, read by bios_linsel */
static volatile byte rr0_b, rr1_b;

/* ================================================================
 * Floppy disk driver — variables and buffers
 * ================================================================ */

/* Host sector buffer (512 bytes) and directory scratch (128 bytes) */
static byte hstbuf[512];
byte dirbf[128];

/* Allocation and check vectors (2 drives) */
byte all0[71], chk0[32];
byte all1[71], chk1[32];

/* CP/M requested disk/track/sector (set by BDOS calls) */
static byte  sekdsk;
word sektrk;
word seksec;

/* Host buffer state (what's cached in hstbuf) */
static byte  hstdsk;
static word hsttrk;
static byte hstsec;

/* Last seek position (skip redundant FDC seeks) */
byte  lstdsk;
static word lsttrk;

/* Intermediate: seksec >> secshf */
static byte sekhst;

/* Buffer status */
byte  hstact;     /* 0=empty, 1=valid */
byte  hstwrt;     /* 0=clean, 1=dirty */

/* Unallocated sector tracking */
byte  unacnt;
static byte  unadsk;
static word unatrk;
static word unasec;
static byte  unamsk;

/* I/O operation control */
byte  erflag;
static byte  rsflag;
static byte  readop;
static byte  wrtype;  /* renamed to avoid conflict with WRTYPE macro */

/* DMA and format state */
word dmaadr;         /* CP/M DMA address */
static const FDF *form;  /* pointer to current FDF entry */
byte  cform;   /* current format index */
static byte  eotv;        /* sectors per side on track 0 */
byte  drno;        /* highest drive number */

/* Physical disk control */
static byte  dskno;       /* drive + head select bits */
static word dskad;       /* DMA address for FDC */
static byte  actra;       /* actual track */
static byte  acsec;       /* actual sector (1-based) */
static byte  repet;       /* retry counter */
/* FDC result bytes.  After Read Data / Read ID:
 *   st0, st1, st2, cylinder, head, sector, size_code, (pad)
 * After Sense Drive Status: st0 contains ST3.
 * After Sense Interrupt: st0=ST0, st1=PCN. */
typedef struct {
    byte st0;
    byte st1;
    byte st2;
    byte cylinder;
    byte head;
    byte sector;
    byte size_code;
    byte pad;
} fdc_result_block;

volatile fdc_result_block rstab;           /* FDC result */
static volatile byte fl_flg;      /* floppy completion flag */

/* FSPA working copy (set by SELDSK) */
static DPB *dpblck;      /* DPB pointer (set by SELDSK per format) */
static byte  cpmrbp;      /* records per block */
static word cpmspt;      /* CP/M sectors per track */
static byte  secmsk;      /* sector mask */
static byte  secshf;      /* sector shift count */
static byte *trantb;     /* sector translation table pointer */
static byte  dtlv;        /* data length value */
static byte  dsktyp;      /* 0=floppy, 0xFF=HD */

/* Disk Parameter Headers — one per drive, returned by SELDSK.
 * BSS-zeroed at boot; dpb pointer updated by SELDSK per format. */
DPH dpbase[2];

/* Motor control */
static void fdstop(void)
{
    if (!(port_in(sw1) & 0b10000000))    /* maxi: no motor control */
        return;
    port_out(sw1, 0x00);
}

static void waitd(word ticks)
{
    delcnt = ticks;
    while (delcnt)
        ; // wait for timer to count down (20ms per tick)
}

static void fdstar(void)
{
    if (!(port_in(sw1) & 0b10000000))    /* maxi: no motor control */
        return;
    hal_di();
    if (timer2 == 0) {
        /* motor was stopped — start and wait for spinup */
        timer2 = fdtimo_var;
        hal_ei();
        port_out(sw1, 0x01);
        waitd(50);              /* 50 * 20ms = 1 second */
    } else {
        timer2 = fdtimo_var;
        hal_ei();
    }
}

/* FDC Main Status Register bits:
 *   7: RQM  — Request for Master (1 = ready for CPU access)
 *   6: DIO  — Data direction (0 = CPU→FDC write, 1 = FDC→CPU read)
 *   5: EXM  — Execution mode (1 = in execution phase)
 *   4: CB   — Controller Busy (1 = command in progress)
 *   3-0:    — Drive seek status (D3-D0 busy flags)
 */

/* Wait for FDC ready, then write command/parameter byte (RQM=1, DIO=0) */
void fdc_write(byte val)
{
    while ((port_in(fdc_status) & 0b11000000) != 0b10000000)  /* RQM+DIO mask */
        ;
    port_out(fdc_data, val);
}

/* Wait for FDC result byte available (RQM=1, DIO=1), return data */
static byte fdc_read(void)
{
    while ((port_in(fdc_status) & 0b11000000) != 0b11000000)  /* RQM+DIO mask */
        ;
    return port_in(fdc_data);
}

static void fdc_recalibrate(void)
{
    fdc_write(0x07);            /* RECALIBRATE */
    fdc_write(dskno & 3);      /* drive */
}

static void fdc_sense_int(void)
{
    fdc_write(0x08);            /* SENSE INTERRUPT STATUS */
    rstab.st0 = fdc_read();
    if ((rstab.st0 & 0b11000000) != 0b10000000)
        rstab.st1 = fdc_read();
}

static void fdc_seek(void)
{
    fdc_write(0x0F);            /* SEEK */
    fdc_write(dskno & 3);      /* drive + head */
    fdc_write(actra);          /* cylinder */
}

static void fdc_result(void)
{
    byte *p = (byte *)&rstab;
    byte n = 7;
    do {
        byte delay;
        *p++ = fdc_read();
        for (delay = 4; delay; delay--)
            ;
        if (!(port_in(fdc_status) & 0b00010000))  /* CB: more result bytes? */
            return;
    } while (--n);
}

/* Interrupt flag */
static void clfit(void)
{
    hal_di();
    fl_flg = 0;
    hal_ei();
}

static void watir(void)
{
    while (!fl_flg)
        ;
}

void wfitr(void)
{
    watir();
    clfit();
}

/* DMA setup for FDC transfers (channel 1)
 * CHKTRK sets dskad = HSTBUF address before calling sec_rw.
 * write=1 means FDC reads from memory (FLPR), write=0 means FDC writes to memory (FLPW)
 */
static word dma_count;      /* parameter: byte count for DMA */
static byte  dma_write;      /* parameter: 0=read(FDC→mem), 1=write(mem→FDC) */

static void flp_dma_setup(void)
{
    hal_di();
    port_out(dma_smsk, DMA_MASK_SET(DMA_CH_FLOPPY));
    port_out(dma_mode, dma_write
        ? DMA_MODE_MEM2IO(DMA_CH_FLOPPY)   /* disk write: mem→FDC */
        : DMA_MODE_IO2MEM(DMA_CH_FLOPPY)); /* disk read:  FDC→mem */
    port_out(dma_clbp, 0);
    hal_dma_flp_addr(dskad);
    hal_dma_flp_wc(dma_count);
    port_out(dma_smsk, DMA_MASK_CLR(DMA_CH_FLOPPY));
    hal_ei();
}

/* General FDC command (9-byte read/write sequence)
 * fdfp points past DMA count bytes, at the MF field:
 *   fdfp[0]=MF, fdfp[1]=N, fdfp[2]=EOT, fdfp[3]=gap
 */
static void fdc_general_cmd(byte cmd, const byte *fdfp)
{
    hal_di();
    fdc_write(cmd + fdfp[0]);       /* command + MF flag */
    fdc_write(dskno);              /* drive + head */
    fdc_write(actra);              /* cylinder */
    fdc_write((dskno >> 2) & 3);   /* head number */
    fdc_write(acsec);              /* sector */
    fdc_write(fdfp[1]);            /* N (sector size code) */
    fdc_write(fdfp[2]);            /* EOT (final sector) */
    fdc_write(fdfp[3]);            /* gap length */
    fdc_write(dtlv);               /* data length */
    hal_ei();
}

/* CHKTRK: multi-density track dispatch + sector translation + seek */
static void chktrk(void)
{
    byte sec, ev;
    byte *tp;

    sec = (byte)hstsec;
    ev = eotv;
    dskno = hstdsk;

    if (sec >= ev) {
        /* head 1 (track 0 side 1, or beyond EOTV) */
        dskno |= 4;
        sec -= ev;
    }

    /* sector translation */
    tp = trantb;
    acsec = tp[sec];
    actra = (byte)hsttrk;
    dskad = (word)&hstbuf[0];

    /* check if seek needed */
    if (hstdsk == lstdsk && hsttrk == lsttrk)
        return;

    /* need to seek */
    lstdsk = hstdsk;
    lsttrk = hsttrk;
    clfit();
    fdc_seek();
    wfitr();

    /* check seek completion */
    if (rstab.st0 == ((dskno & 3) | 0b00100000))
        return;

    /* seek failed — recalibrate and retry */
    clfit();
    fdc_recalibrate();
    wfitr();
    fdc_sense_int();
    clfit();
    fdc_seek();
    wfitr();
    fdc_sense_int();
}

/* Forward declaration — definition placed after rdhst for fall-through */
static void sec_rw(byte cmd, byte dma_dir);

/* Write host buffer to disk */
static void wrthst(void)
{
    chktrk();
    sec_rw(5, 1);               /* WRITE DATA, mem→FDC */
}

/* Read host buffer from disk */
static void rdhst(void)
{
    if (unamsk)
        ;                   /* force pre-read if unamsk set */
    else
        unacnt = 0;
    chktrk();
    sec_rw(6, 0);               /* READ DATA, FDC→mem */
}

/* Placed after rdhst so the tail call falls through (saves 3 bytes).
 * Sector read/write with retry.
 * cmd: 6=READ DATA, 5=WRITE DATA.  dma_dir: 0=read(FDC→mem), 1=write(mem→FDC). */
static void sec_rw(byte cmd, byte dma_dir)
{
    static byte s_cmd, s_dma_dir;
    s_cmd = cmd;
    s_dma_dir = dma_dir;
    repet = 10;
    for (;;) {
        fdstar();
        clfit();

        dma_count = form->dma_count;

        dma_write = s_dma_dir;
        flp_dma_setup();
        fdc_general_cmd(s_cmd, (byte *)&form->mf);
        watir();

        if (!(rstab.st0 & 0b11111000))
            return;                     /* success */

        if (rstab.st0 & 0b00001000)            /* write protected — no retry */
            goto fail;

        if (--repet == 0)
            goto fail;

        if (repet == 5) {
            /* recalibrate and retry */
            clfit();
            fdc_recalibrate();
            wfitr();
            fdc_sense_int();
            clfit();
            fdc_seek();
            wfitr();
            fdc_sense_int();
        }
    }
fail:
    hstact = 0;
    erflag = 1;
}


/* Core blocking/deblocking algorithm (DRI standard) */
static byte rwoper(void)
{
    /* compute host sector: sekhst = seksec >> (secshf-1)
     * secshf=3 → 2 shifts (divide by 4, for 512B sectors).
     * secshf=1 → 0 shifts (128B sectors, no deblocking). */
    sekhst = seksec >> (byte)(secshf - 1);

    /* check if host buffer is active and matches */
    if (hstact) {
        if (sekdsk == hstdsk && hsttrk == sektrk && sekhst == hstsec)
            goto match;
        /* not matching — flush if dirty */
        if (hstwrt)
            wrthst();
    }

    /* fill host buffer */
    hstact = 1;
    hstdsk = sekdsk;
    hsttrk = sektrk;
    hstsec = sekhst;
    if (rsflag)
        rdhst();
    hstwrt = 0;

match:
    /* Inline hstbuf offset + dmaadr in each memcpy call rather than storing
     * in static src/dst variables.  sdcc stores statics to memory then
     * immediately reloads them — inlining lets the compiler keep values
     * in registers, saving 10 bytes despite the duplicated expression. */
    if (readop) {
        /* read: copy from host buffer to DMA area */
        memcpy((byte *)dmaadr, &hstbuf[(word)(seksec & secmsk) << 7], 128);
    } else {
        /* write: copy from DMA area to host buffer */
        hstwrt = 1;
        memcpy(&hstbuf[(word)(seksec & secmsk) << 7], (byte *)dmaadr, 128);
    }

    /* post-processing */
    if (erflag) {
        hstact = 0;
    }

    if (wrtype == WRDIR && !erflag) {
        /* directory write: flush immediately */
        hstwrt = 0;
        wrthst();
    }

    {
        byte err = erflag;
        erflag = 0;
        return err;
    }
}


/* bios_hw_init is in bios_hw_init.c (BOOT_CODE section).
 * It runs once at cold boot from unrelocated memory and is
 * overwritten by CCP after boot — saves ~474 bytes of resident BIOS. */

/* ================================================================
 * BIOS entry points
 * ================================================================ */

static void puts_p(const char *s)
{
    while (*s)
        bios_conout_c(*s++);
}


/* Arm SIO Channel A receiver: enable RTS, DTR, TX, and interrupts */
static void readi(void)
{
    hal_di();
    port_out(sio_a_ctrl, 0x05);            /* select WR5 */
    port_out(sio_a_ctrl, wr5a + 0x8A);     /* DTR=1, TX enable, RTS=1 */
    port_out(sio_a_ctrl, 0x01);            /* select WR1 */
    port_out(sio_a_ctrl, 0x1B);            /* enable RX, TX, ext status ints */
    hal_ei();
}

void wboot_c(void);
#ifndef __clang__
static void jump_ccp(byte drive) __naked;
#else
extern void jump_ccp(byte drive);
#endif
void bios_boot_c(void);

/* Cold boot entry — sets BIOS stack then calls bios_boot_c. */
void bios_boot(void) __naked
{
    __asm__("ld sp, #" STR(BIOS_STACK) "\n");       /* use BIOS private stack */
    bios_boot_c();
}

void bios_boot_c(void)
{
    /* Conversion tables (outcon/inconv at 0xF680) are initialized by
     * coldboot from _conv_tables (boot_confi.c) before we get here. */

    /* Set IOBYTE before first console output */
    iobyte = IOBYTE_DEFAULT;

    /* Cold boot: print signon, init state, then warm boot */
    puts_p("\x0C"                       /* form feed = clear screen */
           "RC700 " MSIZE_STR "k CP/M 2.2 C-bios/"
#ifdef __clang__
           "clang "
#else
           "sdcc "
#endif
           BUILDDATE "\r\n");
    /* todo: single block, easy zero */
    cdisk = 0;
    hstact = 0;
    erflag = 0;
    hstwrt = 0;
    kbhead = 0;
    kbtail = 0;
    kbstat = 0;
    rxhead = 0;
    rxtail = 0;
    readi();

    wboot_c();
}

void wboot_c(void)
{
    byte sec;

    hal_ei();
    bios_seldsk_c(0);

    unacnt = 0;
    /* iobyte NOT reset here — preserve STAT CON:=TTY: across warm boots */
    dskno = 0;

    bios_home();

    /* Load CCP+BDOS from track 1 into CCP_BASE */
    dmaadr = CCP_BASE;
    sektrk = 1;

    for (sec = 0; sec < NSECTS; sec++) {
        seksec = sec;
        if (xread()) {
            puts_p("\r\nDisk read error - reset\r\n");
            // ReSharper disable once CppDFAEndlessLoop
            for (;;)
                hal_halt();
        }
        dmaadr += 128;
    }

    dmaadr = BUFF;

    /* Set up JP vectors at page zero */
#ifndef HOST_TEST
    wboot_jp  = 0xC3;                        /* JP opcode */
    bdos_jp   = 0xC3;                        /* JP opcode, here for the peep hole optimizer */
    wboot_vec = BIOS_BASE + 3;              /* WBOOT entry */
    bdos_vec  = BDOS_BASE;

    /* Re-select drive to ensure clean state for CCP */
    bios_seldsk_c(0);

    /* Jump to CCP with current disk in register C */
    jump_ccp(cdisk & 0b00001111);
#endif
}

/* CCP entry point — __at makes the linker resolve the address from
 * the CCP_BASE expression, avoiding a hardcoded hex literal in asm. */
#if defined(__clang__)
#define ccp_entry_point (*(volatile byte *)CCP_BASE)
#else
static volatile byte __at(CCP_BASE) ccp_entry_point;
#endif

/* Jump to CCP entry point — does not return.
 * drive (in A via sdcccall(1)) is moved to C for CP/M convention. */
#ifndef __clang__
static void jump_ccp(byte drive) __naked
{
    (void)drive;
    __asm__("ld c, a               \n"
            "jp _ccp_entry_point   \n");
}
#endif

void bios_wboot(void) __naked
{
    __asm__("ld sp, #" STR(BIOS_STACK) " \n"  /* use BIOS private stack */
            "jp _wboot_c          \n");
}

/* ----------------------------------------------------------------
 * Console I/O — IOBYTE-redirectable (CP/M 2.2 Table 6-4)
 *
 * CON: field (bits 1:0):
 *   0=TTY: SIO-A serial   1=CRT: keyboard+display
 *   2=BAT: RDR→in,LST→out 3=UC1: parked
 * ---------------------------------------------------------------- */

/* Serial (SIO-A) console primitives for IOBYTE TTY: mode */
static byte serial_const(void) {
    return (rxtail != rxhead) ? 0xFF : 0x00;
}
static byte serial_conin(void) {
    /* Ensure RTS is asserted so host can send.  RTS may be de-asserted
     * if the RCA ISR throttled a previous burst.  bios_reader_body only
     * reasserts when the buffer drains to empty, but if we're called
     * with an empty buffer and RTS=0 (e.g. after warm boot), we'd block
     * forever.  readi() unconditionally arms RTS + receiver interrupts. */
    if (rxtail == rxhead)
        readi();
    return bios_reader_body();
}
static void serial_conout(byte c) {
    /* Non-blocking: if SIO-A TX not ready (e.g. no host connected,
     * CTS deasserted), skip.  CRT echo still shows the character. */
    byte timeout = 255;
    while (!ptpflg && --timeout)
        ;
    if (!timeout) return;
    bios_punch_body(c);
}

byte bios_const(void)
{
    switch (IOBYTE_CON(iobyte)) {
    case IOB_TTY:  return serial_const();
    case IOB_CRT:  return kbstat;
    case IOB_BAT:  return serial_const();
    default:       return 0;
    }
}

byte bios_conin(void)
{
    switch (IOBYTE_CON(iobyte)) {
    case IOB_TTY:  return serial_conin();
    case IOB_CRT: {
        while (kbtail == kbhead)
            hal_halt();
        byte raw = kbbuf[kbtail];
        kbtail = (kbtail + 1) & (KBBUFSZ - 1);
        kbstat = (kbtail != kbhead) ? 0xFF : 0x00;
        return inconv[raw];
    }
    case IOB_BAT:  return serial_conin();
    default:       return 0x1A;
    }
}

/* ================================================================
 * Display driver — CONOUT with escape sequences
 *
 * Implements the RC702 display protocol: control characters 0x00-0x1F
 * dispatch via jump table, ESC = X Y for cursor addressing, printable
 * characters go through OUTCON conversion table to display memory.
 *
 * BGSTAR: 250-byte bitmap, one bit per screen cell (80×25/8).
 * Ctrl-S (0x13) enters background mode, marking each written position.
 * Ctrl-T (0x14) returns to foreground mode.
 * Ctrl-U (0x15) clears foreground: erases only positions NOT marked.
 * ================================================================ */

#define BGSTAR_SIZE 250         /* 80*25/8 = 250 bytes */
#define BG_ROW_BYTES 10         /* 80 bits / 8 = 10 bytes per row */

static byte bgstar[BGSTAR_SIZE];
static byte bgflg;             /* 0=off, 1=foreground, 2=background */
static byte graph;           /* graphical mode flag (sticky) */

/* Forward declarations — definitions placed for tail-call fall-through */
static void cursor_right(void);
static inline void cursorxy(void);

/* Reset cursor to top-left (does NOT update 8275) */
static void goto00(void);

/* Start XY addressing: set xflg and reset cursor.
 * Placed immediately before goto00 so the tail call falls through. */
static void start_xy(void)
{
    xflg = 2;
    goto00();
}

/* Placed after start_xy so the tail call falls through (saves 3 bytes) */
static void goto00(void)
{
    cury = 0;
    curx = 0;
    cursy = 0;
}

/* Forward declaration — definition placed after cursor_down for fall-through */
static void rowdn(void);

/* Move cursor up one row */
static void rowup(void)
{
    cury -= SCRN_COLS;
    cursy--;
    cursorxy();
}

/* Set a bit in BGSTAR for screen position `pos` (0-1999) */
static void bg_set_bit(word pos)
{
    static byte byteoff;
    byteoff = (byte)(pos >> 3);
    bgstar[byteoff] |= (byte)0x80 >> (byte)(pos & 7);
}

/* ======================================================================
 * SCROLL — performance-critical, hand-optimized in assembly.
 *
 * Scroll display up one line: copy ROW1..ROW24 → ROW0..ROW23, fill ROW24.
 *
 * OPTIMIZATION: Unrolled 16×LDI loop (16T/byte vs LDIR's 21T/byte).
 * Same technique as the REL30 assembly BIOS (see rcbios/src/DISPLAY.MAC).
 * 1920 bytes / 16 = 120 exact iterations, no remainder.
 *
 * Saves ~9,600 T-states per scroll call.  During TYPE FILEX.PRN (~1000
 * scrolls) this recovers ~10M cycles ≈ 5% of total execution time,
 * closing the gap between the C BIOS and the original assembly BIOS.
 *
 * The ROW24 fill uses the LDIR fill trick (write first byte, LDIR the
 * rest) instead of a DJNZ byte loop — saves another ~630T per scroll.
 * ====================================================================== */
static void scroll(void)
{
    /* --- display memory scroll --- */
#if defined(__SDCC) || defined(__SCCZ80)
    /* Inline asm: unrolled 16xLDI for speed (16T/byte vs 21T/byte LDIR) */
    __asm
    ld  hl, #0xF850         ; source = DSPSTR + 80
    ld  de, #0xF800         ; dest   = DSPSTR
    ld  bc, #0x0780         ; count  = 1920
scroll_ldi:
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    jp  PE, scroll_ldi      ; P/V set while BC > 0
    ld  hl, #0xFF80         ; ROW24 = DSPSTR + 1920
    ld  (hl), #0x20         ; first byte = space
    ld  d, h
    ld  e, l
    inc de
    ld  bc, #79             ; remaining 79 bytes
    ldir
    __endasm;
#else
    /* 16x LDI unroll: 20% faster than LDIR (16T/byte vs 21T/byte) */
    memcpy_z80((void *)0xF800, (void *)0xF850, 1920, 0);  /* 1920/16*16=1920, 1920%16=0 */
    memset((void *)0xFF80, 0x20, 80);
#endif

    /* --- bgstar overlay: C code (not performance-critical) --- */
    if (bgflg) {
        memcpy(bgstar, bgstar + BG_ROW_BYTES, BGSTAR_SIZE - BG_ROW_BYTES);
        memset(bgstar + BGSTAR_SIZE - BG_ROW_BYTES, 0, BG_ROW_BYTES);
    }
}

/* Cursor left — wrap to previous line if at column 0 */
static void cursor_left(void)
{
    if (curx != COLUMN0) {
        curx--;
        cursorxy();
    } else {
        curx = COLUMN79;
        if (cury != ROW0_OFF) {
            rowup();
        } else {
            cury = ROW24_OFFSET;
            cursy = ROW24;
            cursorxy();
        }
    }
}

/* Cursor down — scroll if on last row */
static void cursor_down(void)
{
    if (cury != ROW24_OFFSET)
        rowdn();
    else
        scroll();
}

/* Placed after cursor_down so the tail call falls through */
static void rowdn(void)
{
    cury += SCRN_COLS;
    cursy++;
    cursorxy();
}

/* Cursor up — wrap to bottom if on first row */
static void cursor_up(void)
{
    if (cury != ROW0_OFF) {
        rowup();
    } else {
        cury = ROW24_OFFSET;
        cursy = ROW24;
        cursorxy();
    }
}

/* Carriage return — column 0, update cursor */
static void carriage_return(void)
{
    curx = COLUMN0;
    cursorxy();
}

/* Single byte-store — always inline to avoid CALL/RET overhead (4B per site). */
static inline void cursorxy(void)
{
    cur_dirty = 1;              /* deferred to isr_crt for speed */
}

/* Tab — 4 cursor rights */
static void tab(void)
{
    cursor_right();
    cursor_right();
    cursor_right();
    cursor_right();
}

/* Home — top-left + update cursor */
static void home(void)
{
    goto00();
    cursorxy();
}

/* Clear screen — fill display with spaces, home */
static void clear_screen(void)
{
    memset(screen, ' ', SCRN_SIZE);
    goto00();
    cursorxy();
    if (bgflg) {
        bgflg = 0;
        memset(bgstar, 0, BGSTAR_SIZE);
    }
}

/* Forward declaration — definition placed after erase_to_eos for fall-through */
static word bgcl_pos, bgcl_count;
static void bg_clear_from(void);

/* Erase from cursor to end of line */
static void erase_to_eol(void)
{
    byte *row = screen + cury;
    for (byte i = curx; i < SCRN_COLS; i++)
        row[i] = ' ';
    if (bgflg) {
        bgcl_pos = cury + curx;
        bgcl_count = SCRN_COLS - curx;
        bg_clear_from();
    }
}

/* Erase from cursor to end of screen */
static void erase_to_eos(void)
{
    static word pos;
    static word count;
    pos = cury + curx;
    count = SCRN_SIZE - pos;
    memset(screen + pos, ' ', count);
    if (bgflg) {
        bgcl_pos = pos;
        bgcl_count = SCRN_SIZE - pos;
        bg_clear_from();
    }
}

/* Placed after erase_to_eos so the tail call falls through (saves 3 bytes).
 * Clear BGSTAR bits from position `pos` for `count` bits.
 * Parameters passed via static variables to avoid IX frame pointer. */
static void bg_clear_from(void)
{
    static byte byteoff, bitno, whole, tail;
    if (!bgflg)
        return;
    byteoff = (byte)(bgcl_pos >> 3);
    bitno = (byte)(bgcl_pos & 7);
    /* Clear remaining bits in the first byte */
    if (bitno) {
        bgstar[byteoff] &= ~((byte)0xFF >> bitno);
        byteoff++;
        bgcl_count = (bgcl_count > (byte)(8 - bitno)) ? bgcl_count - (8 - bitno) : 0;
    }
    /* Clear whole bytes */
    whole = (byte)(bgcl_count >> 3);
    if (whole) {
        memset(bgstar + byteoff, 0, whole);
        byteoff += whole;
    }
    /* Clear leading bits of last byte */
    tail = (byte)(bgcl_count & 7);
    if (tail) {
        bgstar[byteoff] &= ~((byte)0xFF << (byte)(8 - tail));
    }
}

/* Delete line — shift lines up from cury+1 to ROW24, fill ROW24 */
static void delete_line(void)
{
    /* Inline expressions rather than static temps — avoids store/reload overhead */
    if (cury != ROW24_OFFSET)
        memcpy(screen + cury, screen + cury + SCRN_COLS, ROW24_OFFSET - cury);
    memset(DISPLAY_ROW(ROW24), ' ', SCRN_COLS);
    if (bgflg) {
        static byte dl_off, dl_bgcount;
        dl_off = (byte)(cury >> 3);  /* cury is row*80, /8 = row*10 */
        dl_bgcount = BGSTAR_SIZE - BG_ROW_BYTES - dl_off;
        if (dl_bgcount)
            memcpy(bgstar + dl_off, bgstar + dl_off + BG_ROW_BYTES, dl_bgcount);
        memset(bgstar + BGSTAR_SIZE - BG_ROW_BYTES, 0, BG_ROW_BYTES);
    }
}

/* Insert line — shift lines down from cury to ROW23, fill current line.
 * Backward copies use lddr_copy (HL=src_end, DE=dst_end → LDDR). */
static void insert_line(void)
{
    static word count;

    count = ROW24_OFFSET - cury;
    if (count != 0) {
#if defined(__SDCC) || defined(__SCCZ80)
        /* Backward copy for overlapping shift-down (memmove hangs on z88dk) */
        static byte *src, *dst;
        static byte il_i;
        src = screen + ROW24_OFFSET - 1;
        dst = screen + ROW24_OFFSET + SCRN_COLS - 1;
        il_i = (byte)count;
        while (il_i--)
            *dst-- = *src--;
#else
        lddr_copy(screen + ROW24_OFFSET - 1,
                  screen + ROW24_OFFSET + SCRN_COLS - 1,
                  count);
#endif
    }
    memset(screen + cury, ' ', SCRN_COLS);
    if (bgflg) {
        static byte il_off, il_bgcount;
        il_off = (byte)(cury >> 3);
        il_bgcount = BGSTAR_SIZE - BG_ROW_BYTES - il_off;
        if (il_bgcount) {
#if defined(__SDCC) || defined(__SCCZ80)
            static byte *il_src, *il_dst;
            static byte il_j;
            il_src = bgstar + BGSTAR_SIZE - BG_ROW_BYTES - 1;
            il_dst = bgstar + BGSTAR_SIZE - 1;
            il_j = il_bgcount;
            while (il_j--)
                *il_dst-- = *il_src--;
#else
            lddr_copy(bgstar + BGSTAR_SIZE - BG_ROW_BYTES - 1,
                      bgstar + BGSTAR_SIZE - 1,
                      il_bgcount);
#endif
        }
        memset(bgstar + il_off, 0, BG_ROW_BYTES);
    }
}

/* XY cursor addressing — called for each byte after ctrl-F */
static void xyadd(void)
{
    byte val = (usession & 0b01111111) - 32;
    xflg--;
    if (xflg != 0) {
        adr0 = val;             /* save first coordinate */
        return;
    }
    /* Second byte: compute final position */
    byte x_val, y_val;
    if (adrmod == 0) {
        x_val = adr0;           /* XY mode: first=X, second=Y */
        y_val = val;
    } else {
        x_val = val;            /* YX mode: first=Y, second=X */
        y_val = adr0;
    }
    /* Modular arithmetic (matches original CHKDC) */
    while (x_val >= SCRN_COLS) x_val -= SCRN_COLS;
    while (y_val >= SCRN_ROWS) y_val -= SCRN_ROWS;
    curx = x_val;
    cursy = y_val;
    cury = (word)y_val * SCRN_COLS;
    cursorxy();
}

/* Display printable character — convert, write, advance cursor */
static void displ(void)
{
    byte ch = usession;

    locad = cury + curx;

    /* 8275 CRT character encoding:
     * 192-255: fold to 0-63 (character ROM uses 7 address bits)
     * 128-191: semigraphics control — bit 2 sets/clears sticky graph mode
     * 0-127:   normal chars, through OUTCON unless graph mode is active */
    if (ch >= 192)
        ch -= 192;

    if (ch >= 128) {
        graph = ch & 4;         /* set/clear semigraphics mode (sticky) */
    } else if (!graph) {
        ch = outcon[ch];  /* national character conversion (CONFI.COM) */
    }

    screen[locad] = ch;
    if (bgflg == 2)
        bg_set_bit(locad);
    cursor_right();
}

/* Cursor right — advance column, wrap to next line or scroll.
 * Placed immediately after displ() so the tail call can fall through. */
static void cursor_right(void)
{
    if (curx < COLUMN79) {
        curx++;
        cursorxy();
    } else {
        curx = COLUMN0;
        if (cury != ROW24_OFFSET) {
            rowdn();
        } else {
            cursorxy();
            scroll();
        }
    }
}

/* Clear foreground: erase screen positions where BGSTAR bit is NOT set */
static void clear_foreground(void)
{
    static byte i;
    static byte *p;
    static byte bits, mask;
    p = screen;
    for (i = 0; i < BGSTAR_SIZE; i++) {
        bits = bgstar[i];
        mask = 0x80;
        while (mask) {
            if (!(bits & mask))
                *p = ' ';
            p++;
            mask >>= 1;
        }
    }
}

/* Control character dispatch (0x00-0x1F).
 * Uses if/return chains so sdcc generates cp a,N (preserving A) with
 * tail-call jp for each handler.  Ordered by frequency: CR and LF
 * first, then common cursor/editing, then rare screen ops and BGSTAR. */
static void specc(void)
{
    xflg = 0;
    /* Most frequent: every line of output */
    if (usession == 0x0D) { carriage_return(); return; }
    if (usession == 0x0A) { cursor_down(); return; }
    if (usession == 0x06) { start_xy(); return; }  /* XY addressing */
    /* Common: cursor movement, editing */
    if (usession == 0x08) { cursor_left(); return; }
    if (usession == 0x05) { cursor_left(); return; }  /* ENQ = BS */
    if (usession == 0x09) { tab(); return; }
    if (usession == 0x18) { cursor_right(); return; }
    if (usession == 0x1A) { cursor_up(); return; }
    /* Less common: screen operations */
    if (usession == 0x0C) { clear_screen(); return; }
    if (usession == 0x1D) { home(); return; }
    if (usession == 0x1E) { erase_to_eol(); return; }
    if (usession == 0x1F) { erase_to_eos(); return; }
    if (usession == 0x01) { insert_line(); return; }
    if (usession == 0x02) { delete_line(); return; }
    if (usession == 0x07) { port_out(bell, 0); return; }
    /* Rare: fore/background */
    if (usession == 0x13) { bgflg = 2; memset(bgstar, 0, BGSTAR_SIZE); return; }
    if (usession == 0x14) { bgflg = 1; return; }
    if (usession == 0x15) { clear_foreground(); return; }
}

/*
 * CONOUT entry point — CP/M ABI shim
 *
 * CP/M passes character in C register; sdcccall(1) expects it in A.
 * This __naked shim does `ld a, c` then falls through to bios_conout_c.
 * The compiler saves/restores all registers it clobbers, satisfying
 * the CP/M ABI requirement that BIOS calls preserve all registers.
 * No stack switch needed — CONOUT uses at most 16 bytes of stack.
 */
void bios_conout(byte c) __naked
{
    (void)c;
    __asm__("ld a, c               \n"
            "jp _bios_conout_c     \n"); /* explicit tail call */
}

void bios_conout_c(byte c)
{
    switch (IOBYTE_CON(iobyte)) {
    case IOB_TTY:
        serial_conout(c);
        /* fall through to also display on CRT */
    case IOB_CRT:
        usession = c;
        if (xflg != 0) xyadd();
        else if (usession < 32) specc();
        else displ();
        break;
    case IOB_BAT:
        bios_list_body(c);
        break;
    default:
        break;
    }
}

/* LIST: transmit character on SIO Channel B (printer).
 * CP/M passes char in C register; sdcccall(1) expects A.
 * __naked shim translates, then falls through to body. */
void bios_list(void) __naked
{
    __asm__("ld a, c               \n"
            "jp _bios_list_body    \n"); /* explicit tail call */
}

static void list_lpt(byte c)
{
    while (!prtflg)
        ;                       /* wait for TX ready */
    hal_di();
    prtflg = 0;                 /* mark busy */
    port_out(sio_b_ctrl, 0x05);    /* select WR5 */
    port_out(sio_b_ctrl, wr5b + 0x8A);  /* DTR=1, TX enable, RTS=1 */
    port_out(sio_b_ctrl, 0x01);    /* select WR1 */
    port_out(sio_b_ctrl, 0x07);    /* TX int, ext status, status affects vector */
    port_out(sio_b_data, c);
    hal_ei();
}

void bios_list_body(byte c)
{
    switch (IOBYTE_LST(iobyte)) {
    case IOB_TTY:  serial_conout(c); break;
    case IOB_CRT:  bios_conout_c(c); break;
    case IOB_BAT:  list_lpt(c);      break;  /* LPT: SIO-B */
    default:       break;
    }
}

/* PUNCH: transmit character on SIO Channel A (serial).
 * CP/M passes char in C; sdcccall(1) expects A.
 * HL preserved for SNIOS (CP/NET). */
void bios_punch(void) __naked
{
    __asm__("push hl     \n"
            "ld a, c     \n"
            "call _bios_punch_body \n"
            "pop hl      \n"
            "ret         \n");
}

void bios_punch_body(byte c)
{
    byte pun = IOBYTE_PUN(iobyte);
    if (pun >= IOB_BAT) return;     /* UP1/UP2: parked */

    while (!ptpflg)
        ;                       /* wait for TX ready */
    hal_di();
    ptpflg = 0;                 /* mark busy */
    port_out(sio_a_ctrl, 0x05);    /* select WR5 */
    port_out(sio_a_ctrl, wr5a + 0x8A);  /* DTR=1, TX enable, RTS=1 */
    port_out(sio_a_ctrl, 0x01);    /* select WR1 */
    port_out(sio_a_ctrl, 0x1B);    /* RX, TX, ext status ints */
    port_out(sio_a_data, c);
    hal_ei();
}

/* READER: read character from SIO Channel A ring buffer with RTS flow control.
 * CP/M expects return in A; also copies to C.
 * HL preserved for SNIOS (CP/NET). */
void bios_reader(void) __naked
{
    __asm__("push hl     \n"
            "call _bios_reader_body \n"
            "pop hl      \n"
            "ld c, a     \n"
            "ret         \n");
}

byte bios_reader_body(void)
{
    byte rdr = IOBYTE_RDR(iobyte);
    if (rdr >= IOB_BAT) return 0x1A;    /* UR1/UR2: parked, return EOF */

    byte ch, new_tail;

    /* wait for data in ring buffer */
    while (rxtail == rxhead)
        ;

    /* read character and advance tail */
    new_tail = (rxtail + 1) & RXMASK;
    ch = rxbuf[rxtail];
    rxtail = new_tail;

    /* reassert RTS only when buffer is empty — ensures the sender
     * pauses long enough for PIP to complete disk writes */
    if (new_tail == rxhead) {
        port_out(sio_a_ctrl, 0x05);        /* select WR5 */
        port_out(sio_a_ctrl, wr5a + 0x8A); /* DTR=1, TX enable, RTS=1 */
    }

    return ch;
}

/* READS (DA4D): Reader status.
 * Returns: A=0xFF if character available, A=0x00 if empty.
 * HL preserved for SNIOS (CP/NET). */
void bios_reads(void) __naked
{
    __asm__("push hl     \n"
            "call _bios_reads_body \n"
            "pop hl      \n"
            "ld c, a     \n"
            "ret         \n");
}

byte bios_reads_body(void)
{
    byte rdr = IOBYTE_RDR(iobyte);
    if (rdr >= IOB_BAT) return 0;       /* UR1/UR2: parked */
    return (rxtail != rxhead) ? 0xFF : 0x00;
}

void bios_home(void)
{
    if (hstwrt) {
        wrthst();
    } else {
        hstact = 0;
    }
    fdstar();
    dskno = sekdsk;
    lstdsk = sekdsk;
    lsttrk = 0;
    clfit();
    fdc_recalibrate();
    wfitr();
}

/* CP/M passes drive in C register, expects DPH in HL.
 * sdcccall(1) returns word in DE, CP/M expects HL. */
word bios_seldsk(byte disk) __naked
{
    (void)disk;
    __asm__("ld a, c               \n"
            "call _bios_seldsk_c   \n"
            "ex de, hl             \n"
            "ret                   \n");
#ifdef __clang__
    return 0; /* unreachable — silences clang -Wreturn-type */
#endif
}

word bios_seldsk_c(byte drv)
{
    static byte drive;
    static byte fmt;

    drive = drv;
    if (drive > drno)
        return 0;               /* invalid drive */

    sekdsk = drive;

    /* look up format from fd0 table */
    fmt = fd0[drive];

    /* if format changed, flush dirty buffer */
    if (fmt != cform) {
        if (hstwrt) {
            wrthst();
            hstwrt = 0;
        }
    }

    cform = fmt;

    /* get format descriptor (FDF) and system parameters (FSPA) */
    {
        static byte idx;
        static const FSPA *sp;
        idx = (fmt >> 3) & 3;
        sp = &fspa[idx];

        form = &fdf[idx];
        eotv = form->eot;

        /* copy FSPA format parameters to working area */
        dpblck = sp->dpb;
        cpmrbp = sp->cpmrbp;
        cpmspt = sp->cpmspt;
        secmsk = sp->secmsk;
        secshf = sp->secshf;
        trantb = sp->trantb;
        dtlv = sp->dtlv;
        dsktyp = sp->dsktyp;
    }

    /* update DPB pointer in DPH and return DPH address to BDOS */
    {
        static DPH *dph;
        dph = &dpbase[drive];
        dph->dpb = dpblck;
        return (word)dph;
    }
}

void bios_settrk(word track) __naked
{
    (void)track;
    __asm__("ld (_sektrk), bc       \n"  /* CP/M passes track in BC */
            "ret                     \n");
}

void bios_setsec(word sector) __naked
{
    (void)sector;
    __asm__("ld (_seksec), bc       \n"  /* CP/M passes sector in BC */
            "ret                     \n");
}

void bios_setdma(word addr) __naked
{
    (void)addr;
    __asm__("ld (_dmaadr), bc       \n"  /* CP/M passes DMA address in BC */
            "ret                     \n");
}

static byte xread(void)
{
    unacnt = 0;
    readop = 1;
    rsflag = 1;
    wrtype = WRUAL;
    return rwoper();
}

static byte xwrite(byte wt)
{
    readop = 0;
    wrtype = wt;

    if (wt == WRUAL) {
        /* first write to unallocated block */
        unacnt = cpmrbp;
        unadsk = sekdsk;
        unatrk = sektrk;
        unasec = seksec;
    }

    /* check for continuation of unallocated writes */
    if (unacnt) {
        unacnt--;
        if (sekdsk != unadsk || sektrk != unatrk || seksec != unasec)
            goto alloc;

        /* match — advance unalloc pointer */
        unasec++;
        if (unasec >= cpmspt) {
            unasec = 0;
            unatrk++;
        }

        /* check if pre-read needed */
        rsflag = 0;
        if ((seksec & secmsk) == secmsk)
            unamsk = 1;
        else
            unamsk = 0;
        return rwoper();
    }

alloc:
    unacnt = 0;
    rsflag = secmsk;
    return rwoper();
}

byte bios_read(void)
{
    return xread();
}

/* CP/M passes write type in C register */
byte bios_write(byte type) __naked
{
    (void)type;
    __asm__("ld a, c               \n"
            "jp _bios_write_c      \n"); /* explicit tail call */
#ifdef __clang__
    return 0; /* unreachable — silences clang -Wreturn-type */
#endif
}

byte bios_write_c(byte wt)
{
    return xwrite(wt);
}

byte bios_listst(void)
{
    switch (IOBYTE_LST(iobyte)) {
    case IOB_TTY:  return ptpflg;   /* SIO-A TX ready */
    case IOB_CRT:  return 0xFF;     /* CRT always ready */
    case IOB_BAT:  return prtflg;   /* LPT: SIO-B TX ready */
    default:       return 0;        /* UL1: parked */
    }
}

word bios_sectran(word sector) __naked
{
    (void)sector;
    __asm__("ld h, b                \n"  /* return BC in HL (no translation) */
            "ld l, c                \n"
            "ret                    \n");
#ifdef __clang__
    return 0; /* unreachable — silences clang -Wreturn-type */
#endif
}

/* ================================================================
 * Extended BIOS entries (DA4A+)
 *
 * RC700-specific extensions beyond the standard CP/M 2.2 BIOS.
 * Documented in CP/M User's Guide section 4.4 "Extended BIOS Functions".
 * These use register-based calling conventions that differ from
 * sdcccall(1), so most need __naked wrappers with inline asm.
 *
 *   DA4A  JP WFITR    Wait for FDC interrupt, return result
 *   DA4D  JP READS    Reader status (0xFF=data, 0=empty)
 *   DA50  JP LINSEL   RC791 line selector control
 *   DA53  JP EXIT     Register application timeout callback
 *   DA56  JP CLOCK    Read/set 32-bit real-time clock
 *   DA59  JP HRDFMT   Format hard disk track (stub)
 * ================================================================ */

/* WFITR (DA4A): PROCEDURE WAIT_CLEAR_FD_INTERRUPT
 * Waits for FDC interrupt flag, then returns result status.
 * Returns: B=ST0 (rstab.st0), C=ST1 (rstab.st1).
 * Used by FORMAT.COM (RC700 FORMAT UTILITY VERS 1.2). */
void bios_wfitr(void) __naked
{
    wfitr();
    __asm__("ld a, (_rstab)         \n"
            "ld b, a                \n"
            "ld a, (_rstab + 1)     \n"
            "ld c, a                \n"
            "ret                    \n");
}

/* LINSEL (DA50): PROCEDURE LINE_SELECT
 * Controls the RC791 Line Selector (Linieselektor), a V.24 multiplexer
 * that routes 8 V.24 inputs to 2 outputs.
 *
 * Input:  A = port (0=terminal SIO-A, 1=printer SIO-B)
 *         B = line (0=release, 1=select line A, 2=select line B)
 *         C = irrelevant
 * Returns: A = 0xFF if selection OK (CTS active)
 *          A = 0x00 if line busy (CTS not active, line released)
 *
 * Protocol (from original source):
 *   1. Wait for all-sent (RR1 bit 0)
 *   2. Delay between line release and new select
 *   3. DTR:=FALSE; RTS:=FALSE
 *   4. IF B<>0 THEN
 *        DTR:=FALSE; RTS:=(B=2)    (* wait at least 100 ns *)
 *        DTR:=TRUE                 (* wait 1-2 timer periods *)
 *        IF CTS THEN A:=0FFH
 *        ELSE A:=0; DTR:=FALSE; RTS:=FALSE
 *
 * The original asm uses OUT (C),r with a variable port in the C register.
 * This C version uses two code paths (SIO-A / SIO-B) with fixed ports. */

/* SIO WR5 access via fixed ports (two code paths for A/B) */
byte ls_port;           /* 0=SIO-A, 1=SIO-B */

/* noinline per-channel: address_space(2) PHI crash workaround (ravn/llvm-z80#44).
 * Inlining merges port pointers across branches → Legalizer crash.
 * SDCC doesn't need noinline — it doesn't merge address_space pointers. */
#ifdef __clang__
#define NOINLINE __attribute__((noinline))
#else
#define NOINLINE
#endif
static void NOINLINE sio_a_wr5(byte v) { port_out(sio_a_ctrl, 5); port_out(sio_a_ctrl, v); }
static void NOINLINE sio_b_wr5(byte v) { port_out(sio_b_ctrl, 5); port_out(sio_b_ctrl, v); }
static void sio_wr5(byte val) { if (ls_port) sio_b_wr5(val); else sio_a_wr5(val); }

static byte NOINLINE sio_a_rd1(void) { port_out(sio_a_ctrl, 1); return port_in(sio_a_ctrl); }
static byte NOINLINE sio_b_rd1(void) { port_out(sio_b_ctrl, 1); return port_in(sio_b_ctrl); }
static byte sio_rd1(void) { return ls_port ? sio_b_rd1() : sio_a_rd1(); }
#undef NOINLINE

byte ls_line;

/* LINSEL entry: extract A=port, B=line from CP/M registers,
 * then call C body.  Returns result in A (0=no CTS, 0xFF=CTS). */
byte bios_linsel_body(void);
void bios_linsel(void) __naked
{
    __asm__("ld (_ls_port), a       \n"  /* A=port (0=SIO-A, 1=SIO-B) */
            "ld a, b                \n"
            "ld (_ls_line), a       \n"); /* B=line (0-2) */
    bios_linsel_body();
    /* sdcccall(1) returns byte in A — correct for CP/M */
}

byte bios_linsel_body(void)
{
    /* Wait for all-sent (RR1 bit 0) */
    while (!(sio_rd1() & 0b00000001))
        ;

    waitd(2);

    /* Release: DTR=0, RTS=0 */
    hal_di();
    sio_wr5(0x00);
    hal_ei();

    if (ls_line == 0)
        return 0;

    /* Select line: line=1→DTR only, line=2→DTR+RTS */
    {
        byte wr5val;
        wr5val = (byte)(ls_line << 1);      /* RTS bit position */
        hal_di();
        sio_wr5(wr5val);
        hal_ei();
        wr5val |= 0b10000000;                     /* add DTR */
        hal_di();
        sio_wr5(wr5val);
        hal_ei();
    }

    waitd(2);

    /* Check CTS (RR0 bit 5) — cached by ISR */
    if ((ls_port ? rr0_b : rr0_a) & 0b00100000)
        return 0xFF;

    /* No CTS — release line */
    hal_di();
    sio_wr5(0x00);
    hal_ei();
    return 0;
}

/* EXIT (DA53): PROCEDURE DEF_EXIT_ROUTINE
 * Registers an application timeout callback.
 * Input: HL = callback routine address
 *        DE = countdown in 20ms ticks
 * The CRT ISR decrements the counter every 20ms; when it reaches zero,
 * the callback at HL is invoked with interrupts disabled.
 * The callback must NOT enable interrupts and must return via RET. */
void bios_exit(void) __naked
{
    __asm__("ld (" STR(WARMJP_ADDR) "), hl \n"  /* warmjp = callback address */
            "ex de, hl                   \n"
            "ld (" STR(TIMER1_ADDR) "), hl \n" /* timer1 = countdown */
            "ret                         \n");
}

/* CLOCK (DA56): PROCEDURE CLOCK
 * Reads or sets the 32-bit real-time clock (incremented every 20ms
 * by the CRT ISR, stored at 0xFFFC-0xFFFF).
 * Input:  A=0  → SET clock from DE (low word) and HL (high word)
 *         A≠0  → GET clock
 * Returns (GET): DE = clock bits 0-15, HL = clock bits 16-31 */
void bios_clock(void) __naked
{
    __asm__("or a                   \n"
            "jr z, _clock_set       \n"
            "di                     \n"  /* read clock */
            "ld de, (" STR(RTC0_ADDR) ") \n"
            "ld hl, (" STR(RTC2_ADDR) ") \n"
            "ei                     \n"
            "ret                    \n"
            "_clock_set:            \n"
            "ld (" STR(RTC0_ADDR) "), de \n"  /* set clock */
            "ld (" STR(RTC2_ADDR) "), hl \n"
            "ret                    \n");
}

/* HRDFMT (DA59): Format hard disk track (WD1000 controller).
 * Input: A=size/drive/head, B=write precomp, C=sector count,
 *        DE=cylinder, DMAADR→format spec data.
 * Returns: A=0 success, A=1 error.
 * TODO(harddisk): Postponed until BIOS fits on mini (5.25") disk. */
void bios_hrdfmt(void) { }

/* ================================================================
 * Interrupt service routines
 *
 * CRITICAL: __interrupt(N) must ALWAYS include the (N) number.
 * Without it, __critical __interrupt generates RETN instead of
 * EI+RETI, leaving interrupts permanently disabled — fatal on
 * the RC702 where all I/O is interrupt-driven.
 *
 * The RC702 requires interrupts disabled in ALL interrupt handlers.
 * Nested interrupts are never safe on this hardware.
 *
 * The (N) numbers match the IVT index in bios.c (_itrtab):
 *   0-1  CTC1 ch0-1: isr_dummy          (__interrupt, baud rate)
 *   2    CTC1 ch2: isr_crt            (__naked)
 *   3    CTC1 ch3: isr_floppy         (__naked)
 *   4    CTC2 ch0: isr_hd             (__interrupt)
 *   5-7  CTC2 ch1-3: isr_dummy          (__interrupt, unused)
 *   8    SIO ch.B TX: isr_sio_b_tx    (__critical __interrupt)
 *   9    SIO ch.B ext: isr_sio_b_ext  (__critical __interrupt)
 *  10    SIO ch.B RX: isr_dummy          (__interrupt, RX disabled)
 *  11    SIO ch.B spec: isr_sio_b_spec(__critical __interrupt)
 *  12    SIO ch.A TX: isr_sio_a_tx    (__critical __interrupt)
 *  13    SIO ch.A ext: isr_sio_a_ext  (__critical __interrupt)
 *  14    SIO ch.A RX: isr_sio_a_rx    (__naked)
 *  15    SIO ch.A spec: isr_sio_a_spec(__critical __interrupt)
 *  16    PIO ch.A: isr_pio_kbd        (__naked)
 *  17    PIO ch.B: isr_pio_par        (__interrupt)
 *
 * ISRs needing stack switch use __naked wrappers with explicit
 * register save/restore and EI only immediately before RETI.
 *
 * Simple ISRs (flag-set only, stubs) use __interrupt(N).
 * ================================================================ */

/* ISR stack switch helpers.
 * All ISRs switch SP to ISTACK (0xF600) to avoid overflowing the
 * interrupted program's stack.  Stack grows down from IVT.  Two variants:
 *   isr_enter / isr_exit: save/restore AF only (for simple flag-set
 *     ISRs whose C body only touches __sfr ports and static bytes)
 *   isr_enter_full / isr_exit_full: save/restore AF,BC,DE,HL (for
 *     ISRs with C body code that may clobber all registers) */

static inline void isr_enter(void) __naked
{
    __asm__("ld (_sp_sav), sp     \n"
            "ld sp, #" STR(ISTACK_ADDR) " \n"
            "push af              \n");
}

static inline void isr_exit(void) __naked
{
    __asm__("pop af               \n"
            "ld sp, (_sp_sav)     \n"
            "ei                   \n"
            "reti                 \n");
}

static inline void isr_enter_full(void) __naked
{
    __asm__("ld (_sp_sav), sp     \n"
            "ld sp, #" STR(ISTACK_ADDR) " \n"
            "push af              \n"
            "push bc              \n"
            "push de              \n"
            "push hl              \n");
}

static inline void isr_exit_full(void) __naked
{
    __asm__("pop hl               \n"
            "pop de               \n"
            "pop bc               \n"
            "pop af               \n"
            "ld sp, (_sp_sav)     \n"
            "ei                   \n"
            "reti                 \n");
}

/*
 * CRT display refresh ISR body (CTC ch.2)
 *
 * Called ~50 times/sec by the 8275 CRT controller.
 * Programs the DMA controller to refresh the display from DSPSTR (0xF800).
 * Also increments the 32-bit RTC and decrements timers.
 */
void isr_crt(void) __naked
{
#ifndef HOST_TEST
    isr_enter_full();

    /* Read CRT status register to acknowledge interrupt */
    (void)port_in(crt_cmd);

    /* Program DMA for 8275 display refresh */
    port_out(dma_smsk, DMA_MASK_SET(DMA_CH_DISPLAY));
    port_out(dma_smsk, DMA_MASK_SET(DMA_CH_DISATTR));
    port_out(dma_clbp, 0);         /* clear byte pointer flip-flop */

    /* Display data: 2000 bytes from DSPSTR */
    hal_dma_dsp_addr(DSPSTR);
    hal_dma_dsp_wc(SCRN_SIZE - 1);

    /* Attribute data: zero length (no attributes used) */
    hal_dma_atr_wc(0);

    /* Unmask DMA channels */
    port_out(dma_smsk, DMA_MASK_CLR(DMA_CH_DISPLAY));
    port_out(dma_smsk, DMA_MASK_CLR(DMA_CH_DISATTR));

    /* Deferred cursor update — avoids 3 port writes per character */
    if (cur_dirty) {
        cur_dirty = 0;
        port_out(crt_cmd, 0x80);       /* load cursor position command */
        port_out(crt_param, curx);     /* X position */
        port_out(crt_param, cursy);    /* Y position */
    }

    /* Reprogram CTC ch2 for next interrupt */
    port_out(ctc2, 0xD7);          /* counter mode */
    port_out(ctc2, 1);             /* count 1 */

    /* Increment 32-bit real-time clock */
    rtc0++;
    if (rtc0 == 0)
        rtc2++;

    /* Timer 0: exit routine countdown */
    if (timer1 != 0) {
        timer1--;
        if (timer1 == 0) {
            /* Call exit routine at warmjp address */
            ((void (*)(void))warmjp)();
        }
    }

    /* Timer 1: floppy motor-off countdown */
    if (timer2 != 0) {
        timer2--;
        if (timer2 == 0)
            fdstop();
    }

    /* General delay timer */
    if (delcnt != 0)
        delcnt--;

    isr_exit_full();
#endif
}

void isr_pio_kbd(void) __naked
{
#ifndef HOST_TEST
    isr_enter_full();

    /* Read keystroke from PIO (clears interrupt even if buffer full) */
    {
        byte key, new_head;
        key = port_in(pio_a_data);
        new_head = (kbhead + 1) & KBMASK;
        if (new_head != kbtail) {
            kbbuf[kbhead] = key;
            kbhead = new_head;
            kbstat = 0xFF;
        }
    }

    isr_exit_full();
#endif
}

void isr_floppy(void) __naked
{
#ifndef HOST_TEST
    isr_enter_full();

    /* Floppy completion: set flag, read FDC result or sense interrupt */
    {
        byte delay;
        fl_flg = 0xFF;
        for (delay = 5; delay; delay--)
            ;
        if (port_in(fdc_status) & 0b00010000)     /* CB: in result phase */
            fdc_result();
        else
            fdc_sense_int();
    }

    isr_exit_full();
#endif
}

/* Dummy ISR for unused IVT slots (EI + RETI) */
void isr_dummy(void) __interrupt(0) {}

/* HD ISR stub — TODO(harddisk): Postponed until BIOS fits on mini. */
void isr_hd(void) __interrupt(4) {}

/*
 * SIO Channel B ISRs (printer port)
 *
 * NOTE: The original asm BIOS switched SP to ISTACK (0xF600) in these
 * ISRs.  The `__critical __interrupt` form does NOT switch stacks — it
 * runs on whatever stack was active when the interrupt fired.  This is
 * safe because:
 *   - The bodies are trivial (port I/O + flag store), using only AF+HL
 *   - The compiler pushes 5 register pairs = 10 bytes of stack
 *   - CP/M guarantees at least 32 bytes of stack in the CCP/BDOS area
 *   - No nested interrupts (__critical keeps DI until EI before RETI)
 * If a future change makes any of these bodies non-trivial (calls,
 * large locals), they must revert to __naked with isr_enter/isr_exit.
 */

/* TXB: Ch.B transmit complete — reset TX int, mark printer ready */
void isr_sio_b_tx(void) __critical __interrupt(8)
{
    port_out(sio_b_ctrl, 0x28);   /* reset TX interrupt pending */
    prtflg = 0xFF;              /* printer ready */
}

/* EXTSTB: Ch.B external status change — read and acknowledge */
void isr_sio_b_ext(void) __critical __interrupt(9)
{
    rr0_b = port_in(sio_b_ctrl);  /* read RR0 */
    port_out(sio_b_ctrl, 0x10);   /* reset ext/status interrupts */
}

/* SPECB: Ch.B special receive condition — read error, reset */
void isr_sio_b_spec(void) __critical __interrupt(11)
{
    port_out(sio_b_ctrl, 0x01);   /* select RR1 */
    rr1_b = port_in(sio_b_ctrl);  /* read RR1 */
    port_out(sio_b_ctrl, 0x30);   /* error reset */
}

/*
 * SIO Channel A ISRs (reader/punch port)
 *
 * NOTE: Same stack-switch omission as Channel B above — trivial bodies
 * run safely on the interrupted code's stack.  isr_sio_a_rx is the
 * exception: it uses local variables and ring buffer logic, so it
 * keeps __naked with isr_enter_full/isr_exit_full for the stack switch.
 */

/* TXA: Ch.A transmit complete — reset TX int, mark punch ready */
void isr_sio_a_tx(void) __critical __interrupt(12)
{
    port_out(sio_a_ctrl, 0x28);   /* reset TX interrupt pending */
    ptpflg = 0xFF;              /* punch ready */
}

/* EXTSTA: Ch.A external status change — read and acknowledge */
void isr_sio_a_ext(void) __critical __interrupt(13)
{
    rr0_a = port_in(sio_a_ctrl);  /* read RR0 */
    port_out(sio_a_ctrl, 0x10);   /* reset ext/status interrupts */
}

/* RCA: Ch.A receive — store in ring buffer with RTS flow control */
void isr_sio_a_rx(void) __naked
{
#ifndef HOST_TEST
    isr_enter_full();

    {
        byte ch, new_head, used;

        ch = port_in(sio_a_data);       /* read char (clears interrupt) */

        new_head = (rxhead + 1) & RXMASK;

        if (new_head == rxtail)
            goto rts_off;            /* buffer full — deassert RTS */

        rxbuf[rxhead] = ch;
        rxhead = new_head;

        /* check if buffer is nearly full */
        used = (new_head - rxtail) & RXMASK;
        if (used < RXTHHI)
            goto done;               /* plenty of room */

    rts_off:
        /* deassert RTS to pause sender */
        port_out(sio_a_ctrl, 0x05);         /* select WR5 */
        port_out(sio_a_ctrl, wr5a + 0x88);  /* DTR=1, TX enable, RTS=0 */
    done: ;
    }

    isr_exit_full();
#endif
}

/* SPECA: Ch.A special receive condition — error reset, flush buffer */
void isr_sio_a_spec(void) __critical __interrupt(15)
{
    port_out(sio_a_ctrl, 0x01);   /* select RR1 */
    rr1_a = port_in(sio_a_ctrl);  /* read RR1 */
    port_out(sio_a_ctrl, 0x30);   /* error reset */
    rxhead = 0;                 /* flush ring buffer */
    rxtail = 0;
}

/* PIO ch.B (parallel output) ISR — not used on RC702 */
void isr_pio_par(void) __interrupt(17) {}
