# PIO Mode 1 input: how busy-wait works, and whether `INIR` fits

Investigation pre-#115 (INIR busy-poll refactor of CP/NET PIO RX).
Source-grounded against `cpnos-in-c/src/transport_pio.c` and the
Zilog Z80-PIO datasheet.

## Question

How does the current PIO RX path synchronise with the peer's strobe,
and can `INIR` replace it given that PIO Mode 1 is peer-paced (the
master strobes; the slave reads)?

## What "busy wait" means for PIO Mode 1 input

PIO Mode 1 = byte-input mode with two-line handshake:

| Line | Direction | Meaning |
|---|---|---|
| `/STB`  | peer → PIO | "I just put valid data on the bus.  Latch it." |
| `/BRDY` | PIO → peer | "I have room for a new byte." (low = not ready) |

The chip-level cycle for one byte is:

1. PIO holds `/BRDY` high → peer asserts data + pulses `/STB`.
2. PIO latches byte into `m_input`, sets `IP` (Interrupt Pending),
   drives `/BRDY` low → **peer must wait**, cannot strobe next byte.
3. Slave CPU executes `IN A,(PIO_B_DATA)` (port 0x11).
4. PIO returns `m_input`, clears `IP`, drives `/BRDY` high → peer can
   strobe next byte.

The handshake gating is real hardware flow control.  **The peer
*cannot* outrun the slave's reads, because step 2's `/BRDY` low
suspends the bridge.**  This is the basis on which `INIR` works
(see below).

## Current path — ISR + 256-byte ring

`transport_pio.c` runs PIO-B with IE on.  Each strobe triggers
`isr_pio_par` via the IM2 vector:

```
isr_pio_par body (transport_pio.c:498):
  push af, push hl                        ~21 T
  in   a, (0x11)                          ~11 T   <-- this clears IP and frees /BRDY
  push af                                 ~11 T
  ld   hl,_pio_rx_head ; ld a,(hl) ; inc  a  ~24 T
  ld   hl,_pio_rx_tail ; cp (hl)          ~14 T
  jr   z,_drop  (not taken)               ~ 7 T
  ld   (_pio_rx_head),a ; dec a           ~17 T
  ld   l,a ; ld h,_pio_rx_buf_page        ~14 T
  pop  af ; ld (hl),a                     ~17 T
  pop  hl, pop af, ei, reti               ~47 T
  ----------------------------------------------
  Body total                              ~184 T  (= 46 µs @ 4 MHz)
  IM2 acceptance (PC push + vector fetch)  ~19 T
  Grand total per byte                    ~203 T  (= 51 µs)
```

Steady-state ceiling: **~19.6 KB/s**.  Mainline `transport_pio_recv_byte`
polls the ring tail (`while (head != tail) { ... }`) with a separate
timeout counter — that's the "busy wait" today, and it spins on a
RAM-only condition: head/tail.

The wall on throughput is the ISR body length, not the PIO chip:
between strobes, the slave's CPU is bouncing through prologue,
epilogue, ring bookkeeping, and IM2 vector fetch.  Each of those
T-states is wall-clock the peer must spend with `/BRDY` low waiting
for its next strobe-opportunity.

## Why `INIR` works on Mode 1 input — without polling IP

`INIR` is a Z80 block I/O instruction:

```
INIR:
  loop:
    IN (HL), (C)     ; HL contains addr, C contains port — read port C → (HL)
    INC HL
    DEC B
    JR  NZ, loop
  total: 21 T/iter (16 last iter) — block of B bytes, no branches in loop
```

Naive worry: each `IN (HL),(C)` doesn't check whether a *new* byte has
arrived since the previous read; would the second iteration just re-read
the same latched byte?

**The handshake answers this.**  Walk through it with `INIR B=2`:

1. Before INIR, peer has strobed one byte (IP set, `/BRDY` low).
2. Iteration 1: `IN` reads `m_input`, clears IP, drives `/BRDY` high.
3. Peer sees `/BRDY` rise, strobes byte 2: `/BRDY` low, IP set,
   `m_input` updated to byte 2.  Peer is *much* faster than 21 T —
   on MAME the bridge reacts in fewer host cycles than one Z80
   instruction; on real hardware a USB/serial bridge with even
   modest firmware can turn around in microseconds.
4. Iteration 2: `IN` reads `m_input` (= byte 2), clears IP, `/BRDY`
   high.  Repeat.

So **the chip-level handshake naturally serialises one byte per
iteration**, even though the `INIR` loop body has no software
synchronisation.  The "wait for strobe set" semantics the question
asks about is delivered *implicitly* by the peer's stalling on
`/BRDY`.  No need to read PIO status — `IN A,(PIO_B_CTRL)` to poll
IP would just waste T-states.

Empirical confirmation: `tasks/session30-pio-driver-and-speed.md`
measured **148 KiB/s** with inline `INIR` busy-poll (IE off) versus
**15 KiB/s** with the ISR/ring path.  Both are MAME measurements;
the gap matches the ~10× ratio of ISR body T-states to INIR body
T-states.  CPU ceiling for `INIR` at 4 MHz: 4 000 000 ÷ 21 ≈ 190
KB/s; the 148 KiB/s measured is within ~22 % of that ceiling, the
balance being PIO chip handshake settling per byte.

## The first-byte caveat (and why ENQ doesn't pay for it)

`INIR` works *once the chain is primed*: there must already be a byte
latched in `m_input` when the loop starts.  If you fire `INIR` with
IP not set, the first iteration reads stale data (whatever was last
latched, or chip-reset default `0xE5`-equivalent).

Two ways to prime:

- **Single-byte `IN` with IP poll** as the first read.  Adds a status-
  poll loop before `INIR`.  Costs ~per-poll T-states until peer
  strobes; bounded by peer's response time.
- **Protocol guarantees a frame is in flight.**  In CP/NET, the slave
  knows it has just sent `ENQ` and the peer must respond with `ACK`
  (1 byte) followed by the `SOH`-prefixed header.  The slave can poll
  for the first byte (`ACK`), then once that arrives switch to `INIR`
  for the rest of the known-size block.

The #115 plan exploits the second pattern.  CP/NET frame layout is
deterministic per `cpnos-shared/docs/CPNET_WIRE_PROTOCOL.md`:

```
peer sends:  SOH | FMT DID SID FNC SIZ | HCS | STX | DAT[0..SIZ] | ETX | CKS | EOT
sizes (B):    1  |       5             |  1  |  1  |    SIZ+1    |  1  |  1  |  1
```

So the slave's full RX of one CP/NET frame becomes:

```
1.  recv1   SOH         poll-IP read    (or already pending after our ACK send)
2.  INIR 7  hdr+HCS     into local scratch — must memcpy first 5 to msgbuf
            -- actually since HL is in our hands, point HL at msgbuf
               directly and let INIR write straight in.  HCS goes one
               byte past msgbuf+5; either that's a scratch byte in the
               cfgtbl tail (4 B available before the next field) or we
               INIR 6 then recv1 HCS — minor wash.
3.  recv1   STX         single IN
4.  INIR SIZ+1  data    HL = msgbuf+5
5.  recv1   ETX
6.  recv1   CKS
7.  recv1   EOT
```

Where `recv1` is "poll IP set, then IN".  Five `recv1`s + two `INIR`s
per frame.  At max SIZ (256 B), the data INIR alone is ~5 380 T ≈ 1.35 ms;
total frame transfer ~1.5 ms vs the current path's ~17 ms.

## Implementation sketch for #115

The cleanest layering: keep `transport_pio_recv_byte` for the one-off
control bytes (ENQ/ACK/SOH/STX/ETX/CKS/EOT), but add an
`transport_pio_recv_block(uint8_t *dst, uint8_t count)` that uses
`INIR` for the bulk path.  Mode-flip stays the same; IE stays OFF for
the duration of the block read so `isr_pio_par` doesn't compete with
INIR for the `IN` that clears IP.

