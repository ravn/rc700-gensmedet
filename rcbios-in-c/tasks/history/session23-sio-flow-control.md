# Session 23 (2026-04-19/20) — SIO flow control bug + integration test

## Summary

Found and fixed a long-standing bug in the BIOS async TX paths that
defeated RTS flow control on both serial ports.  Added symmetric RTS
flow control to SIO-B.  Built a reusable 4096-byte bidirectional
integration test (`make sio-echo-test`) that exercises both SIOs via
BIOS routines directly.  Net BIOS size: 6013 → 6002 B (−11 B).

## The bug

`list_lpt`, `bios_punch_body` (SIO-A path), and `serial_conout` each
rewrote the SIO's WR5/WR1 on **every** transmitted byte, forcing
`RTS=1` (asserted) into bit 1 of WR5.  The RX ISR correctly deasserted
RTS when its 256-byte ring buffer hit `RXTHHI=248`, but the very next
TX byte clobbered it back.  Net effect on sustained bidirectional
traffic: null_modem never saw a sustained RTS-deassert, never paused
its TX, and the RX ring overran.

Observed on a 1024-byte bidirectional BIOS-direct echo test before the
fix:
- 276 bytes lost out of 1024
- ~1-in-3 byte loss rate after the first full 256-byte cycle
- Program hung at byte 748 of 1024 (RX blocked)
- MAME instrumentation showed `wr5=ea` (RTS=1) after every data_write

After the fix:
- 4096-byte bidirectional test passes clean (count=4096 mismatch=0)
- Instrumentation shows `wr5=e8` (RTS=0) during sustained RX → sender
  is paused as intended

## Fixes

### `rcbios-in-c/bios.c`

1. Removed WR5/WR1 per-byte rewrites from `list_lpt`,
   `bios_punch_body` SIO-A branch, `serial_conout`.  They had always
   been copies of an older defensive idiom that re-enables TX every
   byte; once the SIO is armed by `readi()` at boot, TX stays armed.
2. `readi()` now arms both SIO-A and SIO-B at boot (WR5 = wr5b+0x8A,
   WR1 = 0x1F) instead of just SIO-A.
3. Moved `readi()` to run **before** the cold-boot banner.  Previously
   banner bytes were lost on SIO-B because TX was not yet enabled and
   interrupts were off.
4. Added symmetric RTS flow control to `isr_sio_b_rx`: deassert at
   `RXTHHI`, drop on full.  `serial_conin` reasserts on empty.
5. Removed `serial_conout`'s 255-iteration timeout fallback (it was a
   workaround for pre-EI banner printing; no longer needed).

### `mame/src/mame/regnecentralen/rc702.cpp`

- `rs232b_defaults`: `FLOW_CONTROL` `0x00` → `0x01`.  Without this,
  even though the BIOS drives RTS-B correctly, null_modem ignored it.

## Integration test

New Makefile targets:

- `make sio-a-echo-test` — 4096 bytes bidirectional on SIO-A via BIOS
  `READER`/`PUNCH` direct (no BDOS).  Uses `tests/bios_echo_big.asm`,
  0xA5 sync handshake.  PASS iff `count=4096 mismatch=0 status=0xAA`.
- `make sio-b-echo-test` — 4096 bytes on SIO-B via BIOS `CONIN`/`LIST`
  (with `IOBYTE=0` so both routes to SIO-B only, bypassing CRT).
- `make sio-echo-test` — runs both.

Test harness:
- `tests/sioa_trace.lua` — MAME autoboot Lua that taps IO 0x08-0x0B
  (non-destructive), types the command at `A>`, dumps screen + result
  block on exit.  Keyboard buffer addresses read from bios.elf via
  `llvm-objdump` to survive BIOS size changes.
- `tests/sioa_feed_and_read.py` — TCP bridge that listens on port
  (4001 SIO-A, 4002 SIO-B), optionally waits for a sync byte from the
  CP/M program, sends the configured bytes, then captures the echoes.
- `tests/run_sioa_rx_test.sh` / `tests/run_siob_echo_test.sh` — shell
  drivers: patch bios.cim into disk image, install `.COM` via cpmcp,
  convert to MFI, launch MAME with the Lua script + socket.

## Open follow-ups

