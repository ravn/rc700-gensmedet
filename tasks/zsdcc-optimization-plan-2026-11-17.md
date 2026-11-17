# ZSDCC Optimeringsplan for `rc700-gensmedet` (SDCC 4.6.0 #16639 / z88dk v2.5)

**Dato:** 2026-11-17  
**Maal-toolchains:** ZSDCC (`Build: 4.6.0 #16639` i `z88dk/bin/z88dk-zsdcc`) og LLVM-Z80/Clang (dual-compiler paritet)  
**Scope:** `autoload-in-c` (primaert fokus: 2.048 B fysisk 2716 EPROM), `rcbios-in-c`, `cpnos-in-c` (`sdcc-prom1lineprog` mod 2.048 B PROM1)

---

## 1. Verificeret Baseline & Epistemisk Status

Tal maalt direkte i arbejdsomraadet d. 17. nov 2026 (alle estimater laengere nede er eksplicit maerket `[estimeret]`):

### 1.1 `autoload-in-c` (verificeret fra `zsdcc/prom0.map`, `clang/` og `ls -la`)

| Artefakt / Sektion | ZSDCC 4.6.0 (verificeret) | LLVM-Z80 Clang (verificeret) | Kommentar |
|---|---:|---:|---|
| **Fysisk PROM0 (`prom.bin`)** | **1.959 B** (`___BOOT_size = $07A7`) | **1.973 B** | Hard cap: **2.048 B** (89 B fri ZSDCC / 75 B fri Clang) |
| **ZX0-komprimeret (`text_compressed.zx0`)** | **1.855 B** | **1.869 B** | Ratio: 55,84 % (ZSDCC inkl. BSS) mod 56,91 % (Clang) |
| `_BOOT` overhead (`boot.asm`: `_start`, `dzx0`, BSS-LDIR, NMI `retn`) | **104 B** (`1959 - 1855`) | **104 B** (`1973 - 1869`) | Identisk overhead inkl. 0x0066 NMI-padding |
| **Raat dekomprimeret image** (`prom0_CODE.bin` / `text_raw.bin`) | **3.322 B** (`$6000..$6CFA`) | **3.284 B** | ZSDCC +38 B raa pga. 35 B `bss_compiler` + sentinel/l_jphl |
| -> `code_compiler` | **1.567 B** (`$6000..$661F`) | -- | Heraf 32 B `_intvec`, 14 B `_delay`, 3 B `_set_i_reg`, 1.518 B `rom.c` |
| -> `rodata_compiler` | **1.718 B** (`$661F..$6CD5`) | -- | `sem702_font` (1408 B), `qr_data` (117 B), `eot_gap3_table` (32 B), `banner_string` (47 B), strenge |
| -> `data_compiler` | **0 B** | -- | Alle muterbare globals nul-initialiseres implicit i BSS |
| -> `bss_compiler` | **35 B** (`$6CD5..$6CF8`) | **0 B** (separat `.bss`) | ZSDCC inkluderer 35 nul-bytes i `prom0_CODE.bin` |
| -> `code_sentinel` (`_code_end`) | **1 B** (`$6CF8`) | -- | Ubrugt af `zsdcc/boot.asm`; arvet fra `boot_rom.c` |
| -> `code_l_sccz80` (`_l_jphl` / `___sdcc_call_hl`) | **1 B** (`$6CF9`) | -- | Traekkes ind af `jump_to(*(word*)addr)` i `rom.c`; lander PT EFTER `code_sentinel` |

Funktionsstoerrelser i `zsdcc/prom0.map` viser at commit `f8c83968` allerede fjernede `_syscall` (-56 B), rettede 16-bit promotion i `boot_from_floppy_or_jump_prom1`, forenklede `lookup_sectors_and_gap3_for_current_track`, `calc_size_of_current_track`, `check_sysfile` og `draw_qr` (nu 33 B). Dog ligger `rom.c.lis` i repoet fra SDCC 4.5.0 (aeldre snapshot) -- en frisk ZSDCC 4.6.0 `.asm`/`.lis`-udtraek er derfor obligatorisk i Fase 0.

### 1.2 `rcbios-in-c` og `cpnos-in-c` (verificeret byggetilstand)
- **`cpnos-in-c` (`prom1-lineprog`)**:
  - `clang-prom1lineprog/prom1-lineprog.bin`: **2.048 B** (`init.zx0` 453 B, `payload.zx0` 1.454 B, header+bootstrap 141 B).
  - `sdcc-prom1lineprog/`: `init.zx0` = **579 B**, `payload.zx0` = **1.478 B** (samlet over 2.048 B; README dokumenterer ~2.246 B upadded og opfoelgningsmaal paa under 2.048 B; ingen lokal `.map`-fil til stede p.t.).
  - `cpnos-in-c/Makefile:213-243`: Koerer uden `--opt-code-size` og uden `-custom-copt-rules`, fordi 2 `IX`-rammer (`relocator.c::relocate`, `resident.c::delete_line`) traekker 11 B `___sdcc_enter_ix` ind og overhaler ~17 B gevinst fra `sdcc_peeph_cs.3` (+5 B netto i resident).
