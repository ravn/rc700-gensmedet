/*
 * bios.h — RC702 CP/M BIOS declarations
 *
 * Constants, memory layout, and extern declarations for fixed-address
 * variables and structs at fixed addresses.
 */

#ifndef BIOS_H
#define BIOS_H

#include <stdint.h>

typedef uint8_t  byte;
typedef uint16_t word;

/* CP/M 2.2 Disk Parameter Header (DPH) — one per logical drive.
 * Reference: CP/M 2.2 System Interface Guide, section 6.10
 *   http://www.cpm.z80.de/manuals/cpm22-m.pdf page 53
 *
 * The BIOS returns a pointer to the DPH from SELDSK.  The BDOS uses
 * the DPH to locate the translation table, directory buffer, DPB,
 * check vector, and allocation vector for the selected drive.
 *
 * All fields are 16-bit addresses (pointers) or reserved scratch areas.
 * Total size: 16 bytes (8 words) per drive. */
typedef struct {
    void *xlt;       /* +0:  sector translation table (NULL = no translation) */
    void *scratch[3];/* +2:  scratch area used by BDOS (3 words) */
    void *dirbf;     /* +8:  directory buffer (128 bytes, shared by all drives) */
    void *dpb;       /* +10: Disk Parameter Block (set by SELDSK) */
    void *csv;       /* +12: check vector (removable media change detection) */
    void *alv;       /* +14: allocation vector (disk space bitmap) */
} DPH;

/* Display memory: 25 rows × 80 columns at 0xF800, refreshed by 8275 CRT.
 * The array type is the single source of truth for all screen dimensions. */
#define DSPSTR      0xF800      /* display refresh memory base */

typedef byte DisplayRow[80];
typedef DisplayRow Display[25];

/* Dimensions derived from the display array type */
#define SCRN_COLS   ((byte)sizeof(DisplayRow))          /* 80 */
#define SCRN_ROWS   (sizeof(Display) / sizeof(DisplayRow))  /* 25 */
#define SCRN_SIZE   ((word)sizeof(Display))             /* 2000 */

/* Display access: display[row] is a DisplayRow, display[row][col] is a byte.
 * screen is a flat byte pointer for offset-based access (cury+curx). */
#define display     ((DisplayRow *)DSPSTR)
#define screen      ((byte *)DSPSTR)
#define DISPLAY_ROW(n)  ((byte *)display[n])

/* Cursor coordinate limits (derived from array dimensions) */
#define COLUMN0     0
#define COLUMN79    (SCRN_COLS - 1)             /* 79 */
#define ROW0        0
#define ROW24       (SCRN_ROWS - 1)             /* 24 */
#define ROW0_OFF    0                           /* cury byte offset for row 0 */
#define ROW24_OFFSET   (ROW24 * SCRN_COLS)         /* cury byte offset for row 24 = 1920 */

/*
 * Runtime character conversion tables at 0xF680 (384 bytes).
 *
 * These tables convert between the internal character set (ASCII) and
 * national character sets (Danish/Norwegian, Swedish, German, etc.).
 * The RC702 uses 7-bit characters with the high-bit codes (0x40-0x7F)
 * remapped for national characters.
 *
 * At cold boot, BIOS initializes both tables to identity mapping
 * (pass-through).  The disk-resident copy at 0xD580 (CONVTA_ADDR)
 * may contain national tables written by CONFI.COM; these can be
 * memcpy'd here to activate them.
 *
 * Example: Danish/Norwegian mapping in outcon:
 *   '@'(0x40) → 'Ø', '['(0x5B) → 'Æ', '\'(0x5C) → 'Ø',
 *   ']'(0x5D) → 'Å', '{'(0x7B) → 'æ', '|'(0x7C) → 'ø',
 *   '}'(0x7D) → 'å', '~'(0x7E) → 'ü'
 */
typedef struct {
    byte outcon[128];       /* 0xF680: output conversion table.
                             * Maps character codes 0x00-0x7F before display.
                             * Applied by CONOUT before writing to screen memory.
                             * Identity = ASCII pass-through (no conversion). */
    byte inconv[256];       /* 0xF700: input conversion table.
                             * Maps raw keyboard/serial input bytes 0x00-0xFF
                             * to internal character codes.
                             * Identity = no conversion. */
} ConvTables;

