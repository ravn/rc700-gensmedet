# Tidsopslag via CP/NET — TOD (Time of Day)

## Baggrund: CP/M 2.2 og ure

CP/M 2.2 har ingen BDOS-funktion til at læse eller sætte systemtiden.
Urfunktioner kom med CP/M 3 (BDOS-104 Set Date & Time / BDOS-105 Get Date
& Time) og MP/M II (XDOS-155 Get/Set System Date & Time via SCB).

CP/NET 1.2 — den protokolversion vi bruger — er designet til CP/M 2.2-slaver
og **videresender ikke BDOS-105 til masteren**.  Det fremgår direkte af DRI's
NDOS-kildekode (`cpnet-z80/src/ndos3.asm`, linje 504):

```
db  0   ; 105 - GET DATE & TIME - can't support here, use SEND NW MESG
```

En `0`-entry i NDOS's funktionstabell betyder "håndteres ikke — returner fejl".
Kommentaren angiver løsningen: brug `SEND NW MESG`, dvs. BDOS-66/67.


## Løsning: vendor-extension via BDOS-66/67

CP/NET 1.2 definerer to netværksfunktioner til fri brug af applikationer:

| BDOS | Navn     | Beskrivelse                            |
|------|----------|----------------------------------------|
| 66   | NSEND    | Send en rå CP/NET-besked til masteren  |
| 67   | NRECV    | Modtag den næste besked fra masteren   |

NDOS ruter disse direkte til SNIOS (`fsdnw`/`frvnw` i `ndos3.asm`) uden at
tolke nyttelasten.  Det giver et åbent kanal til vendor-specifikke kommandoer.

Vi bruger FNC=105 som identifikator for vores TOD-forespørgsel.  Det er ikke
en CP/NET 1.2 standardfunktion — det er vores egen vendor-extension der tilfældigvis
bruger det samme funktionsnummer som CP/M 3's BDOS-105.


## Beskedformat

### Forespørgsel (slave → master)

```
Offset  Felt  Indhold
------  ----  -------
0       FMT   0x00   (request)
1       DID   0x00   (masteren, server NID)
2       SID   0x01   (slavens NID; udfyldes af SNIOS)
3       FNC   105    (0x69) — TOD vendor-extension
4       SIZ   0x00   (1 dummy-byte payload)
5       DAT   0x00   (dummy)
```

### Svar (master → slave)

```
Offset  Felt   Indhold
------  -----  -------
0       FMT    0x01   (response)
1       DID    0x01   (slavens NID)
2       SID    0x00   (masteren)
3       FNC    105    (echo af request-FNC)
4       SIZ    25     (26 bytes payload: SIZ = N-1)
5..9    DAT    5 bytes binær tid (se nedenfor)
10..30  DAT    21 bytes ASCII-dato inkl. CR/LF
```

#### Binær del (MSG[0..4], 5 bytes)

Følger det format MP/M II bruger i SCB'en og `SYSDATF` (XDOS-154):

```
MSG[0]  days_lo   Bit 7..0 af antal dage siden 1978-01-01 (little-endian)
MSG[1]  days_hi   Bit 15..8
MSG[2]  hr        BCD (00..23)
MSG[3]  min       BCD (00..59)
MSG[4]  sec       BCD (00..59)
```

#### ASCII del (MSG[5..25], 21 bytes)

```
"YYYY-MM-DD HH:MM:SS\r\n"
```

Gyldigt for år 2000..2059.  Kan udskrives direkte til konsollen uden
at tolke felterne.


## Implementering på mastersiden

Masteren kører under MP/M II + CP/NET på z80pack `cpmsim`.

### Host-RTC (z80pack)

z80pack eksponerer værtssystemets ur via to I/O-porte:

```
Port 25  CLKCMD   Skriv feltvalg (0..7) for at vælge sub-felt
Port 26  CLKDAT   Læs valgt felt tilbage
```

Sub-felter (standard BCD-mode):

| Felt | Indhold                                                        |
|------|----------------------------------------------------------------|
| 0    | Sekunder (BCD, 00..59)                                         |
| 1    | Minutter (BCD, 00..59)                                         |
| 2    | Timer (BCD, 00..23)                                            |
| 3    | Dage siden 1978-01-01, lav byte                                |
| 4    | Dage siden 1978-01-01, høj byte (16-bit, wraps ~2157)          |
| 5    | Dag i måned (BCD)                                              |
| 6    | Måned, 0-indekseret (BCD; Jan=0x00, Dec=0x0B)                  |
| 7    | År siden 1900, packed-decimal (høj nibble × 10 + lav nibble)   |

År-encoding: for 2000..2059 er høj nibble 10..15 (0xA..0xF), hvilket ikke
er strengt BCD men dekoderbart som `(high × 10 + low) + 1900`.  z80pack
kalder det selv en "Y2K bug" (rtc80.c) men det virker til 2059.

Måned er 0-indekseret fra C's `tm_mon`.  `gettod`-handleren lægger 1 til
med `DAA` for at konvertere til 1..12 i ASCII-feltet.

### SERVER.RSP (`cpnet/mpm-server/server.asm`)

SERVER.RSP er den standard DRI CP/NET server-RSP genskabt og udvidet med
en `gettod`-handler.  Dispatch-tabellen i `server.asm` kortlægger
funktionsnummer 17 (intern) til FNC=105:

