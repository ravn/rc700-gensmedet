# Datamuseum RC759 Piccoline artifact catalogue

Complete inventory of every **RC759 Piccoline** artifact preserved by Dansk
Datahistorisk Forening (DDHF / datamuseum.dk), keyword
[RC/RC759](https://ddhf.dk/wiki/Bits:Keyword/RC/RC759).
Snapshot 2026-08-16 — 188 entries (2 higher-protection entries on the wiki are
not listed). This is the RC759 counterpart to `DATAMUSEUM_RC700_ARTIFACTS.md`.

## How to fetch

- **Download any item:** `https://datamuseum.dk/bits/<Bits-number>`
  (e.g. Bits:30002654 -> <https://datamuseum.dk/bits/30002654>). The `bits/`
  endpoint returns the stored representation. Large disk images are **not**
  committed to this repo — fetch on demand.
- **Per-item wiki page** (metadata, provenance): the `Bits:` links below.
- **CP/M / rc759 file listings** (browsable catalogue of each disk's contents):
  `https://datamuseum.dk/aa/rc759/<Bits-number>.html`.

## Formats in this catalogue

| Format | Count | Meaning |
|--------|------:|---------|
| BINARY | 74 | Raw sector image. The **1,261,568-byte** ones are full 5.25" DS-HD RC759 disks (77 cyl x 2 heads x 8 sectors x 1024 B) — directly loadable by MAME `rc759` (floptool identifies them as `rc759`). |
| IMAGEDISK | 59 | Dave Dunfield ImageDisk `.imd` (only the used tracks; smaller). MAME reads `.imd` directly. |
| PDF | 44 | Scanned manuals / release notes. |
| BAGIT | 11 | BagIt ZIP bundle wrapping one or more of the above. |

## MAME boot disks (native rc759 `.img` format)

A **1,261,568-byte** BINARY entry is already in the exact geometry MAME's
`rc759` driver expects (`FLOPPY_RC759_FORMAT`: FF_525 / DSHD / MFM, 8x1024,
77 cyl, 2 heads). Good boot candidates: **Bits:30002654 "CDOS systemdisk"**,
**Bits:30002664 "Digital Research C - CCP/M - May 84"**, **Bits:30002725
"SW1609 Digital Research C - CCP/M - Oct 83"**.

The **Watcom/CP/M-86 work** in this workspace boots
`scratch/rc759-pce/images/mandel.img` (1,261,568 B, native rc759 format — a
CCP/M-86 turnkey disk; NOT the PCE `.pfdc` format). floptool identifies it as
`rc759`. This is the reference boot image for the rc759 MAME launcher.

## Boot ROMs

The ROA955/ROA956 and ROB611/ROB612 pairs (16 KB each, Bits:30004266/30004267
and 30004797/30004798) are Piccoline boot-ROM halves. MAME's `rc759` already
ships four verified BIOS ROM sets (`rc759-1-2.1` .. `rc759-2-5.1`) in
`mame/roms/rc759/`.

## Full catalogue (188 entries)

| Bits | Format | Size (bytes) | Date | Description/Filename |
|------|--------|-------------:|------|----------------------|
| [Bits:30002839](https://datamuseum.dk/wiki/Bits:30002839) | BINARY | 1,261,568 |  | 40 timers kursus i EDB (Vesthimmerlands gymnasium) |
| [Bits:30002840](https://datamuseum.dk/wiki/Bits:30002840) | BINARY | 1,261,568 |  | ANALYSE - matematisk funktionsanalyse |
| [Bits:30003898](https://datamuseum.dk/wiki/Bits:30003898) | BAGIT | 446,240 |  | Brug pæren (Piccoline) |
| [Bits:30004285](https://datamuseum.dk/wiki/Bits:30004285) | IMAGEDISK | 430,129 |  | Budget: Datacentret ved Odense Skolevæsen |
| [Bits:30005381](https://datamuseum.dk/wiki/Bits:30005381) | PDF | 573,956 | 1987-02-03 | CCP/M86 3.1 PICCOLINE XIOS Release 3.1 - 03.02.1987 |
| [Bits:30002654](https://datamuseum.dk/wiki/Bits:30002654) | BINARY | 1,261,568 |  | CDOS systemdisk |
| [Bits:30002655](https://datamuseum.dk/wiki/Bits:30002655) | BINARY | 1,261,568 |  | COBOL Level II v.2.1 og RcTekst |
| [Bits:30002656](https://datamuseum.dk/wiki/Bits:30002656) | BINARY | 1,261,568 |  | COBOL-programmer til undervisning |
| [Bits:30004478](https://datamuseum.dk/wiki/Bits:30004478) | IMAGEDISK | 504,864 |  | CPI-graf 2.5 til Piccoline/Partner |
| [Bits:30005382](https://datamuseum.dk/wiki/Bits:30005382) | PDF | 151,013 | 1987-02-10 | Concurrent DOS 4.1 PICCOLINE XIOS Release 4.0 - 10.02.1987 |
| [Bits:30004632](https://datamuseum.dk/wiki/Bits:30004632) | IMAGEDISK | 295,819 |  | DAVID - Datamaskinens fundamentale virkemåde (Piccoline) |
| [Bits:30002663](https://datamuseum.dk/wiki/Bits:30002663) | BINARY | 1,261,568 |  | DEMO PICCOLINE - COMAL80 1.4 |
| [Bits:30004634](https://datamuseum.dk/wiki/Bits:30004634) | IMAGEDISK | 876,135 |  | DEMO programmer i COMAL-80 |
| [Bits:30002660](https://datamuseum.dk/wiki/Bits:30002660) | BINARY | 1,261,568 |  | DISKGEN - Fremstiller en elev-diskette |
| [Bits:30004289](https://datamuseum.dk/wiki/Bits:30004289) | IMAGEDISK | 452,606 |  | Databank: Datacentret ved Odense Skolevæsen |
| [Bits:30004290](https://datamuseum.dk/wiki/Bits:30004290) | IMAGEDISK | 345,261 |  | Database: Datacentret ved Odense Skolevæsen |
| [Bits:30002661](https://datamuseum.dk/wiki/Bits:30002661) | BINARY | 1,261,568 |  | Datalære sådan - løsningsdiskette |
| [Bits:30002664](https://datamuseum.dk/wiki/Bits:30002664) | BINARY | 1,261,568 |  | Digital Research C - CCP/M - May 84 |
| [Bits:30003277](https://datamuseum.dk/wiki/Bits:30003277) | BINARY | 1,261,568 |  | Digital Research Draw v.1.0 + Skriv + Regn |
| [Bits:30003931](https://datamuseum.dk/wiki/Bits:30003931) | BAGIT | 4,584,393 |  | Disketter indleveret af Steffen Jensen (Piccolo/Piccoline) |
| [Bits:30003050](https://datamuseum.dk/wiki/Bits:30003050) | BINARY | 1,261,568 |  | Dymos II - Dynamisk Model System |
| [Bits:30003051](https://datamuseum.dk/wiki/Bits:30003051) | BINARY | 1,228,800 |  | Dymos II - Modeller |
| [Bits:30003280](https://datamuseum.dk/wiki/Bits:30003280) | BINARY | 1,261,568 |  | EDDIE fra Piccoliniens programklub |
| [Bits:30003281](https://datamuseum.dk/wiki/Bits:30003281) | BINARY | 1,261,568 |  | EDDIE og Tegn med musen v. 2.0 til Piccoline |
| [Bits:30003905](https://datamuseum.dk/wiki/Bits:30003905) | IMAGEDISK | 1,232,203 |  | EL-FI Totalkartotek |
| [Bits:30002748](https://datamuseum.dk/wiki/Bits:30002748) | PDF | 9,188,994 |  | En introduktion til UNIVERSAL-FILE på Piccoline Vers. 3.0 |
| [Bits:30002749](https://datamuseum.dk/wiki/Bits:30002749) | BINARY | 1,261,568 |  | Familieøkonomispillet - Piccoline version 8.1 |
| [Bits:30003635](https://datamuseum.dk/wiki/Bits:30003635) | IMAGEDISK | 452,746 |  | Farvel og Tobak EDB-undervisningsprogram |
| [Bits:30004300](https://datamuseum.dk/wiki/Bits:30004300) | IMAGEDISK | 391,236 |  | Flytgeo (DAKS Kursuscenter) |
| [Bits:30004493](https://datamuseum.dk/wiki/Bits:30004493) | IMAGEDISK | 61,878 |  | Flyttemarksbrug til Piccoline/Partner |
| [Bits:30002670](https://datamuseum.dk/wiki/Bits:30002670) | BINARY | 1,261,568 |  | Fortegnelse over programmer til Piccolinen (Vesthimmerlands Gymnasium) |
| [Bits:30002668](https://datamuseum.dk/wiki/Bits:30002668) | BINARY | 1,228,800 |  | GEM systemdisk |
| [Bits:30004301](https://datamuseum.dk/wiki/Bits:30004301) | IMAGEDISK | 1,091,005 |  | GUK: Grundled, udsagnsled og komma - Piccoline |
| [Bits:30004066](https://datamuseum.dk/wiki/Bits:30004066) | IMAGEDISK | 1,132,932 |  | HELIOS Demo |
| [Bits:30002669](https://datamuseum.dk/wiki/Bits:30002669) | BINARY | 1,307,648 |  | I-APL - PICCOLINIENs programklub Marts 88 |
| [Bits:30004305](https://datamuseum.dk/wiki/Bits:30004305) | IMAGEDISK | 399,410 |  | Kartotek: Datacentret ved Odense Skolevæsen |
| [Bits:30003059](https://datamuseum.dk/wiki/Bits:30003059) | BINARY | 1,261,568 |  | Kend din kost undervisningsprogram |
| [Bits:30004502](https://datamuseum.dk/wiki/Bits:30004502) | IMAGEDISK | 232,719 |  | Kermit-86 version 2.91 (Piccoline/Partner) |
| [Bits:30004504](https://datamuseum.dk/wiki/Bits:30004504) | IMAGEDISK | 246,017 |  | Klimastationer (Piccoline) |
| [Bits:30004304](https://datamuseum.dk/wiki/Bits:30004304) | IMAGEDISK | 163,091 |  | Kædealgoritmer - Piccoline |
| [Bits:30003061](https://datamuseum.dk/wiki/Bits:30003061) | BINARY | 1,261,568 |  | LEGO LINES programmet til RC Piccoline |
| [Bits:30004658](https://datamuseum.dk/wiki/Bits:30004658) | IMAGEDISK | 505,869 |  | Lykkehjulet (Efter TV2) |
| [Bits:30004399](https://datamuseum.dk/wiki/Bits:30004399) | IMAGEDISK | 1,114,622 |  | Lærerkursus 85: Skolen i informationssamfundet (Piccoline) |
| [Bits:30002867](https://datamuseum.dk/wiki/Bits:30002867) | BINARY | 1,261,568 |  | Maskinskrivning med EDB vers. 3.0 |
| [Bits:30003917](https://datamuseum.dk/wiki/Bits:30003917) | IMAGEDISK | 125,235 |  | Mikro-Logo version 1.0 til Piccoline |
| [Bits:30004317](https://datamuseum.dk/wiki/Bits:30004317) | IMAGEDISK | 378,927 |  | MikroOrd vers. 1.0 |
| [Bits:30003918](https://datamuseum.dk/wiki/Bits:30003918) | IMAGEDISK | 182,525 |  | MikroSkinner v. 1.1 - udskrivning af skinner til tastaturet |
| [Bits:30003933](https://datamuseum.dk/wiki/Bits:30003933) | IMAGEDISK | 272,606 |  | MikroStyrepind 1.0 |
| [Bits:30004318](https://datamuseum.dk/wiki/Bits:30004318) | IMAGEDISK | 410,642 |  | MikroTekst vers. 2.1 |
| [Bits:30003921](https://datamuseum.dk/wiki/Bits:30003921) | IMAGEDISK | 1,062,309 |  | Musik og grafik 1.2 (MASTER) |
| [Bits:30004078](https://datamuseum.dk/wiki/Bits:30004078) | IMAGEDISK | 398,401 |  | Myresnak Release 1.2 boot diskette |
| [Bits:30004678](https://datamuseum.dk/wiki/Bits:30004678) | IMAGEDISK | 214,234 |  | Myresnak Release 010784 boot diskette |
| [Bits:30005310](https://datamuseum.dk/wiki/Bits:30005310) | BAGIT | 1,816,131 |  | Open Access II v2.10 (dansk) |
| [Bits:30002679](https://datamuseum.dk/wiki/Bits:30002679) | BINARY | 1,261,568 |  | PGM1 - indeholder forskellige undervisningsprogrammer |
| [Bits:30002680](https://datamuseum.dk/wiki/Bits:30002680) | BINARY | 1,261,568 |  | PGM2 - indeholder forskellige undervisningsprogrammer |
| [Bits:30002874](https://datamuseum.dk/wiki/Bits:30002874) | BINARY | 1,228,800 |  | PKArc, WordStar 3.30 (dansk), XCOPY for Concurrent DOS |
| [Bits:30004080](https://datamuseum.dk/wiki/Bits:30004080) | IMAGEDISK | 294,102 |  | Papyrus v.1.0 - tekstbehandling til de mindste årgange i folkeskolen |
| [Bits:30002678](https://datamuseum.dk/wiki/Bits:30002678) | BINARY | 1,307,648 |  | Pascal MT+ Version 3.3 Rel 1.2 |
| [Bits:30002875](https://datamuseum.dk/wiki/Bits:30002875) | BINARY | 1,261,568 |  | Pascal-bibliotek til tegning af streg-grafik på Piccoline |
| [Bits:30003016](https://datamuseum.dk/wiki/Bits:30003016) | BINARY | 16,384 |  | Piccoline ROA922 "Eprom disk" |
| [Bits:30003017](https://datamuseum.dk/wiki/Bits:30003017) | BINARY | 16,384 |  | Piccoline ROA923 "Eprom disk" |
| [Bits:30003018](https://datamuseum.dk/wiki/Bits:30003018) | BINARY | 16,384 |  | Piccoline ROA924 "Eprom disk" |
| [Bits:30003019](https://datamuseum.dk/wiki/Bits:30003019) | BINARY | 16,384 |  | Piccoline ROA925 "Eprom disk" |
| [Bits:30003020](https://datamuseum.dk/wiki/Bits:30003020) | BINARY | 16,384 |  | Piccoline ROA926 "Eprom disk" |
| [Bits:30003021](https://datamuseum.dk/wiki/Bits:30003021) | BINARY | 16,384 |  | Piccoline ROA927 "Eprom disk" |
| [Bits:30003022](https://datamuseum.dk/wiki/Bits:30003022) | BINARY | 16,384 |  | Piccoline ROA928 "Eprom disk" |
| [Bits:30003023](https://datamuseum.dk/wiki/Bits:30003023) | BINARY | 16,384 |  | Piccoline ROA929 "Eprom disk" |
| [Bits:30004266](https://datamuseum.dk/wiki/Bits:30004266) | BINARY | 16,384 |  | Piccoline ROA955 boot rom (1/2) |
| [Bits:30004267](https://datamuseum.dk/wiki/Bits:30004267) | BINARY | 16,384 |  | Piccoline ROA956 boot rom (2/2) |
| [Bits:30004797](https://datamuseum.dk/wiki/Bits:30004797) | BINARY | 16,384 |  | Piccoline ROB611 boot rom (1/2) |
| [Bits:30004798](https://datamuseum.dk/wiki/Bits:30004798) | BINARY | 16,384 |  | Piccoline ROB612 boot rom (2/2) |
| [Bits:30004324](https://datamuseum.dk/wiki/Bits:30004324) | IMAGEDISK | 1,134,031 |  | Piccoline diskette 1.40/1.4 fra UV-DATATEKET |
| [Bits:30002419](https://datamuseum.dk/wiki/Bits:30002419) | PDF | 6,245,429 | 1984-09 | Piccolinien årgang 1984 nr. 1 - et edb-blad for lærere - September 1984 |
| [Bits:30002420](https://datamuseum.dk/wiki/Bits:30002420) | PDF | 7,665,814 | 1984-11 | Piccolinien årgang 1984 nr. 2 - et edb-blad for lærere - November 1984 |
| [Bits:30002421](https://datamuseum.dk/wiki/Bits:30002421) | PDF | 7,410,809 | 1985-02 | Piccolinien årgang 1985 nr. 1 - et edb-blad for lærere - Februar 1985 |
| [Bits:30002422](https://datamuseum.dk/wiki/Bits:30002422) | PDF | 9,874,260 | 1985-05 | Piccolinien årgang 1985 nr. 2 - et edb-blad for lærere - Maj 1985 |
| [Bits:30002423](https://datamuseum.dk/wiki/Bits:30002423) | PDF | 9,706,871 | 1985-06 | Piccolinien årgang 1985 nr. 3 - et edb-blad for lærere - Juni 1985 |
| [Bits:30002424](https://datamuseum.dk/wiki/Bits:30002424) | PDF | 13,656,646 | 1985-09 | Piccolinien årgang 1985 nr. 4 - et edb-blad for lærere - September 1985 |
| [Bits:30002425](https://datamuseum.dk/wiki/Bits:30002425) | PDF | 11,138,476 | 1985-12 | Piccolinien årgang 1985 nr. 5 - et edb-blad for lærere - December 1985 |
| [Bits:30002426](https://datamuseum.dk/wiki/Bits:30002426) | PDF | 17,145,091 | 1986-01 | Piccolinien årgang 1986 nr. 1 - et edb-blad for lærere - Januar 1986 |
| [Bits:30002427](https://datamuseum.dk/wiki/Bits:30002427) | PDF | 14,517,850 | 1986-03 | Piccolinien årgang 1986 nr. 2 - et edb-blad for lærere - Marts 1986 |
| [Bits:30002428](https://datamuseum.dk/wiki/Bits:30002428) | PDF | 14,536,402 | 1986-05 | Piccolinien årgang 1986 nr. 3 - et edb-blad for lærere - Maj 1986 |
| [Bits:30002429](https://datamuseum.dk/wiki/Bits:30002429) | PDF | 25,655,859 | 1986-09 | Piccolinien årgang 1986 nr. 4 - et edb-blad for lærere - September 1986 |
| [Bits:30002430](https://datamuseum.dk/wiki/Bits:30002430) | PDF | 29,048,394 | 1986-12 | Piccolinien årgang 1986 nr. 5 - et edb-blad for lærere - December 1986 |
| [Bits:30002431](https://datamuseum.dk/wiki/Bits:30002431) | PDF | 37,911,462 | 1987-02 | Piccolinien årgang 1987 nr. 1 - et edb-blad for lærere - Februar 1987 |
| [Bits:30002432](https://datamuseum.dk/wiki/Bits:30002432) | PDF | 36,043,105 | 1987-05 | Piccolinien årgang 1987 nr. 2 - et edb-blad for lærere - Maj 1987 |
| [Bits:30002433](https://datamuseum.dk/wiki/Bits:30002433) | PDF | 31,863,840 | 1987-09 | Piccolinien årgang 1987 nr. 3 - et edb-blad for lærere - September 1987 |
| [Bits:30002434](https://datamuseum.dk/wiki/Bits:30002434) | PDF | 32,209,036 | 1987-12 | Piccolinien årgang 1987 nr. 4 - et edb-blad for lærere - December 1987 |
| [Bits:30002435](https://datamuseum.dk/wiki/Bits:30002435) | PDF | 33,814,797 | 1988-03 | Piccolinien årgang 1988 nr. 1 - et edb-blad for lærere - Marts 1988 |
| [Bits:30002436](https://datamuseum.dk/wiki/Bits:30002436) | PDF | 36,491,829 | 1988-05 | Piccolinien årgang 1988 nr. 2 - et edb-blad for lærere - Maj 1988 |
| [Bits:30002437](https://datamuseum.dk/wiki/Bits:30002437) | PDF | 33,086,467 | 1988-09 | Piccolinien årgang 1988 nr. 3 - et edb-blad for lærere - September 1988 |
| [Bits:30002438](https://datamuseum.dk/wiki/Bits:30002438) | PDF | 30,530,088 | 1988-11 | Piccolinien årgang 1988 nr. 4 - et edb-blad for lærere - November 1988 |
| [Bits:30002439](https://datamuseum.dk/wiki/Bits:30002439) | PDF | 30,686,473 | 1989-06 | Piccolinien årgang 1989 nr. 1 - et edb-blad for lærere - Juni 1989 |
| [Bits:30002440](https://datamuseum.dk/wiki/Bits:30002440) | PDF | 35,025,653 | 1989-10 | Piccolinien årgang 1989 nr. 2 - et edb-blad for lærere - Oktober 1989 |
| [Bits:30002683](https://datamuseum.dk/wiki/Bits:30002683) | BINARY | 1,261,568 |  | PolyPascal-86 v. 3.11 - Piccoline |
| [Bits:30002666](https://datamuseum.dk/wiki/Bits:30002666) | BINARY | 1,261,568 |  | Programmer fra Forlaget FAG ApS |
| [Bits:30002681](https://datamuseum.dk/wiki/Bits:30002681) | BINARY | 1,261,568 |  | RC-Katalog over EDB-bøger og programmer |
| [Bits:30004327](https://datamuseum.dk/wiki/Bits:30004327) | IMAGEDISK | 430,075 |  | RC-Valg - Piccoline |
| [Bits:30004842](https://datamuseum.dk/wiki/Bits:30004842) | PDF | 5,016,174 |  | RCSL-42-I-2472 - PICCOLINE - Den danske skolemikro |
| [Bits:30002757](https://datamuseum.dk/wiki/Bits:30002757) | PDF | 9,113,611 | 1984-06 | RCSL-99-0-00756 - PICCOLINE Betjening, Installation og vedligeholdelsesvejledning - Juni 1984 |
| [Bits:30009587](https://datamuseum.dk/wiki/Bits:30009587) | PDF | 16,400,741 | 1984-06 | RCSL-99-0-00821 - Piccoline Brugervejledning - 1984-06 |
| [Bits:30002758](https://datamuseum.dk/wiki/Bits:30002758) | PDF | 7,543,580 | 1985-02 | RCSL-99-0-00831 - PICCOLINE Brugervejleding - Betjening - februar 1985 |
| [Bits:30002760](https://datamuseum.dk/wiki/Bits:30002760) | PDF | 7,564,300 | 1985-02 | RCSL-99-0-00832 - PICCOLINE Brugervejledning - Installation og vedligeholdelse - Februar 1985 |
| [Bits:30002762](https://datamuseum.dk/wiki/Bits:30002762) | PDF | 3,777,243 | 1985-04 | RCSL-99-0-00852 - SW1499 Mikro-Logo Brugervejledning - April 1985 |
| [Bits:30002764](https://datamuseum.dk/wiki/Bits:30002764) | PDF | 10,361,614 | 1985 | RCSL-99-0-00864 - PICCOLINE Programmer's Guide Version 2.0 - 1985 |
| [Bits:30007048](https://datamuseum.dk/wiki/Bits:30007048) | PDF | 2,803,905 | 1985-08 | RCSL-99-0-00866 - Installationsvejlning for RC Piccoline ADAM - 1985-08 |
| [Bits:30002765](https://datamuseum.dk/wiki/Bits:30002765) | PDF | 4,907,595 | 1985-11 | RCSL-99-0-00878 - SW1434 RcFont Brugervejledning Version 1.3 - November 1985 |
| [Bits:30002759](https://datamuseum.dk/wiki/Bits:30002759) | PDF | 28,657,414 | 1986-10 | RCSL-99-0-00929 - PICCOLINE Brugervejleding - Betjening - Oktober 1986 |
| [Bits:30002761](https://datamuseum.dk/wiki/Bits:30002761) | PDF | 13,348,937 | 1986-10 | RCSL-99-0-00930 - PICCOLINE Brugervejledning - Installation og vedligeholdelse - Oktober 1986 |
| [Bits:30002766](https://datamuseum.dk/wiki/Bits:30002766) | PDF | 5,988,146 | 1987-10-30 | RCSL-99-1-09800 - SW1403 PICCOLINE RcKalk rel. 1.3 Brugervejledning - 30.10.1987 |
| [Bits:30002756](https://datamuseum.dk/wiki/Bits:30002756) | PDF | 2,491,324 | 1984-11 | RCSL-99-1-09965 - SW1404 Brugervejledning for ACP750 version 2.0 - November 1984 |
| [Bits:30002767](https://datamuseum.dk/wiki/Bits:30002767) | PDF | 6,855,576 | 1984-12 | RCSL-99-1-09972 - SW1405 PICCOLINE RcTekst Brugervejledning - December 1984 |
| [Bits:30004843](https://datamuseum.dk/wiki/Bits:30004843) | PDF | 4,511,875 |  | RCSL-99-1-10008 - PICCOLINE - den danske skolemikro |
| [Bits:30003926](https://datamuseum.dk/wiki/Bits:30003926) | PDF | 16,051,535 | 1985 | RCSL-99-1-10090 - SW1402 PolyPascal v3.11 brugervejledning - 1985 |
| [Bits:30002763](https://datamuseum.dk/wiki/Bits:30002763) | PDF | 1,039,643 | 1985-03 | RCSL-99-1-10147 - SW1495 Myresnak vejledning - Marts 1985 |
| [Bits:30003928](https://datamuseum.dk/wiki/Bits:30003928) | IMAGEDISK | 1,062,288 |  | RcKalk rel. 1.1 for Piccoline |
| [Bits:30002684](https://datamuseum.dk/wiki/Bits:30002684) | BINARY | 1,261,568 |  | RcTekst version 1.3 |
| [Bits:30002641](https://datamuseum.dk/wiki/Bits:30002641) | BINARY | 1,261,568 |  | SCANLOG - Piccoline vers. nov. 87 |
| [Bits:30004336](https://datamuseum.dk/wiki/Bits:30004336) | IMAGEDISK | 469,997 |  | SKAT - et emnearbejde (Piccoline) |
| [Bits:30004337](https://datamuseum.dk/wiki/Bits:30004337) | IMAGEDISK | 1,058,196 |  | SKOMAL Version 84.06.04 til Piccoline |
| [Bits:30004705](https://datamuseum.dk/wiki/Bits:30004705) | IMAGEDISK | 1,101,161 |  | SKRIV v. 5.5 undervisningsdiskette |
| [Bits:30004538](https://datamuseum.dk/wiki/Bits:30004538) | BAGIT | 1,653,995 |  | SW1400-10 Piccoline Distributions system 2.3 |
| [Bits:30002685](https://datamuseum.dk/wiki/Bits:30002685) | BINARY | 1,261,568 |  | SW1400-10 Piccoline Distributions system 2.3 - disk 1/4 |
| [Bits:30002686](https://datamuseum.dk/wiki/Bits:30002686) | BINARY | 1,261,568 |  | SW1400-10 Piccoline Distributions system 2.3 - disk 2/4 |
| [Bits:30002687](https://datamuseum.dk/wiki/Bits:30002687) | BINARY | 1,261,568 |  | SW1400-10 Piccoline Distributions system 2.3 - disk 3/4 |
| [Bits:30002688](https://datamuseum.dk/wiki/Bits:30002688) | BINARY | 1,261,568 |  | SW1400-10 Piccoline Program pakke 2.3 - disk 4/4 |
| [Bits:30004107](https://datamuseum.dk/wiki/Bits:30004107) | BAGIT | 1,748,729 |  | SW1400 CCP/M 86 Distributionsdiskette 3.1 |
| [Bits:30004229](https://datamuseum.dk/wiki/Bits:30004229) | BAGIT | 1,751,601 |  | SW1400 CCP/M 86 Distributionsdiskette 3.1a |
| [Bits:30004536](https://datamuseum.dk/wiki/Bits:30004536) | IMAGEDISK | 824,038 |  | SW1400 Piccoline Distributions system 1.2 |
| [Bits:30004537](https://datamuseum.dk/wiki/Bits:30004537) | BAGIT | 1,408,600 |  | SW1400 Piccoline Distributions system 2.2 |
| [Bits:30004925](https://datamuseum.dk/wiki/Bits:30004925) | BAGIT | 1,418,383 |  | SW1400 Piccoline Distributions system 2.3 |
| [Bits:30002689](https://datamuseum.dk/wiki/Bits:30002689) | BINARY | 1,261,568 |  | SW1400 Piccoline Distributions system 2.3 - disk 1/3 |
| [Bits:30002690](https://datamuseum.dk/wiki/Bits:30002690) | BINARY | 1,261,568 |  | SW1400 Piccoline Distributions system 2.3 - disk 2/3 |
| [Bits:30002691](https://datamuseum.dk/wiki/Bits:30002691) | BINARY | 1,261,568 |  | SW1400 Piccoline Distributions system 2.3 - disk 3/3 |
| [Bits:30004539](https://datamuseum.dk/wiki/Bits:30004539) | IMAGEDISK | 394,369 |  | SW1402 PolyPascal v3.10 (dk) til Piccoline |
| [Bits:30003934](https://datamuseum.dk/wiki/Bits:30003934) | IMAGEDISK | 413,768 |  | SW1402 PolyPascal v3.11 (dk) til Piccoline |
| [Bits:30004540](https://datamuseum.dk/wiki/Bits:30004540) | IMAGEDISK | 184,624 |  | SW1403-F RcKalk release 1.3 |
| [Bits:30009617](https://datamuseum.dk/wiki/Bits:30009617) | IMAGEDISK | 197,921 |  | SW1403 RcKalk release 1.0 |
| [Bits:30004360](https://datamuseum.dk/wiki/Bits:30004360) | IMAGEDISK | 353,415 |  | SW1404 ACP Release: 5.1 |
| [Bits:30002692](https://datamuseum.dk/wiki/Bits:30002692) | BINARY | 1,261,568 |  | SW1405 RcTekst release 1.2 |
| [Bits:30009618](https://datamuseum.dk/wiki/Bits:30009618) | IMAGEDISK | 240,888 |  | SW1405 RcTekst release 1.3 |
| [Bits:30005757](https://datamuseum.dk/wiki/Bits:30005757) | IMAGEDISK | 153,956 |  | SW1426 RC Teledata Release 2.0 |
| [Bits:30004541](https://datamuseum.dk/wiki/Bits:30004541) | IMAGEDISK | 596,903 |  | SW1433 RcTekst II release 3.3 |
| [Bits:30009619](https://datamuseum.dk/wiki/Bits:30009619) | IMAGEDISK | 590,767 |  | SW1433-U RcTekst II release 3.0 |
| [Bits:30002693](https://datamuseum.dk/wiki/Bits:30002693) | BINARY | 1,261,568 |  | SW1433-U RcTekst II release 3.1 |
| [Bits:30002694](https://datamuseum.dk/wiki/Bits:30002694) | BINARY | 1,261,568 |  | SW1435 RcFont Release 1.3 |
| [Bits:30005758](https://datamuseum.dk/wiki/Bits:30005758) | IMAGEDISK | 176,436 |  | SW1435 RcFont Release 1.3 |
| [Bits:30002695](https://datamuseum.dk/wiki/Bits:30002695) | BINARY | 1,261,568 |  | SW1447 RcStart Release 1.0 |
| [Bits:30005759](https://datamuseum.dk/wiki/Bits:30005759) | IMAGEDISK | 797,361 |  | SW1447 RcStart Release 1.0 |
| [Bits:30004108](https://datamuseum.dk/wiki/Bits:30004108) | BAGIT | 737,834 |  | SW1448 GEM Collection rel. 1.0 |
| [Bits:30002696](https://datamuseum.dk/wiki/Bits:30002696) | BINARY | 1,261,568 |  | SW1458 Concurrent DOS Distributionsdiskette 4.0 - disk 1/3 |
| [Bits:30002697](https://datamuseum.dk/wiki/Bits:30002697) | BINARY | 1,261,568 |  | SW1458 Concurrent DOS Distributionsdiskette 4.0 - disk 2/3 |
| [Bits:30002698](https://datamuseum.dk/wiki/Bits:30002698) | BINARY | 1,261,568 |  | SW1458 Concurrent DOS Distributionsdiskette 4.0 - disk 3/3 |
| [Bits:30004361](https://datamuseum.dk/wiki/Bits:30004361) | BAGIT | 965,597 |  | SW1458 Concurrent DOS Distributionsdiskette 5.0 |
| [Bits:30009990](https://datamuseum.dk/wiki/Bits:30009990) | IMAGEDISK | 50,574 |  | SW1494 ParFlyt release 1.0 |
| [Bits:30002699](https://datamuseum.dk/wiki/Bits:30002699) | BINARY | 1,261,568 |  | SW1495 Myresnak Release 1.2 |
| [Bits:30002682](https://datamuseum.dk/wiki/Bits:30002682) | BINARY | 1,261,568 |  | SW1499 Mikro-Logo version 1.1 15/04/85 |
| [Bits:30002672](https://datamuseum.dk/wiki/Bits:30002672) | BINARY | 1,261,568 |  | SW1499 Mikro-Logo version 1.2 19/3/87 |
| [Bits:30002787](https://datamuseum.dk/wiki/Bits:30002787) | BINARY | 1,261,568 |  | SW1602 COMPAS Pascal Version 3.07 Release 1.1 |
| [Bits:30002725](https://datamuseum.dk/wiki/Bits:30002725) | BINARY | 1,261,568 |  | SW1609 Digital Research C - CCP/M - Oct 83 |
| [Bits:30005869](https://datamuseum.dk/wiki/Bits:30005869) | IMAGEDISK | 618,328 |  | SW1609 Digital Research C v. 1.11 - May 84 |
| [Bits:30002726](https://datamuseum.dk/wiki/Bits:30002726) | BINARY | 157,696 |  | SW1639 - ANIMATOR - REL 1.0 |
| [Bits:30002727](https://datamuseum.dk/wiki/Bits:30002727) | BINARY | 1,261,568 |  | SW1648 GEM Collection Release 1.1 Disk 1/2 |
| [Bits:30002728](https://datamuseum.dk/wiki/Bits:30002728) | BINARY | 1,261,568 |  | SW1648 GEM Collection Release 1.1 Disk 2/2 |
| [Bits:30002729](https://datamuseum.dk/wiki/Bits:30002729) | BINARY | 1,261,568 |  | SW1657 QUINTET Spreadsheet Release 1.0 |
| [Bits:30004519](https://datamuseum.dk/wiki/Bits:30004519) | IMAGEDISK | 245,011 |  | Skriv ver. 5.5  Piccoline enkeltbruger |
| [Bits:30002881](https://datamuseum.dk/wiki/Bits:30002881) | BINARY | 1,261,568 |  | Skriv version 3.1 til Piccoline |
| [Bits:30004338](https://datamuseum.dk/wiki/Bits:30004338) | IMAGEDISK | 1,198,360 |  | Skriv version 4.2 til Piccoline |
| [Bits:30004339](https://datamuseum.dk/wiki/Bits:30004339) | IMAGEDISK | 333,953 |  | Skriv version 6.6 til Piccoline |
| [Bits:30002799](https://datamuseum.dk/wiki/Bits:30002799) | BINARY | 1,261,568 |  | Spillet om værdipapirerne - Piccoline version 2.1 |
| [Bits:30003932](https://datamuseum.dk/wiki/Bits:30003932) | IMAGEDISK | 65,977 |  | Styr Trafikken 1.0 (Piccoline) |
| [Bits:30003722](https://datamuseum.dk/wiki/Bits:30003722) | BAGIT | 695,305 |  | Styr trafikken - disketter til Piccoline |
| [Bits:30002731](https://datamuseum.dk/wiki/Bits:30002731) | BINARY | 1,228,800 |  | SuperCalc 2 for CP/M-86 |
| [Bits:30004366](https://datamuseum.dk/wiki/Bits:30004366) | IMAGEDISK | 735,005 |  | Tegn med musen vers. 2.0 |
| [Bits:30003949](https://datamuseum.dk/wiki/Bits:30003949) | IMAGEDISK | 371,838 |  | Tryk16 - desktop publishing til skolebrug |
| [Bits:30003950](https://datamuseum.dk/wiki/Bits:30003950) | IMAGEDISK | 585,657 |  | Tryk17 - desktop publishing til skolebrug |
| [Bits:30004546](https://datamuseum.dk/wiki/Bits:30004546) | IMAGEDISK | 1,099,170 |  | Turbo Pascal 5.5 for C-DOS Piccoline |
| [Bits:30004773](https://datamuseum.dk/wiki/Bits:30004773) | IMAGEDISK | 866,927 |  | Turbo Pascal v.2.00B for CP/M-86 |
| [Bits:30005778](https://datamuseum.dk/wiki/Bits:30005778) | IMAGEDISK | 248,119 |  | Turbo Pascal v.3.01A (CP/M-86) |
| [Bits:30002735](https://datamuseum.dk/wiki/Bits:30002735) | BINARY | 1,292,288 |  | Universal-File 3.0 |
| [Bits:30003952](https://datamuseum.dk/wiki/Bits:30003952) | IMAGEDISK | 1,061,282 |  | Universal-File version 10.12.84 |
| [Bits:30002736](https://datamuseum.dk/wiki/Bits:30002736) | BINARY | 1,228,800 |  | VPC/Grafik Version 1.0 (VPCG) |
| [Bits:30002737](https://datamuseum.dk/wiki/Bits:30002737) | BINARY | 1,228,800 |  | VPC/Grafik Version 1.0A (VPCG) |
| [Bits:30002800](https://datamuseum.dk/wiki/Bits:30002800) | PDF | 357,887 | 1989 | VPC/Grafik Version 1.0A (VPCG) vejledning - 1989 |
| [Bits:30002738](https://datamuseum.dk/wiki/Bits:30002738) | BINARY | 1,228,800 |  | VPC/Grafik Version 2.10 (VPCG) |
| [Bits:30002367](https://datamuseum.dk/wiki/Bits:30002367) | PDF | 364,614 | 1989-06 | VPCG - Virtual PC med Grafik - Juni 1989 |
| [Bits:30009637](https://datamuseum.dk/wiki/Bits:30009637) | IMAGEDISK | 155,010 |  | X-MIT ver. 2.3 -  Piccoline |
| [Bits:30002659](https://datamuseum.dk/wiki/Bits:30002659) | BINARY | 1,228,800 |  | Økonomisystemet CONCORDE til CCP/M-86 |
