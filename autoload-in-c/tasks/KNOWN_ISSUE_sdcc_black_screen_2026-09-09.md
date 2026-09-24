# KNOWN ISSUE — SDCC autoload boots to a fully black screen (2026-09-09)

## Summary

The **SDCC** build of autoload-in-c (`make prom COMPILER=sdcc`) boots to a
**completely black screen** in MAME `regnecentralend rc702`. It issues **zero**
port-I/O writes to any CRT / DMA / CTC / FDC port — i.e. the PROM crashes or
halts *before* it ever runs the hardware-init sequence. The screen is black
because `init_crt()` / `init_display()` never execute.

This is an **SDCC-only** defect. The **clang** build on the identical source,
MAME, ROM slot and boot diskette drives the full, correct init sequence (see
evidence below). The production PROM is the clang build, so this does not block
the production boot path — it is filed to track the loss of SDCC MAME-parity.

## Environment

- Source: `rc700-gensmedet/autoload-in-c` @ git `a84218c` (branch `main`).
- SDCC toolchain: `z88dk:2.4` Docker image, `zcc +z80 -clib=sdcc_iy … --sdcccall 1`.
- SDCC PROM size: 3670 B (padded to 4096 for the MAME `roa375.ic66` slot).
- MAME: `regnecentralend` (SUBTARGET regnecentralen), driver
  `src/mame/regnecentralen/rc702.cpp`, PROM0 ROM_LOAD **temporarily 0x1000
  (4 KB)** with the S13/A11 jumper defaulted to 4 KB (both TEMP for the current
  boot-test work; 2 KB is the production hard cap).
- Boot diskette: in-tree `test-disks/SW1711-I8.imd` (== `~/Downloads/SW1711-I8.imd`,
  byte-identical, md5 `682f0c5e…`).

## Evidence — OUT port log (`mame_out_log.lua`, 3 emulated seconds)

Logger taps the Z80 IO space (ports 0x00–0xFF) and records every write to the
CRT (0x00/0x01), DMA (0xF2–0xFC), CTC (0x0C–0x0F) and FDC (0x04/0x05) ports.

**SDCC — 0 writes in 151 frames:**

```
# autoload OUT log — CRT/DMA/CTC/FDC port writes during boot
# 0 writes captured over 151 emulated frames
```

**clang — 57 writes, the complete correct sequence (excerpt):**

```
[f=4] OUT (0C),08 … (0F),01      ctc init
[f=4] OUT (F8),20 (FB),C0 (FA),00 (FB),4A   dma master clear + ch0/ch2 mode
[f=4] OUT (01),00 (00),4F (00),98 (00),7A (00),5D   init_crt: reset + 4 params
[f=4] OUT (01),80 (00),00 (00),00              init_crt: load cursor 0,0
[f=4] OUT (01),E0                              init_crt: preset counters
[f=42] OUT (FC),00 (F4),30 (F4),78 (F5),CF (F5),07 (FA),02   dma ch2 -> 0x7830, wc 0x07CF
[f=42] OUT (01),23                             crt start display (burst=0, 8 DMA cycles)
```

The clang sequence matches `rom.c:init_crt()` (lines 159–176) and
`init_display()` (lines 318–321) exactly, and the MAME lua confirms the DMA ch2
display base resolves to **0x7830** with the banner text present in RAM there.

## Interpretation

- The clang port-I/O path (`address_space(2)` → `OUT (n),A` / `IN A,(n)`) is
  verified **correct** end-to-end: CRT + DMA + CTC + FDC all programmed with the
  expected port/value pairs. The earlier "clang OUT is broken" hypothesis is
  **disproven** by this log.
- The SDCC PROM never reaches any `port_out()`. The fault is upstream of all HW
  init — most likely the self-relocation / entry sequence or a very early
  crash/HALT in the SDCC build. It is **not** a CRT-init bug per se; init is
  simply never reached.

## Repro

```bash
cd rc700-gensmedet/autoload-in-c
make prom COMPILER=sdcc
cp sdcc/prom0.ic66 ../../mame/roms/rc702/roa375.ic66
OUT_LOG=/tmp/sdcc_out.txt OUT_LOG_SECONDS=3 \
  ../../mame/regnecentralend rc702 -rompath ../../mame/roms \
  -nothrottle -window -skip_gameinfo -seconds_to_run 6 \
  -autoboot_script mame_out_log.lua \
  -flop1 "$(pwd)/test-disks/SW1711-I8.imd"
cat /tmp/sdcc_out.txt      # => 0 writes
```

Swap `sdcc` → `clang` to see the 57-write correct sequence.

## Status

**OPEN / PARKED.** SDCC autoload is MAME-parity only (production is clang). Not
on the critical path to `A>`. Next diagnostic if picked up: single-step the SDCC
PROM entry in the MAME debugger (or dump the first bytes at 0x0000 vs the reset
vector) to find where the SDCC boot dies before HW init.

## Related

- `mame_out_log.lua` — the OUT port logger used for the evidence above (new this session).
- Production boot path is clang; see `BOOT_SEQUENCE.md` and `tasks/finishing-checklist.md`.
