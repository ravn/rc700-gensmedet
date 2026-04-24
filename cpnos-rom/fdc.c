/* cpnos-rom floppy disk controller — µPD765 primitive layer.
 *
 * See fdc.h for layer scope and public API.  Bit-level semantics of
 * every OUT byte in this file are documented in PORT_OUTPUTS.md §µPD765
 * (FDC) and §Z80 CTC / 8237 DMA where relevant.
 *
 * Extracted from rcbios-in-c/bios.c (fdc_write, fdc_read, fdc_seek,
 * fdc_sense_int and the SPECIFY call in bios_hw_init.c:200-208).
 * Rewritten here rather than copied verbatim — the rcbios version
 * uses a different HAL (`port_in/out` wrappers) and relies on a
 * global `fdc_unit_head` + `fdc_track` state which doesn't fit our
 * layering.  The primitive sequences (SPECIFY params, MSR polling
 * masks, drive-busy poll) are unchanged, because they're tied to
 * the µPD765 chip itself, not to a particular software stack.
 */

#include <stdint.h>
#include "hal.h"
#include "fdc.h"

#define RESIDENT __attribute__((section(".resident"), used))

/* --- µPD765 Main Status Register bits ------------------------------ */
/*
 * Read from PORT_FDC_STATUS.  We use these as masks when deciding
 * whether the FDC is ready for the next CPU action.
 *
 *   bit 7  RQM  — Request for Master: FDC ↔ CPU data transfer ready
 *   bit 6  DIO  — Data IO direction (1 = FDC→CPU, 0 = CPU→FDC)
 *   bit 5  NDM  — Non-DMA execution phase (unused here: we use DMA)
 *   bit 4  CB   — Command Busy (command + execution + result phase)
 *   bit 3  D3B  — drive 3 busy (seeking)
 *   bit 2  D2B  — drive 2 busy
 *   bit 1  D1B  — drive 1 busy
 *   bit 0  D0B  — drive 0 busy
 */
#define MSR_RQM       0x80
#define MSR_DIO       0x40
#define MSR_CB        0x10
#define MSR_DRV_BSY   0x0F   /* any drive seeking */
#define MSR_DRV(n)    (1u << ((n) & 3))

/* --- µPD765 command opcodes --------------------------------------- */
#define CMD_SPECIFY        0x03
#define CMD_READ_DATA      0x06   /* OR with CMD_MFM for double density */
#define CMD_RECALIBRATE    0x07
#define CMD_SENSE_INT      0x08
#define CMD_SEEK           0x0F
#define CMD_MFM            0x40   /* OR flag: MFM (double density) on READ/WRITE */

/* --- low-level RQM polling ----------------------------------------
 *
 * The FDC signals it is ready for a byte exchange by raising RQM.  DIO
 * tells us which direction: 1 means the FDC has a result byte waiting
 * for us, 0 means it is waiting to receive a command/parameter byte.
 *
 * Both polls wait for (MSR & (RQM|DIO)) to match the expected pattern:
 *   fdc_write: expect RQM=1, DIO=0 → mask value 0x80
 *   fdc_read:  expect RQM=1, DIO=1 → mask value 0xC0
 *
 * The polls are tight busy-loops — the µPD765 brings RQM up in
 * microseconds between bytes of a command/result block, so idle time
 * here is negligible compared to a full sector transfer.
 */

RESIDENT
static void fdc_write(uint8_t val) {
    while ((_port_in(PORT_FDC_STATUS) & (MSR_RQM | MSR_DIO)) != MSR_RQM)
        { }
    _port_out(PORT_FDC_DATA, val);
}

RESIDENT
static uint8_t fdc_read(void) {
    while ((_port_in(PORT_FDC_STATUS) & (MSR_RQM | MSR_DIO)) != (MSR_RQM | MSR_DIO))
        { }
    return _port_in(PORT_FDC_DATA);
}

/* --- seek completion wait -----------------------------------------
 *
 * SEEK and RECALIBRATE have no "result phase" — the FDC signals
 * completion on its INT pin, not by queueing result bytes for MSR
 * polling.  Our caller (BIOS READ) blocks on the FDC anyway, so we
 * poll the MSR's drive-busy bit for the drive we targeted instead of
 * wiring an IRQ handler.  The busy bit sets as soon as the command
 * enters execution and clears when the head settles.
 *
 * Mean wait: ~3 ms per track stepped at SRT=3 (see fdc_init comment).
 * At 4 MHz Z80 that's ~12000 clock cycles per track — the poll loop
 * is comfortably tight enough to see the transition.
 */
