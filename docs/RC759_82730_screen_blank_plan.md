# RC759 82730 — "sære tegn ved skærmslukning efter 15 min": undersøgelse + plan

Status: **UNDERSØGELSE + PLAN. Rodårsag er en velunderbygget HYPOTESE, ikke
bekræftet. Intet fix skrevet endnu.** (2026-08-31)

## Symptom (rapporteret af bruger, tidligere observeret)
Når RC759 skal slukke skærmen efter ~15 min inaktivitet (timeout kan formentlig
sættes), sker der to fejl i MAME:
1. Der kommer **sære tegn** på skærmen, som **forsvinder igen ved tastetryk**.
2. **Skærmen slukker ikke** (bliver ved med at vise indhold).

Brugerens hypotese: samme klasse som 8275-problemet — **visse tegnkoder/attributter
har særlig (display-undertrykkende) betydning**, som MAME ikke honorerer.

### Ekstra observation (bruger, 2026-08-31)
Der er **også sære tegn i bunden af skærmen lige når CCP/M er færdigindlæst.**
Bunden af skærmen tegnes af 82730's **status-række**, som hentes separat: i
`row_update` indlæses status-row-strengen fra `cbp+36/34` ved `y == vfldstp-1`,
og tegnes på scanlinjerne `vfldstp+scroll_margin+1 .. +lpr+1` (uden cursor). At
der kommer artefakter dér er sandsynligvis **samme rodårsag** (uanvendte
felt-attributter / ufortolkede tegnkoder), blot på status-række-stien frem for
selve tegnfeltet — et nyttigt, kortere-at-reproducere spor (kræver ikke 15 min
idle, ses straks efter CCP/M-load).

## Hvad er verificeret i koden (2026-08-31)

Kilder: `mame/src/devices/video/i82730.cpp`, `mame/src/mame/regnecentralen/rc75x.cpp`,
`mame/src/devices/video/i8275.cpp`.

1. **Felt-attributter parses men anvendes ALDRIG i rendering.**
   `rvv_row` (revers hele rækken, bit 11), `blk_row` (blank hele rækken, bit 10),
   `dbl_hgt` (bit 9), `field_attribute_mask` (SET FIELD ATTRIB, 15 bit),
   `char_blink`, `blinking_char` — alle læses i `mode_set()` /
   `dscmd_fulrowdescrpt()` / `dscmd_set_field_attrib()` og gemmes i `m_mb.*`, men
   **ingen** af dem konsulteres når en række tegnes. RC759-driverens
   `txt_update_row`/`gfx_update_row` (`rc75x.cpp`) bruger kun `m_vram` + cursor og
   ser hverken revers, blank eller blink. → Felt-attributter er reelt no-ops.

2. **STOP DISPLAY (0x03) ER implementeret og ville slukke korrekt** (rydder DIP,
   stopper row-timeren, `i82730.cpp:349`). At skærmen i praksis IKKE slukker
   beviser, at firmwaren **ikke** blanker via STOP DISPLAY — den bruger en
   in-band-metode i display-strengen.

3. **Flere datastream-koder er stubs** (logges, gør intet): EOF (`0x81`),
   SL SCROLL (`0x84/0x85`), TAB TO (`0x86`), SKIP (`0x89`), SUB/SUP (`0x8b/0x8c`),
   SET GEN PUR ATTRIB (`0x8d`), INIT NEXT PROCESS (`0x8f`).

4. **8275-analogien holder.** `i8275.cpp` implementerer Field Attribute Codes og
   Special Control Codes: en FAC/SCC i tegnstrømmen renderes ikke som glyf, men
   **blanker** cellen (`attr = FAC_B`) og propagerer attributten (blink/blank/
   highlight) til efterfølgende celler indtil reset (`i8275.cpp:415-445`,
   `SCC_END_OF_SCREEN` → blank resten). Det er præcis den mekanisme 82730 mangler.

5. **Logning** slås til ved at afkommentere `i82730.cpp:18`
   (`#define VERBOSE (LOG_GENERAL | LOG_COMMANDS | LOG_DATASTREAM)`) og genbygge.

## Hypotese (IKKE bekræftet)

RC759's ~15-min pauseskærm blanker via en **in-band 82730-mekanisme** — sandsynligvis
én af:
- **BLK_ROW** (blank hele rækken) sat via FULROWDESCRPT for alle rækker, eller
- en **BLANK-felt-attribut** (bit i `field_attribute_mask` via SET FIELD ATTRIB), eller
- **char-blink** (blinkende tegn via `char_blink`/`blinking_char`).