- **`rcbios-in-c`**:
  - Ingen lokal `sdcc/bios.cim` eller `sdcc/bios.map` i repoet p.t.; `bios.c.lis` (4.112 linjer) viser 0 `push ix`, 15 `iy` (kun ISR `push/pop iy`), 44 stack-spills og 81 `___sdcc_*` EXTERN-deklarationer (men har `check_no_helper_calls.py` port).
  - Baade `rcbios-in-c/sdcc/Makefile:23` og `cpnos-in-c/Makefile` leder efter `$(Z88DK_HOME)/libsrc/_DEVELOPMENT/lib/sdcc_iy/z80.lib` og falder derfor tilbage til Docker `z88dk:2.4` (SDCC 4.5.0), selvom `z88dk v2.5` har flyttet biblioteket til `lib/clibs/sdcc_ix/z80.lib` (verificeret i `z88dk/lib/config/z80.cfg:31`).

---

## 2. Fase 0: Baseline-sikring & Vaerktoejsinspektion (Obligatorisk foer aendringer)

Foer nogen kode aendres:
1. Koer og notér umodificeret baseline for alle tre porte paa baade `zsdcc` og `clang`:
   - `make -C rc700-gensmedet/autoload-in-c prom COMPILER=zsdcc`
   - `make -C rc700-gensmedet/autoload-in-c prom COMPILER=clang`
   - `make -C rc700-gensmedet/autoload-in-c qr-test COMPILER=zsdcc`
   - `make -C rc700-gensmedet/autoload-in-c floppy-boot-test COMPILER=zsdcc`
2. Bevar den faktiske ZSDCC 4.6.0-assembler (`rom.asm` fra `zcc -S` eller ved ikke at slette `/tmp/zsdcc_build` midlertidigt) som reference, da `autoload-in-c/rom.c.lis` i git afspejler en tidligere SDCC 4.5.0-bygning foer `init_fdc()`-loekken og `f8c83968`.
3. Bekraeft efter hver fase:
   - `zsdcc/prom.bin <= 2048 B`
   - `clang/prom.clang.bin <= 2048 B` (ingen Clang-regression)
   - `_intvec % 256 == 0` og ZX0-roundtrip eksakt (`Makefile:602-614`)

---

## 3. Fase 1: Frakobling af `bss_compiler` fra binary payload (`zsdcc/sections.asm`)

### Problem (verificeret i `zsdcc/prom0.map` og `zsdcc/sections.asm`)
I `autoload-in-c/zsdcc/sections.asm:15-21` staar `SECTION bss_compiler` inde i `SECTION CODE` (`ORG 0x6000`):
```asm
	SECTION	CODE
	ORG	0x6000
	SECTION	code_compiler
	SECTION	rodata_compiler
	SECTION	data_compiler
	SECTION	bss_compiler
	SECTION	code_sentinel
```
Det har to konkrete fejl/spild:
1. `prom0_CODE.bin` indeholder **35 nulbytes** (`__bss_compiler_head = $6CD5`, `__bss_compiler_size = $0023`), selvom `zsdcc/boot.asm:22-26` **allerede** nulstiller hele `bss_compiler` i RAM ved boot med `ldir`!
2. `code_l_sccz80` (`_l_jphl` = 1 B `jp (hl)`) mangler i `sections.asm`. Derfor auto-placerer `z80asm` sektionen bagerst i `CODE` paa `$6CF9` -- **efter** `bss_compiler` og `code_sentinel` (`$6CF8`). Hvis man blot klipper ved `__bss_compiler_head`, mister `jump_to()` sin `jp (hl)`-hjaelper og crasher!

### Kritisk `z80asm`-invariant (verificeret i `rcbios-in-c/sdcc/Makefile:83-86` + `z88dk_section_layout.asm:42-43`)
I `z80asm` udskilles en `SECTION BSS` **ikke** som separat `.bin`-fil uden sin egen `ORG` -- den fortsaetter med at blive skrevet ind i `prom0_CODE.bin`. En fast `ORG` for `BSS` er modsat skrøbelig over for kodeskrump/-vaekst. Den rene, dynamiske loesning (identisk med `rcbios-in-c/sdcc/Makefile:83-86`) er:

