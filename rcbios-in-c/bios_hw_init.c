/* bios_hw_init.c — One-time hardware initialization (BOOT_CODE section).
 *
 * Compiled with --codeseg BOOT_CODE so this code lives in the unrelocated
 * boot area, NOT in the resident BIOS. It runs once at cold boot and is
 * overwritten by CCP after boot — saving ~474 bytes of resident BIOS.
 *
 * All hardware I/O uses __sfr ports (work from any address).
 * References to BSS variables (wr5a, fd0[], dph_table, etc.) use their
 * relocated runtime addresses, which are valid because coldboot has
 * already copied the BIOS to BIOS_BASE before calling bios_hw_init().
 */

#include <string.h>
#include <intrinsic.h>
#include "hal.h"
#include "bios.h"

/* ISR functions in bios.c (relocated BIOS) — referenced by IVT */
extern void isr_dummy(void);
extern void isr_hd(void);
extern void isr_sio_b_tx(void);
extern void isr_sio_b_ext(void);
extern void isr_sio_b_rx(void);
extern void isr_sio_b_spec(void);
extern void isr_sio_a_tx(void);
extern void isr_sio_a_ext(void);
extern void isr_sio_a_spec(void);
extern void isr_pio_par(void);

/* Stack-switching ISRs: SDCC uses __naked wrappers in bios.c;
 * clang uses assembly wrappers in bios_shims.s. */
/* isr_sio_b_rx runs on the interrupted program's stack (__critical
 * __interrupt), so both paths reference it directly — no wrapper. */
#ifdef __clang__
extern void isr_crt_wrapper(void);
extern void isr_floppy_wrapper(void);
extern void isr_sio_a_rx_wrapper(void);
extern void isr_pio_kbd_wrapper(void);
#define ISR_CRT      isr_crt_wrapper
#define ISR_FLOPPY   isr_floppy_wrapper
#define ISR_SIO_A_RX isr_sio_a_rx_wrapper
#define ISR_SIO_B_RX isr_sio_b_rx
#define ISR_PIO_KBD  isr_pio_kbd_wrapper
#else
extern void isr_crt(void);
extern void isr_floppy(void);
extern void isr_sio_a_rx(void);
extern void isr_pio_kbd(void);
#define ISR_CRT      isr_crt
#define ISR_FLOPPY   isr_floppy
#define ISR_SIO_A_RX isr_sio_a_rx
#define ISR_SIO_B_RX isr_sio_b_rx
#define ISR_PIO_KBD  isr_pio_kbd
#endif

/* FDC write helper in bios.c (relocated BIOS) */
extern void fdc_write(byte val);

/* BSS variables in bios.c (at relocated runtime addresses) */
extern byte max_drive_num;
extern disk_parameter_header dph_table[];
extern byte dirbf[];
extern const disk_parameter_block dpb_maxi_512;
extern byte chk0[], chk1[], all0[], all1[];
extern byte unalloc_count, current_format_idx, last_seek_disk;
/* hostbuf_valid, hostbuf_dirty, disk_error are accessed via wb macros from bios.h */

/* ================================================================
 * Interrupt vector table — function pointer array
 *
 * Linker resolves ISR addresses to their runtime (relocated) values.
 * Copied to IVT_ADDR (page-aligned) by setup_ivt().
 * ================================================================ */

typedef void (*isr_fn)(void);

#define IVT_ENTRIES 18

__attribute__((section(".boot_rodata"), used))
static const isr_fn ivt_template[IVT_ENTRIES] = {
    isr_dummy,              /*  0: CTC1 ch0 — SIO-A baud rate */
    isr_dummy,              /*  1: CTC1 ch1 — SIO-B baud rate */
    ISR_CRT,                /*  2: CTC1 ch2 — display refresh */
    ISR_FLOPPY,             /*  3: CTC1 ch3 — floppy completion */
    isr_hd,                 /*  4: CTC2 ch0 — hard disk */
    isr_dummy,              /*  5: CTC2 ch1 — unused */
    isr_dummy,              /*  6: CTC2 ch2 — unused */
    isr_dummy,              /*  7: CTC2 ch3 — unused */
    isr_sio_b_tx,           /*  8: SIO ch.B TX */
    isr_sio_b_ext,          /*  9: SIO ch.B ext status */
    ISR_SIO_B_RX,           /* 10: SIO ch.B RX — test console */
    isr_sio_b_spec,         /* 11: SIO ch.B special */
    isr_sio_a_tx,           /* 12: SIO ch.A TX */
    isr_sio_a_ext,          /* 13: SIO ch.A ext status */
    ISR_SIO_A_RX,           /* 14: SIO ch.A RX — ring buffer */
    isr_sio_a_spec,         /* 15: SIO ch.A special */
#ifdef KBD_PIO_B
    isr_pio_par,            /* 16: PIO ch.A — parallel host */
    ISR_PIO_KBD,            /* 17: PIO ch.B — keyboard */
#else
    ISR_PIO_KBD,            /* 16: PIO ch.A — keyboard */
    isr_pio_par,            /* 17: PIO ch.B — parallel output */
#endif
};

