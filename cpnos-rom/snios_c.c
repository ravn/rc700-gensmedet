/* cpnos-rom SNIOS — plain C implementation of the CP/NET 1.2 binary
 * serial wire protocol (Phases 1-6 of #75 complete).
 *
 * The wire-byte sequences in `try_send_frame` and `try_recv_frame`
 * below are an implementation of the spec in `CPNET_WIRE_PROTOCOL.md`
 * (this directory) -- NOT a translation of the historical asm
 * `snios.s`.  Bytes on the wire are byte-identical to what the master
 * (z80pack mpm-net2's `netwrkif-0.asm`) expects; control flow uses
 * structured C (for-loops, early returns) instead of the asm's
 * pop-discard-caller-return tricks.
 *
 * One slave-side deviation from the prior asm is fixed in this
 * rewrite: mid-frame byte receive now uses the timeout-bearing
 * `xport_recv_byte(RECV_TIMEOUT_TICKS)`, matching DRI's reference
 * (`cpnet-z80/src/ser-dri/snios.asm`).  The prior asm used busy-wait
 * `RECVBY` mid-frame, which would hang forever if the master paused
 * mid-frame.  The C version bails cleanly via the outer retry loop.
 *
 * What stays in asm (`snios.s` + `sdcc/snios.asm`) after this rewrite:
 *   (a) the JT (8 x 3-byte `jp` slots, ABI-fixed to NDOS at 0xED33)
 *   (b) two BC->HL calling-convention bridges for the SNDMSG/RCVMSG
 *       JT slots (NDOS passes msg ptr in BC; sdcccall(1) takes HL)
 * Everything else has moved here.
 *
 * Style note: functions whose contract cannot be expressed in
 * sdcccall(1) C -- pointer return in HL not DE (CNFTBL); register
 * conventions for the JT entries -- are written as `__naked` with
 * `ASM_VOLATILE` bodies that match the original asm byte-for-byte.
 *
 * NTWKER must preserve A on entry: NDOS uses A's pre-call value as
 * the error code propagated up from a failed SNDMSG/RCVMSG.
 */

#include <stdint.h>
#include "cfgtbl.h"
#include "compiler/compat.h"
#include "transport.h"      /* TRANSPORT_TIMEOUT == 0xFFFF */

/* CFGTBL netst flags (mirror of CPNET_WIRE_PROTOCOL.md § Network status byte). */
#define CFG_NETST_ACTIVE  0x10
#define CFG_NETST_RCVERR  0x02
#define CFG_NETST_SNDERR  0x01

/* CP/NET 1.2 control bytes (CPNET_WIRE_PROTOCOL.md § Control-byte equates). */
#define SOH 0x01
#define STX 0x02
#define ETX 0x03
#define EOT 0x04
#define ENQ 0x05
#define ACK 0x06
#define NAK 0x15

/* Retry / timeout parameters (CPNET_WIRE_PROTOCOL.md § Retry semantics). */
#define MAXRETRY            10      /* whole-frame retries on either side */
#define TMRETRY             100     /* slave's polls of RECVBT during initial ENQ wait */
#define RECV_TIMEOUT_TICKS  0x8000  /* per-RECVBT inner-timeout passed to xport_recv_byte */

/* Forward declarations of the chip-specific byte transport.  Resolved at
 * link time by clang `--defsym` or SDCC `xport_aliases.asm`.
 *
 * `__preserves_regs(d, e)` on xport_send_byte: verified by inspection
 * of the SDCC asm output (sdcc/audit/transport_pio.s) that
 * transport_pio_send_byte never writes D or E in either path (PIO
 * already-output or PIO state-change).  Lets SDCC skip push/pop DE
 * around xport_send_byte calls in the state-machine loops.  Clang
 * ignores the attribute (compat.h `#define __preserves_regs(...)`). */
extern void xport_send_byte(uint8_t b) __preserves_regs(d, e);
extern uint16_t xport_recv_byte(uint16_t timeout_ticks);

