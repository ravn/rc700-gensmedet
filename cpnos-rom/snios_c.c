/* cpnos-rom SNIOS — C implementations of non-protocol entry points.
 *
 * Phase 1 + 2 of #75 (asm -> C migration of DRI's SNIOS hand-port).
 * JT slots in snios.s / sdcc/snios.asm route to these via
 * `jp _snios_<name>_impl`; the asm bodies for NTWKIN/NTWKST/CNFTBL/
 * NTWKER/NTWKBT (Phase 1) and NTWKDN/ERRRTN/SNDERR1 (Phase 2) have
 * been deleted.  Protocol-bearing functions (SENDBY/RECVBY/RECVBT,
 * NETOUT/NETIN/MSGOUT/MSGIN, SNDMSG/RCVMSG and helpers) remain in asm
 * pending later phases — those carry HL/DE preservation contracts,
 * D-checksum-state-passing, and CY-flag returns that are not natively
 * expressible in sdcccall(1) C.
 *
 * NTWKER must preserve A on entry: NDOS uses A's pre-call value as
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

/* SNDERR1 -- "not active" return path used by SNDMSG/RCVMSG when
 * cfgtbl.netst lacks the ACTIVE flag.  Returns 0xFF unconditionally. */
uint8_t snios_snderr1_impl(void) {
    return 0xFF;
}

/* ERRRTN -- timeout/error return path.  Sets the error bit (passed
 * in `err_bit`, typically RCVERR or SNDERR) into cfgtbl.netst, calls
 * the device-recovery hook NTWKER (currently a no-op stub), and
 * returns 0xFF.  Asm callers reach this via `jp _snios_errrtn_impl`
 * with the error bit already in A (sdcccall(1) 8-bit arg convention). */
uint8_t snios_errrtn_impl(uint8_t err_bit) {
    cfgtbl.netst |= err_bit;
    snios_ntwker_impl();
    return 0xFF;
}

/* `_snios_sndmsg_force` is an asm-side bridge in snios.s / sdcc/snios.asm:
 * takes msg pointer in HL (sdcccall(1)), copies HL->BC, and tail-jumps
 * to SNDMS0 (the body of SNDMSG that bypasses the cfgtbl.netst.ACTIVE
 * check).  We declare it here so NTWKDN's C implementation can call it. */
extern uint8_t snios_sndmsg_force(uint8_t *msg);

/* NTWKDN -- network shutdown.  Builds a CP/NET frame in cfgtbl.msgbuf
 * with FNC=0xFE (shutdown) and sends it via the bypass entry point
 * (so shutdown works even from a non-ACTIVE state).  Always returns 0;
 * the asm version's xor-a-then-ret discarded SNDMSG's success/error
 * code. */
uint8_t snios_ntwkdn_impl(void) {
    cfgtbl.msgbuf[0] = 0;       /* FMT */
    cfgtbl.msgbuf[3] = 0xFE;    /* FNC = 254 (shutdown) */
    cfgtbl.msgbuf[4] = 0;       /* SIZ */
    snios_sndmsg_force(cfgtbl.msgbuf);  /* result discarded */
    return 0;
}
