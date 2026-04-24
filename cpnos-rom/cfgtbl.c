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

#ifndef RC702_SLAVEID
#define RC702_SLAVEID 0x70
#endif

/* cfgtbl goes in .scratch_bss (zero-initialised at cold boot).  The
 * non-zero fields are set at runtime by cfgtbl_init() — avoids burning
 * 170+ B of explicit zero bytes in the PROM just to spell out MSGBUF
 * and the unused upper drive slots. */
#define RESIDENT_BSS __attribute__((section(".bss.cfgtbl"), used))

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

struct cfgtbl {
    uint8_t  netst;                /* +0 */
    uint8_t  slaveid;              /* +1 */
    uint16_t drive[16];            /* +2  A: .. P: */
    uint16_t console;              /* +34 */
    uint16_t list;                 /* +36 */
    uint8_t  bufidx;               /* +38 */
    uint8_t  fmt;                  /* +39 */
    uint8_t  did;                  /* +40 */
    uint8_t  sid;                  /* +41 */
    uint8_t  fnc;                  /* +42 */
    uint8_t  siz;                  /* +43 */
    uint8_t  msg0;                 /* +44 list number */
    uint8_t  msgbuf[128];          /* +45 */
};

static_assert(sizeof(struct cfgtbl) == 173, "CFGTBL layout must be 173 bytes");
static_assert(__builtin_offsetof(struct cfgtbl, slaveid) == 1, "SLAVEID @ +1");
static_assert(__builtin_offsetof(struct cfgtbl, console) == 34, "console @ +34");
static_assert(__builtin_offsetof(struct cfgtbl, fmt) == 39, "FMT @ +39");
static_assert(__builtin_offsetof(struct cfgtbl, sid) == 41, "SID @ +41");
static_assert(__builtin_offsetof(struct cfgtbl, msgbuf) == 45, "MSGBUF @ +45");

RESIDENT_BSS
struct cfgtbl cfgtbl;

/* Set the few non-zero fields.  Everything else stayed zero at BSS
 * clear.  Must run before any SNIOS call (cpnos_main calls us before
 * netboot). */
void cfgtbl_init(void) {
    cfgtbl.slaveid = RC702_SLAVEID;
    /* Drive A: is network (the master's A: is where cpnos.com, CCP,
     * NDOS, etc. live — netboot picks from CDISK=0 by default).
     * Drive B: is LOCAL (our 8" maxi floppy, handled by impl_seldsk
     * returning &dph_b).  C: and D: also network so cpnet tools
     * (PIPNET, LOGIN, ...) keep working.
     *
     * LOCAL = 0x0000 — NDOS's chkdsk sees bit 7 clear and passes the
     * SELDSK through to our BIOS.  NET_DRV has bit 7 set. */
    cfgtbl.drive[0] = NET_DRV('A', 0x00);
    cfgtbl.drive[1] = LOCAL;
    cfgtbl.drive[2] = NET_DRV('C', 0x00);
    cfgtbl.drive[3] = NET_DRV('D', 0x00);
    cfgtbl.sid = 0xFF;          /* SNIOS rewrites to SLAVEID at init */
    cfgtbl.fnc = 0x05;          /* LIST function */
}