#define BIOS_STACK  0xF500      /* BIOS private stack top (grows down) */
#define CONV_ADDR   0xF680      /* runtime address of conversion tables */
#ifndef HOST_TEST
#define CONV (*(volatile ConvTables *)CONV_ADDR)
#else
extern volatile ConvTables _convtables;
#define CONV _convtables
#endif

#define outcon      CONV.outcon
#define inconv      CONV.inconv
#define IVT_ADDR    0xF600      /* interrupt vector table (page-aligned) */
#define ISTACK_ADDR 0xF600      /* interrupt stack top (grows down from IVT) */

/* CP/M memory layout — derived from MSIZE, same as BIOS.MAC.
 * MSIZE = available memory excluding BIOS (in KB).
 * BIAS  = offset from 20K base CP/M to actual addresses.
 * CPMB  = CCP base.  BDOS = CPMB + 0x806.  BIOS = CPMB + CPML.
 * CPML  = 0x1600 = length of CCP + BDOS. */
#ifndef MSIZE
#define MSIZE       56          /* default; overridden by -DMSIZE=N from Makefile */
#endif
#define STR_(x) #x
#define STR(x)  STR_(x)
#define MSIZE_STR STR(MSIZE)
#define BIAS        ((MSIZE - 20) * 1024u)
#define CPMB        (0x3400u + BIAS)        /* CCP base */
#define CPML        0x1600                  /* CCP + BDOS length */
#define CCP_BASE    CPMB
#define BDOS_BASE   (CPMB + 0x806)          /* BDOS entry */
#define BIOS_BASE   (CPMB + CPML)           /* BIOS jump table */
#define BUFF        0x0080                  /* default DMA buffer */
#define CFG_ADDR    (CPMB + 0x1100)         /* CONFI block temp address (CCP area) */
#if defined(__SDCC) || defined(__SCCZ80)
static volatile byte __at(0x0000) wboot_jp;   /* JP opcode */
static volatile word __at(0x0001) wboot_vec;  /* JP WBOOT address */
static volatile byte __at(0x0003) iobyte;
static volatile byte __at(0x0004) cdisk;
static volatile byte __at(0x0005) bdos_jp;    /* JP opcode */
static volatile word __at(0x0006) bdos_vec;   /* JP BDOS address */
#elif defined(__clang__)
#define wboot_jp   (*(volatile byte *)0x0000)
#define wboot_vec  (*(volatile word *)0x0001)
#define iobyte     (*(volatile byte *)0x0003)
#define cdisk      (*(volatile byte *)0x0004)
#define bdos_jp    (*(volatile byte *)0x0005)
#define bdos_vec   (*(volatile word *)0x0006)
#else
/* Stubs for host testing */
static volatile byte wboot_jp, iobyte, cdisk, bdos_jp;
static volatile word wboot_vec, bdos_vec;
#endif
#define NSECTS      (CPML / 128)    /* CCP+BDOS length in 128-byte sectors */

/* I/O port numbers now defined in hal.h.
 * Legacy aliases for bios.c code that uses different names: */
#define PORT_CTC_CH0    PORT_CTC0
#define PORT_FDC        PORT_FDC_STATUS
#define PORT_FDD        PORT_FDC_DATA
#define PORT_CRT_DATA   PORT_CRT_PARAM

/* IOBYTE device redirection (CP/M 2.2 Table 6-4).
 * STAT CON:=TTY: routes console to SIO-A serial for remote control. */
#define IOBYTE_CON(io)  ((io) & 0x03)
#define IOBYTE_RDR(io)  (((io) >> 2) & 0x03)
#define IOBYTE_PUN(io)  (((io) >> 4) & 0x03)
#define IOBYTE_LST(io)  (((io) >> 6) & 0x03)

#define IOB_TTY  0      /* CON:TTY/RDR:TTY/PUN:TTY/LST:TTY → SIO-A serial */
#define IOB_CRT  1      /* CON:CRT/RDR:PTR/PUN:PTP/LST:CRT */
#define IOB_BAT  2      /* CON:BAT/RDR:UR1/PUN:UP1/LST:LPT */
#define IOB_UC1  3      /* CON:UC1/RDR:UR2/PUN:UP2/LST:UL1 (parked) */

