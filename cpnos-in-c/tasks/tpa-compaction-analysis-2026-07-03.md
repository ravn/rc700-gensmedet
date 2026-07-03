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
| `cpndos` (NDOS) | 3200 B | DRI network BDOS — dominant block, and **editable** (we own cpnet-z80 DRI sources, [[project_dri_ndos_frozen]]).  The real lever, see T7. |
| `cpbdos` (RESBDOS) | 896 B | local BDOS delegation (fn 12 GET VERSION etc.); editable, trim to genuinely-local fns (T7) |
| `cpnios` (SNIOS) | 128 B | tiny shim |
| conversion tables | 384 B | OUTCON+INCONV @ 0xF680 (Danish locale) |
| PIO-B ring | 256 B | transport_pio |
| display buffer | 2000 B | 0xF800.. — hardware-fixed, not reclaimable |
| IVT + int stack | ~256 B | IM2 hardware-fixed |

**Correction (user, 2026-07-03):** the DRI NDOS/RESBDOS/CCP are NOT
off-limits — they are abandonware and we own the sources
(`cpnet-z80/dist/src/cpndos.asm` etc.).  So the 3.2 KB NDOS is the largest
*addressable* block, not an untouchable given.  See T7.

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
4. **NDOS + RESBDOS trim for a diskless slave (largest addressable, T7).**
   cpnos has NO local disk — every drive in the CFGTBL is a network drive, so
   NDOS almost always routes to the master. The DRI NDOS still carries the full
   local-disk-vs-network decision path and RESBDOS carries local-BDOS handlers.
   Collapsing the local-disk branch (drive is *always* network) and reducing
   RESBDOS to the genuinely-local functions (GET VERSION, console/list I/O that
   the BIOS serves) is real reclaimable space in the 3.2 KB + 0.9 KB blocks.
   Since it's abandonware we own, this is editable. Needs a BDOS-function
   usage audit (what cpnos workloads actually call) + full oracle re-test
   (polypascal + TOD + smoke on both transports); risk is breaking a program
   that calls a trimmed path, so gate on the value-oracle. Estimated
   several hundred B to ~1 KB.

## Honest assessment

The cheap config/parked levers (locale tables 384 B, PIO ring ~240 B) total
~600 B and are gated. The **structural** levers are (a) T7 — trim the DRI
NDOS/RESBDOS for the diskless case, the largest addressable block; and (b) T6
— make the resident relocatable so the loader packs it tightly. Note the PROM1
line program is at only 35 B free against the 2 KB cap, so shifting the
resident *up* is blocked by the PROM, not the resident — which is why
*shrinking* the resident (T7) is the more promising direction than moving it.

## Tasks raised

- **T6:** make the cpnos resident relocatable at load time instead of hardwired
  to fixed CODE/DATA bases, so the netboot loader can place it to maximise TPA.
  Refines `todo-cpnos-relocatable-2026-05-17.md`. (User "to do later".)
- **T7:** trim the DRI NDOS + RESBDOS for the diskless slave — collapse the
  local-disk path (drives are always network) and reduce RESBDOS to the
  genuinely-local functions. We own the sources ([[project_dri_ndos_frozen]]).
  Audit BDOS-function usage first; gate on the full value-oracle. Largest
  addressable block (3.2 KB NDOS + 0.9 KB RESBDOS). (User, 2026-07-03.)
