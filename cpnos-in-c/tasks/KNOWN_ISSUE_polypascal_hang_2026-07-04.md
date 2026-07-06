# KNOWN ISSUE (parked 2026-07-04): polypascal-test hangs after CP/NOS banner

## Status: PARKED — root cause not yet found, symptom fully characterized

## Symptom

`make cpnos-polypascal-test COMPILER={clang,sdcc}` (both compilers, both
identically) fails:

```
[ 12.00s] === stage 1 (deadline 30s): wait for E> on SIO-B; type WS launch
[ 42.01s] FAIL: timeout waiting for E> boot prompt
```

The CP/NOS banner **does** print correctly on both the CRT and the SIO-B
mirror (`RC702 CP/NOS 55K PIO clang 2026-07-04 15:09 d9c6b5b+`), but
nothing else ever appears — no `E>` prompt, no further output at all,
for the rest of the run (confirmed by direct memory dumps at t=15s,
25s, 35s: identical banner, blank rows below it, every time).

A live CPU-state dump during the hang shows:

```
PC=f246..f248  SP=f674  IFF1=1  IM=2  IX=ffff  IY=2008
```

`nm clang-prom1lineprog/payload.elf` resolves PC≈0xf246 to
**`_transport_recv_byte`** — the slave is spinning inside its own
byte-receive routine, waiting for a byte from the network transport
that never arrives. Interrupts are enabled (IFF1=1, IM=2) so this is
not a halted/crashed CPU — it is a live, unproductive polling loop.

This matches `cpnos-in-c`'s known-diligent LOGIN, but never gets far
enough to attempt one — the hang is below the wire-protocol layer,
in the transport byte-shuttle itself.

## What has been ruled OUT (confirmed working, in this exact environment)

1. **Autoload / BIOS PROM (PROM0)**: `make floppy-boot-test COMPILER=clang`
   in `autoload-in-c/` boots cleanly to `A>` with a real floppy image.
   Not implicated.

2. **cpnos PROM1 signature + SW1 DIP defaults**: the installed
   `prom1.ic65` has the correct `" RC702"` signature at the exact byte
   offset (0x2002) `autoload-in-c/rom.c`'s `prom1_if_present()` checks,
   and the SW1 S02 (PROM1 enable) DIP default is `On` (bit=0). Confirmed
   by the fact that the CP/NOS banner actually prints — the jump into
   PROM1 demonstrably happens.