1. **Opdatér `autoload-in-c/zsdcc/sections.asm`**:
   Deklarér eventuelle z88dk runtime-sektioner **foer** `bss_compiler`, saaledes at ingen aktiv kode eller data nogensinde havner efter `bss_compiler`:
   ```asm
	SECTION	_BOOT
	ORG	0x0000

	SECTION	CODE
	ORG	0x6000
	SECTION	code_compiler
	SECTION	rodata_compiler
	SECTION	data_compiler
	SECTION	code_l_sccz80
	SECTION	code_l_sdcc
	SECTION	code_clib
	SECTION	code_string

	SECTION	BSS
	SECTION	bss_compiler
   ```
   Og i `rom.c:1089-1092`: ekskludér `code_end` for `zsdcc` (via `#if !defined(__SDCC) || defined(LEGACY_SDCC_BOOT)` el. `-DZSDCC_NO_SENTINEL` i `ZSDCC_FLAGS`), fordi `zsdcc/boot.asm` slet ikke refererer `_code_end` (`LEGACY` `sdcc/boot_rom.c` bruger det fortsat).
2. **Trunkér `prom0_CODE.bin` ved `__bss_compiler_head` foer ZX0 i `autoload-in-c/Makefile`** (pass 1):
   ```makefile
	BSS_HEAD=$$(awk '/^__bss_compiler_head / {gsub(/\$$/, "", $$3); print $$3; exit}' prom0.map); \
	CODESIZE=$$((0x$$BSS_HEAD - 0x6000)); \
	dd if=prom0_CODE.bin of=prom0_CODE_stripped.bin bs=1 count=$$CODESIZE 2>/dev/null && \
	$(Z88DK_ZX0) -f prom0_CODE_stripped.bin $(CURDIR)/zsdcc/text_compressed.zx0
   ```
   (Husk tilsvarende `cmp prom0_CODE_stripped.bin text_roundtrip.bin` i roundtrip-checken, plus et sikkerhedstjek paa at `__rodata_compiler_tail <= __bss_compiler_head` og `__code_l_sccz80_tail <= __bss_compiler_head` og `__bss_compiler_size >= 2`, da `boot.asm:24` koerer `ld bc, __bss_compiler_size - 1; ldir` -- `size < 2` ville underflowe `BC`!)
3. Ret den foraeldede kommentar i `autoload-in-c/zsdcc/boot.asm:18` (`0x7200` -> `0x6000`).

- **Gevinst `autoload-in-c`**: **36 B raa** (35 B BSS + 1 B `code_sentinel`), **~5-6 B ZX0** `[estimeret]`.
- **Dual-compiler paritet**: 100 % isoleret til `zsdcc/sections.asm` og `zsdcc/prom.bin`-reglen; 0 paavirkning paa Clang.

---

## 4. Fase 2: Manuel Dead Code Elimination & Kildekoderensning

`z80asm` har ingen `--gc-sections` for `.o`-filer (modsat `ld.lld` + LTO under Clang). Smaa ubrugte symboler, overflodige `static`-kopier og ikke-`NORETURN`-stier overlever derfor i ZSDCC.

### 4.1 `autoload-in-c` konkrete DCE-maal
1. **Fjern skrive-kun globale `fdc_isr_delay` og `fdc_result_delay`** (`rom.h:370-371`, `rom.c:589-590`, `rom.c:815-816`):
   - Verificeret ved grep paa hele `autoload-in-c/`: kun skrevet i `get_floppy_ready()` (`fdc_isr_delay = 3; fdc_result_delay = 4;`) og udkommenteret paa `rom.c:419`. Fordi de er non-`static` globals, kan hverken ZSDCC eller single-TU Clang bevise at de er ubrugte.
   - **Gevinst**: **~10 B raa kode** + **2 B BSS** `[estimeret]`. Hjaelper baade ZSDCC og Clang!
2. **Erstat standalone `_set_i_reg(byte page)` med inline `__asm__`-makro under `#ifdef __SDCC`** (`rom.h:280-289`):
   - Verificeret i `zsdcc/prom0.map`: `_set_i_reg` optager 3 B (`ld i, a; ret` paa `$602E`) + `call _set_i_reg` 3 B + `ld a, 0x60` 2 B = **8 B** i `prom0_CODE.bin`, og kraevede `__INTVEC_ONLY`-hacket i `intvec.c:9` og `boot_rom.c:15`.
   - Under `#ifdef __SDCC` (med `TOSTRING`-moenstret fra `tasks/lessons.md:473-475` saa `INTVEC_PAGE` makroudvider):
     ```c
     #define set_i_reg(page) __asm__("ld a, " TOSTRING(page) "\n\tld i, a\n")
     ```
     (eller `STR(page)` fra `rom.h:187` / `SET_SP`-stilen i `rom.h:306`: `"ld a, #" STR(page) "\n\tld i, a\n"` -- tjek at `ld a, #0x60` udvider korrekt med zsdcc/sdasz80!).
   - **Gevinst**: **4 B raa** (`8 B -> 4 B`, verificeret i `prom0.map`), plus fjernelse af `__INTVEC_ONLY`-specialiseringer.