/* Default: CON:=CRT(1), RDR:=PTR(1), PUN:=PTP(1), LST:=LPT(2) */
#define IOBYTE_DEFAULT  0x94  /* CON:=TTY (serial+CRT echo), RDR:=PTR, PUN:=PTP, LST:=LPT */

/* Ring buffer parameters (REL30) */
#define RXBUFSZ     256         /* SIO ring buffer size (page-aligned) */
#define RXMASK      (RXBUFSZ-1)
#define RXTHHI      (RXBUFSZ-8) /* deassert RTS threshold */
#define RXTHLO      (RXBUFSZ-16)/* reassert RTS threshold */
#define KBBUFSZ     16          /* keyboard ring buffer size */
#define KBMASK      (KBBUFSZ-1)

/*
 * Work area at 0xFFD0-0xFFFF (48 bytes).
 *
 * Fixed-address RAM variables used by the BIOS at runtime.
 * Layout matches the original BIOS ORG+DS block — addresses are ABI
 * because some external programs may access them directly.
 *
 * Located at the very top of the Z80 address space, above the display
 * memory (0xF800-0xFFCF).  The _pad fields are reserved gaps in the
 * original layout that must be preserved for address compatibility.
 *
 * All fields are zeroed by _cboot's BSS-clear or set during BIOS init.
 */
typedef struct {
    byte  _pad0;            /* 0xFFD0: reserved (unused byte) */
    byte  curx;             /* 0xFFD1: cursor column position (0-79) */
    word cury;              /* 0xFFD2: cursor row as byte offset (row × 80) */
    byte  cursy;            /* 0xFFD4: cursor row number (0-24) */
    word locbuf;            /* 0xFFD5: scroll source pointer */
    byte  xflg;             /* 0xFFD7: escape sequence state (0/1/6) */
    word locad;             /* 0xFFD8: screen position offset (scroll temp) */
    byte  usession;         /* 0xFFDA: character currently being output */
    byte  _pad1[3];         /* 0xFFDB-0xFFDD: reserved gap */
    byte  adr0;             /* 0xFFDE: first XY escape coordinate */
    /* --- ISR-modified fields below: must be volatile --- */
    volatile word timer1;   /* 0xFFDF: warm-boot countdown (ISR decrements) */
    volatile word timer2;   /* 0xFFE1: motor stop countdown (ISR decrements) */
    volatile word delcnt;   /* 0xFFE3: delay counter (ISR decrements) */
    word warmjp;            /* 0xFFE5: exit routine JP target address */
    byte  fdtimo_var;       /* 0xFFE7: motor-off timeout reload value */
    byte  _pad2[2];         /* 0xFFE8-0xFFE9: reserved gap */
    word stptim_var;        /* 0xFFEA: motor timer reload value */
    volatile word clktim;   /* 0xFFEC: screen blank timer (ISR decrements) */
    byte  _pad3[14];        /* 0xFFEE-0xFFFB: reserved gap (14 bytes) */
    volatile word rtc0;     /* 0xFFFC: real-time clock low (ISR increments) */
    volatile word rtc2;     /* 0xFFFE: real-time clock high (ISR increments) */
} WorkArea;

#ifndef HOST_TEST
#define WORK_ADDR   0xFFD0      /* work area base address */
#define W (*(WorkArea *)WORK_ADDR)

/* Absolute addresses for work area fields (used in inline asm).
 * These MUST match the WorkArea struct layout above. */
#define TIMER1_ADDR 0xFFDF      /* WorkArea.timer1 */
#define WARMJP_ADDR 0xFFE5      /* WorkArea.warmjp */
#define RTC0_ADDR   0xFFFC      /* WorkArea.rtc0 */
#define RTC2_ADDR   0xFFFE      /* WorkArea.rtc2 */
#else
extern WorkArea _workarea;
#define W _workarea
#endif

