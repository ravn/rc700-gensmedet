# Session 21: SDLC decoder follow-up + FT2232H sourcing (2026-04-18)

Continuation of session 20. No hardware changes landed; the session
closed out the software side of the SDLC path and pinned the next
hardware decision.

## What shipped

### Synthetic decoder test harness
- `rcbios-in-c/test_sdlc_decoder.py` — builds an ideal SDLC bit stream
  (HDLC-stuffed, CRC-CCITT, NRZI, flag-idle, oversampled) and feeds it
  through `sdlc_receiver.py`'s decode pipeline.
- 5 correctness tests PASS on clean input including stuffer stress
  (0xFF×16, 0x7E×8) and long-idle boundaries.
- Degradation curve characterised: decoder recovers up to ~±6% sps
  mismatch and ~10% random sample drops. Falls off sharply beyond.
- `crc_ccitt("123456789") = 0x906E` — matches X.25 reference.

### DPLL bit recovery
- `samples_to_bits`' `round(run/sps)` is brittle: a 78-sample 6-ones
  flag run gets rounded to 7 under small jitter, which HDLC reads as
  an abort and kills frame detection.
- Added `dpll_bits()` in `sdlc_receiver.py`: sample at bit-center,
  snap phase to each detected transition. Tolerates ~±20%
  bit-period jitter.
- `decode_with(use_dpll=True)` — now the default path.
- Synthetic tests still PASS under DPLL.

### End-to-end hardware run
- `./sdlc_deploy.sh` ran cleanly on physical RC702:
  - DDT deploy of SIOASDLC.COM (343 B, 16.5 s) — verified OK.
  - FTDI C capture: 97.2% effective rate at 80 kHz, zero drops.
  - Z80 printed "Frame sent." — transmit completed.
- Burst span: 0.48 s starting at t=1.49 s; only ADBUS1 active.
- Transition density (1387/s) consistent with ~5.5 kbaud SDLC flag
  idle at line rate ~6 kHz.
- Legacy decoder: 1 frame candidate. DPLL: **40 candidates**.
- **Zero CRC-OK, zero payload substring matches** across sps 4–18,
  both NRZI polarities, all 8 byte-shift offsets.

## Diagnosis

Decoder logic is correct (synthetic tests pass). Capture is clean
(97.2% effective). TX ran to completion (console confirmed).

The bit-level flag structure is present in the capture — DPLL finds
40 candidate frames — but byte streams never contain "SDLC", "TEST",
"-TX-", or a valid CRC.

At sps≈13, genuine 6-cell flag runs should cluster tightly near
78 samples. Observed 5- and 6-cell runs spread 65–110 samples (~40%
variance). Hardware-clocked Z80-SIO can't produce that jitter. The
most likely source is the cheap "USB FAST SERIAL ADAPTER"'s RS-232
transceiver — asymmetric slew + noisy threshold smearing transitions
off the ideal bit grid.

Confidence: medium. Needs scope confirmation on SIO-A TxD at the Z80
side of the RS-232 driver, or bypass of the current adapter.

## Next hardware step

Replace the adapter with a genuine **FTDI USB-COM232-PLUS2**
(FT2232H + proper RS-232 transceivers). Fixes three things at once:
USB 2.0 HS, 4 KB FIFO per channel, quality transceiver.

User preference is EU-based retailer (not US shipping). Survey is in
`rcbios-in-c/tasks/sdlc-hw-test.md`. Primary picks:
- **Farnell DK** (EU warehouse)
- **Newark UK** (UK warehouse, 2–4 business days)

Avoid DigiKey DK (64 in stock but ships from Minnesota) and the
FT2232H Mini Module (0 in stock, 38-week lead, TTL-only).

FT232RL considered and rejected — smaller FIFO, same USB 1.1
full-speed; sideways move at best.

## Open follow-ups

- [ ] ~~Order USB-COM232-PLUS2 from Farnell DK / Newark UK.~~
      **Revised (2026-04-19):** USB-COM232-PLUS2 out of stock at all EU
      retailers. Replaced with Adafruit FT232H (€14.95, Antratek.de)
      + MAX3232 module (~€8, Amazon.de). See `rcbios-in-c/tasks/sdlc-hw-test.md`
      for wiring and MPSSE capture strategy.
- [ ] Order Adafruit FT232H from Antratek.de + ANGEEK MAX3232 from Amazon.de.
- [ ] On arrival: rerun `./sdlc_deploy.sh`, auto-decode, confirm CRC-OK
      frame with "SDLC-TX-TEST..." payload.
- [ ] If still failing with the new adapter: scope on SIO-A TxD at the
      DB-25 connector, verify bit-cell uniformity. Filed as
      sdlc-hw-test.md "TODO before any code lands".
- [ ] Settle the CTC CLK rate on PCB530 with scope (4 MHz / 5 MHz /
      8 MHz question from session 20).
- [ ] File ravn/mame-rc702-rc759-rc750 issue: PCB530 CTC rate likely differs from the
      4 MHz in `rc702.cpp`, pending scope confirmation.

## Files touched

- `rcbios-in-c/sdlc_receiver.py` — added `dpll_bits`, made it default
  in `decode_with`.
- `rcbios-in-c/test_sdlc_decoder.py` — new synthetic round-trip test.
- `rcbios-in-c/tasks/sdlc-hw-test.md` — session 21 findings +
  retailer survey.
- `tasks/prompts.md` — session 21 prompts.
