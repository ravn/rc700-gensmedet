/* cpnos-rom SNIOS — hybrid asm+C implementation of CP/NET 1.2.
 *
 * Phase 64 (2026-05-10): the SNDMSG/RCVMSG state machines and their
 * shared helpers (SENDBY/RECVBT/NETIN/NETOUT/MSGIN/MSGOUT/SNDACK/
 * BADCKS) are written as `__naked` inline-asm functions, ported
 * byte-for-byte from the original `snios.s` (commit 0bd7515) with
 * the Phase 6 timeout-bearing-recv fix preserved.  The trivial JT
 * impls (NTWKIN/NTWKST/CNFTBL/NTWKER/NTWKBT/NTWKDN) stay in plain C
 * — they're each ~10 B and the C version is identical to the asm.
 *
 * Why the partial revert: the C state machines were paying ~370 B
 * over the original asm because the compiler couldn't share
 * register meanings across helper-call boundaries — every call
 * forced a BSS spill of any live local.  With `__naked` asm the
 * register convention is hand-rolled (D = running checksum, E =
 * byte counter, HL = msg ptr, BC = scratch) and shared across
 * callers, eliminating the spill storm.
 *
 * Phase 6 fix preserved: mid-frame byte receives use `_snios_recvbt`
 * (timeout-bearing per DRI semantics).  The original asm had a
 * separate `RECVBY` helper that busy-waited; that variant is
 * eliminated and all mid-frame recvs go through the timeout path.
 * Existing `ret c` propagation in the receiver state machine
 * handles timeout the same way as the C version's RC_RETRY.
 */

#include <stdint.h>
#include "cfgtbl.h"
#include "compiler/compat.h"

/* CFGTBL netst flags (mirror of CPNET_WIRE_PROTOCOL.md § Network status byte). */
#define CFG_NETST_ACTIVE  0x10
#define CFG_NETST_RCVERR  0x02
#define CFG_NETST_SNDERR  0x01

/* Forward declarations of the chip-specific byte transport.  Resolved
 * at link time by clang `--defsym` or SDCC `xport_aliases.asm`. */
extern void     xport_send_byte(uint8_t b) __preserves_regs(d, e);
extern uint16_t xport_recv_byte(uint16_t timeout_ticks);

/* Local scratch shared by the SNDMSG/RCVMSG state machines.  Lives
 * in BSS (zero-init); cfgtbl section absorbs the 3 bytes. */
SECTION_BSS_CFGTBL static uint16_t snios_msgadr;
SECTION_BSS_CFGTBL static uint8_t  snios_retcnt;

/* ============================================================
 *  Trivial JT impls (plain C — already as small as the asm).
 * ============================================================ */

uint8_t snios_ntwkin_impl(void) {
    cfgtbl.netst = CFG_NETST_ACTIVE;
    cfgtbl.siz = 0;
    return 0;
}

uint8_t snios_ntwkst_impl(void) {
    uint8_t status = cfgtbl.netst;
    cfgtbl.netst = (uint8_t)(status & ~(CFG_NETST_RCVERR | CFG_NETST_SNDERR));
    return status;
}

void snios_cnftbl_impl(void) __naked {
    /* Returns &cfgtbl in HL (NDOS contract; sdcccall(1) returns 16-bit
     * in DE so we need __naked to enforce HL convention). */
    ASM_VOLATILE("ld hl,_cfgtbl\n\tret");
}

void snios_ntwker_impl(void) __naked {
    /* NDOS hook for "device re-init on error" — null-impl on us, but
     * NDOS calls it with A=error-code and expects A preserved.  ret. */
    ASM_VOLATILE("ret");
}

uint8_t snios_ntwkbt_impl(void) { return 0; }

uint8_t snios_snderr1_impl(void) { return 0xFF; }

/* ERRRTN (private to the state machines): set error flag in
 * CFG_NETST (A holds the bit), call NTWKER, return 0xFF.  Reachable
 * via JP from the asm bodies. */
void snios_errrtn(void) __naked {
    ASM_VOLATILE(
        "ld   hl, _cfgtbl\n\t"
        "or   (hl)\n\t"
        "ld   (hl), a\n\t"
        "call _snios_ntwker_impl\n\t"
        "ld   a, 0xff\n\t"
        "ret\n\t"
    );
}

