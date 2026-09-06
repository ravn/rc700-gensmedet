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

## 2. Banner string is hard-coded and stale — RESOLVED 2026-06-04 (verified 2026-07-01)

The banner is now **auto-generated** from the build date + git hash
(rcbios `builddate.h` pattern, `clang/banner.h` with a `FORCE` dep).
Verified 2026-07-01: a fresh `make prom` stamps
`RC700 ROA375 CL 2026-07-01 01.23 61c5d78/ravn` (date + short hash + user),
and the only byte-delta between two builds is that timestamp.  The old
hard-coded `"RC700 CL 2026-04-15 12.15/ravn"` is gone.  Closed.

## 3. MAME path was wrong (FIXED 2026-05-04)

`MAME = /Users/ravn/git/mame` — pre-workspace-restructuring
location, no longer exists.  Fixed to
`MAME ?= $(CURDIR)/../../mame` in commit `b6c797d` 2026-05-04.

## 4. PROM1 presence check reads RAM (not the PROM) in the mid-read drive-select failure path — OPEN (possibly inherited from the original ROA375 ROM)

**Status:** OPEN, latent edge case.  Filed 2026-07-01 during the ID-COMAL boot
investigation.

`prom1_if_present()` (`rom.c`) decides whether to run the PROM1 line program by
checking the `" RC702"` signature at **0x2002** (plus the SW1 S02 enable gate):

```c
if ((read_sw1() & 0x02) == 0 &&
    compare_6bytes((const byte *) 0x2002, msg_rc702) == 0)
    jump_to(*(word *)0x2000);
```

This is correct in the two common failure paths that call it (`rom.c:856`
drive-not-ready, `rom.c:869` format-undetectable) — both run **before**
`prom_disable()` (`rom.c:873`), so the PROM1 ROM overlay at 0x2000 is still
mapped and `compare_6bytes(0x2002, ...)` reads the real PROM.

**The bug:** the third call site, `rom.c:760` inside
`fdc_read_data_from_current_location()`, fires on a drive-select failure
(`fdc_select_drive_cylinder_head() == 1`) that happens **during** the data read
— i.e. from the read loop at `rom.c:875-881`, which runs **after**
`prom_disable()`.  `prom_disable()` turns off *both* ROM overlays (PROM0 @ 0x0000
and PROM1 @ 0x2000, via port 0x18 RAMEN), so by then 0x2000-0x2007 is **RAM**,
not the PROM1 ROM.  The presence check therefore reads whatever the partial
floppy read (or power-on state) left in RAM at 0x2002, not the actual PROM1
contents.

**Impact:** low-probability latent defect, only in the mid-read drive-select
failure path and only when SW1 S02 is enabled:
- false positive — `JP (0x2000)` into RAM if it coincidentally holds `" RC702"`
  at 0x2002 (unlikely to match exactly);
- false negative — a genuinely socketed PROM1 is missed because its ROM is no
  longer mapped.

**Possibly inherited:** the C autoload is a reconstruction of the original ROA375
ROM; this ordering (prom-disable before the main read, prom1 fallback reachable
from inside the read) may reflect the original ROM's structure rather than a
rewrite regression — worth checking the roa375 disassembly before "fixing".

**Fix options (deferred):** re-enable the PROM1 overlay around the 0x2002 check
in the 760 path, or cache the PROM1-present result from before `prom_disable()`
and reuse it in all three paths.

**Pointers:** `rom.c` `prom1_if_present` (~740), call sites 760 / 856 / 869,
`prom_disable()` at 873; overlay semantics in `rc700-gensmedet/CLAUDE.md`
(port 0x18 RAMEN disables both PROM0 and PROM1).

## 5. `make mame`'s `EXPECT_BANNER` check fires too late — always FAILs even on a correct boot (recurrence of bug #1's harness class, different symptom) — OPEN

**Status:** OPEN, found 2026-09-06 while verifying the `ravn/llvm-z80`
upstream-merge branch (`merge-upstream-2026-09-05`) didn't regress the
autoload boot path.

**Symptom:** `make mame COMPILER=clang` reports
`FAIL: booted but wrong banner (expected 'RC700 ROA375 CL')`, with the
captured display showing DRI CP/M's own sign-on
(`RC700   56k CP/M vers.2.2   rel. 2.3`) at the canonical BIOS base
0xF800 — **not** autoload's banner. This reproduces identically with
both COMPILER=clang and COMPILER=sdcc, so it is unrelated to any
compiler change.

**Root cause (confirmed with a frame-by-frame screen trace via a patched
`mame_boot_test.lua`, dumping `screen_text()` every 10 frames instead of
only at the "A>" check):** autoload's banner **is** correctly displayed —
frames 30-70 (display base 0x7830, ~0.6-1.4s emulated) show
`RC700 ROA375 CL 2026-09-06 11.06 2951f96/ravn ... SW1 12345678: 00000000`
verbatim. Around frame 80 the display base switches to 0xF800 as DRI
CP/M's cold-boot code (loaded from Track 0, see "CP/M" row in
`BOOT_SEQUENCE.md`'s disk-boot-variants table) takes over the screen and
writes its own sign-on. `mame_boot_test.lua`'s `EXPECT_BANNER` match only
runs at the moment `screen_find("A>")` first succeeds — by then CP/M has
already overwritten the banner autoload wrote, so the check can never see
it. This is a **test-timing bug**, structurally the same class as bug #1
above (the harness looks at the wrong moment/place), but a different
manifestation: bug #1 was fixed by scanning both display bases; this one
additionally needs the *banner match* to run **before** CP/M's handoff,
not only at the final `A>` check.

**Fix options (deferred — no code change made yet, pending go-ahead):**
record whether `EXPECT_BANNER` was ever seen on **any** frame (not just
the final one) before deciding pass/fail, e.g. latch a `banner_seen`
flag the first time `screen_find(EXPECT_BANNER)` matches at the
DMA-derived base, independent of the later `A>`/0xF800 check.

**Pointers:** `autoload-in-c/mame_boot_test.lua` (`screen_find`,
`finish()`), `autoload-in-c/Makefile` `mame:` target (~line 165, sets
`EXPECT` per compiler), `autoload-in-c/BOOT_SEQUENCE.md` "CP/M —
`" RC702"` at offset 0x0008" section (documents the Track-0 handoff that
overwrites the banner).
