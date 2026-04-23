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

#endif /* CPNOS_FDC_H */
