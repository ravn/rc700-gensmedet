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

## Runtime testing -- next session

Not yet run on a real boot.  Needs:

  * MAME built with cpnet_bridge (already current).
  * Reference disk image (~/Downloads/SW1711-I8.imd or similar)
    that `cpnet/run_test.sh` expects.
  * z80pack MP/M running on `:4002` (PIO mode) or null_modem TCP
    server (SIO mode).

Test plan:

  1. **SIO regression** (`cpnet/chksum_roundtrip_test.sh`):
     set SW1 bit 2 = Off (=1) so the new NTWKIN takes the SIO
     branch and behaves identically to pre-2026-05-18 SNIOS.
     Confirms the SIO path didn't regress in the refactor.

  2. **PIO new path**: same test with SW1 bit 2 = On (=0, default)
     and a PIO-wired test topology (`-piob cpnet_bridge`).
     Confirms the SENDBY/RECVBY dispatcher patch + ISR + ring
     buffer work end-to-end against MP/M.

## Memory rules invoked

  * `feedback_no_literal_addresses` -- IVT slot offset 0x22 IS a
    literal but it's a magic constant (the PIO-B chip's vector
    register value), not a memory address.  Acceptable per the
    rule's discriminators.
  * `project_cpnos_address_coupling_brittle` -- avoided.  The
    only address coupling here is `LD A, I` reading rcbios's
    current IVT page at runtime, which adapts automatically if
    rcbios's IVT_ADDR shifts.
