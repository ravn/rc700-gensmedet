# Known issue: rcbios clang build hangs forever in FDC SPECIFY (bios_hw_init), SDCC unaffected

Status: PARKED 2026-07-04. Root cause NOT found. Extensively ruled out (see below).

## Symptom

`make mame-test COMPILER=clang` in `rcbios-in-c/` never boots. The disk-boot test
(`mame_disk_test.lua`) times out after its 2-minute frame budget with a **completely
blank screen** (no banner, no "A>", nothing ever written to CRT memory at 0xF800+).

`make mame-test COMPILER=sdcc` on the **exact same test disk** (`SW1711-I8.imd`,
patched with the SDCC-built `bios.cim` instead) boots cleanly to `A>` within 2
emulated seconds. Same MAME binary, same disk image, same ROM set — only the BIOS
compiler differs.

## Root cause of the symptom (not the underlying defect) — CONFIRMED

Using a custom `-autoboot_script` that samples `cpu.state["PC"]`/`SP` every 25
frames (`/tmp/mame_pc_dump.lua`), the clang-built machine is caught spinning
forever at PC 0xDA9E–0xDAA6, inside `fdc_write()`'s polling loop:

```
da9d: 57         ld d,a
da9e: db 04       in a,($4)      ; port_in(fdc_status)      <-- polls forever
daa0: ee 80       xor $80
daa2: fe 40       cp $40
daa4: 30 f8       jr nc,$da9e
daa6: 7a         ld a,d
daa7: d3 05       out ($5),a
```

This is the very **first** `fdc_write()` call in the whole boot sequence — the
`FDC: send SPECIFY command` block in `bios_hw_init.c`:

```c
/* FDC: send SPECIFY command */
while (port_in(fdc_status) & (FDC_MSR_CB | FDC_MSR_DRIVE_SEEKING))
    ;  /* wait until FDC not busy AND no drive is seeking */
fdc_write(0x03);            /* SPECIFY command */
fdc_write(0xDF);            /* step rate 3ms, head unload 240ms */
fdc_write(0x28);            /* head load 40ms, DMA mode */
```

The **first** `while` loop (waiting for CB|DRIVE_SEEKING to clear) exits normally.
The very next statement — `fdc_write(0x03)` — then spins forever: the µPD765
Main Status Register never reports `RQM=1, DIO=0` (ready for a CPU→FDC byte),
so the CPU is stuck polling port 0x04 for the rest of the test.

Frame trace (`/tmp/pc_trace.txt`) shows the hang starts almost immediately
(~3.5s emulated in), not after some earlier delay — i.e. this is the *first*
FDC access in `bios_hw_init()`, not a later one during actual disk I/O.

## Clarification: autoload-in-c's `floppy-boot-test` does NOT exercise rcbios-in-c

