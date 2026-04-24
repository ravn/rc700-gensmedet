/* cpnos-rom CP/M disk layer — 8" maxi drive B: parameters.
 *
 * This file owns the CP/M disk-parameter constants and the BSS-
 * resident alloc/dir-check vectors for drive B:.  Nothing here
 * talks to the FDC directly; that's fdc.c's job.  Nothing here is
 * a BIOS JT target; that's resident.c's job.  Host-sector blocking
 * (the 512 B cache + deblocking math) will land in a follow-up
 * commit and live in this file.
 *
 * DPB field derivation borrowed verbatim from rcbios-in-c/bios.c
 * — the DISKDEF macro there computes all 10 DPB fields from eight
 * primitives (physical_spt, sector_size, sides, bls, dks, dir,
 * removable, ofs) per the CP/M 2.2 Alteration Guide.  We use the
 * single 8"-DSDD-data-area instance and nothing else; the macro is
 * kept intact for copy-paste fidelity, so future format additions
 * here stay identical to rcbios's derivations.
 */

#include <stdint.h>
#include "disk.h"
#include "fdc.h"

#define RESIDENT __attribute__((section(".resident"), used))

/* --- µPD765 format descriptor for 8" maxi data tracks -------------
 *
 * Tracks 2..76, both sides, uniform MFM 15 sectors × 512 bytes.
 * Track 0 (mixed density FM+MFM) is intentionally not modelled —
 * CP/M with OFF=2 never touches it, so the drive can be used for
 * reading data-area files without mixed-density support.
 *
 *   mfm = 1   → double density (CMD_MFM flag OR'd into READ DATA)
 *   n   = 2   → 512-byte sectors (128 << 2)
 *   eot = 15  → 15 sectors per track per side (1..15)
 *   gap = 0x1B → inter-sector GAP3, standard 8" MFM value
 *
 * Values cross-checked against rcbios-in-c/autoload-in-c's
 * eot_gap3_table entries for maxi/N=2/side-1.
 */
const struct fdc_format fmt_maxi_data = {
    .mfm = 1,
    .n   = 2,
    .eot = 15,
    .gap = 0x1B,
};

/* --- CP/M 2.2 DPB derivation macro (verbatim from rcbios-in-c) ----
 *
 * DISKDEF(physical_spt, sector_size, sides, bls, dks, dir,
 *         removable, ofs) computes the 10 DPB fields exactly per
 * the CP/M 2.2 Alteration Guide.
 *
 * Keep this macro byte-for-byte in sync with rcbios — that way any
 * future format we add (e.g. 5.25" mini for a Phase-B variant)
 * derives identical values without re-deriving by hand.
 */
#define DDF_BSH(bls) \
    ((bls) == 1024  ? 3 : \
     (bls) == 2048  ? 4 : \
     (bls) == 4096  ? 5 : \
     (bls) == 8192  ? 6 : \
     (bls) == 16384 ? 7 : 0xFF)

#define DDF_EXM(bls, dks) \
    ((bls) == 1024  ? 0 : \
     (bls) == 2048  ? ((dks) <= 256 ? 1 : 0) : \
     (bls) == 4096  ? ((dks) <= 256 ? 3 : 1) : \
     (bls) == 8192  ? ((dks) <= 256 ? 7 : 3) : \
     (bls) == 16384 ? ((dks) <= 256 ? 15 : 7) : 0xFF)

#define DDF_DIR_BLKS(dir, bls) (((dir) * 32 + (bls) - 1) / (bls))

#define DDF_AL_BITS(dir, bls) \
    ((uint16_t)(0xFFFFu - (0xFFFFu >> DDF_DIR_BLKS(dir, bls))))
#define DDF_AL0(dir, bls)     ((uint8_t)(DDF_AL_BITS(dir, bls) >> 8))
#define DDF_AL1(dir, bls)     ((uint8_t)(DDF_AL_BITS(dir, bls) & 0xFF))

#define DISKDEF(physical_spt, sector_size, sides, bls, dks, dir, removable, ofs) { \
    .spt = (uint16_t)((physical_spt) * ((sector_size)/128) * (sides)),             \
    .bsh = DDF_BSH(bls),                                                           \
    .blm = (uint8_t)((bls)/128 - 1),                                               \
    .exm = DDF_EXM(bls, dks),                                                      \
    .dsm = (uint16_t)((dks) - 1),                                                  \
    .drm = (uint16_t)((dir) - 1),                                                  \
    .al0 = DDF_AL0(dir, bls),                                                      \
    .al1 = DDF_AL1(dir, bls),                                                      \
    .cks = (uint16_t)((removable) ? (dir)/4 : 0),                                  \
    .off = (uint16_t)(ofs),                                                        \
}

