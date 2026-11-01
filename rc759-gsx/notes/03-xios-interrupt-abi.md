# RC759 XIOS Int-28h ABI — reference for driver RE (session 3, 2026-10-31)

Kilde: `rc700-gensmedet/docs/PICCOLINE_Programmers_Guide_v2.pdf`, Appendix A
(side 193+ i dokumentet, linje 6455+ i den ekstraherede `.txt`).

## Kaldskonventioner

- **Int 28h** = XIOS-funktioner. AL = funktionsnummer. Vector @ `0000:00A0h`.
- **Int E0h** (= 224) = CP/M-86 BDOS / CCP/M-86 systemkald. CL = funktion.
- **Int 29h** = Net driver.
- **Int 30h** = IMC.

Al kommunikation med RC759-hardware (CRT, palette, pixel-memory, mouse, FDC,
sound, cassette, iSBX351) går gennem Int 28h — driveren rammer **aldrig** HW
direkte via `IN/OUT`.

## Komplet Int 28h-funktionstabel

| AL | Funktion | Registre ind | Registre ud | Afsnit |
|---:|----------|--------------|-------------|--------|
| 0  | **Init Graphics** | AH=1 høj-/2 medium-opløsning, DX:CX→gcb | — | 4.5.1 |
| 1  | **Exit Graphics** | — | — | 4.5.2 |
| 2  | Reserved | | | |
| 3  | Get NVM copy address | — | ES:SI → NVM-kopi | 3.2 |
| 4  | Get config description | — | ES:SI → config | 3.1 |
| 5  | Recalibrate floppy | stak: drive/head/cyl/… | AL = FDC status | |
| 6-7 | Reserved | | | |
| 8  | Step floppy head in | stak-param | AL = status | |
| 9  | Step floppy head out | stak-param | AL = status | |
| 10 | Write floppy track | stak-param | AL = status | |
| 11 | Read floppy track | stak-param | AL = status | |
| 12 | Write byte to sound gen | DL = byte | — | |
| 13 | Get disk-driver stats | — | ES:(stats-struct) | |
| 14-18 | Reserved | | | |
| 19 | Get 16ms counter | — | DX:AX sek-tæller, CX ticks | |
| 20 | **Define alternative char** | CL=char#(0-255), DS:DX→font | — | 4.3.2 |
| 21 | Get display-list pointer | — | ES:BX→list, DX=buf-seg, SI=82730 cmd | 4.2.3 |
| 22 | **Get cursor position** | — | BH=row, BL=col | 4.2.4 |
| 23 | iSBX351 status | — | AX = status | 10.3 |
| 24 | iSBX351 init | stak: param-blok | — | 10.3 |
| 25 | Reserved | | | |
| 26 | Read cassette file header | CX=max, DS:DX→buf | AL=result, CX=got | 7.2.5 |
| 27 | Write cassette file header | CX=count, DS:DX→buf | — | 7.2.2 |
| 28 | Read next cassette data record | CX=max, DS:DX→buf | AL=result | 7.2.6 |
| 29 | Write cassette data record | CX=count, DS:DX→buf | — | 7.2.3 |
| 30 | **Mouse** | CL=sub (1=init, 2=deinit, 3=status) | varierer | 4.7 |
| 31 | **Define palette** | DS:DX → palette-def | — | 4.1.3 |
| 32-34 | Reserved | | | |
| 35 | **Write string to console buf** | DL=col, DH=row, CX=count, DS:SI→str | — | 4.2.2 |
| 36 | Set cursor position | BH=row, BL=col | — | 4.2.4 |
| 37 | Get attributes | — | AH = current attr | 4.2.5 |
| 38 | Set attributes | AH = new attr | — | 4.2.5 |
| 39 | Update physical screen | — | — | 4.2.3 |
| 40 | Write EOF on cassette | — | AX=0 | |
| 41 | DPC parallel reserve (CL=1) / release (CL=2) | AH=sub | — | 9.3 |
| 42 | Shared disk reserve (CL=1) / release (CL=2) | AH=sub | — | 8.4 |
| 43-49 | Reserved | | | |
| 50 | Reset iSBX351 | — | — | 10.3 |
| 51 | **Get char from font** | CX=char#(0-1023), DS:DX→buf | — | 4.3.4 |
| 52 | **Define char in font** | CX=char#(0-1023), DS:DX→font-def | — | 4.3.3 |
| 53 | Get XIOS version | — | AH=yr, AL=ver, BH=mo, BL=day (BCD) | |

## Int E0h (= 224) funktioner anvendt af driveren

| CL | Funktion | Registre | Note |
|---:|----------|----------|------|
| 6  | **BDOS Direct Console I/O** | DL=char (output) el. DL=0xFF (input nonblocking) | Standard CP/M BDOS |
| 141 (0x8D) | **CCP/M-86 Delay** | DX = tick-count | Bruges til semafor-polling på `gcb_mx` |

