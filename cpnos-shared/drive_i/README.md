# drive_i/ — canonical contents of master drive I: (= cpnos slave E:)

This folder is the **single source of truth** for what lives on the shared
tool drive that every cpnos test target uses. The slave's CFGTBL maps
`E: -> master I:` (`cpnos-in-c/src/init.c` `cfgtbl_init_template`), and the
E:-tests build cpnos with `-DCPNOS_DEFAULT_DRIVE=0x04` so the slave
cold-boots straight into E:.

## Workflow

- **Populate the drive** (folder → fresh I:, done automatically before a
  test run):
  ```
  make -C cpnos-in-c stage-drivei-tools
  ```
  Drive I: is rebuilt blank (4 MB `z80pack-hd`) and every file here is copied
  onto it.

- **Merge changes back** (I: → folder, capture anything the slave created or
  modified — compiled `.REL`/`.COM`, saved COMAL/Pascal sources, etc.):
  ```
  make -C cpnos-in-c sync-drivei-back
  git status cpnos-shared/drive_i/
  ```
  Review and commit intentionally. Merge-back is a separate, explicit target
  so ordinary test runs don't churn the tree.

- **Add a tool:** drop the file here (uppercase 8.3 name) and re-stage.

## Current tool set

| File | Tool |
|------|------|
| `PPAS.COM`, `PPAS.ERM`, `PRIMES.PAS` | PolyPascal-80 v3.10 + demo |
| `TODGET.COM` | CP/NET FN-105 time-of-day client |
| `COMAL80.COM`, `COMAL80.ERM` | RcComal80 v2.0 (CP/M) |
| `M80.COM`, `L80.COM` | Microsoft M80 assembler + L80 linker |

## Notes

- Names are UPPERCASE 8.3 (CP/M convention). `drive_i_sync.sh` normalises on
  merge-back so the round-trip is stable on case-insensitive (macOS) and
  case-sensitive (Linux) filesystems.
- `cpmtools` on `z80pack-hd` images often exits 139 (segfault) on cleanup
  *after* a successful transfer; the sync helper tolerates this and verifies
  by result, not exit code.