/* ============================================================
 *  Shared transport-byte helpers (asm).
 *  All take/return in the asm-convention (HL/D/E/A); not directly
 *  callable from regular C code without going through the state
 *  machines.
 *
 *  Register conventions inside this block:
 *    HL = message buffer pointer (preserved across all helpers)
 *    D  = running checksum / TMRETRY counter (set up by callers)
 *    E  = byte-loop counter (set up by callers)
 *    BC = scratch
 *    A  = byte being sent/received
 *    CY = error flag on receive helpers (1 = timeout)
 * ============================================================ */

/* SENDBY: send byte in A.  Preserves HL, DE. */
USED static void snios_sendby(uint8_t a) __naked {
    ASM_VOLATILE(
        "push hl\n\t"
        "push de\n\t"
        "call _xport_send_byte\n\t"
        "pop  de\n\t"
        "pop  hl\n\t"
        "ret\n\t"
    );
}

/* RECVBT: receive byte with timeout.  Returns A = byte, CY = 0 on
 * success; CY = 1 on timeout.  Preserves HL, DE.  Used everywhere
 * (the original asm RECVBY busy-wait variant is replaced — Phase 6
 * fix: mid-frame timeout now propagates via CY). */
USED static uint8_t snios_recvbt(void) __naked {
    ASM_VOLATILE(
        "push de\n\t"
        "push hl\n\t"
        "ld   hl, 0x8000\n\t"               /* RECV_TIMEOUT_TICKS */
        "call _xport_recv_byte\n\t"
        "ld   a, d\n\t"                     /* D=0 success, D=0xff timeout */
        "inc  a\n\t"                        /* Z if timeout */
        "ld   a, e\n\t"                     /* A = byte (Z preserved by ld) */
        "pop  hl\n\t"                       /* pop doesn't touch flags */
        "pop  de\n\t"
        "scf\n\t"                           /* assume timeout: CY=1 */
        "ret  z\n\t"                        /* timeout: return CY=1 */
        "or   a\n\t"                        /* success: clear CY */
        "ret\n\t"
    );
}

/* NETOUT/PREOUT: send byte C, accumulate into D (running checksum). */
USED static void snios_netout(void) __naked {
    ASM_VOLATILE(
        "_snios_preout:\n\t"                /* alias entry */
        "ld   a, d\n\t"
        "add  a, c\n\t"
        "ld   d, a\n\t"                     /* update D */
        "ld   a, c\n\t"
        "jp   _snios_sendby\n\t"            /* tail-call */
    );
}

/* NETIN: receive byte, accumulate into D.  Returns A = byte, D
 * updated, Z = (D == 0).  CY = 1 on timeout. */
USED static uint8_t snios_netin(void) __naked {
    ASM_VOLATILE(
        "call _snios_recvbt\n\t"
        "ret  c\n\t"                        /* propagate timeout */
        "ld   b, a\n\t"                     /* save byte */
        "add  a, d\n\t"
        "ld   d, a\n\t"
        "or   a\n\t"                        /* Z from D */
        "ld   a, b\n\t"
        "ret\n\t"
    );
}

/* MSGIN: receive E bytes into (HL), accumulate D, advance HL.
 * Returns CY = 1 on timeout. */
USED static void snios_msgin(void) __naked {
    ASM_VOLATILE(
        "_snios_msgin_loop:\n\t"
        "call _snios_netin\n\t"
        "ret  c\n\t"
        "ld   (hl), a\n\t"
        "inc  hl\n\t"
        "dec  e\n\t"
        "jr   nz, _snios_msgin_loop\n\t"
        "ret\n\t"
    );
}

/* MSGOUT: send preamble C then E bytes from (HL); init D=0, accumulate. */
USED static void snios_msgout(void) __naked {
    ASM_VOLATILE(
        "ld   d, 0\n\t"
        "call _snios_preout\n\t"            /* send preamble C, D += C */
        "_snios_msoLP:\n\t"
        "ld   c, (hl)\n\t"
        "inc  hl\n\t"
        "call _snios_netout\n\t"
        "dec  e\n\t"
        "jr   nz, _snios_msoLP\n\t"
        "ret\n\t"
    );
}

