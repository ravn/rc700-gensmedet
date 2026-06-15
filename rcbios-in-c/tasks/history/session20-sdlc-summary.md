# Session 20: SDLC on Physical RC702 (2026-04-18)

End-to-end SDLC TX experiment on the physical PCB530 mainboard, with
FT2232D async bit-bang capture on the host.  Started from the
Session 18 plan (ravn/rcbios-in-c `tasks/sdlc-hw-test.md`) and drove
it all the way to a live run.

## What works end-to-end

1. **DDT deploy path** — new `ddt_deploy.py` replaces the PIP+MLOAD
   hex-upload flow.  Types the .COM bytes into DDT's `S` command over
   the SIO-B console, verifies via `D` dump, warm-boots with `G0`,
   and `SAVE`s as a .COM.  No SIO-A involvement, no RX ring-buffer
   contamination, per-byte echo as inherent verification.  User
   directive: always use this path.
2. **Z80 side** — `sioa_sdlc_tx.asm` (344 B) programs CTC ch0 in
   timer mode, SIO-A for SDLC NRZI with CRC-CCITT + flag idle,
   transmits one test frame of 28 bytes (payload contains
   bit-stuffer stress patterns `0xFF×4`, `0x7E×2`, `0xAA/0x55`,
   `0xDEADBEEF`), waits for "All Sent", restores 38400 async.
   Now targets SIO-A because the current BIOS has CON: on SIO-B —
   commandeering the console channel would black out the serial
   link if the restore path had a bug.  The first version did
   exactly that and we learned the hard way.
3. **Host capture** — `sdlc_capture.c` in C against libftdi1
   (runtime-linked, no dev headers needed).  Empirically sustains
   98% of 80 kHz sampling, 96% of 150 kHz, 26% of 1 MHz (the
   FT2232D USB-scheduling + FIFO-depth ceiling — see below).
   Auto-reattaches the kernel ftdi_sio driver via the Python helper
   `/tmp/ftdi_reattach.py` so `/dev/ttyUSB*` comes back for the
   next serial tty user.
4. **Decoder** — `sdlc_receiver.py` (Python ctypes into libftdi1).
   Supports `--decode-only` for offline analysis of captures.  The
   bit-level recovery works — we've seen `DE AD` bytes from the
   payload tail at the expected offset in decoded NRZI streams at
   clean capture rates.  Frame-level CRC alignment is the remaining
   gap.
5. **Orchestration** — `sdlc_deploy.sh` + Makefile target `sdlc` run
   the whole chain from a single `make sdlc`.

## Key empirical findings

### FT2232D bit-bang capture ceiling (2026-04-18)

Measured sustained sample rates vs. configured:

| Configured | Effective | Notes |
|------------|-----------|-------|
| 100 kHz | 96 kHz (95.7%) | clean |
| 150 kHz | 143 kHz (95.6%) | clean |
| 200 kHz | 188 kHz (94.0%) | minor drops |
| 250 kHz | 216 kHz (86.6%) | noticeable drops |
| 500 kHz | 212 kHz (42.5%) | saturated |
| 1 MHz | 264 kHz (26.4%) | heavily capped |

Above ~200 kHz the FT2232D's 384-byte FIFO overflows between USB
1 ms bulk-IN scheduling frames.  `ftdi_readstream` (async API)
would help but FT2232D doesn't support it — that's FT2232H-only.

**Implication:** FT2232D caps at ~200 kHz bit-bang.  For 8×
oversampling that's ~25 kbaud line rate — **slower than 38400
async, so not useful for CP/NET throughput gains** on this adapter.
An FT2232H adapter lifts the ceiling ~40×.

### CTC CLK on PCB530 (unresolved)

My asm set TC=50 expecting 10 kHz SIO clock.  The observed bit rate
on the line, measured from run-length statistics of clean captures,
is closer to **6.0–6.8 kHz**.  Working backward with TC=50 and /16
prescale, the CTC CLK pin appears to be fed from a ~5 MHz source,
not the 4 MHz CPU Φ I assumed.

