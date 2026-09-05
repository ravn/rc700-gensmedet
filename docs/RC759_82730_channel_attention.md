# RC759/RC750 — Intel 82730 channel attention, kommandosæt og MYRESNAK-fixet

Dette dokument beskriver, hvordan **channel attention** (CA) fungerer i MAMEs
Intel 82730-emulering på RC759 (Piccoline) og RC750, hvilke kommandoer 82730
understøtter, samt rodårsag og rettelse af MYRESNAK-frysningen på `BB`/`HENT`/`HUSK`.

Kilder (verificeret denne session):
- `mame/src/devices/video/i82730.cpp` — selve enheden.
- `mame/src/mame/regnecentralen/rc75x.cpp`, `rc759.cpp`, `rc750.cpp` — driverne.
- Fix-commit `2a4b21cdbdb` på branch `rc759-82730-graphics` (`Fixes: ravn/mame#31`).

---

## 1. Hvad er channel attention?

Channel attention er værtens (80186's) måde at bede 82730 om at udføre en
**kommando**. Værten lægger en kommando-byte i kommandoblokken (CBP) i RAM og
pulser derefter 82730's CA-linje. På den faldende flanke henter 82730
kommando-byten og eksekverer den.

### Indgang (kun én på RC759/RC750)

Port `0x240` → `txt_ca_w` (`rc75x.cpp:110`), der laver en puls:

```cpp
void rc75x_state::txt_ca_w(uint16_t data)
{
    m_txt->ca_w(1);
    m_txt->ca_w(0);   // faldende flanke latcher CA
}
```

Samme kerne (`rc75x_state`) deles af `rc759` og `rc750`, så begge maskiner
bruger nøjagtig samme CA-vej. (På RC759 er porten mappet i `rc759.cpp:177`, på
RC750 i `rc750.cpp:120`.)

### To service-steder inde i 82730 (`i82730.cpp`)

Den faldende flanke sætter `m_ca_latch`. Hvornår latchen afvikles afhænger af,
om displayet er aktivt (`DIP`-bit i status):

1. **Straks — skærm inaktiv.** I `ca_w` (linje ~877/911): hvis
   `(m_status & DIP) == 0` da CA falder, kaldes `attention()` med det samme.
   (Første gang initialiseres enheden fra IBP/SCB.)
2. **Udskudt — skærm aktiv.** Hvis `DIP` er sat, forbliver `m_ca_latch` sat og
   afvikles først ved **billedslut** i `row_update` (linje ~846). Latchen
   re-tjekkes kun på en *ny* CA-flanke, så `row_update` er den **eneste**
   servicer for "latchet under aktiv skærm".

`attention()` (linje ~862) kalder `execute_command()` og rydder latchen.

---

## 2. Channel-attention-kommandosættet (CBP-kommandoer)

`execute_command()` (`i82730.cpp:326`) læser kommando-byten på `m_cbp+1` og
udfører den. Understøttede kommandoer i denne emulering:

| Kode | Kommando | Status | Effekt |
|------|----------|--------|--------|
| `0x00` | NOP | ✅ | Ingenting |
| `0x01` | START DISPLAY | ✅ | Sætter `DIP`, starter row-timeren (kræver at MODE SET er kørt) |
| `0x02` | START VIRTUAL DISPLAY | ❌ stub | Logges, ingen effekt |
| `0x03` | STOP DISPLAY | ✅ | Rydder `VDIP`/`DIP`, stopper row-timeren |
| `0x04` | MODE SET | ✅ | `mode_set()` — indlæser mode-blokken (geometri: `vfldstp`, `scroll_margin`, `lpr`, `frame_length` …) |
| `0x05` | LOAD CBP | ✅ | Henter ny CBP-peger og kalder `execute_command()` **rekursivt** (kommandokæder) |
| `0x06` | LOAD INTMASK | ✅ | Indlæser interrupt-maske fra `cbp+22` |
| `0x07` | LPEN ENABLE | ❌ stub | Lyspen — ingen effekt |
| `0x08` | READ STATUS | ✅ | Skriver status til `cbp+18`, rydder derefter status (undt. `VDIP`/`DIP`) |
| `0x09` | LD CUR POS | ✅ | Indlæser to cursor-positioner fra `cbp+26`/`cbp+28` |
| `0x0a` | SELF TEST | ❌ stub | Ingen effekt |
| `0x0b` | TEST ROW BUFFER | ❌ stub | Ingen effekt |
| andet | ukendt | — | Sætter `RCC` (reserved-command) i status + rejser interrupt |

**Ikke det samme:** *datastream*-kommandoerne `0x80`–`0x8f`
(ENDROW/EOL/FULROWDESCRPT/REPEAT/SET FIELD ATTRIB …) i
`execute_datastream_command()` eksekveres under selve rækketegningen, **ikke** via
channel attention. `0x90`–`0xbf` er reserverede; `0xc0`+ behandles særskilt.

---

## 3. MYRESNAK-frysningen på BB/HENT/HUSK

### Symptom (observeret)
I MYRESNAK hang programmet, når man skrev `BB` (programoversigt), `HENT`
(hent program) eller `HUSK` (start editor). Alle tre skifter tilbage til
**tekstsiden**.

### Rodårsag (fundet i koden)
Fejlen lå i 82730-emuleringen, ikke i MYRESNAK. Billedslut-oprydningen i
`row_update` (afvikling af udskudt CA + periodisk **EONF** frame-interrupt) var
bundet til scanlinjen:

```
vfldstp + scroll_margin + 1 + lpr + 1
```

Når MYRESNAK skifter til tekstsiden (via en MODE SET-kommando, `0x04`),
programmerer den et **felt højere end billedet**:

| Felt | Værdi (tekstside) |
|------|-------------------|
| `vfldstp` | 288 |
| `scroll_margin` | 31 |
| `lpr` | 15 |
| → trigger-scanline | **336** |
| `frame_length` | **312** |

`row_update` går kun `y = 0 .. frame_length-1` (0..311), så y når **aldrig** 336.
Dermed sættes EONF aldrig, ingen SINT rejses, og den udskudte `m_ca_latch`
afvikles aldrig.

MYRESNAKs handshake er:

```
sæt flag-byte
OUT channel-attention (port 0x240)
spin indtil 82730-ISR'en rydder flaget
```

Handshaket kører mens displayet er aktivt (`DIP` sat) → CA går ad den
**udskudte** vej → uden interrupt ryddes flaget aldrig → **evig spin →
programmet ser frosset ud.**

### Rettelse (`2a4b21cdbdb`)
1. **Clamp** trigger-scanlinjen til sidste fysiske linje
   (`screen().height() - 1`), så frame-interruptet fyrer præcis én gang pr.
   billede uanset feltgeometri. Fungerende tilstande (trigger allerede inde i
   billedet) er uændrede.
2. Flyttet oprydningen **ud af** `if/else`-kæden i `row_update` til et
   selvstændigt tjek, så branch-rækkefølge aldrig kan skygge for den, når den
   clampes ind i et tidligere interval.
3. Tilføjet **divide-by-zero-guard** på `frame_int_count`-moduloen.

```cpp
int eof_line = m_mb.vfldstp + m_mb.scroll_margin + 1 + m_mb.lpr + 1;
if (eof_line > screen().height() - 1)
    eof_line = screen().height() - 1;

if (y == eof_line)
{
    if (m_ca_latch)
        attention();
    if (m_mb.frame_int_count && (screen().frame_number() % m_mb.frame_int_count) == 0)
        m_status |= EONF;
    update_interrupts();
}
```

### Hvorfor rettelsen er fuldstændig
Fordi latchen kun re-tjekkes på en ny CA-flanke, er `row_update` det eneste
service-sted for "latchet under aktiv skærm". Den **straks**-vej (skærm inaktiv)
går ikke gennem den fejlbehæftede scanline og kan derfor ikke hænge på samme
måde. Clampen garanterer billedslut-servicering hver frame → der er ikke et
andet channel-attention-sted, der kræver samme fix.

Verificeret: `BB`, `HENT`, `HUSK` samt normal boot fungerer efter rettelsen.

### Status
Committet lokalt (`2a4b21cdbdb`, branch `rc759-82730-graphics`,
`Fixes: ravn/mame#31`). **Ikke pushet; issue ikke lukket** — kræver eksplicit
go-ahead før upstream-handling.

---

## Relateret
- `MYRESNAK_programoversigt.md` — MYRESNAK-kommandoer, de 10 programmer, kørsel i MAME.
- `RC759_RC750_hardware_vs_mame.md` — bredere hardware-vs-MAME-oversigt (82730 i kontekst).
- `tasks/memory/reference_rc759_82730_graphics.md` — 82730 = char-gen framebuffer, ikke bitmap.
- `tasks/memory/reference_myresnak_color_oracle.md` — MYRESNAK-farver som fremtidigt farveskærm-orakel.