/* ============================================================
 * SNIOS JT entry points.  Reached from NDOS via the JT slots in
 * snios.s / sdcc/snios.asm (3-byte `jp _snios_<name>_impl`).
 * ============================================================ */

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

/* CNFTBL: NDOS expects HL=cfgtbl on return.  Both compilers' sdcccall(1)
 * returns 16-bit pointers in DE -- not HL -- so we hand-write the load. */
void snios_cnftbl_impl(void) __naked {
    ASM_VOLATILE("ld hl,_cfgtbl\n\tret");
}

/* NTWKER: must preserve A.  Empty C body would let SDCC alias the symbol
 * to z88dk's `l_ret`; force a local `ret` via inline asm. */
void snios_ntwker_impl(void) __naked {
    ASM_VOLATILE("ret");
}

uint8_t snios_ntwkbt_impl(void) {
    return 0;
}

uint8_t snios_snderr1_impl(void) {
    return 0xFF;
}

uint8_t snios_errrtn_impl(uint8_t err_bit) {
    cfgtbl.netst |= err_bit;
    snios_ntwker_impl();
    return 0xFF;
}

/* ============================================================
 * Wire-protocol state machines.  Implements
 * CPNET_WIRE_PROTOCOL.md § Send protocol and § Receive protocol.
 * ============================================================ */

/* recv_byte_t: receive one byte with timeout.  Returns 0..255 on
 * success, 0x100 on timeout.  Single uint16_t return so caller can do
 * one branch on the high byte (compiles to `ld a,d; or a; jr nz,...`
 * on sdcccall(1)). */
static inline uint16_t recv_byte_t(void) {
    return xport_recv_byte(RECV_TIMEOUT_TICKS);
}

/* try_send_frame: one full attempt at sending a frame.
 * Returns 0 on success, 1 on retryable failure (caller retries
 * MAXRETRY times).  Wire spec: CPNET_WIRE_PROTOCOL.md § Send protocol. */
static uint8_t try_send_frame(uint8_t *msg) {
    uint16_t r;

    /* (1) ENQ; (2) wait ACK with TMRETRY-bounded inner retry */
    xport_send_byte(ENQ);
    {
        uint8_t t = TMRETRY;
        do {
            r = recv_byte_t();
            if (r != TRANSPORT_TIMEOUT) goto got_first_ack;
        } while (--t);
        return 1;
    got_first_ack:
        if (((uint8_t)r & 0x7F) != ACK) return 1;
    }

    /* (3) send SOH + 5 header bytes + HCS, accumulating into hcs.
     * Pointer-walking is tighter than indexed access on Z80. */
    {
        uint8_t hcs = SOH;
        uint8_t *p = msg;
        uint8_t i = 5;
        xport_send_byte(SOH);
        do {
            uint8_t b = *p++;
            hcs += b;
            xport_send_byte(b);
        } while (--i);
        xport_send_byte((uint8_t)-hcs);
    }

    /* (4) wait header-ACK (single RECVBT, no inner retry) */
    r = recv_byte_t();
    if (r >= 0x100) return 1;
    if (((uint8_t)r & 0x7F) != ACK) return 1;

    /* (5) send STX + (SIZ+1) data bytes + ETX + CKS + EOT.
     * Loop runs (SIZ+1) iterations, possibly 256 -- use do-while
     * with k as countdown so a single uint8_t handles the full range. */
    {
        uint8_t cks = STX;
        uint8_t *p = msg + 5;
        uint8_t k = msg[4];     /* SIZ */
        xport_send_byte(STX);
        do {
            uint8_t b = *p++;
            cks += b;
            xport_send_byte(b);
        } while (k--);          /* runs SIZ+1 times (k counts down 0..0xFF) */
        cks += ETX;
        xport_send_byte(ETX);
        xport_send_byte((uint8_t)-cks);
        xport_send_byte(EOT);
    }

    /* (6) wait final ACK */
    r = recv_byte_t();
    if (r >= 0x100) return 1;
    if (((uint8_t)r & 0x7F) != ACK) return 1;

    return 0;
}