Initially this looked contradictory: `autoload-in-c`'s `make floppy-boot-test
COMPILER=clang` passes (boots to `A>` in ~3.5s), which seemed to suggest "clang
FDC access works, so why does rcbios hang?" — **this is not actually a
contradiction**, because the two tests boot two **completely different BIOS
binaries**:

- `floppy-boot-test` boots `test-disks/SW1711-I8.imd` **directly, unpatched**
  (see `Makefile:187`, `FLOPPY=$(CURDIR)/test-disks/SW1711-I8.imd`) — i.e. the
  BIOS already baked onto that disk image (committed `fc6085b`, 2026-06-03).
  Its boot banner is `"RC700   56k CP/M vers.2.2   rel. 2.3"` — a format that
  does **not** match rcbios-in-c's own banner string at all (rcbios-in-c's is
  `"RC700 <msize>k CP/M 2.2 C-bios/<compiler> <date>"`, confirmed in `bios.c`).
  This is some older/historic BIOS baked onto the disk, unrelated to
  rcbios-in-c's C source.
- `rcbios-in-c`'s own `mame-test` **copies** the disk and **patches in** the
  freshly-built `bios.clang.cim`/`bios.cim` before booting (`Makefile`'s
  `$(PATCH) /tmp/bios_c_test.imd $(BIOS_CIM)`) — this is the only test that
  actually exercises rcbios-in-c's own compiled BIOS.

So `floppy-boot-test` passing only proves autoload-in-c's own FDC read path
(loading the boot sector off track 0) works fine under clang — it says
nothing about whether rcbios-in-c's `bios_hw_init()` FDC SPECIFY sequence
works, because that code is never reached by that test.

**Full clean-rebuild verification performed 2026-07-04/05** (per explicit
request, to rule out any stale-artifact confusion): `autoload-in-c` cleaned
and rebuilt from scratch (`make clean && make prom COMPILER=clang`, freshly
reinstalled to `mame/roms/rc702/roa375.ic66`), confirmed `floppy-boot-test`
still PASSES. `rcbios-in-c` cleaned and rebuilt from scratch for **both**
compilers. clang's `mame-test` **still hangs** identically; SDCC's still
boots to `A>` in ~2s. The hang is real, reproducible after a fully clean
rebuild of every component involved, and specific to rcbios-in-c's own
clang-compiled `bios_hw_init()`.

## What was ruled out, with evidence

1. **Not a stale/cached MAME binary.** Both `regnecentralen` (release) and
   `regnecentralend` (debug, `d` suffix = MAME's standard debug-build naming,
   NOT "more recent") were freshly rebuilt from current mame source
   (`make OSD=sdl SOURCES=src/mame/regnecentralen/rc702.cpp SUBTARGET=regnecentralen
   REGENIE=1` and `... DEBUG=1`) at commit `e7827672` (2026-07-02). Identical hang
   in both freshly-built binaries.
2. **Not a specific MAME commit.** Rebuilt and retested at 3 different mame
   commits: `e7827672` (current HEAD), `3d77a3a3` (HEAD~1, "rename rc702_base
   -> rc700_base; apply upstream d066f1613412 fix"), and the previously-installed
   stale `regnecentralen`/`regnecentralend` binaries (26 Apr / 14 Jun — themselves
   spanning the real upd765/rc702 FDC fixes `99ea81b2`/`79ffed51`). **All produce
   the identical blank-screen hang.**
3. **Not a specific llvm-z80 commit.** Rebuilt clang and retested at 2 commits:
   current HEAD (`ef97b6c5`, includes today's `#247` MO_MCSymbol offset fix) and
   `bfc36eb8` (immediately before that fix). **Both hang identically** — today's
   MO_MCSymbol fix is not implicated.
4. **Not a bad port constant.** `PORT_FDC_STATUS=0x04` / `PORT_FDC_DATA=0x05`
   in `hal.h` match `autoload-in-c/rom.h`'s values exactly, and autoload-in-c's
   own (clang-built) FDC access works fine (`make floppy-boot-test COMPILER=clang`
   PASSES, boots to `A>` with a real floppy, verified earlier in this same
   session) — so the basic port I/O primitive is not broken for clang in general.
5. **Not a miscompiled polling-loop condition.** The `xor $80; cp $40; jr nc`
   sequence implementing `(msr & 0xC0) != 0x80` was verified by hand for all 4
   combinations of bit7/bit6 (the only bits the C source masks against) — the
   compiled bit-trick is mathematically sound for every possible MSR byte value.
   Not a codegen bug in the loop test itself.
6. **Not the outer "wait not busy" loop.** That loop (`while (msr &
   (FDC_MSR_CB|FDC_MSR_DRIVE_SEEKING))`, mask 0x1F) compiles straightforwardly
   to `in a,($4); and $1f; jr nz,...` and is observed to exit normally (PC moves
   on to the `fdc_write(0x03)` call) — the hang is specifically in the *second*
   loop, waiting for RQM/DIO after the SPECIFY byte's been requested.

## What is still unknown

Why the µPD765 (emulated) never reports MSR=RQM after the CPU passes the
"not busy" check and calls `fdc_write(0x03)`. Two live hypotheses, neither
confirmed:

