# MAME build: regnecentralend vs mame binary naming drift

**Status:** TODO -- low priority, documentation/Makefile cleanup.

## Symptom

The historical MAME binary on this workstation is named
`/Users/ravn/z80/mame/regnecentralend` (~87 MB) -- the cpnos-in-c
Makefile recipes and `scripts/mame_capture.sh` default look it up
by that name.

The current MAME source tree (`/Users/ravn/z80/mame`, ravn/mame
master) when built with `make OSD=sdl SOURCES=src/mame/regnecentralen/
rc702.cpp REGENIE=1` emits the binary as plain `mame` (~74 MB).
After a fresh build there is no `regnecentralend` -- subsequent
test recipes that look for it run the OLD stale binary, miss the
recompile, and silently report results from prior source state.

## What happened this session

Session 73j-locale's MAME col-80 fix:

  1. Edited `src/mame/regnecentralen/rc702.cpp` for set_size 560.
  2. `make ... REGENIE=1` succeeded; produced `mame` binary.
  3. Test recipes ran `regnecentralend` (still the OLD binary from
     15:11) -- captured AVIs were the old 568x212 width, col 80
     still clipped.
  4. Diagnosis: probe AVI from regnecentralend showed source dim
     unchanged.  Found `mame` (~74 MB at 20:56) next to old
     `regnecentralend` (~87 MB at 15:11).
  5. Copied `mame` -> `regnecentralend` manually; subsequent
     captures showed 584x212 source = driver fix live.

The unsigned-binary swap is fragile: another rebuild produces `mame`
again, and tests will run stale `regnecentralend` until the swap
happens.

## Fixes

Option A: change cpnos-in-c Makefile + `scripts/mame_capture.sh`
default to look up `mame` first, fall back to `regnecentralend`.
Cost: 2 lines of make, 2 lines of shell.

Option B: rename `regnecentralend` -> `mame` in all callers, drop
the legacy alias entirely.  Requires editing recipes in cpnos-in-c
and possibly other subprojects.

Option C: change the MAME build target in ravn/mame fork to emit
`regnecentralend` (premake5.lua / scripts).  Most invasive --
diverges from MAME upstream conventions, but means historical
recipes "just work" forever.

Recommendation: Option A.  Cheapest, most transparent for someone
reading the recipes later.

## When

Whenever the MAME source tree is touched again.  Currently no
active blocker -- the manual binary swap works once you know to do
it (memory rule `feedback_mame_osd_sdl` already touches the
adjacent OSD=sdl-not-sdl3 gotcha).