/* snios_sndmsg_force: bypass the cfgtbl.netst.ACTIVE check.  Used by
 * NTWKDN to send the FNC=0xFE shutdown frame even when the slave is
 * not currently logged in.
 *
 * Per CPNET_WIRE_PROTOCOL.md § SID rewriting, overwrite msg[2] with
 * cfgtbl.slaveid before the first ENQ. */
uint8_t snios_sndmsg_force(uint8_t *msg) {
    uint8_t retry = MAXRETRY;
    msg[2] = cfgtbl.slaveid;

    do {
        if (try_send_frame(msg) == 0) return 0;
    } while (--retry);

    cfgtbl.netst |= CFG_NETST_SNDERR;
    snios_ntwker_impl();
    return 0xFF;
}

/* snios_sndmsg_c: public C entry, with ACTIVE-flag gate.
 * Reached from NDOS via the JT bridge `_snios_sndmsg_jt`. */
uint8_t snios_sndmsg_c(uint8_t *msg) {
    if (!(cfgtbl.netst & CFG_NETST_ACTIVE)) return 0xFF;
    return snios_sndmsg_force(msg);
}

/* try_recv_frame: one full attempt at receiving a frame.
 *
 * Return values (encoded as int because three states):
 *    0    = success, DID matched our SLAVEID (or slaveid==0xFF init mode)
 *   -1    = success, frame received OK but DID mismatch -- still ACKed,
 *          slave returns 0xFF to NDOS so it rejects
 *    1    = intra-frame error (timeout, bad checksum, missing marker);
 *          caller retries up to MAXRETRY times
 *    2    = initial-ENQ wait exhausted; caller bails immediately to
 *          RCVERR (CPNET_WIRE_PROTOCOL.md § Receive protocol).
 *
 * This is where the prior cpnos-rom slave's deviation is fixed:
 * mid-frame byte receives use timeout-bearing xport_recv_byte (same
 * as DRI's reference), not the busy-wait `RECVBY` the asm version
 * had.  If the master pauses mid-frame, the slave bails cleanly via
 * the outer retry instead of hanging forever.
 */
/* try_recv_frame return values are encoded as uint8_t (smaller than int):
 *   RC_OK_MATCH    = 0    success, DID matched
 *   RC_RETRY       = 1    intra-frame failure, caller retries
 *   RC_BAIL        = 2    initial-ENQ timeout, caller bails immediately
 *   RC_OK_MISMATCH = 3    success but DID mismatch -- ACKed, NDOS rejects
 */
#define RC_OK_MATCH    0
#define RC_RETRY       1
#define RC_BAIL        2
#define RC_OK_MISMATCH 3

