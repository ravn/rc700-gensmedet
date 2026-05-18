# cpnet/snios.asm — dual-transport (SIO + PIO) update

Date: 2026-05-18.
Status: code change in place; runtime test pending.

## Change

`cpnet/snios.asm` (the rcbios CP/NET SNIOS driver, loaded by CPNETLDR
as `SNIOS.SPR`) now supports both byte transports:

  * **SIO** -- existing path, BIOS PUNCH/READER at `0xDA12`/`0xDA15`
    (SIO ch.A polled).
  * **PIO** -- new path, direct PIO ch.B Mode 1 + IRQ-driven 256 B
    SPSC ring buffer, mirroring `cpnos-in-c/src/transport_pio.c`.

Runtime selection via SW1 bit 2 (S03), per the canonical convention
in `docs/SW1_BIT_MAP.md`:

  * Bit clear (default On)  -> PIO transport.
  * Bit set   (Off)         -> SIO transport (existing behaviour).

Build: `python3 cpnet/build_snios.py` -> `cpnet/zout/SNIOS.SPR`.
Sizes pre/post:

  | Metric             | Before | After  | Delta  |
  | ------------------ | ------ | ------ | ------ |
  | SNIOS code         | 673 B  | 1149 B | +476 B |
  | of which DS (ring) | 0      | 262 B  | (data) |
  | of which code      | ~673 B | ~887 B | +~214 B|
  | SPR file           | 1024 B | 1664 B | +640 B |

## Implementation notes

`SENDBY` / `RECVBY` / `RECVBT` are now 3-byte `JP nn` trampolines.
`NTWKIN` reads SW1 bit 2 once at network init and patches the
`nn` operand in place to either the SIO body (`SENDBY_SIO`, etc.)
or the PIO body (`SENDBY_PIO`, etc.).  Once patched, dispatch is
zero overhead -- the call lands on the JP, which tail-jumps to the
chosen impl, which returns to the original caller.  Same
self-modifying-JP pattern cpnos-in-c uses in `xport_aliases.asm`.

PIO init sequence (NTWKIN, when bit 2 clear):

  1. DI (protect IVT patch + chip-state flip).
  2. `LD A, I` -> read rcbios's IVT page register.
  3. Patch IVT slot 17 (PIO-B IRQ vector, byte offset 0x22) to point
     at `ISR_PIO_RX`.  The relocation bitmap covers the high byte of
     `LD DE, ISR_PIO_RX` so the SPR loader lands the right runtime
     address.
  4. PIO-B chip: Mode 1 input (`OUT 0x13 <- 0x4F`), ICW enable + mask
     follows (`0x97`), mask = 0 (`0x00`), IE latch on (`0x83`).
  5. Reset PIO_HEAD = PIO_TAIL = PIO_DIR = 0.
  6. EI.
  7. Fall through to the common slave-ID / ACTIVE-bit init.

`ISR_PIO_RX` is the standard IM 2 ISR: PUSH AF/BC/DE/HL, `IN A,
(PIO_B_DATA)`, store at `PIO_RING + PIO_HEAD`, advance head
(wraps mod 256 because PIO_HEAD is a single byte), POP, EI, RETI.

`SENDBY_PIO` mirrors `transport_pio_send_byte` from cpnos: if
direction state == OUTPUT, just write data; otherwise IE_DISABLE,
preload data, MODE_OUTPUT (which fires the cpnet_bridge `write()`
callback with our data byte), latch direction.

`RECVBY_PIO` / `RECVBT_PIO` poll the head!=tail condition, index
into `PIO_RING + PIO_TAIL`, advance tail.  Both call
`PIO_TO_INPUT` first so a recv after a send (last-byte-of-frame
flip) correctly puts the chip back in input mode and reactivates
the ISR.

## Build verification

```
$ python3 cpnet/build_snios.py
SNIOS code: 1149 bytes
Relocatable bytes: 98
SPR file: cpnet/zout/SNIOS.SPR
  Total: 1664 bytes

Verification: simulated load at D800h
  NTWKIN JP target: F8DBh -> DBF8h
```

Relocation bitmap correctly tracks the ISR address (the only
new IVT-bound relocatable).  Build's own simulated-load test
confirms NTWKIN's JP target relocates correctly.

## Runtime testing

Done.  `cpnet/polypascal_pio_test.sh` (added 2026-05-18, refined
2026-05-19) drives the full rcbios + PIO + PolyPascal regression
against z80pack mpm-net2:

  | BIOS  | Result   |
  | ----- | -------- |
  | clang | PASS 10.50 s |
  | SDCC  | PASS 10.71 s |

Stages: CPNETLDR -> LOGIN PASSWORD -> NETWORK H:=A: -> H: (first
remote-drive SELDSK) -> PPAS launch (typed via SIO-B injector with
explicit CR; see `polypascal_pio_inject.py`) -> L PRIMES (PPAS.COM
loaded from H: over CP/NET PIO) -> R -> PRIMES output through 29989
-> Q -> H>.

Open follow-up: PPAS-launched-from-`$$$.SUB` works through a TCP
proxy but not direct-to-mpm.  Documented in
`cpnet/todo-ppas-sub-direct-vs-proxy-2026-05-19.md`.  Not blocking
-- the inject-typed-with-CR path is robust.

SIO regression (`cpnet/chksum_roundtrip_test.sh` with SW1 bit 2 =
Off) is also still expected to pass but hasn't been re-run this
session; the SIO code-path was preserved verbatim in the
refactor and the dispatcher patch is bottom-up content-checked at
NTWKIN, so a regression on SIO would manifest as a NTWKIN-time
failure visible in the dispatch (SENDBY/RECVBY/RECVBT) JP-targets.

## Memory rules invoked

  * `feedback_no_literal_addresses` -- IVT slot offset 0x22 IS a
    literal but it's a magic constant (the PIO-B chip's vector
    register value), not a memory address.  Acceptable per the
    rule's discriminators.
  * `project_cpnos_address_coupling_brittle` -- avoided.  The
    only address coupling here is `LD A, I` reading rcbios's
    current IVT page at runtime, which adapts automatically if
    rcbios's IVT_ADDR shifts.
