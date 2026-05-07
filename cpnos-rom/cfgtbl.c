/* cpnos-rom CP/NET configuration table.
 *
 * DRI CFGTBL layout (per cpnet-z80/src/snios.asm:62+):
 *   +0   NETST      Network status byte (0 = offline, 1 = online, plus error bits)
 *   +1   SLAVEID    This node's slave ID (set from RC702_SLAVEID build flag)
 *   +2   A: disk    2 bytes per drive, 16 drives total (A: .. P:), bit 7 of
 *   ...             the low byte = remote-via-network, low nibble = remote drive letter
 *   +34  console    2 bytes, bit 7 = remote console
 *   +36  list       2 bytes, bit 7 = remote list device
 *   +38  bufidx     Buffer index
 *   +39  FMT        outbound message template: 0 (request)
 *   +40  DID        outbound DID: 0 (to master)
 *   +41  SID        outbound SID: 0xFF (SNIOS initialises to our SLAVEID)
 *   +42  FNC        outbound FNC: 5 (LIST)
 *   +43  SIZ        outbound SIZ: 0
 *   +44  MSG[0]     List number (for LST:)
 *   +45..+172  MSGBUF (128-byte message buffer)
 *
 * This is a public ABI — any imported SNIOS object references it by
 * name, and the wire offsets must match the DRI specification.
 */

#include <stdint.h>
#include "cfgtbl.h"
#include "compiler/compat.h"

#ifndef RC702_SLAVEID
#define RC702_SLAVEID 0x70
#endif

/* cfgtbl goes in .scratch_bss (zero-initialised at cold boot).  The
 * non-zero fields are set at runtime by cfgtbl_init() — avoids burning
 * 170+ B of explicit zero bytes in the PROM just to spell out MSGBUF
 * and the unused upper drive slots. */
#define RESIDENT_BSS SECTION_BSS_CFGTBL

/* Drive map entry encoding (per cpndos.asm:435-451 chkdsk):
 *   byte 0 (low):  bit 7 = 1 for network drive, bits 3..0 = remote drive letter
 *   byte 1 (high): server slave ID that serves this drive
 *
 * NET_DRV(letter, srv) packs into a uint16_t LE — bit 7 of low byte
 * marks network, and the low nibble holds the remote drive letter.
 * chkdsk rotates bit 7 out and re-rotates back, then ANDs with 0x0F
 * to extract the letter, so NET_DRV('A', 0x00) uses a remote drive A
 * on server slave 0 (the master). */
#define LOCAL   0x0000
#define NET_DRV(letter, srv)  ((uint16_t)((0x80 | ((letter) - 'A')) | ((srv) << 8)))

/* struct cfgtbl moved to cfgtbl.h so netboot_mpm.c can share the
 * outbound message-frame slots as its own staging buffer. */

static_assert(sizeof(struct cfgtbl) == 210,
              "CFGTBL must be 210 B (173 DRI ABI + 37 netboot tail)");
static_assert(__builtin_offsetof(struct cfgtbl, slaveid) == 1, "SLAVEID @ +1");
static_assert(__builtin_offsetof(struct cfgtbl, console) == 34, "console @ +34");
static_assert(__builtin_offsetof(struct cfgtbl, fmt) == 39, "FMT @ +39");
static_assert(__builtin_offsetof(struct cfgtbl, sid) == 41, "SID @ +41");
static_assert(__builtin_offsetof(struct cfgtbl, msgbuf) == 45, "MSGBUF @ +45");

RESIDENT_BSS
struct cfgtbl cfgtbl;

/* Template for the contiguous slaveid + drive[0..5] block (cfgtbl
 * offsets +1..+13).  Lifted out of cfgtbl_init's per-field stores so
 * the function lowers to a single LDIR -- saves ~30 B of init code
 * versus 7 individual `ld hl,$X; ld (nn),hl` pairs.  Drives A:-D: map
 * to server master (slave 0) drives A:-D: -- NDOS's LOAD for CCP.SPR
 * uses ccpfcb (cpndos.asm:ccpfcb) which hardcodes drive byte 1 (= A:),
 * so A: must be network and must carry CCP.SPR for cold-boot CCP load.
 * E:, F: -> master I:, J: (4 MB hard disks; master XIOS exposes
 * harddisk DPHs at drive numbers 8 and 9 -- see bnkxios-net-2.mac).
 * Disk images seeded by the cpmsim/mpm-net2 launcher from
 * disks/library/mpm-net2-drive[ij].dsk. */
SECTION_INIT_RODATA
static const uint8_t cfgtbl_init_template[13] = {
    RC702_SLAVEID,                                                /* +1  slaveid */
    NET_DRV('A', 0x00) & 0xFF, (NET_DRV('A', 0x00) >> 8) & 0xFF,  /* +2  drive[0] */
    NET_DRV('B', 0x00) & 0xFF, (NET_DRV('B', 0x00) >> 8) & 0xFF,  /* +4  drive[1] */
    NET_DRV('C', 0x00) & 0xFF, (NET_DRV('C', 0x00) >> 8) & 0xFF,  /* +6  drive[2] */
    NET_DRV('D', 0x00) & 0xFF, (NET_DRV('D', 0x00) >> 8) & 0xFF,  /* +8  drive[3] */
    NET_DRV('I', 0x00) & 0xFF, (NET_DRV('I', 0x00) >> 8) & 0xFF,  /* +10 drive[4] */
    NET_DRV('J', 0x00) & 0xFF, (NET_DRV('J', 0x00) >> 8) & 0xFF,  /* +12 drive[5] */
};

/* Set the few non-zero fields.  Everything else stayed zero at BSS
 * clear.  Must run before any SNIOS call (cpnos_main calls us before
 * netboot). */
SECTION_INIT_TEXT
void cfgtbl_init(void) {
    __builtin_memcpy(&cfgtbl.slaveid, cfgtbl_init_template,
                     sizeof(cfgtbl_init_template));
    cfgtbl.sid = 0xFF;          /* SNIOS rewrites to SLAVEID at init */
    cfgtbl.fnc = 0x05;          /* LIST function */
}
