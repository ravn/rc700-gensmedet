# RC702 Boot Sequence

Order of invocation from power-on to CP/M `A>` prompt.

## Boot priority (TL;DR)

The floppy is tried first; PROM1 (cpnos-in-asm / lineprog) is the
fallback when the floppy path can't proceed.  Three gates inside
`boot_from_floppy_or_jump_prom1` decide the outcome:

| Floppy state                                  | Outcome                                  |
|-----------------------------------------------|------------------------------------------|
| Bootable CP/M disk in drive (Track 0 sig)     | **CP/M boots**; PROM1 ignored            |
| ID-COMAL disk in drive (` RC700` at 0x0002)   | **COMAL boots** from 0x1000; PROM1 ignored |
| No disk / drive not ready                     | **PROM1 lineprog runs** (e.g. cpnos-in-asm) |
| Disk present, format not detectable           | **PROM1 lineprog runs**                  |
| Disk present, readable, no recognised sig     | Halt `** NO KATALOG **` (PROM1 **not** consulted) |
| PROM1 also absent / no ` RC702` signature     | Halt `** NO DISKETTE NOR LINEPROG **`    |

The first three rows are the common cases.  The fifth row (readable
disk with no signature) is a gap: autoload halts rather than falling
back to PROM1.  Don't insert a non-CP/M readable disk if you want the
PROM1 path to run -- eject the disk instead.

Detail of each gate is in Phases 5 and 6 below.

## Memory map

The autoload PROM is **2 KB** — the physical RC702 PROM socket has no A11
bridge, so addresses ≥ 0x0800 do not exist on the hardware (the `.ic66` file is
padded to 4 KB for the MAME socket only).  At power-on the ROM decompresses its
payload with a ZX0 decoder into RAM, then runs from RAM.  All sizes below are
from the current clang build (`llvm-nm clang/prom.clang.elf`).

### ROM — before ZX0 decompression (physical PROM0, 0x0000–0x07FF)

The ZX0 decoder is **split around the NMI vector** to fill the otherwise-wasted
pre-NMI ROM, and the banner lives in the compressed payload (not raw in ROM):

| Address | Size | Contents |
|---|---|---|
| `0x0000` | 33 B | `.boot` — `start()` (DI, set SP, `reloc_zx0()`, jump) |
| `0x0021` | ~57 B | `.zx0_decoder` — ZX0 decoder **main loop** (`_reloc_zx0` + `dzx0_standard` … `dzx0s_new_offset`) |
| `~0x005C`–`0x0066` | ~10 B | padding (`0xFF`) |
| `0x0066` | 2 B | `.nmi` — NMI handler (`RETN`) at the Z80 hardwired vector |
| `0x0068` | ~15 B | `.zx0_decoder_hi` — decoder **tail** (`dzx0s_elias` subroutine), reached only by `CALL` |
| `0x0077` | **1524 B** | `.text_compressed` — ZX0-compressed payload (now includes the banner) |
| `0x066B` | | `__prom_end` — **PROM used = 1643 B** |
| `0x066B`–`0x07FF` | 405 B | free (`0xFF`) |
| `0x0800` | | **2 KB hard cap** (A11 not bridged) |

### RAM — after ZX0 decompression (0x6000–0xBFFF)

`start()` → `reloc_zx0()` → `dzx0_standard` decompresses `.text_compressed` to
0x6000, then jumps there.

| Address | Size | Contents |
|---|---|---|
| `0x6000` | 1996 B | `_intvec` (IM2 vector table) + `.text` code + rodata + `banner_string` (`__code_start`; I-reg = 0x60) |
| `0x679D` | 47 B | `banner_string` (decompressed here; `BANNER_PTR = &banner_string`) |
| `0x67CC` | 53 B | `.bss` (`__bss_start`) |
| `0x6801` | | `__bss_end` — end of the decompressed image |
| `0x6801`–`0x782F` | ~4 KB | free RAM |
| **`0x7830`** | 2000 B | **display framebuffer** (80×25, `DSPSTR_ADDR`, via DMA ch2) — ends at 0x8000 |
| `0x8000`–`0xBFFE` | 16 KB | free RAM (upper half) |
| `0xBFFF` | | stack top (`ROM_STACK`, grows down) |

**Pre-NMI packing (2026-07-01).**  The 74 B ZX0 decoder used to sit entirely
after the NMI vector (payload started at 0x00B3), and the banner was 47 raw
bytes at 0x0021.  Now the decoder's main loop fills the pre-NMI region (0x0021)
and its elias tail goes after the NMI at 0x0068 — a clean split because
`dzx0s_new_offset` ends in an unconditional `jr`, so the tail is only reached by
`CALL` (no branch crosses the gap, no bridge instruction).  The banner moved
into the compressed payload.  Net PROM: 1663 → 1643 B (payload start 0x00B3 →
0x0077 = −60 B, minus ~40 B the banner adds compressed — its date+hash don't
compress well).  A linker `ASSERT(. <= 0x0066)` fails the build if the pre-NMI
decoder part ever overruns the NMI vector.

