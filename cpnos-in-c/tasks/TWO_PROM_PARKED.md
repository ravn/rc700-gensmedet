# cpnos-in-c two-PROM build — REMOVED 2026-06-03

The two-PROM build (former `make cpnos`, `cpnos-mame-install`,
`cpnos-disk-install`, `relocator.c`, `cpnos-shared/ld/payload.ld`,
`cpnos-shared/ld/relocator.ld`, `cpnos-shared/ld/cpnos_rom.ld`,
`src/reset.s`) was **parked** 2026-05-17 (locale refactor broke SDCC's
link; `make` defaulted to a broken target) and **removed in full**
2026-06-03 along with the dead source + Makefile sections.

**The only supported slave topology is now:**
  autoload-in-c (ROA375) in PROM 0  +  cpnos-in-c PROM1-only line program
  (`make prom1-lineprog`) in PROM 1.

Cleanup commit closes the parked-build maintenance debt.  See the
project finishing-checklist (`tasks/finishing-checklist.md`) and
`tasks/finishing-roadmap-2026-06-03.md` for the broader four-component
finishing plan this slot into.
