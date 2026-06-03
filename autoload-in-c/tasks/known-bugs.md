# autoload-in-c known bugs

## 1. C autoload hangs in FDC detect, never hands off to BIOS

**Status:** RESOLVED / not reproducing (2026-06-03 — final).
ravn/llvm-z80#215 filed then CLOSED the same day.

**Verified:** autoload-in-c floppy boot reaches `A>` (CP/M loaded) on BOTH
the standard rcbios test disk (`bios_c_test.imd`) AND the unpatched
`SW1711-I8.imd` (original DRI rel. 2.3 BIOS), on the d0a7dcd MAME.  In
under 5s of emulated time the BIOS reaches `A>` and writes
"RC700 56k CP/M vers.2.2 rel. 2.3" + cursor at the canonical BIOS display
address 0xF800.

**The "hang" was a harness limitation, not a system bug.**  Two layered
issues in `mame_boot_test.lua` previously masked the success:

  1. **`screen:snapshot()` with no arg** — newer MAME's lua API requires a
     filename string; old call signature throws "stack index 2, expected
     string, received no value" ~20× per run and made the harness look
     broken.  Fixed: `pcall + filename`.

  2. **Single-display-base scan** — the lua derived the live display base
     from DMA ch2 writes (correctly capturing autoload's 0x7A00 framebuffer)
     and ONLY scanned there.  Once the DRI BIOS takes over it uses its own
     canonical display at 0xF800, but our DMA tap doesn't always capture
     the BIOS reprogramming cleanly (different write order; 8237
     flip-flop sequence).  So `A>` was on screen at 0xF800 from t<5s,
     but the lua was looking at 0x7A00 and reported "no A>" for 45s.
     Fixed: `screen_find()` now scans BOTH the DMA-derived base AND 0xF800.

The original 2026-05-04 codegen analysis below was probably accurate at
the time (the C source built then to a hanging binary); the issue does
not reproduce with current clang (build-macos, 2026-05-31) on either disk.

**Symptom:** with `mame/roms/rc702/roa375.ic66` set to autoload-in-c's
`clang/prom.bin` (padded to 4096 B, install via `make prom`):

  - PROM display at `0x7A00` shows the autoload banner: ` RC700 CL
    2026-04-15 12.15/ravn` (build-date string in `boot_rom.c` is
    hard-coded and stale; not the cause of this bug).
  - BIOS display at `0xF800` stays blank (BIOS never starts).
  - PC stuck in `_fdc_detect_sector_size_and_density` (LMA `0x02D6`
    in PROM 0; VMA `0x626E` in the RAM-relocated `.text`).
  - `mame_boot_test.lua` reports `FAIL: PROM error (see display)`
    after 10 sim-seconds (any non-blank text at `0x7A00` past the
    initial 10s window counts as PROM error per the harness).

**Comparison: hand-assembled `roa375/roa375.rom` (a136b144) WORKS.**
Same disk image, same MAME version, same FDC chip emulation.
Boots through to the BIOS prompt:

```
RC700 56k CP/M 2.2 C-bios/clang 2026-05-04 02:31
SIO-B debugging enabled (38400 8N1)
```

So the bug is either in `autoload-in-c/rom.c` (the C source) OR in
`llvm-z80`'s codegen for that source.  Not in MAME or the disk
image.

**Source unchanged since April 26.**  `git log autoload-in-c/rom.c
autoload-in-c/rom.h autoload-in-c/boot_rom.c autoload-in-c/intvec.c`
shows no commits since Apr 25.  The compiled `prom.bin` from
April 26 (1832 B) presumably worked then; the same C source
rebuilt today (1832 B) does not.  Therefore the regression is in
`llvm-z80` codegen between April 26 and today.

**Optimization-level invariant:** rebuilt with `-Oz`, `-O1`, and
`-O0` -- all three produce broken builds (different symptoms, all
non-booting).  -Oz and -O1 hang at PC=0x02D6 (in
`_fdc_detect_sector_size_and_density`); -O0 jumps PC randomly
through RAM (different crash mode).  Bug is NOT in optimization
passes alone; some lower-level codegen change affects all opt
levels.

**PC trajectory comparison (assembly autoload vs clang autoload),
sampled every 0.5 sim seconds:**

```
                 t=0.5s    t=1.0s   t=1.5s   t=2.0s   t=2.5s   t=3.0s+
assembly roa375  0x76B9    0x76B6   0x76B7   0x02B0   0xE821   0xDA8E (BIOS code)
clang -Oz prom   0x6051    0x6052   0x02B0   0x02D6   0x02D6   0x02D6 (stuck)
```

Both autoloads pass through PC=0x02B0 (in PROM 0 region, executing
the LMA copy of `_fdc_get_result_bytes`).  The assembly version
transitions OUT (to 0xE821 = BIOS code in upper RAM); the clang
version gets stuck at 0x02D6 (= `_fdc_detect_sector_size_and_density`
+ 0x09, just after a call returns).

**I/O port trace:** clang autoload writes ~108 chargen events
(loading SEM702 font), then stops doing I/O writes after t=0.04s.
Assembly autoload also goes silent on I/O writes after t=0.98s
(both continue computing without writing for some time).  The function
involved is:

```c
byte fdc_detect_sector_size_and_density(void) {
    is_mfm = 0;
    while (1) {
        if (fdc_select_drive_cylinder_head() != 0) return 1;
        dma_transfer_size = 4;
        if (fdc_get_result_bytes(FDC_READ_ID, 1) == 0) break;
        if (is_mfm) return 1;
        is_mfm = 1; /* switch to MFM and retry */
    }
    fdc_cmd.size_shift = fdc_result.size_code & 0b00000111;
    lookup_sectors_and_gap3_for_current_track();
    calc_size_of_current_track();
    return 0;
}
```

Likely failure modes (not yet diagnosed):

  1. `fdc_select_drive_cylinder_head` (which calls `fdc_seek` →
     `verify_seek_result`) returns non-zero → outer caller loops on
     this function expecting eventual success.
  2. Some interrupt-handler / IM 2 vector setup is wrong, causing
     the FDC interrupt callback to run incorrectly or never.
  3. The DMA / FDC port write sequence diverges from the
     hand-assembled ROA375.

To diagnose (next session):

  1. **Bisect llvm-z80** between commit `703d96f07a06` (last
     pre-April-26 Z80 backend commit, presumed good) and current
     HEAD.  The naive checkout-Z80-only-dir approach FAILED
     because the Z80 backend uses LLVM core APIs that have drifted
     since April 26 -- a partial checkout doesn't compile against
     current LLVM core.  Cleaner approach: bisect with full
     `git checkout <commit>` of the entire llvm-z80 tree (slower
     because of full LLVM rebuild per iteration, but works).

     Commits to bisect (oldest first):
     - 2c9395f645a2 EXX shadow-bank deletion
     - 95d2cd718a4f AsmParser ex-af-af
     - bbd882f2f56d LDIR/LDDR BC=0 guard (#63)
     - 41fdb83a9c6a #105 doc
     - 3ef14efcbafb in-mem INC/DEC H/L liveness (#104)
     - d7505c8e8caa #85 chain peephole H/L liveness (#107)
     - 3dc83747a1b5 runtime BC==0 guard for variable-size memcpy (#105)
     - fa6cc884907c IX/IY in large-offset spill (#28)
     - 8b268e18eedc #38 doc
     - 90687fc74d6d sequential DJNZ counter split (#94)
     - e9564bf0a9ef BCReg + i16 counter (#99)
     - 5748dddf96c8 IX/IY un-reservation diagnosis (session 40)
     - 28613369fa08 GR16NoIR + LSHR16/ASHR16 (#112)
     - 5f84730bac84 GR16NoIR on CMP16/CMP_ZERO16 (#113)
     - 33ceae174673 SBC HL,rr ISel attempt (#116, reverted)
     - f1eece6e0c55 post-RA peephole for i16 EQ/NE (#116)
     - e4b3496a81b1 GR16NoIR on XOR_CMP_*16 (#113)
     - c8d2dbedff90 #121 IR16 fallback drop

  2. **Asm diff:** once a regressing commit is identified, compare
     `clang/prom.lis` from before vs after.  Look for changes in
     `_fdc_detect_sector_size_and_density` and its callees.

  3. **Port trace:** capture FDC port writes via Lua
     `install_write_tap(0x04, 0x05, ...)` for both PROMs on the
     same disk and diff (see `feedback_lua_no_port_reads` for
     caveats).  Initial trace already done -- clang version stops
     doing I/O writes at t=0.04s while assembly version keeps
     going.  The clang version's chargen-load completes; FDC
     init / detect loop then does no port writes (busy-loop on
     CPU-only state, possibly polling a memory variable that
     never updates, suggesting an ISR isn't firing or its handler
     isn't updating the variable).

**Workaround:** for any work that needs rcbios standalone MAME
boot (the value-oracle MAME path -- see
`llvm-z80/tasks/lessons-2026-05-04-structural-fix-failures.md`),
install the assembly ROA375 instead:

```
cd rc700-gensmedet/rcbios-in-c && make mame-roms-rcbios
```

This is the working PROM.  Continue using autoload-in-c only for
its own development work (and for now, expect it to hang).

## 2. Banner string is hard-coded and stale

`boot_rom.c` defines:

```c
const char banner_string[] = "RC700 CL 2026-04-15 12.15/ravn";
```

The build date is not auto-generated.  Should be regenerated from
`builddate.h` (parallel to rcbios-in-c's pattern) or removed if
the autoload PROM doesn't need a build date stamp.  Cosmetic, not
a blocker.

## 3. MAME path was wrong (FIXED 2026-05-04)

`MAME = /Users/ravn/git/mame` — pre-workspace-restructuring
location, no longer exists.  Fixed to
`MAME ?= $(CURDIR)/../../mame` in commit `b6c797d` 2026-05-04.
