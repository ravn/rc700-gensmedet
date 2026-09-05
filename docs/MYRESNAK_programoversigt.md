# MYRESNAK — programoversigt

MYRESNAK er et dansk Logo/skildpadde-tegneprogram til PICCOLINE (RC759), der
kører oven på GSX-grafik (`GRAPHICS`/`DD75XH1.SYS`). Kilde: manualen
`PICCOLINE_Myresnak_mar1985.pdf` (dette bibliotek) samt de faktiske `.MYR`-filer
udtrukket fra distributionsdisketten (`scratch/rc759-cmd-toolchain/30004078.imd`).

## Turtle-ordforråd (myreordrer)

| Ordre | Betydning |
|---|---|
| `FREM(n)` | frem n |
| `BAK(n)` | tilbage n |
| `HDREJ(n)` | højredrej n grader |
| `VDREJ(n)` | venstredrej n grader |
| `GENTAG(n) … HERTIL` | gentag blokken n gange |
| `HVIS(cond) …` | betingelse |
| `FLYV` | pen op (flyt uden at tegne) |
| `RENS` | ryd skærmen |
| `SLUT` | afslut programdefinition |

## Systemordrer (uddrag)

| Ordre | Tast | Funktion |
|---|---|---|
| `BIBLIOTEK` / `BB` | F1 | oversigt over `.MYR`-programmer på disketten |
| `HENT` | F2 | indlæs ét navngivet program fra disk (navn uden `.MYR`) |
| `GEM` | F3 | gem et program til disk (navn ≤ 8 tegn, ikke Æ/Å) |
| `KATALOG` | F4 | programmer i arbejdshukommelsen (max 10) |
| `TEGNING` / `TG` | F5 | skift fra tekstside til tegneside |
| `LIST` | F6 | udskriv et program på skærmen |
| `RET` | F7 | ret et program |
| `HUSK` | F8 | forlad tegnesiden, gå til tekstside for at indskrive program |
| `GLEM` | F9 | slet program fra arbejdshukommelsen (ikke disk) |
| `SLET` | — | slet program på disketten |
| `FARVER` | — | aktiver farvevalg (se nedenfor) |
| `STOP` | — | afslut MYRESNAK, retur til CCP/M |

Et program indledes med sit navn (+ evt. parametre som enkeltbogstaver i
parentes) og afsluttes med `SLUT`; max 20 linier. Programmer kan kalde sig selv
(rekursion). Op til 10 programmer i hukommelsen samtidigt.

## Farver

MYRESNAK understøtter farver på farveskærm. `FARVER` aktiverer farvevalg;
tegnefarve vælges med myreordrerne `BLA`, `GRØN`, `HVID`, `RØD` (og `SORT` =
baggrund). `SORTHVID` skifter tilbage til monokrom. Forgrundsfarve konfigureres
via hjælpeprogrammet `GKONFIG` på CCP/M-disketten. (Se manualens kap. 6.)

## De 10 distributionsprogrammer

Faktisk kildetekst fra disketten:

**POLYGON(A,S)** — regulær mangekant med sidelængde S.
```
GENTAG(A) FREM(S) VDREJ(360/A) HERTIL
```
A=3 → trekant, A=4 → kvadrat, osv.

**SPIRAL(S,V)** — spiral udad (rekursiv, side +3 indtil S≥100).
```
FREM(S) HDREJ(V) HVIS(S<100)SPIRAL(S+3,V)
```

**HCIRKEL(R)** — 90°-cirkelbue der krummer til højre (byggeklods).
```
GENTAG(9) HDREJ(5) FREM(R*3.14159/18) HDREJ(5) HERTIL
```
`R*π/18` er buelængden for 10° af en cirkel med radius R; 9 × 10° = 90°.

**VCIRKEL(R)** — 90°-cirkelbue der krummer til venstre.
```
GENTAG(9) VDREJ(5) FREM(R*3.14159/18) VDREJ(5) HERTIL
```

**STRAALE(S)** — bølget kronblad af 4 buer.
```
HCIRKEL(S) VCIRKEL(S) HCIRKEL(S) VCIRKEL(S)
```

