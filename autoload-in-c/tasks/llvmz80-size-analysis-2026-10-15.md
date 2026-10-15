# LLVM-Z80 PROM Size Analysis (2026-10-15)

Status and optimization paths for `autoload-in-c` built with `zcc +z80 -compiler=llvmz80`.

Target: Physical RC702 motherboard has 2716 EPROM sockets (no A11 bridge, PROM0 hard ceiling = 2048 B).
MAME format: 4096 B slot (`roa375.ic66`).

---

## 1. Baseline Measurements (2026-10-15)

Built with `make prom COMPILER=llvmz80` (default `zcc` flags: `-O2`, no `+static-frame`):

| Component | Size (bytes) | Range / Details |
|---|---|---|
| Decompressor + Reset + NMI pad (`_BOOT`) | 119 B | `0x0000` .. `0x0077` (retn at 0x0066) |
| ZX0 compressed payload | 2542 B | Compressed from 4730 B raw |
| **Total PROM (`llvmz80/prom.bin`)** | **2661 B** | MAME 4 KB slot: 1435 B free |
| **Gap to 2048 B physical target** | **+613 B** | |

### Uncompressed CODE breakdown (4730 B at 0x6000)

| Section | Size (bytes) | Range | Contents |
|---|---|---|---|
| `intvec_compiler` | 32 B | `0x6000` - `0x601F` | IM2 vector table (page-aligned at I=0x60) |
| `code_compiler` | 2990 B | `0x6020` - `0x6BCE` | Compiled C functions + delay loop |
| `rodata_compiler` | 1616 B | `0x6BCE` - `0x721E` | Font data, QR image, string constants, tables |
| `bss_compiler` | 35 B | `0x721E` - `0x7241` | Zero-initialized globals (zeroed by boot) |
| `code_string` / `code_l` | 57 B | `0x7241` - `0x727A` | z88dk runtime support (`memcpy`, `l_jpiy`) |

---

## 2. Top Symbols by Uncompressed Size

Measured via `llvmz80/prom0.map`:

| Size (B) | Symbol | Address | Section / Type | Notes |
|---|---|---|---|---|
| 1407 B | `_sem702_font` | `0x6923` | `rodata` | Full ROA327 font for SEM702 RAM |
| 207 B | `_main_relocated` | `0x60DA` | `code` | Peripheral initialization and boot setup |
| 165 B | `_fdc_read_data_from_current_location` | `0x64CC` | `code` | Multi-track floppy read loop |
| 160 B | `_boot_from_floppy_or_jump_prom1` | `0x637F` | `code` | Floppy detect and recalibrate |
| 152 B | `_boot_floppy_or_prom` | `0x6571` | `code` | Signature check (CP/M vs COMAL) |
| 125 B | `_display_sw1_status` | `0x62B0` | `code` | SW1 DIP-switch bit formatting |
| 117 B | `_qr_screen` | `0x6EB1` | `rodata` | 13x9 sextant QR code image |
| 110 B | `_fdc_get_result_bytes` | `0x66B5` | `code` | FDC command retry and DMA setup |
| 104 B | `_fdc_write_full_cmd` | `0x6798` | `code` | FDC 7-byte parameter block dispatch |
| 82 B | `_draw_qr` | `0x632D` | `code` | CRT refresh buffer QR renderer |
| 81 B | `_floppy_completed_operation_interrupt` | `0x6089` | `code` | IM2 CTC CH3 interrupt handler |
| 78 B | `_check_sysfile` | `0x682F` | `code` | COMAL directory entry scanner |
| 74 B | `_display_banner_and_start_crt` | `0x61CB` | `code` | CRT DMA channel-2 start + banner copy |
| 64 B | `_fdc_select_drive_cylinder_head` | `0x6675` | `code` | FDC Seek + verify wrapper |
| 64 B | `_lookup_sectors_and_gap3_for_current_track`| `0x6723` | `code` | Disk density geometry table lookup |
| 63 B | `_fdc_read_result` | `0x6215` | `code` | Result phase reading (up to 7 bytes) |
| 62 B | `_verify_seek_result` | `0x641F` | `code` | ST0 and PCN cylinder verification |
| 61 B | `_wait_fdc_ready` | `0x6609` | `code` | 255-iteration floppy completion polling |
| 59 B | `_fdc_detect_sector_size_and_density` | `0x6491` | `code` | Read ID probing for FM/MFM |

---

## 3. Optimization Path 1: Compiler Flags Only

The standalone clang target uses `-Oz` and `+static-frame` (via `-Xclang -target-feature -Xclang +static-frame`).
Passing these flags to clang through `zcc` via `-Cg-Oz -Cg-Xclang -Cg-target-feature -Cg-Xclang -Cg+static-frame`:

- `prom0_CODE.bin` raw size: **4730 B -> 4096 B** (−634 B uncompressed)
  - Eliminates dynamic IX frame setup/teardown and relative `(ix+d)` spills on non-reentrant functions.
- `text_compressed.zx0`: **2542 B -> 2280 B** (−262 B compressed)
- Total PROM (`prom.bin`): `119 B + 2280 B` = **2399 B**
- **Gap to 2048 B:** **+351 B** (reduced by 262 B without any source changes).

---

## 4. Optimization Path 2: Hardware Target Configuration (`INIT_SEM702=0`)

On physical RC702 machines with character generator in ROM (ROA327 ROM socket), soft-loading the font is unnecessary.

- `INIT_SEM702=0` omits `_sem702_font` (1407 B uncompressed).
- Compressed savings: **~377 B**.
- Combined with Path 1 (`-Oz +static-frame` + `INIT_SEM702=0`):
  `2399 B - 377 B` = **~2022 B**
- **Outcome: 2022 B <= 2048 B (26 B free on 2716 EPROM).**
- Target is met immediately for ROM-character-generator machines.

---

## 5. Optimization Path 3: Retaining Font in 2048 B (`INIT_SEM702=1`)

To fit code, font, and features inside 2048 B simultaneously, 351 B compressed (approx 500-600 B raw) must be recovered:

1. **Diagnostic features:**
   - QR code error display: `_draw_qr` (82 B) + `_qr_screen` (117 B) = 199 B raw -> **~130 B compressed**.
   - SW1 DIP display: `_display_sw1_status` (125 B) + prefix (19 B) = 144 B raw -> **~80 B compressed**.
   - Combined diagnostic savings: **~210 B compressed**.

2. **Code generation / factorization:**
   - Factorize FDC port wait loops: `fdc_write_when_ready` and `fdc_read_when_ready` inlining can be consolidated.
   - Investigate `-mllvm -z80-enable-licm -mllvm -z80-enable-cse` and backend peepholes.
   - Estimated potential: **~100-150 B compressed**.

3. **Combined potential:** 210 B + 140 B = **~350 B compressed**, bringing the full build to the 2048 B threshold.