/* Convenience accessors */
#define curx        W.curx
#define cury        W.cury
#define cursy       W.cursy
#define locbuf      W.locbuf
#define xflg        W.xflg
#define locad       W.locad
#define usession    W.usession
#define adr0        W.adr0
#define timer1      W.timer1
#define timer2      W.timer2
#define delcnt      W.delcnt
#define warmjp      W.warmjp
#define fdtimo_var  W.fdtimo_var
#define stptim_var  W.stptim_var
#define clktim      W.clktim
#define rtc0        W.rtc0
#define rtc2        W.rtc2

/*
 * JTVARS — runtime configuration variables at 0xDA33 (22 bytes).
 *
 * Located immediately after the BIOS JP table (17 entries at 0xDA00)
 * and before the extended JP table (0xDA49+).  Storage is in the
 *
 * External programs (CONFI.COM, FORMAT.COM, etc.) depend on these
 * exact addresses — they are part of the BIOS ABI.
 *
 * Initialized by bios_jump_vector_table.c const struct (zeros + fd0_term=0xFF); populated
 * by bios_hw_init() and bios_boot() from CONFI block values.
 */
typedef struct {
    byte  adrmod;           /* 0xDA33: cursor addressing mode.
                             *   0 = XY (column first, then row) — default
                             *   1 = YX (row first, then column)
                             * Copied from CFG.xyflg at boot.
                             * Controls interpretation of 0x06 escape sequence. */
    byte  wr5a;             /* 0xDA34: SIO channel A WR5 bits/char mask.
                             * Extracted from CFG.sioa[6] & 0x60 at boot.
                             * Used by CONOUT/LIST to set character width:
                             *   0x60 = 8 bits (REL30), 0x20 = 7 bits (older). */
    byte  wr5b;             /* 0xDA35: SIO channel B WR5 bits/char mask.
                             * Extracted from CFG.siob[8] & 0x60 at boot.
                             * Used by PUNCH to set character width. */
    byte  mtype;            /* 0xDA36: machine type identifier.
                             *   0 = RC700/RC702 (default)
                             *   1 = RC850/RC855
                             *   2 = ITT3290
                             *   3 = RC703
                             * Set to 0 by bios_jump_vector_table.c initializer; not modified by BIOS. */
    byte  fd0[16];          /* 0xDA37-0xDA46: active drive format table.
                             * One format code per drive (A-P).
                             * Initialized from CFG.infd[] at boot.
                             * Updated by CONFI.COM when drives are reconfigured.
                             * Format codes: see ConfiBlock.infd[] comments.
                             * 0xFF = drive not present. */
    byte  fd0_term;         /* 0xDA47: drive table terminator.
                             *   Always 0xFF.  Marks end of fd0[] scan. */
    byte  bootd;            /* 0xDA48: boot device identifier.
                             *   0x00 = booted from floppy disk
                             *   0x01 = booted from hard disk
                             * Set from CFG.ibootd at boot.  Used by warm boot
                             * to know which device to reload CCP/BDOS from. */
} JTVars;

#ifndef HOST_TEST
#define JT (*(volatile JTVars *)(BIOS_BASE + 0x33))  /* after 17 JP entries */
#else
extern volatile JTVars _jtvars;
#define JT _jtvars
#endif

#define adrmod      JT.adrmod
#define wr5a        JT.wr5a
#define wr5b        JT.wr5b
#define mtype       JT.mtype
#define fd0         JT.fd0
#define bootd       JT.bootd

/* CP/M Disk Parameter Block */
typedef struct {
    word spt;               /* sectors per track */
    byte  bsh;                  /* block shift factor */
    byte  blm;                  /* block mask */
    byte  exm;                  /* extent mask */
    word dsm;               /* disk size - 1 (in blocks) */
    word drm;               /* directory entries - 1 */
    byte  al0, al1;             /* allocation bitmap */
    word cks;               /* check vector size */
    word off;               /* track offset */
} DPB;

/* Floppy System Parameters (16 bytes each) */
typedef struct {
    DPB  *dpb;                  /* DPB pointer */
    byte  cpmrbp;               /* records per block */
    word cpmspt;            /* CP/M sectors per track */
    byte  secmsk;               /* sector mask */
    byte  secshf;               /* sector shift */
    byte *trantb;               /* translation table pointer */
    byte  dtlv;                 /* data length value */
    byte  dsktyp;               /* disk type (0=floppy) */
    byte  _pad[5];              /* filler to 16 bytes */
} FSPA;