**SOL(S)** — sol/blomst: 9 stråler roteret rundt.
```
GENTAG(9) STRAALE(S) HDREJ(160) HERTIL
```

**HJUL(R)** — hjul: hel cirkel (36 × 10° = 360°) plus en eger.
```
FLYV HDREJ(90) FREM(R) BAK(R) VDREJ(90) …
GENTAG(36) HDREJ(5) FREM(R*3.14159/18) HDREJ(5) HERTIL
```

**POLY(S,V)** — stjerne/spirograf (uendelig rekursion).
```
FREM(S) HDREJ(V) POLY(S,V)
```
Med V der ikke går op i 360 (fx `POLY(100,156)`) tegnes en stjerne.

**POLYSTEP(S,V)** — ét frem+drej-skridt (byggeklods).
```
FREM(S) HDREJ(V)
```

**POLYTO(S,V,T,U)** — veksler rekursivt mellem to skridt-mønstre.
```
POLYSTEP(S,V) POLYSTEP(T,U) POLYTO(S,V,T,U)
```

### Opsummering

| Program | Tegner |
|---|---|
| POLYGON(A,S) | regulær A-kant |
| SPIRAL(S,V) | spiral udad |
| HCIRKEL(R) / VCIRKEL(R) | cirkelbue højre / venstre |
| STRAALE(S) | bølget kronblad af 4 buer |
| SOL(S) | 9 stråler i cirkel (sol/blomst) |
| HJUL(R) | cirkel + eger (hjul) |
| POLY(S,V) | stjerne/spirograf (uendelig) |
| POLYSTEP(S,V) | ét frem+drej-skridt |
| POLYTO(S,V,T,U) | to vekslende skridt-mønstre |

## Relateret

- MAME-fix for BB/HENT/HUSK-frys (82730 frame-interrupt tabt når felt højere end
  frame): `mame` branch `rc759-82730-graphics`, `i82730.cpp`; ravn/mame#31.
  Fuld analyse + channel-attention-kommandosæt: `RC759_82730_channel_attention.md`.
- MYRESNAKs farvestøtte er tiltænkt som **orakel** for RC759-farveskærm med mere
  end 2 farveværdier (senere arbejde).

## Kørsel og interaktiv indtastning i MAME (verificeret 2026-08-30)

- **Kommandosyntaks er `NAVN(arg,...)` + RETURN**, ikke `NAVN arg!`. De faktiske
  diskprogrammer bruger parenteser (`FREM(100)`, `HDREJ(90)`, `STRAALE(40)`).
  Manualens `FREM0!`/`VDREJ 90!` er ældre/OCR-notation; parentesformen er den der
  virker. Verificeret: `FREM(100)`/`VDREJ(90)` ×4 tegner et rektangel.
- **Tegneside vs tekstside:** myreordrer og programkald udføres på tegnesiden.
  `HENT`/`HUSK` skifter til tekstsiden; brug `TG` (TEGNING) for at komme tilbage
  til tegnesiden før man kalder et program.
- **Kald af hentet program:** `HENT` → svar programnavn (uden `.MYR`). STRAALE
  kalder HCIRKEL og VCIRKEL, så alle tre skal hentes før `STRAALE(40)` kan køre.
- **MAME natural-keyboard dropper mellemrum** på RC759 HLE-tastaturet
  (`rc759_kbd.cpp`): `natkeyboard:post("AB CD")` giver "ABCD". Parentessyntaksen
  kræver ikke mellemrum, så den er upåvirket. Har man brug for et rigtigt
  mellemrum (fx `FREM 100`), skal SPACE-tasten trykkes direkte via ioport-feltet
  (`row_3` maske `0x0200`) mens natkeyboard er idle.
- **GSX-tegning er langsom i emulering** (~10 s pr. 90°-bue), så et fuldt
  `STRAALE` (4 buer) tager ~40 s emuleret tid.

Eksempelbilleder: `myresnak-captures/` (rektangel via FREM/VDREJ; STRAALE bølge).
