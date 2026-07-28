# CP/NET 1.2 udvidelsesmuligheder — oversigt

Undersøgt 2026-07-28.  Formålet er at kortlægge hvad CP/NET 1.2 tilbyder ud
over det vi allerede bruger (disk-I/O + TOD-opslag via FNC=105 over BDOS-66/67),
og hvilke spor der er interessante at forfølge på RC702.

## De otte standard CP/NET-netværksfunktioner

CP/NET 1.2 definerer BDOS-64..71 som "CP/NET-funktioner, ukendte for CP/M-BDOS".
De håndteres af NDOS (`cpnet-z80/src/ndos3.asm`):

| BDOS | Navn              | NDOS-label | Hvad det gør |
|------|-------------------|------------|--------------|
| 64   | LOGIN             | `flgin`    | Logger slaven ind — køres automatisk af CPNETLDR ved boot |
| 65   | LOGOFF            | `flgof`    | Logger ud — sender standard "logoff"-besked til server |
| 66   | SEND NW MESG      | `fsdnw`    | Sender rå CP/NET-ramme (vi bruger dette til TOD via FNC=105) |
| 67   | RECV NW MESG      | `frvnw`    | Modtager næste indkommende ramme |
| 68   | GET NW STATUS     | `fnwst`    | Returnerer statusbyte: bit0=TX-fejl, bit1=RX-fejl, bit4=logget ind |
| 69   | GET NW CFG        | `fnwcf`    | Returnerer adressen på konfigurationstabellen (hvilke drev er netværksdrev) |
| 70   | SET COMP ATTR     | `fstcp`    | Sætter "compatibility attributes" — styrer serverens fejlhåndteringsadfærd |
| 71   | GET SERVER CFG    | `fsvcf`    | Returnerer adressen på serverens konfigurationstabel (NID, antal slots, login-vektor) |

Fejlbits i BDOS-68-statusbyten nulstilles ved læsning, hvilket gør den ideel
til periodisk diagnostik.

## BDOS-funktioner videresendt til serveren

NDOS videresender en delmængde af CP/M 3 / MP/M II BDOS-kald til masteren.
Nyttige:

| BDOS | Navn                   | NDOS | Bemærkning |
|------|------------------------|------|------------|
| 38   | ACCESS DRIVE           | `frsvc` | MP/M II multi-bruger drive-adgang |
| 39   | FREE DRIVE             | `frsvc` | Frigiver drive-adgang |
| 42   | LOCK RECORD            | `flkrc` | Flyt record-lås (multi-bruger, se nedenfor) |
| 43   | UNLOCK RECORD          | `flkrc` | Frigiver record-lås |
| 101  | GET DIR LABEL BYTE     | `fgtdl` | Henter katalogetiket-byte fra server |
| 102  | READ FILE DATE-PWD MODE| `fopfi` | Læser XFCB (filstempel + adgangskode) |
| 103  | WRITE FILE XFCB        | **0**  | Ikke understøttet i NDOS 1.2 |
| 104  | SET DATE & TIME        | **0**  | Ikke understøttet — CP/M 3 kun |
| 105  | GET DATE & TIME        | **0**  | Ikke understøttet — vores vendor-extension via BDOS-66/67 |
| 106  | SET DEFAULT PASSWORD   | `fstpw` | Netværksadgangskode til serverbeskyttede filer |
| 112  | LIST BLOCK             | `flstbk`| Udskriver blok til serverstyret LST:-enhed |

## Orderly shutdown — NETEND

`server.asm` definerer `netend equ 76`.  FNC=0xFE i CP/NET-protokollen er
"network shutdown" — en besked der signalerer at slaven er ved at lukke ned.
Masteren frigiver slave-slottet med det samme i stedet for at vente på timeout.

I øjeblikket dropper cpnos blot forbindelsen ved genstart/sluk.  Et NETEND-
kald i cpnos's nedlukningskode ville give en renere server-log og hurtigere
slot-genfrigivelse.

---

## Interessant spor 1: ZSDOS + ZCPR clock-driver (filstemplinger)

**Status:** Ikke implementeret.  Undersøges når tid tillader.

### Baggrund

ZSDOS (Z-System BDOS, Harold F. Bower & Cameron W. Cotrill) er en drop-in
CP/M 2.2 BDOS-erstatning.  Den tilføjer:

- `GET$TIME` / `PUT$TIME` BDOS-kald (kompatible med CP/M 3 BDOS-104/105)
- DateStamper-filstemplinger i `!!!TIME&.DAT` (oprettelse + ændring pr. fil)
- En pluggbar "clock capsule" — en kort flytbar kodeblok ZSDOS kalder for at
  hente/sætte systemtiden

ZCPR3 / NZ-COM er den tilhørende kommandoprocessor-erstatning.  Begge er
CP/M 2.2-kompatible og kan lastes ovenpå rcbios.

### Ideen: clock capsule over BDOS-66/67

ZSDOS's clock capsule er en lille Z80-rutine der:
1. Kaldes af ZSDOS ved GET$TIME eller PUT$TIME
2. Udfylder en 6-byte buffer: `days_lo, days_hi, hr_bcd, min_bcd, sec_bcd, (hundredths)`
3. Returnerer med carry=0 (OK) eller carry=1 (fejl)

Vores eksisterende FNC=105 vendor-extension (se `TOD_TIME_LOOKUP.md`) returnerer
præcis dette format i MSG[0..4] (days_lo, days_hi, hr, min, sec — alle BCD).

En clock capsule der kalder BDOS 66/67 med FNC=105 og kopierer MSG[0..4] til
ZSDOS's forventede buffer ville give:

- Transparent `BDOS 105` support for alle programmer der bruger ZSDOS
- Filstemplinger i `!!!TIME&.DAT` for alle filer åbnet/lukket under CP/NET
- Fungerende `DATE`, `SHOW`, `ZXD` (ZSDOS directory med datoer), etc.
- Alt uden lokal RTC-hardware på RC702

Slaven behøver **ingen lokal klokke** — masteren har z80pack-RTC, og alle
disk-operationer sker alligevel på masteren.

### Implementeringsplan (foreløbig)

1. Bekræft at ZSDOS laster og kører stabilt under rcbios + CP/NET
2. Skriv clock capsule i Z80-assembler (~30-50 bytes):
   - Byg FNC=105 beskedbuffer i en fast BSS-celle (udenfor TPA)
   - Kald BDOS 66 (NSEND) + BDOS 67 (NRECV)
   - Kopier MSG[0..4] til ZSDOS GET$TIME-bufferen
   - Returnerer carry=0 ved FMT=0x01 i svaret, carry=1 ellers
3. Installer capsule via CLKLOAD (ZSDOS-værktøj)
4. Verificer via `DATE`-kommando og `!!!TIME&.DAT`-stemplinger

### Referencemateriale

- ZSDOS Manual: `deramp.com/downloads/mfe_archive/.../ZSDOS Manual.TXT`
- ZSDOS source i RomWBW: `github.com/wwarthen/RomWBW/blob/master/Source/ZSDOS/`
- RomWBW clock-driver eksempler (mange hardwaretyper) som skabeloner
- Capsule-format: ZSDOS Manual, afsnit "Clock Driver Capsule"

---

## Interessant spor 2: Transparent netværksudskrift (LST: → serverfil)

**Status:** Ikke implementeret.  Undersøges når tid tillader.

### Baggrund

CP/NET 1.2 har to mekanismer til at sende LIST-output til serveren:

- **FNC=2** (LST: direkte): SERVER.RSP sender bytes til serverens LST:-enhed
- **FNC=3** (LST: spooler): SPOOL.RSP på serveren køer output til en fil

DRI's originale `SPOOL.RSP` er en MP/M II Resident System Process der
intercepterer FNC=3-beskeder fra slaver og appender til en spool-fil på
serverens disk, hvorfra den kan udskrives bagefter.

### Ideen

Når et CP/M-program på slaven skriver til `LST:`, ruter NDOS kaldet som
FNC=2 eller FNC=3 til serveren — afhængig af om `SPOOL.RSP` er konfigureret.
Serveren kan da:

- Appende output til en navngivet fil på et serversdrev (fx `D:PRINT.TXT`)
- Formatere og gemme som PostScript / PDF via et serverscript
- Sende til en netværksprinter (LPR eller lignende fra Python-serveren)

Det giver transparent udskrift fra CP/M-programmer som `PIP LST:=FILE.TXT`
eller Wordstar-print, **uden at RC702 behøver en lokal printer**.

### To tilgange

**A. SPOOL.RSP i MPM.SYS (klassisk DRI)**