Fordi MAME ikke anvender nogen af disse, sker der følgende: de underliggende
tegnkoder (attribut-celler / blank-markerede celler) **renderes som glyfer** →
"sære tegn"; skærmen **blanker aldrig**; et **tastetryk** får firmwaren til at
gentegne det normale skærmbillede → artefakterne forsvinder. Dette matcher begge
observerede symptomer.

Alternativ (mindre sandsynlig) forklaring der skal udelukkes: firmwaren skriver
en bestemt "blank-glyf"-kode, og `txt_update_row`'s grove "spring tomme celler
over"-heuristik (`(gfx & 0xff) == 0`) rammer forkert.

## Åbne spørgsmål (skal afklares i fase 0)
- Præcis hvilken mekanisme firmwaren bruger (BLK_ROW vs felt-attribut vs blink).
- Er timeouten konfigurerbar, og kan den sættes kort til test (RC759 setup/CONFI)?
- Hvilke bit i `field_attribute_mask` betyder blank/revers/blink (82730-datablad).

---

## Plan

### Fase 0 — Bekræft mekanismen FØR noget fix (jf. repo-regel "verify before fix")
1. Afkommentér `i82730.cpp:18` (LOG_COMMANDS|LOG_DATASTREAM), genbyg
   `regnecentralen` (Docker/native efter host).
2. Reproducér headless: boot `rc759`, **ingen** input, kør ~900 s emuleret (eller
   find kortere konfigurerbar timeout). Log datastream + tag periodiske snapshots.
   - **Orakel:** loggen viser hvilken kommando/attribut firmwaren udsteder ved
     blank-tidspunktet, og bekræfter at STOP DISPLAY **ikke** bruges.
3. Snapshot "de sære tegn" (jf. `feedback_screenshot_to_verify`) for at bekræfte,
   at de er renderede attribut-/blank-celler.
   - **Exit-kriterium:** mekanismen er entydigt identificeret (BLK_ROW / felt-attribut
     / blink), ellers stopper vi og graver videre — intet fix på gæt.

### Fase 1 — Fix (kun efter fase 0 har fastlagt mekanismen)
Afhængig af hvad fase 0 viser:
- **BLK_ROW / RVV_ROW:** anvend i device eller driver — blank (eller revers) hele
  rækken. Lille ændring: enten blank `m_row`-bufferen i `load_row`/`row_update` når
  `blk_row` er sat, eller giv driveren et række-flag.
- **Felt-attribut BLANK (midt i række):** implementér felt-attributter — større
  ændring. Sandsynligvis udvid `update_row_delegate`-signaturen (`i82730.h:28`) til
  at bære per-celle-attribut (blank/revers/blink), eller lad device'en forudberegne
  en blanket rækkebuffer. Spejl 8275-mønsteret (`FAC_B`: blank cellen, propagér
  attributten indtil reset).
- **Char-blink:** implementér blink-fase (blank hver anden frame) via
  `char_blink`/`blinking_char` + `frame_number`, analogt til `cursor_visible()`
  (`i82730.cpp:176`).
- **Guard:** må ikke regressere MYRESNAK-grafik (`gfx_update_row`), boot-konsollen
  eller menuen (auto_line_feed 0/1-layouts).

### Fase 2 — Verificér
- Kør fase 0-reproen igen: skærmen **slukker** faktisk ved timeout; **tastetryk**
  genopretter; **ingen** sære tegn.
- Visuel verifikation over flere frames (jf. `feedback_visual_capture_for_display`).
- Regression: MYRESNAK tegner (STRAALE/SOL), boot-konsol og menu renderer korrekt.

### Fase 3 — Pakketering
- Doc-opdatering + memory-note. Commit på branch `rc759-82730-graphics` (samme som
  CA/EONF-fixet). Evt. upstream til ravn/mame — **kun** efter eksplicit go-ahead
  (jf. `feedback_mame_upstream_routing`).

## Relateret
- `RC759_82730_channel_attention.md` — CA-mekanisme, kommandosæt, BB/HENT/HUSK-fix.
- `RC759_RC750_hardware_vs_mame.md` — bredere hardware-vs-MAME (video er kendt hul).
- `tasks/memory/reference_rc759_82730_graphics.md` — 82730 = char-gen framebuffer.
- 8275-reference: `mame/src/devices/video/i8275.cpp` (FAC/SCC-blanking, forbilledet).