RESIDENT
static void fdc_wait_seek_done(uint8_t drive) {
    const uint8_t busy = MSR_DRV(drive);
    while ((_port_in(PORT_FDC_STATUS) & busy) != 0)
        { }
}

/* --- SPECIFY / init -----------------------------------------------
 *
 * SPECIFY programs the FDC's head-movement timing constants:
 *   SRT — Step Rate Time, step-to-step pulse interval
 *   HUT — Head Unload Time, automatic unload after READ/WRITE
 *   HLT — Head Load Time, delay after LOAD before R/W
 *   ND  — Non-DMA flag (0 = DMA mode, 1 = CPU polls FIFO)
 *
 * Values are rcbios's ones, validated against real hardware:
 *   0xDF  →  SRT=13 → (16-13)=3 ms between tracks
 *            HUT=15 → 15*16 = 240 ms before head unload
 *   0x28  →  HLT=20 → 20*2 = 40 ms head-load settling
 *            ND=0   → DMA mode (we'll use it for sector reads)
 *
 * Before issuing, we wait for the MSR to show no command active and
 * no drive seeking — stale state from a warm boot would otherwise
 * corrupt the SPECIFY sequence.
 */
RESIDENT
void fdc_init(void) {
    while ((_port_in(PORT_FDC_STATUS) & (MSR_CB | MSR_DRV_BSY)) != 0)
        { }
    fdc_write(CMD_SPECIFY);
    fdc_write(0xDF);   /* SRT=3ms, HUT=240ms */
    fdc_write(0x28);   /* HLT=40ms, DMA mode */
}

/* --- sense interrupt ----------------------------------------------
 *
 * SENSE INTERRUPT STATUS (0x08) returns the FDC's "what just
 * happened" status after a SEEK/RECAL completion.  Two result bytes
 * normally: ST0 (completion code) + PCN (present cylinder).  If the
 * command was flagged invalid, only ST0 is emitted — we detect that
 * via ST0's Interrupt Code field (bits 7-6):
 *
 *   IC=00  Normal termination
 *   IC=01  Abnormal — equipment check
 *   IC=10  Invalid command issued (only ST0 returned, no PCN)
 *   IC=11  Abnormal — ready signal changed state
 */
RESIDENT
uint8_t fdc_sense_int(uint8_t *pcn_out) {
    fdc_write(CMD_SENSE_INT);
    uint8_t st0 = fdc_read();
    uint8_t pcn = 0;
    if ((st0 & 0xC0) != 0x80)              /* IC != 10 → PCN follows */
        pcn = fdc_read();
    if (pcn_out) *pcn_out = pcn;
    return st0;
}

/* --- RECALIBRATE --------------------------------------------------
 *
 * Step the head toward track 0 until the drive's TRK0 sensor fires.
 * Unlike SEEK, the target cylinder is hard-wired to 0; the drive
 * issues up to 77 step pulses waiting for TRK0.  After completion
 * the FDC's PCN (Present Cylinder Number) is reset to 0 regardless
 * of where the head physically landed.
 *
 * Returns the ST0 captured by the follow-up SENSE INTERRUPT.  Caller
 * checks ST0 bit 5 (SE = Seek End) to distinguish success from a
 * drive that never found TRK0.
 */
RESIDENT
uint8_t fdc_recalibrate(uint8_t drive) {
    fdc_write(CMD_RECALIBRATE);
    fdc_write(drive & 0x03);
    fdc_wait_seek_done(drive);
    return fdc_sense_int(0);
}

/* --- SEEK ---------------------------------------------------------
 *
 * Step the head to the specified cylinder.  drive_head layout:
 *   bits 1-0  drive unit (0..3)
 *   bit   2   head select (0 = side 0, 1 = side 1)
 *   others    should be 0 (reserved)
 *
 * The FDC issues step pulses at the SPECIFY-configured SRT rate
 * until PCN == cylinder.  Multi-step distance: absolute (count
 * derived from current PCN), so consecutive SEEKs across the disk
 * are fine without intermediate RECALIBRATE.
 *
 * Returns ST0 from the follow-up SENSE INTERRUPT; SE bit indicates
 * successful arrival.
 */
RESIDENT
uint8_t fdc_seek(uint8_t drive_head, uint8_t cylinder) {
    fdc_write(CMD_SEEK);
    fdc_write(drive_head);
    fdc_write(cylinder);
    fdc_wait_seek_done(drive_head & 0x03);
    return fdc_sense_int(0);
}