```asm
db  17   ; 55 = 105 - Get Time/Date (gettod)
...
dw  gettod  ; 17 - Get Time/Date (FN 105, custom extension)
```

`gettod`-handleren (ca. linje 354 i `server.asm`):

1. Læser de 8 RTC-felter via `out CLKCMD` / `in CLKDAT`
2. Skriver binær del (days_lo, days_hi, hr, min, sec) til MSG[0..4]
3. Formaterer ASCII-streng til MSG[5..25]:
   - `yr2asc`: konverterer packed-decimal år til `"20XX"` (hardkodet `"20"` prefix)
   - `bcd2asc`: konverterer BCD-byte til 2 ASCII-cifre
   - Separatorer (`-`, `T`, `:`) og afsluttende `\r\n` indsættes direkte
4. Sætter `SIZ = 25` (dvs. 26 bytes payload)
5. Springer til `sndbak` (standard SERVER.RSP svar-rutine)

Hjælpefunktioner i `server.asm`:

| Label     | Funktion                                                    |
|-----------|-------------------------------------------------------------|
| `rdclk`   | `out CLKCMD, a` + `in CLKDAT` → `(HL)`, advance HL         |
| `bcd2asc` | BCD-byte → 2 ASCII-cifre til `(HL)`, advance HL × 2        |
| `yr2asc`  | packed-decimal år → 4 ASCII-cifre `"20XX"` til `(HL)` × 4  |


## Implementering på slavesiden

### NDOS-lag (CP/NET 1.2)

NDOS (`ndos3.asm`) sender BDOS-66/67 direkte videre til SNIOS uden at tolke
nyttelasten.  Fra `ndos3.asm`:

```asm
fsdnw equ $-FUNTB2
    db 0b8h         ; SDMSGU — send brugerdefineret besked

frvnw equ $-FUNTB2
    db 0bah         ; RVMSGU — modtag brugerdefineret besked
```

SNIOS udfylder SID-feltet med slavens NID inden afsendelse.

### TODGET (`cpnet/todget/todget.c`)

CP/M-program til manuel tidsforespørgsel fra slavens brugerniveau.  Kørende
efter boot på CP/NET-drevet E:

```c
msg[0] = 0x00;    // FMT request
msg[1] = 0x00;    // DID = master
msg[2] = 0x01;    // SID = slavens NID
msg[3] = 105;     // FNC = TOD vendor-extension
msg[4] = 0x00;    // SIZ = 0 (1 dummy byte)
msg[5] = 0x00;

bdos(NSEND, (int)msg);   // BDOS 66
bdos(NRECV, (int)msg);   // BDOS 67
// msg[5..9]  = binær tid
// msg[10..30] = ASCII "YYYY-MM-DD HH:MM:SS\r\n"
```

TODGET udskriver begge dele til konsollen og kan bruges til at verificere
at server-extensionen virker.

### RTCTOD (`cpnet/rtctod/rtctod.c`)

Hjælpeprogram der kører på masteren (ikke slaven) og læser RTC-portene
direkte.  Bruges til at verificere z80pack's ur uafhængigt af CP/NET.

### TODSRV (`cpnet/todsrv/todsrv.c`)

Alternativ master-side responder skrevet i C (køres som CP/M-program under
MP/M).  Bruger FMT=0x80/0x81 som vendor-format i stedet for standard
FMT=0x00/0x01.  Status: eksperimentel — den nuværende løsning er
`gettod`-handleren i SERVER.RSP.


## Sekvensdiagram

```
Slave (cpnos-in-c)           NDOS (ndos3.asm)     SNIOS        Master (server.asm)
        |                          |                  |                  |
        | BDOS(66, &msg)           |                  |                  |
        |------------------------->|                  |                  |
        |    fsdnw dispatch        |                  |                  |
        |                          |---SNDMSG-------->|                  |
        |                          |                  |--ENQ/SOH frame-->|
        |                          |                  |                  |
        | BDOS(67, &msg)           |                  |                  |
        |------------------------->|                  |                  |
        |    frvnw dispatch        |                  |                  |
        |                          |---RCVMSG-------->|                  |
        |                          |                  |<--SOH frame------|
        |                          |                  |  (gettod reply)  |
        |<-- msg[] udfyldt --------|                  |                  |
        |                          |                  |                  |
```

Beskederne transporteres over PIO-B (IRQ-drevet) eller SIO-A (pollet)
afhængig af SW1 S03.  Selve CP/NET-rammen (ENQ/SOH/STX/ETX/EOT/ACK) er
usynlig for NDOS og applikationslaget.


## Begrænsninger

- **Tidszoner**: z80pack eksponerer værtens lokaltid.  Der er ingen
  tidszoneinfo i protokollen.
- **CP/M 2.2 BDOS**: har ingen mekanisme til at gemme systemtiden for
  andre programmer.  TODGET viser tiden; den skrives ikke ind i et
  systemdelt felt (modsat CP/M 3's SCB).
- **Ingen automatisk synkronisering ved boot**: cpnos og rcbios sætter
  ikke uret automatisk ved opstart.  En ZSDOS-lignende integration
  (som kalder BDOS-66/67 fra BIOS `CLOCK`-vektoren på 0xDA56) er mulig
  men ikke implementeret.
- **Årstal**: ASCII-feltet er hardkodet med `"20"` prefix og er kun
  gyldigt for 2000..2059.  Det binære dagsfelt er korrekt til 2157.