3. **`NORETURN` paa `boot_from_floppy_or_jump_prom1` og `get_floppy_ready`** (`rom.c:448-449, 814-873, 1074-1077`):
   - Verificeret: alle udgange fra `boot_from_floppy_or_jump_prom1` kalder enten `prom1_if_present()` (allerede `NORETURN`) eller `boot_floppy_or_prom()` (allerede `NORETURN`). De to `return;` efter `prom1_if_present()` i `rom.c:845, 858` (og `rom.c:805` i `init_fdc`) er uopnaaelige, og `for (;;);` i `main_relocated` (`rom.c:1077`) samt evt. afsluttende `ret` i `boot_from_floppy_or_jump_prom1` (`rom.c.lis:3122`) kan elimineres.
   - Bemærk `rom.c:1049`: `main_relocated` selv maa **ikke** markeres `NORETURN` (for ikke at hindre tail-call fra `boot.asm`/`start()`), men `get_floppy_ready` er ikke `main_relocated`.
   - **Gevinst**: **~4-6 B raa** `[estimeret]` (oeger ogsaa Clang eller er neutral; tjekkes med `make prom COMPILER=clang`).
4. **Banner NUL-byte** (`zsdcc/banner.c:2`):
   - `display_clear_and_banner` kopierer via `LDIR` med fast `BUILD_BANNER_LENGTH` (`46` bytes) og laeser aldrig NUL-terminatoren. `const char banner_string[BUILD_BANNER_LENGTH] = BUILD_BANNER;` sparer **1 B raa** i `rodata_compiler` (hvis `-Werror`/C23 accepterer det uden advarsel; kræver tilpasning af `_Static_assert` i `boot_rom.c:51` eller kun i `zsdcc/banner.c`).

### 4.2 `cpnos-in-c` og `rcbios-in-c` konkrete DCE-maal
- **`cpnos-in-c`**:
  - Gør `DUAL_TRANSPORT ?= 0` standard (allerede analyseret i `tasks/plan-cpnos-in-c-2kb-prom.md:67-71`): fjerner `xport_jt.o` og `transport_sio.o` -> **~150-200 B raa / ~80-120 B ZX0** `[estimeret]`.
  - Beskyt test-only counters (`pio_rx_count`, `pio_test_done` i `src/transport_pio.c:242-243`) med `#ifdef PIO_SPEED_TEST`, saa produktion ikke betaler døde symboler/BSS. (Obs: `pio_par_byte` og `pio_par_count` i `resident.c:128-129` er bundet til `tests/cpnet_bridge/harness.py` og maa ikke fjernes uden at opdatere harness.)
  - `#ifndef __SDCC` omkring `void bios_stub_ret(void) {}` i `src/resident.c:55`, fordi `sdcc/bios_jt.asm:63` allerede definerer `_bios_stub_ret: ret` inde i `RESIDENT_CODE`.
- **`rcbios-in-c`**:
  - `bios.c:2056` (`void bios_hrdfmt(void) { }`) og tomme ISRs (`isr_dummy`): tjek at `sdcc_opt.2:2201-2208` aliaser dem til `l_ret` uden at placere `l_ret` i `code_l_sccz80` uden for `BIOS`-kopien (i `rcbios-in-c/sdcc/z88dk_section_layout.asm:31` er `code_l_sccz80` allerede pinnet inde i `BIOS` foer `SENTINEL`!).

---

## 5. Fase 3: `__preserves_regs(...)` paa Leaf- og ASM-hjaelpere

### Kritisk sikkerhedsregel (ZSDCC vs. Clang)
- **ZSDCC** (`sdccman.txt:3589-3597`): `__preserves_regs(...)` er et **tillidsloefte til caller**; ZSDCC genererer **ikke** `push`/`pop` i callee og kontrollerer ikke C-kroppen. En C-funktion med `__preserves_regs` kan derfor lydloest korrumpere callers efter en regallokator-aendring!
  -> **Regel:** Sæt KUN `__preserves_regs(...)` på funktioner skrevet i `.asm` eller `__naked` inline-asm, hvor hvert eneste modificeret register er bevist ved inspektion!
- **Clang** (`cpnos-in-c/compiler/compat.h:75-90`): `#define __preserves_regs(...)` (no-op), mens `PRESERVES_REGS_CLANG(...)` bruger `__attribute__((z80_preserves_regs(...)))`, hvor LLVM-Z80 aktivt gemmer modificerede registre i prologen.