- [ ] RX ring hysteresis: `bios_reader` / `serial_conin` reassert RTS
      only when the ring is fully empty.  `RXTHLO=240` is defined in
      bios.h but unused.  Using a real low-threshold hysteresis would
      shorten the sender-paused interval under sustained load.
      Trade-off: more frequent RTS toggles.  Not urgent now that 4 KB
      passes clean, but worth revisiting if the echo throughput profile
      ever matters.
- [ ] The integration test currently kills MAME on a 30 s wall-clock
      timeout rather than detecting program completion on screen.  The
      status byte at 0x180 tells us pass/fail after the fact, but a
      completion marker-based MAME exit would shave seconds.
- [ ] The `0xA5` sync-byte handshake in the test programs is a
      convenience to avoid "first bytes lost to whatever ran before the
      CONIN loop" race.  The BIOS itself doesn't need it, but any
      future stress test should adopt the same pattern.

## Not touched

- SDLC / sync mode (sessions 18–21): the fixes are in async TX paths
  only; standalone SDLC programs re-initialize the SIO from scratch.
  No retest needed.

## Related MAME PR-track state

- `ravn/mame@1f2d4d000db`: rs232b FLOW_CONTROL default 0x00 → 0x01
  (symmetric to rs232a), so null_modem honors BIOS RTS-B.
- `ravn/mame#5` (SIO TX hang from session 22) is subsumed by the
  combined BIOS + rs232b fix and may be closed.

## Follow-up investigation — CP/NET vs MP/M (same session)

After the RTS fix shipped, retested CP/NET bring-up (which had been
wedged since session 22).  Trajectory:

1. **RTS fix alone was not sufficient.**  RC702 → MP/M still hung
   with `LOGIN PASSWORD`; SIO-A trace showed SNIOS sending `SOH + 2
   header bytes` then aborting mid-frame, retrying ENQ, server
   silent thereafter.

2. **Root cause: SDCC-vs-clang register-allocation mismatch.**  SNIOS's
   `MSGOUT` loop holds its byte counter in E across
   `CALL NETOUT → JP SENDBY → JP B$PUNCH`.  Clang's `bios_punch_body`
   uses D/E as scratch (saves the char in D and `iobyte_pun` in E
   before dispatching).  SDCC's codegen for the same function
   happened not to touch DE, so the bug lay dormant with SDCC.
   CP/M 2.2 BIOS spec requires **no** register preservation, so the
   shim was technically correct.

3. **Fix landed in SNIOS, not the BIOS.**  `SENDBY` now pushes/pops
   HL+DE around `B$PUNCH`, mirroring `RECVBY`'s existing pattern.
   `cpnet/snios.asm` (commit 41bc0fa).  BIOS shims stay spec-literal.

4. **End-to-end works against z80pack MP/M**:
   `CPNETLDR → LOGIN PASSWORD → NETWORK H:=B: → DIR H:` all succeed,
   MP/M's B: directory listed on CRT.  Closed three symptom issues
   (#12 NETWORK slow, #13 per-byte latency, #14 mid-header abort) —
   same root cause.

5. **File-write to MP/M: must use PIPNET.**  Stock `PIP.COM` from
   the RC702 boot disk triggers `NDOS Err 06, Func 10` = "Close
   Checksum Error" (per DRI CP/NET Ref Manual §3.2.1).  MP/M
   maintains an FCB checksum over reserved bytes; CP/M 2.2's PIP
   clobbers those bytes between F_MAKE and F_CLOSE.  Fix: use
   `PIPNET.COM` from `cpnet-z80/dist/` — the CP/NET-aware PIP.
   Closed #15 with the write-up.

6. **`cpnet-z80` added as a submodule** at workspace root (`~/z80`):
   read-only reference impl + DRI CP/NET manual.  Decoding the
   extended error codes and discovering PIPNET would have been
   far slower without it.

7. **New regression test: `cpnet/chksum_roundtrip_test.sh`.**
   2 KB deterministic fixture, PIPNET-based round-trip, three-way
   CHKSUM verification against pre-computed reference.  End-to-end
   byte-exact; PASS/FAIL output suitable for CI.

## Questions investigated and answered

- *Does CP/NET provide a "remote login to MP/M" feature?*  No.  The
  architecture is one-way (requester uses server's devices).  The
  `NETWORK CON:=n` command maps the *requester's* CON: onto the
  *server's* console hardware, which is the opposite of a remote
  shell.  DRI CP/NET Ref Manual §3.2.7 is explicit; no dedicated
  utility in `cpnet-z80/dist/` provides one either.  Recorded in
  todo.md.