/* Floppy Disk Format descriptor (8 bytes each) */
typedef struct {
    byte  phys_spt;             /* physical sectors per track */
    word dma_count;         /* DMA byte count */
    byte  mf;                   /* MF flag (0=FM, 64=MFM) */
    byte  n;                    /* sector size code (0=128, 1=256, 2=512) */
    byte  eot;                  /* end of track (last sector number) */
    byte  gap;                  /* gap length */
    byte  tracks;               /* total tracks */
} FDF;

/* Disk tables (defined in bios.c) */
extern const byte tran0[], tran8[], tran16[], tran24[];
extern const DPB dpb0, dpb8, dpb16, dpb24;
extern const FSPA fspa[4];
extern const FDF fdf[4];
extern word trkoff[];

/* Write type constants */
#define WRALL   0   /* write to allocated sector */
#define WRDIR   1   /* write to directory sector */
#define WRUAL   2   /* write to unallocated sector */

/*
 * CONFI configuration block — hardware init parameters.
 *
 * Disk-resident on Track 0 at offset 0x080 (_confi_on_disk in boot_confi.c).
 * _cboot copies it to runtime 0xD500 (CCP area, valid during init only).
 *
 * CONFI.COM reads/writes this block on disk; restoring the original
 * disk layout for CONFI.COM compatibility is a long-term goal.
 * INIT sends these values to hardware I/O ports at cold boot.
 * C code accesses via CFG macro.
 *
 * The default values shown in comments are for REL30.
 * CONFI.COM may have written different values to disk.
 */
