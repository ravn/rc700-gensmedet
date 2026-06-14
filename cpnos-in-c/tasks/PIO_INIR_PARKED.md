# cpnos-in-c PIO → INIR (#115 Steps 2+4) — PARKED 2026-06-14

The hand-rolled-asm `transport_pio_recv_block` (INIR-based PIO-B block
receive) and the bundled ring-shrink + TPA-grow layout migration are
**parked** pending user's physical RC702 + Pi/Pico bridge hardware
bring-up.

## Why parked

The 2026-06-14 implementation session built clean, bisected, and
diagnosed via MAME debugger CPU trace that:

- **Ring-shrink (256 → 16 B) and INIR are coupled, not independent.**
  INIR drains data bytes direct to msg+5..msg+SIZ+5, bypassing the
  ring; ring then only carries control bytes (max ~8 B burst).
  Without INIR, the 41-byte data block flows through the ring and
  overflows a 16-byte buffer (measured 12 % ISR drop rate, slave's
  step (7) ETX check fails on a dropped byte, RC_RETRY without NAK,
  outer loop waits for an ENQ master never sends, slave eventually
  falls into `_resident_handoff`'s `jr $f301` netboot-failed dead
  loop).
- **MAME's cpnet_bridge can't honor the Z80-PIO Mode 1 per-iter
  handshake INIR needs** (TCP-bound timing is ms-scale; INIR expects
  µs-scale strobes).  See `tasks/session-2026-06-13-phase4-inir-and-mame-findings.md`.

Net: in MAME there is **no working configuration** for the bundle.
The implementation should work on real hardware where the Pi/Pico can
strobe /STB within INIR's per-iter ~5 µs budget, but that requires the
physical bring-up.

## What stays in main (kept from the session work)

- **Step 0 — `9592c2d`**: strip per-VRTC DMA reload from `isr_crt`,
  lean on autoinit (0x5A) mode programmed in `init.c`.  Structural
  enabler -- removes ~150 T-states / VRTC cost and makes any future
  DI bracket survive without display garble.  Correct on its own,
  independent of INIR.
- **Step 1 — `50cc0bf`**: additive `pio_b_recv_block_body` __naked
  scaffold function with `pio_block_dst` / `pio_block_count` BSS
  globals.  No call sites yet; linker --gc-sections drops it from
  the PROM when unreferenced.  Available as the INIR primitive when
  the parked work resumes.

PROM1 line program at HEAD: 2015 / 2048 B (33 B free).  Polypascal-test
PASS in 53.61 s.

## What's NOT in main (parked work)

- Hand-rolled asm `transport_pio_recv_block(uint8_t init_cks) -> uint8_t`
  with DI + drain + INIR + EI + CKS fold body (~33 B asm).
- snios_c.c step (6) PIO dispatch (prime byte + `if (transport_uses_pio)`
  branch + post-INIR CKS fold).
- `transport_uses_pio` runtime flag in default BSS, set by
  `install_transport()` based on SW1 bit 2 (S03).
- Ring-shrink (PIO_RX_BUF_SIZE 256 → 16, AND 0x0F mask).
- Layout migration: IVT 0xEB00 → 0xEC00, SCRATCH 0xEC00 → 0xED00
  (now holds the 16 B ring), dedicated PIO_RX page removed; CODE_BASE
  LDE80 → LDF80, DATA_BASE DDA80 → DDB80 (NDOS +0x100, +256 B TPA).
- 4 KB temporary PROM1 cap raise (the 2 KB cap requires more
  size-optimization work; the implementation overflows by 48 B
  compressed).

## Unparking trigger

User has bench-validated the Pi/Pico bridge timing per
`tasks/future-pi-bridge-timing-validation.md` (file is referenced
from session writeups but not yet present in the tree as of 2026-06-14;
the parking-resume plan should be drafted there when the hardware
work begins).

## When unparking, also revisit

- **Size optimization** to fit the 2 KB cap: either function-pointer
  dispatch via a `_xport_recv_block` JP trampoline (saves ~15-25 B
  compressed) or drop SIO support from the cpnos PROM1-only build
  (cpnos slave becomes PIO-only; rcbios + autoload still support SIO
  independently; saves ~60 B compressed).
- **Session 2026-06-13's MAME cpnet_bridge timing-fix plan** if MAME
  oracle verification is required before real-hw bring-up.

## See also

- `tasks/session-2026-06-14-inir-step-0-1-shipped.md` — Steps 0+1
  shipping writeup
- `tasks/session-2026-06-14-inir-step-2-4-blocked-on-size.md` — Steps
  2+4 implementation + the CPU-trace bisect that found the coupling
- `tasks/session-2026-06-13-phase4-inir-and-mame-findings.md` —
  MAME cpnet_bridge timing limitation (the upstream reason INIR
  can't be MAME-verified)
- `tasks/pio-input-busy-wait-and-inir-2026-06-12.md` — chip-handshake
  analysis showing INIR works on PIO Mode 1 without status polling
- `tasks/session-2026-06-14-windowed-trace-analysis.md` — measured
  ~50 µs/byte ISR ceiling that motivates the INIR work
