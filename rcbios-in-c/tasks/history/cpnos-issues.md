# CP/NOS ROM — Open Issues & Follow-up Tasks

Concrete items surfaced during the planning sessions that need action before
or during implementation. Live next to `cpnos-rom-plan.md`.

## MAME observations (Phase 1 work-in-progress)

- **Display RAM at 0xF800 is not visible until CRT + interrupts are
  enabled.** Writing bytes via `LD ($F800),A` from ROM code did not
  produce readable bytes at 0xF800 in the MAME boot test — either MAME
  emulates display RAM as CRT-DMA-gated (reads return 0 while CRT is
  idle) or some other interaction keeps our writes invisible.  Either
  way, the MVP path is: enable IVT + PIO + DMA + 8275 CRT + interrupts
  in init_hardware before expecting display-based test oracles to work.
- **Alternative test oracles while CRT is still offline:** SIO-B TxD
  toggles (capture via MAME null-modem image), MAME debugger memory
  dump of 0xF800 after a known delay, or a software-maintained "alive"
  byte at a non-display RAM address polled by the lua script.

## Verification tasks (before Phase 1 code)

- [ ] **Confirm port 0x14 is DIP switch on MIC702.** User stated this is
      "probably" the case. Verify against `RC702_HARDWARE_TECHNICAL_REFERENCE.md`
      and/or MAME `rc702.cpp` port map. If confirmed, document in the
      hardware reference; if wrong, fix here.

- [ ] **Verify MAME rc702 driver implements OUT 0x18 → PROM disable.**
      Write a tiny test (OUT 0x18, then read 0x0000, expect RAM value we
      just wrote, not PROM byte). Needed before Phase 1 because MAME is
      our main test harness.

- [ ] **Confirm SNIOS entry-point address stability requirement.**
      Current 0xDA12 / 0xDA15 / 0xDA4D — are these hard-coded into any
      CP/NOS applications we need to run, or is everything we'll load
      fresh enough to use whatever addresses we pick? Check `cpnet-z80/`
      client utilities.

- [ ] **Find NDOS.SPR (or equivalent) for the CP/NOS client runtime.**
      The combined image loads CCP+BDOS via netboot; CP/NOS uses NDOS
      (not standard CP/M BDOS). Need to confirm which binary the server
      streams — NDOS is in `cpnet-z80/dist/src/ndos.asm`, need the
      assembled image and to verify it fits the 6–8KB budget.

## Server-side work

