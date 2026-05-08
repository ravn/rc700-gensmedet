# RC700-SYSGEN Project Timeline

## Phase 1: SYSGEN Reconstruction (Apr-May 2023)
- **2023-04-28**: Initial commit. SYSGEN.ASM from CP/M 2.2 source, RCSYSGEN.COM from RC702 system
- **2023-04-28**: MAC assembler chosen (Digital Research native CP/M assembler)
- **2023-04-29**: SYSGEN.COM byte-identical to RCSYSGEN.COM — first byte-exact reconstruction
- **2023-04-29**: Multi-density track/sector mapping documented (mini/maxi translation tables)
- **2023-05-07**: Added SYSTEM.ORG for reference comparisons

## Phase 2: Toolchain Modernization (Sep 2025)
- **2025-09-21**: Added zmac assembler (macOS native) — cross-assembly without CP/M emulator
- **2025-09-21**: Toolchain decision: zmac with DRI syntax compatibility over MAC under emulation

## Phase 3: ROA375 Boot PROM (Jun 2025, then Feb 2026)
- **2025-06-29**: Added ROA375 autoload PROM binary and ROB358 (RC703 variant) source reference
- **2026-02-08**: Ghidra seeding script for ROM analysis; Makefile for SYSGEN
- **2026-02-08**: Fresh ROM disassembly started with PORT14 documentation
- **2026-02-09**: Byte-exact disassembly of ROA375 achieved (z80dasm + manual cleanup)
- **2026-02-10**: Raw disassembly converted to annotated style with EQUs and labels
- **2026-02-11**: CLAUDE.md created; rob358.mac adapted for zmac
- **2026-02-14**: Systematic documentation: port values, CRT work area, comment style standardized

## Phase 4: ROA375 C Rewrite (Feb 16-19, 2026)
- **2026-02-16**: Architectural decision: rewrite ROA375 in C using z88dk with sdcc backend
- **2026-02-16**: z88dk toolchain added; autoload-in-c/ scaffold created
- **2026-02-16**: Full C implementation: boot logic, FDC driver, HAL abstraction, host tests
- **2026-02-17**: Code too large for 2KB PROM — all C moved to hand-written assembly
- **2026-02-17**: Key decision: switch to sdcccall(1) ABI — params in A/HL/DE
- **2026-02-17**: Reversed course: globals-only C experiment showed sdcc can be small enough
- **2026-02-18**: Progressive migration back to C: boot7, hal_delay, init functions
- **2026-02-18**: Final result: 1984 bytes (64 to spare), boots in rc700 emulator
- **2026-02-19**: CRT/display interrupt handler documented and renamed

## Phase 5: CP/M BIOS Reverse Engineering (Feb 19-21, 2026)
- **2026-02-19**: BIOS RE analysis started — imd2raw.py extracts Track 0 from disk images
- **2026-02-20**: jbox.dk rel.2.1 BIOS sources obtained — modular structure identified
- **2026-02-20**: 58K Compas BIOS disassembled from disk image, byte-verified
- **2026-02-20**: verify_bios.py created for automated BIOS verification
- **2026-02-21**: patch_bios.py, imdinfo.py tools created for disk image manipulation
- **2026-02-21**: Conditional assembly restructured: COMPAS renamed to REL14
- **2026-02-21**: CONFI.COM reverse engineered (SIO label swap bug discovered)

## Phase 6: BIOS Source Reconstruction — All 13 Variants (Feb 21 - Mar 1, 2026)
- **2026-02-21**: rel.2.3 MAXI build added; RC703 analysis began
- **2026-02-24**: PHE358A.MAC analyzed (RC702E variant PROM with RAM disk)
- **2026-02-25**: bin2imd.py: RC703 format support added
- **2026-02-27**: 14 unique BIOSes extracted from 20 disk images
- **2026-02-27**: MAME boot testing: UPD765 ST0 HD bit regression discovered
- **2026-02-28**: REL20 conditional assembly added — 5 variants from shared source
- **2026-03-01**: All 13 BIOS variants byte-verified:
  - src/ (shared): REL20, REL21, REL22, REL23-mini, REL23-maxi (5)
  - src-58k/: REL13-mini, REL14-mini, REL14-maxi (3)
  - src-rc703/: REL10, REL12, RELTFj (3)
  - src-rc702e/: REL201-mini, REL220-QD (2)

## Phase 7: REL30 New BIOS Development (Mar 1-3, 2026)
- **2026-03-01**: BIOS rel.3.0 created — new features, not a reconstruction
- **2026-03-01**: SIO ring buffer (256B, page-aligned) + PIO keyboard ring buffer (16B)
- **2026-03-01**: 8-N-1 at 38400 baud on SIO Channel A (was 7-E-1 at 1200)
- **2026-03-01**: Bidirectional serial verified: PIP file transfer byte-identical
- **2026-03-02**: RTS flow control with hysteresis (deassert at 248, re-assert at 240)
- **2026-03-02**: AUTOEXEC.COM disassembled; run_mame.sh automation script
- **2026-03-03**: Ring buffer optimization: register-cached TAIL, parametric size
- **2026-03-03**: SCROLL optimization: unrolled LDIR into 16-wide LDI loop (20% faster)

## Phase 8: CP/NET Implementation (Mar 4-6, 2026)
- **2026-03-04**: SNIOS.SPR written (1280B Z80 assembly): hex-encoded CRC-16 serial framing
- **2026-03-04**: Python CP/NET server: BDOS F13-F40, F64-F65, F70-F71 over TCP
- **2026-03-04**: SPR relocatable format implemented (dual-assembly bitmap technique)
- **2026-03-04**: File transfer validated: 204KB BIGFILE.DAT, 1600 records, zero packet loss
- **2026-03-06**: Automated test suite: autotest.lua (MAME Lua) + run_test.sh orchestrator
- **2026-03-06**: imd_cpmfs.py: CP/M file injector for IMD disk images
- **2026-03-06**: Server expanded: F28/F30/F33-F35/F40 handlers added
- **Key decision**: Custom hex-encoded CRC-16 protocol (from cpnet-z80 serial SNIOS)
  over DRI's original ENQ/ACK protocol — simpler, proven in other Z80 implementations
- **Key decision**: BIOS READER/PUNCH entry points for I/O (not direct SIO access)
  — simpler SNIOS, ring buffer handled by BIOS ISR

## Phase 9: RC702E Modular Source (Mar 7, 2026)
- **2026-03-07**: RC702E BIOS split into modular source files (current branch: rc702e-modular)
- **2026-03-07**: Work area 0xFFD0-0xFFFF mapped with ORG+DS layout

## Phase 10: CP/NOS autoloader PROM — bring-up (Apr 20, 2026)
- **2026-04-20**: New subtree `cpnos-rom/` — combined autoloader + runtime BIOS image
  intended to burn into RC702's two 2 KB EPROMs.  Goal: cold-boot a CP/NOS slave
  directly from PROM, no 8″ floppy required.  **(Easy)** basic skeleton (reset.s,
  linker script, clang Z80 build) landed in hours.
- **2026-04-20**: PROM-disable hazard diagnosed and fixed — `OUT (0x18),A` has
  to be issued from RAM-resident code, not from PROM-backed code that's about
  to vanish from under the program counter.  **(Hard)** MAME boot test reliably
  reproduced the hazard only after explicit PROM-mapping assertions were added.
- **2026-04-20**: SIO-B (polled) + SIO-A (transport) + CTC bring-up in C;
  38400 8N1 TX verified.  **(Easy)** — same ports as rcbios-in-c, semantics
  unchanged.
- **2026-04-20**: Netboot protocol wired end-to-end against the Python server;
  cold-boot fetches a remote image into RAM.  First hang was in FNC=4 (execute)
  — server-side protocol quirk, not Z80 side.  **(Medium)**

## Phase 11: CP/NET on bare CP/NOS — real NDOS/CCP (Apr 20, 2026)
- **2026-04-20**: Ported SNIOS from rcbios-in-c into cpnos-rom, dropped BIOS_BASE
  to 0xF200 to make room; SNDMSG/RCVMSG round-trip PASS.  **(Easy)** — SNIOS was
  already hardware-independent above the BIOS layer.
- **2026-04-20**: DRI .SPR page-relocator written in C — streams NDOS.SPR and
  CCP.SPR from the server, walks the bitmap, installs at chosen RAM addresses.
  **(Hard)** the 128-byte "ignored sector" at the head of the .SPR threw off
  the relocator until the alignment bug was caught.
- **2026-04-20**: CCP reaches PC inside NDOS entry — first sign the relocated
  modules are cross-calling correctly.
- **2026-04-20**: 8275 CRT + 8237 DMA bring-up in C; display refreshes from RAM.
  **(Medium)** — CRT parameter values were transcribed from rcbios-in-c, DMA
  autoinit-mode discovered experimentally.
- **2026-04-21**: Zero-page convention switched from null-trap to real WBOOT
  vector so NDOS's TLBIOS-walk patches the right BIOS JT.  **(Hard)** —
  debugging NDOS's opaque post-handoff behaviour required memory dumps at
  multiple instants to find where page 0 was getting scribbled.
- **2026-04-21**: SIO-B captured to `/tmp/cpnos_siob.raw`; ^C warm-boot via
  SIO-B injection works.
- **2026-04-21**: Server gains full CP/NET BDOS surface: OPEN/READ/WRITE,
  SEARCH FIRST/NEXT, MAKE, DELETE, RENAME, GET VERSION, plus R/O and SYS
  attribute handling.  `$$.SUB` automation lets MAME execute scripted
  CCP command sequences for regression tests.

## Phase 12: DRI CP/NOS monolith build (Apr 21, 2026)
- **2026-04-21**: `cpnos-build/` — a separate subdir that runs DRI's original
  RMAC+LINK under VirtualCpm (Java) to assemble and link `cpnos.asm` +
  `cpndos.asm` + `cpnios.asm` + `cpbdos.asm` + `cpbios.asm` into one
  flat `cpnos.com` image.  **(Medium)** — most friction was in VirtualCpm
  invocation, not the 8080 sources themselves.
- **2026-04-21**: Link addresses relocked to `CODE=0xD000 / DATA=0xCC00`
  so CP/NOS doesn't collide with our resident BIOS + display RAM above.
- **2026-04-21**: `dri_split.py` + `dri2gnu.pl` bridge — one-instruction-per
  -line reformatted DRI sources, then mechanical translation into GNU-as
  Z80 syntax.  Enables double-assembly for byte-verification of CCP.SPR.
- **2026-04-21**: First full boot: `cpnos.com` streams from server, NDOS
  routes BDOS through SNIOS, CCP reaches `A>`.  **This was the first
  end-to-end PASS.**

## Phase 13: MP/M II retarget (Apr 22, 2026)
- **2026-04-22**: Decision: replace the Python proxy server with a live
  MP/M II running on the host under z80pack cpmsim.  Goal: prove the
  stack works against a stock unmodified master.  Motivation: the Python
  server risked drifting into a bespoke protocol the DRI slave wouldn't
  accept on real MP/M.  **(Hard)** the decision itself — and documenting
  which MP/M version + disk images to use.
- **2026-04-22**: `netboot_mpm.c` replaces the legacy FMT=0xB0 custom
  protocol with standard CP/NET 1.2 LOGIN (fn 64) + OPEN (fn 15) +
  READ-SEQ (fn 20) + CLOSE (fn 16) against a virtual A:CPNOS.IMG.
  **(Medium)** — the DRI functions were documented but MP/M's exact
  response framing needed trial-and-error.
- **2026-04-22**: `netboot_server.py` rewritten to implement the same
  CP/NET 1.2 surface, so the slave can be tested without cpmsim running
  — the two servers are now wire-compatible.
- **2026-04-22**: SLAVEID normalized to 0x01 end-to-end (was 0x70 from
  historical RC-in-house choice).  `Makefile: $(OBJS): Makefile` dep
  added after a stale `cfgtbl.o` sent 0x70 on the wire despite flag
  change — **(painful)** lesson in build-graph hygiene.
- **2026-04-22**: BIOS_BASE moved 0xF200 → 0xED00 (RESIDENT grows 1.5 KB
  → 2.75 KB).  Three follow-up bugs fell out: IVT at 0xF100 got copied
  over by the resident memcpy (fixed by moving IVT to 0xEC00, issue #35
  added a linker ASSERT); SNIOS JT constant in cpnios.s stale; impl_wboot/
  impl_boot traps re-pointed at 0xD000 (issue U).  **(Hard)** — each bug
  was silent at build time and only showed up as a mid-boot lockup.

## Phase 47: cpnos-rom data-driven relocator (header-prefixed payload) (May 6-7, 2026) — branch `session47-cpnos-header-driven-relocator` in rc700-gensmedet/cpnos-rom

- **Goal**: stop the four-way coupling (C decl + linker script + Makefile
  awk + Makefile defsym) that wires payload metadata into the relocator,
  before adding any more BSS regions or page-aligned reservations.
  Replace it with a payload header the relocator reads at boot.

- **Reached** (clang side, plan steps 1-5 of 8):
  - `payload_header.h` defines the on-PROM struct (magic + chunk
    srcs/sizes + cold_entry + checksum_magic + variable-length BSS-pair
    list, sentinel-terminated).
  - `tasks/scripts/gen_payload_header.py` reads payload.elf symbols
    (clang) or cpnos_payload.map (SDCC) and emits payload_header_data.s.
  - `relocator.c` rewritten to read `_payload_header` and act on its
    fields — no externs, no compile-time constants except the magic.
    Preserves the LDIR → BSS → checksum → JP ordering invariant (user-
    restated 2026-05-07).
  - `relocator.ld` places `.payload_header` right after relocator code;
    emits `__chunk_a_start`/`__chunk_b_start` symbols at chunk physical
    PROM offsets (linker-decided, no hardcoded 0x0400).
  - `payload.ld` `INIT origin: 0x0100 → 0x0200` to give the data-driven
    relocator a 512 B code budget.
  - `Makefile` `PROM0_TAIL_SIZE: 1024 → 768` (chunk B grows from 708 to
    964; total payload size unchanged).
  - **6 of 7 cross-stage `--defsym` lines deleted** from the relocator-
    link rule; only `__stack_top` remains (consumed by reset.s before
    the relocator runs).
  - Compiler stamped in the boot banner via `CPNOS_COMPILER_NAME` macro
    in `compiler/compat.h` — selects `clang`/`sdcc`/`hitech`/`host`
    from predefined compiler macros at preprocess time.

  Verification: `make cpnos-polypascal-test` PASS end-to-end (PPAS
  PRIMES → 29989 → E>) at every step that touched the relocator
  pipeline.  `_payload_header @ 0x185` in the relocator binary, 30 B
  contents.  **(Medium)** — required two iterations on the .init VMA
  shift (relocator code grew from 110 B to 393 B), one on the indirect-
  call lowering (used `__call_iy` which we don't have; replaced with
  inline asm).

- **Side fix** (this session): `_pio_rx_buf_page` derived from
  `HIGH(_pio_rx_buf)` in BOTH pipelines instead of being a hardcoded
  literal that disagreed with the actual buffer placement.  SDCC: new
  `bss_pio_rx` SECTION at 0xEC00 (page-aligned, 256 B); buffer at
  0xEC00, page constant = 0xEC.  Clang: page-alignment ASSERT in
  `payload.ld` plus shift-and-mask in the symbol expression.

