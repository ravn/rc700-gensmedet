# CP/NET architecture — Clapp 1983 notes

A focused summary of the genuinely useful bits of:

> **Clapp, George H.** "An Analysis of CP/NET." *Proceedings of the
> 1983 ACM SIGSMALL symposium on Personal and small computers*
> (SIGSMALL '83), pp. 117–124. ACM, December 1983.
> DOI: [10.1145/800219.806658](https://dl.acm.org/doi/10.1145/800219.806658)

The byte-level protocol in this project's `CPNET_WIRE_PROTOCOL.md` is
deeper than Clapp's data-link sketch and authoritative — read that
first.  This doc records the **architectural framing** (CP/NET vs the
ISO OSI reference model) and a handful of Clapp's design observations
that are useful when reasoning about why our slave looks the way it
does, and that the byte-level doc deliberately doesn't cover.

## What the paper is

A contemporaneous (1983) academic analysis of Digital Research's
CP/NET 1.2, mapping its software modules onto the ISO OSI 7-layer
reference model.  Clapp's stated goal is to support CP/NET over UNIX
servers (which is why he focuses on the CP/M-80 *requester* side and
ignores the MP/M II *server* side — for him the server's
implementation is irrelevant).  That requester-side focus matches our
own interests: cpnos-in-c is a requester.

## OSI mapping (Clapp's Figure 11)

```
        OSI layer            CP/NET module
        -----------------    -------------------------------
        Application          CCP, CPNETLDR, MAIL, LOCAL,
                               NETWORK    (application progs)
        Presentation     ┐
        Session          ┘   NDOS
        Transport        ┐
        Network          │   SNIOS  (extends the
        Data-link        ┘    "communication subnet"
        Physical                upward into transport)
```

Two things worth noticing:

1. **NDOS straddles presentation + session, not just one layer.**
   The presentation work is "convert a CP/M BDOS-style system call
   into a CP/NET message frame, and vice versa" (since pre-existing
   CP/M-80 applications have no concept of messages).  The session
   work is "manage the logical request↔response pairing with the
   server" — including LOGIN / LOGOFF.

2. **SNIOS is everything below NDOS down to (but not including) the
   physical layer.**  Clapp explicitly notes that DRI pushed the
   transport-layer responsibility *down* into SNIOS too, which is
   architecturally unusual — most OSI mappings put transport above
   the communication subnet, not inside it.

   Practical consequence for our slave: any flow control / framing /
   error recovery / multi-hop routing has to live in `snios_c.c` (or
   in `transport_*.c` below it), because there is no module *above*
   SNIOS that could provide it.

## Memory layout — CP/NET vs CP/NOS

Clapp's reference 64 K layout (CP/M-80 + CP/NET, with BDOS still
present for local disk):

```
            CP/M-80          CP/NET
            ----------       -----------
            BIOS    4.00K    BIOS    4.00K
            BDOS    3.50K    BDOS    3.50K   ← still loaded for local resources
                             SNIOS   0.75K
                             NDOS    3.00K
            CCP              CCP
            TPA    56.25K    TPA    52.50K   ← 3.75K cost of going networked
            Base    0.25K    Base    0.25K
```

