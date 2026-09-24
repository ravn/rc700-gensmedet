# Session 31 — PIO CP/NET driver + MAME bridge brought to standards

Date: 2026-04-27

## Headline

- **Real PIO CP/NET driver** in cpnos-rom: `transport_pio.c`
  rewritten as a frame-level transport (OTIR send / INIR recv), not
  just speed-test scaffolding.  CKS computed in-place per DRI
  sum-to-zero convention.
- **Boot-time transport probe**: `pio_probe()` sends a 7-byte PING
  SCB, awaits PONG; on success `active_transport` flips to PIO so
  netboot + runtime CP/NET both go through the parallel link.  No
  PONG within the budget → SIO fallback.  No `di`/`ei` around any
  block instruction (chip IE off, Z80 IFF on, CRT VRTC keeps
  firing between INIR/OTIR iterations).
- **Full netboot via PIO** (Phase B): `cpnet_pio_server.py`
  dispatches LOGIN / OPEN / READ-SEQ / CLOSE through
  `netboot_server.dispatch_sndmsg`.  CP/NOS reaches NDOS COLDST via
  the parallel link.
- **MAME bridge refactor**: `cpnet_bridge.cpp` rewritten from
  private listener thread + raw POSIX sockets + 50 ms `select()`
  timeout to MAME-standard `BITBANGER` sub-device pattern (matches
  `null_modem`).  -192 net lines, no thread/mutex/atomics.
  Per-frame host recv 53 ms → 0.5-3 ms wall; full PIO netboot in
  MAME-nothrottle 3.82 s → **0.28 s emulated (13.6× faster)**.
- **Signon banner shows transport + UTC timestamp + git hash**:
  `RC702 CP/NOS PIO 2026-04-27 12:58 f6c43a4+`
  (`+` indicates dirty tree at build time).

## Commits

### `ravn/rc700-gensmedet:cpnet-pio-direct`
- `46b5479` — PIO transport driver + boot-time CP/NET probe (Phase A).
  vtable in `transport.h`, `cpnet_dispatch.c` + `active_transport`,
  `transport_sio_vt`, real `transport_pio.c`, snios.s jt redirect,
  `netboot_mpm.c::cpnet_xact` routes through dispatcher,
  `cpnos_main.c` probe before NETBOOT, `BOOT_MARK(7,'P'/'S')`,
  payload-overflow linker guard.
- `e4a0397` — full CP/NET netboot over PIO (Phase B).
  `cpnet_pio_server.py`, `pio_send_msg` computes trailing CKS,
  harness `--mode=pio-netboot` asserts `'J'` at strip idx 18.
- `06ec780` — tuning + boot-marker timing in tap.lua.
  NTWKIN drains only when active=SIO; PIO_FIRST_BYTE_BUDGET tightened
  to 0x4000 (~150 ms emulated); cpnet_pio_server prints per-frame
  timings.
- `d5b637c` — host-side timing instrumentation + early server spawn.
  Race: Z80 probe ran ~24 ms wall after MAME launch; Python import
  took ~80 ms.  Move pio_server spawn to step 5c (before MAME).
- `f6c43a4` — banner: transport + build timestamp + git hash.
  `cpnos_buildinfo.h` regenerated each build, transport tag patched
  in-place (writable .data banner) so a single template covers
  PIO/SIO without separate rodata strings.  `transport_pio_send_byte`
  / `_recv_byte` shims now `#if defined(PIO_LOOPBACK_TEST) ||
  PIO_SPEED_TEST==1` so gc-sections drops them in default builds.
- `61147d8` — banner adds HH:MM, transport patch via
  `__builtin_memcpy` (clang emits LDIR; ~4 bytes shorter than three
  byte stores).
