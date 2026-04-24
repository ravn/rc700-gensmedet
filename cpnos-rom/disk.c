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

/* --- BSS-resident scratch for drive B: ----------------------------
 *
 * alv (allocation vector): ceil((dsm + 1) / 8) = ceil(450 / 8) = 57 B.
 *   BDOS marks block k allocated by setting bit (k & 7) of
 *   alv[k >> 3].  Zero-initialised at cold boot by .scratch_bss
 *   and gradually populated as BDOS scans the directory.
 *
 * csv (directory check vector): cks bytes (= 32) — one byte per 4
 *   directory entries.  BDOS recomputes each entry's hash on every
 *   directory read; a mismatch flags "media change", used to reset
 *   cached state if a disk is swapped underneath.
 *
 * dirbuf: 128-byte directory buffer.  One BDOS buffer shared across
 *   all drives; it stages the most-recently-read directory sector.
 */
static uint8_t alv_b[57];
static uint8_t csv_b[32];
static uint8_t dirbuf[128];

/* --- Sector translation table -------------------------------------
 *
 * CP/M's DPH.xlt maps a "logical" CP/M sector index (0..SPT-1) to
 * its physical sector number on the track, applying a skew so that
 * sequential logical reads end up reading sectors with an interleave
 * pattern the drive mechanics can keep up with.
 *
 * With 15 physical sectors/track/side and skew 4, rcbios's
 * xlt_maxi_512 gives the sequence:
 *   0 4 8 12 1 5 9 13 2 6 10 14 3 7 11
 *
 * Our format is 120 CP/M sectors per track (15 phys × 4 CP/M-per-phys
 * × 2 sides).  The host-sector-blocking layer (next commit) takes
 * the post-xlt CP/M sector number and splits it into (physical-
 * sector, byte-offset-within-sector, side).  The xlt only needs to
 * describe the skew across one side's worth of CP/M sectors.
 *
 * Kept as a 120-entry table.  Entries are 1-based (CP/M convention,
 * BDOS adds the BDOS-SETSEC offset internally).
 *
 * Placeholder for now: identity translation.  The real skew table
 * lands in the blocking-layer commit where it's paired with the
 * deblock math — easier to validate both together.
 */
static const uint8_t xlt_maxi_data[120] = {
    1,   2,   3,   4,   5,   6,   7,   8,   9,  10,
   11,  12,  13,  14,  15,  16,  17,  18,  19,  20,
   21,  22,  23,  24,  25,  26,  27,  28,  29,  30,
   31,  32,  33,  34,  35,  36,  37,  38,  39,  40,
   41,  42,  43,  44,  45,  46,  47,  48,  49,  50,
   51,  52,  53,  54,  55,  56,  57,  58,  59,  60,
   61,  62,  63,  64,  65,  66,  67,  68,  69,  70,
   71,  72,  73,  74,  75,  76,  77,  78,  79,  80,
   81,  82,  83,  84,  85,  86,  87,  88,  89,  90,
   91,  92,  93,  94,  95,  96,  97,  98,  99, 100,
  101, 102, 103, 104, 105, 106, 107, 108, 109, 110,
  111, 112, 113, 114, 115, 116, 117, 118, 119, 120,
};

/* --- DPH for drive B: ---------------------------------------------
 *
 * Single instance — drive B: is the only local floppy.  SELDSK
 * returns a pointer to this for drive index 1; drive index 0 (A:)
 * stays a network drive handled by NDOS as before.
 */
RESIDENT
const disk_parameter_header dph_b = {
    .xlt    = xlt_maxi_data,
    .sctp1  = 0,
    .sctp2  = 0,
    .sctp3  = 0,
    .dirbuf = dirbuf,
    .dpb    = &dpb_maxi_data,
    .csv    = csv_b,
    .alv    = alv_b,
};