Candidates:
- 4.9152 MHz (= 19.6608 MHz / 4) — would give 6144 Hz output, close
  to observed.  19.6608 MHz is the DRAM/video master oscillator.
- 5 MHz exact — would give 6250 Hz, also within measurement error.
  Not a standard derived clock on the RC702.

Needs direct measurement with a scope on the Z80-CTC CLK pin to
settle.  Until resolved, empirically tune CTC TC to hit a target
baud by trial-and-error rather than relying on the 8-MHz-or-4-MHz
theoretical derivation.

(Earlier in the session I wrote "CTC CLK is 8 MHz" in the hardware
reference doc and asm comments — that was wrong; corrected to "needs
verification".)

### MAME model mismatch

`mame/src/mame/regnecentralen/rc702.cpp` uses `Z80CTC(config, m_ctc1,
8_MHz_XTAL / 2)` — i.e. 4 MHz CTC clock.  Physical PCB530 shows a
different rate per above.  Filing as a follow-up MAME issue after
confirming the real clock.

## Physical deploy/retail notes

- RC702 DB-25 (J1/J2) pinout extracted from the tech manual and
  recorded in `RC702_HARDWARE_TECHNICAL_REFERENCE.md`.  No TxC/RxC
  pins wired on MIC702/MIC703 — no external clock path for sync
  mode, confirming TX-only capability for SDLC without a cable mod.
- Host adapter confirmed FT2232**D** (not H) via USB descriptor
  (`bcdDevice 0x0500`, 8-byte EP0, 4 bulk endpoints 64 B each).
- elextra.dk does not stock FT2232H products.  Available options:
  FTDI USB-COM232-PLUS2 (dual RS-232, drop-in, ~€100-150) at
  distrelec.dk / farnell.dk / digikey.dk; or Waveshare FT2232HL
  breakout (~€30, TTL, needs MAX232) at mouser.dk / amazon.de.

## Open items / suggested issues

- [ ] Decoder CRC-matching tuning.  `samples_to_bits`'s
  `MAX_RUN_BITS=8` cap destroys frame CRC bytes at long idle
  boundaries; remove or raise the cap once the first flag is
  detected.  Also `find_frames` may need to tolerate abort/flag
  ambiguity more carefully (6 ones = end-of-flag, 7 ones = abort,
  8+ ones = idle-mark).
- [ ] Scope measurement of the Z80-CTC CLK pin on PCB530 to settle
  the 4-vs-5-vs-8-MHz question.
- [ ] File ravn/mame issue: PCB530 CTC clock rate differs from the
  4 MHz in rc702.cpp (pending scope confirmation).
- [ ] MAME `ftdi_readstream` path is unusable on FT2232D; any
  attempt to bit-bang over 200 kHz on this adapter will drop data.
  Document the ceiling in `rcbios-in-c/tasks/sdlc-hw-test.md`
  (already done).
- [ ] Consider FT2232H adapter purchase (USB-COM232-PLUS2 or
  Waveshare FT2232HL) to unlock 614.4 kbaud SDLC per the original
  Session 18 plan — the current FT2232D cannot sustain it.

## Code artefacts added this session

- `rcbios-in-c/sioa_sdlc_tx.asm` — Z80 SDLC TX program (344 B).
- `rcbios-in-c/ddt_deploy.py` — generic DDT S+D+SAVE uploader.
- `rcbios-in-c/sioa_fix_via_ddt.py` — recovery helper (fixes SIO-A
  state when a bad SIOASDLC run leaves it unusable).
- `rcbios-in-c/cim_to_hex.py` — .cim → Intel HEX (no longer used
  after DDT switch, kept for ref).
- `rcbios-in-c/sdlc_capture.c` — tight-loop C bit-bang capture.
- `rcbios-in-c/sdlc_receiver.py` — Python decoder + offline analysis.
- `rcbios-in-c/sdlc_deploy.sh` — end-to-end orchestrator.
- Makefile target `sdlc`.
- `RC702_HARDWARE_TECHNICAL_REFERENCE.md` — DB-25 pinout, PCB530
  identification, sync-mode availability matrix.