- [x] **Stream real NDOS.SPR (session #25).** `netboot_server.py` now
      reads `cpnet-z80/dist/ndos.spr`, applies DRI SPR page-relocation
      (128B header -> code_len body -> code_len/8 MSB-first bitmap,
      add base_page to flagged bytes) to NDOS_BASE=0xE300, and streams
      24x 128B blocks via one FNC=2 + N FNC=3 pairs.  MAME verifies
      relocation correctness at 0xE702/0xE705 (link-relative 0x01/0x05
      -> 0xE4/0xE8 after +base_page).  CCP still pending.

- [ ] **Stream real CCP.SPR.**  Same pattern as NDOS.  ccp.spr
      code_len=0x0A00 (2.5KB) -> CCP_BASE=0xD900, 20 blocks.  Needed
      before the FNC=4 execute can hand off to real CCP instead of
      the current RET stub at 0xDB80.

- [ ] **z80pack cpmsim MP/M netboot handler.** Extend the MP/M master
      running on z80pack to respond to FMT=0xB0/FNC=0 boot request with
      the CP/NOS load sequence (FNC=1/2/3/4). Reference:
      `cpnet-z80/src/netboot.asm`. May need host-side Python bridge if
      z80pack cpmsim MP/M doesn't have a netboot handler out of the box.

- [ ] **Document the z80pack ↔ MAME null-modem pipe.** How does MAME's
      SIO-A null-modem image connect to z80pack's CP/NET character device?
      Likely a PTY bridge or named pipe. Add to `docs/cpnos-server.md`.

## Parked / future

- [ ] **Parallel-port transport (PIO-B / J3 half-duplex, Option P).**
      Design pinned 2026-04-25 in
      `../../docs/cpnet_fast_link.md`. Implementation deferred until
      Pi 4B host hardware is acquired. Earlier "PIO Mode 2 on J3/J4"
      framing is obsolete: Mode 2 is impossible (ARDY not routed),
      and the keyboard-on-J4 constraint locks PIO-A. Transport vtable
      slot in Phase 1 still planned so this drops in cleanly. ~520 B
      reserved in the budget; size estimate stands.

- [ ] **Local-diskette cache policy.** Phase 3 benchmark: is local 8" DSDD
      read meaningfully faster than SIO-A 38400 for the CCP+BDOS image?
      If so, add boot-time `CPNOS.SYS` lookup on B: with server fallback.

- [ ] **IOBYTE defaults.** Map SIO-A for NOS traffic, SIO-B for console.
      Confirm matches `rcbios-in-c` convention and document in
      `docs/cpnos-iobyte.md`.

- [ ] **Multi-node SLAVEID story.** Current plan is hard-coded 0x70.
      If multiple RC702s ever need to share one MP/M master, either:
      build per-node variants, or read a DIP-switch byte at boot. Decide
      only when the need arises.

## llvm-z80 codegen risks (monitor during Phase 1)

- [ ] **Transport vtable indirection.** `(HL)` call-through-pointer patterns
      may stress GlobalISel. If codegen bloats the transport layer,
      consider flattening to direct calls with `#if ENABLE_PARALLEL`.

- [ ] **Asm ↔ C interop for SNIOS/netboot.** Porting `snios.asm` and
      `netboot.asm` means clang must link DRI-style asm. Check
      `autoload-in-c/` for precedent — current autoloader does C+asm mix.

## Session 24 (SNIOS port) — new issues

## Session 28 (NDOS hang diagnosis) — new issues

- [x] **Null-jump trap at 0x0000 (resolved as diagnostic).**  resident_entry
      now writes `JP 0x0000` (`c3 00 00`) at 0x0000 instead of the CP/M
      `JP _bios_wboot` convention.  Turns any stray null jump into a
      stable `PC=0x0000` so the hang is visible in the MAME probe.
      Will switch to the real `JP _bios_wboot` once SNIOS wiring below
      is resolved and NDOS can be trusted not to dereference nulls.

- [x] **NDOS expects SNIOS.SPR immediately after NDOS (root cause).**
      The DRI NDOS.SPR is linked so SNIOS's jump table lives at
      NDOS_BASE + 0xC00 (= code_len).  With NDOS at 0xDE00, that's
      **0xEA00**.  NDOS's `CALL NTWKIN` in COLDST goes there first;
      on our build that address is zero (NDOS BSS region), so the call
      executes NOPs forward into garbage and NDOS unwinds into a
      `JP (HL)` with HL = BDOSE = 0 → null-loop.  The
      uninitialised-BDOSE symptom was downstream.

- [x] **Wire SNIOS jump table at 0xEA00 (resolved).**  resident_entry
      now memcpys the 24 bytes of `snios_jt` from its BIOS-resident
      address (0xF233) to 0xEA00 right before `jump_to(0xDE03)`.  NDOS
      COLDST now progresses past NTWKIN, through the TLBIOS walk,
      CNFTBL, BDOSE setup, and into NWBOOT.  New hang appears further
      downstream (see below) — baseline null-loop gone.

- [ ] **CCP/NDOS warm-boot loop at 0xD3F5.**  After NDOS COLDST reaches
      NWBOOT, execution lands in CCP at `ccpstart+0xC` (0xD3F5, the
      `call setuser` site).  PC cycles: `D3F5: call D13A` → ... →
      returns → somehow re-enters ccpstart → `lxi sp,stack` → `push b`
      → A/HL differ each pass so some state is flowing.  Likely causes:
      (a) NWBOOT's `call LOAD` is succeeding/failing in a way that
          GOCCP re-enters ccpstart each time,
      (b) A BDOS call inside setuser triggers warm-boot via CP/M
          function 0 (reset),
      (c) NDOS's MSGBUF / CFGTBL isn't initialised the way CCP expects.
      Next step: trace at higher granularity from the first D3F5 hit
      (line 805493) to see the exact path back to ccpstart.  Also:
      server-side should start listening for SNIOS SNDMSG after FNC=4,
      because GOCCP → LOAD path is expected to hit the wire.

## Session 27 (real CCP cold-boot handoff) — new issues

- [x] **JP (HL) trampoline for real CCP handoff (resolved).**  Added
      `_jump_to` in `snios.s` (single `JP (HL)`), lives in .resident so
      it survives PROM disable.  `resident_entry` calls it after
      writing the BDOS vector at 0x0005 (`JP 0xE206`) and running
      SNIOS NTWKIN.  MAME confirms PC lands inside NDOS (PC=0xEA35)
      after the jump, SP inside CCP/NDOS region — handoff is live.

- [x] **CCP BSS-past-code hypothesis was wrong (resolved).**
      Disassembling relocated CCP at ccpstart (0xD3E9 when based at
      0xD000) shows `LXI SP, 0xD8FF` — CCP's stack symbol is at link
      offset 0x08FF, **inside** its 2560 B code_len.  The SP=0xE199/
      0xE399 I was observing at finish time was NDOS's stack (NDOS
      has `LXI SP, 0xDF9B` at its own offset 0x288), not CCP's.  So
      CCP needs exactly code_len bytes — no extra BSS allocation.
      NDOS has one path that does `LXI SP, 0xEBE9` (link offset
      0x0DE9, 411 B past code_len); that stack grows *down* from
      0xEBE9 so doesn't overshoot our BSS at 0xEC00 — safe.