- **Side fix** (this session): clang build hygiene — `relocator.c`
  was missing `<stddef.h>`; `payload.ld` was missing
  `__pio_rx_bss_start/end` symbols; Makefile was missing 4 `--defsym`
  lines (now all dropped along with the rest in plan #19 step 5).
  Without these, the inherited "BSS-clearing relocator" change from a
  prior session wouldn't link.

- **Documented** (this session):
  - `cpnos-rom/tasks/memory-layout-investigation-2026-05-06.md` — full
    survey of both pipelines' MEMORY-region / SECTION / `defc` /
    ASSERT vocabularies, catalog of pinned-vs-movable items,
    recommendation for fully linker-driven layout.
  - `tasks/session47-cpnos-header-driven-relocator.md` — this session's
    delivery + open issues + risks.
  - 4 new memory rules (`feedback_memory_layout_on_port.md`,
    `feedback_extract_rules_from_time_sinks.md` (meta — write rules
    from time-sinks proactively), `feedback_relink_dependencies_atomically.md`,
    `feedback_kill_stale_servers_on_test_target.md`).

- **Reached** (afternoon/evening continuation 2026-05-07, steps 6-8):
  - **Step 6** (commit `d2485c8`): `relocator.c` compiles under SDCC and
    replaces `prom_loader.asm` at link time.  SDCC slave boots through
    the unified C relocator (banner `RC702 CP/NOS 55K SIO sdcc ...` on
    display, slave reaches netboot wait loop).  Two side-fixes folded
    in: SDCC `reset.asm` SP changed 0xF700 → 0xEC00 (library calls
    during the relocator must not push into resident bytes the
    checksum is about to read), and a `__naked` `relocator_zero` helper
    inlines LDIR-from-self to side-step a z88dk-zsdcc 4.5.0 calling-
    convention mismatch where `--sdcccall=1` codegen for `memset(d,0,n)`
    doesn't match `_memset`'s sdcccall=0 stack-arg preamble (filed
    upstream-bug task #26).
  - **Step 7 clang side** (commit `0e8fc58`): `--include-ivt` added to
    `gen_payload_header.py` invocation; `(__ivt_start, __ivt_end)`
    lands in the header's bss_pairs list and the relocator zeroes the
    IVT region during the BSS-clear pass before checksum verification.
  - **Step 8** (commit `302ce24`): `sdcc/prom_loader.asm` physically
    deleted; `check_sdcc_layout.py` extended with payload-header sanity
    check (verifies magic 0x6350, version 0x0001, sentinel pair within
    64 B after header).  Both fail paths verified by manual tampering.
  - **Persistent SDCC IX+/IY+ frame-pointer regression gate**
    (commit `55d68c2`): `tasks/scripts/check_no_frame_ptr.py` scans
    per-source `.s` files for `(ix±d)` / `(iy±d)` operands, identifies
    the violating function, and fails the build if any new (file,
    function) appears or a baselined function's count grows.  Two
    known violators captured (`relocator.c::relocate` 10 hits,
    `resident.c::delete_line` 2 hits — tasks #27/#28).
  - **`--opt-code-size` investigation + revert** (commit `8429b8d`):
    User flagged that SDCC was at default speed-tuned codegen.
    Lifting `--opt-code-size` to zcc level (matching
    `rcbios-in-c/sdcc/Makefile`'s established pattern, captured as
    HARD memory rule `feedback_check_sibling_subprojects.md`) flips
    z88dk's peephole file from `sdcc_peeph.3` to `sdcc_peeph_cs.3`
    and saves ~17 B across the resident.  But `--opt-code-size` also
    factors out an 11 B `___sdcc_enter_ix` shared helper — amortises
    only with many IX-frame functions, and our build has just 2
    (the audit's known violators).  Net: +5 B resident, overflows
    display memory at 0xF800.  Reverted; documented in Makefile
    comment for the next attempt.

- **Memory-map gap analysis (2026-05-07 evening) — initial 0xFFD0
  IVT plan was WRONG; corrected 2026-05-08**: display memory is
  0xF800..0xFFCF (2000 chars, 80×25); bytes 0xFFD0..0xFFFF are 48 B
  of scratch RAM (CRT frame counter at 0xFFFC..0xFFFF + 44 B free).
  Initial plan was to host the IVT there with `I = 0xFF` -- **this
  is unsafe**: under Z80 IM 2 the I register fixes a 256 B page and
  the CPU reads its ISR pointer from anywhere in that page based on
  the device-supplied vector low byte; with I = 0xFF the page is
  0xFF00..0xFFFF, of which 0xFF00..0xFFCF IS on-screen character
  RAM.  Any spurious or misprogrammed vector with low byte < 0xD0
  jumps to a pointer composed of screen bytes.  All pages I=0xF8..
  0xFF are similarly forbidden.  Valid IVT pages are pages whose
  entire 256 B range is owned by the slave AND not display: the
  actual fix landed in Phase 47b (Path 6) by placing the SDCC IVT
  inside a page-aligned `bss_ivt` SECTION in scratch BSS at 0xEA00
  (I = 0xEA), zero resident cost.  The 44 B at 0xFFD0..0xFFFB stays
  scratch RAM (frame counter, future use), NOT IVT.  Tracked as
  **#29**; SDCC side closed by Path 6, clang side still uses
  `__ivt_start = 0xF500` in resident (could mirror SDCC for symmetry
  to free 36 B of clang resident).

- **Two more memory rules captured (session 47 evening)**:
  `feedback_no_stale_dump_files.md` (`rm -f /tmp/foo` BEFORE every
  producer-command iteration); `feedback_no_dotall_backtracking.md`
  (don't combine Python `re.DOTALL` with non-greedy `.*?` over
  multi-line source — catastrophic backtracking).

- **Plan #19 status**: 7 of 8 structural steps fully done (1-6, 8);
  step 7 done on clang side; SDCC side closed by Phase 47b Path 6
  (IVT placed in `bss_ivt` page-aligned section at 0xEA00).  No more
  architectural unknowns.

- **Pending** (separate from plan #19):
  - **#29** clang-side mirror: move `__ivt_start` from 0xF500 in
    resident to a BSS-scratch page (matches SDCC) to free 36 B of
    clang resident.  Optional symmetry fix; no functional blocker.
  - **#27/#28** drive IX-spill audit baseline toward zero.
  - **#26** file the SDCC `--sdcccall=1`/`_memset` mismatch upstream.
  - **#21** runtime version check at boot (low priority).
  - **#13** hunt remaining JP-0 sources in SDCC build (gated on #29).

## Phase 47c: clang IVT mirror + #29 plan correction (May 8, 2026 evening) — branch `session47-analysis-2026-05-08` in z80, `main` in rc700-gensmedet

- **Goal**: extend Phase 47b's structural IVT cleanup to the clang
  side and fix a wrong-headed plan that had crept into CLAUDE.md /
  timeline.md / a draft #29 doc -- "place IVT at 0xFFD0 with I=0xFF".

- **Catch**: under Z80 IM 2 the I register fixes a 256 B page; the
  CPU reads its ISR pointer from anywhere in that page determined by
  the device-supplied vector low byte.  With I=0xFF the page is
  0xFF00..0xFFFF, of which **0xFF00..0xFFCF IS on-screen character
  RAM** (display memory occupies 0xF800..0xFFCF on RC702).  Any
  spurious or misprogrammed vector with low byte < 0xD0 would jump
  to a pointer composed of screen bytes.  All pages I=0xF8..0xFF are
  similarly forbidden.  The 48 B at 0xFFD0..0xFFFF is fine as scratch
  RAM (frame counter at 0xFFFC..0xFFFF + 44 B free) but unsuitable
  as an IM 2 IVT page.  Captured as new HARD-RULE memory entry
  `project_rc702_ivt_page_constraint.md`.

- **Reached**:
  - `cpnos-rom/payload.ld` — IVT relocated from literal `__ivt_start
    = 0xF500;` (above resident, costing 36 B of resident-adjacent
    BSS slack) to a `.ivt (NOLOAD)` SECTION pinned at **0xEA00** in
    a new IVT MEMORY region.  Same page as SDCC's `bss_ivt`
    (sdcc/sections.asm:156); cross-compiler structural parity
    achieved.  The 0xEA00 page is in the 768 B gap between
    cpnos.com's tail (0xE9FF; cpnos.com is 3200 B at NDOS=0xDD80)
    and the resident region (0xED00).  No literal IVT address
    remains; `init.c::setup_ivt` derives `IVT_ADDR` from the linker
    symbol and `set_i_reg(IVT_ADDR >> 8)` produces I=0xEA.  ASSERTs
    updated: new `__cpnos_load_end <= 0xEA00` enforces clang's
    cpnos.com-vs-IVT clearance (Makefile:391 already enforced this
    for SDCC at 0xEA00; now applies symmetrically).  Net: payload
    1733 B → 1732 B; `__scratch_bss_start` 0xF524 → 0xF500 (36 B
    BSS recovered).  All 11 link-time ASSERTs pass.

  - **Functional verification** via custom Lua probe of CRT frame
    counter at 0xFFFC..0xFFFF: counter incremented 0x000000 → 0x18A
    across 8 emu seconds (~50 Hz, exactly the VRTC rate); MAME CPU
    state shows `I = 0xEA` live; PC sits in slave main loop
    (0xF305..0xF315) servicing IRQs.  This is the value-oracle the
    "no commit on lit+size alone" rule asks for: not just that
    things link clean and pass ASSERTs, but that IM 2 IRQ delivery
    actually works through the new IVT page.

  - **Doc corrections**: top-level `CLAUDE.md` item (12), this
    timeline's Phase 47 entry (lines 269-291), and a new
    `cpnos-rom/tasks/issue-29-ivt-relocation-plan.md` capturing
    actual fix vs. wrong initial plan.  Sweep of project for stale
    "0xFFD0 IVT" / "I=0xFF" references: clean (remaining 0xFFD0
    references are all legitimate -- rcbios WorkArea at 0xFFD0,
    lessons.md ORG context, status-line-26 display-row mention).

- **Tasks filed** (`tasks/todo.md` Parked):
  - `cpnos-warmboot-test` is the wrong harness for `TRANSPORT=
    pio-irq` builds (wires SIO-A but slave talks PIO-B; appeared as
    a hang during this session's verification, but baseline showed
    same symptom -- harness mismatch, not regression).
  - `mame_boot_test.lua` finish() never fires under canonical 8 s
    `cpnos-mame` -- emulation runs out before the lua's 60 s
    frame-timeout, leaving the result file empty.

- **Lessons (extracted as new memory rule via the
  feedback_extract_rules_from_time_sinks meta-rule)**:
  - `project_rc702_ivt_page_constraint.md` -- IM 2 IVT page (I*256)
    cannot overlap RC702 display memory at 0xF800..0xFFCF; pages
    I=0xF8..0xFF are forbidden.  The 0xFFD0 scratch tail looks like
    free RAM but cannot host an IVT.

  - "If you need more space, lower TPA more" (user, this session)
    is the right framing for cross-compiler resident pressure: the
    resident-vs-TPA boundary is the binding constraint, not the
    intra-resident layout.  Path 6 (Phase 47b) demonstrated this
    on SDCC; the clang IVT mirror this session validates the same
    boundary works for clang.

  - Wrong-test-harness symptom looks identical to genuine boot
    regression (banner prints, no E>).  Verify by stashing
    candidate changes and re-running -- if baseline shows the same
    symptom, the harness is wrong, not the change.  This caught
    me wasting time on `cpnos-warmboot-test` before remembering
    that pio-irq builds need `pio-irq-netboot` (memory rule
    `project_pio_irq_test_topology.md`).

## Phase 47b: Path 6 TPA shrink + SDCC slave reaches CCP (May 8, 2026) — branch `session47-cpnos-header-driven-relocator` then `session47-analysis-2026-05-08`

- **Goal**: get the SDCC `cpnos-polypascal-test` past the post-NDOS-
  handoff hang.  Slave reached netboot completion (25 sectors received,
  cpnos.com stamp printed) but never produced an `E>` prompt under
  TRANSPORT=pio-irq; clang at the same checkpoint reaches `E>` cleanly.

- **Reached**:
  - **Comparison disassembly** (`cpnos-rom/tasks/compare-clang-vs-sdcc-handoff-2026-05-08.md`):
    side-by-side analysis of resident_handoff / enter_coldst / BIOS jt /
    cfgtbl placement.  Found three candidate divergences (port-bus shape,
    IVT-at-0xEB00 stack collision, cfgtbl in BSS vs RESIDENT_DATA);
    documented two as benign, one as latent class-of-risk fix.
  - **commit `d9bbc8b`** "sdcc: __port_out mirrors port high byte;
    IVT-clobber build assert" — closes the bus-shape divergence
    (deterministic `B = port_high` before `OUT (C),A` matching clang's
    `D3 nn`); adds Makefile assert that cpnos.com size + NDOS load
    address fits below the IVT page.  Side fix: MSGADR/RETCNT moved
    from RESIDENT_DATA to bss_compiler so they don't burn 3 zero PROM
    bytes (write-before-read at every entry point makes the move safe).
  - **commit `8573a09`** "Path 6: shrink TPA 256 B to grow resident
    from 2560 to 2816 B" — the actual fix.  cpnos-build CODE_BASE
    LDE80 → LDD80 (cpnos.com 0xDE80 → 0xDD80), DATA_BASE LDA80 →
    LD980, NIOS in cpnios-shim.asm 0xEE33 → 0xED33.  cpnos-rom
    resident lower bound 0xEE00 → 0xED00 (PROM1 chunk-B cap raised
    1536 → 1792 B).  SDCC SCRATCH_BSS slid 0xEB00 → 0xEA00.
    `sdcc/reset.asm` SP moved to 0xDD80 (clear of resident, BSS-clear,
    netboot LDIR, AND IVT).  Side fix: Makefile cpnos.bin recipe pads
    the resident image to even bytes with 0xFF if z88dk produced odd
    (checksum patcher needs even input).
  - **Workspace bump `a9c9175`** (in `/Users/ravn/z80`):
    rc700-gensmedet pointer `b75b7ae` → `8573a09`, recording 19
    commits at workspace level (Phase 47 step 7 SDCC + Path 6 cluster
    + build-speed cluster + SDCC polypascal harness).

  Verification: `make cpnos-polypascal-test COMPILER=clang` PASS
  end-to-end.  `make cpnos-polypascal-test COMPILER=sdcc TRANSPORT=
  pio-irq` reaches CCP (was hanging at NDOS handoff before Path 6),
  but FAILs stage 1 because CCP receives 0x10 (Ctrl-P) bytes from
  CONIN repeatedly and prints "Ctl-P OFF" instead of `E>`.

- **Open** (analysis branch `session47-analysis-2026-05-08`):
  - **Ctrl-P flood from CONIN under SDCC pio-irq** — three suspects:
    MAME null_modem TX→RX loopback, PIO-A spurious IRQ, SIO-B FIFO
    power-on state.  Naive fix attempts (drain SIO-B FIFO at init,
    SP relocation, B=H mirror) did NOT close it.  See
    `cpnos-rom/tasks/session47-analysis-2026-05-08.md` for the full
    suspect ranking and rejected-fix log.
  - **polypascal-test driver hardcodes `clang/...` addrs lua path** —
    doesn't honour `COMPILER=sdcc`; would mis-inject keys into
    SDCC-build BSS at clang's addresses.  Not a stage-1 issue (no
    inject needed for the boot prompt) but blocks stage 2+.
  - **Makefile odd-resident-pad shell hack** — should be a z88dk
    align directive (or a relocator-side accept-odd fix).
  - **reset.asm SP moved through 4 different layouts in 2 sessions** —
    convert to `defc __stack_top = ...` derived from symbols, not a
    literal in a comment.

  Lessons:
  - "Same problem, three candidate fixes, none close it" → step back
    and instrument before proposing fix #4.
  - Resident at the byte-cap blocks debug instrumentation as a class.
    The 256 B Path 6 grow buys headroom; future SDCC work should
    target keeping ≥64 B free for probes.
  - Plan-mode-then-execute workflow caught a stale plan (the existing
    `harmonic-sleeping-spring.md` was plan #19 done; rewrote it for
    the workspace bump task).

## Phase 46: cpnos-rom SDCC port reaches NDOS handoff (May 6, 2026 evening) — branch `main` in rc700-gensmedet

- **Goal**: continue the SDCC dual-compile port (Phase 45) past the
  Makefile dispatch into actual link + runtime, push it as far as
  `cpnos-polypascal-test` passes.

- **Reached**: SDCC build boots cleanly, netboots cpnos.com (25 of
  25 sectors), disables PROM, hands control to NDOS COLDST.  Boot
  marks `I PNILOREC+P J` confirm every cold-init phase.  NDOS coldst
  runs (NTWKIN, tlbios, CNFTBL all return correctly), nwboot starts
  CCP.SPR load via `call load`.  **(Medium-Hard)** — required eight
  bring-up bug fixes catalogued in `cpnos-rom/tasks/sdcc-port.md`
  "Bugs fixed this session".

- **Two `JP 0` cascades found and squashed**:
  (a) **NIOS placement** — `cpnos-build/src/cpnios-shim.asm` hardcodes
  `NIOS = 0xEE33`.  Initial SDCC layout had BIOS jt at 0xF200 → SNIOS
  jt at 0xF233, so NDOS's `call nios+0` jumped into uninitialised
  resident bytes.  Fixed by relocating `RESIDENT_JUMPTABLE` to
  `org 0xEE00` so SNIOS jt naturally lands at 0xEE33.  **(Easy once
  spotted)** — symptom was 22-of-25 dot stall; root cause needed
  symbol-table inspection.
  (b) **`_bios_stub_ret` mis-placement** — SDCC link of
  `void f(void){}` placed it in z88dk's `code_l_sccz80` runtime
  section at 0xEDF4, OUTSIDE the prom_loader's LDIR target range
  (0xEE00..0xF7FF).  Every NDOS call to an unimplemented BIOS entry
  (LIST/PUNCH/SELDSK/READ/...) jumped into uninit RAM → garbage
  execution → eventual JP 0 → ZP[0]=0xC3 → JP WBOOT → impl_wboot →
  re-COLDST.  Classic warm-boot loop, exactly the user's "JP 0"
  hypothesis.  Fixed by defining the symbol directly in
  `sdcc/bios_jt.asm SECTION RESIDENT_CODE` (NOT in
  RESIDENT_JUMPTABLE — would shift SNIOS jt off 0xEE33).
  **(Painful)** — required gdbstub probing of stack contents at
  hang to spot the 0x00 0x00 return addresses; symptom was
  silent post-handoff hang.

- **`cpnos-build` Path 4 — CODE_BASE shift**: cpnos.com originally
  loaded 0xE180..0xEE00 (3200 B); SDCC's larger BSS at 0xEC00
  collided with cpnos.com sectors 22+, killing
  `_cfgtbl.netst.ACTIVE` mid-netboot.  Shifted `CODE_BASE` LE180
  → LDF80, `DATA_BASE` DDD80 → DDB80 — cpnos.com now ends at
  0xEC00, leaves 0xEC00..0xEDFF for slave BSS.  TPA 56→55 KB.
  Both compilers re-tested at new address; clang reaches `E>`
  prompt cleanly.  Long-term fix tracked as relocatable cpnos.SPR
  refactor (`cpnos-rom/cpnos-build/RELOCATABLE_SPR.md` option a,
  task #11).  **(Medium)** — requires rebuilding cpnos.com (DRI
  RMAC+LINK via VirtualCpm), regenerating `cpnos_addrs.h`,
  re-testing both compiler builds.

- **Phase 2D `zp_init_data`**: `cpnos_main.c::resident_handoff`'s
  LDIR was `#ifdef __clang__`-gated with a no-op `else`; ZP[0..7]
  was never written under SDCC, so NDOS's WBOOT calls jumped via
  uninit ZP.  Replaced with `ASM_VOLATILE("ld hl,_zp_init_data;
  ld de,0; ld bc,8; ldir")`.  **(Easy)** — straightforward port;
  `resident.c::insert_line` LDDR still TODO (task #17).

- **Diagnostic infrastructure landed**: MAME's gdbstub (`-debugger
  gdbstub -debugger_port 23946`) confirmed working without a debug
  build; Python probe at `/tmp/gdb_probe.py` reads memory + dumps
  registers/stack at break.  Bitbanger TCP proxy at
  `/tmp/cpnet_proxy.py` logs every byte slave↔master with timestamps.
  Both used heavily this session to localise the JP-0 sources.
  **(Useful for future debugging)** — tools should be promoted out
  of /tmp.

- **Open**: SDCC build still hangs post-handoff with stack
  corruption — more JP-0 paths suspected (task #13).  Polypascal
  test cannot run for either compiler until MAME_IRQ branch built
  (task #15) and test harness adapted for SDCC's symbol extraction
  (task #16).  Resident.c insert_line LDDR still gated (task #17).

- **Phase 2F — link-time audit landed (closes task #14)**: hard
  build gate `tasks/scripts/check_sdcc_layout.py` added to the
  SDCC `cpnos.cim` recipe.  Parses `cpnos.map`, walks every `addr`
  symbol and every `__SECTION_head/size/tail`, fails the build
  if a `code_*`/`rodata_*`/`data_*` symbol resolves outside
  0xEE00..0xF7FF, a `bss_*` symbol resolves outside 0xEC00..0xEDFF,
  or any two non-zero-size sections overlap.  On its first run it
  caught a NEW outside-resident symbol — `_memset @ 0xEDF1` (with
  `code_string` overlapping RESIDENT_JUMPTABLE at 0xEE00..0xEE0D),
  meaning every `__builtin_memset` in resident.c (`clear_screen`,
  `scroll_up`, `erase_to_eol/eos`, `insert/delete_line`) was a
  dormant JP-0 source independent of #8 above.  Fix in `sections.asm`:
  pin every z88dk runtime section explicitly inside its proper chain
  (`code_clib` / `code_string` / `code_l_sccz80` / `code_home` /
  `code_crt_init` / `code_compiler` at end of resident chain;
  `rodata_*` / `data_*` aliases right after RESIDENT_RODATA;
  `bss_clib` / `bss_string` after `bss_compiler`).  Audit re-runs on
  every SDCC build and is a permanent build failure on regression.
  Generalises bug #8's manual fix into a class of bugs caught
  automatically.  **(Medium)** — root cause was systemic, the fix
  is too.

- **Lessons** (in `cpnos-rom/tasks/sdcc-port.md`): (1) SDCC drops
  block-scope `extern` decls from asm output silently; declare
  cross-file at file scope.  (2) z88dk's link places runtime-lib
  sections in gaps; small `void f(void){}` functions can land
  OUTSIDE the user-controlled resident region — define stubs in
  asm or annotate placement explicitly.  (3) Build-time stack-
  mismatch / out-of-region symbol detection would catch (2)
  earlier (task #14).  (4) cpnos.com address shifts cascade
  through `cpnos_addrs.h` regeneration; rebuild both compiler
  outputs after every shift.

## Phase 45: cpnos-rom dual+triple compile port — Phase 1 + 2A (May 5-6, 2026) — branch `main` in rc700-gensmedet

- **Goal**: make `cpnos-rom` build under SDCC (z88dk-zsdcc) in
  addition to clang Z80, with both builds coexisting (deploy time
  picks one).  Scaffold for a third compiler (HiTech zc, ravn/hitech)
  in the same pass.

- **User-stated principles** (recorded as feedback memories):
  - "clarity in the c code is very important" — drives every
    compiler-dispatch decision: identical call shape across
    backends, all `#ifdef` confined to `compiler/compat.h`, no
    `#ifdef __SDCC` in business logic.
  - "z88dk has intrinsic definitions for many z80 specific code" —
    SDCC builds pull z88dk's `<intrinsic.h>` (e.g. `intrinsic_di`,
    `intrinsic_ei`, `intrinsic_im_2`); clang Z80 has matching
    `static inline` wrappers; same call shape.

- **Phase 1 — source-level dual-compile (DONE)**:
  - `hal.h` rewritten with 3-backend dispatch (`__clang__ + __z80__`,
    `__SDCC || __SCCZ80`, `__HITECH__`/`HI_TECH_C`, host fallback).
    `_port_in(p)` / `_port_out(p, v)` keep the same call shape in
    every backend.  Clang Z80 inlines via `address_space(2)`; SDCC
    declares an extern (Phase 2D will provide the asm body in
    `runtime.asm`); HiTech `#error "not yet implemented"`.
  - New `compiler/compat.h` is the keyword/macro shim: `ASM_VOLATILE`,
    `__naked` / `__sdcccall(x)` / `__interrupt(n)` / `__critical` /
    `__preserves_regs`, `STATIC_ASSERT`, `NORETURN`, `USED`,
    `NOINLINE`, `SECTION_*` (one macro per `.payload_checksum` /
    `.bss.cfgtbl` / `.init.text` / `.init.rodata` / `.resident*` /
    `.prom0_*` / `.prom1` / `.pio_rx_bss`), `CPNOS_STR(x)`
    preprocessor stringify (replaces clang's `%0` operand syntax in
    `enter_coldst` -> `jp <CPNOS_NDOSE_ADDR>`), and a uniform
    `intrinsic_di / _ei / _halt / _nop / _im_2 / _ld_i_a` API.
    Header renamed from `compiler/intrinsic.h` to `compiler/compat.h`
    so the SDCC `#include <intrinsic.h>` reaches z88dk's system
    header rather than recursing.
  - `tasks/scripts/bin2inc.py` is the `#embed` workaround.
    SDCC has no `#embed` (not in `--std-sdcc23`).  A 25-LOC Python
    script reads `<name>.bin` and emits `<name>.inc` (comma-separated
    bytes) which both compilers `#include` inside an array
    initializer.  C source identical between compilers.  Was offered
    a 1.5-3-day SDCC patch; user chose the workaround.
  - `relocator.c` / `cfgtbl.c` / `init.c` / `netboot_mpm.c` /
    `payload_checksum.c` / `isr.c` / `resident.c` / `transport_pio.c`
    / `transport_sio.c` / `cpnos_main.c` all rewritten to use
    `compiler/compat.h` vocabulary.  Numeric local labels
    (`8:`/`jr nz, 8f`) replaced with globally-unique labels
    (`_isr_crt_count_done`).  Naked-keyword positioned after
    declarator (`void f(void) __naked`) for cross-compiler parity.
    All 10 .c files compile clean under both clang Z80 and SDCC `-S`.
  - Clang Z80 build remains byte-stable through the entire port:
    payload **1738 B**, PROM0 **1778 non-padding B** — same as
    before the port started.

- **Phase 2A — Makefile dispatch (DONE)**:
  - `make cpnos COMPILER=clang|sdcc|hitech` selects the build path.
  - `BUILDDIR = $(COMPILER)` parameterizes 96 hardcoded `clang/`
    paths.  Clang path byte-stable; SDCC path reaches the assembler
    and stops at the first `.s` file (Phase 2C); HiTech path
    `$(error not yet implemented)`.
  - Per-compiler tool/flag block: clang uses ld.lld + llvm-objcopy;
    SDCC uses `+z80 -compiler=sdcc -clib=sdcc_iy --no-crt
    -Cs"--std-sdcc23" -Cs"--sdcccall 1"`; native zcc preferred,
    Docker (`z88dk:2.4`) fallback retained.

- **Phase 2 remaining (NOT DONE)**:
  - **2B linker layout**: `cpnos_rom.ld` (4 memory regions
    PROM0/PROM1/RESIDENT/SCRATCH, 6 ASSERTs) → z88dk
    `sdcc/sections.asm` + `appmake +rom`.  rcbios pattern
    (`rcbios-in-c/sdcc/z88dk_section_layout.asm`) is the reference;
    cpnos has 4 regions vs rcbios's 2 so it's harder.
  - **2C asm files**: parallel `.asm` files per SDCC for `reset.s`,
    `runtime.s`, `bios_jt.s`, `snios.s`.  Direct semantic translation;
    different syntax.
  - **2D LDDR/LDIR helpers**: replace the two
    `#if defined(__clang__) && defined(__z80__)` gates around inline
    asm (`resident.c::insert_line`, `cpnos_main.c::resident_handoff`)
    with calls to a shared `mem_copy_forward` / `mem_copy_backwards`
    helper hosted in per-compiler runtime.{s,asm}.  Tried
    `__builtin_memmove` first — it inflates the clang Z80 payload
    past the budget (causes `IVT overlaps .payload` link error);
    reverted.
  - **2E validation**: run `cpnos-polypascal-test` against the SDCC
    build; confirm functional parity with clang.

- **Realistic remaining**: 8-14 hours focused work to a SDCC PROM
  that boots through cpnos-polypascal-test.

- **Lessons (session 45)**:
  - **Header naming clash bites silently**.  My initial
    `compiler/intrinsic.h` name caused `#include <intrinsic.h>`
    inside that file to recurse into itself instead of finding
    z88dk's system intrinsic.h.  Renamed to `compiler/compat.h`.
    Lesson: when bridging to a system header by the same canonical
    name, do not reuse the name — even with header guards, the
    include just becomes a no-op.
  - **`__builtin_memmove` is not a free portability fallback on
    Z80**.  Looks like the right choice for "let the compiler emit
    LDIR/LDDR per direction"; in practice clang's memmove dispatch
    grew the payload by enough bytes to break the section layout.
    Always measure size cost before swapping inline asm.
  - **Parallel Edit-tool batches can drop file content silently**.
    Mid-session, 7 sequential Edits on `cpnos_main.c` issued in one
    tool batch came back with "file modified since read" errors but
    left the file at 0 bytes.  `git checkout HEAD -- cpnos_main.c`
    restored it.  Lesson for future sessions: do edits one at a time
    on the same file; verify with `wc -l` after batches.

- **Files committed in this phase** (planned, not yet done):
  - `cpnos-rom/hal.h` (3-backend dispatch)
  - `cpnos-rom/compiler/compat.h` (new shared shim)
  - `cpnos-rom/tasks/scripts/bin2inc.py` (new `#embed` workaround)
  - `cpnos-rom/Makefile` (COMPILER dispatch + 96-path parameterize)
  - 10 .c files updated to compat.h vocabulary
  - `cpnos-rom/tasks/sdcc-port.md` (scope/progress doc)
  - `compiler/MEMORY` updates (added `feedback_clarity_in_c_code.md`,
    updated `project_cpnos_clang_only.md` to reflect direction reversal)

## Phase 33: close ravn/llvm-z80#97 BC ping-pong (May 2, 2026) — branch `session-35-issue-97` in llvm-z80

- **Goal**: close #97 (BC ping-pong in rotated single-BB self-loops),
  the gate on #77a (Z80LoopRotate default-on), and measure whether
  flipping rotation default-on is now profitable.

- **Result** (final, end of session):
  - **#97** closed.  Post-RA peephole in `Z80LateOptimization.cpp`
    handles 3 pred shapes × 2 body orderings; covers param-pointer
    (`LD C,L; LD B,H`), constant-in-both (`LD HL,nn N; LD BC,nn N`),
    and constant-in-BC-only (`LD BC,nn N` rewritten to `LD HL,nn N`).
  - **#99 filed**: i16-counter sub-case of #97 (counter and pointer
    compete for HL).  XFAIL test pinned; deferred — needs regalloc-
    level swap.
  - **#100 filed**: rotation-around-CALL BSS-spill regression.
    `Z80LoopRotate` stays default off despite #97 closing.
    Measurement on 2026-05-02 with rotation forced on showed rcbios
    +33 B, cpnos-rom +4 B (e.g. `_netboot_mpm` inner banner loop
    +28 B alone).  Tracked at `tasks/followup-77a-rotation-around-
    call.md` in llvm-z80; closes #77a once a fix lands (peephole
    rewriting the spill-around-CALL shape, or a regalloc cost-model
    tweak).
  - **rcbios BIOS**: 5920 B unchanged from session 33 baseline.
  - **cpnos-rom payload**: 1708 B unchanged from session 33
    baseline.  PROM0 init code -1 B (the peephole still fires on
    Case 1 hand-written shapes even with rotation off).
  - **Z80 lit suite**: 76 PASS + 1 XFAIL → **77 PASS + 1 XFAIL**.

- **Pain points caught** (all in llvm-z80):
  - LD_HL_nn operand layout: passing `RegState::Define` plus a
    second `addReg(HL)` produced the literal `ld hl,hl` — operand 0
    is the immediate / global / MC-symbol; the def is implicit.
    **(Easy)**.
  - Symbol vs. immediate operand comparison: Case 2 matcher only
    checked `isImm()` and silently bailed on `__ivt_start`-style
    global / MC-symbol operands.  Required diffing cpnos-rom asm
    function-by-function to spot.  **(Medium)**.
  - Two body orderings (anchor-first vs. anchor-last in the loop
    block): visible only after flipping rotation default-on.
    Restructured matcher to walk three regions regardless of order.
    **(Medium)**.
  - Rotation-around-CALL spill regression: ~30 min chasing the
    +4 B mystery on cpnos-rom before realising it was a separate
    regalloc-spill-around-CALL shape, not a residual ping-pong.
    **(Medium)**.

- **Files touched**:
  - `llvm-z80/llvm/lib/Target/Z80/Z80LateOptimization.cpp` (new
    ~250-LOC peephole after the existing #84 peephole).
  - `llvm-z80/llvm/lib/Target/Z80/Z80LoopRotate.cpp` (default
    confirmed off; comment updated to document the new gate).
  - `llvm-z80/llvm/test/CodeGen/Z80/issue-97-bc-pingpong-singlebb.ll`
    (XFAIL dropped, i16 case extracted, header rewritten).
  - `llvm-z80/llvm/test/CodeGen/Z80/issue-97a-bc-pingpong-i16-counter.ll`
    (new XFAIL).
  - `llvm-z80/llvm/test/CodeGen/Z80/issue-77a-loop-rotate.ll`
    (header refreshed; RUN lines unchanged).
  - `llvm-z80/tasks/session35-summary.md` (new).
  - No source touched in `rc700-gensmedet`.

## Phase 32: llvm-z80 codegen-fix burst (May 1-2, 2026) — branch `z80-close-all-issues` in llvm-z80

- **Goal**: tighten cluster 2 (DJNZ + LDIR family) and adjacent
  pessimizations, flip the long-standing XFAIL test to PASS, and
  measure the BIOS / cpnos-rom size delta.

- **Result** (final, end of session):
  - **rcbios BIOS**: 5998 B → **5967 B** (-31 B, -0.52 %).  Smallest
    yet; 54 B below the 6021 B initial baseline.
  - **cpnos-rom payload**: 1738 B → **1730 B** (-8 B).
  - **Z80 lit suite**: 65/66 + 1 XFAIL → **73/73**, no XFAILs.
  - **GitHub issues**: 46 open at session start → **28** open at
    end (-18, including 5 newly filed, so 23 net closed).

- **Issues fixed this session (8 with code changes)**: #78, #88, #64,
  #91, #82, #76, #93, #86.  Each landed with reproducer + lit test
  + measured size delta.

- **Issues closed retrospectively (10)**: #65, #67, #68, #69, #71, #75,
  #79, #83, #84, #85, #87, #73, #80, #60, #90.  Earlier-session
  fixes that hadn't been closed on GitHub; verified each has a
  corresponding commit + lit test on the branch.

- **Issues filed (5)**: #91 (LDDR setup quality, fixed same session),
  #92 (nested-loop DJNZ direction reversed), #93 (constant-trip
  countdown emits count-up + carry-test; fixed same session via
  path b), #94 (sequential loops: B not re-hinted between loops),
  #95 (long-term path a -- prevent the IV rewrite at IR level).

- **Mechanism (per fix)**:
  - **#78 LDIR aftermath**: late peephole rewrites
    `LD HL,(slot); LD DE,N; ADD HL,DE; <sink>` to direct DE-reuse
    (LD H,D / LD L,E, or skip-EX, or store-DE-back), with ±1 INC/DEC
    fixup.  Order-independent matcher.  cpnos READ-SEQ inner loop
    -6 B/iter absorbed into payload alignment.
  - **#88 pattern-fill loop idiom**: new IR-level pass
    `Z80LoopIdiomFill` (both new-PM and legacy-PM entry points)
    rewrites K-byte (K∈{1,2,3,4}) constant-trip-count fill loops as
    `seed K bytes; memcpy(base+K, base, K*(N-1))`, which the backend
    lowers as `seed; LDIR`.  K=3 (jump-table / IVT shape) was
    explicitly requested.
  - **#64 memmove inline**: `G_MEMMOVE` `.libcall()` → `.custom()`
    in `Z80LegalizerInfo` with direction analysis (same pointer,
    G_PTR_ADD chains, common base).  Picks LDIR or LDDR; otherwise
    libcall.
  - **#91 LDDR setup quality**: when Size is constant, fold Size-1
    + chained G_PTR_ADDs at legalization so end-pointers collapse
    to single G_PTR_ADD(base, total).  Global-base case 22 B → 12 B.
  - **#82 BSS-spill peephole orphan-reload bug**: spill→PUSH/POP
    rewrite was missing a check for orphan loads to a different
    register pair.  Added the check; the long-standing XFAIL flips
    to PASS.
  - **#76 LD A,(HL); LD r,A → LD r,(HL)** (and symmetric store):
    direct-form is 1 B / 4 T cheaper than A-via.  Peephole rewrites
    both directions when A is dead after.  Hits CONOUT and FDC
    paths in BIOS.
  - **#93 carry-roundtrip elimination** (path b -- post-RA peephole):
    two composing peepholes — `SBC A,A; AND 1; XOR 1; RRCA; JR C`
    → `JR NC` and `LD A,r; ADD A,1; LD r,A; JR NC` → `INC r;
    JR NZ`.  11 B → 3 B per loop body for constant-trip-count
    countdowns.
  - **#86 u8 switch range-check 16→8 bit**: GISel switch lowering
    widens the discriminator to i16 BEFORE the bound check.  New
    peephole detects the 9-byte 16-bit subtract chain and rewrites
    as `CP_n; JR_C/NC` (3 B), with the carry condition flipped
    (the chain computes `limit-offset` while CP computes
    `offset-limit`).

- **Pain points caught**:
  - lit `CHECK-NOT djnz` matched the substring inside function names
    like `_call_in_body_no_djnz`.  Fixed by anchoring on whitespace.
    **(Easy)**, but caught only when writing the comprehensive DJNZ
    test.
  - cmake/ninja not on PATH on macOS; user has no brew.  Found
    CLion-bundled cmake/ninja under `/Applications/CLion.app`.
    Recorded path in user memory `reference_build_binaries.md`.
    **(Medium)** — 15 min lost.
  - SCEV's `getBackedgeTakenCount` semantics: returns body iteration
    count (= trip count), NOT trips-1, for the while-style for-loop
    shape tested.  Initial #88 pass had off-by-one CopyLen.
    **(Medium)** — caught by lit CHECK on the `LD BC,N` immediate.
  - `clang` driver caches built artifacts; the new #88 IR pass only
    fired via `llc` until clang was rebuilt too (separate
    `ninja clang` from `ninja llc`).  **(Painful)** — spent ~30 min
    wondering why `errs()` didn't print before realising clang
    binary was stale.
  - #89 LICM extern-addr investigation hit a deeper issue: the
    constant gets rematerialised INTO the loop body by the register
    coalescer before regalloc can place a hint.  Backed out the
    exploratory hint extension; documented on the issue (no commit
    this round). **(Hard)** — open follow-up.

- **Easy/Medium/Hard/Painful tags**:
  - LDIR aftermath / LD r,(HL) / memmove inlining peepholes:
    **(Easy)** — pattern matches in late-opt are well-tooled.
  - `Z80LoopIdiomFill` new IR pass with both PM hooks:
    **(Medium)** — legacy + new PM dual entry, cmake registration,
    pass-pipeline placement.
  - #93 chain matching with two distinct forms: **(Medium)**.
  - clang stale-artifact debugging: **(Painful)**.

- **Files touched** (in llvm-z80):
  `llvm/lib/Target/Z80/Z80LateOptimization.cpp`,
  `llvm/lib/Target/Z80/Z80LegalizerInfo.cpp`,
  `llvm/lib/Target/Z80/Z80LoopIdiomFill.{h,cpp}` (new),
  `llvm/lib/Target/Z80/Z80TargetMachine.cpp`,
  `llvm/lib/Target/Z80/Z80.h`,
  `llvm/lib/Target/Z80/CMakeLists.txt`,
  `llvm/lib/Transforms/InstCombine/InstCombineCalls.cpp` (#87 guard),
  9 new `llvm/test/CodeGen/Z80/*.ll` lit tests.
  No source touched in `rc700-gensmedet`; size deltas are pure
  compiler-side wins.

- **Not yet fixed** (deferred to future sessions):
  - **#92** nested-loop DJNZ direction (regalloc hint needs
    MachineLoopInfo).
  - **#93** partial: INC counter still in D, not B, so DJNZ
    doesn't fire (needs path a -- #95 -- or a count-up→countdown
    rewrite chained with B-hint).
  - **#94** sequential-loops B re-hint.
  - **#89** LICM extern-addr (deeper rematerialisation cost-model
    work).
  - **#95** long-term path a for #93 (target-aware IV rewrite
    suppression at IR level).
  - All pinned via lit tests (`djnz-comprehensive.ll` and
    per-issue files) so they're regression-locked.

