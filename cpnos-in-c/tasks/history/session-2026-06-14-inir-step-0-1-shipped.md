# Session 2026-06-14 — #115 INIR Steps 0 + 1 shipped; Step 2+4 blocked on PROM size

Continuation of the 2026-06-14 windowed-trace analysis session.  User
overrode the cpnos parallel-cable park as **speculative** (MAME oracle
only, real-hw validation gated on task #11) and asked me to "go as
far as you can" on the INIR plan.

## Shipped (verified on MAME, both compilers green)

### Step 0 — strip per-VRTC DMA reload, lean on autoinit (commit `9592c2d`)

`isr_crt` previously masked DMA ch2+3, reloaded source addr 0xF800
and word count 0x07CF, then unmasked — ~150 T-states / VRTC that was
redundant because `init.c:224-225` programs DMA ch2 in autoinit mode
(0x5A bit 4 set).  The 8237 reloads its base regs on terminal count
automatically; the ISR's reload was always after the channel had
already reloaded itself.

Why this matters for #115: a `DI` bracket around an INIR block-RX
(~1.5 ms at max-size CP/NET frame) needs display refresh to keep
running without the VRTC ISR firing.  With autoinit + ISR-reload, DI
would freeze the display.  With autoinit alone (this strip), display
is self-sustaining and DI is safe.

Footprint:
- PROM1 clang: 2033 → 2007 B (−26 B, 41 free)
- PROM1 SDCC:  2151 → 2120 B raw (−31 B)
- ISR body: ~180 T → ~30 T per VRTC

Investigation prior: the autoload-in-c PROM briefly enabled autoinit
at `f11b78b` (2026-03-23) then reverted at `09efa39` because the
autoinit "workaround" was no longer needed once an unrelated FDC ISR
timing bug was fixed.  cpnos has had `0x5A` programmed in init.c
since at least 2026-05-18 — but the ISR was still doing the redundant
reload until this commit.

rcbios was NOT touched (#22): it uses mode `0x4A` non-autoinit, and
its DSPITR per-frame reload IS the refresh mechanism.  Same change
would garble rcbios's display.

Verified: `cpnos-polypascal-test COMPILER=clang` PASS in 50.51 sim sec
+ 5-frame visual capture (banner / PPAS load / L PRIMES load /
mid-flood / late-flood, all crisp).  Capture at
`scratch/mame-videos/20260614T005820_polypascal_clang_pio-irq.mp4`.

### Step 1 — additive `pio_b_recv_block_body` scaffold (commit `50cc0bf`)

`__naked` function that runs INIR on PIO_B_DATA into a BSS-pointed
buffer (`pio_block_dst`, count in `pio_block_count`).  No call sites
yet.  BSS-args calling convention avoids clang vs SDCC sdcccall(1)
drift.  Caller responsibilities documented in the block comment
(bracket DI/EI, prime the chain via a preceding single-byte recv).

Footprint:
- PROM1 clang: 2007 → 2016 B (+9 B, 32 free)
- PROM1 SDCC:  2120 → 2132 B raw (+12 B)

Verified: `cpnos-polypascal-test COMPILER=clang` PASS in 47.25 sim sec
(no functional change; new function is unreferenced so no behavior
delta — the speed-up vs Step 0 baseline is run-to-run variance).

## Blocked — Step 2+4 (wire variant H + DI bracket)

### What was attempted

Wrote `transport_pio_recv_block(uint8_t *dst, uint8_t n)` in C in
`transport_pio.c`:

1. drain pio_rx_buf of any bytes ISR queued during prior protocol-
   byte processing
2. prime via `transport_pio_recv_byte` (ring path, IRQs on)
3. `intrinsic_di()` to block `isr_pio_par` from racing INIR
4. drain ring again — catches any byte ISR pushed between recv_byte_t
   return and DI executing
5. `pio_b_recv_block_body()` for the rest
6. `intrinsic_ei()`

Added `uint8_t transport_uses_pio` flag in `init.c`, set by
`install_transport()` based on SW1 bit 2 (S03).  Branched in
`snios_c.c` `try_recv_frame` step (6) data loop to dispatch
PIO → recv_block + post-block CKS fold, SIO → original per-byte
loop.

### Why it didn't ship

Raw payload grew 2016 → 2248 B (+232 B); compressed went 1404 → 1580 B,
overflowing the 2 KB PROM cap by 176 B.

Breakdown of the +232 B:

- C version of `transport_pio_recv_block`: two while loops + function
  call + 4 BSS reads + post-call cleanup.  Clang -Oz produces
  ~70 B of code for it.
- `transport_uses_pio` flag handling in init.c + snios_c.c.
- snios_c.c branch + post-block CKS fold.

The architecture works; the encoding is too verbose for the PROM cap.

### Path forward

Re-attempt with **hand-rolled asm** for `transport_pio_recv_block`:

```asm
; transport_pio_recv_block(uint8_t *dst, uint8_t n) -> uint8_t
;   dst in DE per sdcccall(1) first arg; n in A (second arg per
;   z88dk-sdcc), or n via BSS as in Step 1.
;
; Estimated body: ~40 B asm vs ~70 B C.  Savings ~30 B.
; Add the flag (~10 B init.c + ~15 B snios_c.c) and we're at
; ~25 B net growth vs current 32 B headroom -- TIGHT but should fit.
;
; Pseudocode:
;   PUSH HL ; PUSH BC
;   LD HL,DE                  ; HL = dst
;   ; --- drain phase 1 ---
;   LD A,(pio_rx_head)
; drain1:
;   LD B,A
;   LD A,(pio_rx_tail)
;   CP B
;   JR Z, drain1_done
;   ...
;   ; --- prime via recv_byte_t ---
;   ; (call back into C transport_pio_recv_byte; saves a lot of asm)
;   ; --- DI + drain phase 2 + INIR + EI ---
;   ...
```

Alternative: skip the second drain (saves ~15 B but races on rare
edge-case where ISR fires between recv_byte_t return and DI).
Probably safe in practice.

Alternative #2: reduce CKS fold cost by accumulating during INIR
itself — but INIR has no accumulator hook; would need to switch to
an INI loop with manual ADD A,(HL); INC HL; DEC B; JR NZ.  That gives
~28 T/iter vs INIR's 21 — modest cost (~30 % slower) but folds CKS
in-line, eliminates the post-block loop.  Worth measuring.

### Decisions left for next attempt

1. Hand-rolled asm vs INI-with-CKS-accumulator vs accept the second-
   drain skip — which keeps the slave robust on real hardware.
2. Whether to commit the per-byte CPU win even if MAME PASS is
   non-conclusive (cpnet_bridge timing race per 2026-06-13 still
   applies; the DI bracket is necessary but maybe not sufficient on
   MAME).
3. Whether to bundle the ring-shrink-to-16 + TPA-grow from the
   2026-06-13 design refinement in the same commit so the layout
   migration happens once (frees ~240 B in PIO_RX, easily covers
   the C version's growth).  This is the cleanest fix; defer
   intentionally since the layout move is its own work item.

## What this session's work unblocked

- Step 0 (autoinit isr_crt) is a **structural enabler**.  Even
  independent of #115, it removes the per-frame DMA reload cost
  and makes any future DI bracket cheap.  Shippable on its own.
- Step 1's `pio_b_recv_block_body` is the INIR primitive.  Available
  for any caller (variant H, Phase 4, real-hw bench).
- The wiring architecture (transport_uses_pio flag + branch) is
  worked out — next attempt just needs the smaller asm encoding.

Steps 0 + 1 are now in the bin and verified MAME-green.  Steps 2+4
are paused on the PROM size cap; the design is correct, only the
code-density encoding needs work.

## Tasks added during this session

- #22 — Share common code between cpnos-in-c and rcbios (future, after #115 settles)
- #23 — Step 0 (COMPLETED)
- #24 — Step 1 (COMPLETED)
- #25 — Step 2+4 (IN PROGRESS, paused on size cap)

## See also

- `tasks/pio-input-busy-wait-and-inir-2026-06-12.md` — chip-handshake
  analysis showing INIR works on PIO Mode 1 without status polling
- `tasks/session-2026-06-13-phase4-inir-and-mame-findings.md` —
  prior variant H attempt + MAME bridge timing wall
- `tasks/session-2026-06-14-windowed-trace-analysis.md` — measured
  ~50 us/byte ISR ceiling that motivates #115
- The cpnos-in-c PROM1 line program at PROM1ONLY_BIN (compiled to
  prom1-lineprog.bin under `clang-prom1lineprog/`)
