# Plan: Få `cpnos-in-c` under 2 KB PROM-grænsen med LLVM-Z80

**Dato**: 2026-10-18  
**Mål**: Gøre `make prom1-lineprog COMPILER=clang` i stand til at bygge en valid 2 KB EPROM-binær (`prom1-lineprog.bin` <= 2048 bytes) og passe under RAM-stakloftet (`0xF60E`) med den opdaterede LLVM-Z80 compiler.

---

## 1. Målinger & Nuværende Baseline

Efter PR #40 og nyere backend-opdateringer i `llvm-z80` har kodestørrelsen flyttet sig:

| Komponent | Juli 2026 (fungerende) | Nuværende baseline (okt 2026) | Delta | Budget / Grænse |
|---|---:|---:|---:|---:|
| `init.bin` (rå) | 605 B | **792 B** | +187 B | Decompresses til RAM 0xC000 |
| `init.zx0` (komprimeret) | 526 B | **656 B** | +130 B | I PROM1 |
| `payload.bin` (rå resident) | 1986 B | **2268 B** | +282 B | Max 2062 B (0xF60E stak-loft) |
| `payload.zx0` (komprimeret) | 1384 B | **1616 B** | +232 B | I PROM1 |
| Bootstrap + header | ~102 B | ~102 B | 0 B | I PROM1 |
| **Samlet PROM1 binær** | **2011 B** (37 B fri) | **2374 B** | **+363 B** | **2048 B hard cap** |

### Aktuelle build-fejl
1. **Linker fejl i `payload.ld`**:
   - `ld.lld: error: .init exceeds 640 B INIT region budget` (forældet grænse arvet fra to-PROM layoutet).
   - `ld.lld: error: payload grew into stack workspace at 0xF60E` (payload er 2268 B mod loft på 2062 B = 206 B for stor i RAM).
2. **Linker fejl i `prom1.ld`**:
   - `ld.lld: error: PROM1 line program exceeds 2 KB hard cap` (2374 B mod max 2048 B = 326 B overflow).

---

## 2. Hovedårsager & Løsningsstrategi

For at bringe PROM1 under 2048 B skal vi reducere den komprimerede størrelse med **>= 326 bytes** (svarer til ~400-500 bytes rå kode). 
Samtidig skal rå `payload.bin` reduceres med **>= 206 bytes** for ikke at overlappe stakken ved `0xF60E`.

Vi angriber problemet i 4 velafgrænsede trin:

```
[Trin 1: Opret RegisterNullTargetStreamer i llvm-z80]
                       ↓
[Trin 2: Slå -flto til i cpnos-in-c/Makefile]
                       ↓
[Trin 3: Ryk dual-transport til opt-in (fokuser på primær PIO)]
                       ↓
[Trin 4: Opdater payload.ld & kør end-to-end MAME PolyPascal test]
```

---

## 3. Trin-for-trin Plan

### Trin 1: Implementer `RegisterNullTargetStreamer` i `llvm-z80`
- **Hvorfor**: `clang -flto` crasher i dag på `bios_jt.c` med:
  `fatal error: error in backend: target did not implement null MCTargetStreamer`
  fordi LLVM Z80 TargetMC mangler standard null-streameren som ModuleSymbolTable kræver ved module-level inline asm under LTO.
- **Handling**:
  - Tilføj `createNullTargetStreamer` i `llvm/lib/Target/Z80/MCTargetDesc/Z80MCTargetDesc.cpp` (4 linjer, identisk med AVR/MSP430/NVPTX).
  - Registrer i `LLVMInitializeZ80TargetMC()`.
  - Kør lit-tests og rebuild ninja `llvm-z80`.

### Trin 2: Undersøg og aktiver `-flto` i `cpnos-in-c`
- **Hvorfor**: `-flto` tillader cross-module dead-code elimination, inlining og konstant-propagering på tværs af `init.c`, `cpnos_main.c`, `resident.c` og `snios_c.c`. I `rcbios-in-c` sparede dette over 1000 bytes.
- **Handling**:
  - Tilføj `-flto` til `CFLAGS` i `cpnos-in-c/Makefile`.
  - Mål reduktionen i både rå kode og ZX0-komprimeret output.

### Trin 3: Single-transport som standard (`TRANSPORT=pio-irq`)
- **Hvorfor**: I juli 2026 blev dual-transport (både PIO og SIO i samme binær) tilføjet. Det kostede +69 B i PROM1 alene til trampoliner (`xport_jt.c`), runtime-patching i `init.c` og `transport_sio.o`.
- **Handling**:
  - Gør dual-transport valgfrit (`DUAL_TRANSPORT ?= 0`).
  - Når `DUAL_TRANSPORT=0`, aliaser `_xport_send_byte` og `_xport_recv_byte` direkte til `_transport_pio_send_byte` / `recv_byte` via `--defsym` (ligesom før juli 2026), og udelad `xport_jt.o` og `transport_sio.o`.
  - Forventet gevinst: ~150-200 bytes rå kode, ~80-120 bytes komprimeret.

### Trin 4: Sanér `clang-prom1lineprog/payload.ld`
- **Hvorfor**: `ASSERT(__init_size <= 0x0280)` (640 B) var en rest fra det slettede to-PROM build (hvor PROM0 havde et 640 B vindue). I `prom1-lineprog` dekomprimeres `init` til `0xC000` i RAM, hvor der er 7,8 KB fri plads før NDOS (`0xDE80`).
- **Handling**:
  - Fjern den forældede 640 B assertion for `INIT`.
  - Behold de reelle grænser: `__payload_end <= 0xF60E` (stak-loft) og `__prom1_used <= 0x2800` (2 KB PROM1 cap).

### Trin 5: Yderligere kildetekst-optimeringer (hvis nødvendigt)
- Hvis LTO + single-transport mod forventning ikke alene er nok til at dække de 326 bytes:
  - Slank opstarts- og banner-tekster i `src/init.c` (sparer ~40-60 B).
  - Optimér `try_recv_frame` / `try_send_frame` i `src/snios_c.c` (sparer ~50-80 B).

### Trin 6: Verifikation
- Bekræft `prom1-lineprog.bin` <= 2048 bytes via build-systemets størrelses-check.
- Kør `make cpnos-polypascal-test COMPILER=clang` (kører MAME mod MP/M master, booter til `E>`, afvikler PolyPascal PRIMES til 29989 og afslutter til prompt).
- Commit & dokumentér i `tasks/timeline.md`.
