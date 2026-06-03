# cpnos slave runtime memory map

**Refreshed 2026-06-03** (post-two-PROM removal, PROM1-only-lineprog is
the sole topology).

This doc snapshots the cpnos slave's RAM layout at the moment **after**
the PROM1 ZX0-decoded resident has been copied to its runtime VMA, init
has finished hardware bring-up, and the IVT is installed — **but
before** `netboot_mpm` has driven the CP/NET LOGIN/OPEN/READ exchange
that loads `cpnos.com` (CCP+BDOS+NDOS) from the master into TPA.

## Authoritative sources

| Concern | File |
|---|---|
| RAM layout (resident, IVT, SCRATCH, PIO_RX, CFGTBL, stack) | `cpnos-in-c/clang-prom1lineprog/payload.ld` |
| PROM1 image layout (lineprog header, ZX0 decoder, init.zx0, payload.zx0) | `cpnos-in-c/clang-prom1lineprog/prom1.ld` |
| ZX0 decode destinations (bootstrap.s constants) | `cpnos-in-c/clang-prom1lineprog/bootstrap.s` |
| Zero-page setup at cold boot | `cpnos-in-c/src/init.c` (`zp_init`) |
| Per-section assignment (`.resident.*`, `.init.text`, `.bss.cfgtbl`, …) | `cpnos-in-c/compiler/compat.h` + `__attribute__((section(...)))` in `.c` sources |
| cpnos.com (CCP+BDOS+NDOS) layout — applies after server-load | `cpnos-in-c/cpnos-build/d/cpnos.sym` |

**If the linker script or symbol map disagrees with this doc, the
sources win.**  ASSERTs in `payload.ld` (16+ of them) catch most
drift at build time; the rest is cosmetic in this doc.

## Three boot phases

1. **Boot from PROM (~0x0000 / 0x2000)** — autoload-in-c (PROM0) checks the
   PROM1 signature, jumps to `bootstrap_entry` at 0x2008.
2. **PROM1 lineprog bootstrap** — `bootstrap.s` disables interrupts, sets
   SP, calls `dzx0_standard` twice (init.zx0 → 0xC000, payload.zx0 →
   0xEE00), then jumps to `_cpnos_cold_entry` at 0xC000.
3. **Init in PROM1 INIT region (0xC000)** — runs `cpnos_cold_entry()`
   (locale pre-fill + sentinel stamp), then standard cold init
   (`init_hardware`, `cfgtbl_init`, `print_banner`, `netboot_mpm` setup),
   disables PROMs via `OUT (0x18)`, hands off to the resident at 0xEE00.

**This doc captures the state at the end of phase 3.**

## PROM1 image layout (the physical 2 KB EPROM)

Static contents of the burned PROM1, loaded by MAME into `prom1.ic65`
and on real hardware into the IC65 2716 socket.  All addresses are the
runtime CPU view (PROM1 maps at 0x2000..0x27FF until `OUT (0x18)`
disables both PROMs in phase 3).

Sizes from the most recent clang build (2026-06-03; will shift ±2 B
per commit due to buildinfo banner in `payload.bin` — see commit
`72e38a6` for the ZX0-sensitivity analysis).

