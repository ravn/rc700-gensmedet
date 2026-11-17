# Z80 Codegen Sammenligning: LLVM-Z80 (Clang) vs. ZSDCC (SDCC 4.6.0)

**Dato:** 2026-11-17  
**Kontekst:** Autoload PROM (`autoload-in-c`) til RC702 (IC66 2716 EPROM, 2.048 byte fysisk grænse)  
**Artefakter undersøgt:**
- Clang / LLVM-Z80: `clang/prom.clang.lis` (kompileret med `clang --target=z80 -Oz -nostdlib -ffunction-sections -fdata-sections -Xclang -target-feature -Xclang +static-frame`)
- ZSDCC: `zsdcc/rom.asm` og `zsdcc/prom0.map` (kompileret med `zsdcc 4.6.0 #16639`, `+z80 -clib=sdcc_iy --no-crt --opt-code-size -SO3 -Cs"--sdcccall 1" -Cs"--fomit-frame-pointer" -Cs"--allow-unsafe-read" -Cs"--max-allocs-per-node 1000000"`)

---

## 1. Overordnede Nøgletal

| Metrik | LLVM-Z80 (Clang) | ZSDCC 4.6.0 | Forskel |
|---|---:|---:|---:|
| **Fysisk PROM (`prom.bin`)** | **2.025 B** | **2.022 B** | **ZSDCC -3 B** |
| Ledig plads under 2.048 B grænsen | 23 B fri | 26 B fri | ZSDCC +3 B |
| **ZX0-komprimeret payload** | **1.921 B** | **1.918 B** | **ZSDCC -3 B** |
| Ukomprimeret payload i RAM | 3.369 B | 3.403 B | Clang -34 B (pga. BSS) |
| -> *Aktiv kompileret C-kode* | 1.605 B | 1.547 B | **ZSDCC -58 B** |
| -> *Død kode (`_syscall` + stubbe)* | 0 B (LTO DCE) | 57 B | Clang fjerner død kode |
| `bss_compiler` i payload | 0 B (separat `.bss`) | 35 B (nuller i blob) | ZSDCC inkluderer BSS i binary |
| **ZX0-komprimeringsgrad** | **57,02 %** | **56,36 %** | ZSDCC -0,66 %-point |

### Forklaring på ZX0-komprimeringsgraden
En bit-for-bit dekodning af de to `.zx0`-filer viser, at ZSDCC's lavere samlede komprimeringsprocent (56,36 % vs. 57,02 %) næsten udelukkende skyldes de 35 efterfølgende nulbytes i ZSDCC's `prom0_CODE.bin` fra `bss_compiler`. ZX0 koder 35 fortløbende nuller på kun **5 bytes** (13,5 % ratio). Renses der for BSS-nullerne, komprimerer den faktiske kode og data næsten identisk (~56,9 % mod 57,0 %).

---

## 2. Funktions-eksempler side-om-side

### 2.1 Registerpres i tætte loops: `draw_qr()`
*Kildekode:* Kopiering af 117 QR-celler (13×9) med spring på `+67` pr. række.

- **ZSDCC (38 bytes, 0 spills, 53T/celle)**:
  - Allokerer alle 4 live variabler (`s`, `d`, `c`, `r`) i henholdsvis `BC`, `DE`, `H` og `L`.
  - Opdaterer `DE += 67` i 8-bit: `add a, 0x43; ld e, a; jr nc, ...; inc d`.
  - Nul hukommelses-spills.
- **Clang (105 bytes, +67 B spild, ~248T/celle — 4,7× langsommere)**:
  - LLVM-Z80 registerallokator bryder sammen under registerpres ved 4 live variabler under `+static-frame`.
  - Spiller 5 variabler til 7 bytes i static RAM (`$6d54..$6d5b`).
  - Genberegner `s+c` og `d+c` med 16-bit `add hl, bc` i hver iteration og udfører 6 RAM-tilgange samt `push`/`pop` pr. celle.

### 2.2 Kortvarige spills omkring funktionkald: `wait_fdc_ready`
*Kildekode:* Loop der poller FDC med `delay(1, 2)` mellem forsøg.

- **ZSDCC (33 bytes)**:
  - Bevarer poll-tælleren i `C` hen over `_delay` med `push bc` og `pop bc` = **2 bytes, 21T**.
- **Clang (42 bytes)**:
  - Fordi `A` og `L` er låst af parametre til `delay`, kan Clang ikke direkte bruge `HL`. Den laver en "spill-dans" til static RAM:
    `push hl; ld hl, $6d5d; ld (hl), b; pop hl` og genindlæser med `ld a, ($6d5d); ld b, a` = **10 bytes og 69T**!

```asm
; Clang spill omkring call (10 B, 69T):    ; ZSDCC spill omkring call (2 B, 21T):
    push hl                                    push bc
    ld   hl, $6d5d                             ld   l, 0x02
    ld   (hl), b                               ld   a, 0x01
    pop  hl                                    call _delay
    call _delay                                pop  bc
    ld   a, ($6d5d)
    ld   b, a
```

### 2.3 Pointer-bevarelse vs. base-genberegning: `check_sysfile`
*Kildekode:* Tjekker 4-tegns filnavn, derefter attributbyte på offset `dir + 8`.

