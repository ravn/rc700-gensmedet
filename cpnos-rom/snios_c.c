/* cpnos-rom SNIOS — C implementations of the SNIOS body.
 *
 * Phases 1, 2, 3 of #75 (asm -> C migration of DRI's SNIOS hand-port).
 * The remaining asm in snios.s / sdcc/snios.asm holds only:
 *   (a) the JT (8 x 3-byte `jp` slots, ABI-fixed to NDOS at 0xED33)
 *   (b) the calling-convention bridges _snios_sndmsg_c, _snios_rcvmsg_c,
 *       _snios_sndmsg_force (HL <-> BC, sdcccall(1) <-> SNDMSG's BC arg)
 *   (c) the protocol state machines SNDMSG / RCVMSG and their internal
 *       helpers (NETOUT/NETIN/MSGOUT/MSGIN, ENQRSP/GOTENQ/CHKACK/GETACK,
 *       SNDACK/BADCKS, RECV/RCVFST/GOTFST, etc.) -- these stay in asm
 *       until Phases 4 + 5 + 6 rewrite them in plain C.
 *
 * Style note (per the user-stated principle "as much C as possible,
 * with tiny naked inline-asm-in-c that implements the abi"): functions
 * whose contract cannot be expressed in sdcccall(1) C -- pointer return
 * in HL not DE (CNFTBL); register-preservation contracts that survive
 * across multiple calls (SENDBY/RECVBY/RECVBT preserving HL+DE for the
 * SNDMSG/RCVMSG state machines that hold the msg pointer in HL); CY-flag
 * returns (RECVBT) -- are written as `__naked` with `ASM_VOLATILE` bodies
 * that match the original asm byte-for-byte.  The .c source is the
 * source of truth; the asm body is documentation of what the compiler
 * cannot express directly.
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

/* Forward declarations of the chip-specific byte transport.  These
 * symbols are resolved at link time by either:
 *   - clang: `--defsym _xport_send_byte=_transport_pio_send_byte` etc.
 *     (cpnos-rom/Makefile clang link line)
 *   - SDCC : the auto-generated `xport_aliases.asm` (a 6-byte JP-trampoline
 *     pair) that lives in RESIDENT_CODE.
 * The declarations are needed so SDCC's z80asm output contains EXTERN
 * directives matching the inline-asm symbol references below. */
extern void xport_send_byte(uint8_t b);
extern uint8_t xport_recv_byte(uint16_t timeout_ticks);

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

/* SENDBY -- send byte (in A) via the chip-specific transport.  Asm
 * callers (SNDMSG/RCVMSG and friends) rely on HL and DE being
 * preserved across the call, so we save and restore them around the
 * underlying `_xport_send_byte` invocation.  Declared `void(void)`
 * because the byte arg lives in A by ABI -- invisible to C; clang's
 * naked attribute forbids `(void)b;`-style parameter swallowing. */
void snios_sendby(void) __naked {
    ASM_VOLATILE(
        "push hl\n\t"
        "push de\n\t"
        "call _xport_send_byte\n\t"   /* arg already in A per sdcccall(1) */
        "pop de\n\t"
        "pop hl\n\t"
        "ret"
    );
}

/* RECVBY -- busy-wait receive (no timeout).  Returns A = byte, CY clear.
 * Preserves HL, DE.  Loops re-arming `_xport_recv_byte` with
 * HL=0xFFFF (max ticks) until the chip returns DE != 0xFFFF.
 * Declared `void` rather than `uint8_t` because the byte-in-A return
 * is invisible to C and adding a fake `return X` to silence
 * -Wreturn-type would conflict with clang's "naked functions cannot
 * have C statements" documentation.  Asm callers don't care; future
 * C callers (Phase 5+ state machines) can add a parallel prototype
 * declaring the uint8_t return -- linker doesn't enforce types. */
void snios_recvby(void) __naked {
    ASM_VOLATILE(
        "push hl\n\t"
        "push de\n"
        "_snios_recvby_loop:\n\t"
        "ld hl, 0xFFFF\n\t"           /* max timeout per call */
        "call _xport_recv_byte\n\t"
        "ld a, d\n\t"
        "inc a\n\t"                   /* D=0xFF -> A=0 (Z=1, retry); D=0 -> A=1 (Z=0) */
        "jr z, _snios_recvby_loop\n\t"
        "ld a, e\n\t"                 /* got byte */
        "pop de\n\t"
        "pop hl\n\t"
        "or a\n\t"                    /* clear carry */
        "ret"
    );
}

/* RECVBT -- receive byte with finite timeout.  Returns A = byte;
 * CY clear on success, CY set on timeout.  Preserves HL, DE.  Used
 * by the SNDMSG/RCVMSG retry loops to bound wait time per attempt.
 * Declared `void` (see RECVBY's note above). */
void snios_recvbt(void) __naked {
    ASM_VOLATILE(
        "push de\n\t"
        "push hl\n\t"
        "ld hl, 0x8000\n\t"           /* RECV_TIMEOUT_TICKS */
        "call _xport_recv_byte\n\t"
        "ld a, d\n\t"                 /* D=0xFF on timeout */
        "inc a\n\t"                   /* Z=1 if timeout */
        "ld a, e\n\t"                 /* A=byte; ld preserves Z */
        "pop hl\n\t"                  /* pop preserves flags */
        "pop de\n\t"
        "scf\n\t"                     /* assume timeout: CY=1 */
        "ret z\n\t"                   /* timeout: return with CY set */
        "or a\n\t"                    /* success: clear CY */
        "ret"
    );
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
