# KNOWN ISSUE (open, parked 2026-07-07): polypascal-test reaches E> in a PERFECTLY ALTERNATING pass/fail pattern

Status: OPEN. Root cause NOT found. Deterministic F,P,F,P alternation fully
characterized; both master-side byte-trace diagnostics hit walls (documented
below so they are not re-attempted blindly).

## UPDATE 2026-07-07 (later): MAME EXONERATED — flake is SIO-intrinsic, not a MAME regression

A pre/post-merge MAME A/B settled the "it worked before" hypothesis. The
suspicion was that the 2026-06-16 MAME upstream merge (`fb6da69a`, 1061 commits
mame0284..0288) broke the transport. Built a pre-merge MAME
(`7be8a027`, 2026-06-14, the merge's non-upstream parent) in a git worktree and
ran the boot-to-E> gate (`SECONDS_TO_RUN_POLYPASCAL=25`, 6 runs each), current
firmware unchanged, only the MAME binary varying:

| Transport | pre-merge MAME (7be8a027) | post-merge MAME (current) |
|-----------|:------------------------:|:-------------------------:|
| **PIO** (pio-irq) | PPPPPP (6/6) | PPPPPP (6/6) |
| **SIO** (sio)     | PFPFPF       | PFPFPF (this doc)         |

Conclusion: the variable is **transport, not MAME version**. SIO alternates
PFPFPF identically on BOTH MAME builds → the MAME merge is NOT the cause;
rolling MAME back does NOT fix the flake. PIO reaches E> rock-solid (6/6) on
both. So the flake is **intrinsic to the SIO byte-path**, and "it worked
before" = PIO (still reliable today). Refocus root-causing on the SIO transport
(`-rs232a null_modem -bitb1 socket:4002` direct SIO-A socket), NOT MAME.

Two side-findings from this A/B:
- **Master-side bug fixed:** the `cpmsim` binary was built with `WANT_ICE`
  enabled (from z80pack `sim.h` commit 8afbaaf1), so `mpm-net2` dropped into the
  ICE monitor (`>>>`) at boot instead of auto-booting MP/M — :4002 opened but
  the CP/NET server never ran, so the health-gate ping got "Connection reset by
  peer" and blocked EVERY polypascal run regardless of MAME/transport. Fixed by
  rebuilding cpmsim from the (already-committed) `WANT_ICE`-off source. If the
  health gate ever fails with connection-reset again, check the cpmsim binary
  was rebuilt after any `sim.h` change.
- **mame#6 / "PIO blocked" claim RESOLVED:** full PIO runs (default 240s cap)
  on the CURRENT MAME completed the whole PPAS primes run to 29989 and returned
  to E> — 2/3 full runs PASS (the 1 failure was a boot-stage E> timeout at ~42s,
  siob=81 B, NOT a primes/throughput failure), plus 6/6 on the 25s boot gate. So
  the **shipping PIO ISR+ring transport WORKS on MAME** (~85-90% boot
  reliability, ~47s to complete primes when it boots). The "PIO blocked by
  mame#6" wording in this doc + CLAUDE.md is misleading: it applies only to the
  **PARKED INIR fast-path** (#115 Steps 2+4), which needs different cpnet_bridge
  timing and is not in the shipping build. The shipping PIO path is the reliable
  transport; SIO is the flaky one.
  - PIO's occasional boot-E> timeout is a DIFFERENT phenomenon from the SIO
    flake: it is a rare (~10-15%) boot-stage transient, NOT the SIO deterministic
    50% mod-2 PFPFPF toggle. Do not conflate them.

This is a SEPARATE, residual issue on top of the ping-wedge hang that was fixed
2026-07-06 (see `KNOWN_ISSUE_polypascal_hang_2026-07-04.md`). The ping-wedge was
100% fail; this is the ~50% flakiness that remains after that fix.

## Symptom

`make cpnos-polypascal-test COMPILER=clang TRANSPORT=sio` reaches the slave's
`E>` prompt in a **perfectly alternating** pass/fail pattern. Measured cleanly
with a short run + a direct E> check over 15+ consecutive runs:

```
make cpnos-polypascal-test COMPILER=clang TRANSPORT=sio SECONDS_TO_RUN_POLYPASCAL=25
grep -a "E>" /tmp/cpnos_siob.raw    # present => reached E> (PASS)
# between runs: screen -S mpm -X quit; pkill -KILL -f cpmsim; screen -wipe; sleep 1
```

Result: `F,P,F,P,F,P,F,P,F,...` — 100% alternation, not the random ~50% spread a
pure timing race would give. On FAIL, `/tmp/cpnos_siob.raw` is **exactly 54
bytes** (the banner only); the slave hangs in its first CP/NET login and never
reaches E>. On PASS, PolyPascal primes run to 29989.

A perfect mod-2 toggle means **some state persists between runs and flips each
time** — even though BOTH MAME (a fresh process) and the master (cpmsim,
killed+restarted) are new every run.

## Ruled OUT (with evidence)

1. **Master login-state persistence.** 3 read-only Explore agents confirmed the
   CP/NET login table (`configtbl` = G$NUM/G$VEC/G$LOG) in
   `z80pack/cpmsim/srcmpm/netwrkif-0.asm:485-492` is RAM-only, zero-initialised
   at assembly, and NEVER written to disk. `mpm-net2` (line 31) deletes all
   drive images and re-copies fresh at every launch. So the master starts clean
   each run. (Aside: if a SID *were* already logged in, `server.asm:1399-1405`
   returns success without a password check — but that state cannot survive a
   cold boot, so it is not the source.)

2. **Pre-MAME socket state.** Instrumented the Makefile to dump
   `lsof -nP -iTCP:4002` (ALL states) + `netstat | grep 4002` immediately before
   each MAME launch. On BOTH P and F runs: one fresh `cpmsim` LISTEN socket + 2-4
   client-side TIME_WAIT sockets (from the `nc -z` + `cpnet_ping` probes). NO
   lingering ESTABLISHED/CLOSE_WAIT server connection. TIME_WAIT count did NOT
   correlate with P vs F.

3. **Reopen / TIME_WAIT timing ("port reopened too quickly").** Added a 15 s wait
   after cpmsim was ready (`nc -z` OK) and before the MAME launch. The
   alternation **persisted unchanged** (P,F,P,F,P,F). Waiting for the socket
   churn to settle does not help — this rules out the reopen-timing hypothesis.

4. **Buffering as the reason diagnostics saw nothing.** Rebuilt cpmsim with
   unbuffered stdout (`setvbuf(stdout, NULL, _IONBF, 0)` in
   `z80pack/z80core/simmain.c`); the MP/M-server marker (below) STILL did not
   appear — so it is not a stdout-buffering artefact.

## Diagnostic DEAD-ENDS (do not re-attempt blindly)

- **MP/M-server console log.** Added a register-safe `'L'` marker to the CP/NET
  server login handler (`cpnet/mpm-server/server.asm`, just before `login:` at
  ~1389) and rebuilt MPM.SYS via `bash cpnet/mpm-server/rebuild-mpm-sys.sh
  --install` (toolchain works: vcpm rmac+link+GENSYS, Java 25). The handler IS
  reached (dispatch `server.asm:298` FNC 64 -> routine 13 -> `login:324`; the
  `val0` validation at `:546` lets login frames through with `sui loginf / rz`).
  BUT the marker's console output NEVER reached cpmsim's stdout: BDOS C_WRITE
  (fn 2) goes to the RSP's own console, not stdout; BIOS conout **device 0**
  (via `biosv`, exactly like the server's own conout handler) also did not
  reach stdout. cpmsim's operator console (stdout) is evidently a different
  console/device number than 0 (cpmsim exposes consoles as network ports).
  Would need the correct operator-console device number.

- **cpmsim SNETDEBUG** (server-side serial byte-trace, `-DSNETDEBUG` added to
  `z80pack/cpmsim/srcsim/Makefile` DEFS). Rebuilding with it makes cpmsim **drop
  into its own monitor** (`>>>` prompt + a Z80 register dump) instead of booting
  MP/M. Cause: SNETDEBUG's `printf` runs inside the SIGIO / O_ASYNC console-read
  handler (signal context), where `printf` is unsafe and corrupts state. To use
  SNETDEBUG it would have to buffer the bytes to a static array and flush from
  the main loop, not printf-in-signal.

## Current best hypothesis (unproven)

**MAME <-> cpmsim dual-emulator timing coupling.** The slave (MAME-emulated) and
the master (cpmsim-emulated MP/M) are coupled by a WALL-CLOCK TCP socket, each
running at its own speed. The slave's CP/NET recv-timeouts are counted in
emulated T-states; the master's response latency is the master emulator's
wall-clock time. Under `-nothrottle` the two emulators' relative speed/phase at
the moment MAME connects appears deterministically phase-locked (a constant
per-run setup time gives a constant connect phase, which alternates the
outcome). Consistent with the lua's own note in
`cpnos-shared/mame/polypascal_test.lua` (~line 240): *"dot_watch disabled: tap
callback overhead slowed MAME below realtime and stalled the test."* Not proven
because the master-side byte trace could not be captured (both dead-ends above).

NOT fully ruled out: deterministic MAME-side persistent state (an rc702 NVRAM /
cfg that MAME saves on exit and reloads on start).

## Untested pragmatic fixes (for a future session)

- **`-throttle`** (MAME realtime) on the SIO polypascal MAME line
  (`cpnos-in-c/Makefile`, the `-nothrottle` in the `ifeq ($(TRANSPORT),sio)`
  branch). If realtime stops the alternation, the emulator-timing coupling is
  confirmed and throttle is the fix (cost: real-time test, ~240 s wall-clock per
  run at `SECONDS_TO_RUN_POLYPASCAL=240`).
  **Test it on the COMMITTED Makefile** — an earlier screen-free pipe-based
  master refactor had a make-hangs-on-background defect: `$(MAKE) _start-mpm`
  never returned because make waited for the backgrounded `sleep`/cpmsim, so
  MAME never launched ("starter ikke"). Any screen-free master MUST fully detach
  (`( ... & )` subshell / `nohup`+disown).
- **Larger slave `RECV_TIMEOUT_TICKS`** in `cpnos-in-c/src/snios_c.c` (more
  emulated patience -> tolerates a slower master response at high MAME speed).
  Firmware change, but benign on real hardware (just a longer receive timeout).

## Reusable diagnostic tooling notes

- Boot-to-E> reliability harness (isolates the login flake from the 4-minute
  primes run): `make cpnos-polypascal-test ... SECONDS_TO_RUN_POLYPASCAL=25`,
  then `grep -a "E>" /tmp/cpnos_siob.raw`. FAIL siob.raw = 54 bytes (banner).
- Master console capture: cpmsim console 0 -> stdout is FULL-buffered when stdout
  is a pipe (small post-boot output not flushed). The boot banner (>4 KB) flushes
  and carries `0A>`. Post-boot capture needs unbuffered cpmsim stdout (setvbuf),
  but that alone did not surface the server marker (console routing, above).
- The MPM.SYS rebuild works: `bash cpnet/mpm-server/rebuild-mpm-sys.sh --install`
  rebuilds `server.rsp` from the patched `server.asm`, runs GENSYS via vcpm,
  installs MPM.SYS to `z80pack/cpmsim/disks/local/mpm-net2-1.dsk`. Needs Java +
  cpmtools.
- `cpnet_ping.py` WEDGES the single-connection master (the #119 root cause): a
  2nd connection to a just-pinged master gets ENQ (0x05) back instead of ACK. So
  you can only get ONE clean login per fresh master.

## Relationship to other issues

- Separate from the ping-wedge (#119) fixed 2026-07-06 (that was 100% fail; this
  is the residual ~50% alternation).
- PIO transport is separately blocked by ravn/mame#6 (reopened 2026-07-07) — the
  MAME `cpnet_bridge` PIO-B device. SIO (this doc) has NO bridge — MAME connects
  directly to the socket — and is the working transport in MAME.

## Cleanup state

All diagnostic instrumentation reverted to baseline: cpmsim rebuilt clean (no
SNETDEBUG/setvbuf), original MPM.SYS reinstalled, `cpnos-in-c/Makefile` at the
committed version, temp files removed. Repos clean. The test remains ~50% flaky.