```
0x2000 ┌────────────────────────────────────────────────┐
       │ .lineprog_header   (8 B)                        │  layout:
       │   0x2000  DW bootstrap_entry  (= 0x2008)        │  - jump-target word
       │   0x2002  " RC702"            (6 B signature)   │  - signature autoload
       │                                                 │    checks at 0x2002
0x2008 ├────────────────────────────────────────────────┤
       │ .lineprog_entry  (25 B)                         │  bootstrap_entry:
       │   bootstrap_entry:                              │    DI; LD SP, ...;
       │     - DI, set SP                                │    LD HL,.init_zx0
       │     - call dzx0_standard(.init_zx0  → 0xC000)   │    LD DE,0xC000
       │     - call dzx0_standard(.payload_zx0→0xEE00)   │    CALL dzx0_standard;
       │     - jp _cpnos_cold_entry  (= 0xC000)          │    (and again for
       │                                                 │     payload); JP 0xC000
0x2021 ├────────────────────────────────────────────────┤
       │ .zx0_decoder  (69 B)                            │  dzx0_standard
       │   Einar Saukas's tiny ZX0 decoder               │  by Einar Saukas
       │   Entry: HL=src, DE=dst → expands inline        │  (Standard variant;
       │                                                 │   dzx0s_literals,
       │                                                 │   dzx0s_copy,
       │                                                 │   dzx0s_new_offset,
       │                                                 │   dzx0s_elias_*)
0x2066 ├────────────────────────────────────────────────┤
       │ .init_zx0  (527 B compressed)                   │  __init_zx0_start
       │   ZX0-compressed init.bin (605 B uncompressed)  │  → __init_zx0_end =
       │   Decoder target: 0xC000  (RAM PROM1 INIT)      │    0x2275
       │   Contents: cpnos_cold_entry, init_hardware,    │
       │             cfgtbl_init, print_banner,          │
       │             netboot_mpm setup, ZP init, jumps   │
0x2275 ├────────────────────────────────────────────────┤
       │ .payload_zx0  (1400 B compressed)               │  __payload_zx0_start
       │   ZX0-compressed payload.bin (2016 B uncompr.)  │  → __payload_zx0_end =
       │   Decoder target: 0xEE00  (RAM resident)        │    0x27ED
       │   Contents: BIOS jump table @ +0x00,            │
       │             SNIOS jump table @ +0x33,           │
       │             ISRs, BIOS/SNIOS code, rodata,      │
       │             data, .payload_checksum (last 2 B)  │
0x27ED ├────────────────────────────────────────────────┤
       │ (unused, 0xFF padding to 2 KB)  ~19 B           │  __prom1_used = 0x27ED
0x27FF └────────────────────────────────────────────────┘  PROM1 total = 2048 B
                                                            (ASSERT __prom1_used
                                                             <= 0x2800)
```

**Total used: 2029 / 2048 B (19 B free; hard cap 2048 B = 2716 EPROM).**

Authoritative source: `cpnos-in-c/clang-prom1lineprog/prom1.ld`.

### PROM0 reference (autoload-in-c, not in this doc's scope)

PROM0 (IC66, 2716) holds autoload-in-c, which boots, reads SW1 to choose
between floppy boot and PROM1-lineprog mode, then jumps to PROM1's
bootstrap when SW1 selects lineprog.  See
`rc700-gensmedet/autoload-in-c/docs/` for autoload's PROM0 layout.

## RAM map (state: ready to start CP/NET LOGIN)

**Post-TPA-grow layout** (2026-06-04).  Slave-resident bottom edge shifted
up $100; CFGTBL packed into IVT-page tail to make room.  Net for user
programs: +256 B TPA (BDOS dispatch 0xE716 → 0xE816).