- **A: real state difference from what SDCC's code does upstream of this
  point** — same C source for both compilers, so if this is a genuine logic
  difference it would have to come from a *miscompile elsewhere* (e.g. the
  DMA master-clear/mode sequence a few lines earlier in `bios_hw_init()`,
  or the CTC/PIO programming before that) that corrupts some piece of state
  the FDC controller depends on, even though the SPECIFY polling loop itself
  is correct.
- **B: a genuine MAME µPD765/rc702 emulation quirk** exposed only by clang's
  exact instruction timing/ordering around this sequence (not ruled out by
  points 1–2 above, since those tested *different* mame commits/binaries but
  not a systematic timing-injection experiment).

Distinguishing these needs either (a) an instruction-by-instruction diff of
SDCC's vs clang's compiled `bios_hw_init()` — the SDCC `.o`/`.map` files don't
carry an easily-diffable annotated listing the way clang's `.lis` does, so this
requires re-invoking `zcc`/`sdasz80` with listing flags — or (b) dumping the
live MSR byte value inside the spin loop via a custom MAME Lua probe reading
the FDC device state directly, to see what bit pattern it's actually stuck on.

## Tooling produced this session (not committed — throwaway diagnostics)

- `/tmp/mame_pc_dump.lua` — periodic PC/SP sampler via `-autoboot_script`.
- `/tmp/mame_screen_dump.lua` — waits for "A>" or timeout, dumps first 3 screen rows.
- Both are simple enough to recreate on demand; not added to the repo since they
  duplicate `mame_disk_test.lua`'s existing screen-dump logic almost exactly.

## Relationship to the parked cpnos polypascal-test hang (#119)

