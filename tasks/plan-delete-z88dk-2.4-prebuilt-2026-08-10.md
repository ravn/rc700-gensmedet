# Plan / blocker — delete the z88dk 2.4 prebuilt, keep only the dev-fork build tree

User request (2026-08-10, da): "vi har z88dk 2.4 i downloadudgave i projektet. det skal
slettes og kun vores z88dk byggetræ forblive" — delete the pinned stock z88dk 2.4
download, keep only the workspace dev fork at `/Users/ravn/z80/z88dk`.

## What the prebuilt is (KNOWN — verified this session)
- Dir: `rc700-gensmedet/z88dk/` — 479 MB on disk. Git-tracked: only 3 files
  (`.gitignore`, `Makefile`, `download/z88dk-osx-2.4.zip`); `bin`/`lib`/`include` are
  symlinks into the gitignored unpacked `download/z88dk/`. `make` re-downloads/unpacks.
- Provides stock `zcc`, `zsdcc`, `z80asm`, `sccz80`, and — critically — the SDCC
  `_DEVELOPMENT` libs `libsrc/_DEVELOPMENT/lib/{sdcc_iy,sdcc_ix,sccz80}/z80.lib`.

## References to repoint before deletion (KNOWN)
- `cpnos-in-c/Makefile:154` — `Z88DK_HOME ?= $(firstword $(wildcard ../z88dk)
  $(wildcard ../../z88dk))` (prefers prebuilt, falls back to dev fork).
- `cpnos-in-c/Makefile:1755` — `Z88DK_PREBUILT = $(CURDIR)/../z88dk` (used by the
  CLASSIC `qsort-build` target; classic path works on the dev fork).
- `rcbios-in-c/sdcc/Makefile:17` — `Z88DK_HOME ?= $(firstword $(wildcard
  ../../../z88dk))` — prebuilt ONLY, no dev-fork fallback; empties if deleted.
- `autoload-in-c/Makefile:296-297`, `cpnos-in-c/Makefile:1993-1994` reference
  `../../z88dk/src/zx0/...` — already the DEV FORK; unaffected.
- The `tasks/compiler-comparison-corpus/*.sh` scripts already point at
  `/Users/ravn/z80/z88dk` (dev fork); unaffected.

## BLOCKER (verified, load-bearing)
The dev-fork build tree does **not** ship the classic SDCC `z80.lib`:
- Present only in prebuilt: `.../download/z88dk/libsrc/_DEVELOPMENT/lib/sdcc_iy/z80.lib`
  (+ `sdcc_ix`, `sccz80`).
- Dev fork `libsrc/_DEVELOPMENT/lib/` is empty/unbuilt; dev-fork `lib/clibs/` has the
  CLASSIC libs but not the `-clib=sdcc_iy` newlib `z80.lib`.
- Production SDCC firmware builds link `-clib=sdcc_iy`:
  `rcbios-in-c/sdcc/Makefile:31` (`+z80 -clib=sdcc_iy`), `cpnos-in-c/Makefile:198`
  (`-compiler=sdcc -clib=sdcc_iy`).
So deleting the prebuilt **breaks** the rcbios-in-c/sdcc and cpnos-in-c SDCC lanes.
The in-Makefile comment at `cpnos-in-c/Makefile:148-153` already documents this:
the dev fork "does NOT ship the classic sdcc z80.lib ... linking there fails with
'file not found: z80.lib'."

## Resolution paths (needs a decision — real trade-offs)
- **A. Make the dev fork self-sufficient, then delete.** `z88dk/build.sh` builds
  `libsrc/newlib` + `include/_DEVELOPMENT` (build.sh:201-202) → would produce
  `sdcc_iy/z80.lib`. But it is a full from-source z88dk library rebuild: heavy,
  uncertain on this macOS host, and it would OVERWRITE the dev-fork libs that were
  just verified good for the #54 fix. Recommended IF SDCC must stay buildable.
- **B. Retire the SDCC lane, delete prebuilt, repoint classic/zx0 to dev fork.**
  clang is the production path (CLAUDE.md: clang beats SDCC on all targets), but SDCC
  is still the documented size-comparison oracle, so this drops a documented
  capability. Low effort, but a real regression to SDCC tooling.
- **C. Keep the prebuilt.** Rejects the request.

## Decision status
Not executed. The destructive deletion is blocked on a genuine, verified load-bearing
dependency; the clean fix (A) is a heavy/uncertain rebuild that risks the known-good
dev-fork state, and (B) silently retires the SDCC oracle. With the user unavailable,
proceeding would be acting on an unfounded assumption about whether SDCC may be
retired — so this is left for the user to choose (A vs B). The #54 work in this
session is independent and complete.

---

## RESOLVED + EXECUTED (2026-08-10) — blocker cleared via Docker (user: "du kan køre z88dk 2.4 i docker")

The blocker (dev fork lacks `sdcc_iy/z80.lib`) is resolved by running z88dk 2.4
in Docker. Verified facts (KNOWN, this session):

- The retired filesystem prebuilt was NOT stable "2.4" — its `zcc` reports
  `v23854-4d530b6eb7-20251002` (a z88dk nightly, commit **4d530b6e**).
- Docker Hub `z88dk/z88dk:2.4` reports `v1-4d530b6e-20251001` — **same commit
  4d530b6e**, bundling the same SDCC 4.5.0 #15242. Byte-compare of a real
  SDCC compile (asm) between the two toolchains: **CODE IDENTICAL** (only the
  `; Version ... (Mac OS X ppc)` vs `(Linux)` banner comment differs).
