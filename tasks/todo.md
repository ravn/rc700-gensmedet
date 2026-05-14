# Build all 13 CP/M BIOSes from source

## Completed
- [x] Step 1: Fetch jbox.dk originals → `rcbios/jbox-originals/` (16 files)
- [x] Step 2: Trivial targets — rel14-mini, rel23-mini added to Makefile
- [x] Step 3: REL20 conditional (56K rel.2.0) — byte-verified
- [x] Step 4: RC703 family (separate source tree) — 3 variants byte-verified
- [x] Step 5: RC702E family (separate source tree) — 2 variants byte-verified
- [x] Step 6: 58K family (separate source tree) — 3 variants byte-verified
- [x] Step 7: 58K label renaming — auto-labels replaced with meaningful names

## Done: MAME RC702 serial port + CP/NET (completed)
- [x] SIO Channel A wired in MAME with null_modem
- [x] REL30 BIOS: 256B ring buffer, RTS flow control, 38400 baud
- [x] SNIOS.SPR: hex-encoded CRC-16 serial framing
- [x] Python CP/NET server: BDOS F13-F40, F64-F65, F70-F71
- [x] 204KB file transfer validated, zero packet loss
- [x] Automated test suite (autotest.lua + run_test.sh)
- See [cpnet.md](../cpnet.md) for full details

## Next: Switch to DRI binary protocol + MP/M server

### Investigation findings (2026-03-07)

**Three CP/NET serial protocols exist** (cpnet-z80 project):

| Protocol | Framing | Encoding | Checksum | Server option |
|----------|---------|----------|----------|---------------|
| `serial` (ASCII) | `++`...`--` | Hex-encoded | CRC-16 (0x8408) | `proto=ASCII` |
| `ser-dri` (DRI) | ENQ/ACK/SOH/STX/ETX/EOT | Binary or ASCII | Two's complement sum | `proto=DRI` |
| z80pack | DRI protocol | Binary (`Binary$ASCII=FFh`) | Two's complement sum | Built-in |

**Our current RC702 SNIOS uses the `serial` (ASCII/hex) protocol.**
This is incompatible with DRI standard and z80pack.

**z80pack has:**
- MP/M II V2.0 on disk images (mpm-1.dsk, mpm-2.dsk)
- Network I/O via TCP socket on port 50/51 (`net_client.conf` → host:port)
- Three SNIOS variants: snios-0 (original DRI), snios-1 (CP/NET 1.1), snios-2 (CP/NET 1.2)
- All use DRI protocol in binary mode by default

**CP/NET version**: Our CPNETLDR.COM says "CP/NET 1.2". Versions 1.1 and 1.2 are
NOT binary compatible. Must use matching client/server versions.

**MP/M as server**: cpnet-z80 has an MP/M Server implementation (NETSERVR.RSP)
but currently only builds for W5500 NIC (Ethernet), not serial.
Would need: serial NIOS for MP/M server side, or adapt z80pack's socket I/O.

**CpnetSerialServer.jar** (Java, in cpnet-z80/contrib) supports both ASCII and DRI
protocols via `cpnet_proto=` config. This is the easiest server to use.

### Recommended approach

**Phase 1: Switch SNIOS to DRI binary protocol**
- [x] Rewrite RC702 SNIOS to use DRI ENQ/ACK/SOH/STX/ETX/EOT framing
- [x] Use binary mode (no hex encoding) — 8-bit clean serial link
- [x] Simple two's complement checksum (code is 32B larger due to retry/ACK)
- [x] Keep FNC=FFh init and FNC=FEh shutdown (same across all protocols)
- [x] Update server.py to speak DRI binary protocol
- [x] Test with MAME (end-to-end validation)
- [ ] Test with CpnetSerialServer.jar (`proto=DRI`) as alternative server

**Phase 2: MP/M server via z80pack**
- [ ] Build z80pack cpmsim on macOS
- [ ] Boot MP/M II with CP/NET server (NETSERVR.RSP)
- [ ] Connect: RC702 (MAME, DRI SNIOS) ↔ TCP ↔ z80pack (MP/M server)
- [ ] Challenge: need serial NIOS on MP/M side, or bridge via TCP

**Phase 3: cpmtools3 for disk image file injection** (DONE)
- [x] RC702 diskdefs: rc702-5dd, rc702-8dd, rc703-qd in `rcbios/diskdefs`
- [x] cpmtools3 binaries installed to `~/.local/bin/`, diskdefs symlinked
- [x] Handles IMD files natively (including multi-density RC702)
- [x] run_test.sh --inject uses `cpmcp` from PATH
- [x] imd_cpmfs.py deleted (replaced by cpmtools3)

### Protocol savings (DRI binary vs current hex)
- Wire: 8+N bytes vs 18+2N bytes per message (2x bandwidth)
- SNIOS code: ~80 bytes smaller (no hex encode/decode, simpler checksum)
- Server code: ~90% smaller framing code
- Throughput: ~4.8 KB/s vs ~2.4 KB/s at 38400 baud

**Phase 4: Recreate Java server sources**
- [ ] CpnetSerialServer.jar in cpnet-z80/contrib/ is distributed as .class files only
- [ ] Decompile and recreate source for CpnetSerialServer, CpnetDRIProtocol,
      CpnetSerialProtocol, CpnetSimpleProtocol, HostFileBdos, etc.
- [ ] Key classes: ServerDispatch, NetworkServer, SerialDevice, TtySerial
- [ ] Goal: maintainable source for the DRI protocol serial server

### Resources
- z80pack: https://retrocmp.de/emulator/z80pack/z80pack.htm
- z80pack fork: https://github.com/ravn/z80pack (local: submodule at z80pack/)
- cpnet-z80: https://github.com/durgadas311/cpnet-z80 (local: ~/git/cpnet-z80)
- CP/NET docs: http://sebhc.durgadas.com/CPNET-docs/cpnet.html
- CpnetSerialServer.jar: cpnet-z80/contrib/ (Java, supports DRI+ASCII protocols)
- cpmtools3: ~/git/cpmtools3

## REL30 Code Size Optimizations (not yet implemented)

### JP→JR replacement (~110 bytes)
~110 shared-code JP instructions can be replaced with JR (1 byte each).
All are in-range and use JR-compatible conditions. Needs `IFDEF REL30` guards
or a macro to preserve byte-verification of existing releases.
2 additional savings in REL30-only code.

### BGSTAR semi-graphics removal (~382 bytes)
BGSTAR is a 250-byte bit table tracking which screen positions were written
in "background mode" — a semi-graphics feature used by ESC codes Ctrl-T/U/V.
Making all BGSTAR-related code conditional for REL30 saves 382 bytes across
11 code sections in DISPLAY.MAC (ADDOFF, CLRBIT, ESCSB/ESCSF/ESCCF procedures,
plus background tails in FILL, SCROLL, ESCE, ESCK, ESCY, ESCDL, ESCIL, DISPL).
TAB1 jump table entries for the 3 ESC handlers should point to DUMMY for REL30.
See `rcbios/BGSTAR_ANALYSIS.md` for section-by-section breakdown with addresses
and byte counts.

## Done: SYSGEN BIOS install via CPM56.COM (completed 2026-04-03)

Workflow to install C BIOS onto a disk using standard CP/M tools:
- [x] SYSGEN memory layout reverse-engineered (track 1 at 0x0900, track 0 at 0x4500)
- [x] mk_cpm56.py: patches bios.cim into CPM56.COM, generates Intel HEX
- [x] cpm56_original.com: CCP+BDOS extracted from distribution disk via SYSGEN+SAVE
- [x] Tested in MAME: LOAD CPM56 → SYSGEN CPM56.COM → boots with clang banner
- [x] MAME rs232a defaults changed to 1200 7E1 (matches distribution disk)
- [x] Serial transfer investigated: blocked by original BIOS 1-char SIO buffer
- See `rcbios-in-c/SYSGEN_INSTALL.md` for full documentation

### Remaining
- [ ] Serial PIP transfer: needs clang BIOS ring buffer (chicken-and-egg)
- [ ] Rebuild CCP+BDOS for different MTYPE (memory size) values
- [ ] USB video grabber for monitoring physical machine
- [ ] Test on real RC702 hardware

## Done: IOBYTE routing + SIO role swap (branch: iobyte-swap-sio)

