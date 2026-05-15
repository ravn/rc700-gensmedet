/* cpnos-rom CP/NET configuration table -- shared by SNIOS and netboot.
 *
 * The DRI ABI (per cpnet-z80/src/snios.asm:62+) defines the layout
 * through MSGBUF (offset +172).  A trailing `netboot_tail[]` is a
 * cpnos-rom extension that lets netboot_mpm reuse the same buffer
 * as its 171-byte READ-SEQ response staging area: starting at
 * `cfgtbl.fmt` (+39), msg[0..170] runs to +209 -- 37 bytes past
 * the DRI MSGBUF end.  Saves ~163 B BSS by eliminating a separate
 * `msg[200]` static in netboot.
 */
#ifndef CPNOS_CFGTBL_H
#define CPNOS_CFGTBL_H

#include <stdint.h>

struct cfgtbl {
    uint8_t  netst;            /* +0   network status */
    uint8_t  slaveid;          /* +1   our slave ID */
    uint16_t drive[16];        /* +2..+33  A: .. P: drive map */
    uint16_t console;          /* +34  console redirection */
    uint16_t list;             /* +36  list redirection */
    uint8_t  bufidx;           /* +38  buffer index */
    uint8_t  fmt;              /* +39  outbound FMT (=msg[0]) */
    uint8_t  did;              /* +40  outbound DID */
    uint8_t  sid;              /* +41  outbound SID */
    uint8_t  fnc;              /* +42  outbound FNC */
    uint8_t  siz;              /* +43  outbound SIZ */
    uint8_t  msg0;             /* +44  list number / first DAT byte */
    uint8_t  msgbuf[128];      /* +45..+172 DRI MSGBUF */
    uint8_t  netboot_tail[37]; /* +173..+209 cpnos-rom netboot scratch */
};

extern struct cfgtbl cfgtbl;

#endif
