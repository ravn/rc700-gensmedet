# Hardware verification checklist — rcbios CP/NET PIO PPAS-over-the-wire

**Purpose:** definitively close the parked
`KNOWN_ISSUE_pio_send_recv_race_2026-07-08.md`. That stall is a **measured
MAME-only artifact** (PORT_B `ius` stuck across the send→recv mode flip;
two-port theory refuted; firmware ISR/RETI + `PIO_TO_INPUT` proven
correct). Real Z80-PIO silicon clears IUS on RETI via the daisy IEO chain,
so the expectation is: **on iron this Just Works.** This checklist proves
or disproves that.

Run when the physical RC702 + Pi/Pico CP/NET bridge is available (the same
hardware dependency that parks the INIR path,
`feedback_ring_shrink_inir_coupled`).

## Prerequisites

- [ ] Physical RC702 (or RC702 with SEM702 — irrelevant to this path).
- [ ] Pi/Pico host-side CP/NET bridge firmware built and flashed. It must
      implement the same byte transport MAME's `cpnet_bridge` does:
      PIO-B Mode-1 input (STB/BRDY handshake) inbound, Mode-0 output
      outbound, bytes shuttled verbatim to/from the CP/NET master. **8-bit
      clean** — no sentinel byte (mirror `ravn/mame 12ea19d0`; all 256
      values are valid payload).
- [ ] CP/NET master reachable from the bridge: either z80pack `mpm-net2`
      on a host, or a real MP/M master. Drive I: (or whichever maps to
      slave H:) seeded with `PPAS.COM`, `PPAS.ERM`, `PRIMES.PAS` (see
      `cpnos-shared/e_drive_seed/ppas/`).
- [ ] Boot floppy: `SW1711-I8.imd` patched with the current clang rcbios
      (`make -C rcbios-in-c bios COMPILER=clang`) + `SNIOS.SPR`
      (`python3 cpnet/build_snios.py`) + CP/NET dist COMs + the `$$$.SUB`
      that runs CPNETLDR / LOGIN / NETWORK H:=I: / H:. The MAME test
      `cpnet/polypascal_pio_test.sh` steps 1-3 build exactly this image at
      `/tmp/cpnet_pio_test.imd` — reuse it, just write it to a real floppy
      / IMD-capable drive.

## Wiring

- [ ] Pi/Pico bridge on **PIO-B (J3)** — the expansion connector, NOT the
      printer port (printer is on SIO). Confirm PB0..PB7 + STB + BRDY.
- [ ] **SW1 S03 = On (bit 2 = 0)** → PIO transport in the dual SNIOS.
- [ ] **SW1 S01 = On (bit 0 = 0)** → joined console (so the physical
      keyboard / serial console can type commands).
- [ ] Console: the real RC702 keyboard + CRT (no SIO-B injector needed on
      hardware — you type `PPAS` yourself).

## Procedure

1. [ ] Power on; rcbios boots from floppy; `$$$.SUB` auto-runs
       CPNETLDR → LOGIN PASSWORD → NETWORK H:=I: → H:. Expect a clean
       `H>` prompt (the login/NETWORK frames already exercise PIO
       send+recv — a stall here means the transport is broken, not just
       the bulk-transfer race).
2. [ ] At `H>` type `PPAS` <CR>. This triggers the 222-record
       `H:PPAS.COM` load over CP/NET — the exact path that stalls in MAME.
3. [ ] Wait for PolyPascal's `>>` prompt (PPAS loaded and running).
4. [ ] `L PRIMES` <CR>, then `R` <CR>; watch the sieve print primes.
5. [ ] `Q` <CR> returns to CCP (`H>` / `A>`).

## Pass / fail

- **PASS** = `>>` appears after `PPAS` (step 3) and PRIMES runs to
  completion. → **PPAS.COM transferred all 222 records over CP/NET PIO
  without stalling.** Firmware + transport proven correct on hardware; the
  MAME stall is confirmed MAME-only. Close the known issue as
  "hardware-verified, MAME-model limitation."
- **FAIL** = load stalls partway (no `>>`, console hung). → the stuck-IUS
  mechanism (or an analogue) reproduces on real silicon after all;
  re-open with a real firmware/transport defect. Capture: how many bytes
  the bridge shuttled before the stall, and whether the slave's PIO_RING
  head/tail froze (needs a bridge-side byte counter + a way to peek slave
  RAM — e.g. gdb-z80 stub, see `tasks/gdb-z80-stub-findings-2026-06-19.md`).

## What each outcome means for the code

- PASS → **do not** invest in fixing MAME's z80pio daisy accept/reti
  model; it's not on the critical path (production runs on cpnos-in-c PIO).
  Just annotate the MAME limitation. The 8-bit-clean bridge stays as the
  shipped host-side reference for the Pi/Pico firmware.
- FAIL → the fix is genuinely firmware/transport, not MAME. Prime suspects
  in order: (1) `SENDBY_PIO`'s `PIO_IE_DISABLE` leaving an interrupt
  acknowledged-but-not-serviced across the flip; (2) a real ring
  head/tail overrun under sustained bulk transfer; (3) master-side
  (mpm-net2) flow-control assumption the real bridge violates.

## Notes

- The MAME test caps out at ~0.05x realtime during CP/NET transfer (TCP
  round-trip per record); on hardware the PIO handshake runs at bus speed,
  so a full PPAS load should take **seconds, not minutes**. If it's slow on
  hardware too, that's a separate bridge-latency issue, not this stall.
- Related: `KNOWN_ISSUE_pio_send_recv_race_2026-07-08.md` (root cause),
  `docs/SW1_BIT_MAP.md` (DIP allocation), the parked INIR path
  (`cpnos-in-c/tasks/PIO_INIR_PARKED.md`) which unparks on the same
  hardware.