Kræver at SPOOL.RSP inkluderes i `MPM.SYS` ved GENSYS og konfigureres med
spool-filnavn.  Output fra alle slaver samles i én kø.  Fordel: ingen
ændringer i cpnos eller SERVER.RSP.  Ulempe: SPOOL.RSP er en ekstra RSP-
plads i MP/M.

**B. FNC=2 handler i SERVER.RSP (vores tilgang)**

Udvide `server.asm`'s FNC=2-handler (`lstout`) til at appende til en fil
på serverdisken i stedet for at sende til MP/M's lokale LST:-enhed.  Giver
fuld kontrol: per-slave-filer, tidsstempling, automatisk flush på FMT=0xFE
(NETEND), integration med Python-baseret postprocessor.

Vores Python-baserede cpnet_bridge (MAME-laget) kunne alternativt
interceptere FNC=2-beskeder i TCP-strømmen og skrive direkte til en værtsfil
— uden at ændre hverken SERVER.RSP eller MPM.SYS.

### Implementeringsplan (foreløbig)

1. Bekræft at FNC=2 (LST: direkte) allerede virker under cpnos
   — test med `PIP LST:=` fra slaven og observer serverens CONOUT
2. Vælg tilgang A eller B ud fra kompleksitet
3. Hvis B: udvid `lstout` i `server.asm` til at åbne/appende en fil
4. Tilføj flush ved NETEND så filen lukkes rent

---

## Diagnostisk værktøj: NETSTAT.COM

**Status:** Ikke implementeret.  Lav kompleksitet.

Et simpelt CP/M-program der kalder BDOS-68 og viser netværksstatus:

```
NETSTAT v1.0
  Logged in   : YES
  TX errors   : 0
  RX errors   : 0
  Network cfg : drive A: local, B: server, drive C: server
```

Nyttigt ved PIO/SIO-fejlfinding — giver én enkelt kommando der bekræfter
forbindelsestilstand uden at skulle kigge i MAME-log.

---

## Record locking (multi-bruger, fremtidig)

BDOS-42/43 (LOCK/UNLOCK RECORD) videresendes af NDOS til serveren.  Relevant
kun ved to samtidige slaver med adgang til fælles filer.  Ikke aktuelt i
vores enkelt-slave-konfiguration, men implementeret og tilgængeligt.

---

## Prioritering

| Spor | Kompleksitet | Nyttighed | Prioritet |
|------|-------------|-----------|-----------|
| ZSDOS clock-driver (filstemplinger) | Middel | Høj — synlig i daglig brug | Høj |
| ZCPR3 / NZ-COM integration | Middel | Middel — kræver ZSDOS først | Efter ZSDOS |
| Netværksudskrift (LST: → fil) | Lav–middel | Høj — nyttigt ved fysisk RC702 | Høj |
| NETSTAT.COM (BDOS-68) | Lav | Middel — diagnostisk | Lav |
| Orderly shutdown (NETEND) | Lav | Lav — kosmetisk | Lav |
| XFCB-stemplinger på server | Undersøg MP/M config | Potentielt gratis | Undersøg |
| Record locking | Lav | Lav — enkelt-slave | Parkeret |

## Referencer

- [CP/NET Network Operating System Reference Manual](http://sebhc.durgadas.com/CPNET-docs/cpnet.html)
- [Unofficial CP/NET Documentation (z80pack mirror)](http://cpmarchives.classiccmp.org//cpm/mirrors/www.autometer.de/unix4fun/z80pack/cpnet/cpnet.htm)
- [CP/M BDOS function summary (seasip.info)](https://www.seasip.info/Cpm/bdosfunc.html)
- [ZSDOS Manual (DeRamp)](https://deramp.com/downloads/mfe_archive/040-Software/Z80%20CPM/ZSDOS/ZSDOS%20Manual.TXT)
- [RomWBW ZSDOS source med clock-driver eksempler](https://github.com/wwarthen/RomWBW/blob/master/Source/ZSDOS/)
- `cpnet/TOD_TIME_LOOKUP.md` — detaljeret FNC=105 protokoldokumentation
- `cpnet-z80/src/ndos3.asm` — DRI NDOS kildekode med funktionsdispatch-tabeller
- `cpnet/mpm-server/server.asm` — SERVER.RSP med `gettod`-extension