- `3f30d8f` — cpnet_pio_server now LISTENs (was: connector).  MAME's
  bitbanger uses CONNECT semantics for `socket.host:port`, so the
  Python side must bind.  Harness pre-spawns server-or-dummy on
  :BRIDGE_PORT before MAME launches (otherwise MAME aborts at start
  with "Connection refused" from bitbanger's first I/O).

### `ravn/mame-rc702-rc759-rc750:cpnet-fast-link-remerge`
- `f9f1efdc1ce` — cpnet_bridge: switch to MAME-standard bitbanger
  sub-device pattern.  Removes private listener thread, mutex,
  std::atomic, std::deque buffering, and the 50 ms `select()` that
  was the entire MAME-side latency penalty.

## Architecture findings

### MAME's `cpnet_bridge.cpp` 50 ms select was the whole "PIO is slow in MAME" story

Profiling pio-netboot in MAME -nothrottle showed 130 ms emulated /
frame round-trip.  Host wall-clock was ~53 ms / frame, of which
99.96 % was inside `socket.recv()` blocked on bytes from MAME.

Root cause: the prior `cpnet_bridge.cpp` ran a private listener
thread with `select()` timeout = 50 ms.  Chip-side `write()` on the
emu thread queued bytes into `m_z80_to_host` but didn't wake the
listener.  The listener only noticed on its next 50 ms timeout
before flushing to TCP.  Two such waits per round-trip (Z80→host
flush + host→Z80 flush) ≈ 50 ms wall.  At MAME-nothrottle ~5×, that
was ~125 ms emulated of busy-polling per frame on the Z80 side.

Refactor uses the same pattern as `null_modem`: a `BITBANGER`
sub-device sitting on the OSD layer's `posix_osd_socket`, which uses
`select()` with **zero** timeout (non-blocking, polled inline by the
emu thread).  No private threads, no 50 ms sleeps.  Per-frame wait
collapses to ~ms.

### Why I had to flip the Python server from connector to listener

MAME's `socket.host:port` OSD syntax means **connect** (look at
`posixsocket.cpp:170` — `::connect(...)` if not OPEN_FLAG_CREATE).
Bitbanger images aren't opened with CREATE, so MAME is the TCP
client; the Python side has to listen.  This is opposite of the old
listener-thread bridge (where MAME listened) and required flipping
`cpnet_pio_server.py::run` and adding a "dummy listener" pre-spawn
in the harness for non-PIO modes (otherwise MAME aborts at startup).

### Display memory at 0xF800 limits payload growth

While shrinking the payload, found a silent bug: payload extending
past 0xF800 lands string literals + initialised data inside display
memory.  `init_hardware()` calls `clear_screen()` early, wiping
those rodata bytes back to spaces — symptom: "INIT OK" boot marker
showed blank because the marker[] string was clobbered, then the
loop read spaces from it.  Added a hard linker ASSERT on
`__payload_end <= 0xF800` so this fails at build time, not
mysteriously at boot.

### MAME's standard pattern for "socket as byte stream" is bitbanger

- `src/devices/imagedev/bitbngr.cpp`: the device.
- `src/osd/modules/file/posixsocket.cpp`: the OSD layer with
  zero-timeout select.
- `src/devices/bus/rs232/null_modem.cpp`: the canonical example.
The cpnet_bridge code was originally written without referencing
this pattern and reinvented its own (with the bug above).  Rewrite
followed null_modem precisely.

## Recommendations / next phase

1. **Real-hardware bring-up** (parked, no Pi 4B yet) — the MAME
   measurement is now within ~5× of theoretical, but that 5× is all
   emulator dispatch.  Real HW will land near the 50 ms mark
   (vs. 280 ms emulated), wire-bound.
2. **Fix the bring-up scaffolding harness modes**
   (`hostsend`/`loopback`/`speed*`) to work with the bitbanger
   bridge.  They were written assuming the harness is the TCP
   client and MAME is the listener; that's now reversed.  See
   ravn/rc700-gensmedet#... (filed below).
3. **Bridge first-byte cost** — first PING in MAME still takes
   ~53 ms wall because the bitbanger sub-device lazy-opens the
   socket on first I/O.  Tolerable (one-time cost) but worth a
   note in the slot device's docs.

## Open follow-ups

### Branch hygiene
- [ ] Promote `ravn/mame-rc702-rc759-rc750:cpnet-fast-link-remerge` → `master`.
      Slot infrastructure + bridge refactor both validated.