```
0x0000 ┌────────────────────────────────────────────────┐
       │ Zero page                                       │  set by zp_init at cold boot
       │   0x0000  JP WBOOT                              │
       │   0x0005  JP BDOS  ← placeholder until NDOS loads
       │   0x0008..0x00FF  unused                        │
0x0100 ├────────────────────────────────────────────────┤
       │ TPA — FREE  (+256 B vs pre-TPA-grow)            │  cpnos.com lands here
       │  ~58.25 KB of empty RAM                         │  after server-load
       │                                                 │  completes (see "Post-
       │  (0xC000..0xC27F briefly held the PROM1 INIT    │   server-load delta"
       │   region used by phase 3; reclaimed as TPA      │   below)
       │   once init returns)                            │
0xEB00 ├────────────────────────────────────────────────┤
       │ IVT  (18 IM2 vectors × 2 B = 36 B in use)       │  I = 0xEB
0xEB24 ├────────────────────────────────────────────────┤
       │ CFGTBL  (210 B; packed into IVT-page tail to    │  CP/M CFGTBL drive entries:
       │  free upper-region space for the move-up)       │  NET_DRV(...) for H:,
       │                                                 │  0x0000 for unmounted slots
0xEBF6 ├────────────────────────────────────────────────┤
       │ IVT-page slack  (10 B)                          │
0xEC00 ├────────────────────────────────────────────────┤
       │ SCRATCH BSS  (256 B)                            │  cpnos-internal scratch
0xED00 ├────────────────────────────────────────────────┤
       │ PIO_RX ring buffer  (256 B, page-aligned)       │  SPSC ring for IRQ-driven
       │                                                 │  PIO-B byte input.
       │                                                 │  Page-aligned so isr_pio_par
       │                                                 │  forms ring[head] as
       │                                                 │  `ld h,_pio_rx_buf_page; ld l,head`
       │                                                 │  (4 B / 18 T) instead of
       │                                                 │  full base+index (8 B / 39 T).
       │                                                 │  isr_pio_par is THROUGHPUT-
       │                                                 │  CRITICAL — its ~51 µs round-
       │                                                 │  trip caps CP/NET RX at
       │                                                 │  ~19.6 kbyte/s.  See speed-
       │                                                 │  budget section at top of
       │                                                 │  src/transport_pio.c.
0xEE00 ├────────────────────────────────────────────────┤
       │ .payload — resident BIOS + SNIOS  (~2016 B)     │
       │   0xEE00  _bios_boot      (BIOS jump table)     │  17 CP/M BIOS entries
       │   0xEE0C  _bios_conout                          │  (+12 from _bios_boot)
       │   0xEE30  _bios_sectran                         │  (+48 from _bios_boot)
       │   0xEE33  _snios_jt       (SNIOS jump table)    │  NDOS jumps via NIOS = 0xEE33
       │   ...     ISRs, code, rodata, data              │
       │  ~0xF5DE  __payload_checksum  (word-additive    │  patched to == 0xCAFE so
       │                                = 0xCAFE)        │  bootstrap can verify after
       │  ~0xF5DF  __payload_end                          │  ZX0 decode + BSS clear
0xF5E0 ├────────────────────────────────────────────────┤
       │ payload-growth budget  (~46 B)                  │  ceiling at 0xF60E
0xF60E ├────────────────────────────────────────────────┤
       │ Stack workspace  (~114 B, SP grows down from    │  __stack_top = 0xF680
       │  0xF680; __stack_low = 0xF60E → max ~114 B)     │  __stack_low = 0xF60E
0xF680 ├────────────────────────────────────────────────┤
       │ Locale tables  (384 B)                          │  outcon[128] + inconv[256]
       │   outcon[128]   US-ASCII output translation     │  pre-filled by
       │   inconv[256]   Danish keyboard input mapping   │  cpnos_cold_entry; locale
       │                                                 │  prefix loaded into here
       │                                                 │  from cpnos.img on first
       │                                                 │  server read
0xF800 ├────────────────────────────────────────────────┤
       │ Display memory  (2000 chars = 80 × 25)          │  driven by i8275 CRTC via
       │                                                 │  Am9517A DMA channel 2
0xFFCF ├────────────────────────────────────────────────┤
       │ i8275 row table + control area  (48 B)          │
0xFFFF └────────────────────────────────────────────────┘
```

## Link-time ASSERTs (in `payload.ld`)

The build fails with a clear message if any of these don't hold:

| Symbol / region | ASSERT |
|---|---|
| `_bios_boot` | `== 0xEE00` (BIOS JT pinned) |
| `__init_end` (via `__init_size`) | `≤ 0xC280` (NEVER overlap cpnos.com NDOSRL=0xDA80 — see "init vs cpnos.com" below) |
| `_bios_conout - _bios_boot` | `== 12` (CONOUT entry offset) |
| `_bios_sectran - _bios_boot` | `== 48` (SECTRAN entry offset) |
| `_snios_jt` | `== 0xEE33` (matches `cpnos-build/src/cpnios-shim.asm:NIOS EQU`) |
| `__cfgtbl_bss_end` | `≤ 0xEC00` (CFGTBL fits in IVT-page tail) |
| `__payload_end` | `≤ 0xF60E` (would clobber stack/locale) |
| `__payload_end` | `≤ 0xF800` (would clobber display) |
| `__payload_size` | `≤ 0x1000` (4 KB budget) |
| `__init_size` | `≤ 0x0280` (640 B INIT region budget) |
| `__scratch_bss_end` | `≤ 0xED00` (would clobber PIO_RX) |
| `__pio_rx_bss_start & 0xFF` | `== 0` (page-aligned for SPSC ring) |
| `.payload_checksum` size | `== 2 B` (word-additive checksum slot) |
| `__prom1_used` (in `prom1.ld`) | `≤ 0x2800` (PROM1 hard cap 2 KB; hardware-set, see `project_rc702_2kb_prom_hard_limit`) |

## Free regions at this moment

| Region | Size | Notes |
|---|---:|---|
| 0x0100..0xEA7F (TPA) | ~58.25 KB | cpnos.com lands here at server-load (+256 B vs pre-TPA-grow) |
| 0xEBF6..0xEBFF | 10 B | IVT-page slack after CFGTBL |
| 0xF5E0..0xF60D | ~46 B | `.payload` growth budget before tripping the 0xF60E ASSERT |

## Post-server-load delta