3. **MP/M / mpm-net2 master itself**: a new tool,
   `cpnos-in-c/scripts/cpnet_ping.py`, speaks one full CP/NET 1.2 LOGIN
   round-trip (ENQ→ACK, SOH-header→ACK, STX-data→ACK, then the
   master's own ENQ→ACK, SOH→ACK, STX→ACK reply) directly over the raw
   TCP console at `127.0.0.1:4002`, bypassing MAME/PIO/SIO entirely. It
   deliberately sends a WRONG password (`PINGPING`, not `PASSWORD`) so a
   rejected login is the *expected*, side-effect-free success case. This
   probe **passes** against the currently-running `mpm-net2` — the
   master fully processes a real frame (network driver + BDOS + NDOS +
   login validation) and replies within milliseconds. **The master is
   alive and correctly speaking the wire protocol right now.**

4. **`cpnet_bridge.cpp` (the MAME PIO-port bridge device)**: no logic
   changes since the last known-good `polypascal-test` baseline
   (2026-05-31, issue #150). The only commit touching this file since
   then is `mame@4ade3656` (2026-06-13), which is logging-only (adds
   `logerror()` calls; the `read()`/`write()`/`rdy_w()` control flow is
   byte-for-byte unchanged). Confirmed via `git show` after deepening
   the (shallow-cloned) `mame` history with `git fetch --deepen=50`.

5. **Transport consistency ("PIO in both ends")**: the MAME command
   line uses `-piob cpnet_bridge` (slot tag `"piob"` = `m_pio_b` in
   `rc702.cpp`, the RC702's real PIO-B chip). `cpnet_bridge`'s device
   class (`rc702_pio_cpnet_bridge_device`, namespaced under
   `bus/rc702/pio_port/`) is PIO-port-only by construction — there is
   no separate SIO variant it could be mismatched against. The SW1 S03
   DIP is set to `0x00` (PIO) at machine start, matching
   `TRANSPORT=pio-irq` (the default). Both ends are confirmed
   consistently PIO.

6. **A previously real, matching MAME bug (`z80pio.cpp`,
   `mame@72c5e46c`, 2026-06-13, filed as `ravn/mame#11`)**: MAME's
   `z80pio_device::pio_port::set_mode(MODE_OUTPUT)` used to fire the
   output callback (which can call back into the chip via
   `strobe_w()`, exactly what `cpnet_bridge::write()` does to
   acknowledge a byte) **before** updating `m_mode`. A strobe-back
   arriving during that window would hit the *old* mode's handler —
   if that was `MODE_INPUT`, it would call `bridge::read()` and
   pollute `m_input` with a stale/sentinel byte. This is **exactly**
   the class of bug that would explain our hang. However: this bug
   was found and fixed on 2026-06-13, and the currently-installed
   `regnecentralend` binary (built 2026-06-14 00:11, i.e. *after* the
   fix) already includes it. So this specific race is not the current,
   live cause — though it establishes that this exact chip/bridge
   interaction is a known trouble spot.

## What is still UNEXAMINED (real, dated candidates)

Both of these post-date the last known-good baseline (2026-05-31) and
touch files in the RC702/PIO signal path, but have not yet been read
or bisected:

- **`mame@7be8a027`** — "rc702: wire 74LS74 CLK input -- ch2/ch3 DMA
  roll function". A timing/wiring change to the RC702 driver's DMA
  channel 2/3 clock input. Not yet diffed for relevance to the PIO/CTC
  interrupt path the IRQ-driven `pio-irq` transport depends on.
- **`mame@fb6da69a`** — "Merge mamedev/mame master (1061 commits,
  mame0284..mame0288)". A large upstream merge; could contain
  unrelated-looking changes to shared scheduler/timer/Z80-core/OSD
  socket code that indirectly affect this test. Not yet examined —
  expensive to review directly; a bisect (checking out intermediate
  commits and re-running a minimal PIO liveness test) would likely be
  cheaper than reading the diff.

## What changed as part of this investigation (kept, not reverted)

1. **`cpnos-in-c/Makefile`**: all 9 targets that start `mpm-net2` and
   wait for `:4002` now (a) time out after 20s instead of hanging
   forever if the port never opens, and (b) additionally require
   `scripts/cpnet_ping.py` to complete a full CP/NET LOGIN round-trip
   before proceeding — a real liveness check, not just "the kernel
   accepted the TCP SYN". Both gates fail loudly with a diagnostic
   pointing at `screen -r mpm` / the `mpm-net2` log.

2. **`cpnos-in-c/scripts/cpnet_ping.py`** (new): standalone CP/NET 1.2
   liveness probe, reusable for any future master-health check
   independent of MAME/PIO/SIO. See its docstring for the full wire
   sequence it drives.

## Environment notes for whoever resumes this

- **`mame` is a shallow clone** (`git rev-parse --is-shallow-repository`
  → true). `git log` only shows the most recent fetched commit by
  default. Run `git fetch --deepen=50` (or more) before trusting any
  `git show`/`git log -- <path>` result for this repo — a diff against
  the shallow boundary silently renders as "new file" and is
  meaningless. This bit us once already in this investigation (an
  earlier claim that `mame@3d77a3a3` "touched cpnet_bridge.cpp" was
  entirely a shallow-clone artifact and has been retracted).
- Last known-good `polypascal-test` PASS (both transports): 2026-05-31,
  issue #150 (per `rc700-gensmedet/CLAUDE.md` project state notes).
- `z80pack` submodule is at `8e5ce0e8` "milestone 2026-06-11:
  cpnet/mpm-net2 supports rebuilt MPM.SYS workflow" — also post-baseline
  and also not yet ruled in/out as a contributing factor (the
  `cpnet_ping.py` LOGIN probe only proves the master answers *a*
  frame correctly; it does not prove `mpm-net2`'s behavior is
  unchanged from the pre-milestone version for every code path
  `cpnos-in-c` exercises, e.g. drive I/O after a successful login).

## Suggested next steps (not started)

1. Bisect empirically rather than reading diffs: build/checkout `mame`
   at a handful of commits between the last known-good date
   (2026-05-31) and now, rerun the `_transport_recv_byte`-hang repro
   (a short, ~15s MAME run with the diagnostic PC-dump Lua snippet used
   in this session works fine and is cheap), and narrow the window.
2. Separately: `cpnos-shared/docs/CPNET_WIRE_PROTOCOL.md`'s
   "Slave-side deviations" section already documents that
   `cpnos-in-c`'s mid-frame receive is a **busy-wait with no timeout**
   (unlike the DRI reference, which times out and retries). That is a
   latent slave-side robustness gap independent of whatever the actual
   MAME/z80pack regression turns out to be, and is exactly why this
   hang has no natural timeout today. Worth its own follow-up
   regardless of how this issue resolves.

---

## RESOLVED 2026-07-06 (SIO) — the health-gate ping wedged the master

Root cause: the `cpnet_ping.py` startup gate added in eb116e9 (2026-07-04, the
SAME commit that documented this hang) does a full CP/NET LOGIN round-trip
against mpm-net2 and **consumes the master's single CP/NET connection**, leaving
its protocol state machine wedged mid-frame.  Proven directly: against a fresh
master, ping #1 PASSES but a 2nd connection gets ENQ (0x05) back instead of ACK.
MAME's slave is that 2nd connection, so it hangs in `_transport_recv_byte` after
the banner and never reaches E> — exactly the symptom above.  The diagnostic
tool corrupted the thing it was diagnosing; the #119 author ran the ping once,
saw it pass, and wrongly cleared the master.

Fix (Makefile, all polypascal-test variants): keep the ping (real health-check
value) but **restart the master FRESH afterwards** (`_kill-mpm` + `$(START_MPM)`)
so MAME connects to a pristine, un-probed one.  `make cpnos-polypascal-test
COMPILER=clang TRANSPORT=sio` now PASSES: `PPAS PRIMES ran to completion (29989
seen) and Q returned to E>`.

Also hardened in the same change: mpm-net2 lifecycle is now killed by the SAVED
screen-session PID (`pkill -P $PID`, parent-PID targeted) + an `lsof -t` orphan
fallback, instead of a broad `pkill -f cpmsim` that could reap an unrelated
cpmsim.  screen is retained for the launch because cpmsim needs a PTY on its
console stdin (a plain `</dev/null` EOFs the MP/M console into a busy-loop that
starves the CP/NET server — verified).

## STILL OPEN (PIO only): cpnet_bridge byte delivery — ravn/mame#6

With the ping fix, `TRANSPORT=pio-irq` still fails: the slave boots (banner) but
the `cpnet_bridge` MAME PIO-B slot device delivers the slave's first byte to the
master and never returns the reply (bridge log shows a lone `write(00) -> TCP`,
no refill).  This is the separate, already-parked `project_ravn_mame_6` PIO-B
timing regression at the MAME device layer — independent of the master-wedge bug
fixed here, and of cpnos code.  SIO is the working transport in MAME.