- [ ] Promote `ravn/rc700-gensmedet:cpnet-pio-direct` → `main`.
      Driver, probe, netboot, banner all working end-to-end.

### Issues filed
- [x] **ravn/rc700-gensmedet#55** — harness `hostsend`/`loopback`/
      `speed*` modes broken after cpnet_bridge bitbanger refactor;
      connection topology flipped (MAME now connector, harness must
      listen).  Sketch in the issue body.

### Real-hardware bring-up (parked)
- [ ] Pi 4B + Pi Pico + J3 cable per `docs/cpnet_fast_link.md`.
- [ ] Re-measure: expected ~50 ms / 25 sectors total CP/NOS
      netboot (~64 ms / sector worst case at 38400 baud SIO,
      so ~40× speedup).

### Compiler-driven goal (project KPI per CLAUDE.md)
- [ ] Shrink CP/NOS payload to fit single 2 KB PROM.  Currently
      2814 bytes (2 bytes slack to the 0xF800 display ceiling, but
      total payload still spans both PROMs at 2814+padding < 4096).

## Lessons

### When a wire is fast, tooling overhead becomes the bottleneck

Session 30 measured PIO at 148-156 KiB/s wire-bound — way faster
than the ~3.8 KB/s SIO ceiling.  Yet end-to-end CP/NOS netboot in
MAME was *slower* on PIO until this session's bridge refactor.  Why:
SIO's 260 µs / byte chip-emulated rate happens to be larger than
MAME's listener-thread dispatch jitter, so SIO masked the dispatch
cost.  PIO's 5 µs / byte (~50× faster wire) made the 50 ms dispatch
window the dominant per-frame cost.  Lesson: when you ship a wire
that's much faster than the slow path it replaced, audit every
layer of dispatch / polling / buffering on top of it.

### Look at MAME's standard patterns before reinventing

The cpnet_bridge's listener-thread design predated this session.
Rewriting to follow null_modem (BITBANGER + osd_file) was -192
lines and ~14× faster.  The MAME way is correct here.

### Display memory overlap is a silent footgun

Until this session's linker ASSERT, payload growth past 0xF800
produced inscrutable runtime symptoms (blank boot markers, missing
"PASSWORD" string, bogus signon).  The linker now refuses to emit a
binary that overlaps display memory.  Cheap insurance.

## Files of note

- `cpnos-rom/transport_pio.c` — the real PIO frame transport.
- `cpnos-rom/transport.h` — vtable + dispatcher interface.
- `cpnos-rom/cpnet_dispatch.c` — `active_transport` + dispatch fns.
- `cpnos-rom/cpnet_pio_server.py` — host-side CP/NET PIO responder.
- `cpnos-rom/payload.ld` — linker guard against display-memory
  overflow.
- `tests/cpnet_bridge/harness.py` — `--mode=probe` and
  `--mode=pio-netboot`; pre-spawns listener for any cpnet_bridge
  mode.
- `tests/cpnet_bridge/tap.lua` — boot-marker strip + per-marker
  emulated-time log to `/tmp/cpnos_boot_marks.log`.
- `mame:src/devices/bus/rc702/pio_port/cpnet_bridge.{cpp,h}` —
  rewritten on the bitbanger pattern.

## Numbers

End-to-end CP/NOS netboot in MAME -nothrottle:

| Phase | Path | Time |
|---|---|---|
| Pre-session | PIO listener-thread bridge | 3.78 s emulated |
| Post-session | PIO bitbanger bridge      | **0.28 s emulated** (13.6× faster) |
| Reference   | SIO 38400 baud           | 2.08 s emulated |

Per-frame host wall-clock:

| Path | recv | dispatch | send |
|---|---|---|---|
| Pre-session  | 53 ms       | 0.02 ms | 0.01 ms |
| Post-session | 0.5–3 ms    | 0.02 ms | 0.01 ms |

Real-hardware projection (Pi+Pico bridge, no MAME emulation):
PIO ~50 ms total netboot, SIO ~2 s total netboot, **~40× PIO over SIO**.