Pre-block setup (called once at start of `rcvmsg_impl`):

```c
disable_interrupts();      // EI off — INIR owns the IN port
pio_b_set_input();         // ensure Mode 1 input
```

The single-byte path stays where it is and just polls the existing
ring (drained by however many ISRs fired between blocks — but since
IE is off during reads, none do).

`transport_pio_recv_block`:

```asm
; B = count, HL = dst, C = PIO_B_DATA (0x11)
;
; Caller has already polled IP set and read the first byte
; (or has just IN'd a control byte that primed /BRDY).
;
; Precondition: a strobe is pending OR will arrive within tens of T-states.
        inir            ; 21 T per byte, no branches
        ret
```

Post-block teardown:

```c
enable_interrupts();
```

### Constraints to verify before landing

- **Per-byte timeout** — `INIR` has no timeout.  If the peer dies
  mid-block, the slave hangs forever.  Mitigations:
    - Pre-set a hardware timer (CTC ch3?) to interrupt at frame-
      level deadline; CTC IRQ unblocks even with PIO-B IE off if its
      own IE is on.  But IM2 dispatching from inside an `INIR` is
      hairy.
    - Accept the hang for the bulk path; rely on `RECV_TIMEOUT_TICKS`
      on the priming single-byte read to catch dead-peer cases
      *before* INIR starts.  Simpler, matches the current SNIOS
      protocol layer (which already retries the whole frame on
      timeout).
- **PIO-A keyboard ISR** — must continue to fire so the operator can
  hit keys during the read.  PIO-A's IE is separate from PIO-B's,
  so this is fine — only `pio_b_set_input`/`pio_b_set_output` toggle
  PIO-B's IE.  Don't `DI` globally; just keep PIO-B IE off.  Actually
  re-reading the current code, `pio_b_set_input` ends with
  `IO_WRITE(PIO_B_CTRL, PIO_IE_ENABLE)` — that's what enables IRQ.
  For #115 we want a `pio_b_set_input_no_ie` variant.
- **Chip-`/BRDY` settling time** — Zilog Z80-PIO datasheet specifies
  the chip's IP→/BRDY-high transition is well within one Z80 cycle
  at 4 MHz.  The wire delay is peer-bridge-dependent; on MAME it's
  zero, on a real RC702 with an STM32-class USB-PIO bridge it's
  sub-microsecond.  No headroom worry.
- **Stale data on prime failure** — if the slave somehow starts
  `INIR` without IP set, the first iteration reads stale `m_input`.
  Detect by checking that the first INIR-read byte equals an expected
  marker (e.g. the `SIZ` byte is always within `0..0xFF` and follows
  HCS; data is unbounded).  Honestly: don't bother — the priming
  read guarantees correctness, just enforce that "INIR is only ever
  entered after a successful priming `IN`".

## Answer in two sentences

The PIO Mode 1 handshake (`/STB` peer-asserted, `/BRDY` PIO-asserted)
gates the peer's next strobe on the slave's read of `m_input`, so
each `IN A,(PIO_B_DATA)` instruction implicitly synchronises with one
peer byte — no need for software to poll IP or any other "strobe is
set" status.  This means `INIR` can run as a tight ~21 T/byte block
read after the chain is primed by one initial poll-and-`IN`, and is
the natural shape for #115's planned ~10× CP/NET RX speedup.

## See also

- `transport_pio.c:30-44` — the wall-on-throughput documentation
- `transport_pio.c:113-135` — #115 simplification plan in code
- `transport_pio.c:498-538` — current `isr_pio_par` body (184 T)
- `tasks/session30-pio-driver-and-speed.md` — empirical INIR bench
- `tasks/cpnet-pio-throughput-baseline-2026-06-12.md` — pre-INIR baseline
- `cpnos-shared/docs/CPNET_WIRE_PROTOCOL.md` — frame layout the INIR
  block reads must match
- Zilog Z80-PIO Technical Manual (1976), Section 5 (Mode 1 input)