Superficially similar shape (boot proceeds partway then spins forever polling
hardware state that never arrives), but a **different subsystem** (FDC/µPD765
here vs CP/NET network transport there) and a **different, much earlier**
point in the boot sequence (before CP/M even reaches the disk-boot BIOS calls,
vs. after MP/M full application startup in #119). No evidence connecting the
two; listed together here only because both were investigated the same day and
both remain open with the same "environment ruled out, root cause not found"
shape.

## Update 2026-07-05: confirmed not a regression; new FDC-transaction evidence

**Verified against yesterday's build.** Checked out `rcbios-in-c` at commit
`fb512f7` (2026-07-03 12:19, the last commit touching this directory before
today — includes the `-flto` re-enablement from `fd4a197`) in a separate git
worktree, rebuilt clean with clang, and ran `mame-test`. **Identical hang**
(blank screen, full 2-minute timeout). This rules out every commit made today
as the cause; the bug predates today by at least ~14 hours and was already
present with `-flto` freshly re-enabled.

**FDC transaction log** (`autoload-in-c/mame_fdc_log.lua`, reused as-is,
passive I/O taps on ports 0x04/0x05 — see that file's own header comment for
why it must never do a `space:read`) was run twice independently (once against
a stale leftover `/tmp/bios_c_debug.imd`, once against a freshly rebuilt +
freshly repatched `/tmp/bios_c_test.imd`) and produced **byte-for-byte
identical decoded traces both times**, confirming the pattern below is
deterministic, not an artifact of a stale disk:

```
[t=0.4109] CMD Specify   op=03 params=[4F 20]        <- autoload's own FDC init (different params)
...autoload's own boot-sector-load Seeks/Read-IDs/Read-Data (t=0.77..1.24)...
[t=1.5142] CMD Specify   op=03 params=[DF 28]         <- rcbios bios_hw_init.c:210-212 (the ONLY
                                                          call site in the whole C source for this
                                                          exact byte sequence)
[t=1.5440] CMD Recalibrate op=07 params=[00]          <- bios_home()'s single fdc_recalibrate() call
                                                          (bios.c:1660, via wboot_c() at bios.c:837)
[t=1.5441] CMD Sense Interrupt Status  RESULT=[20 00] <- isr_floppy() (bios.c:2244) consuming the
                                                          recalibrate's completion IRQ. Normal —
                                                          ST0=0x20 is SEEK_END, IC=00 (normal term).
[t=1.6200] CMD Sense Interrupt Status  RESULT=[80]    <- ANOMALY: a SECOND FDC interrupt fires here,
                                                          80ms after the first, with NO intervening
                                                          command issued at all. isr_floppy() reacts
                                                          to it exactly as designed (MSR.CB clear ->
                                                          issue Sense Int), and gets back ST0=0x80
                                                          (IC=10, "Invalid Command" — the uPD765's
                                                          documented response when Sense Interrupt
                                                          Status is issued with no interrupt actually
                                                          pending). fdc_sense_int() (bios.c:388-395)
                                                          already handles this 1-byte-vs-2-byte case
                                                          correctly in software, so this by itself is
                                                          not fatal — but it proves isr_floppy() is
                                                          being invoked by SOMETHING with no real FDC
                                                          completion behind it.
[t=3.4275] CMD Specify   op=03 params=[DF 28]         <- ANOMALY: bios_hw_init.c's exact 3-byte
                                                          SPECIFY sequence (03,DF,28) appears AGAIN,
                                                          fully completed (all 3 bytes logged), 1.9s
                                                          later. bios_hw_init() has exactly ONE call
                                                          site (boot_entry.c:123, itself called only
                                                          once from coldboot()) and runs long before
                                                          any CCP/BDOS disk I/O — it should be
                                                          impossible for this byte sequence to recur.
[t=3.4406] UNKNOWN op=00 params=[] RESULT=[]          <- a 4th byte, 0x00, written to port 5 right
                                                          after — not a valid uPD765 opcode. Trace
                                                          ends here (matches the previously-located
                                                          hang PC 0xDA9E-0xDAA6, fdc_write()'s RQM/DIO
                                                          poll spinning forever afterward — the FDC
                                                          model has no defined response to an
                                                          unrecognized opcode, so RQM never re-asserts
                                                          the way the polling loop expects).
```

**Also notable**: no `Seek` command appears anywhere in the ~1.9s gap between
the legitimate recalibrate (t=1.544) and the second, anomalous Specify
(t=3.4275) — yet `wboot_c()`'s CCP/BDOS-load loop (`bios.c:837-860`, via
`xread()` -> `chktrk()`) sets `cpm_track=1` immediately after `bios_home()`
returns and would need to seek away from track 0 to read it. The complete
absence of a seek attempt for 1.9 emulated seconds, followed by a byte
sequence that is only supposed to exist inside `bios_hw_init()`, suggests
`chktrk()`/`xread()` never got as far as issuing the expected seek at all —
i.e. execution took a different path than the C source implies, possibly via
a corrupted/hijacked control-flow transfer (bad return address, stray jump
into `bios_hw_init()`'s bytes, or memory scribbled by the spurious-interrupt
handling) rather than a straightforward miscompile of the SPECIFY sequence
itself (which has already been ruled out — see the instruction-by-instruction
SDCC-vs-clang comparison above).

**Working hypothesis, now sharper but still unconfirmed**: a spurious/extra
FDC interrupt (cause unknown — candidates: CTC1 channel 3's mode/count
programming in `bios_hw_init.c:164-165` mis-configured relative to what the
uPD765's INTRQ->CTC-trigger wiring expects, or a MAME upd765a_device emulation
quirk around SEEK_END/recalibrate-already-at-track-0 timing) fires while
`isr_floppy()`'s flag-based rendezvous (`fdc_irq_arm()`/`fdc_irq_wait()`,
`bios.c:497-513`) is armed for an unrelated, not-yet-issued command elsewhere
in the boot path, causing that wait to return prematurely and the CPU to
proceed on stale/wrong state. This would explain both anomalies (the invalid
Sense Interrupt at t=1.62 AND the impossible-per-source-code repeat Specify at
t=3.4275) as two symptoms of the same underlying spurious-interrupt race,
rather than two unrelated bugs. **Not yet confirmed** — needs a PC/call-stack
trace at the exact moment the second Specify sequence begins (~t=3.42-3.43s)
to see whether execution is genuinely back inside `bios_hw_init()`'s compiled
code (stack/control-flow corruption) or whether it is executing unrelated
bytes that happen to coincide with the same opcode pattern by chance.

