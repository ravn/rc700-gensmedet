# RC750 Partner — Brugervejledning (Installation og vedligeholdelse)

Kilde: datamuseum.dk **Bits:30002753** (PN 99109961, A/S Regnecentralen 1984).
188 sider. Beskriver bl.a. boot-PROM'ens selvtest-adfærd og fejlkoder.

- `RC750_Partner_brugervejledning_30002753.pdf` — søgbar (OCR-tekstlag lagt på via
  `ocrmypdf -l dan+eng`, Docker `jbarlow83/ocrmypdf`).
- `RC750_Partner_brugervejledning_30002753.txt` — rent tekstudtræk (OCR sidecar).

## Nøgleafsnit (dokumentets sidetal)
- **8.1 Selvtest under opstart** s.120
- **8.3 Fejlkoder under opstart** s.122 — fejlkode-tabellen (se nedenfor)
- **8.4 Funktionstestene** s.128 (8.4.1 RW-test, 8.4.2 Diskettestation, 8.4.3 Winchester)
- **DEL IV D. Konnektorer** s.163

## Fejlkode-tabel (OCR, uddrag) — [120h] i ROM'en
| kode | enhed | fejl |
|------|-------|------|
| 19 | Hovedkort systemparametre | Checksum fejl (NVRAM ej initialiseret) |
| 20-23 | Hovedkort Serial Interface | X.21 / V.24 forbindelsesfejl |
| **24** | **Hovedkort Printer port** | **Fejl i styresignaler** (0x260 kontrol-latch) |
| **25** | **Hovedkort Printer port** | **Fejl i data-signaler** (0x250 data-latch) |
| 26 | Diskette kontroller | Underløb ved læsning |
| 27 | Central enhed | CRC fejl |
| 30 | Diskette | "klar"-tilstand skiftet |
| 31-34 | Winchester | Søge-/data-/kommando-/RAM-fejl |
| 35 | Hovedkort SCSI Interface | (rettet i MAME: PPI port B bit3) |

**Konsekvens for MAME-emuleringen:** selvtestens "printer port"-test (fejl 24/25) skriver
walking-bit-mønstre til printer-data (0x250) og -kontrol (0x260) og læser tilbage — uden
printer/loopback fejler den (forventet). Bootstien er selvtest → PARTNER BOOTLOADER →
"Styresystem indlæses fra" (konfig-enhed, normalt A: floppy). Se `[[project_rc750_partner_boot_bringup]]`.

## Demo-video: rc750_boot_realfont.mp4

MAME-optagelse (ravn/mame) af RC750 Partner der booter SW1500-disken: selvtest →
banner → installations-menu (med box-ramme + den ægte 9×14-font fra pixel-hukommelsen
@0xF0000) → ESC + "j" for at forlade menuen → CP/M `A>` → `DIR` viser filerne. Fonten
renderes direkte fra Partnerens tegngenerator (Programmer's Guide §4.1.2), loadet af
boot-ROM'en ved POST. Detaljer: `[[project_rc750_partner_boot_bringup]]`.
