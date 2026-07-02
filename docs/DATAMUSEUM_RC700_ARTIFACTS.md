# Datamuseum RC700 artifact catalogue

Living inventory of every RC700-family artifact preserved by
[datamuseum.dk keyword RC/RC700](https://datamuseum.dk/wiki/Bits:Keyword/RC/RC700).
Snapshot 2026-07-02 (≈160 entries; 118 software disks downloaded + analysed).

## How to fetch & local copies

- **Download link for any item:** `https://datamuseum.dk/bits/<Bits-number>`
  (e.g. Bits:30003294 → <https://datamuseum.dk/bits/30003294>).  The `bits/`
  endpoint returns the stored representation (raw `.bin`, ImageDisk `.imd`, PDF,
  or a **BagIt ZIP** bundle — see notes).  This URL is the permanent way to
  re-fetch; the full disk images are **not** committed to this repo (large, and
  we only need the extracted BIOS/PROM parts).
- **Local copies we DO hold** (in-repo):
  - Byte-verified **BIOS references**: `rcbios/extracted_bios/*.bin` (see that
    README — maps each ref to its source disk).
  - **RC703 TFj system tracks**: `rc703-div-bios-typer/` (from Bits:30003297).
  - **Autoload PROM sources** ROB358 / PHE358A: `roa375/` (from Bits:30003296;
    see `roa375/RC703_DIV_ROA_DISK.md`).
- Transient working copies during analysis live in `/tmp/rc700dm/` (not kept).

Status legend: **✓analysed** · **✓ref** (byte-verified BIOS reference held) ·
**★lead** (high value, not yet opened) · **·** (out of firmware scope).

---

## Derived knowledge (2026-07-02 analysis pass)

1. **NEW BIOS variant: RC702E rel 1.7** — Bits:30003291 (MT Pascal+ loader disk)
   boots `RC702E 56k CP/M Ver 2.2 Rel 1.7`.  Verified **distinct** from our
   RC702E rel 2.01 and 2.20 references (neither's code appears in it).  An
   *earlier* RC702E than we had.  **DONE:** extracted + reconstructed byte-identical
   (`make rc702e-rel17` / `verify-rc702e-rel17`, 5514/5514); reference
   `rcbios/extracted_bios/cpm22_56k_rc702e_rel1.7_mini.bin`.
2. **RC703 rel 1.1 corroborated on three disks** — Bits:30003294 (source of our
   reference), 30003305 (COMPAS/RcTekst suite), 30003306 (PROMbrænder RC703).
3. **BIOS runtime census** (which system each software disk boots): most RC700
   applications run **RC702 CP/M rel 2.1**; the developer/office suite
   (CIS COBOL, COMPAS-80, DataStar, BDS C, REZ, RcKalk, PROMbrænder) runs
   **RC702E rel 2.20** (the SEM702/RAM-disk variant); RC703 disks run rel 1.1/1.2.
   So RC702E 2.20 and RC702 2.1 were the two dominant shipping runtimes.
4. **RC701 docs are the top open lead** — Bits:30002918 (RC Micro BASIC
   RC701/751, 1979) + Bits:30005728 (RCSL-42-I-1322 RC701/751 brugsanvisning,
   Dec 1979): candidate source for the RC701 I/O port map we lack (ref [8] gap).
5. **6 items are BagIt ZIP bundles** (multi-file collections, not single disks):
   Bits:30003894, 30003899, 30004118, 30005351, 30005769, 30005981 — unzip to a
   `data/` payload before analysis.
6. **No byte-identical duplicates** among the 118 raw/IMD downloads (the endpoint
   serves per-entry representations; even "same disk" entries differ raw-vs-IMD).

---

## A. Firmware — CP/M / BIOS / autoload / PROM / diagnostics

| Bits | Title | Analysed content / runtime | Local |
|------|-------|----------------------------|-------|
| 30003297 | Diverse BIOS typer RC703 | RC703 **rel.TFj** system tracks + 13-module manifest | ✓analysed `rc703-div-bios-typer/` |
| 30003296 | Diverse kildekode assembler RC700 | ROB358/PHE358A src; non-Z80 ROE114/115 | ✓analysed `roa375/RC703_DIV_ROA_DISK.md` |
| 30003294 | ASM assembler+editor RC700 | boots **RC702E 2.20**; carries **RC703 rel.1.1** BIOS (T0.703) | ✓ref (rel.1.1) |
| 30005324 | BDS C 1.50 RC703 | boots **RC702E 2.20** (= our rel2.20 ref source) | ✓ref (RC702E 2.20) |
| 30003295 | BDS C 1.50 RC703 | boots **RC702E 2.20** (raw copy of 30005324's disk) | ✓ (dup content) |
| 30003291 | MT Pascal+ 5.5 loader | **RC702E rel 1.7** BIOS (0x280, after CONFI.COM) | ✓ref + **reconstructed** (rc702e-rel17) |
| 30003293 | RC702 hardware test program | boots RC702; diagnostic disk (≠ testprog PDF) | ★lead (not fully analysed) |
| 30003292 | PROMbrænder software RC700 | boots RC702E 2.20; RC PROM-burner | ★lead |
| 30003306 | PROMbrænder software RC703 | boots **RC703 rel.1.1**; PROM burner | ★lead |
| 30003308 | REZ disassembler RC700 | boots RC702E 2.20; RC disassembler | · tool |
| 30003070 | RC703 56K CP/M rel1.2 | RC703 **rel.1.2** | ✓ref |
| 30004758 / 30005349 | SW1311 RC703 CP/M rel1.2 | RC703 **rel.1.2** | ✓ref |
| 30005959 | SW1311 RC703 CP/M rel1.0 | RC703 **rel.1.0** | ✓ref |
| 30004115 / 30004061 | RC702 CP/M Release 2.0 | RC702 **rel.2.0** | ✓ref |
| 30003271/314/315/09624/003271 | RC702 CP/M rel 2.1 (copies) | RC702 **rel.2.1** | ✓ref |
| 30003272 / 30005763 / 30003944 | RC702 CP/M rel 2.2 / 2.3 | RC702 **rel.2.2 / 2.3** | ✓ref |
| 30005764 | SW1711/I8 RC702 rel 2.x (maxi) | RC702 rel.2.x maxi | ✓ref (2.3 maxi) |
| 30005762 | SW1711 RC702 Release 1.4 | CP/M rel.1.4 (58K line) | ✓ref (58K 1.4) |
| 30005601 | CIS COBOL 4.5 (RC702) | boots **CP/M rel 1.4** | ✓ref? |
| 30005838 | CP/M 58K COMPAS 2.13 | 58K CP/M (compas) | ★lead (58K src) |
| 30007376 | SW7503/2 RC700 CP/M | CP/M 2.2 (SW7503 line) | ★lead |
| 30003901 | CP/M 2.2 + two COMAL80 (RC702) | RC702 rel 2.1 dual-COMAL | · |
| 30003293… | — | — | — |

## RC701 (predecessor — different ports, no semigraphics)

| Bits | Title | Note |
|------|-------|------|
| 30002918 | RC MICRO BASIC RC701/RC751 (1979) | **★★lead** — earliest RC701 doc; candidate RC701 port map |
| 30005728 | RCSL-42-I-1322 RC701/751 brugsanvisning (Dec 1979) | **★★lead** — RC701 user guide (ref [8] candidate) |

## B. Hardware & system documentation (PDFs — download via bits/<num>)

- 30004910 RCSL-42-I-1495 **RC702 Testprogrammer** (✓analysed) ·
  30008786 RCSL-44-RT-2029 **Keyboard RC700/RC850** (★lead — keyboard MCU) ·
  30004692 RC752 Dataskærm (✓used — 230×165mm) · 30004691 RC722 keyboard ·
  30004694 RC763 Winchester · 30004695 + 30004911 RC791 lineselector ·
  30004689 RC702 · 30004690 RC703 · 30000013/14 RC700/RC761 · 30006506/07 printers/RC762 ·
  30004693/30005942 RC761/762 · 30009572 RC700 User Guide (★lead) ·
  30009385 CP/M for RC702 User's Guide 1983 (★lead) · 30005727 install ·
  30003288 Introduction · 30004704/30005919/20/30005936/30003758 overviews ·
  30009068 CP/M reference card · price lists 30005938/30007657/30005937/30004687/30004688/30005717 (·)

## C. Languages & compilers (disks — download via bits/<num>)

- **COMAL:** 30005726 (✓used ID-COMAL rev01.11), 30005768 (r1.17), 30007375 (r1.13),
  30003572 (r1.07), 30003986 (1.08), 30003316/17, 30005765/66, 30003945 (1.1),
  30003985/30003946/30004120/30003318/30009625/30005767 (RcComal80), 30003916 (Metanic), 30003588 (ID-Comal conv)
- **Pascal:** 30005922/30005716/30003066/30003287 (PolyPascal 3.10), 30003270 (COMPAS 3.03),
  30005754/30003073/30005838 (COMPAS 2.20/2.13), 30003291/30004118/30003289 (Pascal/MT+),
  30005674 (InterSystems 3.2), 30005750/51/30003074/30005351/30005769 (UCSD), 30003298 (Turbo 3.01A)
- **C:** 30003295/30005324 (BDS C 1.50 ✓), 30003303/30003304/30005327 (Mix C 2.1)
- **COBOL:** 30005601 (4.5), 30003265/66 (4.4), 30005663 (FORMS-2)
- **BASIC:** 30002918 (RC Micro BASIC RC701/751 — see RC701 leads)

## D. Applications (CP/M — download via bits/<num>)

WordStar 3.0 (30004116/30005748/49), MailMerge 3.0 (30005687/30004069),
DataStar/InfoStar (30003290/30005606/30004117/30003301/02/30005960/30007658),
CalcStar (30005599/30004061), RcKalk (30003309/30004759/30005755/30004041/30003307/30005733),
SuperCalc (30003076/30003307), RcTekst (30003310/11/30004119/30005752),
Skriv (30003323/30003068/69), BOGIKA (30003896), Milestone (30004071),
dBASE II (30003048), SuperSort (30004106), Turn-Key DES (30005981 BagIt),
ACP comms (30004121/30007661), Kermit-80 (30007604), ParFlyt (30005756),
Animator (30005593), FK-SOFT (30003300)

## E. Courseware / education / games (download via bits/<num>, out of firmware scope)

Education: 30003043, 30003261, 30003899(BagIt), 30003900, 30003267/68, 30003903,
30003278, 30003049, 30003064/65, 30003067, 30003906, 30003044/46, 30003312,
30004000, 30003282, 30004004, 30003913, 30003085, 30004005, 30003983/84,
30004303, 30004310, 30004400, 30005686, 30003286, 30003058, 30003042, 30003603,
30003621, 30004335, 30003930, 30003313, 30003088, 30003057, 30004092, 30003931,
30003299, 30003305, 30003894(BagIt).
Games: 30003279, 30003324/25, 30003707 (Pacman), 30003939, 30003053, 30003911.
Misc: 30006263 (Måle&Tælle interface).

---

## Open leads / TODO (priority order)

1. **RC701 ports** — open Bits:30002918 + 30005728 for the RC701 I/O map (unblocks
   any RC701 MAME emulation; ref [8] gap in `reference_rc700_family_proms`).
2. ~~RC702E rel 1.7 — reconstruct~~ **DONE** (byte-identical, `make rc702e-rel17`; ref extracted from Bits:30003291).
3. **RC702 hardware test disk** (Bits:30003293) — analyse (test-PROM code / ports).
4. **Keyboard/peripheral MCU** — Bits:30008786 keyboard description could identify
   the non-Z80 ROE114/115 chip family.
5. **58K / SW7503 CP/M** (Bits:30005838, 30007376) — cross-check the 58K line.
6. **Get Pascal/MT+ running** (later) — CP/M-based, so runnable under RC702 CP/M
   in MAME.  Disks: Bits:30003291 (MT Pascal+ 5.5 loader — also our rel.1.7
   source), 30004118 (SW1720 Pascal/MT+ 5.5, BagIt), 30003289 (Pascal loader
   82.04.30); product sheet Bits:30004761; spec Bits:30005914 (PASCAL/MI+).
7. **UCSD Pascal** (later) — we HAVE it (Bits:30005750 SW1322 RC703 UCSD Pascal,
   30005751 facility, 30003074 UCSD II.0 disk 1, 30005351/30005769 UCSD II.0
   rel1.2 BagIt; doc 30004932).  **NOT CP/M** — it uses the UCSD p-System file
   system (directory shows `PASCALSYSTEM/USERPROG/DEBUGGER/…`), so `cpmtools`
   can't read it; extraction/running needs UCSD p-System tools or the p-System
   interpreter, not the CP/M path.
8. **Graphics-card extension** (even later; user has no hardware) — there was a
   graphics-card extension with a **graphics coprocessor** that merges with the
   8275 CRT output to drive a separate **colour** screen.  Goal: model it in MAME
   and run sample programs.  Evidence/leads already in hand:
   - **Firmware support:** `roa375/rob358.mac` has a conditional **COLOR CRT
     autoload variant** (`COLOR EQU 0 ;SELECT COLOR CRT AUTOLOAD VERSION`,
     `COL EQU 193 ;COLOR ATTRIBUTE`, a "CRT COLOR DESCRIPTION" section).
   - **Candidate programs:** Bits:30003285 "Mikro-Logo … **med grafikkort**",
     30003947 (SW1740 Mikro-Logo 1.0), 30003312 (turtle/skildpadde graphics),
     30003268 (COMAL + Tegngenerator) — investigate which actually drive the
     graphics coprocessor.
   - **Possible coprocessor firmware:** the two 16 KB **non-Z80** ROMs
     `ROE114`/`ROE115` on Bits:30003296 (see `roa375/RC703_DIV_ROA_DISK.md`) — a
     graphics coprocessor has its own CPU, which would explain why they are not
     Z80.  Worth re-examining as the graphics-card firmware once its CPU is known.

## Analysis status

- **Fully analysed:** 30003297, 30003296, 30003294, 30005324, 30005726, 30004910.
- **Runtime-BIOS identified** for ~70 software disks (this pass) — see census above.
- **Byte-verified BIOS references held:** RC702 rel 2.0/2.1/2.2/2.3, RC703
  rel 1.0/1.1/1.2/TFj, RC702E rel 2.01/2.20, 58K rel 1.3/1.4
  (`rcbios/extracted_bios/`).