## Phase 31: Init/resident split + Option β (Apr 30 - May 1, 2026) — branch `init-resident-split`

- **Goal**: shrink cpnos-rom resident RAM footprint by moving init-only
  code out of the relocated payload, then exploit the freed RAM for TPA.

- **Result**: resident 2438 B -> 1746 B (-692 B, -28 %); TPA 55 K -> 56 K
  reported.  8 commits, all green through `make integration-test`.

- **Mechanism**: `.init.text` / `.init.rodata` sections at PROM 0 0x0100,
  embedded by relocator and run in place from PROM (never copied to
  RAM).  cpnos_cold_entry split into init-phase (PROM, runs to netboot
  end) + resident_handoff (RAM, does PROM disable + NDOS coldstart).
  Option β raised cpnos.com CODE_BASE 0xDEA0 -> 0xE080, moving
  scratch_bss + IVT from 0xEB20+ up to 0xF410+ to clear the path.

- **Pain points caught (and now linker-asserted)**:
  - Initial Option β attempt left `SP=0xED00` while cpnos.com loaded
    up to 0xED00; stack pushes during `impl_conout` calls overwrote
    the loaded build stamp at 0xECE8.  Symptom: "no E> prompt".  Fix:
    moved SP to 0xF500 + added 4 layout ASSERTs in payload.ld (cpnos
    end ≤ resident base, stack top > load end, etc).  **(Hard)** —
    silent corruption, only visible by hex-dumping the SIO output.
  - First attempt to move ZP_INIT to `.init.rodata` broke NDOS COLDST
    silently (zero-page LDIR'd from PROM-shadowed RAM post-disable).
    Fix: pinned as global `zp_init_data` in `.resident.data` with
    linker ASSERT that its address is in 0xED00..0xF7FF.
    **(Painful)** — caught only by integration test, not link-time;
    ASSERT now turns the same trap into a build error.

- **Compiler issues filed during the work**:
  - ravn/llvm-z80 #88 — N×16-bit constant fill loop should lower to
    seed-and-LDIR idiom (~6-8 B per call site, hits `setup_ivt`).
  - ravn/llvm-z80 #89 — Loop-invariant 16-bit constant reloaded into
    DE every iteration despite IR-level hoist (regalloc clobbers DE
    for loop counter).  IR is clean; backend-side bug.
  - ravn/llvm-z80 #90 — `(uint8_t)(extern_addr >> 8)` byte-arg call
    routes through DE→L→H→A in 10 B instead of `ld a, high(sym); call
    fn` in 5 B.  Hits `set_i_reg(IVT_ADDR>>8)` for 5 B savings.

- **Easy/Medium/Hard/Painful tags**:
  - Tagging sources with section attrs: **(Easy)**.
  - Two-region linker script + relocator embed update: **(Medium)**.
  - Stack collision diagnosis: **(Hard)**.
  - ZP_INIT post-PROM-disable trap: **(Painful)**.

- **Files touched**: `init.c`, `cfgtbl.c`, `netboot_mpm.c`,
  `cpnos_main.c`, `reset.s`, `payload.ld`, `relocator.c`, `relocator.ld`,
  `Makefile`, `cpnos-build/Makefile`, `docs/memory_map.md`,
  `tasks/todo.md`.

## Phase 30: cpnos TPA growth (Apr 30, 2026) — Phase A + B

- **Goal**: maximize the TPA on the cpnos slave by sliding NDOS
  upward in RAM.  cpnos.com is non-relocatable and link-addressed,
  so each lift is a coordinated change to `cpnos-build/Makefile`
  CODE_BASE/DATA_BASE plus the resident BIOS layout in
  `cpnos-rom/payload.ld`.

- **Phase A (commit `6251525`)**: NDOS 0xD000 → 0xDD80 (TPA 51 K → 55 K
  reported, +1.7 KB strict).  Blockers cleaned up along the way:
  - `nos_handoff()` used to memcpy a 24 B SNIOS jump table to a fixed
    0xEA00 slot every cold boot (~16 B of code + the 24 B copy at
    0xEA00 was forced live).  Replaced by pinning the cpnet-z80 NIOS
    extern at 0xED33 (= the resident `_snios_jt` symbol) via
    `cpnos-build/src/cpnios-shim.asm` -- a build-time constant.
    `payload.ld` now asserts `_snios_jt == 0xED33` so any drift is a
    link error, not a silent runtime stomp.
  - Resident `enter_coldst()` had `jp 0xD003` hard-coded; replaced
    with inline-asm `jp %0 : "i" (CPNOS_NDOS_ADDR + 3)` so the target
    follows `cpnos.sym` automatically.
  - `nos_handoff()`'s BIOS-JT copy address (was 0xCF00 hard-coded)
    becomes parametric via `BIOS_JT_COPY_ADDR = CPNOS_NDOS_ADDR -
    0x100`.  `cpnos_addrs.h` is generated from `cpnos.sym` at PROM
    build time -- one source of truth.  **(Medium)** -- the
    individual edits were small, but each was a chase to find a
    hard-coded address that had been "fine forever" because NDOS had
    never moved.
  - cpnos.com payload-stamp: a 23-char "YYYY-MM-DD HH:MM <git>" tag
    written into the trailing 0x1A record padding by
    `cpnos-build/stamp_cpnos.py` and printed by `netboot_mpm.c` after
    EOF.  Operator can read off the screen which build of the
    monolith landed -- decoupled from the resident BIOS's banner
    stamp.  Two distinct stamps because the PROM and the cpnos.com
    are produced in separate make sub-builds.

- **Phase B (commit `a1e9ce9`)**: NDOS 0xDD80 → 0xDEA0 (+288 B, but
  `CPNOS_TPA_KB = (NDOS+0x22)/1024` rounds down to the same 55 K).
  - `_msg` (200 B netboot frame buffer) moved out of low scratch_bss
    via `__attribute__((section(".scratch_bss_hi")))` into a new
    SCRATCH_HI region in the previously-unused 0xEC24..0xECEC IVT->
    payload gap.
  - Low scratch_bss (now just `_cfgtbl` + `_kbd_ring` + smalls,
    ~218 B) shrinks to 0xEB20..0xEC00 and butts up against IVT.
    cpnos.com's record-padded file end (0xDEA0+0xC80 = 0xEB20)
    butts up against the new low scratch start with 0 B headroom.
  - Path 2 was bounded: in the 0xEA20..0xED00 budget, scratch_bss
    (418 B) + IVT (36 B) only fit if `_msg` moves out (the post-IVT
    220 B gap is the only single hole large enough to absorb 200 B
    in one piece).  Going further requires moving IVT itself or
    sliding the payload origin -- Path 3 territory, hits the brittle
    `cpbios.asm` hand-typed addresses noted in the
    `feedback_state_certainty` memory.
  - Off-by-one bug found mid-test: netboot's safety check was
    `if (dma >= 0xEB20)`, which fires on the *successful* last
    sector landing exactly at the limit.  Changed to strict `>` so
    the next iteration's READ-SEQ EOF response can still drive the
    break.  **(Painful)** -- the symptom was 25 dots then silence,
    not a test failure with a clear cause.
  - `mame_ppas_test.lua` had hard-coded `KBD_HEAD = 0xEA24` /
    `KBD_RING = 0xEA2A`; broke on the Phase B move.  Fixed by
    auto-extracting via `llvm-nm` into `clang/cpnos_ppas_addrs.lua`
    in the integration-test target.  **(Medium)** -- caught only
    because the harness sat in stage 2 timeout for 60 s; quick to
    fix once located.  Audited the rest of the cpnos-rom tree for
    similar hard-coded scratch_bss addresses -- only one stale
    *comment* in `init.c` (now fixed); no other live references.

- **Integration-test alias added** (commit `e08f963`): `make test`
  and `make integration-test` both run `cpnos-ppas-test`.  Plain
  `make` still only builds.  The PPAS regression covers transport
  + NDOS + BDOS + console + keyboard + file load + run + output
  framing, which is enough to catch any layout move that broke a
  load-time invariant.  **(Easy)** -- mechanical Makefile edit.

- **Cumulative result**: NDOS rose 0x11A0 = 4512 B over Phases A+B
  (51 K -> 55 K reported, ~55.7 K strict).  The net TPA growth on
  Phase B alone (288 B) is real but doesn't show in `STAT`-style
  reporting because of integer KB rounding.  To reach 56 K reported,
  NDOS needs to land at 0xDFDE or higher -- another ~318 B of
  layout work, which hits Path 3.

## Phase 19: PROM-oblivious payload + C23 #embed relocator (Apr 23, 2026) — branch `conout-codes`

- **Goal**: split the 2 KB PROM0 budget across both physical EPROMs
  (PROM0 0x0000..0x07FF + PROM1 0x2000..0x27FF) to fit a full RC700
  CONOUT control-code set (ported from `rcbios-in-c/bios.c:specc`),
  AND restructure the build so the payload linker has *no* knowledge
  of ROM geometry — class-of-bug elimination.

- **Before**: one ELF, `.reset`+`.init` packed into PROM0, `.resident`
  LMA'd into PROM0 tail, copied to 0xED00 at cold boot.  Switch
  jumptables emitted to `.rodata` landed in `.init` (PROM0) with
  absolute addresses baked in; after `OUT (0x18)` that RAM was
  overwritten by CCP TPA and the dispatch table JP'd to garbage.
  Root-caused during the first CONOUT refactor attempt when a new
  `switch (c)` in `specc()` triggered exactly this — serial trace
  showed banner then silence post-netboot.

- **After** — new architecture in 4 new files + a refactor:
  | File | Role |
  |---|---|
  | `payload.ld` | Links everything at VMA=LMA=0xED00 as one blob `.payload`.  No PROM regions, no AT(), no LMA tracking. |
  | `relocator.c` | C23 `#embed` of `payload_a.bin` (PROM0 tail) and `payload_b.bin` (PROM1), two `__builtin_memcpy`s into 0xED00, tail call to `cpnos_cold_entry`. |
  | `reset.s` | 3 instructions: `di; ld sp,0xED00; jp _relocate`.  Required because clang-z80 doesn't reliably honor `__attribute__((naked))` to set the stack before its own C prologue pushes. |
  | `relocator.ld` | Places `.reset` at 0x0000, C body below 0x80, `.prom0_tail` at 0x80, `.prom1` at 0x2000.  Knows about PROMs — that knowledge is *only* here. |
  | Makefile | Two-stage link: payload → `nm` extracts `_cpnos_cold_entry` → relocator linked with `--defsym` of that address.  `dd` splits `payload.bin` at byte 1920 into the two `#embed` inputs. |

- **Side effects / collapses**:
  - `cpnos_main.c`'s LMA-copy loop deleted (relocator does the copy).
  - `resident_entry` merged into `cpnos_cold_entry`; two-stage
    init/resident split was only there because of the LMA dance.
  - `.resident`/`.init` section attributes kept for minimal churn
    — the payload script just globs `.resident.*` + `.text.*` into
    `.payload`.  No jumptable-routing footgun anymore: switch
    tables and their readers are now co-located inside the payload.
  - `cpnos_rom.ld` deleted.
  - `impl_conout` gained full RC700 control-code dispatch (specc):
    CR, LF, BS, TAB, BEL, clear, home, erase-EOL/EOS, insert/delete
    line, cursor L/R/U/D, XY addressing (ctrl-F + two coord bytes).
    Excludes bg/fg (0x13/14/15) — need BGSTAR buffer we don't carry.

- **Sizes**: payload 2126 B at 0xED00.  PROM0 = 33 B relocator + 95 B
  pad + 1920 B payload_a.  PROM1 = 206 B payload_b + 1842 B pad.
  Both EPROMs actively used for the first time since Phase 18.

- **Smoke**: `make cpnet-smoke` PASS end-to-end.  Full CCP + M80
  assembly + L80 link + `sumtest.com` execution prints `CPNET OK A314`.

- **Lessons**:
  - A single switch statement was enough to trip the jumptable-
    landed-in-wrong-PROM class of bug.  Architectural fix > local
    workaround (`-fno-jump-tables` would have papered over it).
  - C23 `#embed` is the right tool for carrying a binary payload
    through a compile — it keeps the tool-flow declarative instead
    of Python-shell-string-munging.  Two `#embed`s + linker-placed
    sections is cleaner than one array + a runtime split.
  - Clang-z80 lacks `naked` + reliable `[[noreturn]]` tail calls —
    tiny asm shim for SP setup, accept `CALL` at end of `relocate`
    (payload's cold entry is marked noreturn, so the return slot
    is harmless).
  - Reserving a fixed 128 B budget for the relocator code avoids
    a chicken-and-egg (its size determines where payload_a lives,
    but payload_a's size is known only after the split).

- **Filed / TODO**:
  - #50 — Investigate why `memcpy`/`memmove` compile to large code
    at call sites (118 B for one `memmove` before inline-LDDR rewrite).
  - #51 — Clean up dead `build_loader.py`, `cpnos-loader` target.
  - #52 — Replace `EXX` in CRT/PIO ISRs with selective register
    save: slave programs can legally use shadow regs (was #48).
  - Earlier todo-laters still open: ISR-driven SIO-B RX ring (#44),
    MEMORY_MAP.md needs a Phase 19 refresh.

### Phase 19b: CONOUT acid test (Apr 23, 2026) — Medium

- **Goal**: reproducible test that exercises all 15 RC700 CONOUT
  control codes end-to-end (not just `make cpnet-smoke` which only
  touches print+CR/LF) and asserts the resulting 8275 framebuffer.
- **Shape**: `testutil/acid.c` — z88dk `+cpm` C program using
  stdlib `bdos(6, c)` (Direct Console I/O) to bypass BDOS fn 2's
  TAB-to-spaces expansion so raw control bytes reach our BIOS
  CONOUT JT.  `mame_acid_test.lua` boots the slave, waits for
  `DONE\r\n` on SIO-B, dumps 0xF800..0xFFFF, asserts 30 specific
  cells.  `make conout-acid` target wires it up — runs in ~7 s.
- **Lessons / footguns hit**:
  - BDOS fn 2 expands TAB to spaces at the BDOS layer; fn 6 is
    the right call for exercising raw BIOS CONOUT.
  - Don't pass `--sdcccall 1` to z88dk when linking against the
    default crt/stdlib — mismatch produces a working-looking
    .COM that corrupts its first BDOS call arg.
  - RC700 `start_xy` (0x06) coord bytes are ASCII-offset by `' '`
    (matches rcbios `specc`).  Sending raw binary col/row
    underflows `uint8_t` in `xy_step`, and our unrolled
    `mod SCRN_ROWS` only subtracts 3× — residual `val` ≥ 25
    makes `CELL()` write outside display RAM and corrupt the
    payload.  Fixed in acid.c by adding 32 to both coords; file
    a follow-up to either bound-check in `xy_step` or widen the
    mod-unroll to cover 0..255 input.
  - Netboot server's `_seed_sub_file` default was `slave_id=0x70`
    but our build hardcodes `RC702_SLAVEID=0x01`.  Added
    `CPNOS_SLAVEID` env var overriding the default to 0x01 so
    `cpnos-sub-test` and `conout-acid` both hit the right `$nn.SUB`.
- **Result**: `PASS: all 15 CONOUT codes verified at frame 370
  (7.4s emulated)`.  Display shows the full intended pattern —
  HELLO! at (20,5), smiley at rows 10-11, STAY/GONE preserved,
  erase_to_eol/eos regions blank.

### Phase 19c: payload size analysis + clang-z80 codegen audit (Apr 23, 2026) — Medium

Read-only pass over the payload (2126 B at 0xED00; 688 B slack before
the 0xF800 resident ceiling; PROM1 has 1842 B of pad).  Nothing
ROM- or RAM-constrained; savings below are tidiness, not unblocking.

- **Size-sorted symbol dump** (`llvm-nm --size-sort clang/payload.elf`):
  top 6 by function size are `netboot_mpm` (170), `port_init` (104),
  `specc` (101), `init_hardware` (99), `impl_conout` (97), `delete_line`
  (76).  Biggest data: `_msg` 200 B (CP/NET frame, fixed), `_cfgtbl`
  173 B (DRI layout, fixed).

- **Tier 1 savings (~95 B, mechanical)**:
  1. `scroll_up` triplicated — exists as 26 B symbol AND inlined in
     `cursor_right` (25 B tail of 52 B) AND `cursor_down` (25 B tail
     of 38 B).  `__attribute__((noinline))` reuses standalone copy.
     ~50 B.
  2. `xy_step` 3×-unrolled `mod SCRN_ROWS` — 48 of 68 B is two
     triple-subtracts for row + col.  Replacing with a clamp-on-
     overflow fixes the acid-test underflow bug AND shrinks the
     function.  ~35 B.
  3. `init_hardware` inlines a 4th copy of the scroll/clear LDIR —
     calling `clear_screen` saves ~10 B.

- **Tier 2 savings (~35 B, medium)**: impl_conout BSS spill of `c`
  (~12 B), cfgtbl_init LDIR-template for pointer fields (~10 B),
  port-init + IVT-fill 16-bit-for-small-count loops (~10-15 B).

- **Tier 3 uncertain (~40-80 B)**: specc switch + 60 B jumptable →
  hand-rolled dispatch; netboot_mpm `sframe` BSS spills.  Both
  higher-effort, unclear savings.

- **Nothing reclaimable**: `_msg`, `_cfgtbl`, `_FCB_HEAD`, and
  clang's per-switch `LJTI_*` jumptable overhead — all intrinsic.

- **Recursion check**: zero.  Call-graph is a DAG (Tarjan's on the
  disasm), no self-loops.  Deepest chain: 5 levels
  (`cpnos_cold_entry → netboot_mpm → cpnet_xact → snios_rcvmsg_c
  → transport_recv_byte`).  Two `jp (hl)` sites exist — one is the
  `specc` switch jumptable, other is the `_jump_to` CCP trampoline.
  Neither introduces cycles.  ISRs contain zero `CALL`s so they
  add nothing to stack depth when they fire.  Worst-case stack
  high-water ~14 B against SP=0xED00.

- **BSS spill attribution**: 13 B total across 6 functions
  (`delete_line` 4 B, the rest 1-2 B).  **Zero** of it is parameter
  overflow — every payload fn takes 0-2 args, well within
  sdcccall(1)'s register budget.  All 13 B is register-alloc
  spill of locals or parameters that can't stay live across a
  CALL or LDIR setup.

- **Push/pop vs BSS spill** (filed as ravn/llvm-z80#74): Z80
  `push hl`/`pop hl` is 2 B / 21 T for a spill-reload pair vs
  BSS `ld (nn),hl`/`ld hl,(nn)` at 6 B / 32 T.  Dropping
  `+static-stack` doesn't help — clang falls back to SP-relative
  alloca (10 B per spill side) which is +77 B worse across
  resident.c.  Minimal self-contained repro posted on the issue.
  Interesting: clang-z80 *does* use push/pop for simple "one
  value crosses one CALL" but gives up on the multi-value
  LDIR-setup shape.

- **Tail-call peephole** (filed as ravn/llvm-z80#75): TCO exists at
  `Z80LateOptimization.cpp:2913` but is MBB-local.  Common early-
  return pattern produces `CALL` in one MBB that falls through to
  a separate `RET`-only MBB — branch folding already handles the
  explicit early-return (`ret c` in-place) but misses the CALL-
  fall-through-to-RET case.  Likely pass-ordering (BranchFolding
  considers the merge before `JR_C → RET_C` drops the other
  predecessor).  Fix: run TCO peephole *after* branch folding,
  or widen it to follow the fall-through edge.

- **SDCC peephole.def vs clang**: 20+ rules in the custom
  `sdcc/peephole.def` — ALL handled by clang natively at -Oz:
  `ld a, 0 → xor a`, redundant trailing `xor a`, `out (p), a` A-
  preservation, dead `jp`/`ret` sequences, `jp X; X:` fall-
  through, `jr cond; jp` → inverted-cond consolidation.  Clang
  goes *beyond* the rules in several cases: branchless ?: (r5
  repro emits `sub 0; add ff; sbc a,a; and 1` — 7 B, zero
  branches); vectorizes 4×byte-zero into `ld hl, 0; ld (n), hl;
  ld (n+2), hl` (9 B vs SDCC's 13+ B); OUT-chain A reuse
  generalizes beyond SDCC's 2-OUT rule.  The .def file exists to
  paper over zsdcc gaps that clang doesn't have.  Nothing to
  port.

### Phase 19c follow-throughs (Apr 23, 2026) — applied

Three commits after the audit:

1. **CR inline fast-path** (`c38ff77`): `\r` (0x0D) was routing through
   the `specc()` switch jumptable (two CALLs deep); hoisting it inline
   alongside `\n` lets clang tail-merge both into the same
   `xor a; ld (curx), a` tail.  +4 B impl_conout, ~-50 T per CR,
   +7 T per printable char.
2. **CRT-ISR-deferred cursor update** (`0773f09`): `impl_conout` used
   to reprogram the 8275 cursor via 3 port OUTs per character —
   visibly flickered on fast streams.  Replaced with `cur_dirty = 1`;
   `_isr_crt` reads the flag at each VRTC and pushes curx/cury once
   per frame.  impl_conout 101→88 B, -40 T per CONOUT call, bounded
   flicker → zero.  Also trimmed two leading CR/LFs from the signon
   banner in cpbios.asm.
3. **Tier 1 shrink** (`03fbc78`): `scroll_up __attribute__((noinline))`
   (cursor_right 52→30, cursor_down 38→15), `xy_step` clamp instead
   of 3×-unrolled mod (68→50, also fixes the acid-test underflow
   bug directly instead of just dodging it in acid.c), and
   `init_hardware` calls `clear_screen` instead of inlining a 4th
   LDIR copy (99→87).  Payload .text 2126 → 2054 B (−72 B).

- Three issues filed against `ravn/llvm-z80` for codegen gaps
  surfaced during the audit (all open, no PRs yet):
  - **#74** register-alloc spills go to BSS instead of push/pop
  - **#75** `CALL; RET → JP` peephole misses on fall-through MBB
    pairs (common early-return fan-in pattern)
  - **#76** `ld a, (hl); ld r, a` not peepholed to `ld r, (hl)`

- Tier 2 (~35 B) and Tier 3 (~40-80 B) savings from the audit
  remain on the table if payload pressure returns.  Not urgent:
  760+ B slack remains below the 0xF800 resident ceiling.

### Phase 21: Tier 2 mini-pass (Apr 25, 2026) — Easy

- Investigated the audit's Tier 2 candidates.  Shipped what worked,
  filed issues for the rest.  Payload .text 2054 → 2047 B (-7 B).

- **Applied** (`init.c`):
  - `setup_ivt`: pointer-walk + 8-bit countdown loop instead of
    `for (i=0; i<18; ++i) ivt[i]=...`.  -1 B.  clang still emits a
    parallel BC pointer dance and `dec a; ld d, a; or a; jr nz`
    instead of `dec d; jr nz` — see #77.
  - `init_hardware` port-init loop: pointer-walk + 8-bit countdown,
    same shape.  Drops 16-bit DE counter for 8-bit L counter.  -7 B.
    Same flag-routing pessimism applies.

- **Tried, rejected**:
  - `cfgtbl_init` 4× sequential `cfgtbl.drive[i] = 0x80+i` →
    `__builtin_memcpy(const)`: **+19 B**.  clang refuses to inline
    LDIR for 8-byte memcpy, unrolls into a base-pointer dance.
    Worse than direct stores.
  - `impl_const` invert second `if`: 0 B.  The 12 B
    `(x != y) ? 0xFF : 0` mask chain is the same regardless of
    polarity — see #79.

- **Blocked, deferred to llvm-z80 fixes**:
  - `impl_conout` BSS spill of `c`: ~12 B, blocked on #74.
  - `netboot_mpm` `sframe` reload-after-LDIR: ~7 B, file as #78.
  - `impl_const` mask chain: ~7 B, file as #79.

- Three more issues filed against `ravn/llvm-z80` from this
  mini-pass (all open, with self-contained C reproducers):
  - **#77** 8-bit countdown loops emit `dec a; ld r, a; or a` instead
    of flag-using `dec r` (or `djnz`) — hits every countdown loop.
  - **#78** LDIR's post-state `DE = dst+count` not used; subsequent
    `dst += count` reloads from BSS.  ~10 B per occurrence.
  - **#79** `(x != y) ? 0xFF : 0` materialised as 7-instruction mask
    chain instead of 2-instruction `add a,$ff; sbc a,a`.  ~9 B per
    occurrence.

- **Verdict**: audit's "~35 B" Tier 2 estimate optimistic by ~5×.
  Real mechanical wins cap around 7 B without compiler fixes;
  rest is gated on llvm-z80.  6 issues now open against codegen.

### Phase 21b: cross-codebase codegen sweep (Apr 25, 2026) — Easy

- User asked for a wider scan: walk BIOS + autoload + CP/NOS payload
  for clang-z80 anti-patterns worth filing as enhancements against
  ravn/llvm-z80.  Three Explore agents in parallel.

- **rcbios-in-c** — clean against #74-#79.  The only oddity is the
  `push hl; pop iy; call __call_iy` indirect-call thunk used for
  `((void(*)(void))warmjp)()`; that's load-bearing for the chosen
  sdcccall(1) ABI (no native indirect-call instruction; runtime.s
  funnels through IY).  Volatile reloads in `isr_ctc_a` are
  semantically required.  No new issues.

- **autoload-in-c** — one new actionable pattern surfaced (filed
  as #80).  The mask chain in `check_sysfile` is already covered
  by #60.  Rest is clean.

- **cpnos-rom** — the deep-scan agent flagged five candidates,
  three of which are duplicates of existing issues (#60, #74) or
  semantically required.  Two genuinely new patterns are minor:
  - sequential 16-bit immediate stores to consecutive addresses
    not folded to `ld hl, K; ld (a), hl; inc hl; ld (a+2), hl;...`
    (cfgtbl_init: 4× `ld hl, $80..$83; ld (...), hl` could be
    one `ld hl` + 3 `inc hl` + 4 stores — saves ~6 B).  Not filed:
    very narrow, single-function impact.
  - tail-merge of multiple `ld de, $0; ret` early-exit paths in
    `netboot_mpm` (~3 sites).  Not filed: generic LLVM tail-merge
    territory, may be Z80 ABI-specific quirk worth investigating
    only if anyone hits it elsewhere.

- One new issue filed:
  - **#80** `ld bc, (nn)` / `ld de, (nn)` direct addressing not
    used; clang loads to HL then `ld c, l; ld b, h`.  ~1 B per
    site, mechanical fix.

- Spurious agent finding worth recording: the autoload audit
  suggested `ld (nn), (hl)` as a fold target.  **That instruction
  does not exist on Z80** — agent hallucinated.  Pattern dropped.

- 7 codegen issues open against ravn/llvm-z80 from the cpnos
  audit cycle: #74, #75, #76, #77, #78, #79, #80.

### Phase 20: drive B: as local floppy on CP/NOS (Apr 24-25, 2026) — branch `fdc-variant` — Painful

- **Goal**: give the RC702 slave a local 8" floppy as drive B:
  alongside its existing CP/NET-served drives.  Read-only initially,
  with `pip a:foo=b:bar` style file movement as the acceptance test.
- **What got built (correct, on the dead branch)**:
  - `fdc.c`/`fdc.h` — clean µPD765 primitives (init/recal/seek/sense_int/
    READ DATA + DMA ch1 setup).  Globals-based arg passing to dodge
    clang-z80's IX-frame overhead.  ~330 B.
  - `disk.c`/`disk.h` — CP/M disk layer.  rcbios's DISKDEF macro
    verbatim for byte-identical DPB derivation; `dpb_maxi_data =
    DISKDEF(15,512,2,2048,450,128,1,2)`; DPH with `xlt=NULL` so BDOS
    skips SECTRAN; xlt_maxi_side[15] real skew-4 table; impl_read
    with 128↔512 deblocking; hostbuf-aliased dirbuf saves 128 B BSS.
  - `cpbios.asm` shims (dskshim/trkshim/...) tail-calling our BIOS.
  - `cfgtbl.drive[1] = LOCAL` so NDOS's chkdsk classifies B: local.
  - BIOS_BASE relocation from 0xED00 → 0xDD00 → 0xDE00 to make
    room for the disk BSS region.
  - 8"-DSDD MFI disk-builder pipeline (`mkmfidisk.sh` +
    `bin2imd.py` 8" maxi auto-detect).
- **Wall hit**: instrumented MAME CPU-fetch trace showed
  `_bios_seldsk` and `_bios_read` get **0** fetches during
  `dir b:`.  NDOS correctly classified B: local and JP'd to BDOS,
  but BDOS never made the BIOS calls.
- **Root cause** (the deliverable): `cpnet-z80/dist/src/cpbdos.asm`
  line 1: *"diskless BDOS for CP/NOS - functions 0-12 only.  may be
  ROMable"*.  By design.  CP/NOS was a 1982 diskless-workstation
  spec — no BDOS fns 14/15/17/18/20/21/22.  Local disks need a
  different BDOS.  See `tasks/cpnos-next-steps.md` for the three
  non-session-sized fix paths (replace BDOS / port disk fns / NDOS
  bypasses BDOS).
- **Resolution**: parked.  `pip a:=b:` over CP/NET already covers
  practical file transfer.  Cherry-picked the standalone-useful
  artifacts onto main:
  - `PORT_OUTPUTS.md` (621-line bit-level OUT-byte reference).
  - `cpnos-rom/testutil/mkmfidisk.sh` + `rcbios/bin2imd.py`
    8" maxi support (any future CP/M-floppy work benefits).
  Reverted on main: fdc.c, disk.c, BIOS_BASE move, cpbios.asm
  shims, cfgtbl.drive[1]=LOCAL, fdc-acceptance target.  Branch
  `fdc-variant` preserved locally for reference.
- **Lessons**:
  - Read the asm source headers FIRST.  The "diskless BDOS" comment
    on line 1 of cpbdos.asm was the answer to the entire mystery,
    visible the whole time.  ~3 sessions of debugging in BIOS/JT/
    NDOS/cfgtbl space could have been minutes of reading.
  - RMAC 1.1 silently emits `c3 0000` for forward references >
    ~0x90 bytes (no error, no warning, just `I` prefix in the
    listing).  And RMAC 1.1 is ASCII-only — UTF-8 em-dashes/
    arrows in comments break the parser silently.  Two foot-guns
    worth a comment in `tasks/cpnos-next-steps.md` for any future
    cpnos-build edit.
  - clang-z80's `--gc-sections` is good — fdc.c/disk.c never made
    it into the live payload bytes despite being compiled and
    linked, because nothing called them.  Made the experiment
    cheap to keep around (no PROM cost) and clean to revert.

### Phase 22: CP/NET fast-link design — Option P pinned (Apr 25, 2026) — Easy

- **Goal**: pick a host<->RC702 transport that beats the current 38400-
  baud async path (~3.8 KB/s) for CP/NET + CP/NOS traffic, without PCB
  modifications, while leaving the machine "usable normally" — physical
  RC722 keyboard plugged into J4, both SIOs free for terminal/printer.

- **Design phase only.** User does not have Pi 4B / 3B host hardware on
  hand and explicitly asked for design artifacts only — no Pico
  firmware, no Z80 bench tests, no MAME patches yet. Bring-up deferred
  until hardware is acquired.

- **Investigated scenarios** (using SIO and PIO ports, no J8):
  - SIO-only async tweaks — capped at 38400 baud, dead-end without mods.
  - SIO-only SDLC — TX works but RX blocked by missing DPLL + NC TxC/RxC
    pins on J1.  Asymmetric only.
  - PIO-A (J4) repurposed for fast link — ruled out by RC722-keyboard
    constraint and missing ARDY chip pin (Mode 2 impossible).
  - PIO-B half-duplex via J3 — full handshake (BSTB+BRDY both routed),
    keyboard untouched, SIOs untouched.  ~30-50 KB/s sustained.
  - Hybrid PIO-B in + SIO-A SDLC TX — ~70 KB/s response side, costs
    SIO-A.  Documented as future upgrade if response throughput needs.

- **Pinned**: Option P — PIO-B half-duplex via J3, direction-switched at
  CP/NET frame boundaries.  Design doc at `docs/cpnet_fast_link.md`.
  Hard upper bound: ~30 KB/s in, ~50 KB/s out (8-13× current).
  Production target: Pi 4B running z80pack-as-CP/NET-master natively,
  driving J3 cable through level shifter (Topology B).  Development
  iteration shape: Mac + Pico USB-CDC (Topology A), same wire protocol.

- **Languages locked**: C (clang-z80) for Z80 BIOS, Python 3 for host
  bridge, C with Pico SDK for optional Pico firmware, C++ for MAME.

- **Superseded**: `rcbios-in-c/docs/parallel_host_interface.md`
  Mode-2-on-PIO-A plan.  Deprecation banner added; previous "three
  options" / cable-shopping notes in `tasks/todo.md` rewritten.

- **Verified hardware facts** (consolidated from sessions 16/18/20-21
  and the schematic):
  - SIO-A bit clock at ÷1 = ~614 kbaud TX-direction signaling works.
    Framing layer (SDLC vs monosync) **uncertain** — earlier
    "SDLC specifically verified" claims should be treated as
    unverified bit-level signaling only.
  - PIO-A Mode 1 input + ASTB strobe works on this RC702 (`ravn/cbl923`
    Pico keyboard rig is the existence proof).
  - PIO-B (J3) is electrically symmetric to PIO-A but has never been
    bench-tested — first bring-up step when hardware arrives.

- **Memory pinned**: project goal "fast link is CP/NET-only", "physical
  RC722 keyboard remains attached", "Pi as production sidecar (Pi
  hardware not yet acquired)" all recorded in user memory so future
  sessions inherit the constraints without re-deriving them.

- **Decision rationale formalised** (later in same day, after the
  initial design pin): user requested a thorough report in the project
  on the Option-P decision and why the alternatives were rejected.
  Added a "Decision rationale" section at the top of
  `docs/cpnet_fast_link.md` with: priority-ordered constraint list,
  full options-considered matrix (P, H, H', Mode-2, K, A1-A4, B/C
  variants, Y-cable, keyboard-relocation, J8), per-option rejection
  analysis, and an explicit "Long-term: full-speed SIO TX comparison"
  subsection capturing the user's plan to ship P, bench it, then
  build an H prototype to determine empirically whether the response-
  side throughput improvement justifies H's costs.  Existing "Option H
  alternative / future upgrade" subsection retitled "long-term
  comparison target" to match.

- **MAME side implemented** (2026-04-25, follow-on to design):
  branches `ravn/mame:cpnet-fast-link` (slot device + bridge card)
  and `ravn/rc700-gensmedet:cpnet-fast-link` (Z80 stub + harness).
  Three commits land the work:
  - `mame 0e6ee52260d` — `bus/rc702/pio_port/` slot infrastructure
    (modelled on Einstein userport), keyboard slot card refactor,
    `cpnet_bridge` slot card (POSIX TCP listener), `rc702.cpp`
    machine_config refactored, misleading "parallel port" comment
    dropped.  690 insertions / 27 deletions across 8 files.
  - `rc700-gensmedet bcdb181` — `cpnos-rom/init.c` PIO-B init triplet
    + IVT slot 17 routed to new `_isr_pio_par` (in `isr.s`) which
    counts received bytes into resident.c BSS variables.  ~40 byte
    PROM growth, well within budget.
  - `rc700-gensmedet a71d7c1` — `tests/cpnet_bridge/` Python+Lua
    harness that drives the host -> Z80 byte path end-to-end inside
    MAME via TCP localhost:4003 and a write-tap on the BSS counter.
    `make cpnet-mame-test` target wires it in.

  Verification done so far: `mame -validate rc702` passes,
  `-listdevices`/`-listslots` show pioa/keyboard/kbd nesting + empty
  piob, both slots accept `keyboard` and `cpnet_bridge` options,
  `make cpnos` builds clean with the new ISR.  End-to-end harness
  PASS gate is conditional on the CP/NET netboot server being up
  (z80pack-as-master on :4002) — without it the Z80 stays in the
  autoload PROM and `_isr_pio_par` never fires.

  Topology B production deployment (Pi 4B + Pi Pico) still parked
  pending hardware acquisition, per the original phase 22 scope.

- **MAME bridge design specified** (same day, post-cleanup):
  expanded the "MAME side" section of `docs/cpnet_fast_link.md` from
  a 3-bullet stub to a full design spec.  Initially scoped narrowly
  (CP/NET-specific PIO-B wiring); user redirected the same day to
  a generic-slot pattern that mirrors how MAME exposes RS-232 ports.
  Branch: `cpnet-fast-link`.

  Final shape (4 changes in `ravn/mame`), anchored after a source
  survey of upstream MAME conventions for Z80-PIO peripherals:

  - **Precedent identified**: `einstein_userport_device`
    (`src/devices/bus/einstein/userport/`) is the closest existing
    upstream pattern — a `device_single_card_slot_interface` with
    exactly the methods we want (`read()`, `write(uint8_t)`,
    `brdy_w(int)`).  Verified by source fetch.  Most other Z80-PIO
    drivers (`mz700`, `pasopia`, `kc`, `prof80`, `rt1715`)
    hardcode their peripherals.
  - **No upstream generic 8-bit + STB/RDY slot exists**.
    `centronics_device` is wrong topology (unidirectional
    Centronics-shaped); `cg_parallel_slot_device` lacks STB/RDY.
  - **Verified gap, then closed**: `z80pio_device` has no
    MODE-change callback — but neither does the physical Z80-PIO
    chip (no mode-signal pin; per-port external signals are only
    data + STB + RDY + INT, verified Zilog datasheet).  Real
    peripherals don't observe mode either — they cope by being
    fixed-mode (printer, keyboard) or by following higher-level
    protocol on the wire.  The CP/NET bridge takes the latter
    route: implements both `read()` and `write()` and lets the
    chip route events to the right one based on its current mode;
    direction state on the socket-facing side comes from CP/NET
    SCB length counting.  No port-0x13 sniff, no upstream PIO
    patch, no control-word parser in the bridge.  (Earlier draft
    had option-(a)/option-(b) hedging; closed by realising the
    bridge mirrors real hardware and doesn't need to know mode.)

  - (1) `rc702_pio_port_device` in `bus/rc702/pio_port/` — modelled
    verbatim on Einstein userport; `device_single_card_slot_interface`
    with `read()` / `write(uint8_t)` / `brdy_w(int)` interface.
    Promotable to `bus/z80pio_port/` later if it earns adoption.
  - (2) `rc702_pio_port_cards` slot-option list mirroring
    `default_rs232_devices`: `keyboard` (existing model,
    slot-ified), `cpnet_bridge` (new), open for future entries.
    No "null_pio" entry — MAME's idiom for "no default card" is
    passing `nullptr` as the slot's third argument, not a named
    no-op card.  (`null_modem` is a misleading naming
    inspiration: it actually forwards bytes to a host bytestream;
    not the same as "empty slot".)
  - (3) Refactor `rc702.cpp` to expose PIO-A and PIO-B as slots.
    Default config: PIO-A=keyboard, PIO-B=nullptr (empty slot).
    Matches today's
    behaviour exactly when no `-piob` argument given.  Drops the
    incorrect 2016 comment "Printer (PIO port B commented out)" —
    PIO-B was never the printer port (printer is on a SIO channel
    per the hardware reference and per `bios.h:185-195`).
  - (4) `rc702_cpnet_bridge_device` slot card implementing the
    `device_rc702_pio_port_interface` — talks Z80-PIO handshake on
    one side, Unix/TCP socket on the other, same wire protocol the
    Pi+Pico USB-CDC bridge will speak in production.

  Why generic-slot framing matters: lets us run any historical
  RC702 software (CP/M, COMAL, BASIC) in MAME with PIO-B simply
  empty, exactly as on real hardware.  CP/NET activation becomes
  a `-piob cpnet_bridge:localhost:4003` command-line argument,
  not a build-time wiring decision.  Steps (1)-(3) are also a
  credible upstream MAME contribution candidate; only the bridge
  peripheral (step 4) needs to stay fork-only.  Bridge is the
  first concrete bring-up step — needs only a working `ravn/mame`
  build (already maintained) and a stub `isr_pio_par` on the Z80
  side, no Pi 4B or J3 cable required.

- **Level-shifter requirement dropped** (same day, post-rationale):
  user pointed out that the existing `ravn/cbl923` Pi Pico keyboard
  rig drives the Z80 PIO directly from 3.3V GPIO without level
  shifting, and the Z80 reads it cleanly (TTL VIH min 2.0V).  Z80 PIO
  is signal-only on J3 (no +5V or +12V rail — unlike J4 which powers
  the keyboard).  Updated `docs/cpnet_fast_link.md` cable spec, host
  side, and constraint-#5 satisfaction text:  no TXS0108E / 74LVC245
  / shifter chip required;  add 470 Ω - 1 kΩ series resistor on each
  Pico-input pin to current-limit protection diodes in the
  Z80-drives-Pico direction;  Topology B switched from "Pi 4B GPIO
  direct + level shifter" to "Pi 4B + Pi Pico over USB-CDC" so one
  firmware codepath covers both dev and production.  Cable BOM is
  now 11 wires + 9 series resistors.  Open question retained:
  measure Z80 PIO VOH on this RC702 at bring-up to confirm the
  no-shifter cable holds.

### Phase 23: Option P MAME bring-up — slot infra and unwinding (Apr 26-27, 2026) — Painful

- **Goal**: implement the Option P host bridge in MAME so external
  Pi/Mac processes can plumb CP/NET frames into the Z80's PIO-B port.

- **Path 1 — slot device** (committed on `cpnet-fast-link` branch,
  merged via `588658b4327`).  Built `src/devices/bus/rc702/pio_port/`
  with `pio_port`, `keyboard`, `cpnet_bridge` cards; wired both PIO-A
  and PIO-B as `device_single_card_slot_interface` slots in
  `rc702.cpp`.  POSIX socket listener on :4003 + listener thread +
  FIFO + emu_timer + STB pulse logic.  Filed
  [ravn/mame#6](https://github.com/ravn/mame/issues/6) when
  `-piob cpnet_bridge` (or `-piob keyboard`) blocked cpnos-rom IM2
  IRQ delivery — VRTC stops firing, CRT goes black, CCP never loads.

- **Path 2 — Einstein topology** (commit `54cccdbc3af`).  PIO-A
  reverted to direct keyboard wiring, PIO-B kept as the lone slot.
  `-piob keyboard` still produced the regression.  **Falsified** the
  "two slots on one chip" hypothesis.

- **Path 3 — bypass slot, wire `cpnet_bridge_device` directly to
  chip callbacks** (devcb_write_line / std::function flavours).
  Both crashed at MAME config time
  (`device_t::config_complete + 428`) before any data flowed.
  Discarded.

- **Empty-slot regression discovered (2026-04-27)**: even with NO
  card plugged in, the bare `RC702_PIO_PORT(config, m_pio_b)` slot
  wrapper breaks cpnos-rom boot.  Hangs at `PC=0x0039` before its
  first SIO-A transmit, never sends ENQ, never reaches A>.  The
  earlier "empty slot is benign" claim on ravn/mame#6 was true only
  for autoload-PROM CP/M floppy boot, which doesn't engage PIO-B's
  IM2 IRQ vector.  cpnos-rom uses that vector for `isr_pio_par`,
  hence sensitive.  Issue title amended.

- **Path 4 — direct (no-slot) bridge** (designed in
  `docs/cpnet_pio_direct_design.md`, branch `cpnet-pio-direct`).
  Drop slot/card entirely; `m_pio->in_pb_callback().set(FUNC(rc702_state::cpnet_pb_r))`
  directly to driver methods; use MAME's `osd_file` as TCP listener
  (no POSIX socket); single emu thread via 1 ms `emu_timer`; raw byte
  logs to `/tmp/cpnet_pio_rx.bin` + `tx.bin`.  Implementation written
  + built once.  Byte-level path verified working (6 bytes from
  harness arrived in rx.bin, strobe fired, in_pb_callback returned
  the right byte) but PIO-B IRQ never delivered — chip log showed
  `IE=0 IP=1` because cpnos-rom itself wasn't booting through to its
  PIO-B init phase, the slot-infra regression masking everything.
  Implementation code lost in a stash/checkout cycle.

- **Master reverted** to `b06f303737a` "Revert merge".  Working tree
  byte-identical to `1f2d4d000db` (verified via `git diff --stat`).
  Open puzzle: a freshly-built revert binary fails cpnos-rom boot
  the same way the merge did, while the April-21 daily-use binary at
  `/Users/ravn/git/mame/regnecentralend` (built from the same SHA)
  succeeds.  Suspects: stale `.o` cache or build-flag drift.  Under
  investigation.

- **Painful** because three workarounds in a row didn't fix the
  underlying break, the empty-slot finding invalidated yesterday's
  ravn/mame#6 comment, and the direct-bridge code was lost in a
  git stash/checkout cycle and will need re-implementation.

- **What survives**:
  `docs/cpnet_pio_direct_design.md`, `docs/cpnet_slot_work_history.md`
  (this work's connective tissue), `tests/cpnet_bridge/harness.py`
  switched from mpm-net2 to `netboot_server.py`,
  `tests/cpnet_bridge/dump_logs.sh`, the ravn/mame#6 issue mirror
  `docs/mame-rc702-piob-slot-regression.md`.

### Phase 27: IRQ-driven snios-on-PIO + 3-way bench (Apr 28, 2026) — Hard

- **Goal**: fix the snios-on-PIO direct path so it actually works,
  then bench it against SIO and PIO-proxy modes.  Phase 26 left it
  failing at "INIT OKPNILOR..." stalls after 4-25 sectors, filed as
  ravn/rc700-gensmedet#56 with a "fourth race" framing.
- **Root cause** (not a race): `transport_pio_recv_byte` treated the
  byte value `0xFF` as "no byte yet" sentinel, but `0xFF` is a valid
  data byte that mpm-net2 sends throughout cpnos.com.  Sector 4 of
  cpnos.com contains 19 0xFF bytes — the first sector with any —
  matching the "stall after ~4 iterations" report.  The "intermittent"
  framing was misleading: `cpnos.com.count(0xff)` would have nailed
  it in 30 seconds.  Saved as memory
  `feedback_intermittent_is_hypothesis.md`.
  Full RCA: `tasks/session34-direct-pio-stall-rootcause.md`.
- **Fix** (architecturally correct, ~50 LoC):
  - PIO-B chip IE on (init.c).
  - 256-byte SPSC ring buffer at 0xF700 (page-aligned, in unused
    tail of PAYLOAD region).  uint8_t head/tail = free mod-256 wrap.
  - `isr_pio_par` reads `PORT_PIO_B_DATA` and pushes into ring.
  - `transport_pio_recv_byte` pops from ring with timeout.
  - `enable_interrupts()` moved before `NETBOOT()` (otherwise the
    ISR can't fire during the boot phase).
  - `cpnet_bridge::poll_tick` re-gated on `m_brdy_high && buffer_non_empty`
    (the "always strobe" workaround for the polled path's 0xFF=empty
    issue would over-strobe and overwrite m_input under the IRQ
    design).
- **MAME-side issue uncovered**: Mode 1 entry doesn't auto-raise
  BRDY (Zilog datasheet says it should, 2 cycles after mode select).
  Bridge's optimistic-init `m_brdy_high=true` self-bootstraps via
  `set_mode(OUTPUT)` callback.  Filed **ravn/mame#8**.
- **Banner reorder**: signon now prints BEFORE `NETBOOT()` so the
  screen layout is row 0 = banner, row 1 = netboot progress dots,
  row 2 = blank, row 3 = `A>`.  Wire-mode banner tag extended from
  3 chars to 7 chars (`"WWW-MMM"`); branch ships `"PIO-IRQ"`.
- **Bench results** (sumtest workload pending; netboot only here):

  | Mode | Wall median (-nothrottle) | Wall median (real-time) |
  |------|---:|---:|
  | PIO-PROXY (raw OTIR/INIR + host proxy) | 1668 ms | (not measured) |
  | PIO-IRQ direct (snios envelope on PIO) | 1874 ms | 3738 ms |

  Both 9/9 OK with strict success check (boot marker `+PSJ` AND
  clean `A>` prompt).  PROXY is ~12% faster cold-boot; IRQ-direct
  is more variable (stddev 68 ms vs 3 ms) due to per-byte ISR
  cascade vs bulk OTIR/INIR.

- **`smoke_inject.py` fix**: prompt-check now runs on recv-timeout,
  not just on data-received.  Removed the 10s nudge mechanism; it
  was injecting phantom CRs during program work and creating extra
  A> echoes.  This is the "I had to type Enter manually" report.

- **sumtest port-write done signal**: sumtest.asm now does
  `mvi a, 055h; out 080h` after printing CPNET OK.  Lua tap traps
  port 0x80 via `install_write_tap` for deterministic completion
  detection — no SIO-B byte parsing, no display memory scanning.
  (Tried port 0xFF first; that maps to 8237 DMA on rc702.cpp:175.)

- **Lessons** (saved as feedback memories):
  - Sentinel preconditions must travel with the value across use
    sites; promoting context-specific sentinels to a shared `#define`
    invites silent breakage when the precondition no longer holds.
  - "Intermittent" is a hypothesis label, not a property — falsify
    it with cheap data-content checks before chasing timing causes.

- **Issues + TODOs raised**: see `tasks/session35-irq-fix-and-bench.md`
  for the full list (Pico-side proxy port, 32-bit CRT counter mirror,
  multi-channel SNIOS investigation).

### Phase 27b: warm-boot port instrumentation (Apr 28, 2026) — Easy

- **Goal**: generic "Nth program exited" detection for harnesses
  driving multi-program workloads, without screen/SIO-B scraping.
- **Mechanism**: 4-byte OUT in `impl_wboot` (resident BIOS) writes
  0x57 to port 0x81 on every CP/M warm boot.  Companion
  `mame_porttap.lua` extends the existing port-0x80 sumtest-done tap
  with a port-0x81 wboot tap; `/tmp/cpnos_wboot.txt` carries a
  saturating counter + `emu.time()` per fire.  Catches every program
  that overwrites CCP (m80, l80, sumtest, all non-trivial transients);
  by-design misses programs that just RET back into a still-resident
  CCP — those don't warm-boot, so there's nothing to instrument.
- **End-to-end verification deferred**: netboot reported as regressed
  after Phase 27 commit (NETBOOT returns 0, `-PS` boot marker).  OUT
  mechanism itself verified by disassembly at clang/cpnos.lis +
  0xefc8: `3e 57 d3 81`.

### Phase 28: cpnos-rom payload codegen audit (Apr 29, 2026) — Easy

- **Goal**: assess whether the 2536 B cpnos-rom payload is at the
  llvm-z80 codegen ceiling, or if the gap to slot-1 (2 KB, ~488 B) is
  a compiler-fix away vs a refactor away.
- **Method**: ranked all 130 functions by size from `clang/cpnos.lis`,
  read the largest (`_netboot_mpm` 202 B, `_cpnos_cold_entry` 137 B,
  `_init_hardware` 110 B, `_specc` 101 B, `_isr_crt` 101 B,
  `_impl_conout` 88 B, `_xport_*` family) and looked for recurring
  patterns.  Built minimal repros for each new finding, verified
  against the project flags (`-Oz +static-stack -disable-lsr`).
- **Verdict**: **not at the ceiling.**  Several recurring missed
  optimizations identified.  Hand-written 8080 SNIOS asm is tight;
  the C-side functions show common gaps.
- **Filed (4 new ravn/llvm-z80 issues)**:
  - **#83** — dead `and 1` after `ld a,1` for `_Bool` store
  - **#84** — loop body backs up HL through BC unnecessarily
    (in-place writes already advance HL); plus DJNZ miss
  - **#85** — sequential consecutive-address stores not lowered to
    HL-walked `ld (hl),v / inc hl` chain
  - **#86** — switch range-check on `u8` discriminant uses 16-bit
    SUB/SBC instead of 8-bit CP
- **Comments added** to existing issues:
  - **#60** (Redundant LD A,reg) — `xor a; out; ld a,$0; out`
    instance from `_isr_crt`
  - **#18** (Known-value register copy) — constant routed
    DE→L→A in `_init_hardware`'s `set_i_reg($EC)` call
- **Already covered** by prior issues #73 (small memcpy unroll),
  #74 (BSS spill across single CALL), #78 (LDIR post-state DE/HL
  not reused) — no refile.
- **Source-side wins** independently of compiler (filed in
  tasks/todo.md): drop the vtable indirection (~38 B; build is
  already TRANSPORT-specific), gate BOOT_MARK in production
  (~30-50 B), pad LOGIN_PWD copy to 12 B to hit the LDIR
  threshold.
- **Realistic shave estimates**:
  - Source-only: ~80-100 B → ~2440 B
  - + compiler fixes: ~100-150 B → ~2300 B
  - + drop vtable: → ~2260 B
  - Closing the full ~488 B gap to slot-1 needs a console
    subsystem refactor on top.  Not yet planned.
- **Lessons**: the `+static-stack` BSS-spill policy is the single
  biggest source of waste in C-side functions; #74 (push/pop for
  short-lived spills) would be the most impactful fix.  Dense-range
  switches on u8 keys are a recurring 8-bit->16-bit promotion source.

### Phase 28e: source-side size shave + PPAS regression test + IMD pipeline doc (Apr 30, 2026) — Medium

User declared cpnos "feature complete for my purposes now" -- this
session focuses on cleanup, size, and capturing the workflow.

**TPA in banner.**  Banner now reads `RC702 CP/NOS 52K PIO-IRQ
<date> <hash>`.  The `52K` is computed at PROM build time from the
NDOS address extracted from `cpnos-build/d/cpnos.sym` (TPA top =
NDOSE = NDOS + 0x0122; TPA size = (NDOS + 0x22 - 0x100) / 1024).
Auto-updates whenever NDOS placement shifts.

**Vtable removal (-134 B).**  `cpnet_transport_t` was a remnant of
a planned runtime SIO/PIO probe that never shipped.  Replaced the
indirect dispatch with `#define cpnet_send_msg snios_sndmsg_c`
aliases in `transport.h`.  Killed `cpnet_dispatch.c`, the two
vtable structs, the `active_transport` pointer, the static
`sio_probe` stub, and the BC<->HL juggling in
`snios.s`'s `SNDMSG_DISPATCH` / `RCVMSG_DISPATCH`.  Banner uses
`TRANSPORT_NAME` literal directly -- no runtime patch from
`active_transport->name`.

**BOOT_MARK_ENABLED build flag.**  19 BOOT_MARK call sites x ~5 B
each were ~95 B that don't ship in production.  New default-1 flag
collapses the macro to `((void)0)` when set 0; dropping the marker
saves 98 B (yet better than the 30-50 B audit estimate -- clang
cleared more dead code than expected).

**LOGIN password copy (-6 B).**  `__builtin_memcpy(8)` unrolls into
4 immediate stores (~40 B); a byte for-loop runs ~16 B; the
"manual byte 0 + memcpy 7" idiom drops below clang's unroll
threshold and dispatches to the runtime `_memcpy` LDIR stub
(shared, ~3 B per call site).  Stays in plain C per project rule
"prefer C over inline asm".

**Cumulative size impact**:
  - default (MIRROR_SIOB=1): 2548 -> 2410 B (-138 B)
  - production (MIRROR_SIOB=0 BOOT_MARK_ENABLED=0): 2528 -> 2280 B (-248 B)

PROM-1 budget is 2048 B -- so default is 362 B over, production is
232 B over.  The remaining gap likely needs llvm-z80 codegen fixes
(BSS-spill across CALL is the biggest single offender).

**ravn/llvm-z80 #87 filed.**  `__builtin_memcpy(8)` unrolling at
`-Oz` is a `MaxStoresPerMemcpyOptSize` setting too high for Z80 --
on this target the "inline stores" branch is much larger than the
"call shared LDIR stub" branch.  Threshold of ~1 byte would
recover ~50-80 B project-wide on top of this session's work.

**`make cpnos-ppas-test` regression.**  End-to-end driver:
  `E>` -> `PPAS<CR>` -> `>>` -> `L PRIMES<CR>` -> `>>` -> `R<CR>`
  -> wait for "29989" in SIO-B mirror -> `>>` -> `Q<CR>` -> `E>`.
Wall-clock ~50 s.  Direct kbd_ring injection (MAME's
natural-keyboard layer doesn't fully wire to the RC702 driver).
Critical lesson: split the keystroke feed at `>>` boundaries --
queueing "L PRIMES<CR>" during PPAS's CP/NET load of PPAS.ERM
caused the leading 'L' to be dropped (some part of the load path
flushes the input ring).

**`docs/imd_to_mpm.md`.**  Captures the IMD -> cpmsim recipe used
this session for PolyPascal v3.10: imd2raw parser + sector skew +
EXM=1 extent semantics + per-disk diskdef table + the bounce-mpm
step.  Generic enough to extract any RC700 5.25" mini disk.

**Open follow-ups.**
- ravn/llvm-z80 #87 (memcpy threshold) — would unlock another
  ~50-80 B of free shrinkage.
- "Rewrite ISRs in C with __attribute__((interrupt)) + port vars"
  (todo.md, parked).  All prereqs verified working today.
- "Replace or re-install WS for cpnos" (todo.md, parked from
  Phase 28d) -- not blocking, but would let the WS-on-E: tree
  actually be usable.
- "NDOS into the PROMs" (todo.md, parked) -- collapses cold-boot
  netboot from ~4 KB to ~2 KB.
- 18 commits ahead of origin/main + 1 commit ahead in z80pack
  submodule, awaiting an explicit `git push`.

### Phase 28d: WS 3.x from rc703-div-bios-typer is unusable as-is (Apr 30, 2026) — Easy

- **Symptom**: `WS PRIMES.PAS`; load works; opening the help-level menu (`^J H 2`) consistently corrupts the cpnos slave -- screen freezes / shows garbage / cury+curx clobbered to 0x20, frame counter at 0xFFFC..0xFFFF gets overwritten with spaces.
- **Root cause** (verified by Lua probe + state dumps): the `ws.com` we lifted from `rc703-div-bios-typer/` was installed for a memory-mapped screen layout that differs from our cpnos slave's.  WS does direct memory writes (not BIOS CONOUT) to its configured screen base; that base + size assumption overlaps both our scratch BSS at `0xEAxx` (cury/curx/kbd_ring/cfgtbl) and the resident BIOS frame counter at `0xFFFC..0xFFFF`.  Each WS status redraw fills 48+ bytes past `0xFFCF` plus stomps low BSS.
- **Why PPAS works**: PolyPascal-compiled binaries use BIOS CONOUT for all screen output -- no direct memory writes -- so their 80x25 view stays inside our display range.  (PolyPascal v3 is a native Z80 compiler -- precursor to Turbo Pascal -- not a P-code interpreter, despite the term being misused in earlier notes.)
- **Not a cpnos-rom bug.**  The ISR refactor and frame-counter placement are correct against any well-installed CP/M program.  Moving the counter wouldn't help -- WS also corrupts BSS at `0xEAxx`, same root cause.
- **Action**: track the "re-install or replace WS" task in `tasks/todo.md`.  Either find a WS that uses BIOS CONOUT only (no direct video) or run WINSTALL.COM (not in our `ws/` set) to retarget the existing copy.

### Phase 28c: ISRs preserve shadow regs (PPAS no longer corrupted) (Apr 29, 2026) — Easy

- **Trigger**: extracted PolyPascal v3.10 (PPAS.COM, 28416 B) onto E:.
  Disassembly showed PPAS uses the shadow bank as persistent
  workspace — 216 `EXX` and 208 `EX AF,AF'` opcodes, with dense
  clusters in the editor / runtime dispatch.  Cpnos-rom's three IM2
  ISRs (`isr_crt`, `isr_pio_kbd`, `isr_pio_par`) bracket their bodies
  with `EX AF,AF'; EXX` / `EXX; EX AF,AF'`, which clobbers PPAS's
  shadow registers on every interrupt.  At 50 Hz CRT VRTC alone, the
  Pascal runtime state corrupts within milliseconds.
- **Investigation (clang interrupt attribute)**:
  `__attribute__((interrupt))` is fully wired in llvm-z80
  (`Z80FrameLowering.cpp`, `Z80CallLowering.cpp`,
  `Z80RegisterInfo.cpp`).  CSR list `Z80_Interrupt_CSR =
  {AF,BC,DE,HL,IX,IY}` filters down to actually-clobbered regs.  Lit
  test `llvm/test/CodeGen/Z80/interrupt.ll` shows a one-store ISR
  emits exactly `push af / ... / pop af / ei / reti`.  Cpnos build
  doesn't pass `+shadow-regs`, so the EXX-based EXX_CSR_SaveList
  isn't used today.
- **Fix**: keep the ISRs as `__attribute__((naked))` with manual asm
  (the bodies are 100% inline asm anyway), but replace `EX AF,AF';
  EXX` bracket with explicit PUSH/POP for only the registers each
  ISR actually clobbers:
  | ISR | Uses | Save set |
  |-----|------|----------|
  | `isr_crt` | A, F, HL | AF + HL (4 B) |
  | `isr_pio_kbd` | A, F, BC, DE, HL | AF + BC + DE + HL (8 B) |
  | `isr_pio_par` | A, F, DE, HL | AF + DE + HL (6 B) |
  | `isr_noop` | none | none |

  None of the ISRs touch IX/IY; all userspace shadow registers are
  preserved by definition since we never EXX.
- **Cost**: payload 2548 -> 2554 B (+6 B with MIRROR_SIOB=1, mirrors
  to 2528 -> 2534 B with mirror off).  T-states: isr_crt +26 T at
  50 Hz = 0.03% CPU; isr_pio_par +47 T per byte at 31 KB/s peak =
  ~37% of CPU during netboot bursts only (acceptable, netboot is
  one-shot).
- **Verified**: `PPAS PRIMES` runs cleanly under MAME with the new
  ISRs after extracting PPAS.COM/ERM/HLP onto E: (master I: 4 MB HD).
- **Followup TODO**: convert each ISR to a C function with
  `__attribute__((interrupt))` and inline-asm clobber lists, so the
  compiler computes the save set automatically.  Current naked form
  produces identical code; the conversion is purely an ergonomics
  win.

### Phase 28b: bigger MP/M disks; CCP boots on E:=master I: (Apr 29, 2026) — Easy

- **Goal**: stop being constrained to 256 KB 8" SS-SD floppies for
  master-side MP/M, and have the slave's first prompt land on a
  4 MB drive instead of A:.
- **Method**: master MP/M's `bnkxios-net-2.mac` already declares HD
  DPHs at drive numbers 8/9/15 (I/J/P).  No XIOS rebuild — just
  populate `disks/drive[ij].dsk` and extend the slave's CFGTBL.
  - `cpnos-rom/cfgtbl.c`: added `drive[4]=NET_DRV('I',0)`,
    `drive[5]=NET_DRV('J',0)` so slave E:/F: route to master I:/J:.
  - `cpnos-rom/cpnos_main.c`: ZP[4] = 0x04 so CCP comes up at E>
    instead of A>.  CCP.SPR LOAD path was unaffected — that uses
    `ccpfcb` (cpndos.asm) which hardcodes drive byte 1 (A:), so
    boot still pulls CCP.SPR from master A:.  Fixed an outdated
    cfgtbl.c comment that claimed CDISK drove the LOAD.
  - `z80pack/cpmsim/mpm-net2`: cp library copies of
    `mpm-net2-drive[ij].dsk` -> `disks/drive[ij].dsk` on every
    launch, with mkdskimg fallback if the library disks are
    missing.  Pre-formatted 4 MB images created via
    `mkfs.cpm -f z80pack-hd` and staged in `disks/library/`.
- **Verdict**: live-tested via PIO-IRQ netboot.  Banner +
  18-char boot strip ending in `J` (NDOS COLDST reached) +
  25 sector dots + `E>` prompt confirmed on both the SIO-B mirror
  (`/tmp/cpnos_siob.raw`) and the MAME CRT screenshot.
- **Cost**: payload 2536 -> 2548 B (+12 B for two extra
  `NET_DRV('I'/'J',0)` stores).  Still ~480 B headroom under
  PROM0+PROM1 = 4 KB.
- **Caveat**: existing pass criteria (`pio-irq-netboot`,
  `pio-irq-smoke`, `cpnet-smoke`) grep for `A>` in SIO-B; they need
  updating to match `E>`.  Smoke workloads that explicitly do
  `A:`/`B:`/`C:` etc. are unaffected since A:..D: still mount the
  same 256 KB floppies as before.

### Phase 27d: 3-way bench complete (SIO / PIO-IRQ / PIO-PROXY) (Apr 28, 2026) — Medium

- **Goal**: comparable workload bench across the three CP/NET transports
  on the same `m80 + l80 + sumtest` workload (sumtest = unrolled
  sum-of-1..1000).  Session 35 had netboot-only numbers; this is the
  first apples-to-apples workload comparison.
- **TRANSPORT= build flag** (`make cpnos TRANSPORT=sio|pio-irq|pio-proxy`):
  - snios.s calls indirect through `_xport_send_byte` /
    `_xport_recv_byte`; Makefile aliases via `ld --defsym` to the
    chip-specific primitives at link time.
  - `clang/transport_stamp` invalidates .o cache when TRANSPORT changes
    (without it, switching modes incrementally relinks stale objects).
  - Banner tag from `-DTRANSPORT_NAME='"$TRANSPORT_NAME"'` so the
    on-screen banner reflects the chosen wire.
  - For pio-proxy: `-DTRANSPORT_PROXY` triggers a different
    active_transport (`&transport_pio_vt`, raw OTIR/INIR frames),
    skips the 256 B IRQ ring at 0xF700 (transport_pio.c +
    isr.c #ifndef TRANSPORT_PROXY), preprocesses payload.ld so the
    upper-bound ASSERT relaxes to display memory at 0xF800.
- **Auto-exit**: mame_porttap.lua reads `/tmp/cpnos_smoke_inject.log`
  every periodic; on `[marker] CPNET OK found` schedules
  `manager.machine:exit()` 0.5 s later.  Without this, `make
  *-smoke` ran to `-seconds_to_run 1200` (20 minutes) on every PASS
  — masked by manual `pkill regnecentralend` between iterations.
  Saved as memory `feedback_bench_must_self_terminate`.
- **Bench results** (-nothrottle, mpm-net2 backend; smoke_inject
  step1->marker is the timed window):

  | Workload  | SIO     | PIO-IRQ          | PIO-PROXY        |
  |-----------|--------:|-----------------:|-----------------:|
  | sumtest   | 35.8 s  | 27.5 s (1.30×)   | 25.4 s (1.41×)   |
  | filecopy  | 14.8 s  |  8.4 s (**1.81×**) |  7.7 s (**2.02×**) |

  Frames-to-completion (filecopy, 32-bit CRT counter @ 50 Hz):

  | Workload  | SIO    | PIO-IRQ | PIO-PROXY |
  |-----------|-------:|--------:|----------:|
  | filecopy  | 3416   | 1883    | 1687      |

  Workload shape:
    sumtest = `m80 sumtest,=sumtest.asm` + `l80 sumtest,sumtest/n/e`
              + `sumtest` (run).  CPU-dominated; the m80 step alone
              takes ~25 s of the wall in SIO mode.
    filecopy = pre-assembled FILECOPY.COM reads SUMTEST.ASM record-by-
              record via BDOS F_READ and writes SUMTEST.CPY via F_WRITE.
              ~358 reads + ~358 writes over CP/NET — no compiler in
              the timed window.  Verify step extracts both files via
              cpmcp and byte-compares (first 45735 B identical in all
              three modes; CPY's last 89 B is record-pad).

  PIO-PROXY beats PIO-IRQ by ~8% (envelope avoidance) and SIO by
  ~30% on the CPU-bound sumtest.  On the I/O-dominated filecopy the
  parallel-transport advantage is much clearer: PIO-IRQ ~1.8×,
  PIO-PROXY ~2.0× over SIO.
- **Reproducible via**: `make {sio,pio-irq,pio-proxy}-smoke
  WORKLOAD={sumtest,filecopy}`.  Each target preflight-checks the
  cpnos build's wire-mode tag (SIO / PIO-IRQ / PIO-PRX in cpnos.bin),
  MAME tree has the bridge gate fix (`m_brdy_high` in
  cpnet_bridge.cpp), and the binary is newer than the source.
- **32-bit CRT frame counter** added to isr_crt at 0xFFFC..0xFFFF
  (50 Hz CRT VRTC), mirroring rcbios.  filecopy.com snapshots S/E
  and prints both in the FILECOPY OK marker; the verify step diffs
  them for emulation-second-precise timing immune to MAME wall-clock
  jitter.
- **NDOS Err 06, Func 10**: appears between m80 exit and l80 start
  in all three runs.  Per session 23, this is "Close Checksum Error"
  from MP/M's FCB checksum mechanism — m80 (CP/M 2.2 era, predates
  CP/NET) clobbers FCB reserved bytes between F_MAKE and F_CLOSE.
  Cosmetic in this bench (m80 still produces correct .REL output);
  same root cause as the PIPNET fix from session 23.

### Phase 27c: netboot "regression" was a test-setup mismatch (Apr 28, 2026) — Easy

- **Symptom** carried over from 27b: every netboot run today produced
  boot strip `INIT OKPNI...-PS` (LOGIN never fired), reported as a
  regression vs Phase 27's 9/9 OK.
- **Root cause**: the test entry point was wrong for this branch, not
  the code.  The irq-fix slave drives SNDMSG/RCVMSG on PIO byte
  primitives but keeps the SNIOS envelope.  Compatible host: anything
  that speaks SNIOS envelope on TCP — mpm-net2 itself does.  Setups
  tried during the burn:
  - `make cpnet-smoke`: wires only SIO-A → :4002.  Slave's PIO bytes
    go nowhere; slave doesn't use SIO-A in this branch.
  - `tests/cpnet_bridge/harness.py --mode pio-netboot`: spawns
    `cpnet_pio_server` in self-contained mode, which expects RAW SCB
    frames — protocol mismatch with envelope-on-PIO slave.  Also
    blocked at the symbol-extract step because `_pio_par_byte` /
    `_pio_par_count` were dropped by `ld.lld --gc-sections` after the
    IRQ-ring rewrite removed their writers (commit f10c99f).
  - **Correct setup** (committed in `be1059c` as `make pio-irq-netboot`):
    `-piob cpnet_bridge -bitb3 socket.127.0.0.1:4002` — MAME PIO-B
    bridge connects directly to mpm-net2's TCP port; slave envelope
    bytes flow straight through.  Boot strip `INIT OKPNILOREC+PSJ`,
    A> on SIO-B, 30 s -nothrottle.
- **Side fixes** in `be1059c`:
  - `__attribute__((used))` + explicit `KEEP(*(.bss._pio_par_*))` in
    payload.ld so the harness's symbol-extract step works.  ld.lld
    drops sections marked SHF_GNU_RETAIN regardless of `((used))`,
    needs the linker-script KEEP.
- **Lesson** (saved as `project_pio_irq_test_topology` memory):
  before assuming a regression, verify the test harness was designed
  for the slave's *current* transport configuration.  When the slave
  protocol changes (envelope on serial → envelope on PIO), every
  test entry point that wires the host needs to be re-evaluated for
  shape compatibility.

### Phase 26: PIO-to-mpm-net2 — proxy vs direct snios (Apr 27, 2026) — Hard

- **Goal**: get CP/NOS netboot working against real `mpm-net2`
  (z80pack MP/M + SERVER.RSP) over the PIO transport, not just our
  Python `netboot_server.py` responder.  Two designs compared:
  - **Proxy**: Z80 sends raw PIO SCBs; a host-side Python translator
    wraps them in the SIO ENQ/ACK/SOH/CKS/EOT envelope and forwards
    to mpm-net2 :4002.  Z80 work unchanged from Phase 25.
  - **Direct (snios on PIO)**: snios.s envelope code is left intact
    but its byte primitives are rewired from SIO chip ports to PIO
    chip ports.  No host-side proxy; MAME's PIO bridge connects
    directly to mpm-net2.  Bytes on the wire are the same envelope
    SIO would produce, just on the PIO line.
- **Proxy implementation**: extended `cpnet_pio_server.py` with a
  `--upstream HOST:PORT` flag.  `upstream_send` / `upstream_recv`
  mirror snios.s as a Python client (slave-side ENQ/ACK exchange).
  PING (FNC=0xC0) handled locally; everything else forwarded.
  End-to-end netboot against mpm-net2: **1.44 s emulated, full
  NDOS COLDST**, 60 frames, ~10 ms host wall per frame for the
  envelope round-trips.  Works robustly.
- **Direct implementation**: snios.s `_transport_send_byte` /
  `_transport_recv_byte` calls swapped for `_transport_pio_*`
  versions.  Frame-level transport_pio_vt and pio_probe deleted
  on the experiment branch (saves ~340 B payload).  cpnos_main's
  probe block dropped (always default to SIO transport vtable;
  SIO vtable's send_msg/recv_msg = snios_sndmsg_c/snios_rcvmsg_c
  which now use PIO bytes).
- **Three bugs found and patched**:
  1. **Stale-prefix byte on Mode 1→0** (transport_pio.c).  MAME's
     z80pio.cpp `set_mode(MODE_OUTPUT)` immediately fires
     `out_pb_callback(m_output)`, leaking the previous send's last
     byte before the actual data.  mpm-net2 saw a stale `05`
     between ACK and SOH, errored.  Fix: pre-load `m_output` via
     data-port write while still in Mode 1 (the chip's
     `MODE_INPUT::data_write` latches `m_output` without firing
     the callback), then flip to Mode 0 — `set_mode` then emits
     the byte we want.
  2. **PIO-B chip IRQ stealing bytes** (init.c).  Default init
     enabled chip-side IE (`0x83`); `isr_pio_par` fired on each
     byte arrival and `IN A,(0x11)` from the ISR consumed the
     byte before snios's busy-poll could see it.  LOGIN's 1-byte
     payload survived; OPEN's 37-byte payload didn't.  Fix:
     chip IE off at init (`0x83` → `0x03`).
  3. **Bridge `rdy_w` skipping strobe on empty buffer** (the
     smoking gun for OPEN; `mame:cpnet_bridge.cpp@9c2cbb4e1a9`).
     The bridge gated its strobe on `m_input_index < m_input_count`.
     When the buffer drained mid-frame and Z80 kept polling, the
     chip's `m_input` retained the last *real* byte, not 0xff.
     Each Z80 IN returned the same stale byte; snios's NETIN
     stored duplicates and accumulated wrong CKS, eventually
     bailing with retry-exhausted timeout.  Fix: drop the gate;
     always strobe on BRDY rising edge.  When buffer is empty,
     `read()` returns `0xff`; chip latches `0xff`; Z80's
     `transport_pio_recv_byte` correctly polls past the
     `0xff` sentinel.
- **Why SIO worked but PIO didn't** (the question that drove this
  whole investigation): SIO uses MAME's stock `null_modem` slot,
  which sits on `bitbanger_device` + `posix_osd_socket` directly.
  The SIO chip emulation paces bytes at the configured baud rate
  (38400 here) and reports availability via the RR0 char-available
  bit; Z80 only reads `PORT_SIO_A_DATA` when that bit is set, and
  the chip emulation never caches "the last byte" across a
  no-data window.  PIO goes through our project-specific
  `cpnet_bridge.cpp` slot; the Z80-PIO chip emulation caches
  `m_input` between strobes, exposing every quirk above.
- **Status after the three fixes**: snios-on-PIO reaches LOGIN,
  OPEN, and several READ-SEQ iterations against mpm-net2.
  Stalls intermittently after 4-25 sectors — a fourth race remains.
  Filed as **ravn/rc700-gensmedet#56**.
- **Verdict**: proxy wins for routine use (robust, 1.44 s
  end-to-end, simple).  Direct is functional but flaky;
  filed for future work.
- **Branches**: `ravn/rc700-gensmedet:pio-mpm-netboot` (commits
  `62c2b61` proxy WIP, `20d9203` snios-PIO experiment, `7a50843`
  initial comparison report, `ba9277c` init.c IE-off, `4afa036`
  deeper-investigation report).  `ravn/mame:master` (`9c2cbb4e1a9`
  rdy_w fix — landed directly to master since merged from earlier
  Phase 25 work).

### Phase 25: PIO CP/NET driver + MAME bridge to standards (Apr 27, 2026) — Medium

- **Goal**: real PIO transport in CP/NOS (not just speed-test
  scaffolding), boot-time runtime selection, full netboot over
  PIO, and figure out why MAME measured PIO as *slower* than SIO
  end-to-end despite the wire-speed bench from Phase 24 saying
  the opposite.
- **Phase A — Z80 driver + probe**:
  `cpnos-rom/transport_pio.c` rewritten as frame-level (OTIR send,
  INIR recv, no `di`/`ei` around block instructions, chip IE off
  with Z80 IFF on so CRT VRTC keeps firing).  Vtable in
  `transport.h`, `cpnet_dispatch.c` provides `active_transport` +
  `cpnet_send_msg`/`_recv_msg`.  `pio_probe()` sends 7-byte PING
  SCB, awaits PONG with bounded timeout; success → flip
  `active_transport` to PIO.  `BOOT_MARK(7,'P'/'S')` on screen
  records the choice.  `snios.s` jt SNDMSG/RCVMSG slots dispatch
  through `cpnet_send_msg` so NDOS at runtime hits whatever probe
  selected.  `netboot_mpm.c::cpnet_xact` likewise.
- **Phase B — host-side server**: `cpnos-rom/cpnet_pio_server.py`
  reads SCBs raw (no SOH envelope), strips MAME's chip-emulation
  stale-prefix byte by structure (SID at offset 2 vs 3),
  dispatches via `netboot_server.dispatch_sndmsg`.  Z80 reaches
  NDOS COLDST through 25 round-trips (LOGIN / OPEN / READ-SEQ × 25
  / CLOSE).  PASS.
- **Linker guard**: `payload.ld` ASSERT on
  `__payload_end <= 0xF800`.  Discovered while debugging blank
  boot markers — payload growth had pushed `.rodata` into display
  memory; `clear_screen()` then wiped the marker[] string.  Now
  fails at link time.
- **Performance investigation**: per-frame ~130 ms emulated /
  ~53 ms wall on host.  Profiled cpnet_pio_server:
  recv 53 ms, dispatch 0.02 ms, send 0.01 ms.  ~99.96 % of host
  time blocked in `socket.recv()`.  Tracked to MAME's own
  `cpnet_bridge.cpp:266` listener-thread `select()` with **50 ms
  timeout** — chip-side `write()` queues bytes but doesn't wake
  the listener thread, so flush latency = 50 ms wall × 2 (each
  direction).
- **MAME bridge refactor**: rewrote `cpnet_bridge.{cpp,h}` on the
  MAME-standard `BITBANGER` sub-device pattern (matches
  `null_modem`).  No private threads, no mutex, no atomics, no
  std::deque buffering.  -192 net lines.  Result: end-to-end
  CP/NOS netboot **3.82 s emulated → 0.28 s emulated (13.6×
  faster)**.  Per-frame host recv 53 ms → 0.5–3 ms wall.
- **Banner**: signon now reads `RC702 CP/NOS PIO 2026-04-27 12:58
  f6c43a4+` — transport, UTC date, HH:MM, git short hash with `+`
  on dirty tree.  `cpnos_buildinfo.h` regenerated each build via
  `.PHONY` Makefile rule with `cmp`-then-`mv` so cpnos_main.o
  rebuilds only when the date or hash actually change.
- **MAME OSD finding**: `socket.host:port` syntax means CONNECT
  (not listen) — required flipping `cpnet_pio_server.py` to be
  the listener and adding a "dummy listener" pre-spawn to the
  harness for non-PIO modes (otherwise MAME aborts at startup
  with "Connection refused" from bitbanger's first I/O).
- **Numbers (MAME -nothrottle)**:
  - PIO end-to-end: 0.28 s emulated (was 3.82 s pre-refactor).
  - SIO end-to-end: 2.08 s emulated (rate-bound at 38400 baud).
  - PIO is now **7.4× faster than SIO in MAME**, projects to
    ~40× on real hardware.
- **Branches**: `ravn/rc700-gensmedet:cpnet-pio-direct` (commits
  `46b5479…3f30d8f`); `ravn/mame:cpnet-fast-link-remerge`
  (`f9f1efdc1ce` — the bitbanger refactor).  Master/main untouched.

### Phase 24: Option P parallel-port driver + throughput bench (Apr 27, 2026) — Medium

- **Goal**: implement and measure the Option P transport over PIO-B
  end-to-end through the (now-working) `cpnet_bridge` slot card.
- **Driver**: `cpnos-rom/transport_pio.c` — Mode 0/1 lazy switching,
  32-byte RX ring, ISR push.  Two Z80-PIO chip-state quirks worked
  around explicitly:
  1. `set_mode(MODE_OUTPUT)` immediately fires `out_pX_callback` with
     stale `m_output` — leading 0x00 prefix on first Mode 1→0
     transition.  Filed as ravn/mame#7.
  2. Mode 0 STB pulses set `m_ip` even with `m_ie=false`.  Plain
     `0x83` IE-enable on Mode 1 entry causes a spurious IRQ.  Fixed
     with ICW + mask-follows (0x97 + 0x00) which atomically clears
     `m_ip`.
- **Frame round-trip**: 10-byte CP/NET-shaped SCB
  (FMT/DID/SID/FNC/SIZ + 4 payload + CKS) sent + mirrored back +
  validated on Z80 side.  PASS at 4.3s emulated.
- **Throughput bench (MAME 100% throttle, wall ≈ Z80 emulated)**:
  - TX C-loop:  22 KiB/s
  - **TX OTIR: 156 KiB/s**
  - RX ISR-driven: 15 KiB/s (lower bound; MAME emu overhead)
  - **RX INIR busy-poll: 148 KiB/s** (10× ISR; matches TX)
  Full report at `docs/cpnet_pio_speed_results.md`.
- **Compiler bug**: clang Z80 `+static-stack` miscompile of a
  `uint16_t` loop counter — held in BC for the loop test, read from
  a never-written frame slot at the call-arg use.  Filed as
  ravn/llvm-z80#82, XFAIL lit test pushed.  Workaround: nested
  `uint8_t` loops.
- **Architectural finding**: in Mode 1 input, the chip's BRDY toggle
  in `data_read` is the natural flow-control mechanism — disable IE,
  run INIR, get 21 T/byte without any IRQ overhead.  The original
  ring-based recv_byte path is unusable for sustained streaming
  (back-to-back ISRs starve mainline; ring overflows).  Filed as
  ravn/rc700-gensmedet#54.
- **Boot markers** moved to row 0 cols 60-78 (upper-right) so they
  survive the nos_handoff banner overwrite on row 1.
- **Issues filed**: ravn/llvm-z80#82, ravn/mame#7,
  ravn/rc700-gensmedet#53 (tap.lua banner check on wrong row),
  ravn/rc700-gensmedet#54 (recv_byte ring path unusable).
- **Branch**: all on `cpnet-pio-direct`; `2517ba0` is the throughput
  report.  Master/main untouched per project convention; promotion
  is a future decision.

## Phase 18: PROM shrink pass (Apr 23, 2026) — branch `snios-compact`
- **Goal**: create breathing room in the 2 KB PROM0 ceiling (11 B
  slack after #39).  Target: ≥ 200 B for future work (signature
  prefix for #46, ISR-driven SIO-B ring, etc.).
- **Analysis-first**: built a per-function size breakdown of the
  2037 B payload; cross-compared with `rcbios-in-c` patterns
  (table-driven port init, shared ISR structure, SBC A,A idioms)
  to pick high-yield / low-risk changes.  See
  `cpnos-rom/MEMORY_MAP.md` + the GH issue #47 task list.
- **Tier 1 (c54229c)**: strip all trace instrumentation added
  during Phase 16-17 — SNIOS per-FNC counter, CONOUT/CONIN/CONST
  counters, CONIN ring, netboot breadcrumbs.  **-121 B** (vs ~70 B
  predicted — the compiler compacted adjacent basic blocks after
  the bumps went).
- **Tier 2a (0dae340)**: collapse ~30 inline `_port_out` calls
  in `init_hardware` + folded-in `init_pio_kbd`/`init_display`
  into one unified `port_init[]` table + for-loop.  **-39 B**.
- **Interim (9add5ba)**: smoke_inject now sends a CR nudge after
  10 s of SIO-B silence — practical workaround for issue #44 (the
  "had to type Enter manually" annoyance) until Tier 4 gives us an
  ISR-driven SIO-B ring.  Doesn't change PROM size.
- **Current slack after 12 commits**: **524 B** (from 11 B).
  | Step | Delta | Slack |
  |---|---|---|
  | main@155cca7 baseline | — | 11 B |
  | Tier 1: strip trace code | +121 | 132 B |
  | port-init table | +39 | 171 B |
  | netboot memcpy + banner trim | +90 | 261 B |
  | impl_conout dedup + no-FF | +54 | 315 B |
  | cfgtbl → BSS (runtime init) | +130 | 445 B |
  | SNIOS RECVBT tail merge | +4 | 449 B |
  | crt_scroll_up memcpy/memset + FCB trim | +29 | 478 B |
  | zero-page + JT inline LDIR | +32 | 510 B |
  | display-clear memset + 8-byte loop fix | +14 | 524 B |
- **Filed along the way**: #47 (tracking issue), #48 (ISRs unconditionally
  EXX/EX AF,AF' — unsafe), #49 (clang elides memcpy-to-0), and
  ravn/llvm-z80#73 (8-byte inline memcpy cost model).
- **Lessons**: (a) Compiler's `-Oz` inliner can still generate
  pathological code for small memcpys — always disassemble and
  measure, don't trust the intent; (b) BSS-as-ROM-substitute for
  mostly-zero static data paid the biggest single win (130 B);
  (c) Inline `ldir` via clang-z80's +{de}/+{hl}/+{bc} constraints
  is the right tool when \_\_builtin_memcpy gets UB-elided or
  cost-modeled into a pessimal inline.
- **Lessons**: (a) kill diagnostic code with the bug it diagnosed,
  not later — it had been burning space in every boot for two
  phases; (b) when a pattern appears N times inline, a table + loop
  break-evens at N ≈ 3; (c) unify before optimising — consolidating
  init_pio_kbd + init_display into one table was a bigger win than
  any local micro-opt.


- **Goal reached 2026-04-22**: "CP/NOS on a physical RC702 against a
  live MP/M II over serial" validated in emulation — cpnet-smoke PASS
  with stock MP/M (z80pack mpm-net2) serving a slave that assembles a
  1000-iter unrolled program via M80 + L80, executes it, and prints
  the correct checksum.  Eight commits this session; closed #40 and
  #41; filed #43/#44/#45 for polish work.
- **Lessons crystallized**:
  - When the network clearly delivers correct bytes (TYPE works,
    buffer dumps match disk), stop theorizing transport bugs and
    look at *interpretation* differences (CRLF, segments, ABI).
  - BDOS return codes are *function-specific*: OPEN (fn 15) returns
    0..3 on success, 0xFF on fail — don't apply the generic
    "0 ok / non-zero error" heuristic.
  - A Lua tap on 0x0005 with per-call DMA-buffer dump is the single
    most valuable diagnostic we have for slave-side BDOS behavior.
    Kept as permanent infrastructure in mame_smoke_dump.lua.
  - Any text file destined for a CP/M disk image needs CR+LF.  Saved
    as a standing memory rule.

## Phase 17: cpnet-smoke harness + "DIR was a Python false positive" (Apr 22, 2026)
- **2026-04-22**: User asked for a non-trivial regression test that
  exercises the OS end-to-end by having the on-master assembler (M80)
  compile a computed program on the slave's behalf.  Scaffolded
  `testutil/sumtest.asm` (fully unrolled sum-of-1..1000 = 0xA314),
  `mksmokeasm.py`, `mksmokedisk.sh`, `smoke_inject.py` (prompt-aware
  SIO-B sequencer with per-char pacing), and `Makefile: cpnet-smoke`.
  Per user direction: pass oracle = what the program prints,
  not byte-exactness of artifacts — any CP/NET read/write corruption
  makes the assembler emit a wrong COM → program prints wrong
  string → test fails.  **(Medium)** — several orchestration gotchas
  (RMAC label mangling was old; new ones: M80 source extension,
  SIO-B FIFO overrun from burst-inject).
- **2026-04-22**: **Fourth fragility class discovered.**  Multiple
  recent "A>" successes — including today's DIR test against what we
  thought was MP/M — were actually served by a stray
  `python3 netboot_server.py` still listening on :4002 from an
  earlier manual test.  MAME's bitbanger bound to it instead of
  cpmsim-hosted MP/M; Python's mock CP/NET responses looked plausible
  enough to fool the test harness.  Killing the zombie Python exposed
  that real MP/M gets past LOGIN (NB_step=0x03) but OPEN returns
  rc=0x02.  **(Painful)** — had to backtrack days of work because
  the oracle was wrong.  Filed #42 for test-hygiene guard.
- **2026-04-22**: Related finding: `cpnos.com` on stock
  `mpm-net2-1.dsk` (4292 B) targets z80pack's generic slave, not our
  RC702 BIOS/SNIOS layout.  Even with MP/M serving correctly, the
  fetched image would drive wrong I/O.  `mksmokedisk.sh` now
  overwrites CPNOS.IMG with our `cpnos-build/d/cpnos.com`.
- **Remaining:** #40 — real-MP/M OPEN rc=0x02 after LOGIN.  Harness
  (#41) blocked on this.
- **2026-04-22 (post-compact)**: **#40 fix identified.**  `rc=0x02` is
  NOT an error — it's a CP/M BDOS OPEN success code.  BDOS fn 15
  returns directory code 0..3 on success (the found entry's offset
  mod 4), 0xFF on not-found.  `netboot_mpm.c` treated any non-zero
  rc as failure; changed the guard to `if (rc >= 0x04) return 0;`.
  **(Easy)** once misread — hours were burned assuming 0x02 was an
  error code before re-reading the BDOS spec.  Underscores the rule:
  when a retcode looks weird, check whether it's BDOS-passthrough
  (raw directory code) vs. CP/NET transport (normalized 0/0xFF).
- **2026-04-22 (later still)**: **cpnet-smoke PASS.**  Program
  assembled on the slave by M80+L80 over CP/NET prints
  `CPNET OK A314` — sum(1..1000) & 0xFFFF computed correctly.
  Root cause chain (not what I first thought): **M80 requires
  CR+LF line endings.**  Our generator wrote LF-only source; M80's
  line scanner couldn't recognize statement boundaries, so every
  pseudo-op including `END` read as part of a single mega-line.
  Buffer-content dump via Lua tap (reading M80's read-DMA area)
  proved the file *did* reach M80 with END in it — M80's parser
  just didn't see it without the CR.  Two secondary source-level
  bugs surfaced after that: (a) M80 defaults to relocatable, need
  explicit `ASEG` for CP/M .COM output; (b) BDOS PRINTS (fn 9)
  does not preserve HL, so the print-then-format logic needs
  PUSH/POP H around the BDOS call.  Saved `feedback_crlf_cpm_disk`
  as a standing rule.  **(Painful → Easy once found)** — seven
  rounds of "it's CP/NET extent handling" / "it's READ_SEQ return
  values" / "it's source syntax" before the buffer-dump made the
  CR-LF gap obvious.  Deep lesson: when content clearly reaches
  the target correctly, look for *interpretation* differences
  before blaming transport.
- **2026-04-22 (late)**: Netboot fix validated end-to-end — CP/NOS
  loads, banner, CCP prompt, M80 + L80 run.  But assembled program
  is empty (3-byte stub).  Built cpnet-smoke harness with TYPE +
  M80 + DIR + L80 + exec stages, a saturating uint8 counter per
  CP/NET FNC at 0xEC80..0xECFF (plus 16-bit READ_SEQ at 0xEC7E),
  and a MAME Lua tap on 0x0005 to capture the **full** BDOS call
  stream (6351 calls in a typical run).  TYPE reads the source
  perfectly — CP/NET READ is not the transport-level problem.
  zmac assembles the same source cleanly — the source is valid.
  **Hypothesis confirmed via trace analysis:** M80 issues exactly
  17 READ_SEQ calls per OPEN regardless of file size (tested with
  TINY.ASM=20B and SUMTEST.ASM=5790B).  Since TINY.ASM fits in a
  single record, 16 of those reads are past-EOF.  Implication: the
  CP/NET slave chain (SNIOS → NDOS → slave BDOS) is returning
  `rc=0` (success) for past-EOF reads instead of `rc=1` (EOF),
  so M80 never sees the EOF signal that would make it finalize
  assembly.  Next: instrument the return value (A on BDOS RET)
  to prove it, or fix the NDOS/BDOS EOF path in our cpnos.com
  build.  **(Hard)** — needed three distinct diagnostic layers
  (FNC counter, BDOS tap, trace analysis) to triangulate.

## Phase 16: First end-to-end DIR against live MP/M (Apr 22, 2026)
- **2026-04-22**: CONST/CONIN echoed `F G H I` (0x46..0x49) for input
  `d i r \r`.  Diagnosis via a 4-slot CONIN input ring at 0xEC46+:
  impl_conin delivered the correct bytes `64 69 72 0d`.  The corruption
  was in the monolith's cishim/cshim: `mov a, l` after the call, on
  the assumption sdcccall(1) returns 8-bit values in L.  Disassembly of
  impl_conin / impl_const showed both end with `ld a,d; ret` — clang
  Z80 returns 8-bit in **A**, not L.  Fixed by removing `mov a, l`.
  **(Painful)** — the stale HL happened to track the input-ring scratch
  address, producing a deceptively-plausible incrementing pattern that
  looked like an off-by-one input bug rather than an ABI mismatch.
- **2026-04-22**: **First successful DIR over the wire.**  CP/NOS slave
  in MAME, bitbanger SIO-A to TCP 4002 = z80pack cpmsim mpm-net2 MP/M II
  master.  `A>dir` lists `CCP SPR / CPNETLDR COM / CPNOS IMG / NDOS SPR
  / PIPNET COM ...` — real files on `mpm-net2-1.dsk` served by MP/M's
  stock CP/NET server through our RC702-retargeted cpbios + cpnios-shim.
  CONOUT=254 for that one command, confirming full BDOS+NDOS+BIOS chain.
  The goal ("physical RC702 against live MP/M over 38400 8N1") is met
  in emulation; physical hardware next.

## Phase 15: Remote drives for slave workload (Apr 22, 2026)
- **2026-04-22**: `z80pack/cpmsim/mpm-net2` launcher now stages four disks:
  A=mpm-net2-1 (boot + CPNOS.IMG), B=cpm22-1 (DRI/MS assemblers: ASM, MAC,
  RMAC, M80, L80, LINK, Z80ASM, SLRNK, CREF80 + DDT/SID/STAT/PIP),
  C=cpm22-2 (sources: BIOS.Z80, BOOT.Z80, SURVEY.MAC, W.ASM, CLS.MAC,
  BYE.ASM, SPEED.C), D=mpm-net2-2 (MP/M system image kept around for
  tinkering).  Goal: prove CP/NET remote file access with a real workload
  (e.g. `B:MAC C:SURVEY.MAC`).  **(Easy)** — slave `cfgtbl.c` already
  declared A/B/C/D as network-mapped to master drives of the same letter,
  so no slave-side change was needed.
- **Pending:** confirm MP/M `SERVER.RSP` exposes B: and C: to slave
  SID=0x01; if not, reconfigure via GENSYS or direct edit.

## Phase 14: RC702 retarget of DRI reference modules (Apr 22, 2026)
- **2026-04-22**: Decision: the slave must NOT ship DRI's Altos-targeted
  reference code.  The stock `cpbios.asm` bangs ports 0x1C/0x1D/0x1E/0x1F
  (Altos console) and `cpnios.asm` bangs 0x3E/0x3F (Altos serial) — both
  absent on RC702.  **(Easy, once it was seen.)**
- **2026-04-22**: `cpnos-build/src/cpbios.asm` added — RC702 BIOS as a
  trampoline into the cpnos-rom resident at 0xED00+.  17-entry JT matches
  DRI's ABI exactly; CONOUT/CONIN/CONST/LIST shims translate CP/M's
  C-register arg convention and A-register return into clang's sdcccall(1).
- **2026-04-22**: Two RMAC syntax pitfalls surfaced during the cpbios
  retarget.  **(Very hard — silent failures.)**  First, `jmp` is a reserved
  mnemonic; `jmp_op equ 0c3h` assembled but resolved to zero, so the
  zero-page `sta 0000h / sta 0005h` wrote NOPs and CP/M saw a broken
  BDOS vector.  Second, RMAC truncates labels containing underscore, so
  `const_shim` appeared in the sym table as `CONST` and JT entries
  referencing the full name resolved to `JP 0x0000`.  Fixed by renaming
  to short no-underscore labels (`jpopc`, `cshim`, `coshim`, …).
- **2026-04-22**: `cpnos-build/src/cpnios-shim.asm` — 24-byte trampoline
  from the DRI SNIOS JT slot (linked at NIOS=`0xD993` in the monolith)
  into our resident SNIOS JT at `0xEA00`.  Filename carries `-shim`
  suffix per user preference; Makefile maps `cpnios-shim.asm` →
  `d/cpnios.asm` because the link needs the module name RMAC+LINK
  expects (`NIOS:` label).  **(Easy)** now the pattern was established.
- **2026-04-22**: Both trampolines in place; first end-to-end PASS on the
  RC702-retargeted monolith: banner at row 2, `A>` at row 4, 38 CONOUT
  calls (banner 22 + prompt 4 + NDOS addenda 12).  **This closes the
  tripwire that had been blocking since the BIOS_BASE move.**

## What was Hard vs Easy (through Phase 14)

**Easy** (hours, straightforward):
- Initial cpnos-rom skeleton + clang Z80 + lld linker script.
- Porting SNIOS from rcbios-in-c (hardware-abstracted cleanly).
- Adding breadcrumb counters + Lua snapshots for post-hoc analysis.
- Local-override mechanism in cpnos-build/Makefile for shim modules.

**Medium** (a session of focused debugging):
- 8275 CRT + 8237 DMA bring-up.
- DRI .SPR page-relocator (once the 128 B skip-sector was understood).
- MP/M II CP/NET 1.2 wire protocol from DRI docs.

**Hard** (multi-session, required instrumentation to root-cause):
- PROM-disable hazard and its subtle interaction with resident-copy ordering.
- NDOS's TLBIOS-walk of the zero-page BIOS vector.
- BIOS_BASE move and the cascade of silent-until-runtime address drift.
- RMAC's reserved-mnemonic + underscore-label mangling — both assemble
  cleanly, both produce `JP 0x0000` at runtime, neither generates a warning.

**Painful** (wasted time until caught):
- **Stray Python server on :4002 fooling the oracle** — hours of
  "real MP/M" tests were actually Python.  Kill-before-test guard
  filed as #42.
- **Stock CPNOS.IMG on MP/M disk was z80pack-generic, not our RC702
  build** — even when MP/M was in the loop, the fetched image would
  have driven wrong I/O ports.  `mksmokedisk.sh` now overwrites it.

- Stale `.o` files after `-D` flag changes (SLAVEID=0x70 persisted despite
  source edit) — fixed by `$(OBJS): Makefile` dep.
- PROM1 install step missing from `cpnos-install` when `.resident` LMA
  overflowed into PROM1 — silent, produced garbage at the JT LMA.
- Chasing "baseline was flaky" for hours when really one PASS had been a
  lucky single run on an otherwise broken baseline.

## Format for ongoing entries

Each new entry should record: date, phase, what changed, and a
`**(Easy|Medium|Hard|Painful)**` difficulty marker with one-line reason.
Aggregate into a "What was Hard vs Easy" summary at phase boundaries or
when the project reaches a stated goal.

## Key Architectural Decisions

| Decision | Rationale |
|----------|-----------|
| zmac over MAC | Cross-assemble on macOS without CP/M emulator |
| z88dk/sdcc for C rewrite | Only Z80 C compiler that fits 2KB PROM constraint |
| sdcccall(1) ABI | 36% smaller code than sccz80, params in registers |
| Byte-exact reconstruction | Proves understanding of original code; enables verification |
| Conditional assembly | Single source tree for 5 BIOS variants (src/) |
| Separate source trees | 58K, RC703, RC702E too different for conditional assembly |
| Ring buffers in REL30 | Enable reliable serial at 38400 baud for CP/NET |
| BIOS entry points for SNIOS | Simpler than direct SIO access, ring buffer in BIOS ISR |
| Hex-encoded CRC-16 protocol | Proven in cpnet-z80, simpler than DRI ENQ/ACK |
| Python CP/NET server | Quick iteration, handles all BDOS functions over TCP |
| verify_bios.py approach | Compares code bytes only, ignoring runtime-modified variables |
| patch_bios.py | Direct IMD patching avoids SYSGEN round-trip |
| cpnos-rom clang+lld | Z80 backend produces small, readable asm; same toolchain as autoload-in-c |
| DRI RMAC+LINK for monolith | Keep cpnos.com binary-compatible with CP/NET 1.2 semantics rather than reinvent |
| Local-override source dir | `cpnos-build/src/` overrides `cpnet-z80/dist/src/` on a per-file basis |
| -shim suffix for DRI replacements | Makes "this is our RC702 trampoline, not DRI's reference code" explicit at file level |
| Shim at 24 bytes (cpnios) | Smaller than re-implementing SNIOS on the CP/NOS side; resident owns wire logic |
| Breadcrumbs stay until goal is green | Keeps post-hoc trace analysis cheap across sessions; remove only after reliable PASS |
| Monolith addresses locked 0xD000/0xCC00 | Cpnos.com is non-relocatable; acceptable while we ship one slave hardware target |
| Live MP/M over serial as the target | Avoids bespoke-protocol drift vs. goal of stock-MP/M compatibility |

## Key Tools Created

| Tool | Purpose |
|------|---------|
| verify_bios.py | Verify assembled BIOS against reference binaries |
| patch_bios.py | Patch assembled BIOS onto IMD disk images |
| imdinfo.py | Show disk image summary (format, geometry, boot status) |
| imd2raw.py | Extract raw Track 0 from IMD images |
| bin2imd.py | Convert raw BIN to IMD format (mini, maxi, RC703) |
| run_mame.sh | Automated build+patch+launch cycle for MAME testing |
| diskdefs | RC700/RC702/RC703 disk definitions for cpmtools3 |
| build_snios.py | Build SNIOS.SPR with relocation bitmap |
| server.py | Python CP/NET server (BDOS emulation over TCP) |
| autotest.lua | MAME Lua test automation for CP/NET |
| run_test.sh | Full CP/NET test orchestration |
| chksum.asm | CP/M file checksum utility (16-bit sum) |
| bin2ihex.py | Binary to Intel HEX converter for serial transfer |