Andre CCP/M-86-funktioner nævnt i manualen (ikke brugt af driveren):
- CL=153: Get console no.
- CL=156: Get process descriptor

## Pixel memory format (fra PICCOLINE § 4.5.4)

32 KB bitmap-segment, mappet i pixel-memory under grafik-mode.

```
word_address = (X div 16) * 256 + (255 - Y) ; H1 CS:046A
bit_mask     = 1 << (15 - (X mod 16))  ; MSB = leftmost pixel
```
- Origo: nederste venstre hjørne (Y=0 nederst).
- Y: 0..255.
- H1: 1 bit/pixel. 32 KB = 64 strips × 256 words = 1024 × 256 pixels
  adressekapacitet; capability-tabellen annoncerer 560 × 256.
- Andre variant-suffixer og farveformater er ikke verificeret her.

## Graphics Control Block (gcb)

```asm
gcb_mx  db 0        ; mutex-semafor (0=fri, 0xFF=optaget)
gcb_seg dw 0        ; segment af save-buffer (32 KB, el. 8 KB 1-console system)
```

Pointer til gcb gives som argument til Int 28h fn 0 (Init Graphics).
XIOS swapper pixel-memory ↔ gcb_seg-buffer når consol switchs i baggrund.

## Driver-mapning

Driverens brug af Int 28h / Int E0h-funktioner, krydstjekket med
`disasm/dd759h1.a86`:

| CS-offset | Instruktion | XIOS/BDOS fn | Betydning i GSX-sammenhæng |
|-----------|-------------|-------------:|---------------------------|
| 0x0227 | `INT 28h`, AL=16h | **22** Get cursor pos | ESCAPE 15 returnerer tekstcursorposition; kilde-labelens 16 er forkert |
| 0x0B6E | `INT 28h`, AL=1Fh | **31** Define palette | SET_COLOR_REP sender palette-def fra DS:DX på driverstakken; DATA:0233 er to pakkede palettebytes |
| 0x1004 | `MOV CL,0x8D; MOV DX,1; INT E0h` | **141** CCP/M Delay | mutex-polling på gcb_mx |
| 0x1022 | `AL=0, AH=1, CX=0x58c; INT 28h` | **0** Init Graphics | Enter graphics mode; DX=DATA, gcb @ DATA:058C |
| 0x102D | `AL=1; INT 28h` | **1** Exit Graphics | Returnér til alfanumerisk mode |
| 0x0FC1 | `MOV CL,6; DL=0xFF; INT E0h` | **BDOS 6** | Fælles non-blocking tastaturinput |
| 0x0FD6 | `MOV CL,6; DL=byte; INT E0h` | **BDOS 6** | Konsoloutput til ESCAPE og input-echo; ikke grafik-TEXT |
| 0x0D4A | `MOV CX,0x8D; INT E0h`, DX=0 | **141** CCP/M Delay | Yield i locatorens event-loop; ikke gcb-semaforpolling |

Dermed er alle 8 interrupt-call-sites i driveren forklaret ved dokumenterede
XIOS/BDOS-funktioner. Ingen ukendte eller udokumenterede entries.

## Konsekvens for optimering

For at "gøre driveren bedre" skal vi forstå:

1. **Pixel-memory-manipulation** sker DIREKTE med memory-writes efter at have
   fået `gcb_seg` ud af Init Graphics-kaldet — ikke via Int 28h. Så POLYLINE,
   FILLED_AREA osv. kører i hastighed af 8086 memory-adgang + semafor-sync.
   Optimerings-vinkler:
   - Bedre bit-sat-algoritmer (fx precomputed word-stripes i stedet for
     bit-ad-gangen).
   - Fjerne eller reducere mutex-låse hvor det er sikkert.
   - Måling af den eksisterende integer-error/Bresenham-lignende rasterizer.
2. **Palette-updates** er sjældne og rammer kun fn 31.
3. **Tekst** på en grafik-skærm skal driveren selv emulere (XIOS 35 virker
   kun i char-mode) — her kan vi vinde ved at precache glyphs i pixel-mem.
4. **Mode-skift** er en Init/Exit Graphics-cyklus — ret dyrt (fuld 32 KB swap).

For at måle: byg oracle fra Myresnak (GSX-APP) eller en lille egen GRAPHICS.CMD
testharness, kør under MAME-RC759 (vi har allerede en fungerende emulator).

Se [GSX 1.1-kildesammenligningen](04-gsx11-source-comparison.md) for
capability-tabeller, vektorfont, trigonometriske tabeller og pixel-writing modes.
Se [DRI-skeletguiden](05-dri-skeleton-guides.md) for den verificerede
ESCAPE-mapping: source-labels er forskudt i forhold til dispatch-tabellen.
