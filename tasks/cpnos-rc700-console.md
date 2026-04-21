# CP/NOS RC700 console — WIP handover (branch `cpnos-rc700-console`)

## Goal

Extend CP/NOS `impl_conout` from the minimal CR/LF/FF stub to the full
RC700 control-character set — except background-attribute codes
(0x13/0x14/0x15) per spec.  Then add an 8" drive (single, extensible)
in a follow-up.

## Status

**Not booting.**  rc700_console.c is written and wired; linker split
is in place; MAME patched for `prom1.ic65`; but the memory-layout
migration (IVT move, stack move, two-LMA copy) is incomplete so MAME
exits with PC stuck in PROM0.

Tree state on branch `cpnos-rc700-console` relative to `main`:

    M  cpnos-rom/Makefile          (adds rc700_console.o to OBJS)
    M  cpnos-rom/cpnos_rom.ld      (two-section split; LMA split PROM0/PROM1)
    M  cpnos-rom/resident.c        (impl_conout delegates to rc700_console)
    ?? cpnos-rom/rc700_console.c   (new — full state machine, ~750 B)
    ?? cpnos-rom/rc700_console.h   (new — 2-entry API)

## The memory-layout problem

The RC700 console state machine is ~750 B of code.  The existing CP/NOS
resident budget (`RESIDENT` region 0xF200..0xF7FF, 1536 B) is already
~690 B full; adding 750 B overflows by ~374 B.

Can't grow upward (display RAM at 0xF800 is a hard wall).  Growing
downward to 0xF000 frees 512 B but:
- overlaps the IM2 IVT at 0xF100..0xF123
- collides with `fill_trap(0xED20, 0xF100)` + stack at 0xF200 (stack
  grows down through the new pre-JT region)

## Chosen plan (unfinished)

Two-section LMA split so PROM0 stays stable as console features evolve:

- `.resident_pre` at VMA 0xF000..0xF1FF, LMA in PROM1 (0x2000)
- `.resident` at VMA 0xF200..0xF7FF (cpbios.s JT-at-0xF200 ABI intact),
  LMA in PROM0 (unchanged location)
- Two separate `memcpy`s in `cpnos_main` (one per section)
- Move IM2 IVT from 0xF100 to 0xEE00 (page-aligned, in current scratch
  gap between BSS tail 0xED36 and `.resident_pre` VMA 0xF000)
- Move stack init 0xF200 → 0xF000 (reset.s); stack area becomes
  0xEE24..0xF000 = 476 B (was 1.2 KB)
- MAME: `ROM_LOAD_OPTIONAL("prom1.ic65")` so `prom1.bin` gets picked up
  at emulator start

## Done (on branch)

- [x] rc700_console.c + .h — full state machine, RC700 control set
      minus background-attribute codes.  Uses runtime.s memcpy/memset/
      memmove.
- [x] resident.c: impl_conout delegates to rc700_console_putc
- [x] cpnos_rom.ld: MEMORY grown 0xF000..0xF7FF (0x800), two output
      sections with separate LMAs + symbols, `__scratch_bss_end`
      guard tightened to 0xEE00
- [x] Makefile: rc700_console.o in OBJS + compile rule
- [x] mame/rc702.cpp: prom1 region switched to ROM_LOAD_OPTIONAL

## TODO to land the branch

1. init.c: `IVT_ADDR` 0xF100 → 0xEE00; trim `fill_trap` range to
   0xED20..0xEE00 (was ..0xF100)
2. reset.s: `ld sp, #0xF000` (was `#0xF200`)
3. cpnos_main.c: two memcpy calls instead of one, using the new
   `_resident_pre_{lma,start,end}` + existing `_resident_{lma,start,end}`
4. Makefile cpnos-install: also write `clang/prom1.bin` to
   `$(MAME)/roms/rc702/prom1.ic65` so MAME picks it up
5. Rebuild MAME once (ROM_LOAD_OPTIONAL change)
6. `make cpnos cpnos-netboot` — confirm PASS (A> prompt)
7. Run existing smoke plan steps 1-7 unchanged to ensure no regression
8. Then the actual test deliverable:
   - `cpnos-rom/testutil/rc700_console_test.c` — CP/M .COM that drives
     every code (CR, LF, FF, home, clear, eol/eos, up/down/left/right,
     tab, bell, XY addressing, insert/delete line) through stdout /
     BDOS fn 2 with deterministic output state between steps
   - Lua gate that screenshots the 8275 display at known checkpoints
   - compare against expected bitmaps