IOBYTE fully implemented. SIO roles swapped:
- [x] SIO-B = console/control port (CON:=TTY/UC1, LST:=TTY)
- [x] SIO-A = data port (RDR:=PTR/TTY, PUN:=PTP/TTY, LST:=LPT)
- [x] Auto-detect host on SIO-B via DCD at boot
- [x] Banner: "Console also on serial port B at 38400 8N1"
- [x] Source-annotated listing (llvm-objdump -d -S)
- [x] Serial console MAME test (siob-console-test): DIR/ASM/TYPE via SIO-B
- [x] BIOS deploy via dual serial (deploy-serial): SIO-B commands + SIO-A data
  - PIP CPM56.HEX=RDR: → MLOAD CPM56.COM=BDOSCCP.COM,CPM56.HEX → CPM56 (verify) → SYSGEN
  - Test boots SDCC BIOS, deploys clang BIOS, hard resets, verifies banner change
  - MAME driver: RTS flow control on SIO-A, DCD wired for both channels
  - MFI disk format for writable SYSGEN, MLOAD.COM via cpmcp

### Remaining
- [ ] Test with generic Kermit-80 in MAME (Kermit uses IOBYTE flipping)
- [ ] Refactor serial_conout to share TX code with list_lpt (−~20B)
- [ ] Make DCD detection a switch indicator (TODO in bios.c)
- [ ] Full CCP+BDOS+BIOS download mode (user can provide replacement CCP/BDOS)
- [ ] Clean up cfg/ stale overrides in Makefile (delete before MAME runs)

## Additional Z80 C compilers as codegen oracles (research 2026-05-13)

Two maintained Z80 C compilers identified as worth adding alongside SDCC + clang/llvm-z80, primarily as third codegen oracles for outlier-first regression detection (not necessarily as shipping compilers).

### sccz80 (z88dk's native non-optimising C compiler) — MEASURED 2026-05-14

- Distinct from zsdcc (already used) — independent codegen, emphasis on small code via runtime helpers rather than inlining; very different shape from SDCC's IX-frame-heavy output.
- Already installed via z88dk Docker; no new toolchain needed.
- ROM output via `zcc +z80 -clib=sdcc_ix -create-app` with custom target cfg (ORG configurable).
- Measured 2.2× clang on the oracle corpus (257 B vs 115 B). Uniformly worse than zsdcc and clang on every pattern tested.

Tasks:
- [x] Build sccz80 cell in `sccz80-oracle-corpus/Makefile` (corpus + behavioural verification).
- [x] Document size delta vs zsdcc + clang in `findings-2026-05-13.md`.

Outcome: low oracle value — disagreements always mean "sccz80 is worse", not actionable about clang codegen. Do NOT add as a cpnos-rom build cell.

### ~~vbcc Z80 backend~~ — NOT VIABLE (correction 2026-05-14)

vbcc does NOT have a Z80 backend. Survey error corrected; Wikipedia
CPU list + vbcc upstream target archives both confirm no Z80 target.
The earlier survey conflated Z-machine (Infocom VM) with Z80. All
"vbcc" tasks in this section are cancelled.

See `z80-compilers-survey-2026-05-13.md` for the correction details.

### ACK (Amsterdam Compiler Kit) — MEASURED 2026-05-14

- Maintained at `davidgiven/ack` (V6.2+ April 2025).
- **No separate Z80 backend.** `cpm` platform uses i80 (Intel 8080).
  Output `.COM` runs natively on Z80 since 8080 is a strict subset →
  ACK is a Tier-1 Z80-capable compiler (the weakest of four).
- Measured 4.2× clang on the oracle corpus (481 B vs 115 B).
- Zero CB/DD/ED/FD prefix bytes in linked output → confirmed emits no
  Z80-only instructions (no DJNZ/JR/BIT/SET/RES/LDIR/IX/IY/EXX).

Tasks:
- [x] Add ACK Docker invocation to `sccz80-oracle-corpus/Makefile` (commit 45ba433).
- [x] Behavioural verification (all 8 cells PASS, byte-identical results vector).
- [x] Per-function size measurement via `anm -n` + `asize` on `corpus_ack.o`.
- [x] Document in `findings-2026-05-13.md` and `z80-compilers-survey-2026-05-13.md`.

Outcome: low oracle value (disagreement direction always "ACK lacks
the Z80 instruction", structurally pre-determined by ISA scope). Kept
in the harness as a Tier-1 reference point and i8080-floor regression
detector. No cpnos-rom build cell needed — ACK output is byte-bloat
without compensating advantage.

### Future Tier 3 audit: z80.eu/c-compiler.html (deferred)

User-requested follow-up 2026-05-14: walk through
http://z80.eu/c-compiler.html, record current state of every listed
compiler, and create Docker images for the ones that still build, so
they're usable on modern systems without host installs (per
[[reference_build_binaries]]).

The z80.eu page is a long-standing community catalogue covering many
historical compilers that our 2026-05-13 survey treated as frozen /
parked (BDS C, HiTech, Aztec, Whitesmiths, Software Toolworks C/80,
GST, Lattice, etc.) plus some we may not have covered. Goal of this
follow-up is **availability triage**, not oracle value — make the
historical Z80 C compilers boot-up-able from a one-line `docker run`
on macOS/Linux without polluting the host.

Tasks:
- [ ] Scrape http://z80.eu/c-compiler.html into a working list with
      current upstream status per entry (alive / archived / dead-link).
- [ ] Per surviving compiler: locate binaries / source, attempt build,
      record CP/M-host vs cross-compile shape.
- [ ] Docker image per buildable compiler under `ghcr.io/ravn/` namespace
      mirroring the `ghcr.io/ravn/hitech` pattern (HiTech zc Docker
      [[reference_hitech_zc_docker]]).
- [ ] Update `z80-compilers-survey-2026-05-13.md` Tier 3 section with
      "available as `docker run ghcr.io/ravn/<name>`" flag per entry.

Not a blocker on any current work. Probably an evening / weekend item
once direct llvm-z80 codegen work (Cluster A: #89, #27) is back in
focus.

### Survey reference

Full landscape including Tier 3 (HiTech, IAR, Zilog ZDS, Cosmic, BDS C, ASCII MSX-C, GST C, etc.) and explicitly-rejected options (Rust→Z80, Zig eZ80, Z80Babel, MESCC, ZNC, GCC, TCC, …) documented in `rc700-gensmedet/tasks/z80-compilers-survey-2026-05-13.md`.

### Out of scope (do not pursue without explicit user signal)

- HiTech C — parked per `rc700-gensmedet/tasks/hitech-port-parked.md` ([[feedback_check_hitech_park_note]]).
- IAR Z80 / Zilog ZDS-II — unavailable for purchase, no public benchmarks possible.
- Cosmic/Whitesmiths Z80 — frozen, no current release.
- MESCC — Small-C subset; can't compile cpnos sources without rewrites.
- ZNC (Spectrum Next) — C-like, not C; cannot ingest cpnos sources.
- Rust→Z80 / Zig eZ80 / Z80Babel — experimental; either downstream of LLVM (no oracle value) or not yet stable.
- BDS C, ASCII MSX-C, GST C, Aztec C, Software Toolworks C/80, Mark Williams Let's C, Lattice C, HiSoft C — historical only, frozen.
- GCC, TCC, chibicc, cproc, 8cc, PCC, Open Watcom, CompCert — no Z80 backend.

## AES-256 corpus follow-ups (2026-05-14)

The `aes256-corpus/` directory is a real-world compiler-efficiency
benchmark using AES-256 from z80.eu. Baseline shows zsdcc beats
clang 1.42× on size and 4.66× on runtime — the reverse of the
synthetic micro-corpus. See `aes256-corpus/findings.md` for the
full per-function and per-flag analysis.

### Filed compiler issues (do NOT fix — record only)

- **ravn/llvm-z80#156** — `+static-stack` miscompile on AES (ret
  pops corrupted return address `0x7E0C`, escapes into uninit RAM).
  Bin would be 36% smaller if fixed. Production cpnos-rom uses
  `+static-stack` successfully; AES is the first failing shape.
- **ravn/z88dk#5** — zsdcc `--nogcse` silently drops writes through
  a late-assigned absolute-address pointer after a struct-pointer-
  arg call. Adding `volatile` masks; initialising at declaration
  avoids.