Once CP/NET LOGIN/OPEN/READ has fetched `cpnos.com` (~3200 B) from the
master and NDOS hands off, the TPA region is occupied by (from
`cpnos-build/d/cpnos.sym`, build-dependent):

| Symbol | Address | Description |
|---|---:|---|
| `NDOSRL` | 0xDA80 | NDOS DATA region base |
| `BDOSDS` | 0xDC6A | BDOS DATA segment |
| `NDOS` | 0xDE80 | NDOS CODE base |
| `BDOS` | 0xE816 | BDOS dispatch (TPA top for user programs) |
| `NIOS` | 0xEE33 | SNIOS jump table (= `_snios_jt` in resident) |

cpnos.com fits below the IVT at 0xEB00 with **0 B clearance** (tail at
0xEAFF) per the build's `cpnos.com fits below IVT:` report.  The
NIOS=0xEE33 pin is what ties the loaded NDOS to the link-time resident
SNIOS jump table.

**TPA-grow history** (2026-06-04): CODE_BASE/DATA_BASE bumped 0x100
higher (NDOS 0xDD80→0xDE80, NDOSRL 0xD980→0xDA80; BDOS 0xE716→0xE816 =
**+256 B user-visible TPA**).  Resident shifted up to match (BIOS
0xED00→0xEE00); CFGTBL relocated into IVT-page tail to release the
upper-region space needed for the move.  Trade-off: payload growth
budget halved from 92 B to 46 B.

## Init region vs cpnos.com payload (invariant)

**`.init` (decompressed at phase 2 to 0xC000) MUST NOT overlap with
`cpnos.com` (loaded from the master, lowest byte at NDOSRL).**  If
init grew above NDOSRL, the netboot LDIR that lands cpnos.com bytes
would overwrite the still-running init code during the same boot — a
silent corruption class that's hard to root-cause from logs.

Today's geometry (verified by `cpnos_addrs.h` rule):

| Boundary | Address | Constraint |
|---|---|---|
| `.init` floor | 0xC000 | `INIT ORIGIN` in `payload.ld` |
| `.init` ceiling | 0xC280 | `INIT LENGTH = 0x0280` ASSERT in `payload.ld` |
| (free) | 0xC280..0xDA7F | guaranteed ≥ 6144 B (= 6 KB) |
| `cpnos.com` NDOSRL | 0xDA80 | `DATA_BASE = DDA80` in `cpnos-build/Makefile` |

Defended at build time: the `$(BUILDDIR)/cpnos_addrs.h` rule extracts
NDOSRL from `cpnos-build/d/cpnos.sym` and fails the build if it falls
below the 0xC280 INIT ceiling.  Either reducing `DATA_BASE` (lowers
NDOSRL) or expanding `INIT LENGTH` (raises init ceiling) in a way that
violates the inequality fails fast with a clear error pointing at both
levers.

## How to refresh this doc

Numbers may shift on any change to `payload.ld` / `cpnos-build` / cpnos
source.  To re-derive:

```
cd cpnos-in-c
make prom1-lineprog            # gets you cpnos-build/d/cpnos.sym + .ld
# RAM regions:
awk '/^MEMORY/,/^}/' clang-prom1lineprog/payload.ld
# PROM1 image section addresses:
../../llvm-z80/build-macos/bin/llvm-nm \
    clang-prom1lineprog/prom1-lineprog.elf \
  | grep -E ' (bootstrap_entry|dzx0_standard|__(init|payload)_zx0_(start|end)|__prom1_used)$'
# cpnos.com (CCP+BDOS+NDOS) addresses (post-server-load):
grep -E '^[0-9A-F]+ (NDOSRL|NDOS|BDOSDS|BDOS|NIOS|BIOSEND)' \
    cpnos-build/d/cpnos.sym
```

## Stale-doc inventory (as of 2026-06-03)

| Path | Status |
|---|---|
| `cpnos-shared/docs/MEMORY_MAP.md` | **STALE.** Last touched 2026-05-16; ~20 references to the parked `cpnos-rom/` predecessor and to `payload.ld`/`relocator.ld`/`cpnos_rom.ld` deleted in the two-PROM cleanup.  Now a pointer to this doc. |
| `cpnos-in-c/docs/memory_map.md` | **THIS DOC.**  Authoritative current snapshot. |
| `cpnos-in-c/tasks/memory-layout-investigation-2026-05-06.md` | **HISTORICAL** — analysis doc, dated; not a current reference. |
