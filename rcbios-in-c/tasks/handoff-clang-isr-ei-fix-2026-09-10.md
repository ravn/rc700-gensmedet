# Handoff: clang BIOS sort skærm — ISR EI-før-RETI fix (2026-09-10)

## Symptom
clang-bygget rcbios BIOS booter til **sort skærm** (intet på skærmen).
Brugerhypotese: `__critical`-ændringen. Bekræftet — men det er én facet af en
bredere compiler-regression fra upstream-merget **PR #40** (`llvm-z80` 23.1.0-r1).

## Rodårsag (verificeret binært med build-macos llc/clang)
PR #40 (`llvm-z80` commit `1816b2d9e1b2`) + testopdatering `230964ceb53c` fjernede
fra backenden:
1. **`z80_critical`-attributten** (clang Attr.td/SemaDeclAttr/CGCall + Z80FrameLowering
   DI/EI) — helt væk. Nuværende clang: `warning: unknown attribute 'z80_critical' ignored`.
2. **Automatisk `ei` før `reti`** for `__attribute__((interrupt))`. Lå i samme
   FrameLowering-epilogblok som PR #40 slettede (return-lowering flyttede til
   `Z80CallLowering::lowerReturn`, der emitterer `RETI` men aldrig `EI`).

Konsekvens: på Z80 genaktiverer `RETI` **ikke** interrupts (IFF forbliver 0). Første
interrupt på en attribut-baseret ISR (bl.a. konsol-SIO) låser IFF → konsollen dør →
sort skærm. `critical-section.ll` blev samtidig udhulet (di/ei-CHECK fjernet), så
llvm-z80-CI ikke fangede det.

Forenkling: på Z80-ISR'er er `__critical`s DI en no-op (hardwaren clearer IFF ved
accept), og der er ingen stand-alone `__critical`-funktioner i rcbios. Hele
korrekthedsproblemet reducerer til **`ei` før `reti`** i interrupt-handlerne.

Scope: IVT'en pegede på **eksplicitte asm-wrappers** (`isr_*_wrapper` i `bios_shims.s`)
for de 4 stak-skiftende ISR'er (isr_crt/floppy/pio_kbd/sio_a_rx) — de laver korrekt
`ei; reti` og var **upåvirkede**. De øvrige **10 vektorer** pegede direkte på
`__interrupt`/`__critical __interrupt`-funktioner → alle `reti`-uden-`ei` → knækkede.

## Beslutning (bruger)
Reimplementér IKKE `__critical`. Placér EI/RETI **eksplicit i kilden** (som SDCC),
og gå væk fra compiler-magi. SDCC-stien virker (SDCC's `__interrupt` emitterer korrekt
EI+RETI) og røres ikke — kun clang-stien ændres.

## Implementeret fix (4 filer, DONE — men se BLOKKER nedenfor)
Renere end oprindelig plan: da `clang/intrinsic.h` allerede definerer keyword-makroerne,
gøres `__critical`/`__interrupt` **tomme på clang** → ISR-kroppe bliver normale
RET-funktioner; wrappers ejer al interrupt-framing.

1. `clang/intrinsic.h`: `#define __critical` / `#define __interrupt(n)` (tomme, med
   forklarende kommentar).
2. `clang/bios_shims.s`: 10 nye **non-switching** wrappers
   (`push af/bc/de/hl → call _isr_X → pop hl/de/bc/af → ei → reti`) for
   isr_dummy/hd/sio_b_tx/ext/rx/spec/sio_a_tx/ext/spec/pio_par. Kører på afbrudt
   programs stak (mirror af tidligere adfærd). Register-ansvar splittet: wrapper gemmer
   caller-saved (AF/BC/DE/HL); funktionen gemmer selv callee-saved (IX/IY via egen prolog).
3. `bios_hw_init.c`: IVT wired gennem `ISR_*`-makroer → wrappers på clang, bare
   funktioner på SDCC (`#else`-gren uændret adfærd).
4. `bios.c`: fjernet stray `x` i decl linje 49 (`isr_sio_b_tx`).

## BLOKKER — kan ikke build/boot-verificeres endnu
`build-macos` clang er opdateret med HEAD (`ninja: no work to do`), men mangler
**bredere PR #40-fallout** der forhindrer al clang-rcbios-bygning:

| Fejl | Betydning |
|---|---|
| `__builtin_z80_di` → *unknown builtin* | Z80-builtins (#42: di/ei/halt/nop/im2/set_i) ikke registreret i build. `BuiltinsZ80.td` findes stadig, men upstream-23.1.0 ændrede clangs builtin-TableGen-format → registreres ikke længere. |
| `+{de}` → *invalid output constraint* | Braced register-constraints (som `clang/string.h` bruger til LDIR-memcpy) afvises af `Z80TargetInfo::validateAsmConstraint`. |
| `+de` (ubracet) | Backend-crash (`unable to translate instruction: call`). |

Dette blokerer verifikation af ovenstående ISR-fix. Hele `#42/#4`-laget
(builtins + `z80_critical` + interrupt-EI + braced asm-constraints) er kollateral skade
fra PR #40 og ikke re-migreret endnu (matcher igangværende "fix PR #40 fallout"-commits
i llvm-z80).

## NÆSTE SKRIDT (for at fortsætte)
1. **Compiler-blokker (llvm-z80, PR #40-recovery):**
   - Re-migrér `__builtin_z80_*` til det nye clang builtin-TableGen-format (så
     `BuiltinsZ80.td` faktisk registrerer builtins igen).
   - Genindfør braced register-constraint-parsing (`{de}`/`{hl}`/`{bc}`) i
     `clang/lib/Basic/Targets/Z80.cpp` `validateAsmConstraint` (+ backend-lowering).
   - Genbyg `build-macos` (`ninja -C build-macos clang llc lld`).
2. **Verificér ISR-fixet:** `cd rcbios-in-c/clang && make clean && make` (0 warnings;
   inspicér `bios.clang.lis`: hver vektor/wrapper ender i `ei` lige før `reti`).
3. **MAME boot (HARD gate):** boot clang-BIOS, **screenshot** — signon + `A>` +
   konsol-input (bekræfter SIO-ISR'erne re-enabler interrupts). Sort skærm = fail.
4. **SDCC-build uændret:** bekræft SDCC-BIOS stadig booter (kun clang-stien blev rørt).
5. **Regressionsvagt (llvm-z80):** genindsæt `ei`-CHECK i `interrupt.ll` +
   di/ei-CHECK i `critical-section.ll` så en fremtidig backend-drift ikke igen taber
   EI ubemærket — det oracle-hul lod PR #40 slippe igennem.

## Bemærkninger
- Ingen `llvm-z80`-ændring i denne omgang; `z80_critical` forbliver bevidst droppet
  (matcher upstream-linjen "critical sections er library, ikke language").
- SDCC-stien er urørt og virker.
- Størrelse ikke kritisk (BIOS er ikke 2 KB-cappet).