/* SNDACK: send ACK (preserves A across the call). */
USED static void snios_sndack(void) __naked {
    ASM_VOLATILE(
        "push af\n\t"
        "ld   a, 0x06\n\t"                  /* ACK */
        "call _snios_sendby\n\t"
        "pop  af\n\t"
        "ret\n\t"
    );
}

/* BADCKS: send NAK and return (caller treats as retry). */
USED static void snios_badcks(void) __naked {
    ASM_VOLATILE(
        "ld   a, 0x15\n\t"                  /* NAK */
        "jp   _snios_sendby\n\t"            /* tail-call */
    );
}

/* ============================================================
 *  SNDMSG state machine — direct asm port from snios.s.
 *
 *  Two entry points sharing a body via fall-through:
 *    snios_sndmsg_c       : checks ACTIVE flag, then falls through
 *    snios_sndmsg_force   : skips ACTIVE check (NTWKDN's path)
 *
 *  Entry: HL = msg ptr (sdcccall(1) 16-bit arg).
 *  Returns: A = 0 success, A = 0xFF on transport / retry-exhausted error.
 * ============================================================ */

uint8_t snios_sndmsg_c(uint8_t *msg) __naked {
    ASM_VOLATILE(
        /* ACTIVE check (asm SNDMSG entry) */
        "ld   a, (_cfgtbl)\n\t"             /* CFG_NETST */
        "and  0x10\n\t"                     /* ACTIVE */
        "jp   z, _snios_sndmsg_active_off\n\t"
        /* Fall through to the force entry (asm SNDMS0 label). */
        ".globl _snios_sndmsg_force\n\t"
        "_snios_sndmsg_force:\n\t"
        "ld   (_snios_msgadr), hl\n\t"
        /* Set SID = our slaveid in msg[2]. */
        "inc  hl\n\t"
        "inc  hl\n\t"
        "ld   a, (_cfgtbl + 1)\n\t"         /* CFG_SLAVEID */
        "ld   (hl), a\n\t"
        /* Outer retry loop: MAXRETRY frames. */
    "_snios_sndmsg_resend:\n\t"
        "ld   a, 10\n\t"                    /* MAXRETRY */
        "ld   (_snios_retcnt), a\n\t"
    "_snios_sndmsg_send:\n\t"
        "ld   hl, (_snios_msgadr)\n\t"
        /* Send ENQ. */
        "ld   a, 0x05\n\t"                  /* ENQ */
        "call _snios_sendby\n\t"
        /* Wait for ACK with TMRETRY-bound retries. */
        "ld   d, 100\n\t"                   /* TMRETRY */
    "_snios_sndmsg_enqrsp:\n\t"
        "call _snios_recvbt\n\t"
        "jr   nc, _snios_sndmsg_gotenq\n\t" /* got byte */
        "dec  d\n\t"
        "jr   nz, _snios_sndmsg_enqrsp\n\t"
        "jr   _snios_sndmsg_sndtmo\n\t"
    "_snios_sndmsg_gotenq:\n\t"
        "call _snios_chkack\n\t"            /* falls through on success */
        /* Send SOH + 5 header bytes + HCS. */
        "ld   c, 0x01\n\t"                  /* SOH */
        "ld   e, 5\n\t"
        "call _snios_msgout\n\t"            /* SOH FMT DID SID FNC SIZ, sums into D */
        "xor  a\n\t"
        "sub  d\n\t"
        "ld   c, a\n\t"
        "call _snios_netout\n\t"            /* HCS = -running_sum */
        /* Wait for header ACK. */
        "call _snios_getack\n\t"
        /* Send STX + (SIZ+1) data + ETX + CKS + EOT. */
        "dec  hl\n\t"                       /* back to SIZ field */
        "ld   e, (hl)\n\t"
        "inc  hl\n\t"
        "inc  e\n\t"                        /* 0 -> 1 byte */
        "ld   c, 0x02\n\t"                  /* STX */
        "call _snios_msgout\n\t"
        "ld   c, 0x03\n\t"                  /* ETX */
        "call _snios_preout\n\t"            /* fold into checksum */
        "xor  a\n\t"
        "sub  d\n\t"
        "ld   c, a\n\t"
        "call _snios_netout\n\t"            /* CKS */
        "ld   a, 0x04\n\t"                  /* EOT */
        "call _snios_sendby\n\t"
        /* Wait for final ACK; tail-call handles success+retry. */
        "jp   _snios_getack\n\t"
        /* GETACK: recv with retry; returns A=0 success, retries on
         * timeout/NAK by popping caller and looping at SEND. */
    "_snios_getack:\n\t"
        "call _snios_recvbt\n\t"
        "jr   c, _snios_sndmsg_sndret\n\t"  /* timeout → retry */
        /* Fall through to CHKACK. */
    "_snios_chkack:\n\t"
        "and  0x7F\n\t"
        "sub  0x06\n\t"                     /* ACK */
        "ret  z\n\t"                        /* success: A=0 */
        /* Fall through to SNDRET. */
    "_snios_sndmsg_sndret:\n\t"
        "pop  hl\n\t"                       /* discard caller return addr */
        "ld   hl, _snios_retcnt\n\t"
        "dec  (hl)\n\t"
        "jr   nz, _snios_sndmsg_send\n\t"
    "_snios_sndmsg_sndtmo:\n\t"
        "ld   a, 0x01\n\t"                  /* SNDERR */
        "jp   _snios_errrtn\n\t"
    "_snios_sndmsg_active_off:\n\t"
        "ld   a, 0xff\n\t"
        "ret\n\t"
    );
}

