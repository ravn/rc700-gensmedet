/* Payload integrity checksum placeholder.
 *
 * Reserves the last 2 bytes of the .payload section (see payload.ld).
 * The link-time value is 0xFFFF; cpnos-build/patch_payload_checksum.py
 * overwrites it post-link with the 16-bit additive sum of the
 * preceding payload bytes.  At runtime the relocator (relocator.c)
 * recomputes the sum after copying the payload to RAM and compares.
 * Mismatch -> LDIR "BAD CHECKSUM" to display memory and halt.
 *
 * Catches:
 *   - prom1.ic65 missing (rom path empty / rc702.cpp missing
 *     ROM_LOAD_OPTIONAL): payload_b reads as 0xFF padding.
 *   - bit rot in either PROM.
 *   - mismatched prom0.ic66 / prom1.ic65 versions.
 *
 * Without this check the failure mode was a silent hang at PC=0x0039
 * — the resident BIOS jumping into garbage.
 */

#include <stdint.h>
#include "compiler/compat.h"

SECTION_PAYLOAD_CKSUM
static const uint16_t payload_checksum_placeholder = 0xFFFF;
