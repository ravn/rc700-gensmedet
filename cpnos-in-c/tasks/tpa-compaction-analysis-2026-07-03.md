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
4. **Z80-mnemonic rewrite of the DRI resident (T8 — best structural lever).**
   The DRI modules (cpndos, cpbdos, cpnios) are pure **8080** assembled by RMAC:
   every jump is a 3-byte `JMP`/`Jcc`, no `JR`/`DJNZ`.  Counts: NDOS 46 jmp +
   66 jcc + 21 dcr-loops; RESBDOS 22 + 29 + 7.  Converting in-range jumps to
   `JR`/`JR cc` (-1 B each, ~30-50% within +/-127 B) and `DCR B`/`JNZ` -> `DJNZ`
   (-2 B) recovers **~100-150 B** of pure resident shrink = direct TPA.
   Mechanical; needs a Z80 assembler (workspace has `zmac`) instead of RMAC and
   an 8080->Z80 syntax pass.  Editable because it's abandonware we own
   ([[project_dri_ndos_frozen]]).  (User suggestion, 2026-07-04.)

5. **NDOS never-taken local-disk branch (T7 — small).**
   cpnos is diskless, so NDOS's local-vs-network routing always goes network;
   the local branch is dead.  BUT this is smaller than first estimated:
   `cpbdos.asm` is *already* the "diskless BDOS, functions 0-12 only" (no
   SELDSK/READ/WRITE), and the Phase-20 local-floppy attempt was rejected and
   never merged ([[project_cpnos_no_local_floppy]]).  The local-vs-network
   decision is DRI-inherent, not our leftover.  So the trim is just removing
   the never-taken drive-map local branch in NDOS -- ~50-100 B, not ~1 KB.

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
- **T7 (small, corrected):** remove NDOS's never-taken local-disk routing
  branch (cpnos is diskless; all drives network).  ~50-100 B.  NOT a leftover
  of a local-drive attempt — cpbdos is already the diskless fn-0-12 BDOS and
  the Phase-20 local-floppy build was rejected/never merged
  ([[project_cpnos_no_local_floppy]]); the local-vs-network routing is
  DRI-inherent.  Gate on the value-oracle.
- **T8 (best structural, user 2026-07-04):** rewrite the DRI resident modules
  (cpndos, cpbdos, cpnios) from 8080 to Z80 mnemonics so JMP/Jcc -> JR/JR cc
  and DCR B/JNZ -> DJNZ.  ~100-150 B of direct TPA.  Needs a Z80 assembler
  (zmac) replacing RMAC + an 8080->Z80 syntax pass; verify byte-for-byte
  behaviour against the current build, then full value-oracle.  We own the
  sources ([[project_dri_ndos_frozen]]).