- **ZSDCC (32 bytes, 295T)**:
  - Efter at have scannet de 4 tegn står `HL` på `dir + 5`.
  - ZSDCC fortsætter blot: `inc hl; inc hl; inc hl` (**3 bytes, 18T**) og læser attributten med `ld a, (hl)`.
- **Clang (40 bytes, 320T)**:
  - Gemmer startadressen `dir` i static RAM (`ld ($6d5c), bc` = 4 B).
  - Genindlæser den efter loopet (`ld hl, ($6d5c)` = 3 B) og lægger 8 til (`ld bc, 8; add hl, bc` = 4 B) = **11 bytes, 57T**.

### 2.4 16-bit register-aritmetik: `fdc_read_data_from_current_location`
*Kildekode:* 16-bit sammenligning og subtraktion: `bytes_left_to_read -= dma_transfer_size`.

- **Clang (124 bytes)**:
  - Vinder stort (**-22 bytes** mod ZSDCC).
  - Holder `bytes_left_to_read` i `HL` og `dma_transfer_size` i `BC`.
  - Udfører 16-bit subtraktion med en enkelt ren `and a; sbc hl, bc` (3 bytes) og deler store-koden.
- **ZSDCC (146 bytes)**:
  - Håndterer 16-bit sammenligninger og subtraktioner via gentagne 8-bit `sub`/`sbc` i hukommelsen byte-for-byte og duplikerer koden i begge grene (+23 bytes).

### 2.5 Bit-manipulation & IPCP: `fdc_write_when_ready`
- **Clang (24 bytes)**:
  - Matematisk bitmask-optimering: `(x & 0xC0) == 0x80` omskrives til `(x ^ 0x80) < 0x40`.
  - Kodes som: `xor 0x80; cp 0x40; jr c, .Lready` (sparer 2 bytes `and 0xc0`).
  - Interprocedural konstantpropagering (IPCP): Clang ser at `wait_fdc_ready` kun kaldes med `0xFF`, propagerer konstanten og udelader `ld a, 0xff` hos callers.
- **ZSDCC (26 bytes)**:
  - Koder traditionelt: `and 0xc0; cp 0x80; jr nz, ...`.
  - Spilder 2 bytes / 12T på overflødig `jr` til fælles `ret`.

---

### 3. Arkitektur & Optimizer-karakteristik

#### Calling Conventions
Begge compilere benytter register-ABI svarende til `sdcccall(1)`:
- 1. argument: 8-bit i `A`, 16-bit i `HL`.
- 2. argument: 8-bit i `L`, 16-bit i `DE`.
- Returværdi: 8-bit i `A`.
- `AF`, `BC`, `DE`, `HL` er caller-saved. Ingen funktion i `rom.c` overskrider 2 argumenter.

#### Registerallokering & Spills
- Hverken Clang eller ZSDCC bruger `IX` eller `IY` i genereret kode.
- **ZSDCC** er overlegen i 8-bit subregister-pakning (`B, C, D, E, H, L` uafhængigt) og bruger billige `push rr / pop rr` (1-2 bytes) omkring kald.
- **LLVM-Z80 (`+static-frame`)** mangler fleksibilitet ved registermangel. I stedet for at pushe på stakken udlægges variabler i absolutte RAM-adresser (`$6d5x`), hvilket koster 3-4 bytes pr. adgang plus ekstra register-shuffling for at frigøre adresse-registre.

#### Dead Code Elimination & Inlining
- **Clang + LTO** fjerner ubrugte `static` funktioner (herunder `_syscall`, hvilket sparer 56 bytes) og inliner små hjælpefunktioner rent (`set_i_reg`, `fdc_seek`, `init_devices`).
- **ZSDCC** efterlader ubrugte `static` funktioner i koden (`_syscall` koster 56 B i ROM/RAM).

---

### 4. Konkrete Optimeringsanbefalinger

#### A. Kildekode-forbedringer (`rom.c`)
1. **Fjern utilsigtet 16-bit int-promotion i betingelser**:
   I `boot_from_floppy_or_jump_prom1`:
   ```c
   // Før: status != (drive_select + 0x20) -> udløser 16-bit add hl, de i BÅDE Clang og ZSDCC (14-16 B)
   // Efter: status != (byte)(drive_select + 0x20) -> kodes som ren 8-bit add a, 0x20 (sparer 8-10 B)
   ```
2. **Ekskluder ubrugt kode i SDCC**:
   Sæt `#ifndef __SDCC` omkring `_syscall` for at spare 56 bytes i ZSDCC.

#### B. LLVM-Z80 Backend-forbedringer
1. **Korte spills omkring calls**:
   I `+static-frame` tilstand bør variabler med kort levetid (spændende over et enkelt `call`) allokeres til `push rr / pop rr` frem for absolutte RAM-adresser i static-frame sektionen.
2. **Foretræk `HL` til 16-bit absolutte loads/stores**:
   `ld hl, (nn)` er 3 bytes (opcode `2A`), mens `ld bc, (nn)` og `ld de, (nn)` er 4 bytes (opcode `ED 4B` / `ED 5B`). LLVM-Z80 vælger ofte `BC` uden grund.
3. **Peephole: redundant load-after-store**:
   Fjern mønstre som `ld ($6d54), a; ld a, ($6d54)` (set i `main_relocated`).