- Newer official images (`latest`=2026-08-09, nightlies) do NOT ship
  `sdcc_iy/z80.lib` (only `sccz80` + `sdcc_ix`), so `-clib=sdcc_iy` would fail
  there -> stay pinned to `z88dk/z88dk:2.4`.
- End-to-end proof: built the cpnos `prom1-lineprog` SDCC target through Docker
  vs the filesystem prebuilt; linker map byte-identical, output bins identical
  except the embedded build **timestamp** (`00:54` vs `01:00`, same git rev
  `1b1dff1+`). Both reach the same known stack-room guard at `0xF62A`.

### Changes made
- `cpnos-in-c/Makefile` (SDCC lane): detect a usable NATIVE z88dk by the
  presence of `libsrc/_DEVELOPMENT/lib/sdcc_iy/z80.lib` (not merely `bin/zcc`,
  which the lib-less dev fork has); otherwise build via `z88dk:2.4` Docker.
  Docker now mounts the repo ROOT and makes `-w` TRACK the recipe's `$PWD`
  (`/src$${PWD\#$(REPO_ROOT)}`, `#` escaped from make comment) so `cd`-based
  link recipes resolve. `OBJCOPY` uses a branch-specific `APPMAKE`
  (`z88dk-appmake` bare in Docker). `qsort-build` (classic sccz80) now falls
  back to the dev fork.
- `rcbios-in-c/sdcc/Makefile`: same `sdcc_iy/z80.lib` detection -> Docker
  (it pointed at the lib-less dev fork before, so this is a fix, not a regress).
- Deleted `rc700-gensmedet/z88dk/` (479 MB): `git rm` of the 3 tracked files
  (`.gitignore`, `Makefile`, `download/z88dk-osx-2.4.zip`, staged not committed)
  + `rm -rf` of the gitignored unpacked tree.
- Docs: workspace `CLAUDE.md` layout + `docs/z88dk_docker_rebuild.md` updated
  (retirement + pull-and-tag route + "stay pinned to 2.4").

### Post-deletion verification (all PASS)
- cpnos SDCC: `make -n` shows `docker run`; full build auto-selects Docker,
  reaches the identical known stack guard (`0xF62A`).
- cpnos CLANG (production): `PROM1 line program: 2012 / 2048 B`, EXIT 0 —
  unaffected (uses dev-fork zx0 + native llvm-z80 clang).
- qsort-build classic sccz80: builds on the dev fork (QSORT_Z88.COM produced).
- No remaining Makefile/script reference resolves to the deleted prebuilt path.

### Prerequisite for a fresh checkout / CI
The `z88dk:2.4` local Docker tag must exist. Obtain via
`docker pull z88dk/z88dk:2.4 && docker tag z88dk/z88dk:2.4 z88dk:2.4`, or build
from the fork (`docs/z88dk_docker_rebuild.md`). The image is amd64-only ->
runs under QEMU emulation on Apple Silicon (slower, but output is identical).

---

## FUTURE WORK (på sigt) — migrate off sdcc_iy to the newer-image lib variant

User request 2026-08-10: investigate whether the lib variant shipped in a
*current* Docker image can replace the `sdcc_iy` libs we depend on today, so we
are no longer pinned to `z88dk/z88dk:2.4`.

Background (verified this session):
- Production firmware links `-clib=sdcc_iy` (cpnos-in-c/Makefile, rcbios-in-c/
  sdcc/Makefile). `sdcc_iy` == SDCC with **IY reserved / IX as frame pointer**.
- Only `z88dk/z88dk:2.4` (commit 4d530b6e) ships a linkable `sdcc_iy` target
  library. `latest` (v1-5ba9edb1-20260809) and the weekly nightlies ship
  `sccz80` + **`sdcc_ix`** only; their `sdcc_iy` tree has just per-target
  source-object dirs, no `cpm.lib` -> `-clib=sdcc_iy` there exits 0 but emits a
  **0-byte binary** (false pass; see docs/z88dk_docker_rebuild.md).

The investigation (do NOT start until scheduled):
1. Determine WHY newer official images dropped the built `sdcc_iy` target lib
   (upstream build-matrix change? deliberate? ask on z88dk, or diff the image
   build scripts). If it's an image-packaging omission we could get it restored
   upstream, that may be the cheapest fix (keeps `-clib=sdcc_iy`).
2. Else evaluate switching production to **`-clib=sdcc_ix`** (IX reserved /
   IY as frame pointer), which newer images DO ship:
   - Rebuild cpnos-in-c + rcbios-in-c SDCC lanes with `sdcc_ix`; compare code
     size vs the current sdcc_iy baselines (cpnos 2151 B SDCC; BIOS 6103 B).
   - Re-verify correctness: full runtime oracle + **MAME boot gate** (both
     PROMs) — ABI/frame-pointer register change is behaviour-affecting, so a
     clean compile is NOT proof (building != behaving).
   - Check the rc700 asm glue / any hand-written asm that assumes IY-free vs
     IX-free conventions.
3. Decision criteria: only migrate if sdcc_ix is size/behaviour-neutral (or
   better) AND unblocks tracking newer z88dk images. Otherwise stay pinned to
   z88dk/z88dk:2.4 (current, verified-good state).

Note: production firmware is CLANG, not SDCC — the SDCC lanes are the
comparison oracle. So this migration affects the oracle toolchain, not the
shipped binaries; lower urgency, hence "på sigt".