- **ravn/z88dk#6** — zsdcc `-clib=sdcc_ix` produces wrong AES
  output (deterministic miscompile, ~33% larger code too).
  Reproduces under both `--sdcccall 0` and `--sdcccall 1`.

### Stated goal (see `aes256-corpus/GOAL.md`)

Two parallel tracks, each producing an upstream-bound queue:

1. **Clang track** — drive ravn/llvm-z80 to zsdcc parity on AES
   (currently +1699 B / +57% size, 4.66× runtime). Each per-function
   gap → filed `ravn/llvm-z80` issue with reduced repro. NO fixes
   here; fixes land in `llvm-z80/`.
2. **SDCC track** — collect zsdcc miscompiles as `ravn/z88dk`
   issues with repros. Long-term: summarise the queue against
   upstream SDCC.

### Priority clang gaps to file (largest absolute B first)

- [ ] **`aes_mc_inv`** (+549 B / 2.75×) — disassemble both
      compilers, identify codegen pattern, file `ravn/llvm-z80`
      issue with reduced C repro. Largest single function.
- [ ] **`aes_mixColumns`** (+289 B / 2.20×) — same approach as
      `aes_mc_inv`; share the reduced repro if the pattern is
      identical.
- [ ] **`rj_sb_inv`** (+126 B / **5.20× ratio**) — bitwise rotate
      chain `y<<1|y>>7`, `y<<2|y>>6`, `y<<3|y>>5`; suspect missing
      `rlca` chain peephole.
