# CP/NOS RC702 Memory Map

Layout as of 2026-04-23 (Phase 19, branch `conout-codes` — payload
is a single contiguous blob at 0xED00, split across PROM0 tail and
PROM1 at cold boot by a C23 `#embed` relocator).

Authoritative sources: `payload.ld` for VMA layout, `relocator.ld`
for the PROM-side split.  The linker scripts contain the asserts —
this document summarises.

## 64 KB RAM overview

```
0x0000 ┌────────────────────────┐
       │ CP/M reset vectors     │  0x0000=RST0→WBOOT, 0x0005=BDOS JP
       │ 0x0000..0x00FF         │  0x0038=RST7 (IM0 entry — unused)
0x0100 ├────────────────────────┤
       │ TPA                    │  Transient Program Area
       │ 0x0100..0xCFFF         │  51.75 KB available to user code
       │                        │  (M80, L80, user programs, …)
0xD000 ├────────────────────────┤
       │ CP/NOS cold payload    │  Downloaded by netboot_mpm from the
       │ 0xD000..0xDFD9         │  master's A:CPNOS.IMG (4 KB file).
       │                        │    0xD000..0xDDFF  CCP (2.5 KB)
       │                        │    0xDE00..0xE9FF  NDOS (3 KB)
       │                        │    0xDF21          BDOS entry
0xEA00 ├────────────────────────┤
       │ SNIOS resident         │  Our Z80 port of DRI SNIOS (snios.s)
       │ 0xEA00..0xEA1F         │  NDOS expects SNIOS JT here.
       │                        │  cpnios-shim.asm forwards here.
0xEA20 ├────────────────────────┤
       │ SCRATCH (BSS)          │  0xEA20..0xEBFF (widened to 0x200
       │ kbd_head/tail          │    in Phase 18 to host cfgtbl).
       │ 0xEA22..0xEA31 kbd_ring│   0xEA20 kbd_head
       │ 0xEA32 curx            │   0xEA21 kbd_tail
       │ 0xEA33 cury            │   0xEA22..0xEA31  kbd_ring[16]
       │ 0xEA37..0xEAFE cfgtbl  │   0xEA32 curx
       │ (cfgtbl=0xEA37, 173 B) │   0xEA33 cury
       │                        │   0xEA37..0xEAFE  cfgtbl (173 B,
       │                        │                   runtime-init'd)
       │                        │   0xEAFF..0xEBxx  msg[] (netboot)
0xEC00 ├────────────────────────┤
       │ IM2 IVT (36 B)         │  0xEC00..0xEC23 — 18 x u16 ISR ptrs.
       │ Cold-boot stack below  │  SP=0xED00 at cold-boot entry.
       │ (diag breadcrumbs at   │  Diag scratch page 0xEC40..0xECFF
       │  0xEC40..0xECFF were   │  stripped in Phase 18; region free
       │  cleared in Phase 18)  │  for future use (see #47/#48).
0xED00 ├────────────────────────┤
       │ BIOS resident          │  Our retargeted RC702 BIOS, in C:
       │ 0xED00..~0xF24F        │    0xED00  bios JT (51 B, 17 × 3)
       │                        │    0xED33  SNIOS JT local (24 B)
       │                        │    ...     BIOS stubs, ISRs,
       │                        │            console driver, CFGTBL
       │ 2.75 KB region         │  Linker-tracked; ASSERTed ≤ 0xF800.
0xF800 ├────────────────────────┤
       │ 8275 display RAM       │  80×24 char buffer = 1920 B +
       │ 0xF800..0xFFFF         │  conv_tables + workarea (untouched)
0xFFFF └────────────────────────┘
```

## ROM (until `OUT (0x18),A` disables both)

Phase 19 re-architected the PROM usage.  The clang/ld link doesn't
know about PROMs at all — it just links the payload at 0xED00.  A
separate C23 relocator (`relocator.c` + `reset.s`) with PROM-aware
linker script (`relocator.ld`) reconstructs the payload in RAM.

