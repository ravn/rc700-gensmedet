# cpnos CP/NET + PPAS/TOD findings (2026-07-03)

Analysis from a long debugging session verifying cpnos PPAS + TOD over PIO.
Two production-relevant root causes found, one CP/NET security property
documented, and a reusable wire-decode method. Tasks at the bottom.

## Finding 1 — `-autoboot_script` breaks the PIO cpnet_bridge netboot

**Symptom:** `make cpnos-polypascal-test` hangs at "wait for E>" on a fast
host (M4). The slave prints its boot banner but netboot never completes.

**Root cause (definitive):** passing *any* MAME `-autoboot_script` — even a
one-line empty script — puts the MAME Lua engine in the emulation loop and
perturbs device/scheduler timing enough to break the **wall-clock-coupled**
PIO cpnet_bridge handshake. The slave sends its first LOGIN byte and its
no-timeout `RECVBY` busy-wait never receives the master's reply, so it spins
forever at the banner.

**Evidence (not speed, not Lua work, not byte-eating):**
- no-autoboot at 210 % MAME speed → **PASS** (3367 bridge bytes, full
  cpnos.img transfer, reaches `E>`).
- empty-autoboot at 235 % (faster!) → **FAIL** (1 bridge byte, stalls).
- The Lua never reads the PIO port or installs a read-tap; all its reads are
  non-consuming memory peeks, so it does not consume netboot bytes.
- Throttling the Lua's per-frame file I/O did *not* fix it; only removing
  `-autoboot_script` entirely does.

**Fix (proven):** drive the slave from a **host-side SIO-B socket injector**
with **no autoboot script** — cpnos `impl_conin` reads `SIO_B_DATA` when
`console_joined` (resident.c), so keystrokes go in over SIO-B and CONOUT is
mirrored out, exactly like the rcbios `polypascal_pio_inject.py` harness.
Implemented in `cpnos-in-c/cpnos_polypascal_inject.py`. Full run
(PIO, `-nothrottle`, no autoboot): PPAS PRIMES→29989 + Q→E> + TODGET date,
8 stages green, ~19–37 s.

This is the same class as the parked "cpnet_bridge PIO timing can't be
MAME-verified" caveat, now biting because the host is fast enough that the
no-Lua path works while any Lua-engine overhead tips it over.

## Finding 2 — TOD `ff` was a STALE MPM.SYS, not a login/client bug

**Symptom:** TODGET's FN-105 gettod returned `FNC=55 SIZ=1 payload ff 0c`
("not logged in") on cpnos, even though PPAS's remote-drive (E:) access
worked, and even after an explicit `LOGIN PASSWORD`.

**Wire evidence (decoding proxy, HCS-validated frames):**
- slave→master: **every** request — gettod, OPEN, READ, LOGIN — carries
  identical `DID=0x00, SID=0x01`. Not a DID/SID mismatch.
- master→slave: LOGIN → `SIZ=0 DAT0=0x00` (success, cpnos *is* logged in);
  gettod → `SIZ=25` date payload once MPM.SYS is current.

**Root cause:** the master was running a **stale MPM.SYS**. While debugging
truncated-PPAS staging earlier in the session, `disks/local/mpm-net2-1.dsk`
was overwritten with the older `disks/library` copy, whose baked-in
SERVER.RSP predated the current gettod handling. Per
`reference_mpm_sys_baked_via_gensys`, RSP source edits are inert until GENSYS
re-bakes MPM.SYS — so the master ran a stale server and rejected gettod.
Rebuilding MPM.SYS (`cpnet/mpm-server/rebuild-mpm-sys.sh --install`) from the
current `server.asm` fixed it, with login working exactly as designed.

An earlier commit (21c2f13) "fixed" this by exempting gettod from the login
check in `server.asm`; that was unnecessary and reverted in 3bfa4a1.

## Reference — CP/NET login / SID model (for future work)

- **SID is a single byte** (message header `[FMT][DID][SID][FNC][SIZ]`, SID at
  offset 2; master reads it with `mov c,m`; `cfgtbl.slaveid` is `uint8_t`).
- **SID is client-assigned, never handed out by the server.** The LOGIN
  handler reads the client's asserted SID and records it into `G$LOG`
  (server.asm:1466-1468); the login response is only a 1-byte return code.
  Each node is statically configured (cpnos = `RC702_SLAVEID=0x01`, master
  conventionally 0). Max 16 requesters (`G$VEC` 16-bit slot bitmap).
- **Password is checked once, at LOGIN** (8-byte compare vs `G$PWD`,
  server.asm:1421-1431). Re-login of an already-logged-in SID skips the
  password.
- **Per-request validation is SID-membership only** (`valid()`→`chklog`); no
  per-message credential. Once an SID is logged in, any message presenting it
  is accepted — i.e. **spoofable by design** (CP/NET assumes a trusted LAN).
- **FN-105 gettod is a vendor extension**, not a forwarded BDOS time call
  (BDOS-105 is not forwardable under CP/NET 1.2). It rides on the generic
  Send/Receive Network Message primitives (BDOS-66/67); CP/NET transports
  opaque bytes and has no notion of "time of day". The master folds FN 105→55
  and dispatches to the project-added `gettod` handler
  (server.asm:354), which reads MP/M's clock.

## Reusable method — CP/NET wire decode

A TCP proxy on the PIO path (`:5002 → :4002`) capturing raw bytes, decoded
offline by scanning for `SOH(0x01)` + 6 bytes and validating
`HCS = -(SOH+FMT+DID+SID+FNC+SIZ) & 0xFF`, cleanly recovers every request
frame's `FMT/DID/SID/FNC/SIZ`. Frame layout in `cpnos-rom/CPNET_WIRE_PROTOCOL.md`.
Invaluable for future CP/NET debugging; consider adding a small committed
`cpnet/decode_frames.py` tool.

## Tasks raised

- **T1 (primary):** wire `cpnos_polypascal_inject.py` into the
  `cpnos-polypascal-test` Makefile target — replace the `-autoboot_script`
  Lua launch with: no autoboot + injector in background + SIO-B socket. The
  Lua path is fundamentally broken for PIO netboot on fast hosts. Reuse
  `scripts/wait_mpm_ready.py` for the readiness gate.
- **T2:** `stage-drivei-ppas` should also stage `TODGET.COM` (from
  `cpnet/todget/`) on drive I: so the injector's TOD stage has its binary.
  (LOGIN.COM optional — not needed once netboot LOGIN is honoured.)
- **T3:** guard against stale MPM.SYS. `cpnos-disk-install` (or the test
  preamble) should ensure the master boots a **current** SERVER.RSP — never
  silently restore `disks/local/mpm-net2-1.dsk` from the pristine `library`
  copy (it re-introduces a stale baked-in server). Consider a checksum/marker
  assertion, or always `rebuild-mpm-sys.sh --install` when gettod is exercised.
- **T4:** `server.asm` LOGIN handler has a self-flagged `; BUG? needs "ei"?`
  at the table-full path (line ~1418): it takes the `DI` critical section but
  the G$NUM==G$MAX branch `jmp sndbak` without re-enabling interrupts.
  Investigate whether a login attempt when the table is full leaves interrupts
  disabled on the master.
- **T5 (doc/known-property, not a fix):** per-request CP/NET validation is
  SID-membership only and therefore spoofable. This is inherent to CP/NET 1.2
  and acceptable on a trusted link; record it so it isn't mistaken for a bug.
