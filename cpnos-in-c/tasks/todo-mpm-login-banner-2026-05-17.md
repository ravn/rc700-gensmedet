# Can MP/M print (or be asked for) a login banner?

**Status:** RESEARCH / TODO (question raised 2026-05-17).

## Short answer

Out of the box, no -- MP/M II's CCP doesn't have a login-banner
concept the way Unix `/etc/issue` does.  CP/NOS/CP/NET 1.2 has no
"server greeting" frame in the protocol.  But there are three
practical ways to make a banner appear after slave cold boot:

## Option A -- $$$.SUB on the slave's A: drive (CHEAPEST)

CCP auto-executes `$$$.SUB` from user 0 of the default drive at
cold boot (it's how SUBMIT.COM hands chained commands to the
next CCP cycle).  Drop a SUBMIT script with `TYPE A:WELCOME.TXT`
into `mpm-net2-1.dsk`, and the slave's first action after
NDOS COLDST will be to print `WELCOME.TXT`.

Pros: zero slave-side code, zero MP/M changes.
Cons: every slave boots with the same banner; can't include
slave-specific info (slave ID, build hash, etc.).

Plumbing:

    cpmcp mpm-net2-1.dsk welcome.txt 0:welcome.txt
    cpmcp mpm-net2-1.dsk submit.com  0:'$$$.sub'
    # ...where submit.com is the canonical CP/M SUBMIT binary
    # that takes commands from $$$.SUB.

## Option B -- MP/M's own RDOS console message

MP/M II's RDOS reads `BANNER.SYS` from drive A: at cold-boot
console init.  Predates CP/NET so the message is local to the
master.  Slaves don't see it (they're on separate consoles via
CP/NET).  Not useful for our case.

## Option C -- slave-side "post-coldstart hook" in cpnos.com

Add a CCP-replacement hook in cpnos.com that runs once after
NDOS COLDST and prints a banner including slave-specific info
(SLAVEID, locale tag, server identity per LOGIN response).
Lives in cpnos.com itself (not PROM); per-build choice.

Pros: rich content (could include "Connected to MP/M server,
4 drives mapped"); always-on.
Cons: bytes inside cpnos.com -- it's tight; need to keep the
post-load size <= 0xC80 for record-padded netboot.

## Option D -- CP/NET protocol extension

The slave could send a custom function code (e.g. 0xFE custom)
on first connect and have the master respond with a banner
string.  Requires modifying both ends (slave init.c +
master-side z80pack mpm-net2's NDOS handler).  Useful if we
want SERVER-FROM-LOGIN identity in the banner (e.g. "Connected
to: cpmsim mpm-net2-1 cpm22-1 cpm22-2").

Pros: dynamic, server-aware.
Cons: protocol extension breaks compatibility with stock MP/M
masters; only works against our patched cpmsim.

## Related question: can the slave ASK the master for a MOTD?

Yes -- via plain BDOS file I/O over CP/NET.  CP/NET 1.2 has no
dedicated "MOTD" function code, but every BDOS call passes
transparently from slave to master, so the slave can `OPEN` /
`SEQ_READ` / `CLOSE` `A:MOTD.TXT` exactly as if A: were local.
That's what Option A above relies on under the hood -- the
`TYPE A:MOTD.TXT` command in `$$$.SUB` becomes a chain of
BDOS_OPEN_FILE (15), BDOS_READ_SEQ (20), BDOS_CLOSE_FILE (16)
calls transported over CP/NET to the master.

For a *dedicated* CP/NET MOTD opcode, that would be an Option D
extension (custom function code 0x80..0xFF in the DRI-reserved
range).  Only worthwhile if MOTD has runtime content the master
needs to compute per slave (server uptime, slave count, etc.) --
otherwise A:MOTD.TXT served as a regular file is cheaper.

## Recommendation

Start with **Option A**.  It's a 30-second experiment: drop a
WELCOME.TXT + SUBMIT.COM + $$$.SUB onto the master's A: disk
and verify TYPE-style auto-execution on slave cold boot.  If the
content needs to be slave-specific later, graduate to Option C.

## When

Low priority -- the current PROM1 banner (row 0) + cpnos.img
stamp (row 2) already identify the build sufficiently for
on-bench verification.  This is a UX nicety, not a functionality
gap.