### 5.1 `autoload-in-c` konkrete `__preserves_regs`-maal
1. **`_delay(byte outer, byte inner)`** (`zsdcc/delay.asm:8-21`, erklæret i `rom.c:84-88`):
   - Verificeret i `zsdcc/delay.asm`: bruger KUN `A, F, B, C` (`or a`, `ret z`, `ld b, l`, `ld c, 0`, `dec c`, `jr nz`, `djnz`, `dec a`, `jr nz`). Bevarer `D, E, H, L, IX, IY`.
   - Erklaering i `rom.c:84-88`:
     ```c
     #ifdef __clang__
     void delay(byte outer, byte inner) __attribute__((leaf));
     #elif defined(__SDCC)
     void delay(byte outer, byte inner) __preserves_regs(d, e, h, l, iyl, iyh);
     #else
     void delay(byte outer, byte inner);
     #endif
     ```
   - Effekt: I `wait_fdc_ready` (`rom.c.lis:2479-2482`) spildes 2 B paa `push bc / pop bc` omkring `call _delay` fordi `timeout` laa i `C`. Med `__preserves_regs(d, e, h, l, iyl, iyh)` kan `timeout` ligge i `D`, `E` eller `H` (`L` bruges af 2. arg `inner`), og i `init_fdc` (`rom.c:795-800`) kan `retries` ligeledes blive i `D`/`E`/`H` hen over `delay_ms(391)` -> **~4 B raa** `[estimeret]`.
2. **`_fdc_write_when_ready` og `_fdc_read_when_ready`** (`rom.c:34-57`):
   - Verificeret største enkeltkilde til caller-pushes i `rom.c.lis`:
     - `fdc_seek`: 2 × `push hl / pop hl` (**4 B**)
     - `fdc_read_result`: `push hl / push bc / push de / ... / pop de / pop bc / pop hl` i løkke (**6 B**)
     - `fdc_write_full_cmd`: 3 × `push bc / pop bc` (**6 B**)
     - `boot_from_floppy_or_jump_prom1`: `push bc / pop bc` (**2 B**)
   - **Sikker implementering**: I stedet for at sætte `__preserves_regs` paa C-versionerne (usikkert!), flyttes de to smaafunktioner for `#ifdef __SDCC` til `zsdcc/fdc_wait.asm` (eller `__naked` inline-asm), hvor:
     - `_fdc_write_when_ready` (`A` = `val`): gem `val` i `C` (eller brug `B` til timeout-loekke / `DE` til 64K-counter `t`), bruger KUN `A, F, C, D, E` (og hopper via `jp _prom1_if_present` ved timeout, som er `NORETURN`) -> **bevarer garanteret `B, H, L, IY`** (`__preserves_regs(b, h, l, iyl, iyh)`).
     - `_fdc_read_when_ready` (`A` retur): bruger `DE` (eller `BC`) som 64K-counter, modtager ingen parametre -> **bevarer garanteret `B, C, H, L, IY`** (hvis counter i `DE`) eller **`D, E, H, L, IY`** (hvis counter i `BC`), saaledes at `fdc_read_result` kan holde baade bufferpointer og tæller uden `push/pop`!
   - **Gevinst**: **~12-18 B raa** i caller-funktionerne `[estimeret]` + udelukker `jr` til fælles `ret` i selve helperne (~2-4 B).

### 5.2 `cpnos-in-c` og `rcbios-in-c` konkrete `__preserves_regs`-maal
- **`cpnos-in-c/src/hal.h:60-61`** + `cpnos-in-c/sdcc/hal.asm:25-36`:
  - `__port_in` (`ld c, a; in a, (c); ret`) og `__port_out` (`ld c, a; ld a, l; out (c), a; ret`) rører KUN `A` og `C`.
  - Tilføj `__preserves_regs(b, d, e, h, l, iyl, iyh)` paa deklarationerne i `src/hal.h:60-61`.
  - Større gevinst (nævnt i `hal.h:56-59`): definér `#ifdef __SDCC` `IO_WRITE(p, v)` / `IO_READ(p)` via `__sfr __at`, saa konstante port-kald udsteder direkte 2-byte `out (n), a` / `in a, (n)` uden `call __port_*` (~3 B sparet pr. kald = **~50+ B raa** `[estimeret]`, med `hal.asm` kun tilbage for det ene dynamiske kald i `port_init`).
- **`cpnos-in-c/src/snios_c.c:67-95`**: `xport_send_byte` har allerede `__preserves_regs(d, e)`; auditér mod ZSDCC 4.6.0 `transport_pio.s` om `b, c` eller `h, l` også er bevarede i begge grene.
- **`rcbios-in-c/bios.c`**:
  - `_fdc_write` (`bios.c.lis:980-989`) bruger `A, F, C` og `_fdc_read` (`bios.c.lis:993-1000`) bruger `A, F` (ingen timeout-loop!). Som `#ifdef __SDCC __naked`-asm kan `_fdc_write` garantere `__preserves_regs(b, d, e, h, l, iyl, iyh)` og `_fdc_read` garantere `__preserves_regs(b, c, d, e, h, l, iyl, iyh)`, hvilket fjerner 4 × `push de / pop de` i `_fdc_general_cmd` (`bios.c.lis:1124-1154`) og `push bc; push de` i `_fdc_read_result` (`bios.c.lis:1042-1046`) -> **~10-12 B raa** `[estimeret]`.