- [ ] **Could use a pre-linked CCP at a specific base.**  Instead of
      runtime SPR relocation we could either (a) re-link ccp.spr
      with LINK-80 `[Lnnnn]` to bake in an absolute base and skip
      relocation, (b) use MOVCPM.COM to relocate a full CPM.COM
      image to our target memory size, or (c) pick a smaller CCP
      source (standard CP/M 2.2 is 2 KB vs CP/NET 1.2's 2.5 KB).
      Our SPR relocator already works, so (a) is no-gain; (c) would
      shrink CCP by 0.5 KB and recover 2 pages of TPA.  Probably
      worth revisiting once everything else is stable.

- [ ] **CCP/NDOS stuck at PC=0xEA35.**  Handoff works but control
      settles inside NDOS and never emits a console prompt.  No wire
      traffic after FNC=4 (server log shows only "client closed" at
      timeout).  Likely causes: (a) NDOS's CNFTBL query is returning
      a value that makes it loop, (b) NDOS is waiting on a BIOS entry
      we don't implement correctly (bios_stub_ret returns but without
      setting expected registers), (c) NDOS needs a specific
      MSGBUF pre-initialisation we haven't done.  Next step:
      instruction-trace from 0xE206 forward to find the hang.  0xEA35
      is at NDOS offset 0x835; map to source in ndos.asm for context.

- [ ] **Server no longer probes SNIOS SNDMSG/RCVMSG.**  Removed the
      one-shot `sniosro_handshake()` from `netboot_server.py` because
      NDOS, not resident_entry, now drives SNIOS after FNC=4.  The
      wire-protocol regression test (round-trip verify) is therefore
      parked.  When we return to SNIOS work, bring it back under a
      flag or a separate test harness that bypasses CCP.

## Session 26 (SPR relocator correction, CCP blocker) — new issues

