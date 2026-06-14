# RC702 Hardware Technical Reference
## For SYSGEN and Autoload ROM Development

This document provides comprehensive technical information about the RC702 hardware architecture, specifically focused on aspects relevant to the SYSGEN utility and ROA375 autoload ROM development.

**Document Version:** 1.3
**Date:** 2026-02-21
**Sources:** Analysis of jbox.dk RC702 documentation, ROB358.MAC, SYSGEN.ASM, and CP/M for RC702 User's Guide (RCSL No 42-i2190)

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Memory Architecture](#memory-architecture)
3. [I/O Port Map](#io-port-map)
4. [Floppy Disk Format Specifications](#floppy-disk-format-specifications)
5. [Boot and Initialization Sequence](#boot-and-initialization-sequence)
6. [Hardware Controllers](#hardware-controllers)
   - [Display Control Character Protocol](#display-control-character-protocol)
   - [Keyboard](#keyboard)
   - [Serial Port Assignments](#serial-port-assignments)
   - [Peripheral Handshake](#peripheral-handshake)
7. [Multi-Density Disk Support](#multi-density-disk-support)
8. [RC-Specific CP/M Utilities](#rc-specific-cpm-utilities)
9. [RC763 Hard Disk System](#rc763-hard-disk-system)
10. [System Diskette Generation](#system-diskette-generation-appendix-c)
11. [Line Editing and Boot Keys](#line-editing-and-boot-keys)
12. [RC700 Emulator](#rc700-emulator)
13. [RC702E Variant — Memory Disk and SEM702 Character Generator](#rc702e-variant--memory-disk-and-sem702-character-generator)

---

## System Overview

### Core Components

- **Mainboard:** PCB527
- **CPU:** Zilog Z80-A running at 4 MHz
- **RAM:** 64KB (0x0000-0xFFFF in normal operation)
- **ROM:** 2KB boot loader (ROA375) with software-controlled mapping
- **Display:** 80x24 character text display at memory address 0x7800

### I/O Controllers

1. **Zilog Z80A-SIO/2** (Z8442) - Serial I/O controller (async + SDLC/HDLC sync)
2. **Zilog Z80-PIO** (Z8420) - Parallel I/O controller
3. **Zilog Z80-CTC** - Counter and Timer Controller (2 units)
4. **Intel 8237A-5** (P8237-5) - DMA Controller
5. **NEC uPD765** (or Intel 8272) - Floppy Disk Controller
6. **Intel 8275** - Programmable CRT Controller
7. **Intel 8202A** (D8202A) - Dynamic RAM Controller
8. **Western Digital WDC1002** - Winchester Disk Controller (optional)

### Physical Board Identification (user's unit, 2026-04-18)

- Mainboard silkscreen: **PCB530**. Not documented in either RC702
  technical manual (both refer to PCB527 designations for MIC702).
  User's assessment: "strongly suspect it is a MIC702" — behaviour
  and chip count are consistent with the MIC702 baseline, so treat
  as MIC702 until proven otherwise.
- Corollary: synchronous-serial features (OUT 1Eh flip-flop, modem
  clock on J1, DB-25 pins 15/17) are **not** expected to be present.
  PCB530 is likely a minor revision of PCB527 rather than a jump to
  MIC704/705.
- Note: RC702tech.pdf printed page 83 has a "MIC 702 — PHASE LOCK
  LOOP — MIC 14" schematic, but that's the **video dot-clock PLL**
  (locks 11.64 MHz dot clock to 50 Hz VRTC), not a serial DPLL. It
  does not help with SDLC clock recovery on the SIO.

### Chip Markings (from physical inspection, 2026-04-18)

| Chip | Marking | Identification |
|------|---------|---------------|
| CPU | Z8400A P5 | Zilog Z80A CPU, 4 MHz |
| SIO | Z8442AB1 | Zilog Z80A-SIO/2, bonding option 2 |
| PIO | 8420Y | Zilog Z80-PIO |
| DMA | P8237-5, I1250078 | Intel 8237A-5, 5 MHz DMA controller |
| DRAM ctrl (chip 37) | Intel D8202A, S454 Y1390009 | Intel 8202A DRAM controller |

### Mainboard Connectors (PCB527)

| Connector | Function | Notes |
|-----------|----------|-------|
| J1 | Serial port (SIO Channel A) | V.24/RS-232, terminal/modem — DB-25 DTE, pinout below |
| J2 | Serial port (SIO Channel B) | V.24/RS-232, printer — DB-25 DTE, pinout below |
| J3 | Parallel port | PIO-based |
| J4 | Parallel port | PIO-based |
| J9 | External floppy | Connector for external floppy drive(s) |
| J8 | Z80 bus expansion | Full Z80 bus; used for HD interface board (CTC2) |

(J5-J7, J10+ designations: TBD — check technical manual for keyboard,
floppy, power, display connectors.)

#### J1 / J2 DB-25 Pinout (SIO-A / SIO-B)

From RC702-RC703 technical manual, Figure 13 (page 23–24). Both ports
are standard V.24 DTE; only the signals listed below are wired — pins
15 (TxC DCE→DTE) and 17 (RxC DCE→DTE) are **not connected** on the
MIC702/MIC703 motherboards.

| Pin | Signal | Direction | Notes |
|-----|--------|-----------|-------|
| 1 | Protective Ground | — | Chassis |
| 2 | TxD (Transmit Data) | Out | SIO TxDA/TxDB |
| 3 | RxD (Receive Data) | In | SIO RxDA/RxDB |
| 4 | RTS (Request To Send) | Out | SIO RTS output |
| 5 | CTS (Clear To Send) | In | SIO CTS input |
| 7 | Signal Ground | — | |
| 8 | DCD (Data Carrier Detect) | In | SIO DCD input |
| 20 | DTR (Data Terminal Ready) | Out | SIO DTR output |
| 15 | (would be TxC from DCE) | — | **NC on MIC702/MIC703** |
| 17 | (would be RxC from DCE) | — | **NC on MIC702/MIC703** |

**Implication for synchronous modes:** the stock RC702 cabinet
(MIC702/MIC703) cannot accept an external bit clock because no clock
pin is brought out to the DB-25. The Z80-SIO/2 chip itself supports
SDLC/HDLC, but it has no on-chip DPLL, so its receiver cannot recover
a clock from RxD data.

Per page 22 of the same manual: synchronous operation is a
**MIC704/MIC705** feature, not MIC702/MIC703. On those boards:

- Port `IC hex` reads BIT 0/1/2/3 = Calling Indicator A / Data Set
  Ready A / Calling Indicator B / Data Set Ready B.
- `OUT (1E hex), A` with bit 1=1 sets a flip-flop that routes the
  **modem-supplied clock** into SIO channel A. Bit 1=0 resets.

So on MIC702/MIC703, synchronous TX from the RC702 is possible
(SIO clocked from CTC internally, output stream is SDLC-framed), but
synchronous RX from an external source is not — the SIO would be
sampling at its own CTC rate with no phase alignment to the incoming
bit stream, and the chip has no DPLL to fix that.

### Mainboard Variants (MIC boards)

| Board | Machine | RAM | PROM0 | PROM control |
|-------|---------|-----|-------|-------------|
| MIC702 | RC702 | 48KB | ROA375 | OUT (18H): disable both PROMs |
| MIC703 | RC702 | 64KB | ROA375/ROB358 | OUT (19H): disable both PROMs |
| MIC704 | RC702 | 64KB | ROB237 | OUT (18H): enable both PROMs |
| MIC705 | RC703 | 64KB | ROB357 | OUT (1AH): flip-flop (disable PROM0, enable PROM1) |

Note: MIC702 and MIC703 have incomplete address decoding — all four
RAMEN ports (0x18-0x1B) behave identically.

### Configuration

- 8 DIP configuration switches
- Support for 1 or 2 5.25" floppy disk drives
- Optional 10MB Winchester hard disk
- Speaker for audible feedback

---

## Memory Architecture

### ROM Mapping

The RC702 supports two PROMs (see hardware manual page 17): PROM0 at 0x0000 (ROA375 autoload PROM) and an optional PROM1 at 0x2000 (line program ROM). Both are mapped into the Z80's address space at power-on. Writing any value to port 0x18 (RAMEN) disables both PROM mappings, allowing the full 64KB RAM to be linearly accessible.

The PCB schematic (see `docs/PROM_SCHEMATICS.PNG`) shows a solder bridge option that connects address line A11 to the PROM sockets. When open (factory default), A11 is tied low, limiting PROMs to 2KB (2716-type). When closed, A11 is active, enabling 4KB PROMs (2732-type).

**Confirmed from test program documentation:** The RC702 test system comes in two PROM versions:
- **PROM system 1 (2×2KB)**: ROB361 in PROM0 + ROB362 in PROM1. For MIC702 and MIC703.
- **PROM system 2 (1×4KB)**: ROB363 in PROM0 only. For MIC703 with print modification, and MIC704.

The 4KB option requires a print board modification that is NOT applicable to standard MIC702 boards. **The 2KB-per-socket limit is hard for RC702 (MIC702).** The autoload PROM (ROA375) uses only PROM0 (2KB).

### Memory Layout During Boot

```
0x0000-0x07FF   PROM0: 2KB Boot ROM (ROA375) - disabled by OUT to RAMEN
0x2000-0x27FF   PROM1: Optional 2KB line program ROM - disabled by OUT to RAMEN
0x0000-0xFFFF   64KB RAM (fully accessible after PROMs disabled)
0x7800-0x7FFF   CRT display buffer (2K, 80x24 characters)
0xA000-0xBFFF   Bootstrap code copied from ROM
0xB000-0xB0FF   Working area for boot process
0xBFFF          Initial stack pointer during ROM boot
```

### Working Memory Areas (Boot Time)

```
0xB000  TRK        - Track count for ID COMAL
0xB003  RSTAB      - Floppy save status area
0xB00D  ERFLAG     - Hard disk error flag
0xB00E  SECTOR     - Hard disk sector read count
0xB00F  MEMADR     - Memory address pointer (DMA)
0xB011  REPTIM     - Repeat operation indicator
0xB020  DSPSTR     - Display memory buffer
```

---

## I/O Port Map

### Z80 PIO (Parallel I/O)

```
0x10  KEYDAT     - Keyboard data port (Port A)
0x12  KEYCON     - Keyboard control port (Port A)
```

**PIO Programming Values:**
- `0x4F` - PIO mode = INPUT
- `0x02` - PIO interrupt vector
- `0x87` - Enable interrupts
- `0x07` - Disable interrupts

### Z80 CTC (Counter/Timer Controller)

```
0x0C  CTCCH0     - Channel 0 (not used during bootstrap)
0x0D  CTCCH1     - Channel 1 (not used during bootstrap)
0x0E  CTCCH2     - Channel 2 (Display interrupt input)
0x0F  CTCCH3     - Channel 3 (Floppy controller interrupt)
```

**CTC Clock Sources:**
- **Ch 0, Ch 1 (TRG0/TRG1):** 0.6144 MHz baud rate clock, derived from the
  19.6608 MHz memory clock by two cascaded 74LS393 dividers (÷2 → 9.8304 MHz,
  then ÷16 → 0.6144 MHz; ÷32 total). See RC702tech.pdf page 89 (labelled 85).
  These two channels generate SIO-A and SIO-B baud rate clocks respectively.
  Each CTC channel output drives **both** the TX and RX clock inputs of its
  SIO channel (single wire to TxC+RxC on the SIO pin). This means TX and RX
  on the same SIO channel always run at the same baud rate -- split TX/RX
  speeds are not possible without hardware modification.
  The same 0.6144 MHz signal also drives the keyboard beep duration timer.
- **Ch 2 (TRG2):** 8275 CRT controller VRTC (vertical retrace) interrupt.
- **Ch 3 (TRG3):** µPD765 FDC INTRQ (floppy interrupt).

**Baud rate formula:** `baud = 614400 / (CTC_divisor × SIO_clock_mode)`

With SIO ×16 mode, maximum baud rate = 614400 / (1 × 16) = **38400 baud**.
SIO ×1 mode is not viable for async (no oversampling for bit-center sampling).

A hardware modification to tap the ÷16 output instead of ÷32 (one wire change
on the 74LS393 chain) would double the clock to 1.2288 MHz, giving 76800 max,
but would also require doubling all CONFI baud rate divisors and would change
the beep pitch.

**CTC Programming Values:**
- `0x10` - CTC interrupt vector base (Display=0x14, Floppy=0x16)
- `0xD7` - Mode = interrupt after one count
- `0x01` - Count = 1
- `0x03` - Reset channel command

### Z80 CTC2 (Second Counter/Timer for Hard Disk — External)

The CTC2 is **not on the RC702 motherboard**.  It resides on the external
hard disk interface board, connected via the Z80 bus expansion connector
on the motherboard.  The full Z80 bus is exposed on this connector, and
the hard disk enclosure contains additional circuitry including this CTC.
Systems without a hard disk have no CTC2; writes to ports 0x44-0x47 are
ignored.

```
0x44  CT2CH0     - Channel 0 (WD1000 hard disk interrupt)
0x45  CT2CH1     - Channel 1 (not used)
0x46  CT2CH2     - Channel 2 (not used)
0x47  CT2CH3     - Channel 3 (not used)
```

**CTC2 Programming Values:**
- `0x08` - Interrupt vector for WD1000

### Intel 8275 CRT Controller

```
0x00  CRTDAT     - CRT data register
0x01  CRTCOM     - CRT control/command register
```

**CRT Commands:**
- `0x00` - Reset CRT controller
- `0x80` - Load cursor command
- `0xA0` - Enable interrupt
- `0xE0` - Preset counters command
- `0x23` - Start display

**CRT Parameters:**
- `0x4F` - 80 characters/row, normal rows
- `0x98` - 25 rows per frame
- `0x7A` - Underline position 8-10, characters per line
- `0x4D` - Cursor format: block, blink, reverse video

### AMD Am9517A / Intel 8237 DMA Controller

```
0xF0  CH0ADR     - Channel 0 address register (WD1000 hard disk)
0xF1  WCREG0     - Channel 0 word count register
0xF2  CH1ADR     - Channel 1 address register (Floppy disk)
0xF3  WCREG1     - Channel 1 word count register
0xF4  CH2ADR     - Channel 2 address register (Display)
0xF5  WCREG2     - Channel 2 word count register
0xF8  DMACOM     - DMA command register
0xFA  SMSK       - Single mask register
0xFB  DMAMOD     - DMA mode register
0xFC  CLBP       - Clear byte counter register
0xFF  FULMSK     - Full mask register
```

**DMA Channel Assignments:**
- Channel 0: External debugger / J8 expansion (HD controller, MEM700)
- Channel 1: NEC uPD765 floppy disk controller
- Channel 2: Intel 8275 display controller (primary, services from base address until TC)
- Channel 3: Intel 8275 display controller (second DMA channel — *roll function* for hardware-assisted vertical scroll; takes over from ch2 after ch2 hits TC.  Currently unused by all firmware: ch2 covers the full 2000 bytes/frame and ch3 never receives a DRQ.  See `docs/dma_ch3_8275_roll_function.md` for the MIC 11 schematic trace.)

**DMA Programming Values:**
- `0x20` - Command value (standard configuration)
- `0x44` - Mode 0: Transfer disk to memory, CH0
- `0x45` - Mode 1: Transfer disk to memory, CH1
- `0x5A` - Mode 2: Transfer memory to display, CH2 (auto-initialize)
- `0x0F` - Set all DMA channel mask bits
- `0x00` - Clear CH0 mask bit
- `0x01` - Clear CH1 mask bit
- `0x02` - Clear CH2 mask bit
- `0x04` - Set CH0 mask bit
- `0x05` - Set CH1 mask bit

### System Control Ports

RC702 uses incomplete address decoding — ports are mirrored in groups of 4.
The RC703 (later model) likely refines this; rob358.mac uses 0x19 for RAMEN.

```
0x14-0x17  SW1    - Read: Mini/Maxi switch (bit 7). Write: mini floppy motor (1=start, 0=stop)
0x18-0x1B  RAMEN  - PROM disable: any write disables PROM0+PROM1 mappings, enables full RAM
0x1C-0x1F  BIB    - Beeper/speaker output (any write triggers beep)
```

### SEM702 Character Generator (RC702E variant only)

```
0xD1  CHARLN   - Character number (0-127)
0xD2  DOTLN    - Dot line number (0-15)
0xD3  CHARDA   - Character RAM data (8 bits per dot line)
```

Source: PHE358A.MAC. See [RC702E Variant](#rc702e-variant--memory-disk-and-sem702-character-generator).

### Memory Disk (RC702E variant only)

```
0xEE  MDTRK/MDST - Write: track register. Read: status register
0xEF  MDSEC      - Write: sector register (starts DMA transfer)
```

Source: PHE358A.MAC. See [RC702E Variant](#rc702e-variant--memory-disk-and-sem702-character-generator).

---

## Floppy Disk Format Specifications

The RC702 uses a sophisticated multi-density disk format to maintain backward compatibility while maximizing storage capacity. The system uses the NEC uPD765 (or Intel 8272) floppy disk controller, which supports both FM (single density) and MFM (double density) encoding.

### 5.25" Floppy Disk Format (Standard CP/M Format)

This is the primary format used for CP/M operation on the RC702 system with maxi floppy (standard 5.25" double-sided) drives.

#### Track 0 - Special Mixed-Density Format

**Track 0, Side 0** (Single Density FM):
- Encoding: FM (Frequency Modulation)
- Sectors per track: 16
- Bytes per sector: 128
- Total capacity: 2,048 bytes (2KB)
- Physical sector numbers: 0-15

**Track 0, Side 1** (Double Density MFM):
- Encoding: MFM (Modified Frequency Modulation)
- Sectors per track: 16
- Bytes per sector: 256
- Total capacity: 4,096 bytes (4KB)
- Physical sector numbers: 0-15

**Track 0 Total:** 6,144 bytes (6KB)

#### Tracks 1-35 - Standard Double Density

**All remaining tracks, both sides:**
- Encoding: MFM (Modified Frequency Modulation)
- Sectors per track: 9
- Bytes per sector: 512
- Sector interleave: 2:1
- Physical sector order: 0, 2, 4, 6, 8, 1, 3, 5, 7

**Total data tracks:** 35 tracks × 2 sides × 9 sectors × 512 bytes = 322,560 bytes (315 KB)

**Total disk capacity:** 328,704 bytes (321 KB) — 6,144 B (Track 0) + 322,560 B (Tracks 1–35)

#### Reference image: `RC702_TEST_v1.2.bin`

The above mini-floppy layout is corroborated byte-exact by the **RC700 TESTSYSTEM v1.2**
diagnostic diskette preserved at the Dansk Datamuseum:

- Source: <https://datamuseum.dk/wiki/Bits:30003293>
- Description (original DA): *"Boot-diskette, som derefter kører en test af en RC702 Piccolo"*
- Geometry as recorded by datamuseum.dk (matches the three-region layout above):
  - `1c 1h 16s 128b`  → Track 0 Side 0 (2,048 B, FM)
  - `1c 1h 16s 256b`  → Track 0 Side 1 (4,096 B, MFM)
  - `35c 2h 9s 512b`  → Tracks 1–35, both sides (322,560 B, MFM)
- File size: 328,704 B exactly (2,048 + 4,096 + 322,560).
- Raw image starts with the autoload PROM boot header: bytes `80 02 00 … " RC702"`
  i.e. load length `0x0280` (= 640 B = 5 × 128-byte sectors of boot code), matching
  the format the ROA375 PROM reads from Track 0 Side 0.
- Tail of the data area is filled with `0xE5` (CP/M "formatted but unused" fill),
  confirming the diskette was standard-formatted and the test program leaves most
  of the disk empty.
- Embedded strings reveal the test suites: MEM refresh, DMA ch 0/1, CTC, FDC, FDD
  reliability (SD/DD, SS/DS, mini/maxi/quad, configurable steprate/retries), SIO,
  PIO, WDC (RC763/RC763B winchester) and WDD reliability.
- Interactive menu: `"RC700 TESTSYSTEM"`, keys `H R L G S P <esc>` and hex `0-F`.

**Not a CP/M diskette.** The image only *looks* bootable to the PROM; it is a
custom linear-image loader, not CP/M:

- Track 1 side 0 (offset `0x1800`) holds raw Z80 init code
  (`AF 32 FF FF F3 D3 01 ED 7B FF FF D3 FD 3E 18 D3 0A D3 0B 3E 03 D3 0C-0F ED 5E …`)
  — CTC bring-up and `IM 2`, i.e. a continuation of the test program. There is
  no CCP (`C3 …` cold-boot jump) and no 3.5 KB BDOS following it.
- Track 2 side 0 (offset `0x3C00`) is more executable code, not 32-byte
  directory entries; there are no `0xE5` erased slots and no uppercase-ASCII
  filename patterns in this region.
- The strings `**NO SYSTEM FILES**`, `**NO KATALOG**`, `SYSM SYSC` visible in
  the image are baked-in error messages lifted from the standard autoload PROM,
  not live CP/M directory contents.

So the PROM treats Track 0 Side 0 as its usual 640-byte bootstrap
(`80 02 … " RC702"` header, 5 × 128 B sectors of boot code); that bootstrap
is a bare-metal loader that reads the rest of the disk linearly into RAM and
jumps into it. No BDOS, no CCP, no CP/M directory on this disk.

### CP/M Logical Structure

From CP/M for RC702 User's Guide, Appendix E:

**5.25" Mini System Diskette:**
- **Block size:** 2,048 bytes (2 KB)
- **Directory entries:** 128
- **Reserved cylinders:** 2 (Track 0 + Track 1)
- **Drive capacity:** 270 KB in 2 KB blocks
- **Sector interleave:** 2:1, zero track-to-track skew
- **Recommended media:** Verbatim MD550-01-1818E

**8" Maxi System Diskette:**
- **Block size:** 2,048 bytes (2 KB)
- **Directory entries:** 128
- **Reserved cylinders:** 2
- **Drive capacity:** 900 KB in 2 KB blocks
- **Sector interleave:** 4:1, zero track-to-track skew
- **Recommended media:** 3M 743-0-512

**8" Data Diskette (Standard Exchange Format):**
- SS/SD, 128 bytes/sector, 26 sectors/track, 77 cylinders
- **Block size:** 1 KB
- **Directory entries:** 64
- **Reserved tracks:** 2
- **Drive capacity:** 241 KB
- **Sector interleave:** 6:1, zero track-to-track skew
- **Recommended media:** 3M-740/2-0

The data diskette exchange format uses single-sided single-density for
maximum compatibility with other CP/M systems.

### 8" Floppy Disk Formats

The RC702 also supports 8" floppy diskettes in two formats:

#### Type 1: Single-Sided Single-Density (SS/SD)

- Sides: 1 (single-sided)
- Tracks: 77
- Encoding: FM (single density)
- Sectors per track: 26
- Bytes per sector: 128
- Total capacity: ~247KB

#### Type 2: Double-Sided Double-Density (DS/DD)

**Track 0 - Special Format:**
- Track 0, Side 0: 26 sectors × 128 bytes (FM encoding)
- Track 0, Side 1: 26 sectors × 256 bytes (MFM encoding)

**Tracks 1-77 - Standard Format:**
- Both sides: 15 sectors × 512 bytes (MFM encoding)

**Total capacity:** ~1.2MB

### Alternative RC Format (Non-CP/M)

Some specialty RC702 disks use an alternative format:

- Encoding: FM (single density)
- Sides: 2 (double-sided)
- Tracks per side: 35
- Sectors per track: 16
- Bytes per sector: 128
- Total capacity: ~140KB

This format was used for certain RC-specific software but the file system structure has not been fully documented.

---

## Boot and Initialization Sequence

The RC702 boot process is a multi-stage operation that carefully initializes all hardware components and loads the operating system from floppy disk.

### Stage 1: ROM Bootstrap (Executes at 0x0000)

1. **CPU Reset Vector (0x0000)**
   - Disable interrupts (`DI`)
   - Set stack pointer to 0xBFFF

2. **Self-Relocation**
   - Locate boot code (scan for first non-zero byte after 0x0068)
   - Copy boot loader from ROM (0x0069) to RAM (0x7000)
   - Size: 0x0798 bytes
   - Jump to entry point at 0x70D0

### Stage 2: RAM-Based Initialization (Executes at 0x7000)

#### Interrupt Vector Setup (0x7300)

The bootstrap establishes an interrupt vector table using Z80 Mode 2 interrupts:

```
0x7300  INT0    - Dummy interrupt
0x7302  INT1    - PIO Keyboard interrupt
0x7304  INT2    - Dummy interrupt
0x7306  INT3    - Dummy interrupt
0x7308  INT4    - CTC2 WD1000 hard disk interrupt
0x730A  INT5    - Dummy interrupt
0x730C  INT6    - CRT display interrupt
0x730E  INT7    - FDC floppy disk interrupt
```

#### Hardware Initialization Order

1. **Z80 PIO - Keyboard Interface**
   - Set keyboard interrupt vector
   - Configure Port A as input
   - Enable keyboard interrupts
   - Read PIO data port to clear any pending data

2. **AMD 9517 DMA Controller**
   - Set command options (0x20)
   - Configure Channel 0: WD1000 disk-to-memory transfer
   - Configure Channel 1: Floppy disk-to-memory transfer
   - Configure Channel 2: Memory-to-CRT transfer (auto-initialize mode)
   - Set all channel mask bits (disable all channels initially)

3. **Z80 CTC - Counter/Timer Controller**
   - Set interrupt vector base (0x10)
   - Reset channels 0 and 1
   - Configure Channel 2 for display interrupts (mode 0xD7, count 1)
   - Configure Channel 3 for floppy interrupts (mode 0xD7, count 1)

4. **Z80 CTC2 - Hard Disk Controller Timer**
   - Set interrupt vector (0x08)
   - Configure Channel 0 for WD1000 interrupts
   - Reset channels 1, 2, and 3

5. **Display Buffer Initialization**
   - Initialize display buffer at 0xB020 (DSPSTR)
   - Fill 2,000 bytes with space characters (0x20)
   - Copy "RC700" prompt and color attributes to buffer

6. **Intel 8275 CRT Controller**
   - Reset controller
   - Set parameters:
     - 80 characters per row
     - 25 rows per frame
     - Underline position and character height
     - Cursor format (block, blink, reverse video)
   - Load cursor position (0,0)
   - Preset counters
   - Configure DMA Channel 2 for display refresh
     - Set base address to display buffer (0xB020)
     - Set word count to 0x07CF (2,000 characters)
   - Enable display and show "RC700" prompt

### Stage 3: Boot Device Selection

The system attempts to boot from devices in the following priority order:

1. **Hard Disk Boot (WD1000)**
   - Initialize hard disk controller
   - Issue restore command
   - Wait for ready signal or timeout
   - Check DIP switch bit 7 for forced floppy boot
   - If hard disk fails or timeout, fall through to floppy boot

2. **Floppy Disk Boot**
   - Check DIP switch bit 7 to determine disk size (5.25" vs 8")
   - For 5.25" drives:
     - Read 0x0800 bytes (2KB) from Track 0, Side 0 to RAM address 0x0000
     - Read 0x1000 bytes (4KB) from Track 0, Side 1 to RAM address 0x0800
   - For 8" drives:
     - Read appropriate track 0 data based on format

3. **Disable PROM Mapping**
   - Write to port 0x18 (RAMEN) to disable PROM0 and PROM1
   - This frees 0x0000-0x07FF (and 0x2000-0x27FF if PROM1 installed) for RAM use

4. **Transfer Control to Operating System**
   - Jump to bootstrap entry point at address 0x0000
   - The loaded code takes over and continues CP/M bootstrap

### DIP Switch Configuration

**Bit 7:** Disk size selection
- 0 = 8" floppy drives
- 1 = 5.25" floppy drives

Other switch settings control various hardware options but are not documented in available sources.

---

## Hardware Controllers

### NEC uPD765 Floppy Disk Controller

The uPD765 (or Intel 8272 equivalent) is an LSI floppy disk controller capable of interfacing with up to 4 floppy disk drives.

#### Density Format Support

- **FM (Frequency Modulation):** Single density, IBM 3740 format
- **MFM (Modified Frequency Modulation):** Double density, IBM System 34 format
- **Multi-side:** Supports double-sided recording
- **Multi-track:** Can read/write multiple tracks in sequence

#### Data Rate and Clocking

For 4 MHz FDC operation:
- **FM mode:** 250 kHz data rate
- **MFM mode:** 500 kHz data rate

For 8 MHz FDC operation:
- **FM mode:** 500 kHz data rate
- **MFM mode:** 1 MHz data rate

#### Sector Size Support

Variable recording length per sector:
- 128 bytes
- 256 bytes
- 512 bytes
- 1024 bytes
- 2048 bytes
- 4096 bytes
- 8192 bytes

#### DMA Operation

The uPD765 provides handshaking signals for DMA operation:
- Compatible with external DMA controllers (e.g., Intel 8257, AMD 9517)
- Can operate in DMA or non-DMA (programmed I/O) mode
- DMA requests are generated during data transfers

#### Multi-Density Switching

The MFM mode signal controls density:
- **High (logic 1):** MFM double density mode
- **Low (logic 0):** FM single density mode

This signal allows the data recovery circuit to switch between density modes, which is critical for the RC702's mixed-density Track 0 format.

#### Command Set

Key commands relevant to SYSGEN and boot operations:
- **Read Data:** Read sectors from disk
- **Write Data:** Write sectors to disk
- **Format Track:** Format a complete track
- **Read ID:** Read sector header information
- **Seek:** Position head to specified track
- **Recalibrate:** Move head to track 0
- **Sense Drive Status:** Query drive ready status
- **Sense Interrupt Status:** Query interrupt cause

### AMD Am9517A / Intel 8237 DMA Controller

The DMA controller enables high-speed data transfer between memory and I/O devices without CPU intervention.

#### Transfer Capabilities

- **Transfer rate:** Up to 1.6 megabytes per second
- **Channel capacity:** Each channel can address full 64KB memory
- **Transfer size:** Up to 64KB per channel with single programming

#### Four DMA Channels

The 8237 provides four independent DMA channels that can be programmed individually:

**RC702 Channel Assignment** (per technical manual section 2.3.9):
- **Channel 0:** External / J8 expansion (DREQ0 via J8-R28, DACK0 back to J8). Used by WD1000 HD controller and MEM700 RAM disk.
- **Channel 1:** NEC uPD765 floppy disk controller (on motherboard)
- **Channel 2:** Intel 8275 CRT controller (display refresh, row buffer refill — primary)
- **Channel 3:** Intel 8275 CRT controller (*roll function* second DMA channel — takes over from ch2 after TC, enables hardware-assisted vertical scroll of a circular display buffer.  Currently unused by all firmware; see `docs/dma_ch3_8275_roll_function.md`.)

#### Transfer Modes

1. **Single Mode**
   - One DMA cycle per request
   - Interleaves with CPU cycles
   - Continues until word count reaches zero

2. **Block Mode**
   - Continuous transfer until word count reaches zero
   - Or until EOP (End of Process) signal activates
   - Highest transfer rate

3. **Demand Mode**
   - Transfers continue while DRQ (DMA Request) is active
   - Stops when TC (Terminal Count) or EOP activates
   - Or when DRQ goes inactive
   - Optimized for high-speed peripherals

4. **Cascade Mode**
   - Used to cascade additional DMA controllers
   - Expands beyond four channels

#### Programming Registers

Each channel has:
- **Base Address Register** (16-bit): Starting memory address
- **Word Count Register** (16-bit): Number of transfers minus 1
- **Mode Register**: Transfer mode, direction, auto-initialize

Global registers:
- **Command Register**: Controller-wide options
- **Status Register**: Channel status and TC flags
- **Mask Register**: Enable/disable individual channels
- **Request Register**: Software DMA requests

#### RC702-Specific DMA Configuration

**Channel 1 (Floppy):**
- Mode: 0x45 (Transfer disk to memory, increment address)
- Used for reading boot sectors and CP/M system tracks
- DMA address set to 0x0000 during boot
- Word count set based on track/sector size

**Channel 2 (Display):**
- Mode: 0x5A (Memory to display, auto-initialize)
- Base address: 0xB020 (display buffer)
- Word count: 0x07CF (2000 characters = 80×25)
- Auto-initialize mode continuously refreshes display

### Intel 8275 Programmable CRT Controller

The 8275 is a single-chip CRT controller that manages raster scan displays.

#### Primary Functions

- **Display Refresh:** Buffers information from main memory
- **Position Tracking:** Keeps track of screen position
- **DMA Interface:** Requests DMA transfers for row buffer refills

#### Architecture

**Row Buffers:**
- Two 80-character buffers
- Filled from system memory via DMA
- Allows continuous display while CPU accesses memory

**FIFOs:**
- Two 16-character FIFOs
- Provide extra buffering in Transparent Attribute Mode
- Smooths DMA request timing

#### Programmable Parameters

**Screen Format:**
- Characters per row (programmable)
- Rows per frame (programmable)
- Lines per character (affects character height)

**Raster Timing:**
- Derived from character clock input
- All timing parameters set at reset
- Clock provided by external dot timing logic

**Cursor Control:**
- Position (X, Y coordinates)
- Format (block, underline, etc.)
- Blink rate
- Reverse video

#### DMA Operation

**DMA Request Modes:**
- Single character requests
- Burst mode: 2, 4, 8, or 16 character bursts
- Programmable intervals between requests

**RC702 Configuration:**
- Burst mode with auto-initialize
- Continuous refresh from display buffer at 0xB020
- 2000 bytes transferred per frame (80×25 characters)

#### Initialization Sequence

1. Reset controller
2. Load screen format parameters
3. Set cursor position
4. Preset internal counters
5. Configure DMA parameters
6. Start display

### Display Control Character Protocol

The BIOS display driver (CONOUT) interprets control characters before sending
data to the 8275 CRT controller.  Documented in CP/M for RC702 User's Guide,
Appendix B.

#### Control Characters

| Code | Dec | Function |
|------|-----|----------|
| 0x01 | 1 | Insert line at cursor, scroll remainder down |
| 0x02 | 2 | Delete line at cursor, scroll remainder up |
| 0x05 | 5 | Cursor left (backspace) |
| 0x06 | 6 | XY addressing: followed by H+0x20, V+0x20 |
| 0x08 | 8 | Cursor left (backspace, same as 0x05) |
| 0x09 | 9 | Cursor 4 positions forward (tab) |
| 0x0A | 10 | Cursor down (line feed) |
| 0x0C | 12 | Clear screen, reset attributes, cursor to (0,0) |
| 0x0D | 13 | Cursor to column 0 on current line (carriage return) |
| 0x14 | 20 | Mark subsequent characters as background |
| 0x15 | 21 | Mark subsequent characters as foreground |
| 0x17 | 23 | Delete foreground characters without affecting background |
| 0x18 | 24 | Cursor right (forward-space) |
| 0x1A | 26 | Cursor up |
| 0x1D | 29 | Cursor to (0,0) home position |
| 0x1E | 30 | Erase from cursor to end of line |
| 0x1F | 31 | Erase from cursor to end of screen |

#### XY Cursor Addressing

Control character 6 followed by two position bytes:
- Byte 1: horizontal position + 0x20 (column 0 → 0x20, column 79 → 0x6F)
- Byte 2: vertical position + 0x20 (row 0 → 0x20, row 24 → 0x38)

Screen coordinates: (0,0) = upper left, (79,24) = lower right.  The 80×25
display area is confirmed.  Cursor addressing order (H,V vs V,H) is
configurable via CONFI.COM (stored in BIOS ADRMOD byte at BIOS+0x33).

#### Display Attributes

Each character position has an attribute byte.  Attribute value = 128 + sum
of active attributes:

| Value | Hex | Effect |
|-------|-----|--------|
| 2 | 0x02 | Blinking |
| 4 | 0x04 | Semigraphic (alternate character generator ROM ROA327) |
| 16 | 0x10 | Inverse video |
| 32 | 0x20 | Underscore |

Attributes combine additively: e.g., blinking inverse = 128 + 2 + 16 = 146.
"Set attribute" sends 128 + value; "reset attribute" sends 128 (no attributes).

### Keyboard

The RC702 keyboard is a smart peripheral that provides ready-to-use 8-bit
character codes via PIO Port A (0x10).  No scan code processing is needed on
the host side.

Two keyboard layouts were produced:
- **RC721**: early production (serial no. before KBU723 #51)
- **RC722**: early production (serial no. before KBU722 #384)

Later productions of both RC721/RC722 changed the layout (see Figures 2 and
3 in the User's Guide, p.65).

#### Keyboard Code Map (Figure 2 — Early RC721/RC722)

The keyboard sends the following hex codes on PIO Port A when a key is
pressed.  Each key has up to four values: normal, shifted (SHIFT), PA
(function key modifier), and SHIFT+PA.

**Top row (numeric keys):**

| Key | Normal | SHIFT | PA | SHIFT+PA |
|-----|--------|-------|----|----------|
| 1 | 31 | 21 | 91 | A1 |
| 2 | 32 | 22 | 92 | A2 |
| 3 | 33 | 23 | 93 | A3 |
| 4 | 34 | 24 | 94 | A4 |
| 5 | 35 | 25 | 95 | A5 |
| 6 | 36 | 26 | 96 | A6 |
| 7 | 37 | 27 | 97 | A7 |
| 8 | 38 | 28 | 98 | A8 |
| 9 | 39 | 29 | 99 | A9 |
| 0 | 30 | 3D | 90 | 9D |

**Function keys (PA1-PA5):**

| Key | Normal | SHIFT |
|-----|--------|-------|
| PA1 | 01 | 11 |
| PA2 | 1E | 0E |
| PA3 | 05 | 15 |
| PA4 | 0E | 13 |
| PA5 | 1E | 1E |

**Special keys:**

| Key | Code | Notes |
|-----|------|-------|
| RETURN | 0D | Carriage return |
| SPACE | 20 | |
| BS (backspace) | 08 | |
| TAB | 09 | |
| DEL | 7F | Delete character |
| BREAK | 03 | CTRL-C equivalent |

PA keys are programmable function keys.  The PA code values can be patched
in the BIOS conversion table (see Appendix D of User's Guide for patch
addresses).

The keyboard conversion table translates raw key codes to application
characters.  The table base address depends on disk format:
- Mini (5.25") diskette systems: **0x2E80**
- Maxi (8") diskette systems: **0x4680**

Patch address for any key = baseaddress + key value.  For example, the
shifted PA5 key (code 0x1E) on a mini system: 0x2E80 + 0x1E = 0x2E9E.

The conversion table is part of the CP/M system image loaded from Track 0
and can be switched between 7 language variants via CONFI.COM (Danish,
Swedish, German, UK ASCII, US ASCII, French, Library).

### Serial Port Assignments

The RC702 has two serial ports, both active simultaneously:

- **SIO Channel A (ports 0x08/0x0A)**: **Printer port** — directly connected
  to a serial printer.  CP/M maps this as the LST: (list) device.
- **SIO Channel B (ports 0x09/0x0B)**: **Terminal port** — used for an
  optional modem, PC connection, or second RC700 (via FILEX file transfer).
  CP/M maps this as both the PUN: (punch) and RDR: (reader) devices.

The RC700 Parallel Input/Output Port is **not supported** by CP/M — only the
serial ports are used for peripherals.

The system does **not** support the IOBYTE function or the modification of
logical-physical device assignments via the STAT command.  The system does
not include the MOVCPM program.

### Z80A-SIO/2 Chip Details

**Part number:** Z8442 (Z80A-SIO/2). Confirmed from RC702/RC703
Microcomputer Technical Manual (RCSL 44-RT2056), section 2.3.4.

**"SIO/2" means bonding option 2**, not a feature version. The SIO comes
in five bonding variants (SIO/0 through SIO/4) that differ only in which
Channel B signals are brought out on the 40-pin package:
- SIO/0: TxCB and RxCB bonded together, all other signals present
- SIO/1: sacrifices DTRB, keeps TxCB, RxCB, SYNCB
- **SIO/2: sacrifices SYNCB, keeps TxCB, RxCB, DTRB** (used in RC702)
- SIO/3, SIO/4: 44-pin packages with all signals

**Register set:** WR0-WR7, RR0-RR2 only. The SIO does **not** have
WR10-WR15 (DPLL, BRG, NRZI encoding) -- those are features of the
later Z85C30 SCC (Serial Communications Controller), a different chip.
Verified from Zilog um0081.pdf (Z80 Family CPU Peripherals User Manual).

**Key pin assignments (SIO/2, 40-pin DIP):**

| Pin | Signal | Channel | Notes |
|-----|--------|---------|-------|
| 13 | RxCA | A | Receive clock input (separate pin from TxCA) |
| 14 | TxCA | A | Transmit clock input (separate pin from RxCA) |
| 28 | RxCB | B | Receive clock input |
| 27 | TxCB | B | Transmit clock input |
| 11 | SYNCA | A | Sync detect output in SDLC mode; general input in async |
| 16 | DTRA | A | Data Terminal Ready output |
| 25 | DTRB | B | Data Terminal Ready output (replaces SYNCB in SIO/2) |

Note: TxCA and RxCA are separate physical pins on the chip. The shared
clock on the RC702 is a **PCB wiring decision** -- the CTC ch0 output
trace forks to both pins. See CTC section for details.

**Synchronous mode capabilities:**
- SDLC/HDLC: flag bytes (0x7E), automatic zero-insertion/deletion,
  CRC-CCITT generation and checking, address field filtering
- Monosync and bisync: programmable sync characters (WR6/WR7)
- All sync modes require external clock on TxC/RxC (no internal DPLL)
- SDLC mode does not use the SYNC pin (uses internal flag detection),
  so the SIO/2's missing SYNCB pin is not a limitation for SDLC

**MAME emulation:** rc702.cpp originally used `z80dart_device` (Z80-DART,
async only) instead of `z80sio_device`. Fixed locally, filed as
ravn/mame#3. The DART variant silently rejects sync mode programming.

### Serial Baud Rate Limits

Both SIO channels share the same 0.6144 MHz baud rate clock (see CTC section).
With the CONFI utility, users can select baud rates from 50 to 19200 baud by
adjusting the CTC divisor and SIO clock mode (×16 or ×64).

The BIOS C rewrite uses CTC count=1 with SIO ×16 for **38400 baud** on both
channels — the maximum achievable rate with this hardware.

Higher rates are not possible without hardware modification:
- SIO ×1 mode is not viable for async RX (no oversampling for start bit
  detection — x1 was designed for synchronous protocols where the clock
  is phase-aligned by the transmitter). TX works at x1 because the
  transmitter generates its own timing.
- Synchronous mode TX works with the existing CTC clock at ÷1 — sync
  mode has no start-bit detection problem, so the ÷1 framing issue
  doesn't apply on the transmit side. The SIO supports SDLC framing
  (0x7E flags, zero-insertion, CRC-CCITT) in hardware. At CTC timer
  mode divisor 1, **TX achieves the full ~614 kbaud** bit clock
  (bench-verified 2026-04 on real hardware; updated from earlier
  250 kbaud session-summary estimates). **Sync RX is not viable**
  because pins 15/17 (TxC/RxC from the cable) are NC on
  MIC702/MIC703 boards and the Z80-SIO/2 has no on-chip DPLL — the
  receiver cannot recover a clock from RxD data. So SIO sync mode is
  TX-only on this hardware. Note: the SIO does NOT have a DPLL or
  BRG (those are Z85C30 SCC features); "SIO/2" means bonding option
  2, not version 2.
  See `docs/cpnet_fast_link.md` for the current CP/NET fast-link
  design (Option P uses PIO-B / J3 half-duplex; Option H is the
  long-term comparison target that revives SIO sync TX). Earlier
  `cpnet/SPLIT_CHANNEL_TRANSPORT.md` is superseded.
- DMA-assisted serial is not possible (SIO has no DREQ output to the Am9517A)
- The 0.6144 MHz clock could be doubled to 1.2288 MHz by tapping the 74LS393
  divider chain one stage earlier (÷16 instead of ÷32), but this requires a
  PCB modification and changes all CONFI baud rate divisors

**Maximum SIO TxC/RxC clock input:** 4 MHz (250 ns minimum cycle time per
Z80A SIO datasheet AC characteristics). With ×16 mode this gives a
theoretical maximum of 250000 baud, but requires a 4 MHz clock source
routed to TxC/RxC (PCB modification). With the stock 0.6144 MHz
oscillator, the maximum is 38400 (divisor 1, ×16).

**Alternative fast paths** (no PCB modification required):
- PIO-B / J3 — 8-bit handshaked transfers, ~30-50 KB/s sustained
  (Z80 ISR + handshake bound), ~50-80 KB/s peak in tight polled
  loops. See [`docs/cpnet_fast_link.md`](docs/cpnet_fast_link.md)
  Option P for the committed fast-link design over this connector.
  PIO-A / J4 is reserved for the RC722 keyboard and is not available
  as a fast-link connector.
- SIO-A sync-mode TX at the ÷1 clock — ~614 kbaud bit rate,
  ~70 KB/s after framing. TX-only on this hardware (sync RX needs an
  external clock not routed to J1). See `docs/cpnet_fast_link.md`
  Option H for the comparison-target design.
- J8 bus expansion connector — polled I/O ~150-286 KB/s, DMA channel 0
  ~500-1000 KB/s. See `docs/j8_bus_expansion.md` for full analysis.
  Out of scope for current CP/NET work.

### Peripheral Handshake

#### Printer Port (SIO Channel A)

Serial interface with RTS/CTS busy handshake:
1. DTR is asserted
2. RTS is asserted
3. CTS from the printer gates TXD (transmission)

When CTS is deasserted (printer busy), the SIO holds transmission until
CTS is reasserted.  The SIO "Auto Enables" feature (WR3 bit 5) handles
this automatically.

The printer port can be used for attachment of most printers with a serial
interface and busy control.

**Typical printers:**
- **RC862** — rebranded Epson MX-80 (most common)
- **RC867** — rebranded Epson MX-82 (less common)

#### Terminal Port (SIO Channel B)

- **Transmitter**: same RTS/CTS handshake as printer port
- **Receiver**: uses DCD (Data Carrier Detect) signal to enable receiving

The transmitter part functions exactly as the printer port and could be used
for a punch device.  The receiver part can be used to attach e.g. a reader.

#### RC791 Line Selector

The RC791 is an external RS-232 A/B line switch that allows two devices to
share one SIO channel.  It is controlled by the BIOS `LINSEL` routine
(see `rc703-div-bios-typer/cpmboot.mac`) using DTR and RTS signaling:

- **Parameters**: A = port (0=SIO-A, 1=SIO-B), B = line (0=release, 1=line A, 2=line B)
- **Protocol**:
  1. Wait for SIO "All Sent" (RR1 bit 0) — pending transmission completes
  2. Clear both DTR and RTS (release current line)
  3. If B=0, return (release only)
  4. Set RTS based on line: RTS = (B==2), selecting line B when high
  5. Assert DTR (bit 7) to latch the selection
  6. Wait 1-2 timer periods for the switch to settle
  7. Check CTS in RR0 — CTS set means the selected device responded (return 0xFF success), CTS clear means no device present (clear DTR/RTS, return 0 failure)

Reference: https://datamuseum.dk/wiki/RC791_Linieselektor

---

## Multi-Density Disk Support

The RC702's multi-density disk support is one of its most sophisticated features, requiring careful coordination between SYSGEN and the BIOS.

### Density Mode Definitions

The RC702 uses a disk format descriptor byte to specify the density and sector layout:

```
Disk Format Codes (from SYSGEN.ASM and CPMBOOT.MAC):

0x00/0xFF  - Drive type indicator (0x00=floppy, 0xFF=hard disk)

For maxi (8") floppy disks:
0x08 - DD (Double Density): 512 B/S, 30 S/T  [Standard CP/M format]
0x10 - SS (Single Density): 128 B/S, 26 S/T  [Track 0, Side 0]
0x18 - DD (Double Density): 256 B/S, 26 S/T  [Track 0, Side 1]

For mini (5.25") floppy disks:
0x08 - DD: 512 B/S, 20 S/T
0x10 - DD: 512 B/S, 20 S/T
0x18 - DD: 512 B/S, 30 S/T
```

### SYSGEN Multi-Density Handling

The SYSGEN utility must handle the complex track layout when reading or writing the CP/M system tracks (Track 0 and Track 1).

#### Track 0 Processing

When accessing Track 0, SYSGEN must:

1. **Set density for Track 0, Side 0:**
   - Switch to FM (single density) mode
   - Configure for 128-byte sectors
   - Format code: 0x10

2. **Set density for Track 0, Side 1:**
   - Switch to MFM (double density) mode
   - Configure for 256-byte sectors
   - Format code: 0x18

3. **Read/write 16 sectors per side**

#### Track 1 Processing (Complex Multi-Density)

Track 1 uses an even more complex format with THREE different density zones:

**SYSGEN.ASM defines these parameters:**

```asm
rccpmfmt:      db 08h  ; Normal CP/M format (DD, 512 B/S)
                        ; Restored at exit

rctrk1fmt1:    db 10h  ; Track 1 format for sectors < rcmaxsect1
rctrk1fmt2:    db 18h  ; Track 1 format for sectors > rcmaxsect1

rcmaxsect1:    db 19h  ; Largest sector in part ONE (sector 25)
rcmaxsect2:    db 34h  ; Largest sector in part TWO (sector 52)
rcoffset2:     db 1Ah  ; Offset for sectors in part TWO (26)
```

**Track 1 Sector Mapping:**

- **Sectors 0-25 (0x00-0x19):** Format 0x10 (SS, 128 B/S)
- **Sectors 26-52 (0x1A-0x34):** Format 0x18 (DD, 256 B/S)
- **Sectors 53+ (0x35+):** Format 0x08 (DD, 512 B/S) [actually these are on Track 2+]

The SYSGEN code must dynamically switch density modes while reading/writing Track 1:

```asm
; Pseudocode logic from SYSGEN.ASM:

IF sector < rcmaxsect1 THEN
    format = rctrk1fmt1  ; 0x10 = SS, 128 B/S
ELSE IF sector < rcmaxsect2 THEN
    format = rctrk1fmt2  ; 0x18 = DD, 256 B/S
    actual_sector = sector + rcoffset2
ELSE
    format = rccpmfmt    ; 0x08 = DD, 512 B/S
END IF
```

### Sector Interleaving

The RC702 uses a 2:1 sector interleave on data tracks to optimize performance:

**Physical sector order:** 0, 2, 4, 6, 8, 1, 3, 5, 7

This allows the CPU time to process one sector before the next sector arrives under the read head, reducing the need for full-track rotations.

**Translation Tables:**

SYSGEN.ASM includes two sector translation tables:

1. **minitrans:** For mini (5.25") floppy disks
2. **maxitrans:** For maxi (8") floppy disks

```asm
maxitrans:  db 0, 4, 8, 0Ch, 10h, 14h, 18h
            db 1, 5, 9, 0Dh, 11h, 15h, 19h
            db 2, 6, 0Ah, 0Eh, 12h, 16h
            db 3, 7, 0Bh, 0Fh, 13h, 17h
```

### BIOS Disk Parameter Blocks

The CP/M BIOS maintains Disk Parameter Blocks (DPBs) that define the disk geometry and allocation for each drive and format type. These parameters must match the physical disk format:

**Key DPB fields:**
- **SPT:** Sectors Per Track (logical sectors)
- **BSH/BLM:** Block shift/mask for allocation block size
- **EXM:** Extent mask
- **DSM:** Maximum block number (disk capacity)
- **DRM:** Maximum directory entry number
- **AL0/AL1:** Directory allocation bitmap
- **CKS:** Directory check vector size
- **OFF:** Number of reserved tracks

### Runtime Format Detection

The RC702 BIOS and SYSGEN must detect whether the system is running on:

1. **Mini floppy (5.25"):** DIP switch bit 7 = 1
2. **Maxi floppy (8"):** DIP switch bit 7 = 0

(SYSGEN.ASM is the definitive source on this)

Based on this detection, different translation tables and sector layouts are selected.

### Challenges for SYSGEN

The SYSGEN utility faces several challenges due to this multi-density format:

1. **Dynamic Density Switching:** Must change FDC mode between FM and MFM while reading the same track

2. **Variable Sector Sizes:** Must handle 128, 256, and 512-byte sectors in the same copy operation

3. **Logical-to-Physical Mapping:** Must translate logical CP/M sector numbers to physical disk sectors with correct density mode

4. **Boundary Conditions:** Must carefully handle transitions between density zones, especially on Track 1

5. **BIOS Coordination:** Must match the exact sector layout that the BIOS expects

---

## Implementation Notes for Developers

### SYSGEN Modifications for Multi-Density

The RC702 SYSGEN differs significantly from the standard Digital Research SYSGEN.COM:

1. **Format Detection Code:** Added runtime detection of mini vs. maxi floppy
2. **Multiple Translation Tables:** Separate tables for different disk formats
3. **Track-Specific Formatting:** Special handling for Track 0 and Track 1
4. **Density Switching Logic:** Code to change FDC density mode during track access
5. **BIOS Interface Changes:** Modified to pass format codes to BIOS sector I/O routines

### Bootstrap ROM (ROA375) Development

When developing or modifying the ROA375 autoload ROM:

1. **Size Constraint:** Must fit in 2KB (0x0000-0x07FF) with factory default solder bridge. 4KB (0x0000-0x0FFF) possible if A11 solder bridge is closed (unconfirmed).
2. **Self-Relocation:** Must copy itself to RAM before disabling ROM mapping
3. **Hardware Initialization:** Must properly initialize all controllers in correct order
4. **Interrupt Vectors:** Must establish Mode 2 interrupt table before enabling interrupts
5. **Display Early:** Initialize display early for user feedback
6. **Multi-Density Boot:** Must correctly read mixed-density Track 0
7. **Error Handling:** Must gracefully fall back between boot devices

### Testing Considerations

1. **Multi-Density Transitions:** Test reading/writing across density boundaries
2. **Format Detection:** Verify correct operation on both 5.25" and 8" drives
3. **BIOS Compatibility:** Ensure SYSGEN matches exact BIOS sector layout
4. **Edge Cases:** Test boundary sectors (e.g., sector 25/26 on Track 1)
5. **Hardware Variations:** Test with both NEC uPD765 and Intel 8272 FDCs
6. **DMA Timing:** Verify DMA transfers complete before next operation

---

## RC-Specific CP/M Utilities

The RC700 CP/M distribution includes several utilities beyond the standard
Digital Research set.  These are RC700 transient commands (.COM files).

### FORMAT (4.3.1)

Formats diskettes for use on the RC700.  Erases all data.

- **5.25" mini**: always double-sided, double-density (no format prompt).
  36 tracks formatted.
- **8" maxi**: prompts for type — 1=SS/SD (128 B/S, 26 S/T) or 2=DS/DD
  (512 B/S, 15 S/T).  77 tracks formatted.
- CP/M System Diskettes always use format type 2 (DS/DD).
- Factory-fresh 8" diskettes are usually preformatted but formatting
  improves reliability.  5.25" diskettes must always be formatted.

Version string: `RC700 FORMAT UTILITY VERS 1.2 82.03.03`

### HDINST (4.3.2)

Configures (or reconfigures) the RC763 hard disk.  Only for systems with
hard disk.  Four partition configurations available (see Appendix H).

- First logical disk is always C (even if only one floppy is present,
  making C have the same capacity as the floppy).
- Can copy CP/M system to tracks 0 and 1 of the hard disk.
- Hard disk boot requires hard disk autoload PROM (DF016, micro fuse in
  pos. 66) and CP/M system copied to HD tracks 0+1.
- **WARNING**: A new configuration erases all data on the hard disk.

Version string: `RC700 HARD DISK INSTALLATION - VERS.1.1 82.09.28`

### BACKUP (4.3.3)

Copies an entire 8" or 5.25" diskette on a one-drive or two-drive system.

- 8" diskettes may be single-sided single-density or double-sided
  double-density.  5.25" must be double-sided double-density.
- Normally copies entire disk and verifies.  With `FAST` option, copies
  without verifying.
- If an HD system has logical disk C, C may also be used as source/dest.
- Reports `BAD SECTOR ON SOURCE DISK` or `BAD SECTOR ON DESTINATION DISK`
  on read/write errors.

Version string: `RC700 BACKUP VERS 2.1 82.10.12`

### ASSIGN (4.3.4)

Assigns a format to an 8" diskette drive (A or B).  The specified format
may be `SD` (single-sided, single-density) or `DD` (double-sided,
double-density).

Example: `A>ASSIGN B:=SD` makes B: ready for single-density diskettes.

### VERIFY (4.3.5)

Checks a disk for bad sectors.  If bad sectors are found, displays total
number of bad blocks and offers to create a read-only dummy file called
`BLOCKS.BAD` to reserve those blocks.

- Creating the dummy file may damage existing files on the disk.  Copy
  important files first.
- Can be interrupted at any time with CTRL-C.

Version string: `RC700 DISKETTE VERIFICATION VERS.1.0 82.09.14`

### STORE (4.3.6)

Backs up files from a hard disk unit to one or more floppy diskettes.
Labels the floppy with an "iden" string (up to 8 chars) for later RESTORE.
Maximum 100 file references per operation.

Version string: `RC700 STORE VERS.1.1 83.01.03`

### RESTORE (4.3.7)

Restores files from a STORE-created floppy backup onto a hard disk unit.
The "iden" must match the one used during STORE.  Optionally verifies with
`CHECK` option without actually copying.

Version string: `RC700 RESTORE VERS: 1.0 82.10.06`

### SYSGEN (4.3.8)

RC700-modified version of the standard CP/M SYSGEN.  Reads BIOS, BDOS, and
CCP from a System Diskette or from a file, and writes them to the reserved
tracks of a new or existing System Diskette.

- Works with or without a previously created COM file.
- Mini diskette systems: `SAVE 68 <filename>` (68 pages of 256 bytes)
- Maxi diskette systems: `SAVE 107 <filename>` (107 pages of 256 bytes)

### CONFI (4.3.9)

RC700 Configuration Utility.  Modifies BIOS configuration parameters stored
on Track 0 of the system diskette.  Changes take effect at next cold boot.

Version string: `RC700 CP/M CONFIGURATION UTILITY vers 2.1 13.02.33`

**Main menu:**
1. PRINTER PORT
2. TERMINAL PORT
3. CONVERSION
4. CURSOR
5. MINI MOTOR STOP TIMER
6. SAVE CONFIGURATION DESCRIPTION

**CONFI parameter details (Appendix G):**

#### G.1 Printer Port (SIO Channel A)

| Parameter | Options (* = default) |
|-----------|----------------------|
| G.1.1 Stop bits | 1: 1 bit*, 2: 1.5 bit, 3: 2 bits |
| G.1.2 Parity | 1: even*, 2: no, 3: odd |
| G.1.3 Baud rate | 1:50, 2:75, 3:110, 4:150, 5:300, 6:600, 7:1200*, 8:2400, 9:4800, 10:9600, 11:19200 |
| G.1.4 Bits/char | 1: 5 bits, 2: 6 bits, 3: 7 bits*, 4: 8 bits |

#### G.2 Terminal Port (SIO Channel B)

| Parameter | Options (* = default) |
|-----------|----------------------|
| G.2.1 Stop bits | 1: 1 bit*, 2: 1.5 bit, 3: 2 bits |
| G.2.2 Parity | 1: even*, 2: no, 3: odd |
| G.2.3 Baud rate | 1:50, 2:75, 3:110, 4:150, 5:300, 6:600, 7:1200*, 8:2400, 9:4800, 10:9600, 11:19200 |
| G.2.4 Bits/char TX | 1: 5 bits, 2: 6 bits, 3: 7 bits*, 4: 8 bits |
| G.2.5 Bits/char RX | 1: 5 bits, 2: 6 bits, 3: 7 bits*, 4: 8 bits |

Note: The terminal port has separate TX and RX character width settings,
unlike the printer port.

#### G.3 Conversion Tables

| Option | Language |
|--------|----------|
| 1 | Danish |
| 2 | Swedish |
| 3 | German |
| 4 | UK ASCII |
| 5 | US ASCII* |
| 6 | French |
| 7 | Library |

The current value is marked with an asterisk in the CONFI menu.  Typing
RETURN on the current value keeps it unchanged.

#### G.4 Cursor Presentation

| Parameter | Options (* = default) |
|-----------|----------------------|
| G.4.1 Format | 1: blinking reverse video*, 2: blinking underline, 3: reverse video, 4: underline |
| G.4.2 Addressing | 1: H,V (horizontal,vertical)*, 2: V,H (vertical,horizontal) |

#### G.5 Mini Motor Stop Timer

- Range: 5-1200 seconds
- Default: 5 seconds
- Controls how long the 5.25" floppy motor runs after the last disk
  access.  Not applicable to 8" drives (always spinning).

**Saving configuration:**

Option 6 in the main menu saves the new configuration to the system disk.
The CP/M system diskette must be in drive A during execution.  If C: is
being reconfigured, the system must already be installed on the hard disk.
Pressing RETURN without saving exits CONFI and restores the old
configuration at next cold boot.

### SELECT (4.3.10)

Controls the RC791 Line Selector from the command line.

Syntax: `SELECT port function`

- **port**: P (printer port) or T (terminal port)
- **function**: A (select line A), B (select line B), R (release line)

Responses:
- `LINE READY` — selection successful
- `LINE BUSY OR DEVICE OFFLINE` — line occupied or device not connected
- `LINE RELEASED` — line released successfully

### USER (4.3.11)

Built-in CP/M command (not RC-specific).  Allows up to 15 logical user
areas within the same directory.  `USER n` where n = 0-15.  Default after
cold boot is user area 0.

### AUTOEXEC (4.3.12)

Modifies the CP/M System Disk to automatically execute a command line after
boot.

Two modes:
1. Execute after each cold boot AND warm boot
2. Execute after cold boot only

Example: `AUTOEXEC` then enter `CAT` to auto-run CAT on every boot.

Version string: `RC700 Autoexec vers. 1.0 10.01.83`

### CAT (4.1.9)

Enhanced directory listing.  Lists one or more filenames in alphabetical
order, shows total unused directory entries and free disk space.

Options:
- `$SYS` — include files with SYS attribute (listed in parentheses)
- `$R/O` — mark read-only files with asterisk (*)

Example: `CAT *.COM $SYS $R/O` — lists all .COM files including system
files, marking read-only ones.

### TRANSFER (4.1.7)

Transfers files between disks with format conversion.  Reads up to 32K
bytes at a time into main memory, asks user to swap disks, then writes.

- Source and destination disk formats must be specified:
  `SS` (single-sided single-density) or `DD` (double-sided double-density)
- 5.25" diskettes default to DD; format type prompt only for 8".
- Can transfer from SS to DD format (converts between CP/M formats).
- Source files larger than 32K are destroyed if written to same disk under
  same name.

Version string: `RC700 TRANSFER UTILITY VERS 2.0 82.01.05`

### FILEX (4.1.10)

File transfer between two computers via the terminal port (SIO Channel B).
Both computers must use the same baud rate and 7-bit character format
(configure via CONFI).

**Setup:**
1. On remote computer: `FILEX REMOTE`
2. On local computer: `FILEX` (interactive) or
   `FILEX destination=source` (single command)

Remote drive names use prefix `R` — e.g., `RA:` and `RB:` for the remote
computer's A: and B: drives.

The `MORED` option prevents the remote station from exiting remote mode
after the transfer.

**Cable requirements for direct connection (no Line Selector):**
- CML012 (5 meters)
- CML013 (12 meters)
- CML014 (25 meters)

**Cable requirements with RC791 Line Selector:**
- CML092 (5 meters)
- CML093 (12 meters)
- CML094 (25 meters)

### FILEX Transmission Protocol (Appendix I)

FILEX uses a blocked transmission protocol via the terminal port.

**Transaction opcodes:**

| Opcode | Operation | Request payload | Answer payload |
|--------|-----------|-----------------|----------------|
| 1 | OPEN | 16 bytes: filename | result code |
| 2 | MAKE | 16 bytes: filename | result code |
| 3 | READ | (none) | result + 128 bytes data |
| 4 | WRITE | 16 bytes data | result code |
| 5 | CLOSE | (none) | result code |
| 6 | END | (none) | result code |

Result codes: 0=ok, 1=does not exist, 2=full, 3=end of file.

**Block format:**
1. Start character: ASCII 35 (`#`)
2. Block size: 16-bit integer split into 4 ASCII digits (each digit + 64)
3. Data section: each byte split into 2 ASCII digits (each + 64)
4. Checksum: 8-bit, transmitted as 2 ASCII digits
   - Condition: (sum of original string bytes + checksum) mod 256 = 0
5. Stop character: ASCII 13 (CR)

Total characters per block of N data bytes: 2*N + 9.

### XSUB

Extends the SUBMIT facility.  When XSUB is the first command in a .SUB
file, it relocates below the CCP and provides buffered console input to
programs that read from the console.  This means PIP, ED, and DDT can
receive their input directly from the SUB file.

The message `(xsub active)` is displayed to indicate XSUB is resident.
XSUB remains active until the SUB file is exhausted or a cold boot occurs.

---

## RC763 Hard Disk System

### Hard Disk Boot

Hard disk cold boot is possible if:
1. The RC700 has a hard disk autoload PROM (DF016, micro fuse at board
   pos. 66) instead of the standard floppy autoload PROM (ROA375).
2. The CP/M system has been copied to tracks 0 and 1 of the hard disk
   (via HDINST answering "Y" to "COPY CP/M SYSTEM TO HARD DISK").

### Partition Configurations (Appendix H)

The RC763 hard disk (approximately 8MB) can be configured in 4 layouts
via HDINST.  Drive C is always the floppy (matching the physical drive):

| Config | C (floppy) | D | E | F | G |
|--------|-----------|------|------|------|------|
| 1 | 0.270/0.900 | 7.920 MB | — | — | — |
| 2 | 0.270/0.900 | 3.936 MB | 3.936 MB | — | — |
| 3 | 0.270/0.900 | 1.968 MB | 1.968 MB | 3.936 MB | — |
| 4 | 0.270/0.900 | 1.968 MB | 1.968 MB | 1.968 MB | 1.968 MB |

### CP/M Parameters by Disk Size

| Capacity (MB) | Block size | Directory entries |
|---------------|-----------|-------------------|
| 0.270 | 2 KB | 128 |
| 0.900 | 2 KB | 128 |
| 1.968 | 4 KB | 512 |
| 3.936 | 8 KB | 512 |
| 7.920 | 16 KB | 512 |

---

## System Diskette Generation (Appendix C)

Procedure to create a custom System Diskette:

1. Patch BIOS/BDOS/CCP as desired (e.g., keyboard conversion table).
2. Format a diskette with FORMAT.
3. Copy existing system using BACKUP, delete unwanted files with ERA.
4. Write BIOS+BDOS+CCP using SYSGEN.

**Example — patching keyboard conversion table:**
```
A>SYSGEN
SYSGEN VER 2.0
SOURCE DRIVE NAME (OR RETURN TO SKIP) A
; read the system tracks
A>SAVE 107 CPM56.COM     ; 107 pages for maxi, 68 for mini
A>DDT CPM56.COM
DDT VERS 2.2
NEXT PC
; find patch addresses for PA2, PA3, PA4:
; patchaddr = 4680h + key_value  (for maxi; 2E80h for mini)
-S4704                    ; patch PA2
-4704 04 12 .             ; change to CTRL-R
-S4705                    ; patch PA3
-4705 05 . .
-S470E                    ; patch PA4
-470E 0E 13 .             ; change to CTRL-S
-470F 8F . .
-GO
A>SAVE 107 CPM56.COM      ; save patched image
A>SYSGEN CPM56.COM        ; write to system tracks
```

---

## Line Editing and Boot Keys

### Command Line Editing

On the RC700 keyboard:
- **Key marked `<-`**: deletes the last character typed
- **Key marked `->`**: deletes the entire line typed

The up-arrow key (8) may be used to denote CTRL key combinations, e.g.,
`8C` for CTRL-C (system reboot/warm boot).

### System Boot

- **Cold boot (system boot)**: press the RESET button on the front of the
  console, or power on the system.  Loads CP/M from disk.
- **Warm boot (system reboot)**: press CTRL and C simultaneously.  Required
  after changing a disk in the drive (to update read-only status).

### Error Messages

All disk errors are reported as: `BDOS ERR ON d: message`

| Message | Cause |
|---------|-------|
| BAD SECTOR | Disk controller cannot read/write — worn disk, bad controller, wrong format, or damaged data |
| SELECT | Non-existent disk drive selected |
| READ ONLY | Disk has R/O attribute (needs warm boot after disk change) |
| FILE R/O | File has read-only attribute (change with STAT) |

Recovery from BAD SECTOR: retry (R), ignore and continue (RETURN), or
abort and reboot (^C).

---

## RC700 Emulator

Michael Ringgaard's RC700 emulator ([jbox.dk](http://www.jbox.dk/rc702/emulator.shtm))
provides cycle-accurate Z80 emulation with SDL2 display, floppy and hard disk
support, and a built-in ICE-type debugger/monitor.

Source: `../rc700/` relative to this repository.

### Command-Line Options

| Option | Description |
|--------|-------------|
| `image.imd` | Boot from floppy disk image (IMD format). Two images = drives A: and B:. |
| `-maxi` | Select 8" floppy mode (default is 5.25" mini) |
| `-hd HD.IMG` | Mount a hard disk image |
| `-monitor` | Enable monitor mode (F10 enters debugger instead of quitting) |
| `-speed N` | Emulation speed: 100=normal, 50=half, 1000=10x |
| `-memdump FILE` | Dump 64K RAM to FILE on exit (added for BIOS extraction) |

### Keyboard

| Key | Function |
|-----|----------|
| F10 | Exit emulator (or enter monitor if `-monitor` is active) |

### Built-in Monitor

The monitor is an ICE-type Z80 debugger (from Z80SIM by Udo Munk, modified
by Michael Ringgaard).  Activated by pressing F10 when launched with
`-monitor`.  The monitor prompt is `>>>`.  All numeric values are
**hexadecimal** (no `0x` prefix needed).

Source: `../rc700/monitor.c`

#### Memory Commands

| Command | Description |
|---------|-------------|
| `d [addr]` | Dump 256 bytes (16x16) as hex + ASCII. Continues from last address if addr omitted. |
| `l [addr]` | Disassemble 10 instructions from addr. Continues if addr omitted. |
| `m [addr]` | Modify memory interactively. Shows `addr = val :`, enter new hex value or ENTER to advance. Non-hex input exits. |
| `f addr,count,value` | Fill `count` bytes starting at `addr` with `value`. |
| `v from,to,count` | Copy `count` bytes from `from` to `to`. |

#### File Loading

| Command | Description |
|---------|-------------|
| `r file,addr` | Load file at specified address (raw binary). |
| `r file` | Auto-detect format and load. |

File format is auto-detected from the first byte:
- **`0xFF`**: Mostek format (bytes 1-2 = load address little-endian, data follows). Sets PC to load address.
- **`:`**: Intel hex format (standard `:llaaaattddcc` records). Sets PC from EOF record.
- **Otherwise**: Raw binary. Loads at specified address, or 0x0100 (CP/M TPA) if no address given.

All three formats print load statistics (start address, end address, byte count).

#### Execution Control

| Command | Description |
|---------|-------------|
| `g [addr]` | Run from addr (or current PC). Runs until breakpoint, HALT, or error. |
| `t [count]` | Trace `count` instructions (default 20) with full register output per step. |
| *(empty line)* | Single step one instruction. Shows registers and next instruction. |

#### Register Commands

| Command | Description |
|---------|-------------|
| `x` | Display all registers: PC, A, flags, I, IFF, BC, DE, HL, alternate set, IX, IY, SP. |
| `x reg` | Modify a register interactively. Shows current value, prompts for new. |

Register names: `a`, `f`, `b`, `c`, `d`, `e`, `h`, `l`, `i`,
`bc`, `de`, `hl`, `ix`, `iy`, `sp`, `pc`.
Alternate registers: `a'`, `f'`, `b'`, `c'`, `d'`, `e'`, `h'`, `l'`,
`bc'`, `de'`, `hl'`.
Individual flags: `fs` (sign), `fz` (zero), `fh` (half-carry),
`fp` (parity/overflow), `fn` (subtract), `fc` (carry).

#### I/O Port Access

| Command | Description |
|---------|-------------|
| `p addr` | Read port via `cpu_in(addr)`, optionally write new value via `cpu_out(addr, val)`. |

Useful for inspecting RC702 hardware state (e.g., `p 4` reads FDC main status register).

#### Breakpoints

Software breakpoints (replace opcode with HALT). Requires compile-time `SBSIZE` define.

| Command | Description |
|---------|-------------|
| `b` | List all breakpoints (number, address, pass count, current counter). |
| `b addr[,pass]` | Set breakpoint at addr. Triggers after `pass` hits (default 1). Auto-assigns number. |
| `b0 addr` | Set breakpoint #0 explicitly. |
| `b0 c` | Clear breakpoint #0 (restores original opcode). |

#### Execution History

Requires compile-time `HISIZE` define. Records PC + all register values per instruction.

| Command | Description |
|---------|-------------|
| `h` | Show full history (pages at 20 lines, `q` to quit). |
| `h addr` | Show history starting from first entry >= addr. |
| `h c` | Clear history buffer. |

#### T-State Counting

Requires compile-time `ENABLE_TIM` define.

| Command | Description |
|---------|-------------|
| `z start,stop` | Count T-states while PC is between `start` and `stop`. |
| `z` | Show current T-state count, trigger addresses, and status. |

#### Disk Operations

| Command | Description |
|---------|-------------|
| `M file[,drive]` | Mount disk image on drive (0-3, default 0). Hot-swap while running. |
| `S` | Swap drives 0 and 1. |

#### Other Commands

| Command | Description |
|---------|-------------|
| `n` | Dump CRT screen buffer contents. |
| `c` | Measure emulated CPU clock frequency (runs tight loop for 3 seconds). |
| `s` | Show compile-time settings (history size, breakpoint count, T-state support). |
| `?` | Show command summary. |
| `q` | Quit emulator. |

#### CPU Error Codes

The monitor reports these when execution stops:

| Error | Meaning |
|-------|---------|
| OPHALT | HALT opcode reached (not a breakpoint) |
| IOTRAP | I/O trap (unhandled port access) |
| OPTRAP1/2/4 | Unimplemented opcode (1, 2, or 4 bytes) |
| USERINT | User interrupt (Ctrl+C or timer) |

### Workflow: Writing an Assembled BIOS to Disk

The monitor can patch a newly assembled BIOS into the system image in
memory, then SYSGEN writes it to disk with correct multi-density formatting.

**Background:** SYSGEN reads and writes the *complete* CP/M system — CCP,
BDOS, configuration sectors, INIT code, and BIOS — across all system
tracks.  The system image is buffered at `LOADP EQU 0x0900` (from
`sysgen/SYSGEN.ASM`).  Mini systems use 68 pages (17,408 bytes), maxi
systems use 107 pages (27,392 bytes).  The assembled BIOS `.cim` file
contains only the INIT+BIOS portion (starting at disk offset 0), not the
CCP or BDOS which reside on later tracks.

**Procedure:**

1. Build the BIOS variant:
   ```
   cd rcbios && make rel23-maxi
   ```
   This produces `zout/BIOS.cim` (raw binary, offset 0 = address START).

2. Launch the emulator with monitor enabled:
   ```
   rc700-sdl2 -monitor -maxi image.imd
   ```

3. After CP/M boots to `A>`, run SYSGEN and read the full system from
   the source disk:
   ```
   A>SYSGEN
   SOURCE DRIVE NAME (OR RETURN TO SKIP) A
   SOURCE ON A, THEN TYPE RETURN
   ```
   Press RETURN.  SYSGEN reads all system tracks (CCP + BDOS + config +
   INIT + BIOS) into memory at 0x0900.  It prints `FUNCTION COMPLETE`.

4. Before answering the destination prompt, press **F10** to enter the
   monitor.

5. Overwrite the INIT+BIOS portion with the new assembled code:
   ```
   >>> r /path/to/zout/BIOS.cim,900
   ```
   This patches the config+INIT+BIOS at the start of the buffer (offset
   0x0900) while leaving CCP and BDOS intact at higher offsets.

6. Resume CP/M:
   ```
   >>> g
   ```

7. Specify the destination drive when prompted.  SYSGEN writes the
   patched system image to disk with correct multi-density formatting.

**Peeking at memory while CP/M is running:**

Press F10 at any time to freeze execution and inspect Z80 memory. Use `d`
to dump memory, `l` to disassemble, `x` to check registers. Press `g` to
resume. This is useful for verifying that BIOS data was loaded correctly
before running SYSGEN.

---

## References and Sources

### Primary Sources

- **CP/M for RC702 User's Guide:** RCSL No 42-i2190, January 1983, A/S Regnecentralen — [Datamuseum.dk](https://datamuseum.dk/wiki/Bits:30009385) (display protocol, CONFI.COM parameters, disk formats, extended BIOS functions)
- **RC702 Boot Process:** [http://www.jbox.dk/rc702/boot.shtm](http://www.jbox.dk/rc702/boot.shtm)
- **RC702 Emulator Hardware Specs:** [http://www.jbox.dk/rc702/emulator.shtm](http://www.jbox.dk/rc702/emulator.shtm)
- **RC700 CP/M BIOS:** [http://www.jbox.dk/rc702/rcbios.shtm](http://www.jbox.dk/rc702/rcbios.shtm)
- **RC702 Disk Formats:** [http://www.jbox.dk/rc702/disks.shtm](http://www.jbox.dk/rc702/disks.shtm)
- **RC702 Manuals Collection:** [http://www.jbox.dk/rc702/manuals.shtm](http://www.jbox.dk/rc702/manuals.shtm)
- **RC702 Overview:** [http://www.jbox.dk/rc702/index.shtm](http://www.jbox.dk/rc702/index.shtm)

### Source Code Analysis

- **rc703-div-bios-typer/:** Complete RC703 BIOS source code (original authored
  source, not reconstructed). By Karsten Dindorp & Hugo K. Holm (1982), with
  RC703 corrections by FK & LO (1983), RC763B support by LO (1983), and
  YD-380 partner drive modifications by Torben Fjerdingstad (1987).
  Release 1.1, dated 83.09.14. See `rc703-div-bios-typer/README.md` for
  full provenance and module documentation.
- **rcbios/src/:** Reconstructed RC702 BIOS source code (reverse-engineered
  from binary BIOS images on system diskettes). Covers releases 1.4, 2.0–2.3,
  and 3.0 via conditional assembly. Comments backported from RC703 source
  where applicable.
- **ROB358.MAC:** RC703 autoloader PROM source code
- **ROA375.MAC:** RC702 autoloader ROM (reconstruction in progress)
- **SYSGEN.ASM:** RC702-modified SYSGEN utility source code

### Hardware Datasheets

#### NEC uPD765 Floppy Disk Controller
- [NEC uPD765 Application Note (PDF)](https://hxc2001.com/download/datasheet/floppy/thirdparty/FDC/NEC/uPD765_App_Note_Mar79.pdf)
- [uPD765 Datasheet OCR'd (CPC Wiki)](https://www.cpcwiki.eu/imgs/f/f3/UPD765_Datasheet_OCRed.pdf)
- [765 FDC - CPCWiki Reference](https://www.cpcwiki.eu/index.php/765_FDC)

#### Intel 8237/AMD 9517 DMA Controller
- [Intel 8237A High Performance DMA Controller (PDF)](https://pdos.csail.mit.edu/6.828/2018/readings/hardware/8237A.pdf)
- [8237 DMA Controller - Lo-tech Wiki](https://www.lo-tech.co.uk/wiki/8237_DMA_Controller)
- [Intel 8237 - Wikipedia](https://en.wikipedia.org/wiki/Intel_8237)

#### Intel 8275 CRT Controller
- [Intel 8275 Programmable CRT Controller (1984) (PDF)](http://bitsavers.informatik.uni-stuttgart.de/components/intel/8275/1984_8275.pdf)
- [Intel 8275 Programmable CRT Controller (1979) (PDF)](https://bitsavers.org/components/intel/8275/1979_8275.pdf)
- [Intel 8275 CRTC - Scribd](https://www.scribd.com/doc/19068954/Intel-8275-CRTC)

### Documentation PDFs

All scanned PDFs in `docs/` have searchable OCR text layers. OCR was added
using the `jbarlow83/ocrmypdf` Docker image (tesseract-based):

```bash
docker run --rm -v "$(pwd)/docs:/data" jbarlow83/ocrmypdf:latest \
  --skip-text --deskew --rotate-pages /data/INPUT.pdf /data/OUTPUT.pdf
```

Flags: `--skip-text` preserves existing text, `--deskew` straightens
skewed scans, `--rotate-pages` auto-corrects rotation. Use `--force-ocr`
only if the existing text layer is known to be bad (test first — it can
make things worse on low-quality scans).

| PDF | Pages | OCR Status |
|-----|-------|------------|
| `RC702_Microcomputer_Tech_Man.pdf` | 122 | OCR added 2026-04-10 |
| `RC702-RC703_Microcomputer_technical_manual.pdf` | 168 | Pre-existing text layer (mediocre quality, re-OCR tested but worse) |
| `CPM_FOR_RC702_USERS_GUIDE.pdf` | ~100 | OCR added 2026-04-10 |
| `765.pdf` | ~40 | OCR added 2026-04-10 (uPD765 FDC datasheet) |
| `PICCOLINE_RcComal80_Brugervejledning_jan1985.pdf` | ~200 | Pre-existing good text layer |
| `RC702tech.pdf` | ~220 | OCR added 2026-04-10 (RC702 technical notes, schematics) |

Notable pages in `RC702tech.pdf`:
- **SEM702** (physical pp.~215-217): Functional description, Comal80 programming
  example, installation instructions for the RAM character generator
- **Video generator** (p.81 / physical p.218): Schematic for adding highlight
  to the video output signal
- **MEM700** (physical p.219): Schematic for the memory disk (RAM disk)
  described in `roa375/PHE358A.MAC`

### Additional Resources

- **CP/M 2.2 Operating System Manual:** [Digital Research CP/M Documentation](http://www.cpm.z80.de/)
- **Z80 Family CPU and Peripherals User Manual:** Zilog official documentation

---

## Document Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-02-07 | Analysis | Initial document creation from jbox.dk sources and source code analysis |
| 1.1 | 2026-02-20 | Analysis | Added display control chars, keyboard, peripheral handshake, CP/M disk params from User's Guide |
| 1.2 | 2026-02-21 | Analysis | Added RC-specific utilities (FORMAT, BACKUP, ASSIGN, VERIFY, STORE, RESTORE, CONFI, SELECT, AUTOEXEC, CAT, TRANSFER, FILEX, HDINST, XSUB), CONFI parameter tables, FILEX protocol, serial port assignments, keyboard code map, HD boot/partition details, system diskette generation, line editing, error messages |
| 1.3 | 2026-02-21 | Analysis | Added RC700 Emulator section: command-line options, built-in monitor command reference (derived from monitor.c source), BIOS-to-disk workflow using monitor + SYSGEN |

---

## Appendix A: Quick Reference Tables

### I/O Port Summary

| Port | Device | Function |
|------|--------|----------|
| 0x00 | 8275 | CRT Data Register |
| 0x01 | 8275 | CRT Command Register |
| 0x04 | µPD765 | FDC Main Status Register (read) |
| 0x05 | µPD765 | FDC Data Register (read/write) |
| 0x08 | Z80-SIO | SIO Channel A Data |
| 0x09 | Z80-SIO | SIO Channel B Data |
| 0x0A | Z80-SIO | SIO Channel A Control |
| 0x0B | Z80-SIO | SIO Channel B Control |
| 0x0C | CTC | Channel 0 (SIO-A baud rate) |
| 0x0D | CTC | Channel 1 (SIO-B baud rate) |
| 0x0E | CTC | Channel 2 (Display interrupt) |
| 0x0F | CTC | Channel 3 (Floppy interrupt) |
| 0x10 | PIO | Port A Data (Keyboard) |
| 0x11 | PIO | Port B Data (Parallel output) |
| 0x12 | PIO | Port A Control |
| 0x13 | PIO | Port B Control |
| 0x14 | System | SW1: Mini/Maxi switch (read), Mini floppy motor (write) |
| 0x18 | System | RAMEN: PROM disable (write disables PROM0+PROM1) |
| 0x1C | System | BIB: Speaker/beep control |
| 0x44 | CTC2 | Channel 0 (Hard Disk) — external HD board |
| 0x45 | CTC2 | Channel 1 — external |
| 0x46 | CTC2 | Channel 2 — external |
| 0x47 | CTC2 | Channel 3 — external |
| 0xF0 | DMA | CH0 Address (HD) |
| 0xF1 | DMA | CH0 Word Count |
| 0xF2 | DMA | CH1 Address (FDC) |
| 0xF3 | DMA | CH1 Word Count |
| 0xF4 | DMA | CH2 Address (CRT) |
| 0xF5 | DMA | CH2 Word Count |
| 0xF8 | DMA | Command Register |
| 0xFA | DMA | Single Mask Register |
| 0xFB | DMA | Mode Register |
| 0xFC | DMA | Clear Byte Pointer |
| 0xFF | DMA | Full Mask Register |

### Disk Format Summary

| Format | Tracks | Sides | Encoding | Sect/Trk | Bytes/Sect | Capacity |
|--------|--------|-------|----------|----------|------------|----------|
| 5.25" CP/M Trk 0 Side 0 | 1 | 1 | FM | 16 | 128 | 2 KB |
| 5.25" CP/M Trk 0 Side 1 | 1 | 1 | MFM | 16 | 256 | 4 KB |
| 5.25" CP/M Trk 1-34 | 34 | 2 | MFM | 9 | 512 | 306 KB |
| 8" SS/SD | 77 | 1 | FM | 26 | 128 | 247 KB |
| 8" DS/DD Trk 0 | 1 | 2 | FM/MFM | 26 | 128/256 | 10 KB |
| 8" DS/DD Trk 1-77 | 77 | 2 | MFM | 15 | 512 | 1.2 MB |

### Interrupt Vector Table (Mode 2) — autoload-PROM era (ROA375)

**This table is the autoload-PROM IVT layout (I = 0xA0, CTC1 base vector
0x10).**  In CP/M-context with the rcbios-in-c BIOS, the IVT layout is
different: `bios_hw_init.c` sets the CTC1 base vector to **0x00**, so the
display ISR lands at slot **0x04**, not 0x14.  IVT origin is also
different (`0xF600` or `0xEC00` per `project_rc702_ivt_page_constraint`,
not 0xA000).  See `rcbios-in-c/bios_hw_init.c` lines 79-103 for the
authoritative CP/M-context layout (#101).

| Vector | Offset | Handler | Source |
|--------|--------|---------|--------|
| 0x00 | 0xA000 | DUMINT | Dummy |
| 0x02 | 0xA002 | KBINT | PIO Keyboard |
| 0x04 | 0xA004 | DUMINT | Dummy |
| 0x06 | 0xA006 | DUMINT | Dummy |
| 0x08 | 0xA008 | HDINT | CTC2 Hard Disk (RC703 only) |
| 0x0A | 0xA00A | DUMINT | Dummy |
| 0x0C | 0xA00C | DUMINT | Dummy |
| 0x0E | 0xA00E | DUMINT | Dummy |
| 0x10 | 0xA010 | DUMINT | CTC Channel 0 |
| 0x12 | 0xA012 | DUMINT | CTC Channel 1 |
| 0x14 | 0xA014 | DISINT | CTC Channel 2 Display |
| 0x16 | 0xA016 | FLPINT | CTC Channel 3 Floppy |

---

## RC702E Variant — Memory Disk and SEM702 Character Generator

Source: `roa375/PHE358A.MAC` — a modified autoload PROM by Stig Christensen (24 Oct 1987) for an RC702 variant designated "RC702E". Replaces hard disk (WD1000) boot with memory disk boot and adds character generator loading. See `roa375/PHE358A_ANALYSIS.md` for the full analysis.

### Memory Disk (RAM Disk)

An external RAM disk peripheral accessed via DMA Channel 0 (replacing the WD1000 hard disk).

**I/O Ports:**

```
0xEE  MDTRK (W)  - Track register; writing also clears pending errors
0xEE  MDST  (R)  - Status register
0xEF  MDSEC (W)  - Sector register; writing starts the DMA transfer
```

**Status Register (port 0xEE, read):**
- Bit 0: Parity error
- Bit 1: Busy (transfer in progress)
- Bits 7–2: Number of tracks (value after `AND 0xFC`)

**Disk Geometry:** 1024-byte sectors, 16 sectors per track, variable number of tracks (read from status register). Boot image at track 0, sector 128.

### SEM702 Character Generator

A programmable character generator RAM for the CRT display, loaded at boot from a font PROM at address 0x2000.

**I/O Ports:**

```
0xD1  CHARLN  - Character number (0–127)
0xD2  DOTLN   - Dot line number (0–15)
0xD3  CHARDA  - Character pixel data (8 bits per dot line)
```

**Character Format:** 128 characters × 16 dot lines × 8 pixels = 2048 bytes of font data. Each byte is bit-reversed (MSB↔LSB) during loading, suggesting opposite pixel endianness between the font PROM and the SEM702 hardware.

---

**END OF DOCUMENT**
