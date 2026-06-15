# Session 2026-06-14 — #115 Steps 2+4 implementation, blocked on size AND on a layout regression

Continuation of the same-day Steps 0+1 session.  User picked path 1+3
from the menu (hand-rolled asm `transport_pio_recv_block` AND bundle
ring-shrink + TPA-grow layout migration in the same commit).
Implemented end-to-end; clang builds; compressed PROM overflowed 2 KB
cap by 48 B (user OK'd 4 KB MAME-only cap to verify functionally).
MAME oracle still FAILS, and bisect shows the failure is NOT in the
INIR path.

## What was implemented (then reverted, see "Where we are now" at bottom)

### Code changes

**`src/transport_pio.c`** — INIR block-recv with CKS fold in asm:

- `transport_pio_recv_block(uint8_t init_cks) -> uint8_t` __naked.
  sdcccall(1) A-in/A-out.  Body: push af + DI + drain (tail := head)
  + INIR via BSS args + EI + DJNZ fold over freshly-INIRed block.
  33 B.  Stashes dst+count on the stack across INIR to skip 7 B of
  BSS reloads for the fold.
- Ring shrunk 256 -> 16 B.  16-byte-aligned base (scratch_bss origin
  0xED00, low nibble 0).  isr_pio_par uses `ld hl, _pio_rx_buf; or l`
  in place of the page-aligned `_pio_rx_buf_page` trick.  Adds `AND
  0x0F` masks at head/tail.
- `pio_b_recv_block_body` (Step 1 scaffold) replaced by
  `transport_pio_recv_block`.

**`src/init.c`** — runtime dispatch flag:

- `uint8_t transport_uses_pio;` in default BSS (NOT `SECTION_RESIDENT_DATA`
  — that mistakenly placed it inside the loaded payload at 0xF30A,
  so install_transport's write overwrote code; manifested as both
  PIO and SIO transports hanging during cold boot.  Real fix is to
  let it land in `.bss.*` via scratch_bss.)
- `install_transport()` writes the flag UNCONDITIONALLY (cold BSS is
  NOLOAD and may hold garbage in the PROM1-only bootstrap).

**`src/snios_c.c`** — step (6) dispatch:

- Externs + step (6) refactor: prime byte (msg[5]) shared via
  `recv_byte_t()`, then `if (transport_uses_pio) { INIR } else
  { byte loop }`.

### Layout migration (ring-shrink + TPA-grow)

**`clang-prom1lineprog/payload.ld`**: IVT 0xEB00 -> 0xEC00, SCRATCH
0xEC00 -> 0xED00 (now holds the 16 B ring at its base), dedicated
PIO_RX region removed.  PAYLOAD stays 0xEE00, so NIOS=0xEE33 unchanged.

**`sdcc-prom1lineprog/sections.asm`**: mirror layout.

**`cpnos-build/Makefile`**: CODE_BASE LDE80 -> LDF80, DATA_BASE DDA80
-> DDB80.  NDOS 0xDE80 -> 0xDF80 / BDOS dispatch 0xE816 -> 0xE916
(TPA +256 B).

**`clang-prom1lineprog/prom1.ld`**: PROM1 cap temporarily lifted 2 KB
-> 4 KB.  MAME-only until size optimization returns it under 2 KB
(memory rule `project_rc702_2kb_prom_hard_limit`).

## Size — fits 4 KB cap; 48 B over 2 KB cap

| Stage                       | payload.bin | payload.zx0 | PROM1 result            |
| --------------------------- | ----------: | ----------: | ----------------------- |
| Baseline (Step 0+1)         |      1990 B |      1387 B | 2017 / 2048 (31 B free) |
| First Step 2+4 (C glue)     |      2094 B |      1479 B | overflow 59 B           |
| + CKS fold moved to asm     |      2082 B |      1467 B | overflow 47 B           |
| + push BC/HL skip reload    |      2080 B |      1468 B | overflow 48 B           |
| + BSS-init flag bug fix     |      2086 B |      1474 B | overflow 50 B           |

## Why it doesn't pass the MAME oracle

User asked to compare bytes received by MAME vs sent by mpm.  Captured
via `cpnet_bridge` `logerror` in `/tmp/cpnos_dir_bridge.log`.  Result:

- First exchange (slave LOGIN, master 1-byte response): WORKS END TO
  END.  Slave sends ENQ + SOH + 5-byte SCB + HCS + STX + 8 password
  bytes + ETX + CKS + EOT, master ACKs each phase + responds with a
  1-data-byte frame.  Slave ACKs the 1-byte response (visible in
  bridge log at t=1.107s).
- Second exchange (slave READ.IMG, master 37-byte response):
  - Slave sends READ request: SOH + SCB + HCS + STX + data + ETX +
    CKS + EOT.  All ACKed by master.
  - Master sends response: ENQ -> ACK by slave at t=1.146s.  SOH +
    SCB + HCS at t=1.147s.  Slave ACKs at t=1.148s.  Master sends
    data block STX + 37 data bytes + ETX + CKS + EOT at t=1.149-
    1.151s.
  - **Slave reads all 41 bytes correctly** (last is EOT 0x04 at
    t=1.151s).  Bytes received match bytes sent byte-for-byte.
  - **Then silence.**  Slave never sends the post-EOT ACK.  No more
    writes appear in the bridge log for the remaining ~150 s of
    simulation.

## Bisect (with CPU-state inspection via MAME debugger trace)

User suggested: ask MAME what the CPU is doing.  Ran
`cpnos-polypascal-test-trace` which captures every instruction to
`/tmp/z80_trace.txt`.  Bisected by reverting to baseline and re-adding
the smallest plausible-breaking change: **ring shrink alone (PIO_RX_BUF_SIZE
256 -> 16 + AND 0x0F mask in isr_pio_par + transport_pio_recv_byte).
Nothing else.**  Test FAILS.

Trace inspection shows:

- **CPU dead-looping at PC=0xF301**: the `jr $f301` at the tail of
  `_resident_handoff`, hit when entry == 0 (netboot returned failure).
- **Slave was in step (1) ENQ wait** (`_transport_pio_recv_byte`
  polling F2AC..F2BA, counter at $EC3E decrementing) -- meaning slave
  ABANDONED a try_recv_frame attempt (RC_RETRY) and is now waiting for
  master's ENQ on a retry.
- **17 ISR fires (EEC6), 2 went to the drop path (EEE5)**.  12 % drop
  rate.  Bridge log delivered 68 bytes to slave; trace's loop-collapse
  under-counts but the drops are real and confirmed.

## Why ring-shrink alone is fundamentally broken

The design refinement (`session-2026-06-13-phase4-inir-and-mame-findings.md`
"Design refinement" section) assumed the ring only carries **control
bytes** post-INIR (max burst = 8 B).  But that ONLY holds when INIR is
the data path:

| INIR active? | Data bytes path                  | Ring traffic                |
| ------------ | -------------------------------- | --------------------------- |
| YES          | INIR direct to msg+5..msg+SIZ+5  | control bytes only (max 8 B)|
| NO           | recv_byte_t -> ring              | ALL bytes incl data block   |

With INIR inactive (my forced bisect: `transport_uses_pio = 0`), every
data byte goes through the ring.  Bridge poll_tick refills the chip
FIFO in bursts of up to 41 bytes; chip drains at ~46 us/byte while
slave ISR takes ~50 us/byte; ring fills past 16 entries during the
burst; ISR drops bytes (EEE5 path); slave's step (7) ETX check or
step (8) CKS check fails; RC_RETRY without sending NAK; outer loop
waits for ENQ that never comes (master is waiting for our ACK that
we never sent).  Deadlock.

**The two changes are COUPLED**, not independent:
- Ring-shrink REQUIRES INIR.
- INIR is needed for the throughput goal but **doesn't work in MAME**
  (cpnet_bridge TCP-bound timing can't honor chip Mode 1 per-iter
  handshake -- session 2026-06-13).

So the bisect outcome is: in MAME there's no working configuration of
the bundle.
- Ring-shrink + INIR: INIR hangs on bridge timing.
- Ring-shrink + no INIR: ring overflows.
- No ring-shrink + INIR: INIR still hangs (size doesn't matter).
- No ring-shrink + no INIR: PASS (== baseline).

The bundle is **only verifiable on real hardware** (Pi/Pico fast
strobe lets INIR work; ring stays small because INIR bypasses it).

## What to do next session

1. **Decide MAME stance**: option A is to revisit the
   `session-2026-06-13` cpnet_bridge timing work (add per-byte
   synchronous bridge strobe so INIR can be MAME-tested) -- a bigger
   project.  Option B is to park MAME verification entirely and gate
   the bundle on real-hardware bring-up (the Pi/Pico work in
   `tasks/future-pi-bridge-timing-validation.md`).
2. **If pushing forward**: re-add the full bundle (layout + asm wrapper
   + dispatch + ring-shrink), restore the 4 KB PROM cap MAME-only,
   ship to real-hw via the pi-bridge path.  Don't expect MAME to be
   green.
3. **If pausing**: ship only Steps 0+1 (already in main as
   commits 9592c2d + 50cc0bf).  Leave Steps 2+4 + layout migration on
   the shelf with this writeup as the rationale.

## Files modified during the session (reset to HEAD before this writeup, EXCEPT transport_pio.c which retains the ring-shrink-only bisect change)

- src/transport_pio.c (ring shrink + AND mask in ISR; minimum
  reproducing failure for the writeup)
- src/init.c, src/snios_c.c -- at HEAD
- clang-prom1lineprog/payload.ld, clang-prom1lineprog/prom1.ld -- at HEAD
- sdcc-prom1lineprog/sections.asm, cpnos-build/Makefile -- at HEAD

## Where we are now (working tree state)

ALL source-file changes (transport_pio.c, init.c, snios_c.c,
payload.ld, sections.asm, prom1.ld, cpnos-build/Makefile) have been
git-checkout'd back to HEAD.  Baseline PIO oracle re-verified PASS at
51.95 s.  Build artefacts in clang-prom1lineprog/ are still from
intermediate experiments and will rebuild on next `make`.

## What to do next session

1. **Bisect the layout migration vs ring shrink**: re-add changes ONE
   AT A TIME with PIO oracle between each:
   - Add ONLY the asm wrapper (unreferenced) -> test PIO.
   - Add ring shrink (PIO_RX_BUF_SIZE 16 + isr_pio_par rewrite) ->
     test PIO.
   - Add layout migration (IVT/SCRATCH move) -> test PIO.
   - Add transport_uses_pio flag + install_transport store -> test
     PIO (default = 1, so step (6) takes PIO branch via INIR, expect
     hang due to MAME timing per session 2026-06-13).
2. **Once isolated**, fix the regression.  Suspect candidates:
   - The OR-L trick in isr_pio_par may corrupt HL on the path where
     the buffer's low byte ISN'T 0 (i.e. the build's actual address
     ended up at 0xED10 or similar instead of 0xED00).  Verify
     `_pio_rx_buf` is exactly 16-aligned post-link.
   - The new `and 0x0F` after `dec a` for old_head: if the
     compiler-or-assembler emits the wrong opcode (e.g. `and a` zero-
     operand instead of `and $0f` immediate-form), the masking is
     wrong.  Verify via objdump.
3. **After the bisect**, attempt the size-optimization passes:
   - Function-pointer dispatch via xport_jt trampoline (Steps 2+4
     option A): defines `_xport_recv_block`, install_transport
     patches it to PIO impl (current) or new SIO impl (byte loop with
     sticky-error flag).  Eliminates the if(transport_uses_pio)
     branch in snios_c.c (saves ~15-25 B compressed).
   - Or drop SIO from cpnos PROM1: cpnos slave becomes PIO-only.
     Saves ~60 B compressed.  Cost: SW1 bit 2 SIO mode doesn't work
     in cpnos (rcbios + autoload still support SIO independently).
4. **Once size is back under 2 KB**, restore PROM1 cap to 2 KB,
   restore the `0xF60E` payload-end ASSERT, commit the bundle.

## See also

- `tasks/session-2026-06-14-inir-step-0-1-shipped.md` — Steps 0+1
  baseline this builds on.
- `tasks/session-2026-06-13-phase4-inir-and-mame-findings.md` — the
  MAME cpnet_bridge timing limitation (relevant when actually trying
  to verify the INIR path; not the cause of the current regression).
- `/tmp/cpnos_dir_bridge.log` — byte-level wire trace from the
  failing run.  Captures every read() and write() on PIO-B with
  timestamps.

## Files modified during the session (reset to HEAD before this writeup)

- src/transport_pio.c, src/init.c, src/snios_c.c
- clang-prom1lineprog/payload.ld, clang-prom1lineprog/prom1.ld
- sdcc-prom1lineprog/sections.asm
- cpnos-build/Makefile