- [x] **SPR format: ignored sector between header and code (resolved).**
      The DRI SPR file layout carries a 128B "ignored" sector after the
      128B parameter sector and before the code image.  The loader
      `cpnetldr.asm:566` reads it with `CALL OSREAD ;GET DATA & IGNORE`
      and discards the buffer.  Session #25's relocator missed this and
      was reading 128B of zero padding as the start of code — shifting
      every byte offset by 128.  The NDOS smoke check at 0xE702/0xE705
      passed coincidentally because both the "code" and the "bitmap" I
      was reading were shifted together and the particular bit arithmetic
      happened to produce the right delta.  Real NDOS entry after fix:
      **0xE300 = JP 0xE571 (NDOSE)**, **0xE303 = JP 0xE4F6 (COLDST)**.

- [x] **CCP placement stomps scratch_bss (resolved).**  `.scratch_bss`
      moved from 0xE000..0xE217 to 0xEF00..0xF118 in the linker script
      (window between NDOS top 0xEEFF and BIOS_BASE 0xF200).  SCRATCH
      region narrowed from 4KB to 0x300=768B with a hard ASSERT that
      BSS cannot overflow into the resident region.  Diagnostic
      breadcrumbs in `resident.c` moved from 0xE200/0xE210.. to
      0xEF00/0xEF10.. accordingly (both now live inside `rx_buf`, which
      is fine — rx_buf is stale post-SNIOS and the writes are
      diagnostic-only).  Stack space shrinks from ~4KB to 232B (0xF200
      down to 0xF118); fine for current code but worth watching if we
      add deeper call chains.

