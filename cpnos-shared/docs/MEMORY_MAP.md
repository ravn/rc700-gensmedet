# cpnos memory map — see `cpnos-in-c/docs/memory_map.md`

This file used to be the authoritative cpnos memory map (last refreshed
2026-05-10).  It is now stale: the 25 KB of contents below the line
referenced `cpnos-rom/` (the parked predecessor) and the
`cpnos-shared/ld/{payload.ld, relocator.ld, cpnos_rom.ld}` files that
were **deleted in the two-PROM cleanup, 2026-06-03**.

The current authoritative cpnos memory map lives at:

> **`cpnos-in-c/docs/memory_map.md`**

That doc covers the post-relocation, pre-server-load state and is
derived from `cpnos-in-c/clang-prom1lineprog/payload.ld` (the current
linker script) + `cpnos-build/d/cpnos.sym`.

cpnos-in-asm is parked (`rc700-gensmedet/cpnos-in-asm/PARKED.md`); there
is currently no cpnos variant outside cpnos-in-c, so the cpnos-shared/
namespace is effectively cpnos-in-c-specific for memory-layout purposes.
This pointer file is kept under cpnos-shared/docs/ only so existing
in-tree references resolve.
