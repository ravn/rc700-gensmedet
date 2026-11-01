# GSX-86 dokumentation

Tekst-udgaver (`.txt`) er ekstraheret via pypdf fra PDF-filerne, så vi kan
grep/læse uden at skulle PDF-rendere igen. Opdater tekst hvis PDF udskiftes.

## RASM-86 manual (external reference only)

The locally retained `rasm86-manual-computerhistory.pdf` is titled
*Programmer's Utilities Guide for the CP/M-86 Family of Operating Systems*
(Digital Research, 1983; text conversion edited by Emmanuel Roche).
Archive entry point: [Computer History Museum](https://computerhistory.org/).
The exact PDF download URL has not been recovered; this is an archive
link, not a verified direct link to the manual.

The PDF and extracted text remain local and are not added to git:
their copyright notice restricts reproduction of the publication.
The notice separately permits incorporating its example programs.

| Fil | Kilde | Note |
|-----|-------|------|
| `gsx86-programmer-manual-retrobrew.*` | retrobrewcomputers.org (brugeren hentede via browser; Cloudflare blokerer curl) | Primær reference — har Appendix A/B/C med CP/M-86 calling convention + VDI-spec |
| `5000-2024_GSX_Graphics_Extension_Programmers_Guide_Sep83.*` | bitsavers | Officielle DRI dokument, Sept 1983 — formentlig identisk med retrobrew |
| `GSX-86_Graphics_Extension_Users_Guide_for_the_IBM_PC_Jul83.*` | bitsavers | Brugerguide, IBM PC-specifik |
| `GSX_Handbook_1984.*` | bitsavers | Omfangsrig håndbog, 258 sider — inkluderer sandsynligvis driver-skelet-eksempel |

| `concurrent_programmers_utilities_1986.*` | bitsavers | Concurrent DOS 86 Programmer's Utilities Guide, Nov 1986 — **LINK-86 kapitel 7** (side 125+, linje 4535+ i .txt): fuld command-syntax, section-options (CODE/DATA/EXTRA/STACK), sub-params ORIGIN/ADDITIONAL/MAXIMUM/ABSOLUTE. Afgørende for korrekte CMD-group-descriptors i driver-build. |

## Sektioner at huske

- **retrobrew Appendix B** (side 41-44, linje ~1853 i .txt): CP/M-86 GDOS
  calling sequence + driver entry prolog — matcher 1:1 vores drivers
  dispatcher ved offset 0x80 i `dd759h1.sys`.
- **retrobrew Appendix C** (fra linje ~2135): fuld VDI-specifikation med
  alle GDOS-opcodes, deres parametre, og evt. driver-interne nummereringer.
- **Section 3** (GDOS opcodes, linje ~960-1120): oversigt over opcodes
  1-26+ inkl. ESCAPE-sub-funktioner (ID 1-19).
