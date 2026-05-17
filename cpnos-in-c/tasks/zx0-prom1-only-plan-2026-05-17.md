# cpnos-in-c -> PROM1-only line program with ZX0

Status: planned, not started. Measurements verified 2026-05-17.

## Goal

Make cpnos-in-c fit entirely in PROM1 (2 KB at 0x2000) as a PROM1 line
program (signature contract matching cpnos-in-asm/autoload-in-c's
`prom1_if_present`), so PROM0 can hold autoload-in-c (1509 B post-ZX0,
539 B free) and the system has a clean two-PROM layout:

- **PROM0 = autoload-in-c**: boots from floppy OR chains to PROM1
  line program if present.
- **PROM1 = cpnos-in-c**: signature + bootstrap + ZX0 decoder + two
  compressed blobs (init at new RAM VMA + resident payload at 0xED00).

Mirrors the working cpnos-in-asm pattern.

## Measurements (clang, 2026-05-17, HEAD a358bb0)

| Component                       | Raw   | ZX0   | Saved |
| ------------------------------- | ----- | ----- | ----- |
| init.bin                        | 626   | 546   | 80    |
| payload.bin (resident)          | 1858  | 1275  | 583   |
| **Total**                       | **2484** | **1821** | **663** |

PROM1 budget audit:

| Section                         | Bytes |
| ------------------------------- | ----- |
| Header (jump target + " RC702") | 8     |
| Bootstrap (set SP, 2x dzx0, jp init) | ~60 |
| dzx0_standard                   | 68    |
| init.zx0                        | 546   |
| payload.zx0                     | 1275  |
| **Total**                       | **~1957** |
| **PROM1 free**                  | **~91** |

PROM0 already at 1509 B / 2048 (539 B free) from this session's
autoload-in-c ZX0 work.

## Architectural approach

Two separate ZX0 blobs (not one combined), each decompressed by a
distinct call to the same 68 B `dzx0_standard`:

- **Blob 1**: init.zx0 -> RAM 0xC000 (or wherever; init.c gets a new
  VMA). Init code calls into the resident SNIOS so it must run after
  the resident is decompressed.
- **Blob 2**: payload.zx0 -> RAM 0xED00 (unchanged from today).

Boot flow:
```
PROM1 entry (0x2008 say):
    di
    ld sp, 0xF700                   ; same as today
    ld hl, payload_zx0
    ld de, 0xED00
    call dzx0_standard              ; resident now live
    ld hl, init_zx0
    ld de, 0xC000
    call dzx0_standard              ; init code now in RAM
    jp 0xC000                       ; init runs, ends with resident_handoff
```

## Files to add / change

1. `cpnos-in-c/prom1-only/prom1.ld` (NEW) -- linker script:
   - .header at 0x2000 (8 B: jump-word + " RC702")
   - .bootstrap at 0x2008 (~60 B)
   - .zx0_decoder (68 B)
   - .init_zx0 (incbin init.zx0, ~546 B)
   - .payload_zx0 (incbin payload.zx0, ~1275 B)
   - PROM1 ORIGIN=0x2000, LENGTH=0x0800.

2. `cpnos-in-c/prom1-only/bootstrap.s` (NEW) -- header + entry asm.

3. `cpnos-in-c/prom1-only/dzx0_standard.s` (NEW) -- 68 B decoder copy.
   (Already present in autoload-in-c/clang/dzx0_standard.s and
   cpnos-in-asm/src/prom1.asm; same bytes, verbatim.)

4. `cpnos-in-c/clang/payload.ld` -- change `.init` MEMORY ORIGIN
   from 0x02A0 to 0xC000 (or chosen RAM address). VMA shift only;
   init.c source unchanged.

5. `cpnos-in-c/Makefile` -- add `prom1-only` target:
   - Build init.bin at new VMA
   - Build payload.bin as today
   - ZX0-compress both separately
   - Roundtrip-verify both via z88dk-dzx0 (memory rule from
     autoload-in-c session this morning)
   - Link bootstrap + decoder + two incbin blobs into prom1-lineprog.bin
   - 2 KB ASSERT on output size

6. Optionally split into a parallel build path that doesn't disturb
   the existing PROM0+PROM1 split builds until verified working.

## RAM map for init's new VMA

init code calls into resident at 0xED00..0xED7F (BIOS JT, SNIOS JT,
isr_*). Init itself runs once and exits via `resident_handoff(entry)`
to NDOS at 0xDD80. Candidate RAM ranges for init's VMA:

- **0xC000..0xC500**: well below NDOS (0xDD80) and resident (0xED00).
  640 B fits. After handoff, this region becomes part of TPA available
  for CP/M programs. Recommended.
- **0xEB00..0xED00**: today's SCRATCH region (512 B); too small for
  init at 626 B.
- **0xF700..0xF800**: too small (256 B) and conflicts with PIO_RX.

Recommendation: 0xC000.

## Open questions before implementing

1. **Init VMA = 0xC000 safe?**  Need to confirm 0xC000..0xC272 doesn't
   collide with any other reserved region. Today the TPA starts at
   0x0100 and extends to BDOS at ~0xDD80; 0xC000 is inside TPA but
   init runs BEFORE NDOS, so TPA isn't yet user-visible.

2. **PROM1-only chaining via autoload?**  autoload-in-c's
   `_prom1_if_present` jumps to *(word*)0x2000 if it sees " RC702"
   at 0x2002. The two existing line programs (cpnos-in-asm,
   cpnos-in-c-prom1) both satisfy that contract; both can be
   installed in the PROM1 slot interchangeably.

3. **SDCC path.**  cpnos-in-c builds with both clang and SDCC. Memory
   rule `feedback_symmetric_recipes_per_compiler` requires parallel
   recipes. The init.c VMA change cascades through SDCC's z88dk
   build too. Audit needed.

4. **4-cell value oracle.**  Memory rule
   `feedback_value_oracle_all_transport_cells` requires runtime test
   across clang/sdcc x PIO/SIO. cpnos-polypascal-test (~4 min) is the
   end-to-end check.

5. **Init can stay PROM-resident as a fallback.**  If init's relink
   to RAM-VMA hits unexpected codegen issues (function pointers in
   init's IVT registration, etc.), the fallback is: keep init in
   PROM1 at VMA inside 0x2000-0x27FF, no second decompression. Costs
   ~80 B vs the compressed-init plan. PROM1 budget stays viable at
   ~2027 B / 21 B free.

## Stages

- **Stage 1**: write bootstrap.s, dzx0_standard.s, prom1.ld, Makefile
  recipe. Compile, hand-inspect the produced PROM1 binary.
- **Stage 2**: install via autoload-in-c (sw1-mode -> auto-detect
  PROM1). Boot in MAME, verify banner appears, CP/NET LOGIN succeeds,
  resident handoff reaches NDOS at 0xDD80.
- **Stage 3**: cpnos-polypascal-test against the new layout. PASS
  required across all 4 cells before keeping the new path.

## Why not implement now

Multi-hour refactor with 4-cell verification budget. This session
already completed autoload-in-c ZX0 (verified PASS) + cpnos-in-asm
PPAS PASS. Stage gate is: focused session with dedicated time for
build-debug + 4-cell value oracle.

Numbers and plan are now concrete enough to execute in one focused
session without re-discovery.