static uint8_t try_recv_frame(uint8_t *msg) {
    uint16_t r;

    /* (1) wait for ENQ.  Non-ENQ bytes reset the wait window
     * (matches asm RCVFST -> RECV).  Exhaustion = unconditional bail. */
    {
        uint8_t t = TMRETRY;
        while (1) {
            r = recv_byte_t();
            if (r < 0x100) {
                if (((uint8_t)r & 0x7F) == ENQ) break;
                t = TMRETRY;
                continue;
            }
            if (--t == 0) return RC_BAIL;
        }
    }
    xport_send_byte(ACK);

    /* (2) receive SOH (timeout-bearing per DRI spec). */
    r = recv_byte_t();
    if (r >= 0x100) return RC_RETRY;
    if (((uint8_t)r & 0x7F) != SOH) return RC_RETRY;

    /* (3) receive 5 header bytes, accumulate HCS init=SOH. */
    {
        uint8_t hcs = SOH;
        uint8_t *p = msg;
        uint8_t i = 5;
        do {
            r = recv_byte_t();
            if (r >= 0x100) return RC_RETRY;
            *p = (uint8_t)r;
            hcs += *p++;
        } while (--i);

        /* (4) receive HCS byte; verify */
        r = recv_byte_t();
        if (r >= 0x100) return RC_RETRY;
        hcs += (uint8_t)r;
        if (hcs != 0) {
            xport_send_byte(NAK);
            return RC_RETRY;
        }
    }
    xport_send_byte(ACK);

    /* (5) receive STX */
    r = recv_byte_t();
    if (r >= 0x100) return RC_RETRY;
    if (((uint8_t)r & 0x7F) != STX) return RC_RETRY;

    /* (6) receive (SIZ+1) data bytes, accumulate CKS init=STX. */
    {
        uint8_t cks = STX;
        uint8_t *p = msg + 5;
        uint8_t k = msg[4];     /* SIZ */
        do {
            r = recv_byte_t();
            if (r >= 0x100) return RC_RETRY;
            *p = (uint8_t)r;
            cks += *p++;
        } while (k--);

        /* (7) receive ETX, fold into CKS */
        r = recv_byte_t();
        if (r >= 0x100) return RC_RETRY;
        {
            uint8_t b = (uint8_t)r;
            if ((b & 0x7F) != ETX) return RC_RETRY;
            cks += b;
        }

        /* (8) receive CKS byte; verify */
        r = recv_byte_t();
        if (r >= 0x100) return RC_RETRY;
        cks += (uint8_t)r;
        if (cks != 0) {
            xport_send_byte(NAK);
            return RC_RETRY;
        }
    }

    /* (9) receive EOT */
    r = recv_byte_t();
    if (r >= 0x100) return RC_RETRY;
    if (((uint8_t)r & 0x7F) != EOT) return RC_RETRY;

    /* (10) DID check; ACK regardless. */
    {
        uint8_t sid_plus_one = (uint8_t)(cfgtbl.slaveid + 1);
        uint8_t result = RC_OK_MATCH;
        if (sid_plus_one != 0 && msg[1] != cfgtbl.slaveid) {
            result = RC_OK_MISMATCH;
        }
        xport_send_byte(ACK);
        return result;
    }
}

/* snios_rcvmsg_c: public C entry, with ACTIVE-flag gate.
 * Reached from NDOS via the JT bridge `_snios_rcvmsg_jt`.
 *
 * Outer retry loop: try_recv_frame is called up to MAXRETRY times.
 * Initial-ENQ-wait exhaustion (return value 2) bails immediately
 * without consuming further retries -- the slave fails fast when no
 * master is responding at all. */
uint8_t snios_rcvmsg_c(uint8_t *msg) {
    uint8_t retry = MAXRETRY;
    if (!(cfgtbl.netst & CFG_NETST_ACTIVE)) return 0xFF;

    do {
        uint8_t rc = try_recv_frame(msg);
        if (rc == RC_OK_MATCH)    return 0;
        if (rc == RC_OK_MISMATCH) return 0xFF;
        if (rc == RC_BAIL)        break;
        /* RC_RETRY: intra-frame error, retry */
    } while (--retry);

    cfgtbl.netst |= CFG_NETST_RCVERR;
    snios_ntwker_impl();
    return 0xFF;
}

/* ============================================================
 * NTWKDN -- network shutdown.  Builds the FNC=0xFE frame in
 * cfgtbl.msgbuf and force-sends it (bypassing the ACTIVE check).
 *
 * Note: per CPNET_WIRE_PROTOCOL.md § Special FNC values, our
 * actual master (z80pack mpm-net2) rejects FNC=0xFE as out-of-range
 * (server.asm validates FNC < netend == 76).  The frame goes out;
 * the master ACKs the wire dance but takes no shutdown action.
 * NTWKDN returns 0 regardless, matching the asm version's
 * `xor a; ret` after the SNDMS0 call.
 * ============================================================ */
uint8_t snios_ntwkdn_impl(void) {
    cfgtbl.msgbuf[0] = 0;       /* FMT */
    cfgtbl.msgbuf[3] = 0xFE;    /* FNC = 254 (shutdown) */
    cfgtbl.msgbuf[4] = 0;       /* SIZ */
    snios_sndmsg_force(cfgtbl.msgbuf);  /* result discarded */
    return 0;
}