**32 KB → 64 KB history.**  The original roa375 ROM placed its display at 0x7800
— the top of a 32 KB machine's RAM (0x0000–0x7FFF).  The C rewrite targets 64 KB
machines: the stack moved up to 0xBFFF (upper RAM), and clang's larger code
relocates to 0x6000 (SDCC uses 0x7200).  The clang display sits just below 0x8000
(0x7830) so it stays entirely inside the original lower 32 KB; the old 0x7A00
crossed 0x8000 into RAM that only exists on 64 KB machines.  (The SDCC parity
build keeps the display at 0x7A00 — its code at 0x7200 would overlap 0x7830 — and
is MAME-only / 64 KB-emulated.)

## Phase 1: ROM self-relocation (BOOT section, 0x0000)

```
start()                              boot_rom.c — ROM entry at 0x0000
  intrinsic_di()                       disable interrupts
  set SP = 0xBFFF                      initialize stack
  reloc_zx0()                          ZX0-decompress .text_compressed → RAM 0x6000
  <tail JP>                            jump into the relocated code at 0x6000
```

## Phase 2: Hardware initialization (CODE section, 0x6000+)

```
main_relocated()                     rom.c — runs from RAM at 0x6000
  set_i_reg(INTVEC_PAGE)               I register = IVT page (0x60 clang / 0x72 SDCC)
  intrinsic_im_2()                     Z80 interrupt mode 2
  init_peripherals()                   PIO, CTC, DMA, CRT port setup
  main()                               fall-through (tail call)
```

## Phase 3: Pre-boot setup (main → get_floppy_ready)

```
main()                               rom.c — entry point after hw init
  init_fdc()                           boot_rom.c — FDC Specify command (BOOT section)
  clear_screen()                       boot_rom.c — memset display (BOOT section)
  display_banner_and_start_crt()       rom.c — " RC700 gensmedet" + start CRT DMA
  get_floppy_ready()                   fall-through (tail call)
```

## Phase 4: Floppy detection (get_floppy_ready → boot_from_floppy_or_jump_prom1)

```
get_floppy_ready()                   rom.c — set timeouts, read SW1
  ei()                                 enable interrupts (ISRs now active)
  motor(1)                             turn on floppy motor
  boot_from_floppy_or_jump_prom1()     fall-through (tail call)
```

## Phase 5: Floppy boot (boot_from_floppy_or_jump_prom1)

```
boot_from_floppy_or_jump_prom1()     rom.c
  delay(1, 0xFF)                       wait for motor spin-up
  FDC Sense Drive Status               check drive ready (ST3)
  FDC Recalibrate                      seek to track 0
  chk_seekres(0)                       verify at cylinder 0
    ── on failure: prom1_if_present() → jump 0x2000 or halt ──

  fdc_detect_sector_size_and_density() detect side 1 format (head=1)
    fdc_select_drive_cylinder_head()     seek to cylinder/head
    fdc_get_result_bytes(READ_ID)        read sector ID (C/H/R/N)
    format_lookup()                      set EOT, gap3, DTL from tables
    calc_size_of_current_track()         compute transfer byte count

  fdc_detect_sector_size_and_density() detect side 0 format (head=0)
    ── on failure: prom1_if_present() → jump 0x2000 or halt ──

  prom_disable()                       *** ROM no longer accessible ***

  loop:                                read Track 0 data to RAM at 0x0000
    fdc_read_data_from_current_location(dma_transfer_size)
      fdc_select_drive_cylinder_head()   seek
      calc_size_of_current_track()       compute this track's byte count
      fdc_get_result_bytes(READ_DATA)    DMA transfer: disk → RAM
      advance head/cylinder              next side or next track
    if cylinder != 0: break            done when we leave track 0
    fdc_detect_sector_size_and_density() re-detect for new track/side

  boot_floppy_or_prom()                verify Track 0 and boot
```

## Phase 6: Signature check and jump (boot_floppy_or_prom)

```
boot_floppy_or_prom()                rom.c — check Track 0 signatures

  Path A: " RC702" at offset 0x0008   CP/M format
    jump_to(*(word *)0x0000)             jump via boot vector → CP/M cold boot

  Path B: " RC700" at offset 0x0002   ID-COMAL format
    check directory for SYSM + SYSC      verify system files present
    floppy_boot()                        read COMAL boot area
      fdc_read_data_from_current_location(0x300)
      jump_to(0x1000)                    jump to COMAL entry point

  Path C: no signature found
    halt_msg(" **NO KATALOG** ")         display error, halt forever

  Path D: floppy errors at any point
    prom1_if_present()                   check PROM at 0x2000 for network boot
      jump_to(*(word *)0x2000)           jump if " RC702" signature found
      halt_msg("NO DISKETTE...")         otherwise halt forever
```

## Interrupt service routines (active from Phase 4 onward)

```
refresh_crt_dma_50hz_interrupt()     CTC Ch2 — programs DMA Ch2 for
                                       display refresh every frame

floppy_completed_operation_interrupt() CTC Ch3 — sets floppy_operation_completed_flag,
                                       reads FDC result or senses interrupt
```

## Notes

- **BOOT section functions** (`init_fdc`, `clear_screen`) run from ROM
  and are inaccessible after `prom_disable()`.
- **Tail-call fall-through** chains: `main` → `get_floppy_ready` →
  `boot_from_floppy_or_jump_prom1` — no return addresses on stack.
- The boot ROM never returns — all paths end in `jump_to()` or
  `halt_forever()`.
