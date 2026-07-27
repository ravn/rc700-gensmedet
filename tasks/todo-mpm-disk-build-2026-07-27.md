# Make the tailored MP/M disks a first-class build (2026-07-27)

Goal (user): the MP/M-disk customization should be BUILT reproducibly on
equal footing with the other targets, not ad-hoc. Tailored disks must NOT be
in git; regenerate on demand. Frozen input = the committed prebuilt base
(MP/M II + CP/NET server); build only the delta into gitignored `local/`.

## Root cause of the recurring `library/` dirt (found 2026-07-27)

Two build/test steps write straight into the git-tracked
`z80pack/cpmsim/disks/library/` base disks instead of `disks/local/`:
1. `cpnos-in-c/Makefile: cpnos-disk-install` (+ `-with-locale`) — stages
   `cpnos.img` into `library/mpm-net2-1.dsk`.
2. `cpnos-in-c/Makefile: stage-drivei-tools` — `DRIVEI_DSK` points at
   `library/mpm-net2-drivei.dsk`.

Dirt verified: boot disk delta = only `cpnos.img` (MPM.SYS identical);
drive I: delta = the `cpnos-shared/drive_i/` tool set. Both regenerable.
Discarded 2026-07-27 (Trin 0 done).

## Facts

- Launcher `z80pack/cpmsim/mpm-net2` already REQUIRES `local/mpm-net2-1.dsk`
  for boot (drivea); copies library/local -> ephemeral `disks/drive*.dsk`
  each run (cpmsim opens drive[a-j].dsk literally).
- `MPM_DISK_LIB=../z80pack/cpmsim/disks/library`, `MPM_DISK_LOCAL=.../local`,
  `MPM_DIR=$(CURDIR)/../z80pack/cpmsim`, `SHARED=../cpnos-shared`,
  `DRIVEI_DIR=$(SHARED)/drive_i` (the reproducible drive I: source of truth).
- `*/disks/local/` is gitignored in z80pack.
- `cpnetsmk-1.dsk` does not exist (dead Makefile branch — drop it).
- Base boot disk holds ccp.spr + cpnos.img + ndos.spr; only cpnos.img is
  volatile. ccp.spr/ndos.spr are stable CP/NET components -> stay in base.
- drive I: = PPAS.* + COMAL80.* + L80/M80 + TODGET + PRIMES.PAS (work prog).

## Phase 1: rename cpnos.img -> rc700.nos (RC700-specific), FIRST

The image name is baked into the PROM1 slave FCB (`src/init.c:382-387`) — the
slave requests it from the master over CP/NET. So rename = coordinated
firmware + disk change, name must agree on both sides.

- [x] `src/init.c` FCB: name `RC700   ` + ext `NOS` (was `CPNOS   ` / `IMG`).
- [x] `cpnos-in-c/Makefile`: all 10 `0:cpnos.img` -> `0:rc700.nos`.
- [x] clang PROM1 slave rebuilt (2011/2048 B); FCB verified in init.bin +
      payload.elf: `RC700   NOS` PRESENT, `CPNOS   IMG` gone.
- [ ] sdcc PROM1 slave: build env BROKEN pre-existing (`z80.lib` path needs
      rc700 prebuilt z88dk via Z88DK_HOME; then `cpnos_main.o` ordering). FCB
      is a shared const array so sdcc emits identical bytes -- verify once the
      sdcc build env is fixed.
- [x] disk build with rename: stage rc700.nos, cpmls confirms RC700.NOS on
      local/mpm-net2-1.dsk (2026-07-27; `cpnos-disk-install` installs it).
- [x] NETBOOT VALUE ORACLE (commit gate, feedback_no_commit_first_version):
      `make cpnos-polypascal-test COMPILER=clang` PASS 2026-07-27 -- slave FCB
      requests RC700.NOS, master serves it, PPAS PRIMES ran to 29989 and Q
      returned to E>; verified visually (snap/rc702/0773.png). A PASS proves
      BOTH sides agree on RC700.NOS (mismatch would fail netboot file-not-found).
- [ ] host-intermediate `cpnos_with_locale.img` + echoes still say cpnos.img
      (cosmetic) -- tidy in Phase 2.

## Plan (Phase 2: disk-build refactor)

- [x] Trin 0: discard library/ dirt (restore frozen base).
- [~] A. cpnos-in-c/Makefile: redirect both leaks to `local/`.
      - [x] cpnos-disk-install: writes rc700.nos ONLY to local/mpm-net2-1.dsk
        (no library write); removes BOTH legacy cpnos.img AND rc700.nos before
        writing (rename-transition device-full fix); dead cpnetsmk branch
        dropped; errors (not warns) if local disk absent. Done 2026-07-27
        while unblocking the Phase 1 netboot oracle.
      - [ ] cpnos-disk-install-with-locale: still writes to library -- redirect.
      - [ ] auto rebuild-mpm-sys.sh --install if local disk absent (currently errors).
      - [ ] stage-drivei-tools: DRIVEI_DSK -> local/mpm-net2-drivei.dsk.
- [ ] B. launcher: prefer local/mpm-net2-drive{i,j}.dsk over library.
- [ ] C. z80pack: strip cpnos.img from committed library/mpm-net2-1.dsk;
      commit (base becomes pure MP/M+CP/NET; drivei already blank).
- [ ] D. `make mpm-disks` (cpnos-in-c): rebuild-mpm-sys --install +
      cpnos-disk-install + stage-drivei-tools -> all tailored disks in local/.
- [ ] E. docs: REBUILDING_MPM_SYS.md + memory note (flow = make mpm-disks;
      library disks frozen, never written).

## To do later (2026-07-27, user)
- [ ] Opdatér kommentarer på z88dk/z88dk#3022:
      https://github.com/z88dk/z88dk/issues/3022#issuecomment-5096493359