---

## 6. Fase 4: Peephole-regler (`peephole.def`) & Redundante Codegen-mønstre

### Verifikation mod z88dk's indbyggede pass (`z88dk/lib/sdcc/` + `copt.c`)
- Rækkefølge i `zcc`: (1) SDCC intern `sdcc_peeph_cs.3` (kører per-funktion med fuld liveness som `notUsed('f')`), (2) `z88dk-copt` med `sdcc_opt.1`, `sdcc_opt.9`, `sdcc_opt.2` (på hele `.asm`-filen), (3) brugerens `-custom-copt-rules=...`.
- **VIGTIG FARE ved `copt`:** `copt` matcher rent syntaktisk og har **ingen** flag- eller register-liveness (`notUsed('f')`).

### 6.1 Bugfix og oprydning i eksisterende `peephole.def` (`autoload-in-c` + `rcbios-in-c`)
Begge projekter har en byte-identisk 170-linjers `sdcc/peephole.def` med **to konkrete problemer**:
1. **Skrivefejl paa linje 111** (i BÅDE `autoload-in-c/sdcc/peephole.def:111` og `rcbios-in-c/sdcc/peephole.def:111`):
   ```text
   s	jp	%1
   %1:
   =
   %1:
   ```
   Det foranstillede `s` forhindrer reglen i nogensinde at matche! Rettes til `\tjp\t%1`.
2. **Sikkerhedsadvarsel paa linje 1-3 (`ld a,0x00 -> xor a, a`)**:
   - `sdcc_peeph_cs.3` konverterer allerede `ld a,#0x00 -> xor a,a` alle steder hvor `notUsed('f')` holder (verificeret i `rcbios-in-c/bios.c.lis`: 0 forekomster af `ld a,0x00`). At beholde reglen i `copt` uden flag-check er en **latent miscompile-risiko** hvis SDCC udsender `ld a, 0x00` i en carry-afhængig sekvens (`sbc hl, de; ld a, 0x00; rla`). Fjern eller erstatt med specifik sikker mønster-matching!

### 6.2 Nye målrettede `copt`-regler (verificeret manglende i `sdcc_opt.{1,2,9}`)
Følgende mønstre optraeder direkte i `rom.c.lis` og `bios.c.lis` og dækkes IKKE af `sdcc_opt.2`:

1. **`jr %1` til en efterfølgende `ret` erstattes med `ret` (-1 B pr. hit, -10T)**:
   Verificeret i `rom.c.lis:526-533` (`fdc_write_when_ready`), `546-554` (`fdc_read_when_ready`), `2493-2503` (`wait_fdc_ready`), `2672-2681` (`fdc_get_result_bytes`) og `bios.c.lis:1611-1615` (`serial_const`):
   ```text
   	jr	%1
   %2:
   	ld	a,%3
   %1:
   	ret
   =
   	ret
   %2:
   	ld	a,%3
   %1:
   	ret
   ```
   (Samt tilsvarende regel hvor `%2:` har `xor	a, a` før `%1:\n\tret`!)
   *Sikkerhedsbevis:* Hvis `%1:` er umiddelbart `ret`, giver `ret` (1 B) identisk semantik som `jr %1` (2 B), og kræver ingen labelRefCount-ændring fordi `%1:` forbliver staaende til betingede grene.

2. **Død `push hl / pop hl` omkring `out (%1), a` (-2 B pr. hit)**:
   Verificeret direkte i `rom.c.lis:2649-2652` (`fdc_get_result_bytes` ved `dma_ch1_addr`):
   ```text
   	push	hl
   	ld	a, l
   	out	(%1), a
   	pop	hl
   =
   	ld	a, l
   	out	(%1), a
   ```
   *Sikkerhedsbevis:* Hverken `ld a, l` eller `out (n), a` ændrer `HL` eller flags, saa `push hl / pop hl` omkring disse to instruktioner er 100 % identitet. (Tilføj evt. også varianten for `ld a, h`.)

3. **Aktivér `-custom-copt-rules` + `--opt-code-size` i `cpnos-in-c`**:
   - Opret `cpnos-in-c/sdcc/peephole.def` og tilføj `-custom-copt-rules=$(CURDIR)/sdcc/peephole.def` i `cpnos-in-c/Makefile` (`ZFLAGS_BASE`).
   - Refaktorér de sidste 2 `IX`-funktioner (`relocator.c::relocate`, `resident.c::delete_line`), saa antal `IX`-prologues falder fra 2 til 0 (`___sdcc_enter_ix` paa 11 B droppes fra linket!). Derefter genaktiveres `--opt-code-size` (`sdcc_peeph_cs.3`, ~-17 B), hvilket vender +5 B tab til **~-28 B gevinst** `[estimeret]`.

