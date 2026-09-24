# Session 36 — file-I/O bench, TRANSPORT= flag, pulse design parked

Date: 2026-04-28 (continuation of session 35)
Branches:
- `ravn/rc700-gensmedet:pio-mpm-irq-fix`
- `ravn/mame-rc702-rc759-rc750:pio-mpm-irq-fix` (no changes this session)

## Headline

Built a **second workload** for the SIO/PIO-IRQ/PIO-PROXY bench
comparison — `filecopy`, a pre-assembled `FILECOPY.COM` that does pure
BDOS file I/O (open, loop F_READ + F_WRITE, close) over CP/NET, no
m80/l80 in the timed window.  Result: PIO modes show **1.8-2.0×**
speedup over SIO on the I/O-bound workload, vs only 1.3-1.4× on the
CPU-bound `sumtest`.  Also factored the slave's transport selection
into a `TRANSPORT={sio,pio-irq,pio-proxy}` build flag, added auto-exit
to the bench Lua tap, and added a 32-bit CRT frame counter at 0xFFFC
mirroring rcbios so workloads can record emulated time directly.

A "pulse" raw-bandwidth test (slave bypasses BDOS, drives chip ports
directly) was designed and discussed in detail but not built.  Parked
for later because building all-three-modes would require a bespoke
host script (`pulse_host.py`) that handles netboot then transitions
to byte-counter mode — ~3 hours of host-side Python for the full
shape, ~1 hour for SIO+PIO-IRQ TX-only.  Detailed design notes
captured below for the follow-up session.

## What landed (committed)

Branch `pio-mpm-irq-fix`:

- **`343a52f`** Makefile preflight checks bind tests to required setup.
  `_check-tag-pio-irq` / `_check-tag-not-pio-irq` / `_check-tag-pio-prx`
  grep `cpnos.bin` for the wire-mode tag emitted by
  `transport_sio_vt.name`.  `_check-mame-irq` looks at `cpnet_bridge.cpp`
  for the `m_brdy_high` gate-fix identifier and verifies the binary is
  newer than the source.  Origin: 2026-04-28 burn (Phase 27c) where
  `make cpnet-smoke` against an irq-fix slave silently produced a 0/N
  failure for an hour because the wire shape didn't match.

- **`be1059c`** Keep harness-required symbols + canonical
  `pio-irq-netboot` target.  `_pio_par_byte` / `_pio_par_count` were
  dropped by `ld.lld --gc-sections` after the IRQ-ring rewrite removed
  their writers, breaking `tests/cpnet_bridge/harness.py`'s symbol
  extraction.  `__attribute__((used))` alone wasn't enough; needed
  explicit `KEEP(*(.bss._pio_par_*))` in `payload.ld`.

- **`f0cc6de`** `pio-irq-smoke` workload bench against mpm-net2.  First
  PIO-IRQ wall-clock number for the m80+l80+sumtest workload.

- **`1fc963c`** `TRANSPORT={sio,pio-irq}` build flag, `sio-smoke` target,
  bench auto-exit.  snios.s now calls `_xport_send_byte` /
  `_xport_recv_byte`; Makefile aliases via `ld --defsym` to the chip-
  specific primitives at link time.  `clang/transport_stamp` invalidates
  the .o cache when TRANSPORT changes.  `mame_porttap.lua` exits MAME
  on marker (saving 20 minutes of `-seconds_to_run` idle per pass).

