# Rapport: rcbios-in-c codegen-regressionsanalyse (nuværende vs pre-PR#40)

**Dato:** 2026-10-16  
**Baseline (pre-PR#40):** `scratch/pre-pr40-firmware-archive/` (compiler `d52e2334`, firmware snapshot `2951f96a`)  
**Nuværende (HEAD):** `rc700-gensmedet/rcbios-in-c` (LLVM-Z80 `a9c0a692`)

---

## 1. Overordnet sektions- og hukommelsesbudget

| Sektion | Pre-PR#40 (`d52e2334`) | Nuværende (`HEAD`) | Forskel (Δ) | Bemærkning |
|---|---|---|---|---|
| `.boot` | 128 B (`0x0080`) | 128 B (`0x0080`) | 0 B | Boot-header uændret |
| `.boot_data` | 512 B (`0x0200`) | 512 B (`0x0200`) | 0 B | CONFI-defaults + konverteringstabeller |
| `.boot_code` | 468 B (`0x01D4`) | 513 B (`0x0201`) | **+45 B (+9.6%)** | `coldboot` og `bios_hw_init` |
| `.bios_jt` | 113 B (`0x0071`) | 113 B (`0x0071`) | 0 B | CP/M hopvektortabel |
| `.text` (BIOS) | 4246 B (`0x1096`) | 5068 B (`0x13CC`) | **+822 B (+19.4%)** | BIOS-kode (største regression) |
| `.rodata` | 447 B (`0x01BF`) | 471 B (`0x01D7`) | **+24 B (+5.4%)** | Strenge, DPB/DPH-tabeller |
| `.data` | 2 B | 2 B | 0 B | |
| `.sentinel` | 2 B | 2 B | 0 B | |
| **Samlet binær (.cim)** | **5918 B** | **6339 B** | **+421 B (+7.1%)** | Binærfil på disk (inkl. boot) |
| `.bss` | 1783 B (`0x06F7`) | 1755 B (`0x06DB`) | **−28 B (−1.6%)** | BSS er faktisk faldet en smule |
| **Højeste RAM-adresse (`__bss_end`)** | **`0xF3C1`** (575 B fri) | **`0xF6F3`** (243 B overflow) | **+818 B** | **Overskrider stakgrænsen ved `0xF600`** |

### Hovedindsigt på makro-niveau
`.bss` er **ikke** vokset. Den er 28 bytes mindre end før PR#40.
Grunden til at linkeren fejler med `BIOS BSS overlaps interrupt stack (0xF600)! overflowed by 243 bytes` er, at `.text` og `.boot_code` er vokset med **+867 bytes**. Da BIOS-koden placeres fra `0xDA00` og `.bss` lægges umiddelbart efter koden, skubber den ekstra kode BSS 867 bytes op i RAM og ind over stakgrænsen ved `0xF600`.

---

## 2. Funktionsniveau: Størrelsesændringer og inlining-klynger

En differentiel symbolanalyse mellem pre-PR#40 ELF og nuværende inspektions-ELF viser en voldsom opsplitning af funktioner:

### Klynge A: Skærm/specc-klyngen (+216 B netto)
I pre-PR#40 blev alle hjælpefunktioner for skærmkontrol inlinede direkte ind i `specc()`. I den nuværende compiler er inlining afvist pga. TTI-konflikt:

| Funktion | Pre-PR#40 | Nuværende | Forskel (Δ) | Status |
|---|---|---|---|---|
| `_specc` | 664 B | 176 B | −488 B | Hovedfunktion skrumpet pga. manglende inlining |
| `_xwrite` | 0 B (inlined) | 198 B | +198 B | Nu separat funktion med prolog/epilog |
| `_delete_line` | 0 B (inlined) | 143 B | +143 B | Nu separat funktion |
| `_insert_line` | 0 B (inlined) | 130 B | +130 B | Nu separat funktion |
| `_erase_to_eol` | 0 B (inlined) | 89 B | +89 B | Nu separat funktion |
| `_erase_to_eos` | 0 B (inlined) | 60 B | +60 B | Nu separat funktion |
| `_clear_screen` | 0 B (inlined) | 44 B | +44 B | Nu separat funktion |
| `_clear_foreground`| 0 B (inlined) | 40 B | +40 B | Nu separat funktion |
| **Sum skærmklynge** | **664 B** | **880 B** | **+216 B (+32.5%)** | |

### Klynge B: Disk/FDC-klyngen (+111 B netto)
Hjælpefunktioner inlinede tidligere direkte ind i `sec_rw()`:

| Funktion | Pre-PR#40 | Nuværende | Forskel (Δ) | Status |
|---|---|---|---|---|
| `_sec_rw` | 251 B | 138 B | −113 B | Skrumpet pga. manglende inlining |
| `_fdc_general_cmd` | 0 B (inlined) | 93 B | +93 B | Nu separat funktion |
| `_fdc_read_result` | 0 B (inlined) | 74 B | +74 B | Nu separat funktion |
| `_flp_dma_setup` | 0 B (inlined) | 57 B | +57 B | Nu separat funktion |
| **Sum diskklynge** | **251 B** | **362 B** | **+111 B (+44.2%)** | |

### Klynge C: Konsol-input (+49 B netto)
| Funktion | Pre-PR#40 | Nuværende | Forskel (Δ) | Status |
|---|---|---|---|---|
| `_bios_conin` | 127 B | 55 B | −72 B | Skrumpet pga. manglende inlining |
| `_serial_conin` | 0 B (inlined) | 83 B | +83 B | Nu separat funktion |
| `_kbd_dequeue` | 0 B (inlined) | 38 B | +38 B | Nu separat funktion |
| **Sum konsol-input**| **127 B** | **176 B** | **+49 B (+38.6%)** | |

---

## 3. De 5 konkrete rodårsager på instruktionsniveau

### 1. Blokering af inlining for single-use funktioner (~376 B regression)
Clang-inlineren nægter nu at inline interne funktioner med beskeden:
`remark: 'delete_line' not inlined into 'specc' because it should never be inlined (cost=never): conflicting target features [-Rpass-missed=inline]`

**Årsag i compileren:**  
I `llvm/lib/Analysis/InlineCost.cpp` kaldes `TTI.areInlineCompatible(Caller, Callee)`.  
I pre-PR#40 tillod `Z80TTIImpl::areInlineCompatible`:
```cpp
if (Callee->hasInternalLinkage() && Callee->hasOneUse())
  return true;
```
Denne regel blev tabt i upstream PR#40-merget. Uden den afviser inlineren alle funktioner med > 10 instruktioner som værende i konflikt med target-features, selv for statiske funktioner med kun ét kaldssted. Det skaber 13 nye funktioner, der hver skal have egen prolog, epilog, `CALL`-instruktioner og egne stakrammer.

---

### 2. Indirekte 8-bit hukommelsesadgang (`LD BC/DE, addr; LD (BC/DE), A`) (~257 B regression)
Pre-PR#40 brugte direkte Z80-adressering for globale variable og static-frame slots:
- `32 nn nn`: `LD (addr), A` (3 bytes)
- `3A nn nn`: `LD A, (addr)` (3 bytes)

Nuværende compiler materialiserer adressen i et registerpar først:
- `01 nn nn`: `LD BC, addr` (3 bytes)
- `02`:       `LD (BC), A` (1 byte) -> **4 bytes (+33% kode)**

Optælling på tværs af hele BIOS'en:
- Pre-PR#40 `LD (BC/DE), A` eller `LD A, (BC/DE)`: **6 gange**
- Nuværende `LD (BC/DE), A` eller `LD A, (BC/DE)`: **263 gange**
Hvert tilfælde koster 1 ekstra byte plus allokator-pres på BC/DE, hvilket giver **~257 bytes** unødig kode.

---

### 3. IX Frame Pointer-overhead (~140 B regression)
Pre-PR#40 brugte `+static-stack` uden dynamisk IX-frame, medmindre det var absolut nødvendigt.  
Optælling af `push ix` i hele BIOS:
- Pre-PR#40: **0 gange** i hele BIOS!
- Nuværende: **14 gange**

Et typisk funktionshoved i nuværende compiler:
```z80
dd e5         push ix         ; 2 B
dd 21 00 00   ld   ix, 0      ; 4 B
dd 39         add  ix, sp     ; 2 B
f5            push af         ; 1 B
...
dd e1         pop  ix         ; 2 B
```
Overhead: Mindst 10 bytes pr. funktion * 14 funktioner = **~140 bytes**.

---

### 4. 16-bit stores via BC i stedet for HL (~50 B regression)
Ved 16-bit gemninger (fx `cpm_dma_addr`, `cpm_track`, `cpm_sector` i `wboot_c`):
- Pre-PR#40 brugte HL: `22 nn nn`: `LD (addr), HL` (3 bytes).
- Nuværende compiler vælger BC: `ED 43 nn nn`: `LD (addr), BC` (4 bytes, ED-præfiks).
Hver eneste 16-bit gemning koster 1 byte ekstra.

Tilsvarende for 16-bit sammenligning af 8-bit loop-tællere:
```z80
dcef: 79           ld a,c
dcf0: ee 2c        xor $2c
dcf2: b0           or b        ; 3 instruktioner (4 bytes)
```
mod pre-PR#40:
```z80
dc36: 7d           ld a,l
dc37: fe 2c        cp $2c      ; 2 instruktioner (3 bytes)
```

---

### 5. Eksplicitte ISR-wrappers (~50 B regression)
Efter PR#40 fjernede backendens automatiske `ei` før `reti`, måtte rcbios (commit `7131371`) indføre 10 eksplicitte assembly-wrappers i `bios_shims.s` (`push af/bc/de/hl; call body; pop; ei; reti`). Dette tilføjede ca. 50 bytes fast kode.

---

## 4. Samlet konklusion og handlingsplan

Regressionsbudgettet (+867 B kode):
1. **Manglende inlining (TTI `areInlineCompatible`):** ~376 B
2. **Indirekte `LD (BC/DE)` vs direkte `LD (addr)`:** ~257 B
3. **Unødvendige IX frame pointers:** ~140 B
4. **16-bit BC stores / loop-sammenligninger:** ~50 B
5. **ISR assembly-wrappers:** ~50 B  
**Total:** **~873 B** (matcher observeret kodevækst på 867 B).

### Anbefalede tiltag i prioriteret rækkefølge:
1. **Genindfør `Callee->hasInternalLinkage() && Callee->hasOneUse()` i `llvm-z80`'s `areInlineCompatible`:**  
   Dette vil alene reducere BIOS med **~376 bytes** og fjerne samtlige 243 bytes overflow over `0xF600` i ét hug, så Clang-BIOS igen kan bygge og boote!
2. **Fix direkte hukommelsesadressering i GlobalISel (`LD (addr), A` / `LD (addr), HL`):**  
   Vil hente yderligere **~250-300 bytes**.
3. **Undertryk IX-ramme for funktioner uden dynamiske stak-objekter:**  
   Vil hente yderligere **~140 bytes**.
