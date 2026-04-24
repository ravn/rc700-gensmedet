/* cpnos-rom CP/M disk layer — DPB + DPH types + per-drive
 * parameters for drive B: (local 8" maxi floppy).
 *
 * Layer scope:
 *   - CP/M 2.2 disk-parameter types (DPB, DPH) as the BDOS sees them
 *   - per-format constants: dpb_maxi_data, fmt_maxi_data
 *   - DPH for drive B:, with BSS-resident alloc/dir-check vectors
 *     (the actual vectors live in disk.c)
 *
 * Does NOT own:
 *   - FDC hardware access   → fdc.c / fdc.h
 *   - BIOS JT dispatch glue → resident.c (impl_*)
 *   - host-sector blocking  → disk.c (private, called from impl_read)
 */
#ifndef CPNOS_DISK_H
#define CPNOS_DISK_H

#include <stdint.h>
#include "fdc.h"

/* --- CP/M 2.2 Disk Parameter Block --------------------------------
 *
 * 15-byte struct pointed to by each DPH.  Laid out exactly per the
 * DRI CP/M 2.2 Alteration Guide — BDOS code reads these fields by
 * offset, so field order is part of the ABI.
 */
typedef struct {
    uint16_t spt;   /* sectors per track (CP/M 128B logical sectors)   */
    uint8_t  bsh;   /* block shift factor — log2(BLS / 128)            */
    uint8_t  blm;   /* block mask — (BLS / 128) - 1                    */
    uint8_t  exm;   /* extent mask — determined by BLS and DSM         */
    uint16_t dsm;   /* disk size - 1 (in allocation blocks)            */
    uint16_t drm;   /* directory entries - 1                           */
    uint8_t  al0;   /* allocation bitmap, high byte                    */
    uint8_t  al1;   /* allocation bitmap, low byte                     */
    uint16_t cks;   /* directory check-vector size                     */
    uint16_t off;   /* reserved tracks (track offset for user data)    */
} disk_parameter_block;

/* --- CP/M 2.2 Disk Parameter Header -------------------------------
 *
 * 16-byte struct returned by the BIOS's SELDSK entry point.  BDOS
 * caches the pointer and reads the fields; we must keep the alv/csv
 * arrays in BSS and large enough for the configured format.
 */
typedef struct {
    const uint8_t             *xlt;    /* sector translation table     */
    uint16_t                   sctp1;  /* BDOS scratchpad (3 words)    */
    uint16_t                   sctp2;
    uint16_t                   sctp3;
    uint8_t                   *dirbuf; /* 128-byte directory buffer    */
    const disk_parameter_block *dpb;   /* DPB pointer (this format)    */
    uint8_t                   *csv;    /* directory check vector       */
    uint8_t                   *alv;    /* allocation vector            */
} disk_parameter_header;

/* --- Public constants ---------------------------------------------
 *
 * fmt_maxi_data — µPD765 format descriptor for 8" maxi data area
 * (tracks 2-76, both sides, MFM 15x512).  Passed to fdc_read_sector.
 *
 * dpb_maxi_data — the CP/M DPB for the same format.  Derived via the
 * DISKDEF macro (see disk.c) from the same primitives rcbios uses.
 *
 * dph_b — the DPH returned by impl_seldsk for drive B:.
 */
extern const struct fdc_format           fmt_maxi_data;
extern const disk_parameter_block        dpb_maxi_data;
extern const disk_parameter_header       dph_b;

#endif /* CPNOS_DISK_H */