- **`b67b302`** `TRANSPORT=pio-proxy` + `pio-proxy-smoke` target.  Third
  mode: slave uses raw OTIR/INIR (`transport_pio_vt`), `cpnet_dispatch.c`
  sets `active_transport = &transport_pio_vt`, host runs
  `cpnet_pio_server.py --upstream 127.0.0.1:4002`.  Required #ifdef'ing
  out the IRQ ring (256 B at 0xF700 — pio-proxy doesn't use it) and
  preprocessing `payload.ld` so the upper-bound ASSERT could relax.

- **`092d323`** `filecopy` workload + 32-bit frame counter, 3-way I/O
  bench.  `testutil/filecopy.asm` (8080, hand-written, pre-assembled
  by `zmac -8 --dri`) does F_OPEN SUMTEST.ASM → loop F_READ + F_WRITE
  → F_CLOSE both → print `FILECOPY OK <N> S=<8hex> E=<8hex>` → JMP 0.
  S/E are snapshots of the new 32-bit frame counter at 0xFFFC..0xFFFF
  (incremented in `isr_crt`, mirrors rcbios's RTC location).
  `mksmokedisk.sh` assembles + stages `FILECOPY.COM` on the master's
  A: drive.  `smoke_inject.py --workload {sumtest,filecopy}` selects
  STEPS + finish marker.  `_verify-bench` Makefile target shared
  across modes; for filecopy it cpmcp-extracts both files from
  `drivea.dsk` and byte-compares the first
  `sizeof(SUMTEST.ASM)` bytes (the CPY tail is unavoidable CP/M
  record-pad — slave writes whole 128-byte records).

- Commits also for tasks/timeline.md (`6b19ab8`, `3f02cea`, `df5b2d9`,
  `b0938e9`).

## Bench results

`-nothrottle`, mpm-net2 backend, smoke_inject step1→marker is the
timed window:

| Workload  | SIO     | PIO-IRQ          | PIO-PROXY        |
|-----------|--------:|-----------------:|-----------------:|
| sumtest   | 35.8 s  | 27.5 s (1.30×)   | 25.4 s (1.41×)   |
| filecopy  | 14.8 s  |  8.4 s (**1.81×**) |  7.7 s (**2.02×**) |

Frames-to-completion (filecopy, 32-bit CRT counter @ 50 Hz):

| Workload  | SIO    | PIO-IRQ | PIO-PROXY |
|-----------|-------:|--------:|----------:|
| filecopy  | 3416   | 1883    | 1687      |

Workloads:
- `sumtest`: `m80 sumtest,=sumtest.asm` + `l80 sumtest,sumtest/n/e`
  + `sumtest`.  CPU-dominated; m80 alone is ~25 s of the SIO wall.
- `filecopy`: pre-staged `FILECOPY.COM` reads `SUMTEST.ASM` and writes
  `SUMTEST.CPY` record-by-record over CP/NET.  ~358 reads + ~358
  writes; no compiler in the timed window.  Verify: `cpmcp` extract
  + byte-compare first 45735 B (CPY tail is record-pad).

## Reproducible via

    make sio-smoke         WORKLOAD={sumtest,filecopy}
    make pio-irq-smoke     WORKLOAD={sumtest,filecopy}
    make pio-proxy-smoke   WORKLOAD={sumtest,filecopy}

Each target preflight-checks the cpnos build's wire-mode tag (SIO /
PIO-IRQ / PIO-PRX in `cpnos.bin`), the MAME tree has the bridge gate
fix (`m_brdy_high` in `cpnet_bridge.cpp`), and the binary is newer than
the source.

## "pulse" raw-bandwidth test — designed, parked

User asked for a third workload that "just tests transfer speed with a
minimum of overhead."  Design (not built):

- Slave program `pulse.com` (hand-written 8080) bypasses BDOS,
  SNIOS envelope, and `active_transport`; drives PIO-B / SIO-A chip
  ports directly.
- TX phase: send N=32 KB of pattern bytes via `OTIR` (PIO modes) or
  polled `OUT` loop (SIO mode).
- Wait for one ACK byte from host.
- RX phase: receive N bytes via mode-appropriate primitive.  PIO-IRQ
  uses the IRQ ring (busy-poll head≠tail).  PIO-PROXY uses tight
  `INIR`.  SIO polls `IN SIO_A_CTRL` / `IN SIO_A_DATA`.
- Snapshot frame counter at start + end; print
  `PULSE TX=<N> S=<8hex> E=<8hex>  RX=<N> S=<8hex> E=<8hex>`.
- JMP 0.

Host side requires a custom `pulse_host.py` that:
1. Listens on the appropriate port (4002 for SIO/PIO-IRQ, 4003 for
   PIO-PROXY).
2. Speaks just enough CP/NET 1.2 envelope to handle netboot of
   `cpnos.com` (LOGIN + OPEN A:CPNOS.IMG + READ-SEQ × N + CLOSE).
   ~150 lines borrowed from `netboot_server.py`.
3. After netboot, watches for a sentinel byte sequence from the
   slave's pulse phase (e.g., `0xC0 0xDE 0xCA 0xFE`).
4. On match: switches to byte-counter mode.
5. After N counted: sends 1 ACK byte.
6. Sends N pattern bytes (slave reads).
7. Closes.

Gives 5 distinct numbers (PIO-IRQ TX == PIO-PROXY TX at chip level,
so single PIO TX number; the two PIO RX paths differ):

- SIO TX, SIO RX (line-rate-limited, 38400 baud, ≈ 3.8 KB/s)
- PIO TX (one number for both PIO modes; OTIR-bounded by MAME bridge
  per-byte cost)
- PIO-IRQ RX (chip IRQ + ISR-push to ring + mainline pop)
- PIO-PROXY RX (Mode-1 INIR busy-poll, no ISR)

PIO-IRQ-RX vs PIO-PROXY-RX gives the IRQ-overhead-alone number, on
the same wire.

Time estimate:
- Full (3 modes × 2 dir): ~3 h (host-side Python is the bulk).
- Reduced (SIO + PIO-IRQ TX only): ~1 h.

Recommend reduced first.  RX + PIO-PROXY follow-on.

## Investigation thread: warm-boot port instrumentation didn't pan out

Earlier in the session I added a port-0x81 OUT in `impl_wboot`
(commit `b06e6dd`) so MAME Lua taps could count program exits.  We
then tried to make `JP 0` route through that path so transient programs
fire the count too — ZP[1..2] patched to point at a `warmboot_trap`
that does the OUT then chains to NDOS WBOOT at 0xCF03.

That broke l80 because **CP/M programs (and NDOS itself) read ZP[1..2]
to derive `BIOS_BASE = ZP[1..2] - 3`**.  Changing it from 0xCF03 to
~0xefc2 sent BIOS calls to garbage.  Reverted; warmboot_trap removed
from `resident.c`; impl_wboot's OUT remains in the ELF but is never
called from a `JP 0` path.

Open puzzle: **`install_write_tap` on the IO space registered cleanly
(`ok=true`) but the callbacks never fired** for actual Z80 OUT
instructions.  Both port 0x80 (sumtest done signal) and port 0x81
(warm-boot trap) have this symptom.  `mame_porttap.lua` records the
install state in `/tmp/cpnos_porttap_diag.txt`; that confirmed the
install succeeded.  Probably an API issue (wrong arg shape) or a
MAME-version-specific behaviour.  Filed as a follow-up.

## Issues / TODOs surfaced

### Build pulse-bench (parked)

See "pulse raw-bandwidth test" section above.  Design done, ~1-3 h
to implement.  Filed in `tasks/todo.md`.

### `install_write_tap` on IO space doesn't intercept Z80 OUT

Open puzzle.  Diagnostic: lua tap installs return `ok=true` but
callbacks never fire.  Tested with port 0x80 (sumtest emits OUT 80h
just before exit; verified the OUT executes by SIO-B output landing
"CPNET OK A314" before sumtest's RET) and port 0x81 (impl_wboot
OUT 81h, also verified to be reachable via disassembly).  Neither
fires the tap callback.

Hypothesis: the lua API expects a different arg shape, or the
`spaces["io"]` doesn't surface Z80 OUTs in this MAME tree.  Worth
30 min to verify by tapping a known-active port (e.g., 0x10 PIO-A
data, written constantly) and seeing if THAT fires.

Filed in `tasks/todo.md`.

### NDOS Err 06 Func 10 (Close Checksum Error) on m80/l80

Cosmetic noise during sumtest workload.  Per session 23, this is
"Close Checksum Error" from MP/M's FCB-checksum mechanism — m80
(CP/M-2.2-era, predates CP/NET) clobbers FCB reserved bytes between
F_MAKE and F_CLOSE, mpm-net2 rejects the close.  The data still gets
written correctly (sumtest produces correct .REL), but the noise
affects bench readability.  Same root cause as PIPNET fix in s23.

Possible fixes: build a CP/NET-aware m80 wrapper (significant), or
patch m80's close path (significant), or live with it.

### `cpnet_bridge` could be replaced by a bare bitbanger if we drop IRQ recv

Documented in `docs/cpnet_bridge_vs_bitbanger.md`.  The IRQ-driven
receive path is the only sub-path that genuinely needs `cpnet_bridge`'s
custom STB pulse + BRDY-edge logic.  Polled INIR receive (the
PIO-PROXY recv style) and Mode-0 TX both work with a bare bitbanger
wired to PIO-B's `in_pb_callback` / `out_pb_callback`.

Trade-off: simpler MAME side (-140 LoC), simpler slave side (-256 B
ring + ISR), but the slave busy-polls during transfers (no concurrent
work).

Worth considering as a "PIO-poll" mode complementing PIO-IRQ direct.
Filed in `tasks/todo.md`.

### Make targets still have duplicated launch logic

`pio-irq-smoke`, `sio-smoke` (cpnet-smoke body), and pio-proxy's
`_pio-proxy-smoke-impl` each inline the smoke_inject + MAME launch
sequence with mode-specific flags.  `_verify-bench` factored the
post-run verification.  Could similarly factor `_launch-bench` but
the per-mode flag differences make it less obvious.  Low priority.

## Lessons (saved as feedback memories)

- **Bench harness must self-terminate** (memory
  `feedback_bench_must_self_terminate`).  Saw `make pio-irq-smoke`
  appear to PASS but block 20 minutes per run (mame's `-seconds_to_run
  1200` was the only stop signal).  Manual `pkill regnecentralend`
  between iterations masked the gap.  When designing a bench harness,
  the "test complete" signal MUST drive the process termination.

- **No "want me to ...?" inside a debug loop** (memory
  `feedback_no_ask_in_debug_loop`).  When in an authorised debug
  cycle (MAME launches, mpm-net2, builds), proceed without asking;
  asking burns turns inside a known-safe iteration.

## Config: default restored to TRANSPORT=pio-irq

Plain `make cpnos` / `make cpnos-install` produce the PIO-IRQ binary.
Both MAME paths' ROMs now contain the PIO-IRQ build.  The other two
modes are reachable via `TRANSPORT=sio` or `TRANSPORT=pio-proxy`.
