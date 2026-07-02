# RC703 BIOS Source — Torben Fjerdingstad, March 1987

## Provenance

This directory contains the **original authored source code** for an RC703
CP/M 2.2 BIOS, extracted from a floppy disk image (`RC703_Div_BIOS_typer.bin`,
raw 800KB, rc703-qd format).

Unlike the reconstructed BIOS sources in `rcbios/src/` (which were
reverse-engineered from disassembly of binary files found on disk images),
these files are **genuine development sources** with original comments,
variable names, algorithm descriptions, and modification history written by
the developers themselves.

**Note:** This is likely a heavily bugfixed personal fork by TFj, diverging
from the RC Computer rel.1.1 baseline in 1983 and evolving independently
through 1987 for his own RC703 setup. It is not an official RC Computer
release. The RC702 releases (rel.2.0–2.3) evolved on a separate track, so
differences between this source and the RC702 reconstruction may go in
either direction — TFj fixes not in the RC702 line, or RC702 improvements
not in TFj's fork.

## History and Authorship

The source has a documented chain of authorship spanning 1982–1987:

| Date | Author(s) | Work |
|------|-----------|------|
| Apr–Oct 1982 | **Karsten Dindorp & Hugo K. Holm** | Original RC700 CP/M basis software |
| Jun 1982 | **SC & VN** | Hard disk corrections |
| Jan 1983 | (unknown) | Release 1.1 baseline (RC702 version, dated 83.01.05) |
| Mar 1983 | **FK & LO** | RC703 corrections |
| Sep 1983 | **LO** | RC763/RC763B Rodime 202 hard disk support; mini DPB fix |
| Mar 1987 | **Torben Fjerdingstad (TFj)** | YD-380 partner drive support, motor timing, QQMM/QQMP/QQPP variants |

The TITLE line reads: `RC703 CP/M BASIS SOFTWARE RELEASE 1.1  83.09.14`

## Relationship to rcbios/src/

The reconstructed sources in `rcbios/src/` are based on disassembly of binary
BIOS images found on CP/M system diskettes. They cover RC702 releases 1.4,
2.0, 2.1, 2.2, 2.3, and 3.0 using conditional assembly (`REL14`, `REL20`,
etc.).

This RC703 source is a **divergent fork** of the same Release 1.1 codebase:

- **Common ancestor**: Release 1.1 (RC702 dated 83.01.05, RC703 dated 83.09.14)
- **RC702 line** evolved into rel.2.0–2.3 and rel.3.0 with conditional assembly
- **RC703 line** added color support, RC763B hard disk, and TFj's partner drive patches

The RC703 source has two features not present in the RC702 releases:
- **Upgrade 9**: Color support (8-color foreground/background via attribute bit tables)
- **Upgrade 10**: RC763B hard disk (Rodime 202) detection and support

