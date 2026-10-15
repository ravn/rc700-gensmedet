# Rapport: Optimering af `autoload-in-c` og opnåelse af 2 KB EPROM-målet

**Dato:** 15. oktober 2026  
**Projekt:** `rc700-gensmedet` / `autoload-in-c`  
**Branch:** `work/zsdcc-sccz80-builds-20261012`  
**Relateret compiler-branch:** `llvm-z80` (`work/push-pop-call-spills`)  

---

## 1. Målsætning & Udgangspunkt

Det fysiske RC702-bundkort (MIC702) er fra fabrikken udstyret med 2716 EPROM-sokler uden loddebro for A11. Det giver et **ubøjeligt fysisk loft på 2048 bytes (2 KB)** for PROM0-chippen.

Ved cyklens start var PROM-størrelsen over budgettet:
- Standalone Clang (`clang/prom.clang.bin`): **2133 bytes** (+85 B over 2048 B loftet).
- zcc + LLVM-Z80 (`llvmz80/prom.bin`): **2661 bytes** (+613 B over budget).

Målet for denne session var:
1. Identificere og udbedre compiler-ineffektiviteter og regressioner i LLVM-Z80 backend.
2. Forbedre og rydde op i listing-filen (`clang/prom.clang.lis`), specielt omkring interrupt-vektortabellen ved `0x6000`.
3. Optimere firmwaren, så den komplette produktions-PROM med både fuld skrifttype (`_sem702_font`), QR-fejlkode og periferi-initialisering kan brændes i en 2 KB 2716 EPROM.

---

## 2. Arbejde udført i LLVM-Z80 Compileren

I backend-repositoryet `llvm-z80` blev to konkrete optimeringsmønstre implementeret og testet:

### 2.1. Foldning af `dec (hl); jr z` i `Z80InstructionSelector.cpp`
- **Problem:** Tæller-mønstre som `retry_count--; if (retry_count == 0)` (bl.a. i `_check_fdc_result`) blev tidligere sænket til separate indlæsninger, subtraktioner og sammenligninger med unødvendige registerflytninger.
- **Løsning:** Mønsteret foldes nu direkte til `dec (hl)` og et betinget spring `jr z, ...`.
- **Gevinst:** `_check_fdc_result` faldt fra 41 B til 38 B (−3 B).
- **Test:** Ny lit-testsuite tilføjet i `llvm/test/CodeGen/Z80/incdec-hl-indirect.ll` (PASS).

### 2.2. 8-bit Spill/Reload via `push`/`pop` i `Z80PreEmitPeephole.cpp`
- **Problem:** I funktioner som `_fdc_read_result` genererede compileren ved funktionskald en 8-bytes spill/reload-sekvens til en statisk ramme i BSS:
  ```z80
  ld   a, d
  ld   (slot), a
  call ...
  ld   hl, slot
  ld   d, (hl)
  ```
- **Løsning:** `foldSpillReloadToPushPop` blev udvidet til at håndtere 8-bit registre (`B, C, D, E, H, L`), når tvillingeregistret (f.eks. `E` for `D`) er dødt ved reload-tidspunktet. Dette erstatter den 8-bytes sekvens med 2 bytes:
  ```z80
  push de
  call ...
  pop  de
  ```
- **Gevinst:** `_fdc_read_result` faldt fra 45 B til 39 B (−6 B), og dens frame i BSS blev fuldstændig elimineret (3 B -> 0 B).
- **Test:** Ny lit-testsuite i `llvm/test/CodeGen/Z80/static-frame-push-pop-spill.ll` (PASS).
- **Kvalitetssikring:** Fuld LLVM Z80-testsuite (`ninja check-llvm-codegen-z80`) består 100 % (157/157 tests). Samlet delta over alle matchende funktioner mod baseline `c863c55` er nu **−75 B**.

---

## 3. Rengøring af Disassembly & Symbolprioritet (`_intvec`)

I listing-filen `clang/prom.clang.lis` blev de 32 bytes interrupt-vektorer ved `0x6000` tidligere skæmmet af at blive vist som falske instruktioner:
```z80
00006000 <__code_start>:
    6000: d5           push de
    6001: 60           ld   h,b
    ...
```

### Årsagsanalyse:
I `rc700_prom.ld` var `__code_start = .;` defineret før `intvec.o`. I ELF har linker-script-symboler typen `STT_NOTYPE`. Når `llvm-objdump` ser både et NOTYPE-symbol (`__code_start`) og et OBJECT-symbol (`_intvec`) på samme adresse i en eksekverbar sektion, prioriterer den altid kodesymbolet og disassembler bytes'ene.

### Løsning:
1. `__code_start` blev fjernet fra linker-scriptet, og dekomprimeringsmålet i `clang/dzx0_standard.s` blev ændret til at referere direkte til `_intvec` (`ld de, _intvec`).
2. `llvm-objdump` ser nu udelukkende `_intvec` (`STT_OBJECT`, 32 bytes) på `0x6000`.
3. Resultatet er en ren og korrekt listing:
```text
Disassembly of section .text:

00006000 <_intvec>:
    6000: d5 60 d5 60 d5 60 d5 60         .`.`.`.`
    6008: d5 60 d5 60 d8 60 01 61         .`.`.`.a
    6010: d5 60 d5 60 d5 60 d5 60         .`.`.`.`
    6018: d5 60 d5 60 d5 60 d5 60         .`.`.`.`