---

## 7. Fase 5: Calling Conventions (`__z88dk_fastcall`, `__z88dk_callee`, `--sdcccall 1`)

### ABI-regler i ZSDCC `--sdcccall 1` (`sdccman.txt:5789-5806`)
- **Returvaerdier:** 8-bit i `A`, 16-bit i `DE` (**ikke** `HL`!), 32-bit i `HLDE`.
- **Parametre (ikke-variadisk):**
  - 1 arg: 8-bit i `A`, 16-bit i `HL`, 32-bit i `HLDE`.
  - 2 args: `(u8, u8)` -> `(A, L)`, `(u8, u16)` -> `(A, DE)`, `(u16, u16)` -> `(HL, DE)`.
  - **Faellen `(u16, u8)`:** 2. arg tvinges på **stakken**, fordi `A` kun bruges til 1. arg! Det giver stack-adgang og ofte `IX`-ramme.
  - **Callee stack-cleanup:** I `--sdcccall 1` rydder callee **allerede** stakken op for alle ikke-variadiske funktioner med returtype `void` eller `<= 16 bit`. `__z88dk_callee` giver derfor **0 B gevinst** på almindelige C-funktioner (kun nyttig for `sdcccall(0)` eller 3+-arg asm som `_mem_copy_backwards_callee` i `cpnos-in-c/sdcc/runtime.asm:24`).

### Hvornår `__z88dk_fastcall` hjælper vs. skader
- `__z88dk_fastcall` passer 1 arg i `L`/`HL`/`DEHL` og returnerer i `L`/`HL`/`DEHL`.
- **Brug IKKE `__z88dk_fastcall` på `u8`-funktioner** under `--sdcccall 1` (`wait_fdc_ready`, `fdc_write_when_ready`, `error_display_halt` osv.): `sdcccall(1)` bruger allerede `A` til både 8-bit arg og 8-bit retur, mens `__z88dk_fastcall` tvinger ind/ud via `L` (koster ekstra `ld a, l` / `ld l, a`).
- **Hvor `__z88dk_fastcall` faktisk hjælper**:
  - `rcbios-in-c`: C-funktioner kaldt af CP/M `__naked` shims der forventer 16-bit retur i **`HL`** fremfor `sdcccall(1)`'s `DE` (fx `bios_seldsk_c` eller 1-arg 16-bit `word -> word` helpers), hvor man sparer `ex de, hl` (1 B pr. kald/shim). (Indpakkes i `#define SDCC_FASTCALL __z88dk_fastcall` under `#ifdef __SDCC`, no-op under Clang!)
- **Audit af funktionssignaturer på tværs af alle 3 projekter**:
  - `autoload-in-c`: Verificeret -- ingen funktioner har `(u16, u8)` eller 3+ argumenter (`fdc_seek(byte, byte)` -> `A, L`; `fdc_get_result_bytes(byte, byte)` -> `A, L`; `compare_6bytes(ptr, ptr)` -> `HL, DE`; `check_sysfile(ptr, ptr)` -> `HL, DE`). Fokus er derfor Fase 1-4 fremfor ABI-attributter.
  - `rcbios-in-c`: Alle fundne multi-arg funktioner har kun 2 args i register-par (`fdc_general_cmd(byte, const byte*)` -> `A, DE`; `sec_rw(byte, byte)` -> `A, L`).
  - `cpnos-in-c`: `init.c::cpnet_xact(uint8_t, uint8_t)` er allerede `(A, L)`.

---

## 8. Fase 6: Dual-Compiler Paritet & Native ZSDCC 4.6.0-opgradering

1. **Kompiler-isolerede makromønstre** (kompilér rent på både `zsdcc` og `clang`):
   - Genbrug mønsteret fra `cpnos-in-c/compiler/compat.h:75-90`:
     - `__preserves_regs(...)`: kun defineret under `__SDCC` på verificerede `.asm`/`__naked`-symboler (no-op under Clang).
     - `SDCC_FASTCALL`: `#ifdef __SDCC` -> `__z88dk_fastcall`, ellers tom.
   - Delte C-rettelser (Fase 2) testes straks mod `make prom COMPILER=clang` for at garantere 0 Clang-regression (nuværende baseline: 1.973 B / 1.869 B ZX0).