**CP/NOS removes BDOS entirely** — there are no local resources to
service, so NDOS becomes the sole BDOS-interface front-end and the
3.5 K saving comes back to the TPA.  This is consistent with our
`CPNOS_TPA_KB = 56` (versus Clapp's 52.5 K) and with the wire-doc
invariant that *every* drive slot in CFGTBL is either a network drive
or empty.

## NDOS intercepts at *two* levels — the design wart

This is Clapp's most useful observation for understanding our slave.

NDOS's normal job is to intercept system calls *at the BDOS entry
point* (logical entry 5) and route them.  But Clapp documents a
second entry point: NDOS *also* intercepts certain calls coming out
of BDOS into BIOS — specifically:

- console I/O (`CONOUT`, `CONIN`, `CONST`)
- list-device I/O (printer)
- warm boot

Clapp's diagnosis (verbatim, p. 119):

> A possible rationale for this approach is that it allows
> application programs to make direct calls upon the BIOS yet retains
> the mapping from logical to local/remote resources. … The approach
> taken by Digital Research requires a less "abstract" machine, the
> BIOS, to request a service from one more "abstract", the NDOS.  The
> result is a product more conceptually complex, less theoretically
> "clean" than might be desired.

He concludes (p. 124):

> Another flaw in the design of CP/NET is the decision to have the
> NDOS intercept calls at the BIOS as well as the BDOS level.
> Perhaps they were forced to do so by practical necessity, but the
> result is a more cluttered, less straightforward design.

For us this rationalises (without endorsing) several things:

- Why CONOUT routing in `resident.c` has to coexist with
  network-CON routing at the NDOS layer.
- Why the SW1 bit-0 "console_joined" gate exists *at the BIOS
  layer*, not at NDOS — operator console I/O can come in via either
  entry point.
- Why "reader" and "punch" devices have no networked mode (Clapp:
  "the remaining non-disk I/O devices, reader and punch, are not
  intercepted in this manner because they cannot be networked").

## Session ≡ node — the addressing collision

CP/NET 1.2 uses two IDs: server-ID and requester-ID.  Clapp notes
(p. 122) that these identify a **node**, not a **process** on that
node:

> it is impossible for a requester to communicate with more than one
> process at a server node. CP/M-80 is a single tasking operating
> system. The designers of CP/NET did not envisage a situation in
> which multiple processes at a requester would interleave service
> requests to a single MP/M II server.

Our wire protocol carries the same limitation.  Practical effect for
us: there is exactly one "session" between RC702-slave-1 and the
z80pack mpm-net2 master, and the SID field on every outbound frame is
`cfgtbl.slaveid` (= `RC702_SLAVEID = 1`, baked at build time — see
our wire-doc § *SID rewriting*).

This also explains why DRI's `server.asm` validates `FNC < 76` — the
function code uniquely identifies the *operation*, not a session /
channel / process within a session.

## Session-layer responsibility model

Clapp lists what NDOS does at the session layer (p. 122):

- **LOGIN / LOGOFF** establish and dismantle the session.  LOGIN sets
  the requester's view of the network; LOGOFF tears it down.
- **Connection maintenance is *negative*.**  Quoting Clapp: "if a
  message cannot be sent or received, NDOS simply returns an error
  to the application program and allows it to make any attempt at
  recovery it desires."  There is no transparent retry above the
  data-link layer.  Our wire-doc § *Retry semantics* covers the
  data-link-layer retry (MAXRETRY = 10 whole-frame retries); above
  that, NDOS just returns the error.
- **Strict request/response pairing.**  Every frame sent requires a
  response; the master never initiates traffic.  This is the "pull-
  only NDOS" model our wire-doc already calls out under § *Unsupported*.

There is one DRI-provided escape hatch (p. 122):

> The system calls "Send Message on Network" and "Receive Message on
> Network" cause NDOS to pass messages between the application layer
> and the transport layer virtually untouched.

These are the FNC = 64-and-above custom-message functions in the
unofficial CP/NET docs (Functions 66/67 in durgadas's notes).  Our
slave does not use them; they're a hook for application-layer
extensions like the CP/NET MAIL program.

## What Clapp says is missing in CP/NET

Useful to know what *isn't* in the protocol so we don't go looking:

- **No transport layer.**  No message splitting / reassembly above
  data-link.  Implication: every CP/NET frame must fit in one DRI
  message buffer (header + 1..256 data bytes), full stop.  Our wire-
  doc shows this constraint (`SIZ` = data length − 1, single byte).

- **No network layer.**  No routing, no congestion control.  Clapp
  notes the protocol "lends itself most readily to a star topology"
  and that ring is awkward but possible.  Our setup is a 1-to-1
  point-to-point link — degenerate star.

- **No CRC.**  Data-link checksum is the mod-256 negative sum;
  Clapp explicitly observes this is weaker than a CRC and would
  cost only "a simple and short subroutine" to upgrade.  Our wire-
  doc § *Checksums* documents the same byte-sum construction; if
  we ever want stronger integrity, it has to be layered on top of
  the FNC=64-style escape hatch.

- **Naked control bytes.**  ENQ / ACK / NAK travel "naked over the
  physical link" — no checksum, no framing.  Bit-flip on an ACK
  becomes a NAK and triggers a whole-frame retransmit.  This is
  inherent to the protocol; the slave's only defence is the per-byte
  TMRETRY / MAXRETRY budgets in our wire-doc § *Retry semantics*.

## Sample SNIOS variants Digital Research shipped

Per Clapp (p. 121), DRI provided three reference SNIOS
implementations with the CP/NET package:

- **Corvus OMNINET** — proprietary CSMA-like LAN
- **ULCnet** of Orange Compuco, Inc. — point-to-point serial mesh
- **Default simple-serial** — requester ↔ server(s) over an RS-232
  port; this is what `cpnet-z80/src/ser-dri/snios.asm` is the modern
  reincarnation of, and what we ultimately speak (with PIO or SIO
  substituted for the original UART).

The OMNINET and ULCnet variants are historical curiosities.  The
simple-serial variant is the one whose protocol our wire-doc pins
down byte for byte.

## What Clapp got *wrong* / what's changed

For honesty, two corrections to the 1983 framing:

1. Clapp expected the destination-node-vs-destination-process
   conflation to "be regretted" once 16-bit multi-tasking arrived
   (he names 8086 / Concurrent CP/M-86).  History went a different
   way: CP/M itself never grew that, and CP/NET stayed single-task-
   per-slave.  The collision is permanent for CP/NET 1.2.

2. Clapp describes CP/NOS in passing as "future direction" but the
   paper is about CP/NET with BDOS present.  CP/NOS (which is what
   our PROM1 actually runs) takes the simplification further by
   *replacing* BDOS, not just routing around it.

## Operational impact on this project

Nothing in Clapp's paper invalidates anything in
`CPNET_WIRE_PROTOCOL.md`.  The byte-level protocol described there is
exactly the data-link-layer protocol Clapp sketches in his Figure 10,
and the master-side and DRI-reference-slave-side implementations our
doc cross-checks are still the authoritative byte-level sources.

What this doc adds is **why the implementation has its current
shape** — specifically why CON I/O has two interception paths
(`impl_conout` in resident + NDOS-layer routing) and why no transport-
layer fragmentation logic exists in the slave (none exists in the
protocol at all).

## See also

- `cpnos-shared/docs/CPNET_WIRE_PROTOCOL.md` — byte-level wire
  protocol (authoritative)
- `cpnos-shared/docs/MEMORY_MAP.md` — actual cpnos memory layout
- `cpnos-in-c/src/init.c` — `print_banner`, `cfgtbl_init`, CFGTBL
  drive-map construction (NET_DRV macro)
- `cpnos-in-c/src/snios_c.c` — slave-side SNIOS in C (LOGIN, NTWKIN,
  SNDMSG / RCVMSG state machines)
- `z80pack/cpmsim/srcmpm/netwrkif-0.asm` — master-side reference
- `cpnet-z80/src/ser-dri/snios.asm` — DRI's reference slave for
  serial transport (the "simple, default architecture" Clapp names)