Both lines share upgrades 1–8 (16-bit sector numbers, Winchester drives, all
tracks, no alt regs, alt HD config, warm boot from HD, extended unit C, 96 tpi
5.25" floppies).

## Significance

Because this is original source code rather than reconstructed disassembly, it
is authoritative for understanding:

- **Developer intent**: comments describe *why* code exists, not just what it does
- **Algorithm descriptions**: pseudocode-style comments (e.g., the LINSEL line
  selection protocol in `cpmboot.mac`)
- **Hardware register usage**: bit-field explanations for SIO, PIO, FDC, DMA, WD1000
- **Variable semantics**: what each RAM variable actually means
- **Modification history**: who changed what and why (TFj's comments are
  particularly detailed about the HSTBUF overflow bug and partner drive issues)

Comments from this source have been backported into the `rcbios/src/`
reconstructed sources where applicable (shared behavior only, not
RC703-specific features).

## Build Process

The BIOS was built using Microsoft M80 assembler and L80 linker under CP/M:

```
M80 =BIOS703.MAC          ; assemble (BIOS703.MAC includes all modules)
L80 BIOS703/N/E            ; link to produce BIOS5.COM
```

The file `bioslink.703` lists the module dependency order. `BIOS703.MAC` is
the master file that `INCLUDE`s all other `.MAC` files.

## Modules

| File | Size | Purpose |
|------|------|---------|
| `bios703.mac` | 11K | Master file: I/O addresses, RAM layout, EQUs, includes all modules |
| `biostype.mac` | 1K | Single `MINI EQU 0` switch — 5.25" (mini) vs 8" (maxi) disk tables |
| `iniparms.mac` | 7K | Hardware init parameter tables (CTC, SIO, DMA, FDC, Intel 8275 display) |
| `init.mac` | 18K | Hardware initialization, ROM bootstrap, CONFI configuration loading |
| `cpmboot.mac` | 11K | CP/M BIOS jump table, cold/warm boot, LINSEL, EXIT, CLOCK, color |
| `sio.mac` | 8K | Z80-SIO serial driver: printer (Ch.B), punch/reader (Ch.A) |
| `pio.mac` | 2K | Z80-PIO driver: keyboard input (Ch.A, mode 1), parallel output (Ch.B) |
| `qdisplay.mac` | 31K | Intel 8275 display driver: 80×25, escape sequences, scrolling, color, semi-graphics |
| `floppy.mac` | 31K | UPD765 floppy driver: host buffer caching, sector translation, 10-retry recovery |
| `harddsk.mac` | 11K | WD1000 Winchester driver: RC763/RC763B, DMA, seek, format, error logging |
| `qdisktab.mac` | 22K | Disk parameter blocks (DPB), floppy system params (FSP), sector translation tables |
| `inttab.mac` | 1K | Z80 IM2 interrupt vector table (CTC×8, SIO×8, PIO×2) |
| `danishof.mac` | 13K | Danish character conversion tables (output 128 bytes + input 128 bytes) |
| `bioslink.703` | <1K | L80 linker command file listing module order |

## BIOS Variants (TFj, 1987)

The disk contains four BIOS configurations for different drive combinations
on drives C and D (drives A and B are always 5.25" mini):

| File | Drives C,D | Type | Notes |
|------|-----------|------|-------|
| `bios5.com` | (base build) | Binary | Standard BIOS as assembled |
| `qqmm.pch` | C=maxi, D=maxi | Binary patch | Applied with ZAP to BIOS5.COM |
| `qqmp.pch` | C=maxi, D=partner | Binary patch | Applied with ZAP to BIOS5.COM |
| `qqpp.sce` | C=partner, D=partner | Source patch | Applied to .MAC sources before assembly |

**Partner drives** are YD-380 floppy drives (128 sectors/track, 1.2MB capacity)
that replaced hard disk support. TFj's readme.doc notes: "Denne udgave er
ændret så der ikke kan tilsluttes harddisk, men istedet to YD-380
floppydrives (drive C og D)" — This version is modified so hard disk cannot
be attached, but instead two YD-380 floppy drives (drives C and D).

The naming convention: Q=Quad (5.25"), M=Maxi (8"), P=Partner. So QQMP means
A=Quad, B=Quad, C=Maxi, D=Partner.

### Workflow (from readme.doc)

From TFj's readme.doc (translated from Danish):

> With the help of TRACKSYS, drives C and D can be two physical floppy
> drives, two 8" drives, two partner drives, or one of each. (Partner
> drives can also run 8" format.) The following BIOSes can be written
> to Track 0:
>
> | Drives A,B / C,D | File | Method |
> |-------------------|------|--------|
> | mini, C,D = maxi | QQMM.PCH | patched |
> | mini, C = maxi, D = partner | QQMP.PCH | patched |
> | mini, C,D = partner drives | QQPP.SCE | edited in source |
> | Standard BIOS with changed step rate | BIOS703.TFJ | edited in cpmboot.mac |
>
> Unfortunately the programs CONFI and SYSGEN do not work.

Because CONFI and SYSGEN could not handle these modified BIOSes, TFj used
`tracksys.com` as the mechanism to install them. TRACKSYS reads or writes
the system tracks (Track 0 or 1) to/from files, bypassing SYSGEN entirely.
The `.PCH` patch files were applied to `BIOS5.COM` using the `ZAP` binary
editor (also on the disk), with patch addresses calculated as `Adr - D380H`
(the BIOS load address offset).

### Known Issues (documented by TFj)

- **CONFI and SYSGEN do not work** with these modified BIOS versions
- **QQMP had an HSTBUF overflow bug**: the 512-byte host buffer overwrote
  directory check vectors, causing drives to be set read-only after partner
  drive access. Fixed by expanding HSTBUF to 1024 bytes (moved from EE81H
  to EC81H).
- **QQMP still had insufficient space** for CHK2/ALV2 vectors, which caused
  persistent R/O status on drive C. This led to creating QQPP.SCE as a
  source-level fix instead.

## Other Files on the Disk

| File | Size | Purpose |
|------|------|---------|
| `autoexec.com` | 1K | RC700/RC703/RC855 auto-execute installer (writes command to Track 0) |
| `tracksys.com` | 2K | Read/write system tracks (Track 0/1) to/from files |
| `copifil.asm` | 7K | CP/M file copy utility source (Danish, by Peter Heinrich, Mar 1985) |
| `format.com` | 2K | Disk format utility |
| `eraq.com` | 2K | ERA with query (delete with confirmation) |
| `bdos-ccp.com` | 6K | CP/M 2.2 BDOS and CCP binary |
| `m80.com` | 19K | Microsoft M80 macro assembler |
| `l80.com` | 9K | Microsoft L80 linker |
| `pip.com` | 7K | CP/M PIP (Peripheral Interchange Program) |
| `stat.com` | 5K | CP/M STAT utility |
| `zap.com` | 16K | Binary/disk sector editor |
| `zsid.com` | 10K | Z80 Symbolic Instruction Debugger |
| `ws.com` | 31K | WordStar word processor |
| `wsd.com` | 16K | WordStar dictionary |
| `wsmsgs.ovr` | 28K | WordStar messages overlay |
| `wsovly1.ovr` | 34K | WordStar overlay 1 |

## Extraction

Extracted 2026-04-10 from `RC703_Div_BIOS_typer.bin` using:

```bash
cpmcp -f rc703-qd RC703_Div_BIOS_typer.bin '0:*.*' rc703-div-bios-typer/
```

Trailing CP/M Ctrl-Z (0x1A) EOF characters stripped from all text files.

That `cpmcp` step only copies the **filesystem** (user-0 files, 36 files).  It
does NOT copy the CP/M **system/boot tracks** (`boottrk 4` in the `rc703-qd`
diskdef → tracks 0-3 = 4 × 10 × 512 = 20480 B), which hold the *assembled,
runnable* system.  Those are preserved separately (2026-07-02):

## System tracks — the assembled, runnable TFj build (`RC703_Div_BIOS_typer.systemtracks.bin`)

The first 4 tracks of the raw image (`RC703_Div_BIOS_typer.systemtracks.bin`,
20480 B, sha256 `fb3fabc2…`) contain the bootstrap + BDOS/CCP + the fully
assembled BIOS as it actually ran on this disk.  Findings from analysing it
(source: datamuseum.dk Bits:30003297):

- **Assembled signon = `RC703  56k CP/M vers. 2.2  rel. TFj`** (track 0,
  sector 3).  The source TITLE line says `RELEASE 1.1  83.09.14`, but the
  *binary* is self-labelled **`rel. TFj`** — hard evidence that the running
  system is Torben Fjerdingstad's personal build, not an official RC release.
- **Embedded BIOS build manifest** (`BIOS BESTÅR AF:`, track 3 sector 2) lists
  the constituent modules in link order — the definitive 13-module set:
  `BIOS703 · BIOSTYPE · INIPARMS · DANISHOF · INIT · CPMBOOT · SIO · QDISPLAY ·
  FLOPPY · HARDDSK · QDISKTAB · INTTAB · PIO` (all present as source above).
- Runtime strings not obvious from the sources: `Waiting`,
  **`Cannot read configuration record.`** (the BIOS reads a config record),
  `Wrong CP/M Version (Requires 2.0)`, and a STAT-style capacity table
  (`128 Byte Record Capacity / Kilobyte Drive Capacity`).
- **RC763 references** in the boot area — this build includes the RC763/RC763B
  hard-disk support (matches HARDDSK.MAC + LO's Rodime-202 work in the history).

Use: a **byte-level golden reference** for validating the rcbios reconstruction
(boot flow, load addresses, BIOS binary) — an oracle we did not have from the
source files alone.  Re-extract: `dd if=RC703_Div_BIOS_typer.bin of=- bs=512
count=40`.

## Hardware Summary

The BIOS supports the following RC703 hardware:

- **CPU**: Z80-A at 4 MHz
- **PIO** (ports 10H–13H): Channel A = keyboard input (mode 1, interrupt-driven), Channel B = parallel output (mode 0)
- **CTC** (ports 0CH–0FH): Ch.0/1 = SIO baud rate, Ch.2 = display interrupt, Ch.3 = floppy interrupt
- **CTC2** (ports 44H–47H): Ch.0 = WD1000 hard disk interrupt, Ch.1–3 = unused
- **SIO** (ports 08H–0BH): Channel A = punch/reader, Channel B = printer/terminal
- **DMA** (ports F0H–FFH): AM9517A — Ch.0 = WD1000, Ch.1 = floppy, Ch.2 = display refresh
- **FDC** (ports 04H–05H): UPD765 floppy disk controller
- **Display** (ports 00H–01H): Intel 8275 CRT controller, 80×25 characters at F800H
- **Hard disk** (ports 60H–67H): WD1000 Winchester controller (RC763/RC763B)
- **Bell** (port 1CH), **Switch register** (port 14H: bit 7 = mini/maxi detect, bit 0 = motor)
- **RC791 line selector**: External RS-232 A/B switch controlled via SIO DTR/RTS signaling

Machine type byte (MTYPE) at fixed BIOS offset: 0=RC700, 1=RC850, 2=ITT3290, 3=RC703.

## Memory Map (56K system)

```
0000H–0004H    CP/M vectors (warm boot JP, IOBYTE, CDISK)
0005H          BDOS entry
0080H          Default DMA buffer (BUFF, 128 bytes)
0100H          TPA start
C400H          CCP (Console Command Processor)
CC06H          BDOS
D480H          START — INIT code + configuration tables
DA00H          BIOS jump table
EC81H          HSTBUF — host disk buffer (1024 bytes, TFj expanded from 512)
F081H          DIRBF — directory scratch (128 bytes)
F101H          Allocation/check vectors (floppy drives 0–1, then drives 2–3)
F500H          BGSTAR — semi-graphics/color bit table (250 bytes)
F620H          ISTACK — interrupt stack
F680H          OUTCON — output character conversion table (128 bytes)
F700H          INCONV — input character conversion table (128 bytes)
F800H          DSPSTR — display refresh memory (80×25 = 2000 bytes + attributes)
FFD1H          Display control variables (cursor, XY addressing, counters)
FFFCH          RTC0–RTC3 — real-time clock (4 bytes, 50 Hz tick)
```
