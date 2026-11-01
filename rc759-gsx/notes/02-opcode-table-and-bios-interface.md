# RC759 GSX-86 driver — session 2 findings (2026-10-31)

**Rettet efter byte-rekonstruktion og GSX 1.1-kildesammenligning.** Se
[den kildebaserede analyse](04-gsx11-source-comparison.md) for evidens.
De tidligere chargen-/glyph-upload- og graphics-on/off-hypoteser var forkerte.

## Store opdagelser

### 1. CP/M-86 CMD-format identificeret — jump-tabellen fundet
Driveren er en standard CP/M-86 `.CMD` fil med tre grupper:

| Group | Type  | File range          | Length  | Note |
|------:|-------|---------------------|---------|------|
| 0     | CODE  | 0x0080..0x10C0      | 0x1040  | 8086 kode, CS-relativ 0x0000..0x1040 |
| 1     | DATA  | 0x10C0..0x1D00      | 0x0C40  | Initialiseret data **+ GIOS jump-tabel ved DATA:0x100** |
| 2     | EXTRA | 0x1D00..0x20E0      | 0x03E0  | Nulinitialiseret image; segmentreference til grafik-savebuffer |
| —     | —     | 0x20E0..0x2180      | 0xA0    | Fem segmentfixups, terminator og padding; reproduceret byteidentisk |

**Jump-tabellen ligger ved DATA-group offset 0x100 (fil 0x11C0)**, ikke i CODE
som første gæt. Dispatcheren `CALL [BX+0x100]` læser med DS=DATA_SEG efter
CP/M-86-loader har relokeret `MOV AX, 0` ved CS:0x1F til `MOV AX, data_seg`.

### 2. Alle 35 tabelpladser findes — flere handlers er stubs
Dispatch-tabellen er komplet som tabel, ikke som funktionel GSX-dækning:

```
op  1 OPEN_WORKSTATION       -> CS:0x004e
op  2 CLOSE_WORKSTATION      -> CS:0x0153
op  3 CLEAR_WORKSTATION      -> CS:0x0159
op  4 UPDATE_WORKSTATION     -> CS:0x016d  (1 instr før ESCAPE — fælles stub)
op  5 ESCAPE                 -> CS:0x016e
op  6 POLYLINE               -> CS:0x02d7
op  7 POLYMARKER             -> CS:0x04bf
op  8 TEXT                   -> CS:0x050f
op  9 FILLED_AREA            -> CS:0x0706
op 10 CELL_ARRAY             -> CS:0x08be
op 11 GDP                    -> CS:0x0976
op 12..26 SET_* attributter  -> CS:0x0aa7 .. 0x0cda  (små handlers, ~30B hver)
op 27..34 input/writing-mode -> CS:0x0d27 .. 0x0faf
```

Opcode 0 peger på CS:0x0fdd, en `RET`-stub. Opcode 4, 27 og 34 samt
GDP 2..5 er også `RET`-stubs; capability-tabellen annoncerer kun GDP 1 (bar).

### 3. Ingen port-I/O; pixels skrives direkte i bitmap-segmentet
**0 `IN`/`OUT`-instruktioner i hele CODE-segmentet.**

Al I/O går via to interrupts:

- `INT 0xE0` (4 call-sites) = CP/M-86 BDOS / CCP/M-86
  - `CL=6, DL=char`  →  BDOS fn 6 "Direct Console I/O" (ascii text output)
  - `CL=0x8D` → CCP/M fn 141, delay/yield; ikke grafikmodeskift
- `INT 0x28` (4 call-sites) = RC759 XIOS
  - `AL=0x16` → læs tekstcursorposition
  - `AL=0x1F, DS:DX=buffer_ptr` → definér palette
  - `AL=0, AH=1, DX:CX=gcb` → start højopløsningsgrafik
  - `AL=1` → afslut grafik

Dette er konsistent med:
- Appendix C's eksplicitte formulering: *"Device driver I/O (that is,
  communication between the device driver and the device via the system
  hardware ports) is done through operating system calls."*
- PICCOLINE-guide §4.5: XIOS stiller et bitmap-segment og en semafor til
  rådighed. H1 tegner linjer og vektortekst med direkte memory-writes,
  ikke med upload af tegnmønstre.

## Konsekvenser for målet "gøre den bedre"

Vi behøver IKKE kortlægge rc759-portadresser — hardware-abstraktionen ligger
i rc759-BIOS. Forbedringsvinklerne er alle driver-interne:

Ingen optimering er udført eller målt her. Den nuværende POLYLINE er allerede
en integer-error/Bresenham-lignende rasterizer. Før ændringer bør en grafisk
oracle dække endepunkter i XOR-mode, polygonkanter, mønsterfase og vektortekst.
GSX 1.1-referencekilderne er sammenligningsmateriale, ikke en automatisk facitliste.

Hvad vi FØRST skal gøre for at kunne måle "bedre":
- Bruge PICCOLINE-guide §4.5 som XIOS-reference. MAME emulerer maskinens
  hardware; gæste-OS'et implementerer disse interrupts.
- Opsætte en test-rig: GSX-app under CP/M-86 i MAME, med nuværende
  driver som baseline.

## Næste konkrete skridt

1. **Spot-check vigtige handlers** i disassemblyen:
   - OPEN_WORKSTATION (`CS:0x004e`) — hvordan sætter den intout[] op?
   - POLYLINE (`CS:0x02d7`) — er det Bresenham eller noget værre?
   - TEXT (`CS:0x050f`) — bruger den chargen-upload eller BDOS fn 6?
2. **Diff mellem H1 og øvrige varianter** — suffixernes præcise betydning
   og de andre varianters adfærd er ikke fastslået i denne analyse.
3. **Krydstjek `INT 0x28`-funktionsnumre mod MAME rc759-driver**
   (`src/mame/drivers/rc759.cpp` el. hvor den nu bor).
4. Først derefter beslutte om vi vil annotere videre eller reimplementere.

## Værktøj

Disassembler: **Capstone v5.0.7** (Python) i `CS_MODE_16` (16-bit real-mode
8086), linear sweep med `skipdata=True`. CMD-aware wrapper i
`disasm/disasm.py` identificerer grupper, læser jump-tabellen fra
DATA-group, og labler handler-entries. Output: `disasm/dd759h1.a86`
(1883 linjer vs. 3666 før CMD-opdeling — fordi DATA/EXTRA nu dumpes som
hex ikke som "code").