- [ ] **Indirect call via `__call_iy` dies after PROM disable.**  Clang
      lowers `((fn_t)(uintptr_t)entry)()` to `CALL __call_iy` where
      `__call_iy` lives in PROM0 at 0x0009.  `disable_proms()` in
      `resident_entry` unmaps the PROMs just before the CALL, so 0x0009
      becomes RAM (zero), the CALL falls through NOPs until it crosses
      into streamed CCP code, and CCP's entry prologue (`lxi sp,stack`)
      resets SP to ~0xE1FB mid-CCP.  Workaround in session #26: removed
      the indirect call entirely (parameter `entry` still accepted but
      unused; entry was always 0xDB80 = RET stub anyway).  Real CCP
      handoff (session #27+) needs one of:
        (a) Inline asm: PUSH return-address + `JP (HL)`.
        (b) A resident-section copy of `__call_iy` (compiler runtime
            helper relocated into .resident so it survives PROM disable).
        (c) Tail-call style: emit `JP (HL)` without saving a return
            address, since `resident_entry` is `[[noreturn]]` and CCP
            doesn't return anyway.
      Likely (c) is smallest and cleanest — needs a small asm trampoline.

- [x] **Stack space narrowed to 232B (resolved via lower bases).**
      Shifted CCP 0xD900 -> 0xD800 and NDOS 0xE300 -> 0xE200 (one page
      each).  BSS window above NDOS widens from 768B to 1KB; BSS itself
      stays 540B at new origin 0xEE00.  Stack headroom doubles from
      232B to 488B (0xF200 - 0xF018).  TPA drops 0.1KB (54.6 -> 54.5KB)
      — still within the 55KB+ band.  Layout recorded in cpnos_rom.ld
      header and probe comments.

- [ ] **Update memory-map documentation.**  The runtime map in
      cpnos-rom-plan.md still shows CCP at 0xDB80 (2KB) and NDOS at
      0xE380 (3.5KB).  Real fit is CCP 0xD900..0xE2FF (2.5KB) + NDOS
      0xE300..0xEEFF (3KB).  Both now must be page-aligned (SPR
      requirement) and bases were chosen "lower than needed to be
      safe" with later tightening planned.

- [ ] **BDOS vector layout at 0x0005 for CP/NOS.**  NDOS's COLDST at
      ndos.asm:196 reads BDOS+1 (i.e. 0x0006, the 16-bit operand of the
      JP at 0x0005) and caches it as BDOSE.  So cold-boot has to write
      `JP 0xE306` at 0x0005 — the `+6` hits NDOS's *second* JMP NDOSE
      block (ndos.asm lines 82-88 have two back-to-back `jmp NDOSE;
      jmp COLDST` groups, so offsets 0/3 and 6/9 both work, and the +6
      pattern matches the standard CP/M "BDOS entry = base+6" convention
      that leaves a 6-byte ID/JMP preamble at the module base).

- [ ] **SPR relocator: round bitmap length up for non-multiple-of-8
      code_len.**  Current code uses `code_len // 8`; if some future
      module has `code_len = 3073`, the last few bits of the bitmap
      would be silently truncated.  ndos.spr (0x0C00) and ccp.spr
      (0x0A00) are both clean multiples so we're safe today.  Fix:
      `(code_len + 7) // 8` + assert file size accommodates it.

- [ ] **Secondary smoke check: NDOS copyright string.**  `ndos.asm:94`
      embeds the literal `"COPYRIGHT (C) 1980-82, DIGITAL RESEARCH "`.
      Bytes are ASCII and are *not* relocated, so they land verbatim
      at their module offset after streaming.  A grep at a stable
      offset (TBD once we dump the module layout) is a nice independent
      check that streaming transferred the body intact, independent of
      relocation correctness.

## Session 25 (NDOS SPR streaming) — new issues

- [ ] **CCP streaming + real cold-boot handoff.**  NDOS is in RAM at
      0xE300 but nothing calls it.  Next steps: (a) relocate+stream
      ccp.spr to 0xD900, (b) change FNC=4 execute from the RET stub
      at 0xDB80 to the CCP cold-start entry, (c) wire NDOS's BIOS
      vector back-pointer so NDOS can find BIOS entries (typically
      BIOS base is passed in HL at CCP entry, or baked into NDOS at
      link time via a fixed address).  Decide which convention the
      cpnet-z80 NDOS expects — inspect `cpnet-z80/dist/src/ndos.asm`.

- [ ] **SPR relocator coverage.**  Current Python relocator asserts
      page-alignment + bitmap length but doesn't handle data_len>0
      (both ndos.spr and ccp.spr have data_len=0).  Add a path for
      modules with pre-initialised data when we stream those later
      (e.g. future FDOS.SPR).  Small: copy data_len bytes unchanged
      immediately after code.

- [x] **NDOS entry discovery (resolved).**  Inspected
      `cpnet-z80/dist/src/ndos.asm:80-88`.  Module starts at `org 0`
      with `NDOSTP: JMP NDOSE` (BDOS dispatch) at offset 0 followed
      by `JMP COLDST` at offset 3.  After our relocation to 0xE300:
      **0xE300 = BDOS entry**, **0xE303 = COLDST**.  CP/M BDOS vector
      at 0x0005 should be `JP 0xE303` (the +3 half-convention where
      the low byte of the BDOS vector doubles as the top-of-TPA
      marker).  `BDOSE` word at NDOS+? stores a host-supplied entry —
      need a closer read when wiring CCP handoff.

- [ ] **Wire BDOS vector + CCP cold-boot handoff.**  After CCP.SPR is
      streamed and relocated to 0xD900, cold-boot path needs to:
      (a) write `JP 0xE303` at 0x0005 (BDOS vector);
      (b) populate NDOS's BDOSE word with the BDOS entry;
      (c) call CCP cold-start at 0xD900 (or 0xD900+8, convention
          varies — cpnet CCP.ASM header will tell).
      Currently FNC=4 executes a RET stub at 0xDB80 which is unrelated.

- [ ] **Remove SNIOS smoke calls from resident_entry once real NDOS
      runs.**  The `snios_ntwkin`/`sndmsg_c`/`rcvmsg_c` calls in
      `resident.c:71-86` are Session #24 smoke tests; in production
      NDOS is the caller of SNIOS.  Keep them behind a debug flag or
      delete once NDOS drives the net traffic end-to-end.

## Session 24 (SNIOS port) — new issues

- [x] **NDOS/BIOS memory collision (resolved).** Took option (a):
      CCP base moved from 0xDF80 -> 0xDB80 in `netboot_server.py`.
      Runtime map now CCP 0xDB80..0xE37F (2KB), NDOS 0xE380..0xF17F
      (3.5KB est.), BIOS 0xF200..~0xF562, display 0xF800+.  ~130B
      slack between NDOS top and BIOS.  TPA drops from 56KB to 54.6KB
      (plan's TPA target was 55KB for NOS-only; we come in 0.4KB under
      but still well within the "55KB+" bullet).  Revalidate when
      cpnet-z80's real NDOS.SPR hits the stream — if NDOS turns out
      smaller than 3.5KB we can reclaim some TPA by raising CCP back up.

- [ ] **SNIOS jump table not yet wired to NDOS.** `_snios_jt` is
      exposed at 0xF233 but nothing references it.  Once the server
      starts streaming real NDOS, the cold-boot handoff has to tell
      NDOS where SNIOS lives (typical DRI convention: a BIOS entry
      returns the SNIOS address, or the address is baked into NDOS at
      server-side link time).  Wiring TBD when real NDOS lands.

- [ ] **SNIOS NTWKDR drain timeout.** Per-poll `transport_recv_byte`
      timeout hard-coded to 64 ticks.  Fine for MAME but may miss
      trailing stale bytes on real hardware if the SIO buffer drains
      slowly.  Measure on real HW before declaring NTWKIN reliable.

- [ ] **SNIOS CHKACK `AND 7FH` mask.** Carried over from the DRI
      original, which targeted 7-bit async links.  Redundant on our
      8N1 transport but harmless — costs 2B.  Remove if we need the
      space.

- [ ] **SNIOS not protocol-tested yet.** Smoke test verified jump
      table placement and CFGTBL data only.  Need `cpnet/server.py`
      brought up against SNIOS on cpnos-rom to confirm wire format
      round-trips (ENQ/ACK/SOH header/STX data path).  Blocker for
      Phase 1 end state.

- [ ] **CFGTBL symbol naming.** Renamed `_cfgtbl` → `cfgtbl` in
      `cfgtbl.c` so the asm-visible symbol is `_cfgtbl` (clang Z80
      prefixes one underscore). Document the convention for future
      C↔asm shared data: C source should NOT start identifiers with
      underscore or the asm name ends up double-prefixed.

- [ ] **MAME lua probe hardcodes CFGTBL address.** `mame_boot_test.lua`
      has `cfg_addr = 0xF4BC` baked in; every time the resident layout
      shifts, the constant needs manual update (last shifted from
      0xF4B3 -> 0xF4BC when `snios_ntwkin()` call landed).  Fix:
      either resolve the symbol from the ELF at test time, or
      memory-scan for the SLAVEID+16-zero-drives pattern.

- [ ] **Init stack 0xF200 vs netboot DMA.** Stack pointer init moved
      to 0xF200, grows down into 0xF1FF..0xF000.  If netboot ever
      receives payload with SIZ+DMA landing in 0xF000..0xF1FF, stack
      would corrupt or be corrupted.  Add an assert in netboot or a
      comment pinning the DMA range before real NDOS lands here.

## Decisions to defer until we have numbers

- [ ] **Single or dual network DPH (A: only, or A: + extra drives).**
      Decide after measuring ROM headroom in Phase 1.

- [ ] **How much of the current BIOS to reuse literally vs rewrite.**
      Session #23 BIOS is 6002B full-featured; cpnos-rom needs a subset
      (~2KB). Probably cleaner as a new file tree than heavy `#ifdef`
      surgery — confirm once Phase 1 scaffolding exists.