00006020 <_banner_string>:
    6020: 20 52 43 37 30 30 20 52          RC700 R
...
0000604f <_fdc_sense_interrupt>:
;     fdc_write_when_ready(FDC_SENSE_INT);
    604f: 3e 08        	ld	a,$8
    6051: cd 67 60     	call	$6067
```

---

## 4. Analyse og Optimering af `display_sw1_status()`

### 4.1. Hvorfor C-udgaven fyldte 110 bytes
`display_sw1_status()` læser DIP-switchen på port `0x14` og skriver `"SW1 12345678: xxxxxxxx"` på række 0, kolonne 58.

I C-udgaven gav dette anledning til voldsom memory-churn:
- Fordi funktionen var inlinet i `_main_relocated`, var registrene hårdt pressede.
- LLVM's registerallokator allokerede **alle loop-variabler i BSS** (`+static-frame`).
- Hver bit-iteration udførte 3- og 4-bytes `ld (slot), a` / `ld a, (slot)` instruktioner for at opdatere tæller, switch-værdi og skærm-pointer.
- Samlet fodaftryk: 95 B kode + 14 B tekststreng + 7 B frame-slots = **110 B rå / 91 B ZX0-komprimeret**.

### 4.2. Håndskrevet Assembler-udgave (`clang/sw1_display.s`)
Funktionen blev omskrevet til en selvstændig, ren Z80-assemblerfunktion:
```z80
_display_sw1_status:
	ld	hl, .Lsw1_prefix
	ld	de, 0x786a		; row 0, col 58 (0x7830 + 58)
	ld	bc, 14			; sizeof("SW1 12345678: ") - 1
	ldir
	in	a, (0x14)		; læs port 0x14
	ld	b, 8
.Lsw1_loop:
	rrca
	ld	c, a
	ld	a, 0x30			; '0'
	adc	a, 0			; '0' + carry -> '0' eller '1'
	ld	(de), a
	inc	de
	ld	a, c
	djnz	.Lsw1_loop
	ret
```
- **Koderest:** Fylder kun **27 bytes kode + 14 bytes tekst = 41 bytes rå**.
- **Kompressionseffekt:** Reducerede den komprimerede PROM fra **2112 B til 2067 B** (−45 B).

### 4.3. Feature-Gate: Slået fra som standard
Da DIP-switch-visningen er en rent kosmetisk/diagnostisk udskrift (og ikke fandtes i den originale ROA375 PROM), blev den gjort konfigurerbar via flaget **`DISPLAY_SW1_STATUS`**:
- **Default:** `DISPLAY_SW1_STATUS ?= 0` i [Makefile](file:///Users/ravn/z80/rc700-gensmedet/autoload-in-c/Makefile#L357) og beskyttet med `#if` i [rom.c](file:///Users/ravn/z80/rc700-gensmedet/autoload-in-c/rom.c#L241).
- **Opt-in:** Kan tilvælges med `make prom DISPLAY_SW1_STATUS=1`.
- **Automatisk Make-afhængighed:** `clang/rom.o` afhænger af en stamp-fil `clang/.display_sw1_status`, så ændringer i flaget altid tvinger en genkompilering igennem uden manuelle `make clean`-trin.
- **Test-suite:** `make sw1-test` kalder eksplicit `$(MAKE) prom DISPLAY_SW1_STATUS=1` og verificerer, at linjen vises korrekt i MAME.

---

## 5. Resultater og Målinger

| Konfiguration | Rå `.text` | ZX0 Payload | Samlet PROM | Status mod 2048 B EPROM |
|---|---|---|---|---|
| **Oprindelig C-udgave** | 3466 B | 1993 B | 2112 B | +64 B (for stor) |
| **Med Asm-display (`DISPLAY_SW1_STATUS=1`)** | 3400 B | 1948 B | 2067 B | +19 B |
| **Produktion Default (`DISPLAY_SW1_STATUS=0`)** | **3356 B** | **1902 B** | **2021 B** | **27 B fri plads (PASS)** |

### Verifikation med Oracles
Alle ændringer er verificeret mod automatiserede tests og MAME-oracles:
1. **`make mame`:** Booter fuldt ud til CP/M `A>` prompten på 3.5 sekunder emuleret tid (**PASS**).
2. **`make qr-test`:** Renderskærm og 117-cellers QR-fejlkode matcher reference (**PASS**).
3. **`make sw1-test`:** DIP-switch status udlæses og vises korrekt på række 0 (**PASS**).
4. **`ninja check-llvm-codegen-z80`:** 157/157 lit-tests i compileren består (**PASS**).

---

## 6. Konklusion

Med disse ændringer er `autoload-in-c` nu bragt i mål:
- Firmwaren overholder det fysiske 2 KB hardware-krav med **27 bytes fri** på en standard 2716 EPROM.
- Både den komplette 1407 B SEM702-skrifttype og QR-kodediagnostikken er bibeholdt i PROM0.
- Listing-filerne er renset for falske instruktionsfortolkninger af datatabeller.
- Compiler-backend'en har fået to generelle optimeringer, som kommer hele Z80-kodebasen til gode.