/* Set the Z80 I register.  sdcccall(1) passes byte param in A,
 * so the inline ld i,a picks it up directly.
 *
 * Must NOT be declared inline — inlining removes the call boundary
 * and with it the sdcccall(1) guarantee that A holds the parameter.
 * Tested: inline version emits ld i,a without ld a,page — wrong. */
#ifdef __clang__
extern void set_i_reg(byte page);  /* in clang/bios_shims.s */
#else
__attribute__((section(".boot_code"), used))
static void set_i_reg(byte page)
{
    (void)page;
    ASM_VOLATILE("ld i, a\n");
}
#endif

/* Copy IVT to page-aligned RAM and enable IM2 */
__attribute__((section(".boot_code"), used))
static void setup_ivt(void)
{
    memcpy((void *)IVT_ADDR, ivt_template, sizeof(ivt_template));
    set_i_reg(IVT_ADDR >> 8);
    intrinsic_im_2();
}

/* ================================================================
 * Hardware initialization — called once from coldboot after relocation.
 * Configures PIO, CTC, SIO, DMA, FDC, CRT, display, and disk tables.
 * ================================================================ */

__attribute__((section(".boot_code"), used))
void bios_hw_init(void)
{
    /* Set up interrupt vector table and IM2 before any device init */
    setup_ivt();

    /* PIO: set interrupt vectors and modes */
    port_out(pio_a_ctrl, 0x20);    /* PIO-A interrupt vector */
    port_out(pio_b_ctrl, 0x22);    /* PIO-B interrupt vector */
#ifdef KBD_PIO_B
    port_out(pio_a_ctrl, 0x0F);    /* PIO-A output mode (host link) */
    port_out(pio_b_ctrl, 0x4F);    /* PIO-B input mode (keyboard) */
#else
    port_out(pio_a_ctrl, 0x4F);    /* PIO-A input mode (keyboard) */
    port_out(pio_b_ctrl, 0x0F);    /* PIO-B output mode */
#endif
    port_out(pio_a_ctrl, 0x83);    /* PIO-A enable interrupt */
    port_out(pio_b_ctrl, 0x83);    /* PIO-B enable interrupt */

    /* CTC: set interrupt vector and program all channels */
    port_out(ctc0, 0x00);         /* CTC interrupt vector */
    port_out(ctc0, CFG.ctc_mode0);
    port_out(ctc0, CFG.ctc_count0);
    port_out(ctc1, CFG.ctc_mode1);
    port_out(ctc1, CFG.ctc_count1);
    port_out(ctc2, CFG.ctc_mode2);
    port_out(ctc2, CFG.ctc_count2);
    port_out(ctc3, CFG.ctc_mode3);
    port_out(ctc3, CFG.ctc_count3);

    /* SIO: program channels A and B from CONFI init blocks.
     * OTIR: output B bytes from (HL++) to port C. */
#if defined(__SDCC) || defined(__SCCZ80) || !defined(__z80__)
    {
        byte i;
        for (i = 0; i < 9; i++)
            port_out(sio_a_ctrl, CFG.sioa[i]);
        for (i = 0; i < 11; i++)
            port_out(sio_b_ctrl, CFG.siob[i]);
    }
#else
    ASM_VOLATILE(
        "ld hl, %[sioa]\n\t"
        "ld c, %[port_a]\n\t"
        "ld b, 9\n\t"
        "otir\n\t"              /* HL now points to siob (contiguous) */
        "ld c, %[port_b]\n\t"
        "ld b, 11\n\t"
        "otir"
        : : [sioa] "i" (CFG_ADDR + 0x08),
            [port_a] "i" (PORT_SIO_A_CTRL),
            [port_b] "i" (PORT_SIO_B_CTRL)
        : "hl", "bc", "memory"
    );
#endif

    /* SIO: read initial status registers */
    (void)port_in(sio_a_ctrl);     /* read RR0-A */
    port_out(sio_a_ctrl, 1);       /* select RR1 */
    (void)port_in(sio_a_ctrl);     /* read RR1-A */
    (void)port_in(sio_b_ctrl);     /* read RR0-B */
    port_out(sio_b_ctrl, 1);       /* select RR1 */
    (void)port_in(sio_b_ctrl);     /* read RR1-B */

    /* DMA: master clear and set channel modes */
    port_out(dma_cmd, 0x20);                          /* master clear */
    port_out(dma_mode, DMA_MODE_MEM2IO(DMA_CH_HD));       /* HD: mem→disk */
    port_out(dma_mode, DMA_MODE_MEM2IO(DMA_CH_DISPLAY));  /* display: mem→CRT */
    port_out(dma_mode, DMA_MODE_MEM2IO(DMA_CH_DISATTR));  /* attributes: mem→CRT */

    /* FDC: send SPECIFY command */
    while (port_in(fdc_status) & (FDC_MSR_CB | FDC_MSR_DRIVE_SEEKING))
        ;  /* wait until FDC not busy AND no drive is seeking */
    fdc_write(0x03);            /* SPECIFY command */
    fdc_write(0xDF);            /* step rate 3ms, head unload 240ms */
    fdc_write(0x28);            /* head load 40ms, DMA mode */

    /* Clear display buffer with spaces */
    memset(DISPLAY_ROW(0), ' ', sizeof(Display));

    /* Clear work area (curx through end of 64K address space) */
    memset((void *)(WORK_ADDR + 1), 0, 0xFFFF - WORK_ADDR);

    /* CRT 8275: reset and program */
    port_out(crt_cmd, 0x00);       /* reset */
    port_out(crt_param, CFG.par[0]);   /* chars/row */
    port_out(crt_param, CFG.par[1]);   /* rows/frame */
    port_out(crt_param, CFG.par[2]);   /* lines/char + underline */
    port_out(crt_param, CFG.par[3]);   /* cursor format */
    port_out(crt_cmd, 0x80);       /* load cursor position */
    port_out(crt_param, 0);        /* cursor X = 0 */
    port_out(crt_param, 0);        /* cursor Y = 0 */
    port_out(crt_cmd, 0xE0);       /* preset counters */
    port_out(crt_cmd, 0x23);       /* start display */

    /* Initialize runtime variables */
    wr5a = CFG.sioa[6] & 0x60;  /* SIO-A bits/char from WR5 */
    wr5b = CFG.siob[6] & 0x60;  /* SIO-B bits/char from WR5 (test console order) */
    adrmod = xyflg;              /* copy addressing mode (via CFG macro) */

    /* Initialize motor timer reload from config */
    stptim_var = CFG.stptim;

    /* Initialize disk subsystem */
    {
        // ReSharper disable once CppJoinDeclarationAndAssignment
        byte d;

        /* Copy drive format table from config block */
        memcpy((void *)fd0, (const void *)CFG.infd, sizeof(fd0));

        /* Count configured drives from fd0 table */
        max_drive_num = 0;
        for (d = 0; d < 16; d++) {
            if (fd0[d] == 0xFF)
                break;
            max_drive_num = d;
        }

        /* Initialize disk_parameter_header entries for each drive.
         * Clang accepts link-time constants in static initializers;
         * SDCC does not, so it uses per-field assignment. */
#ifdef __clang__
        {
            static const disk_parameter_header dph0 = {
                0, {0,0,0}, dirbf, &dpb_maxi_512, chk0, all0
            };
            static const disk_parameter_header dph1 = {
                0, {0,0,0}, dirbf, &dpb_maxi_512, chk1, all1
            };
            dph_table[0] = dph0;
            if (max_drive_num >= 1)
                dph_table[1] = dph1;
        }
#else
        {
            disk_parameter_header *entry = &dph_table[0];
            memset(entry, 0, sizeof(*entry));
            entry->dirbf                = dirbf;
            entry->dpb = &dpb_maxi_512;
            entry->csv                  = chk0;
            entry->alv                  = all0;
        }
        if (max_drive_num >= 1) {
            disk_parameter_header *entry = &dph_table[1];
            memset(entry, 0, sizeof(*entry));
            entry->dirbf                = dirbf;
            entry->dpb = &dpb_maxi_512;
            entry->csv                  = chk1;
            entry->alv                  = all1;
        }
#endif

        /* Clear disk state */
        hostbuf_valid = 0;
        hostbuf_dirty = 0;
        unalloc_count = 0;
        disk_error = 0;
        current_format_idx = 0xFF;       /* force format reload on first SELDSK */
        last_seek_disk = 0xFF;      /* force seek on first access */
    }
}