/* --- DMA channel 1 setup for FDC → memory transfer ----------------
 *
 * The 8237 needs the channel masked while we reload its address and
 * word-count registers.  See PORT_OUTPUTS.md §8237 DMA for the bit
 * layout of each byte below.
 *
 *   SMSK  0x05  = set mask for ch1   (bit 2 = set, bits 1-0 = ch1)
 *   MODE  0x45  = single-transfer, increment, no-autoinit,
 *                 write-transfer (I/O→memory), ch1
 *   CLBP  0x00  = clear byte-pointer flipflop (next addr/WC write
 *                 is the low half)
 *   ADDR  lo/hi = destination RAM address
 *   WC    lo/hi = count - 1 (8237 uses N-1 encoding)
 *   SMSK  0x01  = clear mask for ch1 (bit 2 = clear, bits 1-0 = ch1)
 *                 → channel responds to the FDC's DREQ on each byte
 */
RESIDENT
static void fdc_dma_setup_read(void *dst, uint16_t count) {
    _port_out(PORT_DMA_SMSK, 0x05);
    _port_out(PORT_DMA_MODE, 0x45);
    _port_out(PORT_DMA_CLBP, 0x00);
    const uint16_t addr = (uint16_t)(uintptr_t)dst;
    _port_out(PORT_DMA_CH1_ADDR, (uint8_t)(addr & 0xFF));
    _port_out(PORT_DMA_CH1_ADDR, (uint8_t)(addr >> 8));
    const uint16_t wc = count - 1;
    _port_out(PORT_DMA_CH1_WC, (uint8_t)(wc & 0xFF));
    _port_out(PORT_DMA_CH1_WC, (uint8_t)(wc >> 8));
    _port_out(PORT_DMA_SMSK, 0x01);
}

/* --- READ DATA ----------------------------------------------------
 *
 * Read one sector via DMA.  The µPD765 READ DATA command takes 9
 * bytes in its command phase:
 *
 *   +0  cmd+MF   — 0x06, OR 0x40 for MFM (double density)
 *   +1  US,HD    — drive (bits 1-0) + head-select (bit 2)
 *   +2  C        — cylinder number
 *   +3  H        — head number (must match bit 2 of +1)
 *   +4  R        — starting sector (1-based)
 *   +5  N        — sector-size code (0=128, 1=256, 2=512, 3=1024)
 *   +6  EOT      — last sector number on track
 *   +7  GPL      — GAP3 length for this format
 *   +8  DTL      — data-length byte (ignored when N > 0; we use 0xFF)
 *
 * Execution phase: the FDC pulses DREQ for each byte; DMA ch1 moves
 * the data to RAM until the word-count expires.  Because the 8237 is
 * in DMA mode, MSR.RQM stays low throughout execution — our first
 * fdc_read() call naturally blocks until the result phase begins.
 *
 * Result phase: 7 bytes — ST0, ST1, ST2, C, H, R, N.  Must be read
 * completely or MSR.CB stays set and the next command jams.  We only
 * surface ST0 to the caller; the rest are drained and discarded.
 * (A later commit may extend the return to pass ST1/ST2 if the BIOS
 * layer needs finer error classification — for now ST0's IC field is
 * enough to distinguish success from failure.)
 */
/* Request globals — caller sets these before fdc_read_sector().  See
 * fdc.h for the rationale (avoiding a 5-arg IX frame). */
uint8_t  fdc_req_cyl;
uint8_t  fdc_req_head;
uint8_t  fdc_req_sec;
uint8_t *fdc_req_dst;

RESIDENT
uint8_t fdc_read_sector(const struct fdc_format *fmt) {
    const uint16_t size = (uint16_t)128u << fmt->n;
    fdc_dma_setup_read(fdc_req_dst, size);

    const uint8_t drive_head = (uint8_t)((fdc_req_head & 1) << 2);  /* drive 0 + head */
    const uint8_t cmd        = (uint8_t)(CMD_READ_DATA |
                                         (fmt->mfm ? CMD_MFM : 0));

    fdc_write(cmd);
    fdc_write(drive_head);
    fdc_write(fdc_req_cyl);
    fdc_write(fdc_req_head);
    fdc_write(fdc_req_sec);
    fdc_write(fmt->n);
    fdc_write(fmt->eot);
    fdc_write(fmt->gap);
    fdc_write(0xFF);                /* DTL — ignored for N > 0 */

    /* Drain 7 result bytes.  Only ST0 is propagated. */
    const uint8_t st0 = fdc_read();
    for (uint8_t i = 0; i < 6; i++)
        (void)fdc_read();
    return st0;
}