typedef struct {
    /*
     * Z80 CTC (Counter/Timer Controller) — 4 channels at ports 0x0C-0x0F.
     *
     * CTC mode byte bits:
     *   bit 0: 1=control word (must be 1)
     *   bit 1: 0=software reset of channel
     *   bit 2: 1=time constant follows in next byte
     *   bit 3: 0=auto trigger, 1=external CLK/TRG edge
     *   bit 4: 0=falling edge, 1=rising edge
     *   bit 5: 0=prescaler ÷16, 1=prescaler ÷256
     *   bit 6: 0=timer mode (uses prescaler), 1=counter mode (no prescaler)
     *   bit 7: 0=disable interrupt, 1=enable interrupt
     *
     * CTC input clock: 614.4 kHz from hardware divider (not software-changeable).
     * Baud rate = 614400 / CTC_divisor / SIO_clock_mode.
     * SIO clock mode: ×16 for 600-38400 baud, ×64 for 50-300 baud.
     *
     * Ch0/Ch1 generate baud rate clocks for SIO channels A and B.
     * Ch2/Ch3 generate interrupts for display refresh and floppy controller.
     */
    byte ctc_mode0;         /* +0x00: CTC ch0 mode (SIO-A baud clock)
                             *   0x47 = timer mode, interrupt disabled, auto trigger,
                             *          time constant follows, prescaler ÷16 */
    byte ctc_count0;        /* +0x01: CTC ch0 time constant (SIO-A baud divisor)
                             *   0x01 = divisor 1 → 614400/1/16 = 38400 baud (REL30)
                             *   0x20 = divisor 32 → 614400/32/16 = 1200 baud (rel.2.1)
                             *   0x02 = divisor 2 → 614400/2/16 = 19200 baud (rel.2.2) */
    byte ctc_mode1;         /* +0x02: CTC ch1 mode (SIO-B baud clock)
                             *   0x47 = same as ch0: timer mode, auto trigger */
    byte ctc_count1;        /* +0x03: CTC ch1 time constant (SIO-B baud divisor)
                             *   0x20 = divisor 32 → 1200 baud */
    byte ctc_mode2;         /* +0x04: CTC ch2 mode (display refresh interrupt)
                             *   0xD7 = counter mode, interrupt enabled, auto trigger,
                             *          time constant follows, rising edge */
    byte ctc_count2;        /* +0x05: CTC ch2 time constant
                             *   0x01 = interrupt after every count pulse from 8275 */
    byte ctc_mode3;         /* +0x06: CTC ch3 mode (floppy controller interrupt)
                             *   0xD7 = same as ch2: counter mode, interrupt enabled */
    byte ctc_count3;        /* +0x07: CTC ch3 time constant
                             *   0x01 = interrupt after every count pulse from µPD765 */

    /*
     * Z80 SIO/2 channel A init block — Printer port (ports 0x08/0x0A).
     *
     * 9 bytes sent sequentially to the SIO-A control port (0x0A) via OTIR.
     * Each register write is a pair: first byte selects the register (written
     * to WR0 bits 2:0), second byte is the register value.  Exception: the
     * channel reset command (0x18) is a WR0 command itself.
     *
     * REL30 defaults: 38400 baud, 8-N-1 (8 data bits, no parity, 1 stop bit).
     * Older releases: 7 data bits, even parity (Danish/Nordic standard).
     *
     * SIO Ch.A is directly connected to a serial printer.
     * CP/M maps it as the LST: (list) device.
     */
    byte sioa[9];           /* +0x08: SIO channel A init sequence
                             *   [0] 0x18: WR0 — channel reset
                             *   [1] 0x04: WR0 — select WR4
                             *   [2] 0x44: WR4 — ×16 clock, 1 stop bit, no parity
                             *             (rel.2.1: 0x47 = ×16, 1 stop, even parity)
                             *             (50-300 baud: 0xC4/C7 for ×64 clock)
                             *   [3] 0x03: WR0 — select WR3
                             *   [4] 0xC1: WR3 — Rx enable, auto enables, 8 bits/char
                             *             (rel.2.1: 0x61 = Rx enable, auto, 7 bits)
                             *   [5] 0x05: WR0 — select WR5
                             *   [6] 0x60: WR5 — 8 bits Tx, Tx disabled, RTS off, DTR off
                             *             (rel.2.1: 0x20 = 7 bits Tx)
                             *             BIOS copies bits 6:5 → wr5a at boot
                             *   [7] 0x01: WR0 — select WR1
                             *   [8] 0x1B: WR1 — Ext/Status Int + Tx Int + Rx Int (all chars) */

    /*
     * Z80 SIO/2 channel B init block — Terminal port (ports 0x09/0x0B).
     *
     * 11 bytes (2 more than Ch.A because Ch.B carries the interrupt vector
     * in WR2, which is shared by both channels — only Ch.B WR2 is used).
     *
     * Used for modem, PC connection, or inter-machine file transfer (FILEX).
     * CP/M maps it as both PUN: (punch) and RDR: (reader) devices.
     *
     * REL30 default: 1200 baud, 7-E-1 (7 data bits, even parity, 1 stop bit).
     * Rx is disabled at init — this is the auxiliary/printer port, output-only
     * unless explicitly enabled by the application.
     */
    byte siob[11];          /* +0x11: SIO channel B init sequence
                             *   [0]  0x18: WR0 — channel reset
                             *   [1]  0x02: WR0 — select WR2
                             *   [2]  0x10: WR2 — interrupt vector base 0x10
                             *              (offset to skip CTC2 gap in vector table;
                             *               with "status affects vector" in WR1,
                             *               the SIO modifies bits 3:1 to encode
                             *               the interrupt source)
                             *   [3]  0x04: WR0 — select WR4
                             *   [4]  0x47: WR4 — ×16 clock, 1 stop bit, even parity
                             *   [5]  0x03: WR0 — select WR3
                             *   [6]  0x60: WR3 — Rx disabled, auto enables, 7 bits/char
                             *              (bit 0 = 0: Rx disabled at init)
                             *   [7]  0x05: WR0 — select WR5
                             *   [8]  0x20: WR5 — 7 bits Tx, Tx disabled, RTS off, DTR off
                             *              BIOS copies bits 6:5 → wr5b at boot
                             *   [9]  0x01: WR0 — select WR1
                             *   [10] 0x1F: WR1 — Ext/Status Int + Tx Int + Rx Int (all)
                             *              + Status Affects Vector (bit 2)
                             *              + Parity Is Special Condition (bit 0) */

    /*
     * Am9517A (Intel 8237) DMA mode register values.
     *
     * Mode register byte bits:
     *   D1:D0 = channel select (00=ch0, 01=ch1, 10=ch2, 11=ch3)
     *   D3:D2 = transfer type (01=write/IO→mem, 10=read/mem→IO)
     *   D4    = auto-initialize enable
     *   D5    = address decrement (0=increment, 1=decrement)
     *   D7:D6 = mode (00=demand, 01=single, 10=block, 11=cascade)
     *
     * Written to DMA mode register port 0xFB.
     * Ch1 (floppy) is not set here — programmed per-operation by disk driver.
     */
    byte dmode[4];          /* +0x1C: DMA channel mode registers
                             *   [0] 0x48: ch0 (HD)      — single, read/mem→IO, ch0
                             *   [1] 0x49: ch1 (floppy)   — single, read/mem→IO, ch1
                             *            (default only; driver reprograms per transfer)
                             *   [2] 0x4A: ch2 (display)  — single, read/mem→IO, ch2
                             *   [3] 0x4B: ch3 (display2) — single, read/mem→IO, ch3 */

    /*
     * Intel 8275 CRT controller reset parameters.
     *
     * After a reset command (0x00) to port 0x01, the 8275 expects 4 parameter
     * bytes written to the data port (0x00).  These define screen geometry,
     * raster timing, and cursor appearance.
     *
     * CONFI.COM can modify PAR4 to change cursor shape and character height.
     */
    byte par1;              /* +0x20: 8275 Parameter 1 — horizontal format
                             *   0x4F = (0x4F & 0x7F) + 1 = 80 characters per row */
    byte par2;              /* +0x21: 8275 Parameter 2 — vertical format
                             *   0x98:  bits 5:0 = (0x18)+1 = 25 rows per frame
                             *          bits 7:6 = VRTC timing */
    byte par3;              /* +0x22: 8275 Parameter 3 — retrace timing
                             *   0x7A:  bits 4:0 = (0x1A)+2 = 28 H retrace chars
                             *          bits 7:5 = (3)+1 = 4 V retrace scan lines */
    byte par4;              /* +0x23: 8275 Parameter 4 — scan lines and cursor
                             *   0x6D:  bits 7:4 = (6)+1 = 7 lines per char row (REL30)
                             *          bits 3:2 = underline position
                             *          bits 1:0 = cursor format:
                             *            00=blink underline, 01=blink block,
                             *            10=steady underline, 11=steady block
                             *          0x6D → 7 lines/char, steady block cursor
                             *          (rel.2.1: 0x4D → 5 lines/char, blink block) */

    /*
     * NEC µPD765 (Intel 8272) FDC SPECIFY command.
     *
     * The SPECIFY command (0x03) sets mechanical timing parameters for the
     * floppy drive.  INIT sends fdprog_len bytes starting at fdprog_cmd
     * to the FDC data port (0x05), waiting for RQM between each byte.
     *
     * For mini (5.25") drives, the BIOS patches fdprog_srt to 0x0F
     * (slower stepping) before sending.
     */
    byte fdprog_len;        /* +0x24: FDC program byte count
                             *   3 = send 3 bytes (SPECIFY cmd + 2 parameter bytes) */
    byte fdprog_cmd;        /* +0x25: FDC command byte
                             *   0x03 = SPECIFY command */
    byte fdprog_srt;        /* +0x26: SRT/HUT byte (step rate time / head unload time)
                             *   0xDF:  bits 7:4 = SRT = 0xD (step rate = 3 ms at 8 MHz)
                             *          bits 3:0 = HUT = 0xF (head unload = 240 ms)
                             *   (mini override: 0x0F = slower stepping for 5.25" drives) */
    byte fdprog_hlt;        /* +0x27: HLT/ND byte (head load time / DMA mode)
                             *   0x28:  bits 7:1 = HLT = 0x14 (head load = 40 ms)
                             *          bit 0 = ND = 0 (DMA mode, not non-DMA) */

    /*
     * CONFI.COM user-facing settings.
     *
     * These are display/menu values shown by CONFI.COM; the actual hardware
     * state is in the register blocks above.  CONFI.COM uses these indices
     * to look up the corresponding CTC divisor and SIO WR4 values.
     */
    byte cursor_num;        /* +0x28: cursor format number (CONFI menu selection)
                             *   0x00 = blinking reverse block (default) */
    byte conv_num;          /* +0x29: character conversion table number
                             *   0x00 = Danish/Norwegian (default) */
    byte baud_a;            /* +0x2A: baud rate index for SIO-A (CONFI display)
                             *   0x06 = 1200 baud (display value; actual rate is
                             *          determined by ctc_count0 and sioa[2]) */
    byte baud_b;            /* +0x2B: baud rate index for SIO-B (CONFI display)
                             *   0x06 = 1200 baud */
    byte xyflg;             /* +0x2C: cursor addressing mode
                             *   0x00 = XY (column first, then row)
                             *   0x01 = YX (row first, then column)
                             *   Copied to adrmod (JTVARS) at boot */
    word stptim;            /* +0x2D: floppy motor stop timer (in 20 ms ticks)
                             *   250 = 250 × 20 ms = 5 second timeout
                             *   Copied to stptim_var (WorkArea) at boot */

    /*
     * Drive format configuration table — 16 entries + 0xFF terminator.
     *
     * Each entry is a disk format code byte that selects the physical
     * format for drives A-P.  Format codes (from SYSGEN/CPMBOOT):
     *   0x08 = DD 512 B/S (standard CP/M maxi or mini format)
     *   0x10 = SS 128 B/S (FM single density, Track 0 Side 0)
     *   0x18 = DD 256 B/S (MFM double density, Track 0 Side 1)
     *   0x20 = HD 1 MB (hard disk, floppy emulation)
     *   0xFF = drive not present / end of table
     *
     * At boot, infd[0] is copied to fd0[0] (JTVARS drive format table).
     * CONFI.COM allows reassigning drive formats.
     */
    byte infd[17];          /* +0x2F: drive format table (16 drives + terminator)
                             *   [0]  = 8: drive A — maxi floppy (8" DD, 1.2 MB)
                             *   [1]  = 8: drive B — mini floppy (5.25" DD)
                             *   [2]  = 32: drive C — hard disk (1 MB, floppy emu)
                             *   [3-15] = 255: drives D-P — not present
                             *   [16] = 255: terminator */

    /*
     * Hard disk partition configuration.
     * Only relevant for systems with a WD1000 Winchester controller
     * connected via the external HD board (CTC2 at ports 0x44-0x47).
     */
    byte ndtab;             /* +0x40: number of HD partitions
                             *   2 (default) */
    byte ndt1[3];           /* +0x41: HD partition descriptor
                             *   {2, 0, 0} */

    /*
     * CTC2 — second CTC on external hard disk interface board.
     *
     * Not present on the RC702 motherboard; lives on the external HD
     * controller board connected via the Z80 bus expansion connector.
     * Systems without a hard disk have no CTC2; writes to ports 0x44-0x47
     * are ignored (no hardware responds).
     */
    byte ctc2_mode4;        /* +0x44: CTC2 ch0 mode (WD1000 HD interrupt)
                             *   0xD7 = counter mode, interrupt enabled */
    byte ctc2_count4;       /* +0x45: CTC2 ch0 time constant
                             *   0x01 = interrupt after every pulse */
    byte ctc2_mode5;        /* +0x46: CTC2 ch1 reset
                             *   0x03 = software reset (disables channel) */

    byte ibootd;            /* +0x47: boot device
                             *   0x00 = boot from floppy disk
                             *   0x01 = boot from hard disk */
} ConfiBlock;

/* Runtime access to CONFI block (copied to CCP area by _cboot).
 * Valid during init only — CCP overwrites this area after boot. */
#ifndef HOST_TEST
#define CFG (*(volatile ConfiBlock *)CFG_ADDR)
#else
extern volatile ConfiBlock _confiblock;
#define CFG _confiblock
#endif

/* Convenience aliases for frequently accessed CONFI fields */
#define xyflg       CFG.xyflg

#endif /* BIOS_H */