```
0x0000 ┌────────────────────────┐
       │ reset.s (3 ins)        │  di, ld sp, 0xED00, jp _relocate
       │ 0x0000..0x0006         │
0x0007 │ relocator.c            │  Two __builtin_memcpys + jp entry
       │ 0x0007..~0x001F        │  (C23, ~26 B)
0x0020 │ 0xFF padding           │  Reserved budget up to 0x0080
0x0080 │ payload_a[]            │  PROM0 tail of the payload, first
       │ 0x0080..0x07FF         │  1920 B of payload.bin, #embed'd
       │                        │  into relocator.c's .prom0_tail
0x0800 └────────────────────────┘
...
0x2000 ┌────────────────────────┐
       │ payload_b[]            │  Rest of payload.bin (206 B), #embed'd
       │ 0x2000..0x20CD         │  into relocator.c's .prom1 section
0x20CE │ 0xFF padding (1842 B)  │
0x2800 └────────────────────────┘
```

Both PROMs are mapped at boot.  Cold flow:
1. Z80 reset → fetch from PROM0 0x0000 (reset.s).
2. Set SP, jump to `_relocate` at 0x0007.
3. `_relocate` LDIRs payload_a (1920 B from PROM0 tail) then
   payload_b (206 B from PROM1) into 0xED00.
4. Tail-calls `cpnos_cold_entry` inside the payload at some address
   in 0xED00+ (resolved via `--defsym` at relocator-link time).
5. Payload runs init + netboot, then does `OUT (0x18),A` itself to
   disable both PROMs (it's executing from 0xED00+ so that's safe).
6. TPA at 0x0100+ now reads RAM; CP/M is online.

Never branch back into ROM after the `OUT (0x18),A` — 0x0000..0x07FF
and 0x2000..0x27FF are RAM content (CCP TPA, our zero-page setup).

## Reserved diagnostic slots (RAM 0xEC40..0xECFF)

All prod-build trace bumps were removed in Phase 18 (commit
c54229c).  Page 0xEC40..0xECFF is free for future diagnostic
scratch; reservations from Phase 16-17 are no longer live code.

External Lua-tap diagnostics live in `mame_*_trace.lua` /
`mame_*_test.lua` (`mame_polypascal_test.lua`, `mame_bios_jt_trace.lua`,
`mame_minimal_trace.lua`).  These run outside the PROM and capture
control-flow / register-state evidence without affecting the PROM
image.  The earlier `mame_smoke_dump.lua` was retired in the Phase 48
harness cleanup along with the Python netboot simulator it depended
on.

## Key non-address facts

- **CP/M BDOS entry** is at `0x0005`, which is a JP to wherever
  BDOS actually lives (currently 0xDF21, inside the cpnos.com blob
  at 0xD000).
- **NDOS base** is 0xDE00.  The NDOS SNIOS JT stub expects our real
  SNIOS to live at `NDOS_BASE + NDOS_CODELEN = 0xEA00`.  If any
  NDOS/CCP component changes size, 0xEA00 moves — cpnios-shim.asm's
  `rsbase` must be updated in lock-step.
- **Default DMA** after cold boot is 0x0080 (CP/M standard).  M80's
  source-read loop (l4d25) sets its own DMA to `l4447 + k*128`
  starting at ~0xC200 in practice.

## Moving boundaries

Before moving any of these boundaries:
1. Update `payload.ld` (VMA, SCRATCH region, IVT placement, ASSERTs).
2. Update the matching `#define` / `equ` in `cpnos_main.c`, `snios.s`,
   `cpnios-shim.asm`, and this file.
3. Rebuild `cpnos.com` (so NDOS's baked-in SNIOS JT stub still
   points at the right resident address).
4. Re-run `make cpnet-smoke` to confirm netboot + CCP + M80 still
   land correctly.

If the relocator side (not the payload) needs to change:
1. Update `relocator.ld` for the PROM split.
2. Update `PROM0_TAIL_SIZE` in `Makefile` to match `.prom0_tail`'s
   base (default 0x80 ⇒ 1920 B).
3. `make cpnet-smoke`.