/* ============================================================
 *  RCVMSG state machine — direct asm port from snios.s.
 *
 *  Entry: HL = msg ptr.
 *  Returns: A = 0 success+match; A = 0xFF on error or DID-mismatch
 *           (NDOS rejects in either case).
 *
 *  Phase 6 fix: mid-frame `RECVBY` busy-wait replaced by `RECVBT`
 *  (timeout-bearing).  Existing `ret c` lines after each recv call
 *  propagate the timeout to the outer RECALL retry loop, which
 *  matches the original asm's intent.
 * ============================================================ */

uint8_t snios_rcvmsg_c(uint8_t *msg) __naked {
    ASM_VOLATILE(
        /* ACTIVE check. */
        "ld   a, (_cfgtbl)\n\t"
        "and  0x10\n\t"
        "jp   z, _snios_rcvmsg_active_off\n\t"
        /* Save msg ptr. */
        "ld   (_snios_msgadr), hl\n\t"
        /* Outer retry loop: MAXRETRY frames. */
    "_snios_rcvmsg_rercv:\n\t"
        "ld   a, 10\n\t"                    /* MAXRETRY */
        "ld   (_snios_retcnt), a\n\t"
    "_snios_rcvmsg_recall:\n\t"
        "call _snios_rcvmsg_recv\n\t"       /* may return CY on intra-frame timeout */
        "ld   hl, _snios_retcnt\n\t"
        "dec  (hl)\n\t"
        "jr   nz, _snios_rcvmsg_recall\n\t"
    "_snios_rcvmsg_rcvtmo:\n\t"
        "ld   a, 0x02\n\t"                  /* RCVERR */
        "jp   _snios_errrtn\n\t"

    "_snios_rcvmsg_recv:\n\t"
        "ld   hl, (_snios_msgadr)\n\t"
        /* Wait for ENQ with TMRETRY-bounded retries. */
        "ld   d, 100\n\t"                   /* TMRETRY */
    "_snios_rcvmsg_rcvfst:\n\t"
        "call _snios_recvbt\n\t"
        "jr   nc, _snios_rcvmsg_gotfst\n\t" /* got byte */
        "dec  d\n\t"
        "jr   nz, _snios_rcvmsg_rcvfst\n\t"
        "pop  hl\n\t"                       /* discard recall return */
        "jr   _snios_rcvmsg_rcvtmo\n\t"
    "_snios_rcvmsg_gotfst:\n\t"
        "and  0x7F\n\t"
        "cp   0x05\n\t"                     /* ENQ */
        "jr   nz, _snios_rcvmsg_recv\n\t"   /* not ENQ — keep looking */
        /* Got ENQ — send ACK. */
        "ld   a, 0x06\n\t"                  /* ACK */
        "call _snios_sendby\n\t"
        /* Receive SOH (timeout-bearing per Phase 6 fix). */
        "call _snios_recvbt\n\t"
        "ret  c\n\t"
        "and  0x7F\n\t"
        "cp   0x01\n\t"                     /* SOH */
        "ret  nz\n\t"                       /* not SOH — retry */
        "ld   d, a\n\t"                     /* init HCS = SOH */
        /* Receive 5 header bytes. */
        "ld   e, 5\n\t"
        "call _snios_msgin\n\t"
        "ret  c\n\t"
        /* Receive HCS, verify. */
        "call _snios_netin\n\t"
        "ret  c\n\t"
        "jr   nz, _snios_badcks_call\n\t"   /* checksum bad */
        /* Header OK — send ACK. */
        "call _snios_sndack\n\t"
        /* Receive STX. */
        "call _snios_recvbt\n\t"
        "ret  c\n\t"
        "and  0x7F\n\t"
        "cp   0x02\n\t"                     /* STX */
        "ret  nz\n\t"
        "ld   d, a\n\t"                     /* init CKS = STX */
        /* Get SIZ from msg[4] (HL points to msg+5 after header recv). */
        "dec  hl\n\t"
        "ld   e, (hl)\n\t"
        "inc  hl\n\t"
        "inc  e\n\t"                        /* 0 -> 1 byte */
        /* Receive (SIZ+1) data bytes. */
        "call _snios_msgin\n\t"
        "ret  c\n\t"
        /* Receive ETX, fold into CKS. */
        "call _snios_recvbt\n\t"
        "ret  c\n\t"
        "and  0x7F\n\t"
        "cp   0x03\n\t"                     /* ETX */
        "ret  nz\n\t"
        "add  a, d\n\t"
        "ld   d, a\n\t"
        /* Receive and verify CKS. */
        "call _snios_netin\n\t"
        "ret  c\n\t"
        /* Receive EOT. */
        "call _snios_recvbt\n\t"
        "ret  c\n\t"
        "and  0x7F\n\t"
        "cp   0x04\n\t"                     /* EOT */
        "ret  nz\n\t"
        "ld   a, d\n\t"
        "or   a\n\t"
        "jr   nz, _snios_badcks_call\n\t"
        /* Frame received OK — discard recall return, check DID. */
        "pop  hl\n\t"                       /* discard recall return */
        "ld   hl, (_snios_msgadr)\n\t"
        "inc  hl\n\t"                       /* -> DID */
        "ld   a, (_cfgtbl + 1)\n\t"         /* CFG_SLAVEID */
        "inc  a\n\t"                        /* 0xFF -> 0 = init mode */
        "jr   z, _snios_rcvmsg_match\n\t"
        "dec  a\n\t"
        "sub  (hl)\n\t"
        "jr   z, _snios_rcvmsg_match\n\t"
        "ld   a, 0xff\n\t"                  /* bad DID */
    "_snios_rcvmsg_match:\n\t"
        /* SNDACK preserves A; A=0 success, A=0xFF mismatch. */
        "jp   _snios_sndack\n\t"
    "_snios_badcks_call:\n\t"
        "jp   _snios_badcks\n\t"
    "_snios_rcvmsg_active_off:\n\t"
        "ld   a, 0xff\n\t"
        "ret\n\t"
    );
}

/* ============================================================
 *  NTWKDN — sends FNC=0xFE shutdown frame, bypassing ACTIVE check.
 *  Calls into snios_sndmsg_force (the post-ACTIVE entry).
 * ============================================================ */

uint8_t snios_ntwkdn_impl(void) {
    cfgtbl.msgbuf[0] = 0;       /* FMT */
    cfgtbl.msgbuf[3] = 0xFE;    /* FNC = 254 (shutdown) */
    cfgtbl.msgbuf[4] = 0;       /* SIZ */
    {
        extern uint8_t snios_sndmsg_force(uint8_t *msg);
        (void)snios_sndmsg_force(cfgtbl.msgbuf);
    }
    return 0;
}