2. **Native `z88dk v2.5` (ZSDCC 4.6.0 #16639) i `rcbios-in-c` og `cpnos-in-c`**:
   - Verificeret i `z88dk/lib/config/z80.cfg:31`: `-clib=sdcc_iy` linker `-LDESTDIR/lib/clibs/sdcc_ix` (`z80.lib` findes i `z88dk/lib/clibs/sdcc_ix/z80.lib`, ikke i `libsrc/_DEVELOPMENT/lib/sdcc_iy/z80.lib`).
   - Bemærk `cpnos-in-c/sdcc/runtime.asm:25` (`_mem_copy_backwards_callee` bruger `pop iy; ...; push iy`): behold `-clib=sdcc_iy` (`--reserve-regs-iy`) uændret -- skift IKKE til `-clib=sdcc_ix` uden omskrivning af `runtime.asm`!
   - Ved eventuel opdatering af detektionsstien i `rcbios-in-c/sdcc/Makefile:23` og `cpnos-in-c/Makefile` fra Docker `z88dk:2.4` (4.5.0) til native `z88dk v2.5` (4.6.0), skal `check_no_helper_calls.py` + `check_sdcc_stack_room.py` + fuld MAME-suite passere før skiftet committes.

---

## 9. Verifikationsporte i MAME & Byggekæde

Ingen fase betragtes som færdig uden grønne porte på **begge** compilere:

### `autoload-in-c` (obligatorisk efter hver eneste fase 1-5)
```sh
# 1. Byg + haard 2048 B gate + ZX0 roundtrip + IM2 page-align check
make -C rc700-gensmedet/autoload-in-c prom COMPILER=zsdcc
make -C rc700-gensmedet/autoload-in-c prom COMPILER=clang

# 2. CRT / Banner / 50Hz ISR / QR-kode / Fallback-gate (tester ogsaa BSS-nulstilling + rodata)
make -C rc700-gensmedet/autoload-in-c qr-test COMPILER=zsdcc
make -C rc700-gensmedet/autoload-in-c qr-test COMPILER=clang

# 3. Fuld FDC / DMA / delay / floppy boot til CP/M A> prompt
make -C rc700-gensmedet/autoload-in-c floppy-boot-test COMPILER=zsdcc
make -C rc700-gensmedet/autoload-in-c floppy-boot-test COMPILER=clang
```

### `rcbios-in-c` (ved ændring af `rcbios-in-c/sdcc/peephole.def` eller `bios.c`)
```sh
make -C rc700-gensmedet/rcbios-in-c bios COMPILER=sdcc
make -C rc700-gensmedet/rcbios-in-c bios COMPILER=clang
make -C rc700-gensmedet/rcbios-in-c mame-test COMPILER=sdcc
make -C rc700-gensmedet/rcbios-in-c polypascal-test COMPILER=sdcc
make -C rc700-gensmedet/rcbios-in-c mame-test COMPILER=clang
```

### `cpnos-in-c` (ved ændring af `cpnos-in-c`)
```sh
make -C rc700-gensmedet/cpnos-in-c prom1-lineprog COMPILER=sdcc
make -C rc700-gensmedet/cpnos-in-c prom1-lineprog COMPILER=clang
make -C rc700-gensmedet/cpnos-in-c cpnos-polypascal-test COMPILER=sdcc
make -C rc700-gensmedet/cpnos-in-c cpnos-polypascal-test COMPILER=clang
```

---

## 10. Samlet Estimat-Oversigt (`autoload-in-c` PROM0)

| Trin | Raa besparelse | PROM0 ZX0-besparelse | Forventet `zsdcc/prom.bin` | Ledig af 2.048 B |
|---|---:|---:|---:|---:|
| **Nuværende baseline** (verificeret) | -- (3.322 B) | -- (1.855 B + 104 B BOOT) | **1.959 B** | **89 B** |
| + Fase 1 (`bss_compiler` + `code_sentinel` fra payload) | -36 B | ~-5 a -6 B `[estimeret]` | ~1.953-1.954 B | ~94-95 B |
| + Fase 2 (DCE: `fdc_*_delay`, `set_i_reg`, `NORETURN`) | ~-18 a -21 B `[estimeret]` | ~-10 a -14 B `[estimeret]` | ~1.939-1.944 B | ~104-109 B |
| + Fase 3 (`__preserves_regs` paa `_delay` + asm `fdc_*_when_ready`) | ~-16 a -22 B `[estimeret]` | ~-9 a -14 B `[estimeret]` | ~1.925-1.935 B | ~113-123 B |
| + Fase 4 (`peephole.def` fix + `jr->ret` + død `push/pop hl`) | ~-5 a -12 B `[estimeret]` | ~-3 a -8 B `[estimeret]` | **~1.917-1.932 B** | **~116-131 B** |
| + Fase 5 (Calling-convention check i `autoload-in-c`) | ~0 a -2 B `[estimeret]` | ~0 a -1 B `[estimeret]` | ~1.916-1.932 B | ~116-132 B |

*(Clang forventes samtidig at gaa fra 1.973 B til ~1.963-1.968 B via Fase 2's fælles C-oprydning uden nogen backend-regression.)*
