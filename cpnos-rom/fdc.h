/* cpnos-rom floppy disk controller — public API.
 *
 * Layer: µPD765 primitives.  Extracted from rcbios-in-c/bios.c and
 * rewritten for clarity; see PORT_OUTPUTS.md §µPD765 for the bit-level
 * semantics of each command byte.
 *
 * This layer owns:
 *   - MSR polling (fdc_write/fdc_read)
 *   - init (SPECIFY)
 *   - head positioning (RECALIBRATE, SEEK)
 *   - SENSE INTERRUPT STATUS for seek completion
 *
 * It does NOT own:
 *   - DMA setup (caller's job — comes in a later commit)
 *   - READ DATA / sector I/O (comes after DMA)
 *   - BIOS integration (DPH/DPB/SELDSK glue comes last)
 *
 * Blocking model: all calls poll MSR bits synchronously.  No
 * interrupts are armed — the completion wait for SEEK/RECAL is a
 * busy-loop on MSR's DRV_BSY[n] bit.  The floppy path is the only
 * caller that cares, and it already blocks the mainline — polling
 * for a few ms is simpler than threading IRQ state through.
 */
#ifndef CPNOS_FDC_H
#define CPNOS_FDC_H

#include <stdint.h>

/* ================ one-shot init ================
 * Waits for the FDC to be idle, then issues SPECIFY with values
 * matching rcbios (step-rate 3 ms, head-unload 240 ms, head-load
 * 40 ms, DMA mode).  Call once at cold boot before any other FDC
 * operation. */
void fdc_init(void);

/* ================ head positioning ================
 *
 * fdc_recalibrate(drive):
 *   Step the drive's head to track 0 and reset the FDC's internal
 *   cylinder counter.  Drive is 0..3 (bits 1-0 of the drive/head
 *   select byte; head is implicit = 0).  Blocks until the FDC
 *   signals completion (DRV_BSY[drive] drops).  Afterwards the
 *   internal PCN equals 0 and the next SEEK is measured from track 0.
 *   Returns: the ST0 byte captured by the follow-up SENSE INTERRUPT
 *   (caller can inspect for SE = 0x20 indicating "seek end").
 *
 * fdc_seek(drive_head, cylinder):
 *   Step the head to the given cylinder.  drive_head packs drive
 *   (bits 1-0) + head-select (bit 2) per µPD765 convention.  Blocks
 *   as recalibrate does.
 */
uint8_t fdc_recalibrate(uint8_t drive);
uint8_t fdc_seek(uint8_t drive_head, uint8_t cylinder);

/* ================ sense interrupt ================
 * Retrieve ST0 + PCN after a SEEK/RECALIBRATE completes.  Returns
 * ST0; writes PCN through the pointer if non-null.
 *
 * The FDC returns 2 result bytes unless the command was flagged
 * invalid (ST0 IC field = 0b11), in which case only ST0 is emitted.
 * We handle both — PCN is set to 0 when the command was invalid.
 */
uint8_t fdc_sense_int(uint8_t *pcn_out);

/* ================ sector read ================
 *
 * Per-track geometry descriptor.  The RC702 8" maxi format uses one
 * format on side 0 of track 0 (FM 26x128), another on side 1 of
 * track 0 (MFM 26x256), and a third on every other track (MFM 15x512).
 * Callers supply the appropriate format instance for the target
 * track+side; this layer doesn't know which format goes where.
 */
struct fdc_format {
    uint8_t mfm;    /* 0 = FM (single density), 1 = MFM (double density) */
    uint8_t n;      /* sector-size code: 0=128, 1=256, 2=512, 3=1024 bytes */
    uint8_t eot;    /* End Of Track — last sector number (1-based) */
    uint8_t gap;    /* GAP3 length in bytes (inter-sector gap) */
};

/* Read one physical sector into `dst`.  Drive is hard-coded to 0
 * — the RC702 only wires the first µPD765 drive-select line, and
 * we only expose drive B: in CP/M.
 *
 * `head` selects physical side (0 or 1).  `sector` is 1-based per
 * the µPD765 convention.  `fmt` must match the physical format of
 * the target track+side or the READ DATA operation fails with a
 * No-Data error (ST1 bit 2).
 *
 * Returns ST0.  On clean completion ST0's IC field (bits 7-6) = 00.
 * The DMA channel must already have been set up; we handle that
 * internally, so `dst` can be any RAM address in range for the
 * transfer size (128 << fmt->n bytes).
 */
uint8_t fdc_read_sector(uint8_t cyl, uint8_t head, uint8_t sector,
                        void *dst, const struct fdc_format *fmt);

#endif /* CPNOS_FDC_H */
