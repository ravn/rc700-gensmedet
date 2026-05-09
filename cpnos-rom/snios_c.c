/* cpnos-rom SNIOS — C implementations of the trivial entry points.
 *
 * Phase 1 of #75 (asm -> C migration of DRI's SNIOS hand-port).  The
 * JT slots in snios.s / sdcc/snios.asm route to these via
 * `jp _snios_<name>_impl`; the asm bodies for NTWKIN/NTWKST/CNFTBL/
 * NTWKER/NTWKBT have been deleted.  Protocol-bearing functions
 * (SENDBY/RECVBY/RECVBT, NETOUT/NETIN/MSGOUT/MSGIN, SNDMSG/RCVMSG and
 * helpers) and NTWKDN remain in asm pending later phases — those carry
 * timing and register-convention sensitivities that warrant per-byte
 * review against DRI's reference port before translation.
 *
 * NTWKER must preserve A on return: NDOS uses A's pre-call value as
 * the error code propagated up from a failed SNDMSG/RCVMSG.  Marked
 * `__naked` so the compiler can't emit a prologue that touches A.
 */

#include <stdint.h>
#include "cfgtbl.h"
#include "compiler/compat.h"

/* CFGTBL netst flags (mirror of snios.s constants). */
#define CFG_NETST_ACTIVE  0x10
#define CFG_NETST_RCVERR  0x02
#define CFG_NETST_SNDERR  0x01

uint8_t snios_ntwkin_impl(void) {
    cfgtbl.netst = CFG_NETST_ACTIVE;
    cfgtbl.siz = 0;
    return 0;
}

uint8_t snios_ntwkst_impl(void) {
    uint8_t st = cfgtbl.netst;
    cfgtbl.netst = st & (uint8_t)~(CFG_NETST_RCVERR | CFG_NETST_SNDERR);
    return st;
}

/* CNFTBL returns the cfgtbl address.  NDOS's contract is HL=address
 * (DRI convention).  Both compilers' sdcccall(1) returns 16-bit
 * pointers in DE -- not HL -- so we hand-write the load to satisfy
 * the JT-side contract regardless of compiler return convention. */
void snios_cnftbl_impl(void) __naked {
    ASM_VOLATILE("ld hl,_cfgtbl\n\tret");
}

/* NTWKER must preserve A on entry; SDCC's optimizer otherwise aliases
 * a plain empty function to the z88dk runtime's `l_ret` (in
 * code_l_sccz80), which lives outside our resident region.  Force a
 * local `ret` via inline asm. */
void snios_ntwker_impl(void) __naked {
    ASM_VOLATILE("ret");
}

uint8_t snios_ntwkbt_impl(void) {
    return 0;
}