## Suggested next steps (updated)

1. **Highest priority given the new evidence**: PC/SP trace (reusing the
   `-autoboot_script` sampler approach from earlier this session) narrowly
   bracketing t=3.40-3.45s, to determine whether the CPU is really executing
   inside `bios_hw_init()` a second time (and if so, via what call path / what
   is on the stack) when the anomalous second Specify sequence is emitted.
2. Investigate whether CTC1 channel 3's `CFG.ctc_mode3`/`CFG.ctc_count3`
   values (`bios_hw_init.c:164-165`, programmed right after the SPECIFY
   sequence — i.e. AFTER the interrupt-generating hardware is live but BEFORE
   its own mode/count than the ISR expects) could cause the FDC->CTC->CPU
   interrupt chain to fire more often than once per real FDC completion.
3. Get an annotated SDCC assembly listing for `bios_hw_init.c` (via
   `zcc ... -a` or equivalent) and diff instruction-by-instruction against
   `clang/bios.clang.lis` for the DMA-mode/CTC-programming block immediately
   preceding the SPECIFY sequence. (Already done for the region up to and
   including the first SPECIFY call — ports and instruction sequence found
   identical; not yet done for the CTC3 programming that follows.)
4. Write a MAME Lua probe that reads the upd765 device's internal MSR state
   directly (`manager.machine.devices[":fdc"]` or similar, exact device path
   TBD) rather than inferring from CPU port reads, to see the actual stuck
   bit pattern and whether a genuine INTRQ assertion is visible at t=1.62 and
   t=3.44 or whether the ISR is being entered without INTRQ at all (pointing
   at an IVT/vector-table bug instead of an FDC-side spurious interrupt).
5. If (1)-(4) don't localize it, try compiling `bios_hw_init.c` at `-O0`
   with clang (bypassing all backend optimization passes) to see if the hang
   persists — would strongly implicate a specific optimization pass over a
   frontend/ABI issue.

---

## RESOLVED 2026-07-06 — root cause was LTO data-placement, not FDC/miscompile

The hang was NOT an FDC timing quirk, a spurious-interrupt race, or a codegen
miscompile. It was **`-flto` mis-placing two data sections** the linker script
anchors via per-object-file matchers:

1. `confi_on_disk[]` / `conv_tables[]` (`.boot_data 0x0080`) fell to generic
   `.rodata` at 0xE78D/0xE80D under LTO. `relocate_bios()` copies FROM these at
   coldboot expecting physical 0x0080/0x0100 (ROM-loaded Track 0), so it read
   uninitialised RAM into CFG. Garbage CTC config -> the spurious 2nd FDC
   interrupt (Sense-Int ST0=0x80 at t=1.62s) and phantom 2nd SPECIFY (t=3.43s)
   documented above were downstream symptoms, not causes.
2. `bios_jump_vector_table` (`.bios_jt` @ BIOSAD) also fell out of place ->
   `_jump_ccp` at 0xDA00 -> banner shows but CCP calls wrong entries -> no `A>`.

Fix: `__attribute__((section(...), used))` on all three symbols +
`KEEP(*(.boot_data))` / `KEEP(*(.bios_jt))` anchors in `rc700_bios.ld`.
`make mame-test COMPILER={clang,sdcc}` both boot to `A>`; clang 5906 B.
See memory `feedback_rcbios_no_lto_boot_placement.md` for the full mechanism.

Every "ruled out" and "still unknown" item above is explained by this single
root cause; the FDC model was behaving correctly the whole time given the
garbage config it was fed.