## Risks / unknowns

- **Stack budget**: shrinks 1.2 KB → 476 B.  Observed `SP=0xE199` at
  session #27 during deep NDOS I/O — this was well below the old stack
  floor, implying NDOS/CCP may use far more stack than the nominal
  reservation.  If this reproduces with the new layout, stack will
  clobber IVT (0xEE00..0xEE23) or scratch BSS (0xEC00..0xED35).
  Mitigation ideas:
  - relocate stack to 0x2000..0x2800 gap (PROM1 region, RAM after
    PROM-disable) — 2 KB stack, plenty
  - relocate stack to 0x0800..0x1FFF (6 KB between-PROMs gap) — even
    more; cost is TPA ceiling if CP/M apps ever use low RAM (they
    don't before CCP+)
- **PROM1 burn cost on physical HW**: any rc700_console change now
  requires burning PROM1.  User has flagged this as expensive.
- **IVT move correctness**: need to re-verify I-register load
  (currently `IVT_ADDR >> 8`, becomes 0xEE) and vector-low-byte
  offsets (PIO-A vec 0x20 → `IVT[16] = IVT_ADDR + 0x20 = 0xEE20`).

## Alternative path (future): COM-file boot loader for physical HW

Per user suggestion: a CP/M `.COM` file that loads into TPA, DIs
interrupts, memcpys the PROM0 + PROM1 payloads to 0x0000..0x07FF /
0x2000..0x27FF, then `JP 0x0000`.  Let physical RC702 test CP/NOS
without burning PROMs between edits.  Build target could be
`cpnos-rom/testutil/cpnos_loader.com`.

## Future path: CP/NOS as a PROM1 add-on to the ROA375 autoloader

Per user 2026-04-21: if we can condense CP/NOS to a single PROM, put
it in **PROM1** so the existing ROA375 autoloader in PROM0 stays
untouched and detects/boots into it.  This preserves the stock
physical PROM0 forever — only PROM1 ever gets reburned.

Design sketch:
- ROA375 stays at 0x0000..0x07FF (unchanged).
- CP/NOS payload fits in PROM1 0x2000..0x27FF.
- ROA375 gains (or already has?) a detection sequence: check PROM1
  first for a magic byte / signature; if present, jump there instead
  of its normal floppy-boot sequence.
- CP/NOS-in-PROM1 would need to be completely self-contained in 2 KB
  — smaller than the current 2 KB init + 2 KB resident layout.  The
  resident bulk (RC700 console, SNIOS, JT) still goes to RAM, but its
  source image now streams from PROM1 alone.
- This requires ripping out most of the current init flow and
  compressing the "copy + PROM-disable + jump to CCP" sequence.

Issue count (I/J/...) deferred to its own task doc when pursued.

## Issue: MAME patch lives in a different repo

The `ROM_LOAD_OPTIONAL("prom1.ic65")` change is in `/Users/ravn/git/mame`
on ravn/mame fork.  Commit it there separately before landing this
branch, otherwise whoever picks up CI/physical build will be confused.

## Open issues discovered this session

- **Issue Q**: `fill_trap` + stack interaction — the trap fill covers
  0xED20..0xF100, and the stack starts at 0xF200 growing down.  Under
  the old layout these didn't overlap; any future re-layout must check
  that `fill_trap` never writes over the active call stack.
- **Issue R**: PROM0/PROM1 LMA split decouples physical reburns but
  the Makefile cpnos-install target only pushes PROM0 to MAME's
  `roa375.ic66`.  Needs the prom1.ic65 step (TODO #4 above) plus a
  physical-burn workflow that produces two .bin files.
- **Issue S**: cpbios.s hardcodes BIOS JT slots at 0xF206, 0xF209,
  0xF20C, 0xF20F, ... and SNIOS JT at 0xF233.  Any layout change that
  moves the JT requires rebuilding cpnos-build's ccp/ndos package as
  well.  The two-section approach preserves these offsets — keep it
  that way.