- [ ] **`gf_log`** (+121 B / 4.78×) — tight while+xor loop; suspect
      flag-recomputation regression (may overlap with
      [llvm-z80#77](https://github.com/ravn/llvm-z80/issues/77)).
- [ ] **`aes_subBytes` / `aes_sb_inv` / `aes_addRoundKey`** (each
      +85 B / ~3×) — all 16-byte iterator loops with byte-pointer
      ops, very similar shapes; one reduced repro probably covers
      all three.

### Cross-cutting tasks

- [ ] **Adopt the AES-validated `-mllvm -disable-machine-licm
      -mllvm -disable-machine-cse` flags in any new C corpus by
      default.** Already in cpnos-rom production. Validates
      [llvm-z80#128](https://github.com/ravn/llvm-z80/issues/128)
      with hard numbers: −7.4% size, **−52% runtime** on AES.
- [ ] **Re-measure cpnos-rom with `-mllvm -disable-lsr` removed.**
      AES shows LSR helps (+366 B without it), counter to the
      production choice to disable it. Cpnos-rom production may be
      leaving size on the table for loop-heavy code shapes.
- [ ] **Wire AES corpus into the regression suite.** Catch the next
      LICM/CSE-shaped regression in days not years. Runtime tstate
      metric is much sharper than size alone for surfacing codegen
      regressions.
- [ ] **Find the compiler that produced the original DEMO.COM
      (9216 B).** HiTech 3.09x with `-O` produces 12581 B — bytes
      differ from offset 1. So either different HiTech flags
      (`-Z`, `-O1`, …), different HiTech version, or BDS C / Aztec
      C / another z80.eu-listed compiler. Low priority — curiosity
      only.
- [ ] **Once miscompiles get fixed upstream:** re-run
      `make sweep` and update `clang-flag-sweep.md` /
      `sdcc-flag-sweep.md` to capture the new FAIL→PASS transitions
      and any size deltas they unlock.

## Upstream bug reports for jacobly0/llvm-z80

Collect all codegen bugs found during BIOS/PROM work and file them as
issues against the upstream jacobly0/llvm-z80 with thorough test cases
(XFAIL lit tests). Do NOT submit pull requests — some bugs may be
side-effects of less-researched features and a fresh fix effort by the
upstream maintainer will likely produce better code.

Known bugs to file:
- [ ] #69: Comparison reversal peephole erases live-out register (fixed in ravn fork)
- [ ] #65: PostRACompareMerge wrongly treats CP variants as setsZForA
- [ ] #67: Pre-existing lit test failures (cmp-eq-regpressure, fib, interrupt, shift-opt, spill-regclass)
- [ ] Redundant XOR A,A when A already holds 0 across consecutive BSS stores (3B in bios_boot_c)
- [ ] Audit ravn/llvm-z80 issues list for others that affect upstream

## Parked (not working on now)
- [ ] **`cpnos-warmboot-test` is the wrong harness for `TRANSPORT=pio-irq` builds.**  Default build is `TRANSPORT=pio-irq` (Makefile:208) but `cpnos-warmboot-test` (Makefile:1253) wires `bitb1 socket:9000` to **SIO-A** (`rs232a null_modem`) for netboot_server and `bitb2` to SIO-B for the E> trigger.  The slave's PIO-B bridge has nothing connected, so it sits in its main loop waiting for ENQ that never arrives.  Server log on a 90 s run: `session ended: EOFError: client closed waiting for ENQ`.  Fix options: (a) gate the target with a `TRANSPORT=sio` check that errors with "use `pio-irq-netboot` instead" for pio-irq builds, (b) deprecate the target since `pio-irq-netboot` covers the same ground for the live transport, (c) wire it to PIO-B for pio-irq builds.  Symptom for future readers: only the boot banner appears on SIO-B, no E>, 0 OPEN events on the server log -- looks like a slave hang but is a harness mismatch.  (recorded 2026-05-08)

- [ ] **`mame_boot_test.lua` finish() never fires under the canonical 8 s `cpnos-mame` target.**  The script's PASS gate scans the screen for E> and the FAIL gate trips at `frame > 50 * 60` (3000 emu frames = 60 emu seconds).  With `make cpnos-mame`'s `-seconds_to_run 8` (real time) and ~5.5x speed, MAME emulates ~44 s before exiting -- short of the 60 s lua timeout AND short of the time real boot needs to reach E>.  Result: `/tmp/cpnos_boot_result.txt` is empty (finish() never called), so the canonical smoke test produces no machine-readable result file.  The trace file at `/tmp/cpnos_boot_trace.txt` is populated (per-frame writes flush) but the rich post-mortem dump (display, BIOS-JT fingerprints, CRT counter, BSS) is gated behind finish().  Fix options: (a) lower the lua's frame-timeout below 50*40 so it fires before MAME exits, (b) raise `cpnos-mame`'s seconds_to_run (8 -> 30+), (c) hook MAME's exit callback to call finish() unconditionally.  Verified the issue this session by running cpnos-mame and getting no result file despite normal boot.  (recorded 2026-05-08)

- [ ] **GitHub Actions version audit.**  Walk `.github/workflows/*.yml` (currently only `makefile.yml`) and confirm each `uses:` reference points at the latest stable major.  Today: `actions/checkout@v4` — verify v5+ isn't out / preferred, and check whether other actions get added by future workflows (cache, setup-python, etc.) stay current.  Low-priority maintenance; revisit once per quarter or before adding a new workflow.  (recorded 2026-05-06)

- [ ] **Let the linker fill memory-map gaps with small code/data.**  Current `payload.ld` declares contiguous regions (PAYLOAD 0xED00 + SCRATCH 0xEA20 + PIO_RX 0xF700) and treats the dead spaces between them as off-limits.  Holes catalogued in `cpnos-rom/docs/memory_map.md` (~3.85 KB total): 0xDC80..0xE9FF (3.4 KB; cpnos→NIOS gap), 0xEC24..0xECFF (220 B), 0xF66A..0xF6FF (150 B), 0xFFD0..0xFFFB (44 B), 0xEA18..0xEA1F (8 B).  After the cpnos.com lift (Phase A) closes the biggest hole, teach the linker to place small functions / rodata into the remaining gaps via `MEMORY` regions + matching output sections so we get every byte.  Likely useful in conjunction with the init/resident split (Phase B) since init code is generally fragmented and easy to slot.  (recorded 2026-04-30)


- [ ] **Replace or re-install WS for cpnos.**  The `ws.com` + overlays we copied from `rc703-div-bios-typer/` use direct memory-mapped video writes, with a screen base / size that does NOT match cpnos's 0xF800..0xFFCF / 80x25 layout.  Effects observed at `^J H 2`: BSS at `0xEAxx` (curx/cury/kbd_ring) clobbered to 0x20, frame counter at `0xFFFC..0xFFFF` overwritten, screen freezes with garbage.  PPAS is fine because it uses BIOS CONOUT only.  Two fix options: (a) find a WS distribution copy that uses CONOUT only, or (b) get `WINSTALL.COM` (the WordStar terminal-config tool) and retarget the existing WS to match our slave's layout.  Diagnosis evidence: probe trajectories + dumps captured 2026-04-30; details in `tasks/timeline.md` Phase 28d.


- [ ] **NDOS into the PROMs (only CCP.SPR loads from disk).** Investigate folding the NDOS+SNIOS half of `cpnos.com` into the cpnos-rom PROM payload (today PROM0+PROM1 = 4 KB; payload is 2548 B, so ~1.5 KB headroom but NDOS+SNIOS is bigger than that — see `cpnos-build/d/cpndos.prn` for size). If feasible, the cold-boot netboot collapses from "OPEN+READ-SEQ on CPNOS.IMG (~4 KB)" to "OPEN+READ-SEQ on CCP.SPR (~2 KB)" — half the disk traffic, and the slave is operational without any master at all up to the CCP-prompt point. May require splitting NDOS reloc'able into ROM-resident + RAM-init halves. (recorded 2026-04-29)
- [x] **ISRs: drop EXX/EX AF,AF', PUSH only what's used** — done 2026-04-29.  PolyPascal v3.10 (PPAS.COM) holds persistent runtime state in the shadow bank (233 EXX/EX AF,AF' instructions in disassembly).  Switched all three ISRs from `EX AF,AF'; EXX` bracket to explicit per-register PUSH/POP: `isr_crt` uses AF+HL (4B saves), `isr_pio_kbd` uses AF+BC+DE+HL (8B), `isr_pio_par` uses AF+DE+HL (6B); none touch IX/IY.  +6 B payload (2548→2554 with MIRROR_SIOB=1; 2528→2534 with MIRROR_SIOB=0).  Verified live: `PPAS PRIMES` runs cleanly under the new ISRs.
- [ ] **Rewrite ISR routines in C using port variables** (user request 2026-04-29).  `isr_crt`, `isr_pio_kbd`, `isr_pio_par` in `cpnos-rom/isr.c` are currently `__attribute__((naked))` with hand-written PUSH/POP + asm body.  Two changes, both well-supported by llvm-z80 today:
  1. Convert each to a non-naked C function with `__attribute__((interrupt))`.  Clang then emits the prologue/epilogue (including `EI` immediately before `RETI`) and PUSHes/POPs only the registers the body actually clobbers (`Z80_Interrupt_CSR` = {AF,BC,DE,HL,IX,IY} filtered).  Lit test `llvm/test/CodeGen/Z80/interrupt.ll` confirms a one-store ISR emits exactly `push af / ... / pop af / ei / reti`.
  2. Replace inline-asm OUT/IN with port variables: `*(volatile __io uint8_t *)0x10` (with `#define __io __attribute__((address_space(2)))`).  Verified working today against the current llvm-z80 build — the legalizer crash was fixed in commits 0ff2114c62a6 + 0d71a91b4e18 (ravn/llvm-z80 #1, #44).  Code emits as bare `IN A,(0x10)` / `OUT (n),A`.
  - End result: ISR source reads as ordinary C plus a port-helper header, identical or smaller code size vs hand-written naked, and adding/removing a register from the body automatically flows through the save set.
- [ ] 58K rel.1.4: 4 ISR-specific auto-labels remain in BIOS_58K_14.MAC (sub_e43dh, lee8ah, lee8bh, lf421h)
- [ ] VERIFY.COM disassembly: Pascal-compiled disk verification utility (10KB). VERIFY.MAC in RC702E BIOS is a related but separate compilation (4KB app block, missing runtime). Low value — compiler output won't produce readable source.
- [x] **Microcontroller-as-host-bridge** — resolved 2026-04-25 by
  the CP/NET fast-link design (`docs/cpnet_fast_link.md`, Option P):
  Pi Pico drives **PIO-B / J3** (not PIO-A — keyboard stays there),
  3.3V GPIO works directly on Z80 PIO without level shifting (cbl923
  rig empirically proves the drive direction; series resistors on
  Pico inputs handle the reverse direction), Mode 2 abandoned in
  favour of half-duplex Mode 0/1 with mode-switching at CP/NET frame
  boundaries. See the new doc for the full design + bring-up plan.

## Verification Status (13 targets) — all MATCH
| # | Target | Source | Status |
|---|--------|--------|--------|
| 1 | rel13-mini | src-58k/BIOS_58K.MAC | MATCH |
| 2 | rel14-mini | src-58k/BIOS_58K_14.MAC | MATCH |
| 3 | rel14-maxi | src-58k/BIOS_58K_14.MAC | MATCH |
| 4 | rel20-mini | src/BIOS.MAC -DREL20 | MATCH |
| 5 | rel21-mini | src/BIOS.MAC -DREL21 | MATCH |
| 6 | rel22-mini | src/BIOS.MAC -DREL22 | MATCH |
| 7 | rel23-mini | src/BIOS.MAC -DREL23 -DMINI | MATCH |
| 8 | rel23-maxi | src/BIOS.MAC -DREL23 -DMAXI | MATCH |
| 9 | rc702e-rel201 | src-rc702e/BIOS_E201.MAC | MATCH |
| 10 | rc702e-rel220 | src-rc702e/BIOS_E220.MAC | MATCH |
| 11 | rc703-rel10 | src-rc703/BIOS_REL10.MAC | MATCH |
| 12 | rc703-rel12 | src-rc703/BIOS.MAC -DREL12 | MATCH |
| 13 | rc703-relTFj | src-rc703/BIOS.MAC -DRELTFJ | MATCH |

## Note: +static-stack removal option

Without `+static-stack`, BIOS is 6617B (+908B, 16% larger) but boots correctly
with banner and avoids the entire class of BSS self-clobber bugs (#51, #53).
Still fits MAXI disk (9984B limit, 3367B headroom). Consider removing
`+static-stack` if the compiler bugs prove too hard to fix.

Sizes: with +static-stack 5709B, without 6617B, SDCC 5570B.

## CP/NET fast host link (PIO-B / J3)

**Design committed (2026-04-25):** `docs/cpnet_fast_link.md` — Option P.
PIO-B half-duplex via J3, keyboard untouched on PIO-A / J4, machine
remains usable normally with the link unplugged.

Supersedes the earlier Mode-2 plan. The previous "Three options to
choose from" / "Hardware verification" / cable shopping notes are now
obsolete — see deprecation banner on
`rcbios-in-c/docs/parallel_host_interface.md`.

### Phase

- [x] **Design phase** — pinned in `docs/cpnet_fast_link.md`
- [ ] Implementation phase — **deferred**: user does not currently have
      Pi 4B / 3B host hardware on hand. Do NOT write Pico firmware,
      Z80 bench tests, MAME patches, or host daemons until an explicit
      "start coding" signal that follows hardware acquisition.

### Deferred bring-up sequence (when hardware available)

1. PIO-B input bench (mirror cbl923 keyboard rig but on J3).
2. PIO-B output bench (Z80 OTIR + host BSTB ack).
3. Direction-switch bench (mode-1 <-> mode-0 transitions clean).
4. End-to-end CP/NET frame test.
5. MAME parity (rc702.cpp PIO-B + virtual host bridge).
6. Pi 4B native deployment (Topology B, headless production).
7. Outside-world services on Pi (out of scope for this link).

### Open design questions (resolvable on paper)

- [ ] Sentinel-byte option for keyboard/CP-NET multiplexing on PIO-A is
      no longer needed under Option P. Remove if it appears anywhere.
- [ ] Optional 1-byte XOR checksum at frame end: yes/no decision after
      Step 4 above.
- [x] Level-shifter chip choice — **resolved 2026-04-25**: no chip
      needed.  Pico drives Z80 PIO directly (cbl923 rig empirically
      proves the Pico->Z80 direction); add 470 Ω - 1 kΩ series
      resistor on each Pico-input pin to current-limit the protection
      diode in the reverse direction.  Fallback to TXS0108E breakout
      only if Z80 PIO VOH measures above ~3.7V at bring-up.
- [ ] Pi-side z80pack invocation: in-process Python binding vs
      subprocess with TCP loopback.

### TODO (2026-04-28): use CP/NET disk traffic as "program running" signal

The sumtest workload tap currently detects "command done, ready for next"
via display-cursor stability + new-A>-row.  Works but slightly fragile
(needs row > last_prompt_row, which can be wrong if the screen
scrolls between commands).

A more robust signal: watch CP/NET frame traffic on the bridge.  When
a program is running and doing file I/O, bytes flow.  When CCP is
idle at A>, no bytes flow.  Idle for ~500ms = CCP at prompt, ready
for next command.

Could be done by:
- Instrumenting cpnet_bridge.cpp with a timestamped "last RX byte" and
  exposing it via a known address Lua can read; OR
- Parsing host-side proxy log (cpnet_pio_server.py) per-frame timing
  in real time; OR
- Watching MAME's bitbanger socket for activity.

### TODO (2026-04-28): port the cpnet_pio_server proxy to a Pico

`cpnos-rom/cpnet_pio_server.py` currently runs on the host PC: it
listens on TCP, talks DRI envelope upstream to mpm-net2 (port 4002),
and forwards raw SCB frames downstream to MAME's bridge / a real
Pi-Pico bridge (port 4003).  Question: can the proxy run on the Pico
itself, eliminating the host PC from the production setup?

Two angles:
1. **MicroPython port** of cpnet_pio_server.py.  ~600 lines fits
   easily in 264 KB SRAM (RP2040) or 520 KB SRAM (RP2350).  Throughput
   is the question: MicroPython ~10-50× slower than CPython; per-byte
   envelope ops would slow per-frame to ~10 ms vs ~1 ms host.  Pico W
   adds WiFi latency to mpm-net2 (~5-20 ms typical).  Enough for cold
   netboot, marginal for sustained workloads.
2. **C SDK port** for production.  PIO state machine handles
   STB/BRDY in hardware (zero-CPU per byte); lwIP for TCP to
   mpm-net2.  Closer to host-Python performance, fully embedded.
   Bigger engineering investment.

Goal: eliminate the host-PC dependency.  Slave (Z80 + RC702) +
Pi/Pico (CP/NET proxy + bridge) connects directly to mpm-net2 server.

### TODO (2026-04-28): investigate multi-channel SNIOS in any CP/NET impl

Question: do any CP/NET SNIOS implementations support more than one
communications channel (e.g., one over SIO + one over PIO simultaneously,
with traffic routed by frame type / priority)?  If yes, the design might
be applicable here — fast PIO link for bulk, slow SIO for control.  If
no (every SNIOS we've seen is single-transport), worth knowing as a
reference point for any multi-link design we'd build.

Sources to check:
- cpnet-z80 contrib SNIOS variants (snios-0/1/2 on z80pack).
- DRI's original CP/NET 1.2 distribution.
- CpnetSerialServer.jar / Java NIOS implementations.
- SEBHC docs (http://sebhc.durgadas.com/CPNET-docs/).

### DONE (2026-04-28, commit 092d323): 32-bit CRT frame counter

cpnos-rom's `isr_crt` now increments a 32-bit counter at
`0xFFFC..0xFFFF` on every CTC ch2 VRTC IRQ — mirrors rcbios's RTC
location (`RC702_BIOS_SPECIFICATION.md` §3.4).  Used by the file-I/O
bench (`testutil/filecopy.asm`) to record frames-to-completion via
the FILECOPY OK marker's S=/E= fields.  ~13 bytes of asm in `isr.c`,
INC (HL) sets Z so borrow-propagate via jr nz from each byte.

### TODO (2026-04-28): pulse — raw-bandwidth bench, no protocol

Slave program that bypasses BDOS / SNIOS / `active_transport`,
drives PIO-B / SIO-A chip ports directly to measure raw chip-level
bandwidth.  TX phase + ACK + RX phase + frame snapshots.

Host requires `pulse_host.py` (~150 LoC borrowed from
`netboot_server.py`) that handles netboot then transitions on a
sentinel byte sequence to byte-counter mode.  Replaces mpm-net2 for
the duration of the bench.

Time: ~3 h full (3 modes × 2 dir), ~1 h reduced (SIO + PIO-IRQ TX).
Detailed design in `tasks/session36-fileio-bench-and-pulse-design.md`.

### TODO (2026-04-28): install_write_tap on IO space — open puzzle

`mame_porttap.lua` installs `install_write_tap` on IO space ports
0x80 / 0x81 with `ok=true err=nil`, but the callbacks never fire when
slave does Z80 OUT.  Verified the OUT does execute (sumtest's
`out 80h` runs because we see the subsequent CONOUT bytes).

Hypothesis: API arg-shape mismatch, or `cpu.spaces["io"]` doesn't
intercept OUT in this MAME tree.  Worth a 30 min sanity check by
tapping a known-active IO port (e.g., 0x10 PIO-A data, written every
key event) — if THAT fires, the issue is something else; if not, it's
the API/MAME-build interaction.

Side-effect of the puzzle: warm-boot port-0x81 instrumentation
(commit `b06e6dd`) is unreachable telemetry.  Either fix the tap or
remove the OUT.

### TODO (2026-04-28): consider polled-PIO mode using bare bitbanger

Documented in `docs/cpnet_bridge_vs_bitbanger.md`.  Drop
`cpnet_bridge` slot device + slave's IRQ ring, use Mode-1 INIR
busy-poll receive instead.  Aligns with the project goal of "Z80
side as fast as possible, host side does the complex work" since
the slave path becomes a tight INIR loop with no ISR / ring / handshake
state machine.  Trade-off: slave busy-polls during transfers, can't
do concurrent CRT / keyboard work — fine for benches, may not be
fine for production.

Worth a one-day spike: gut `cpnet_bridge` to a bare bitbanger wrapper,
build cpnos with `transport_pio_recv_byte` rewritten as INIR,
re-run the 3-way bench, see if the simpler architecture pays off.

### TODO (2026-04-28): TCP_NODELAY on MAME ↔ mpm-net2 socket

Per `docs/cpnet_throughput_analysis.md`, ENQ (1 byte) is exactly
the kind of small write Nagle penalises.  CP/NET has many of these
turnarounds per frame.  TCP_NODELAY status on the mpm-net2 listener
+ MAME bitbanger client isn't verified; could be eating tens of ms
per turnaround out of the measured 58 ms per RTT.

Cheap to set, possibly large effect.  30 min check:

1. `mpm-net2`'s SERVER.RSP socket setup — find the accept/listen
   path, add `setsockopt(SOL_TCP, TCP_NODELAY, 1)`.
2. MAME's bitbanger TCP socket — check `osd/modules/...` for the
   socket creation path.
3. Re-run filecopy bench — compare emulated frames before/after.

If the delta is significant (>10%), wins for free on every CP/NET
configuration.

### TODO (2026-04-28): native (non-z80pack) host CP/NET server

mpm-net2 is itself a simulated Z80 (z80pack/cpmsim running MP/M II's
SERVER.RSP), so every SCB byte arriving at the host TCP listener is
parsed at 4 MHz emulated Z80 speed — adding ~5-10 emulated ms per
frame to the bench.  Replace with a native Python/C server that does
SCB parsing at host CPU speed.

`cpnos-rom/netboot_server.py` is a starting point — already speaks
LOGIN / OPEN / READ-SEQ / CLOSE for cpnos.img.  Would need to grow
to cover full CP/NET BDOS surface (DIR, FCB tracking across extents,
WRITE-RAND, RENAME, COMPUTE FILE SIZE, etc) before it could replace
mpm-net2 for general workload benches.

Estimated effect: 2-4× on PIO modes (host-side parsing was substantial),
no effect on SIO (still line-rate-limited at 38400 baud).

Aligns with project goal "host side does the complex work."

### TODO (2026-04-28): physical-hardware bring-up to verify projection

`docs/cpnet_throughput_analysis.md` projects PIO/SIO ratio widens
from ~2× (MAME) to ~4-7× (physical RC702 with Pi/Pico bridge on J3).
Verify by actually wiring it.

Steps (rough):
1. Pi/Pico-side firmware that responds to chip STB strobes,
   forwards to a host CP/NET server.
2. Cable/connector for J3 expansion port.
3. Same filecopy bench, real RC702.
4. Report frames-to-completion + KB/s; compare to MAME numbers.

Memory project_pico_count says user has 2 Pi Picos available — one
already on the cbl923 keyboard rig, second earmarked for J3.
Hardware is on hand.

### TODO (2026-04-28): reduce MAME cpnet_bridge poll quantum

The `m_poll_timer` in `cpnet_bridge.cpp` fires every 1 ms.  Per
`docs/cpnet_throughput_analysis.md`, CP/NET frames have 4 ACK
turnarounds where the slave waits for a host byte; each eats at least
1 ms of the timer quantum.  Lowering to ~100 µs would shave ~3
emulated seconds off the filecopy bench.  Trade-off: more host CPU
in the timer callback.

Test with `attotime::from_usec(100)` instead of `from_msec(1)`,
re-run bench, compare.  Cheap to test.

## cpnos-rom payload codegen analysis (2026-04-29)

Payload is 2536 B in PROM0+PROM1 (4 KB).  Long-term goal per memory
[CP/NOS → PROM 1 via compiler]: fit in PROM 1 (2 KB).  Gap: ~488 B.

### Already filed against ravn/llvm-z80 (compiler-side)
- [ ] #73 — small fixed-length `__builtin_memcpy` (≤8 B) unrolls to ~40 B of immediate stores instead of LDIR.  Worked around in `netboot_mpm.c:120-123` with a hand byte loop; still not optimal (17 B vs ~11 B LDIR).
- [ ] #74 — short-lived 16-bit spills go to BSS (or SP-relative) instead of PUSH/POP.  Hits `_xport_recv_byte` and `_cpnos_cold_entry`.
- [ ] #78 — LDIR's post-state DE/HL = dst+count not reused for `ptr += count`; hot path in `_netboot_mpm` reloads from BSS and re-adds (~6 B × 358 RTTs).
- [ ] #83 — dead `and 1` after `ld a,1` for `_Bool` store (PIO direction flag).  ~4 B.
- [ ] #84 — IVT loop and marker-print loop back up HL through BC unnecessarily; in-place writes already advance HL.  ~9 B per loop.
- [ ] #85 — sequential consecutive-address stores not lowered to HL-walked `ld (hl),v / inc hl` chain.  `_cpnet_xact` init alone is ~4 B; pattern recurs.
- [ ] #86 — switch range-check on `u8` discriminant uses 16-bit SUB/SBC instead of 8-bit CP.  Hits `_specc` (~5-7 B).
- Comments added: #60 (xor a; out; ld a,$0; out variant in `_isr_crt`), #18 (constant-routed-through-DE→L→A in `_init_hardware` set_i_reg call).

### Source-side wins independent of compiler
- [x] **Drop vtable indirection (~38 B est, -134 B actual)** — done 2026-04-30 in commit `3d4de26`.  `cpnet_transport_t` typedef + `transport_sio_vt` / `transport_pio_vt` + `active_transport` + `cpnet_dispatch.c` all gone; `cpnet_send_msg` / `cpnet_recv_msg` are now `#define` aliases of `snios_sndmsg_c` / `snios_rcvmsg_c` (or `pio_send_msg` under TRANSPORT_PROXY).  `snios.s`'s `SNDMSG_DISPATCH` / `RCVMSG_DISPATCH` are now plain `jp SNDMSG` / `jp RCVMSG` -- no BC<->HL juggling.  Bigger than the audit estimate because clang `--gc-sections` cleared a chain of dead wrappers once the vtable was gone.
- [x] **Gate BOOT_MARK in production (~30-50 B est, -98 B actual)** — done 2026-04-30 in commit `7a11af3`.  Default `BOOT_MARK_ENABLED=1` keeps the 19-char strip on for bring-up; `-DBOOT_MARK_ENABLED=0` collapses every site to `((void)0)` and `--gc-sections` drops the static "INIT OK" literal too.
- [x] **Pad LOGIN_PWD copy / split (~6 B)** — done 2026-04-30 in commit `6bded89`.  `__builtin_memcpy(8)` unrolled to ~40 B; the for-loop ran ~16 B; the manual-byte-0 + `memcpy(7)` idiom drops below clang's threshold and dispatches to the `_memcpy` runtime stub.  Stays in plain C per project rule "prefer C over inline asm".

### Cumulative size budget (after Phase 28e)
- default (MIRROR_SIOB=1):  2548 -> 2410 B (-138 B)
- production (BOOT_MARK_ENABLED=0 MIRROR_SIOB=0):  2528 -> 2280 B (-248 B)
- PROM-1 budget = 2048 B; production is 232 B over, default is 362 B over.
- ravn/llvm-z80 #87 (memcpy unroll threshold) filed 2026-04-30 -- once fixed, expect another ~50-80 B project-wide just from the stock memcpy lowerings.

### Other observations
- Hand-written 8080 SNIOS asm: tight, no waste.
- ISRs: ~2-6 B each savable (mostly via #60 / #84-class fixes).
- Console subsystem (`_specc`, `_impl_conout`, cursor functions): ~5-15 B savable, mostly via #85 / #86.
- Closing the full ~232 B gap to slot-1 (2 KB) likely needs all of #73 / #74 / #78 / #83-#87 in llvm-z80 plus a console-subsystem refactor.  Not yet planned.

### Re-scan after Phase B (2026-04-30 evening)

`payload.bin` is now 2438 B (production build, default flags this
session).  PROM-1 budget = 2048 B -> still 390 B over.

Pattern-matched the listing in `clang/cpnos.lis` against every open
`ravn/llvm-z80` issue.  Hits in compiler-generated code (excluding
`snios.s` hand-asm):

| Issue | Pattern | Hits | Approx win |
|-------|---------|------|------------|
| #75   | `call X ; ret` (unconditional)            | 2 | -2 B (1 B each in `_cursor_right`, `_specc`) |
| #85   | sequential `ld (HL),v ; inc HL`           | 2 | -4..6 B |
| #78   | LDIR + reload of dst/src                  | 1 | -3..5 B |
| #87/73| 8-byte `__builtin_memcpy` unrolled        | 0 in code (already worked around in `netboot_mpm.c:131`) | -10..15 B if fix lets us drop the workaround |
| #76 / #77 / #80 / #83 / #71 / #60 / #84 / #79 | various | **0** | 0 |

Functions ranked by size in current payload:

|  Size | Symbol | Source |
|------:|--------|--------|
| 430 B | `_snios_rcvmsg_c` | hand-asm in `snios.s` (not compiler) |
| 235 B | `_netboot_mpm`    | C |
| 117 B | `_cpnet_xact`     | C |
| 110 B | `_init_hardware`  | C |
| 107 B | `_cpnos_cold_entry` | C |
| 101 B | `_specc`          | C |
|  97 B | `_isr_crt`        | mostly asm |
|  88 B | `_impl_conout`    | C |

**Conclusion.**  Even if every open compiler issue landed today the
payload would shrink ~10..30 B (well under 2 %).  The remaining 390 B
to fit PROM-1 must come from the *structural* items (init/resident
split, CFGTBL/MSGBUF reuse, Path 3 payload-origin lift), not from
codegen.  No new compiler issues filed -- existing #73-#87 already
cover what's there, and the 0-hit issues are still useful for rcbios
where SDCC is now within ~100 B of clang.

Action items (existing, just re-prioritised by impact for cpnos-rom):

- [ ] Re-rank PROM-1 fit by structural delta first: init/resident
      split (~700 B est) >> CFGTBL/MSGBUF reuse (~200 B) >> Path 3
      payload origin (~256 B) >> all open codegen issues combined
      (~30 B).
- [ ] Re-run this scan (`python3 ... cpnos.lis`) after each
      `resident.c` / `netboot_mpm.c` change so the table stays
      honest; pre-Phase-B numbers in the 2026-04-29 block above are
      already stale.

## Phase A + B follow-ups (2026-04-30)

After the NDOS lift to 0xDEA0 (commits `6251525` Phase A, `a1e9ce9`
Phase B), the in-RAM resident layout is packed tight with 0 B
headroom between cpnos.com and scratch_bss LO.  These items are the
remaining axes to pull on.

### Path 3 (lift payload origin from 0xED00 to 0xEC00)

Would let cpnos.com end advance to 0xEC00 (NDOS = 0xDF80, +224 B
TPA), enough to round CPNOS_TPA_KB up to 56.  Blocked by:

- [ ] **Audit `cpbios.asm` hand-typed VMA references.**  Per memory
      `project_cpnos_address_coupling_brittle`: cpbios.asm
      "rbcout" etc. hand-typed.  Need to enumerate every literal
      address tied to BIOS_BASE = 0xED00 in cpnos-build/src/ and
      teach RMAC to take them via EQUs sourced from cpnos.sym (or
      from a generated .asm fragment), the way cpnios-shim.asm now
      sources NIOS = 0xED33.  Until this is done, moving payload
      origin will produce silent runtime failures, not link errors.
- [ ] **Add a payload.ld assert** that mirrors the cpnios-shim
      pattern for any *other* externs cpnos.com imports.  Right now
      only NIOS has a drift-trap.

### Init/resident split (DONE 2026-05-01, branch `init-resident-split`)

**Result: resident 2438 B -> 1746 B (-692 B, -28%); TPA 55K -> 56K
(Option β); 8 commits on branch `init-resident-split`, all green
through `make integration-test`.**

| Commit | Description |
|--------|-------------|
| `ad61dd2` | Plan written |
| `c6c00a4` | Step 2: tag init code+rodata in `.init.*` sections |
| `03a4248` | Step 3: split `.init` out, runs in place from PROM 0 0x0100 |
| `e131c16` | Option β: cpnos.com lift to 0xE080, +1K TPA, stack-collision asserts |
| `fa3dd6e` | Cleanup: drop dead `PROM1_CODE`, `scratch_bss_hi` consolidation |
| `336210f` | Pin `RC702_LOGIN_PWD` to `.init.rodata` (-8 B resident) |
| `607e496` | Split `cpnos_cold_entry` into init phase + resident handoff |
| `67780c8` | Shrink "INIT OK" marker to single 'I' (-26 B init) |

#### Key lessons (worth memory'ing)

- **Stack-vs-cpnos.com collision** silently overwrote the build stamp
  area when `SP=0xED00` and cpnos.com loaded up to 0xED00.  Now caught
  at link time via `__cpnos_load_end < __stack_top` ASSERT in
  `payload.ld`.  Also: `_zp_init_data` (read post-PROM-disable) MUST
  live in `.resident.data`; ASSERT enforces this.  Both checks
  enforced by `--defsym=__cpnos_load_end=...` from cpnos.sym.
- **PROM-resident `_msg` etc. read post-disable yields silent boot
  failure** (NDOS COLDST gets garbage zero-page bytes).  Caught only
  by integration test on first attempt; now caught by linker assert.
- **Init code can call resident-RAM helpers freely** because resident
  RAM (>=0xED00) is unaffected by PROM mapping.  PROM disable is a
  one-shot fence: cross via `JP _resident_handoff` (in RAM), don't
  try to OUT inside init.

#### Compiler issues filed (this branch)

- ravn/llvm-z80 #88 — N×16-bit constant pattern fill not lowered to
  seed-and-LDIR idiom (~6-8 B per call site, hits `setup_ivt`).
- ravn/llvm-z80 #89 — Loop-invariant 16-bit constant reloaded into
  DE every iteration despite IR-level hoist (regalloc clobbers DE
  for loop counter spill).

#### Follow-up items still open

- [x] **`set_i_reg(0xF5)` codegen pessimization filed as ravn/llvm-z80
      #90** (2026-05-01).  Clang routes the high byte of an extern
      symbol address through DE -> L -> A -> call in 10 B instead of
      `ld a, high(sym); call fn` in 5 B.  Plain constants and >>8 of
      numeric literals are already optimized; only the extern-address
      case is pessimized.  Saves 5 B at the `setup_ivt` site and at
      any similar byte-arg call derived from a link-time address.
- [ ] **`INIT_TEXT` / `INIT_RODATA` macros** (CLion squiggle suppression).
      `((section(".init.text")))` is treated as suspicious by CLion's
      host-triple analyzer; wrap in macros like the existing
      `RESIDENT` / `RESIDENT_BSS` pattern in `transport_pio.c` /
      `cfgtbl.c`.  Cosmetic only.
- [ ] **Path 3 prep** (lower `BIOS_BASE` from 0xED00 to 0xEC00) is
      now possible after init/resident split: resident only needs
      1746 B, fits in 0xEC00..0xF40F.  Still blocked on the
      `cpbios.asm` hand-typed VMA audit (see "Path 3" section above
      and memory `project_cpnos_address_coupling_brittle`).
- [ ] **CFGTBL/MSGBUF reuse for netboot** (see "Smaller / cleanup
      items" below) — independent of split; would save 200 B BSS.
- [ ] **Doc refresh** — `cpnos-rom/docs/memory_map.md` addendum was
      bumped to "Option β" but the body of the doc still describes
      the pre-Phase-A layout.  Regenerate from `llvm-nm`.

#### Original detailed plan (kept for reference)

**Goal.**  Move init-only code (`init_hardware`, `setup_ivt`,
`cfgtbl_init`, `print_banner`, `netboot_mpm`, `cpnet_xact`,
`install_fcb`, `reuse_fcb`) plus their rodata (`port_init[]`,
`FCB_HEAD`, banner, "INIT OK" marker) into a `.init` section that
**runs in place from PROM**.  Resident shrinks 2438 B -> ~1809 B in
RAM; 629 B of code+rodata stops occupying the 0xED00 region.

**Why "runs in place" and not "loaded then discarded".**  Loading
init into RAM and discarding it doesn't shrink the PROM image.
Running it from PROM keeps PROM image the same total size but the
*resident RAM footprint* drops.  That's the lever for TPA growth
and/or BIOS_BASE lowering.

#### Sizing facts (llvm-nm on clang/payload.elf, 2026-04-30)

Init-only code+rodata: 629 B
| Symbol            | Size  | Source             |
|-------------------|-------|--------------------|
| init_hardware     | 110 B | init.c             |
| port_init[]       | 110 B | init.c (rodata)    |
| "INIT OK" marker  |   8 B | init.c (rodata)    |
| cfgtbl_init       |  52 B | cfgtbl.c           |
| netboot_mpm       | 235 B | netboot_mpm.c      |
| cpnet_xact        |  49 B | netboot_mpm.c      |
| FCB_HEAD          |  12 B | netboot_mpm.c      |
| print_banner+text |  53 B | cpnos_main.c       |

Init-only BSS (already off-resident-payload, just notes):
- `_msg` 200 B, currently `.scratch_bss_hi` at 0xEC24.

Resident size after split: 2438 - 629 = ~1809 B in RAM.

#### Constraints / pre-flight checks

- **No resident -> init refs found.**  Explore-agent grep across
  resident.c, isr.c, transport_pio.c, snios.s, bios_jt.s, runtime.s
  returned zero references to any init-only symbol.  Clean cut is
  possible.
- **Init -> resident-RAM refs are fine.**  Init calls `impl_conout`,
  `snios_*`, `_port_out`, `_memcpy`, `clear_screen`, `isr_*` (via
  function pointers in `setup_ivt`).  All resolve to RAM addresses
  >= 0xED00 which are exposed regardless of PROM mapping, so init
  running from PROM can call them once the relocator has copied
  resident.
- **`clear_screen`** (16 B) is currently resident, called only by
  `init_hardware`.  Cheap to leave resident; optional move.
- **IVT** (0xEC00..0xEC23) is RAM, written by `setup_ivt`, read by
  IM2 hardware throughout.  Stays where it is.
- **`_cfgtbl`** (173 B, BSS) is written by `cfgtbl_init` (init) and
  read by SNIOS (resident).  Stays in resident BSS.
- **`_msg`** (200 B, BSS) is written/read only during netboot.
  Already in `.scratch_bss_hi` (not in PROM image).  Post-split it
  is fully discardable -- 0xEC24..0xECEC becomes free RAM.

#### Boot sequence after split

1. `reset.s` @ PROM 0x0000: `DI; SP <- 0xED00; JP _relocate`.
2. `relocator` @ PROM ~0x0010: copy **only resident** bytes from
   PROM (LMA) to RAM 0xED00..0xED00+resident_size; verify
   checksum; `JP _init_entry` (PROM address ~0x0100).
3. `_init_entry` @ PROM ~0x0100: setup_ivt, port_init loop,
   clear_screen (calls into RAM), banner (calls `impl_conout` in
   RAM), netboot_mpm (calls `snios_*` in RAM).  All resident
   targets are valid because relocator already populated 0xED00.
4. `_init_entry` tail: `JP _resident_handoff` (RAM 0xED00+offset).
5. `_resident_handoff` (resident, RAM): `OUT prom_disable;
   snios_ntwkin if not done; JP NDOS`.

Critical: PROM disable happens *after* JP into RAM, so the OUT
instruction itself executes from RAM.  Init code in PROM is
abandoned at that JP.

#### Step-by-step implementation

1. **Tag init sources.**  Add `__attribute__((section(".init.text")))`
   to `init_hardware`, `setup_ivt`, `cfgtbl_init`, `print_banner`,
   `netboot_mpm`, `cpnet_xact`, `install_fcb`, `reuse_fcb`.  Add
   `__attribute__((section(".init.rodata")))` to `port_init[]`,
   `FCB_HEAD`, `banner`, "INIT OK".

2. **Verify clang honours rodata-section attributes.**  Lit test
   first: confirm `static const __attribute__((section(".x"))) ...`
   actually places the array.  Filed as ravn/llvm-z80 issue if not.

3. **Linker layout.**  `payload.ld` becomes a two-region script:
   - `RESIDENT (rwx) : ORIGIN = 0xED00, LENGTH = ...` -- VMA=LMA,
     same as today (LMA is updated by Makefile when relocator
     embeds it).
   - `INIT (rx) : ORIGIN = 0x0100, LENGTH = 0x0700` -- VMA=LMA,
     runs in place from PROM 0.
   - `.init.text` / `.init.rodata` sections placed in `INIT`.
   - ASSERT `__init_end <= 0x0800` (PROM 0 budget after relocator).

4. **Relocator update.**  `relocator.c` already #embeds
   `payload_a.bin` + `payload_b.bin` and copies them to RAM.
   Update Makefile so those embeds contain only the resident
   bytes -- `objcopy --only-section=.resident* --only-section=.text*
   ... -O binary` after `objcopy --remove-section=.init.*`.
   Update `_cpnos_cold_entry` extern resolution to instead point
   at `_init_entry` (still extracted via llvm-nm + --defsym).

5. **Reset/entry chain.**  Today `cpnos_cold_entry` does
   `cfgtbl_init -> init_hardware -> EI -> banner -> netboot ->
   prom_disable -> snios_ntwkin -> nos_handoff`.  Split into:
   - `_init_entry` (in `.init.text`): everything up to and
     including netboot_mpm; tail `JP _resident_handoff`.
   - `_resident_handoff` (in `.resident`): EI; PROM disable;
     snios_ntwkin if not done in init; JP NDOS.

6. **Drop `_msg` from `.scratch_bss_hi`.**  Place it in a new
   `.init.bss` section linked into the same RAM region
   (0xEC24..0xECFF works -- that RAM survives PROM disable).
   Net: post-split, scratch_bss_hi is empty and 0xEC24..0xECFF is
   free RAM, available for cpnos.com extension.

7. **Pick a "what to do with freed RAM" path** (separate decision):
   - **Option β (recommended first):** keep `BIOS_BASE = 0xED00`,
     remove scratch_bss_hi region, advance cpnos.com end target
     from 0xEB1F to 0xECFF (raise `DATA_BASE`/`CODE_BASE` by
     ~0x1E0 = ~480 B).  Mechanical change in `cpnos-build/Makefile`
     + `payload.ld` ASSERTs.  No `cpbios.asm` audit needed.
   - **Option α (Path 3 prep first):** lower `BIOS_BASE` from
     0xED00 to 0xEC00.  Requires the `cpbios.asm` hand-typed VMA
     audit listed above.  Bigger change.
   - Recommend β -- delivers TPA gain immediately, leaves Path 3
     as a separate later step.

8. **Build pipeline.**
   - `Makefile`: split objcopy into `.resident.bin` + `.init.bin`;
     embed `.resident.bin` into relocator; embed `.init.bin` at
     PROM 0 0x0100 via a new `.prom0_init` section in relocator.ld.
   - `split_proms.py`: lay out PROM 0 = reset + relocator + init.bin
     + payload_a; PROM 1 = payload_b; pad with 0xFF.

9. **Tests / verify.**
   - `llvm-nm clang/payload.elf` shows init symbols in `.init.text`
     at addresses < 0x0800 and resident symbols at >= 0xED00.
   - `make integration-test` (PPAS primes E2E in MAME): full pass.
   - Diff `payload.bin` size: down by ~629 B in resident region.
   - Banner shows updated TPA (after Option β).

#### Risk register

- **Section attr drift**: clang may not place `static const` rodata
  in custom sections.  Mitigate with a build-time `llvm-nm | grep
  init.rodata` check.  XFAIL lit test if broken.
- **Init address drift between builds**: `_init_entry` PROM address
  must be reachable from relocator at link time -- already the
  pattern for `_cpnos_cold_entry` via `--defsym`, just rename.
- **PROM disable timing**: must be in RAM-resident code, not init
  code in PROM.  Step 5 enforces this by moving prom_disable out
  of `cpnos_cold_entry` into `_resident_handoff`.

#### Effort estimate

- Split + Option β: ~1 day (mostly Makefile + linker script +
  attribute tagging + verify).
- Split + Option α (with cpbios audit): ~2-3 days.

#### Sub-tasks from this plan (all DONE 2026-04-30..2026-05-01)

- [x] Lit test: clang honours `((section(".x.rodata")))` on
      `static const` arrays.  Verified locally (no upstream issue
      needed).
- [x] Tag init sources with `((section(".init.text")))` /
      `((section(".init.rodata")))` (commit `c6c00a4`).
- [x] Two-region payload.ld + ASSERTs on init/resident sizes
      (commits `03a4248`, `e131c16`).
- [x] Split objcopy + relocator embed update (commit `03a4248`).
- [x] Entry chain split: cpnos_cold_entry into init phase +
      resident_handoff (commit `607e496`).
- [x] `_msg` consolidated into the unified scratch_bss region above
      IVT (commit `fa3dd6e`).  ".scratch_bss_hi" attr removed; one
      region only post-Option β.
- [x] Option β chosen and implemented (commit `e131c16`).  Path 3
      (Option α, `BIOS_BASE` lowering) deferred -- still requires
      `cpbios.asm` hand-typed-VMA audit.
- [x] Verify via `make integration-test` (every step passed).
- [ ] Update `docs/memory_map.md` body with post-split layout
      (addendum is current; body is stale).

### Smaller / cleanup items

- [ ] **CPNOS_TPA_KB rounding.**  Current `(NDOS+0x22)/1024` floors
      to KB, so Phase B's 288 B win disappears in the banner.
      Either switch to nearest-KB rounding, or report bytes (e.g.
      "55 K (+0x120)").  One-line Makefile change.
- [ ] **Update `cpnos-rom/docs/memory_map.md`** to reflect Phase B
      end-to-end.  An addendum block was added at the top of the
      doc in 2026-04-30; the rest of the doc still narrates the
      pre-A layout (0xD000 NDOS, 0xEA00 NIOS, etc.) and should be
      regenerated from `llvm-nm --numeric-sort clang/payload.elf`.
- [ ] **CFGTBL/MSGBUF reuse for netboot.**  Per cfgtbl.c:14, SNIOS
      uses `_cfgtbl + 45` as MSGBUF (128 B) post-netboot.  netboot
      currently allocates a separate `_msg[200]`.  If netboot can
      stage frames in `_cfgtbl[+45..+172]` with the same buffer
      reused after `cfgtbl_init()` re-initializes the header, we
      save 200 B of resident RAM.  Caveat: netboot's max response
      (171 B) is bigger than MSGBUF's 128 B; would need to either
      shrink the response (reduce FCB carry?) or extend MSGBUF for
      our slave only.  Investigate cost.
- [ ] **Auto-extracted addresses for *other* harnesses.**  Only
      `mame_ppas_test.lua` was caught and fixed (Phase B); audit
      `mame_*` lua scripts and Python tests for other hard-coded
      BSS addresses that would silently rot on a future move.

