# cpnos TPA compaction — analysis (2026-07-03)

Question: can we compact the cpnos resident further to grow the slave TPA?

## Current state

- **TPA: 0x0100..0xDA80 = 55680 B ≈ 54.4 KB** (ceiling = `DATA_BASE`).
- Resident window `0xDA80..0xF800 = 7.4 KB` holds the netbooted CP/NOS
  (NDOS + SNIOS + RESBDOS) plus BIOS, IVT, buffers and the conversion tables.
- cpnos.sys is L80-linked at fixed `CODE_BASE=0xDE80`, `DATA_BASE=0xDA80`
  (`cpnos-build/Makefile`); modules `cpnos=cpndos,cpnios,cpbdos`.

54.4 KB is already close to the CP/M practical ceiling (a normal CP/M A>
system is ~54-56 KB TPA), so the headroom for compaction is modest.

## Where the resident bytes are (module .rel sizes)

| Module | .rel | Notes |
|--------|------|-------|
| `cpndos` (NDOS) | 3200 B | DRI network BDOS — the dominant block; not our code to shrink |
| `cpbdos` (RESBDOS) | 896 B | local BDOS delegation (fn 12 GET VERSION etc.); already minimal |
| `cpnios` (SNIOS) | 128 B | tiny shim |
| conversion tables | 384 B | OUTCON+INCONV @ 0xF680 (Danish locale) |
| PIO-B ring | 256 B | transport_pio |
| display buffer | 2000 B | 0xF800.. — hardware-fixed, not reclaimable |
| IVT + int stack | ~256 B | IM2 hardware-fixed |

## Levers, largest first

1. **Relocatable resident (structural — user's "to do later").** cpnos.sys is
   hardwired at fixed CODE/DATA bases. If it were relocatable (.PRL/.SPR-style)
   the netboot loader could pack it tightly and adapt to the actual memory
   size instead of a compile-time address, recovering fixed-address rounding +
   the DATA↔CODE slack. Right structural direction; gain bounded by how much of
   the 1 KB data region (0xDA80..0xDE80) is real state vs. padding (mostly
   real). Aligns with `todo-cpnos-relocatable-2026-05-17.md`. **Tracked as T6.**
2. **Conversion/locale tables — 384 B.** Collapse OUTCON/INCONV to identity for
   deployments that don't need the Danish keyboard remap. Deployment-specific;
   the shipping `da_US` build needs them, so this is a config lever, not a free
   win.
3. **PIO-B ring 256→16 B — ~240 B.** Coupled to INIR and PARKED
   (`feedback_ring_shrink_inir_coupled`, `PIO_INIR_PARKED.md`) — do not ship
   the shrink without INIR or netboot overflows.
4. **NDOS (~3 KB)** — dominant but DRI upstream code; not a practical lever.
5. **RESBDOS (~700 B)** — already minimal; needed for local BDOS-fn delegation.

## Honest assessment

Without restructuring, the realistically reclaimable TPA is ~**600 B**
(384 B locale tables if collapsible + ~240 B PIO ring once INIR lands) — and
both are gated (config-specific / parked). The **relocatable-resident** path
(T6) is the only structural lever, and even it is bounded because the resident
is already densely packed. The +256 B TPA-grow (2026-06-04, shift resident up
$100) already captured the cheap win, and the PROM1 line program is at only
35 B free, so further upward shifts of the resident are blocked by the 2 KB
PROM cap, not by the resident layout.

## Task raised

- **T6:** investigate making the cpnos server-side resident module relocatable
  at load time instead of hardwired to fixed CODE/DATA bases, so the netboot
  loader can place it to maximise TPA / adapt to memory size. Refines
  `todo-cpnos-relocatable-2026-05-17.md`. (User "to do later", 2026-07-03.)
