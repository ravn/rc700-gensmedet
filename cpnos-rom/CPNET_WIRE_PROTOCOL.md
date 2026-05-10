# CP/NET Wire Protocol — cpnos-rom slave ⇄ z80pack mpm-net2 master

This document specifies the byte-level protocol that the cpnos-rom CP/NOS slave
speaks to the MP/M II + CP/NET master running under z80pack `cpmsim`.  It is
the **authoritative reference for any rewrite of `cpnos-rom/snios_c.c`**:
the slave-side implementation must produce these exact bytes in this exact
order to interop with the master.

The protocol is Digital Research's **CP/NET 1.2 binary serial framing**,
unchanged since 1980 except for the layer it runs over.

## Authoritative sources cross-checked

| Side | File | Origin |
|---|---|---|
| **Master** | `z80pack/cpmsim/srcmpm/netwrkif-0.asm` | DRI 1980, modified Sep 2014 by Udo Munk for Z80SIM |
| **DRI reference slave** | `cpnet-z80/src/ser-dri/snios.asm` | DRI 1980-1982, "Revised October 5, 1982" |
| **cpnos-rom slave (current)** | `cpnos-rom/snios.s` + `snios_c.c` | Hand port of `rc700-gensmedet/cpnet/snios.asm` |

The master + DRI reference agree byte-for-byte on the protocol described below.
cpnos-rom's slave deviates in one place (mid-frame busy-wait vs.
timeout-bearing receive — see [§ Slave-side deviations](#slave-side-deviations)).

## Transport layer

The wire is a raw byte stream (no framing/escaping at the transport level).
Three transports are wired in cpnos-rom:

| TRANSPORT= | Slave-side I/O | Path to master |
|---|---|---|
| `pio-irq` | RC702 PIO-B (IRQ-driven) | MAME `bus/rs232/cpnet_bridge.cpp` → TCP socket → z80pack `cpmsim` console 3 (TCP 4002) |
| `sio` | RC702 SIO-A (polled) | MAME `null_modem -bitb1 socket.127.0.0.1:4002` → TCP socket → same |
| `proxy` | (legacy, retired Phase 51A) | — |

The transport is byte-pass-through; no framing or flow-control bytes are
inserted by the transport itself.  All retry / timeout / checksum logic
lives in the protocol layer specified below.

## Encoding modes

The master supports two byte-level encoding modes per slave, selected at
master configuration time by `BinaryASCII[slave#]` in netwrkif-0.asm:

- **Binary (8-bit)** — `BinaryASCII[n] = 0xFF`. Each protocol byte is one wire
  byte.  **Default for z80sim mpm-net2; the only mode cpnos-rom supports.**
- **ASCII (7-bit hex)** — `BinaryASCII[n] = 0x00`. Each protocol byte is two
  hex digits (4 wire bytes per protocol byte after `++`/`--` framing).
  Used by durgadas311's `cpnet-z80/src/serial/snios.asm` variant.  cpnos-rom
  does NOT implement this mode.

In binary mode, the protocol bytes themselves are 8-bit (e.g. data payload
can be any byte 0x00..0xFF), but **control-byte comparisons are 7-bit** —
both master and slave mask received bytes with `0x7F` before comparing
against `SOH`/`STX`/`ETX`/`EOT`/`ENQ`/`ACK`.  This survives a transport
that strips parity bits.  Checksum accumulation is over the **raw 8-bit
byte** (no masking), per both `Netin`/`Msgin` on both sides.

## Control-byte equates (identical on both sides)

```
SOH  0x01    Start of Header
STX  0x02    Start of Data
ETX  0x03    End of Data
EOT  0x04    End of Transmission
ENQ  0x05    Enquire
ACK  0x06    Acknowledge
NAK  0x15    Negative Acknowledge
```

## Message frame layout

The CP/NET frame is the standard DRI message buffer — 5-byte header followed
by `SIZ+1` data bytes:

| Offset | Field | Meaning |
|---:|---|---|
| 0 | FMT | Message format (0 = request from slave, 1 = response from master) |
| 1 | DID | Destination ID — 0 for master, slave# for slave |
| 2 | SID | Source ID — slave's own ID (slave fills this in unconditionally before send; see [§ SID rewriting](#sid-rewriting)) |
| 3 | FNC | Function code — usually a CP/M BDOS function number; 0xFE = network shutdown; 0xFF = init/get-node-ID |
| 4 | SIZ | Data length, encoded as `actual_length - 1`.  `SIZ=0` → 1 data byte, `SIZ=255` → 256 data bytes |
| 5..(5+SIZ) | DAT | Data payload, exactly `SIZ+1` bytes |

The header sub-block `[FMT, DID, SID, FNC, SIZ]` is **always 5 bytes**.

## Send protocol (slave → master)

Send sequence on the wire (verified against `netwrkif-0.asm:907-960` and
`cpnos-rom/snios.s`):

```
slave:   ENQ                                       (1 byte)
master:  ACK                                       (1 byte; slave waits with TMRETRY-bounded retry)
slave:   SOH  FMT  DID  SID  FNC  SIZ  HCS         (7 bytes)
master:  ACK                                       (1 byte; slave waits, single Charin-with-WDT)
slave:   STX  DAT[0]  ...  DAT[SIZ]  ETX  CKS  EOT (5 + (SIZ+1) bytes)
master:  ACK                                       (1 byte; slave waits, single Charin-with-WDT)
```

SOH counts toward HCS (HCS = -(SOH + FMT + DID + SID + FNC + SIZ) & 0xFF).
STX and ETX count toward CKS (CKS = -(STX + DAT[0..SIZ] + ETX) & 0xFF).
The terminating `EOT` is sent raw — NOT included in CKS; it's a frame
delimiter, not a payload byte.

If any of the three master-ACK waits times out, returns NAK, or returns
any non-ACK byte: the slave **discards the in-progress frame and retries
the entire send from `ENQ`**.  Up to `MAXRETRY = 10` whole-frame retries.
On exhaustion, the slave sets `cfgtbl.netst |= SNDERR`, calls `NTWKER`
(device-recovery hook, no-op in cpnos-rom), and returns `A = 0xFF`.

Bit 7 of received ACK bytes is masked off before comparison (`A & 0x7F == ACK`).

### SID rewriting

Before the first `ENQ`, the slave overwrites `msg[2]` (SID) with
`cfgtbl.slaveid`.  This guarantees the slave's own ID is always correct
on the wire even if a caller passed a stale `msg[2]`.  Per `SNDMSG` in
`snios.s`:

```
SNDMS0:
    ld   h, b
    ld   l, c
    ld   (MSGADR), hl
    ld   a, (_cfgtbl + CFG_SLAVEID)
    inc  bc
    inc  bc
    ld   (bc), a       ; msg[2] = SLAVEID
```

The master's `sndmsg` does NOT do this — the master is configured per-slave
and trusts its own `chariotbl` routing for SID.

## Receive protocol (slave ← master)

Receive sequence on the wire (verified against `netwrkif-0.asm:1013-1090`):

```
master:  ENQ                                       (1 byte; slave waits with TMRETRY-bounded retry,
                                                    UNCONDITIONAL bail to RCVERR if exhausted)
slave:   ACK                                       (1 byte)
master:  SOH  FMT  DID  SID  FNC  SIZ  HCS         (7 bytes)
slave:   ACK     if HCS valid (sum-check: HCS + (SOH+FMT+DID+SID+FNC+SIZ) == 0 mod 256)
slave:   NAK     if HCS invalid → master retries the frame
master:  STX  DAT[0]  ...  DAT[SIZ]  ETX  CKS  EOT (5 + (SIZ+1) bytes)
slave:   ACK     if CKS valid AND ETX/EOT correctly bracket
slave:   NAK     if CKS invalid → master retries
slave:   ACK with A=0xFF return code if DID mismatch (see below)
```

After successful frame receive, the slave checks DID:

- If `cfgtbl.slaveid == 0xFF` (init mode, accept-any): slave returns A=0 (success).
- If `msg[1] (DID) == cfgtbl.slaveid`: slave returns A=0 (success).
- If `msg[1] != cfgtbl.slaveid`: slave still sends `ACK` (so the master
  doesn't retransmit) but returns `A = 0xFF` so NDOS rejects the message.

Inner-frame errors (timeout mid-frame, bad SOH/STX/ETX/EOT marker, etc.):
slave returns up to `MAXRETRY = 10` whole-frame retries.  On exhaustion:
`cfgtbl.netst |= RCVERR`, `NTWKER` called, return `A = 0xFF`.

Initial-ENQ-wait timeout (the slave waited `TMRETRY = 100` `RECVBT` cycles
and never saw a non-timeout byte): bail **immediately** to `RCVERR` —
DO NOT exhaust the `MAXRETRY` budget.  This makes the slave fail fast when
no master is responding at all (vs. when the master is responding but
sending malformed frames).

## Checksums (both directions)

Both sides use the same construction:

```
HCS = (uint8_t)(-(SOH + FMT + DID + SID + FNC + SIZ));
CKS = (uint8_t)(-(STX + DAT[0] + DAT[1] + ... + DAT[SIZ] + ETX));
```

Equivalently: the running 8-bit sum of all participant bytes plus the
checksum byte should be 0.  This is a weak error detector — designed for
RS-232 noise filtering, not adversarial integrity.

The slave verifies a received checksum by **continuing to accumulate the
running sum into the checksum byte itself**, then testing against zero:

```c
uint8_t hcs = SOH;
for (int i = 0; i < 5; i++) hcs += msg[i];   /* accumulate over header */
hcs += received_hcs_byte;                     /* fold in HCS byte itself */
if (hcs != 0) /* corrupt */;
```

The master uses the same idiom (`Netin: ... add d; mov d,a; ret` then
`mov a,d; ora a; jnz sendNAK` per `netwrkif-0.asm:1066-1071`).

**Bit 7 is NOT masked during checksum accumulation** on either side.
The full 8-bit byte is summed.  Bit 7 IS masked when checking against
control-byte equates (e.g. `b & 0x7F == ACK`).

## Retry semantics — master vs. slave

There is an asymmetry in **per-byte timeout handling**:

| Side | Mechanism |
|---|---|
| **Master** | Per-byte: `Charin` returns CY=1 on watchdog-timer (`WatchDog`) timeout.  Single attempt per byte; failure escapes via `pop d` to retry the whole `send` / `receive`.  No nested retry inside one byte's wait. |
| **Slave** | Initial-ENQ wait: `TMRETRY = 100` polls of `RECVBT` (each `RECVBT` has its own `RECV_TIMEOUT_TICKS = 0x8000` internal timeout).  Mid-frame bytes: see [§ Slave-side deviations](#slave-side-deviations). |

Both sides agree on `MAXRETRY = 10` for whole-frame retries.

Inter-character timing on the master side: `delaycounts[slave#]` (1-4 in
`netwrkif-0.asm`, units of 0.5ms via `dly`) inserts a brief delay between
each transmitted byte.  Slave RX must tolerate up to ~2ms gaps between
adjacent header bytes within one frame.  This is well within
`RECV_TIMEOUT_TICKS` so it doesn't normally show up as a failure.

## Special frames

Two FNC values are dispatched specially by the cpmsim-side serial-port
proxy and never reach the actual MP/M CP/NET server (per
`cpnet-z80/md/SER-DRI.md`):

### Initialize / get node ID (FNC = 0xFF)

Slave sends:
```
FMT=0  DID=0  SID=0  FNC=0xFF  SIZ=0  DAT=[0]
```

Master responds:
```
FMT=1  DID=NN  SID=0  FNC=0xFF  SIZ=0  DAT=[0]    where NN = slave's assigned node ID
```

After this exchange the slave knows its assigned ID and writes it to
`cfgtbl.slaveid`.  Subsequent SID rewriting on send uses this value.

cpnos-rom's `cfgtbl_init` hard-codes `RC702_SLAVEID = 0x01` (set at build
time by the Makefile) rather than running this exchange dynamically.

### Network shutdown (FNC = 0xFE)

Slave sends:
```
FMT=0  DID=0  SID=slaveid  FNC=0xFE  SIZ=0  DAT=[0]
```

Master does NOT respond — the master's serial-port handler closes the socket
and releases resources.  The slave-side `NTWKDN` calls
`_snios_sndmsg_force` (bypassing the ACTIVE check) to send this frame even
when not currently logged in.

## Slave-side deviations

cpnos-rom's `snios.s` deviates from the DRI reference (`ser-dri/snios.asm`)
in one place that matters for the rewrite:

**Mid-frame byte receive uses busy-wait instead of timeout-bearing.**

The DRI reference has one receive primitive (`recvby`) that returns CY=1 on
a single-attempt timeout.  Mid-frame, DRI's `RCVMSG` uses this same
`recvby` and propagates timeouts up via `ret c` — exiting the frame
parser cleanly so the outer `receive` retry loop can try again.

cpnos-rom split this into two primitives:
- `RECVBT` (= DRI's `recvby`, returns CY on timeout) — used only for the
  initial ENQ wait.
- `RECVBY` (busy-wait, retries forever inside its own loop until a byte
  arrives) — used for all mid-frame bytes.

The `ret c` checks in cpnos-rom's `RCVMSG` after `call RECVBY` are
**dead code** — `RECVBY` never sets CY because it never returns on
timeout.  It hangs forever.

Practical effect: if the master pauses mid-frame (e.g. system hung,
network glitch, host process suspended), the cpnos-rom slave hangs
forever waiting for the next byte.  The DRI reference would time out
and bail to the outer retry, eventually giving up via `RCVERR`.

This deviation has not surfaced in `polypascal-test` against z80pack
`mpm-net2` because the host is reliable — once a frame starts, it
finishes.  But it is a latent bug that would matter on real hardware
or under load.

**The C rewrite (Phase 5+6 of #75) should restore DRI's semantics**
(timeout-bearing recv for all frame bytes) since the user's stated goal
is "an accurate spec for the wire-protocol for talking to the mp/m
server".  The master is fine with either behaviour; the deviation is
purely a robustness regression on the slave side.

## Network status byte (`cfgtbl.netst`)

```
ACTIVE  0b0001_0000   slave is logged in on the network
RCVERR  0b0000_0010   error in last received message (set by RCVMSG on retry exhaustion)
SNDERR  0b0000_0001   unable to send last message (set by SNDMSG on retry exhaustion)
```

Master uses the same `Networkstatus` byte but stores the same bit values
(per `netwrkif-0.asm:618`).

`NTWKIN` sets ACTIVE on cold init.  `NTWKST` returns the current netst
byte and clears the two error bits as a side effect (so consecutive
`NTWKST` calls return the latched-since-last-read error state).
`NTWKDN` does NOT clear ACTIVE — the slave is "shutdown" but its
cfgtbl still says ACTIVE; this matches DRI behaviour and master expects
the slave to log back in for any further traffic.

## Unsupported / out-of-scope

cpnos-rom does NOT implement:

- 7-bit ASCII (hex-encoded) mode — see [§ Encoding modes](#encoding-modes).
- Multi-slave operation on one master link (we are slave #1, single-link).
- Master-initiated unsolicited messages (NDOS pull-only model).
- CP/NET 1.5 extensions (different `FNC` values, not relevant for
  CP/NET 1.2-class master like z80pack mpm-net2).

## Capturing real wire bytes

For a verified concrete example of the bytes on the wire, capture a
polypascal-test session via the Phase 48 trace harness:

```
make cpnos-polypascal-test COMPILER=clang TRANSPORT=pio-irq \
     MAME_LUA=cpnos-rom/mame_minimal_trace.lua
```

The Lua hooks tap the byte-transport entry points (`_xport_send_byte`,
`_xport_recv_byte`) and dump every byte that crosses with direction
markers and timestamps.  Compare consecutive frames to verify SOH/STX/
ETX/EOT positions, DID/SID values, and HCS/CKS arithmetic against this
spec.

Hand-computing example wire bytes inline in this doc is forbidden by
`feedback_no_mental_arithmetic_in_fixtures` (HARD rule) — past sessions
learned the hard way that an off-by-one in a worked example becomes
load-bearing and contradicts the actual-running code.

## See also

- `rc700-gensmedet/cpnet/snios.asm` — the original zmac-syntax port of DRI's
  binary serial protocol (commit `fa028b6` "Add CP/NET test infrastructure").
- `cpnos-rom/snios.s` — current clang GAS port (commit `15a3368`).
- `cpnos-rom/sdcc/snios.asm` — current SDCC z88dk port.
- `cpnos-rom/snios_c.c` — Phases 1-4 C ports of the SNIOS housekeeping
  (#75); Phases 5-6 (SNDMSG/RCVMSG state machines) will be plain C
  implementations of THIS spec, not byte-for-byte ports of the asm.
- `z80pack/cpmsim/srcmpm/netwrkif-0.asm` — master-side DRI reference,
  authoritative for what bytes the slave must produce.
- `cpnet-z80/src/ser-dri/snios.asm` — DRI's reference slave, structurally
  parallel to the master.
- `cpnet-z80/md/SER-DRI.md` — durgadas311's notes on running this
  protocol over the `CpnetSerialServer.jar` proxy (alternative master,
  not used in cpnos-rom).