/* --- DPB for drive B: (8" maxi DSDD data area) --------------------
 *
 * Primitives (same as rcbios's dpb_maxi_512):
 *   physical_spt = 15    — 15 physical sectors per track per side
 *   sector_size  = 512   — 512-byte physical sectors (MFM)
 *   sides        = 2     — double sided
 *   bls          = 2048  — 2 KB CP/M allocation blocks
 *   dks          = 450   — 450 blocks total = 900 KB user data
 *   dir          = 128   — 128 directory entries
 *   removable    = 1     — enable directory check vector
 *   ofs          = 2     — skip 2 reserved tracks (track 0 + 1)
 *
 * Derived (for reference, in case the macro changes):
 *   spt = 15 * 4 * 2 = 120    (CP/M 128-byte sectors per track)
 *   bsh = 4, blm = 15         (2 KB block)
 *   exm = 0                   (BLS=2048, dks=450 > 256)
 *   dsm = 449, drm = 127
 *   al0 = 0xC0, al1 = 0x00    (top 2 bits = 2 dir blocks)
 *   cks = 32, off = 2
 */
const disk_parameter_block dpb_maxi_data =
    DISKDEF(15, 512, 2, 2048, 450, 128, 1, 2);

/* --- BSS for drive B: ---------------------------------------------
 *
 * alv (allocation vector): ceil((dsm + 1) / 8) = ceil(450 / 8) = 57 B.
 *   BDOS marks block k allocated by setting bit (k & 7) of
 *   alv[k >> 3].  Populated during SELDSK's directory scan.
 *
 * csv (directory check vector): cks bytes (= 32) — one byte per 4
 *   directory entries.  BDOS recomputes each entry's hash on every
 *   directory read; a mismatch flags "media change".
 *
 * dirbuf: 128-byte directory buffer, BDOS-owned shared staging area.
 *
 * All three placed in the `.disk_bss` section so payload.ld routes
 * them to the DISKBSS region (0xEC40..0xECC0), not the main SCRATCH
 * region which is already tight against the IVT ceiling at 0xEC00.
 */
#define DISKBSS __attribute__((section(".disk_bss")))

static DISKBSS uint8_t alv_b[57];
static DISKBSS uint8_t csv_b[32];
static DISKBSS uint8_t dirbuf[128];

/* --- Sector translation table -------------------------------------
 *
 * The classic 15-sector skew-4 pattern (rcbios's xlt_maxi_512 — one
 * side's worth of physical sectors).  Matches the 8" DSDD MFM layout
 * on real RC702 hardware.
 *
 *   physical sector number for CP/M-sector-within-side index 0..14
 *   produced by the CP/M skew algorithm with stride 4, modulo 15:
 *
 *   idx :  0  1  2  3  4  5  6  7  8  9 10 11 12 13 14
 *   phys:  1  5  9 13  2  6 10 14  3  7 11 15  4  8 12
 *
 * Used by the host-sector-blocking layer (next commit) after the
 * CP/M sector has been split into (side, sector-within-side) —
 * NOT plumbed through DPH.xlt, which is NULL so BDOS skips its
 * SECTRAN hook entirely.
 *
 * Exposed for impl_read via disk.h.  15 entries, not 120 — the
 * deblock layer folds to a sector-within-side index before lookup.
 */
const uint8_t xlt_maxi_side[15] = {
    1,  5,  9, 13,  2,  6, 10, 14,  3,  7, 11, 15,  4,  8, 12,
};

/* --- DPH for drive B: ---------------------------------------------
 *
 * Single instance — drive B: is the only local floppy.  SELDSK
 * returns a pointer to this for drive index 1; drive index 0 (A:)
 * stays a network drive handled by NDOS.
 *
 * xlt = NULL tells BDOS "no SECTRAN call needed"; the skew in
 * xlt_maxi_side is applied inside impl_read where the deblock math
 * already produces the sector-within-side index we need.
 */
RESIDENT
const disk_parameter_header dph_b = {
    .xlt    = (const uint8_t *)0,
    .sctp1  = 0,
    .sctp2  = 0,
    .sctp3  = 0,
    .dirbuf = dirbuf,
    .dpb    = &dpb_maxi_data,
    .csv    = csv_b,
    .alv    = alv_b,
};
