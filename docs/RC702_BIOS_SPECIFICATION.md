# RC702 CP/M 2.2 BIOS -- Clean-Room Implementation Specification

**Purpose:** This document specifies the behavior of a CP/M 2.2 BIOS for the
RC702 microcomputer. It is intended to allow a clean-room implementation by
someone without access to existing RC702 BIOS source code or binaries.

**Target:** RC702/RC703 microcomputer (PCB527 mainboard)
**Operating System:** CP/M 2.2 (Digital Research)
**CPU:** Zilog Z80-A at 4 MHz

**Document Version:** 2.0, 2026-04-12

---

## Table of Contents

1. [System Hardware](#1-system-hardware)
2. [Memory Map](#2-memory-map)
3. [I/O Port Map](#3-io-port-map)
4. [Interrupt Architecture](#4-interrupt-architecture)
5. [CP/M BIOS Entry Points](#5-cpm-bios-entry-points)
6. [IOBYTE Device Routing](#6-iobyte-device-routing)
7. [Hardware Initialization](#7-hardware-initialization)
8. [Console Driver (Display + Keyboard)](#8-console-driver)
9. [Serial I/O Driver (Printer, Punch, Reader)](#9-serial-io-driver)
10. [Floppy Disk Driver](#10-floppy-disk-driver)
11. [Hard Disk Driver](#11-hard-disk-driver)
12. [Disk Format Specifications](#12-disk-format-specifications)
13. [Boot Sequence](#13-boot-sequence)
14. [Extended BIOS Entry Points](#14-extended-bios-entry-points)
15. [Character Conversion](#15-character-conversion)
16. [Configuration (Track 0 Layout)](#16-configuration)
17. [Baud Rate Configuration](#17-baud-rate-configuration)
18. [WorkArea Variables (0xFFD0--0xFFFF)](#18-workarea-variables)
19. [JTVARS Runtime ABI](#19-jtvars-runtime-abi)

---

## 1. System Hardware

The RC702 mainboard contains the following chips:

| Chip | Function | I/O Ports |
|------|----------|-----------|
| Z80-A | CPU, 4 MHz | -- |
| Z80-PIO | Parallel I/O (keyboard + parallel port) | 0x10--0x13 |
| Z80-CTC | Counter/Timer (baud rates + interrupts) | 0x0C--0x0F |
| Z80-CTC #2 | Counter/Timer (hard disk interrupt) | 0x44--0x47 |
| Z80-SIO/2 | Serial I/O (console/data + printer/punch) | 0x08--0x0B |
| Am9517A-4 | DMA controller (4 channels) | 0xF0--0xFF |
| uPD765 | Floppy disk controller | 0x04--0x05 |
| Intel 8275 | CRT display controller | 0x00--0x01 |
| WD1000 | Winchester hard disk controller (optional) | 0x60--0x67 |

Additional hardware signals:

| Port | Function |
|------|----------|
| 0x14 | Switch register: bit 7 = drive type (1=mini/5.25", 0=maxi/8"), bit 0 = mini floppy motor control |
| 0x1C | Bell (any write produces an audible beep) |

---

## 2. Memory Map

The BIOS is designed for a 56K CP/M system (64K RAM minus 8K for CCP+BDOS+BIOS).

### Runtime Layout

```
Address     Size    Contents
---------   -----   ------------------------------------------------
0x0000      3       Warm boot vector: JP WBOOT
0x0003      1       IOBYTE (used for device routing; see Section 6)
0x0004      1       CDISK -- current logged-in disk number
0x0005      3       BDOS entry vector: JP BDOS
0x0080      128     Default DMA buffer
0x0100      --      TPA start (Transient Program Area)
0xC400      --      CCP (Console Command Processor)
0xCC06      --      BDOS (Basic Disk Operating System)
0xD480      --      INIT -- hardware initialization code + config tables
0xDA00      --      BIOS -- jump table and driver code
```

### BIOS Variable Area (above code)

```
Address     Size    Contents
---------   -----   ------------------------------------------------
0xEE81      512     HSTBUF -- host disk sector buffer
0xF081      128     DIRBF -- directory scratch area (shared by all drives)
0xF101      --      Allocation and check vectors for all drives
0xF500      250     BGSTAR -- semi-graphics background bit table
0xF600      --      Interrupt vector table (page-aligned, 36 bytes)
              96    Interrupt stack (grows downward from 0xF600)
0xF680      128     OUTCON -- output character conversion table
0xF700      256     INCONV -- input character conversion table
0xF800      2000    DSPSTR -- display refresh memory (80 x 25)
0xFFD0      48      WorkArea -- display control and timer variables
0xFFFC      4       Real-time clock (32-bit counter, 50 Hz tick)
```

---

## 3. I/O Port Map

### PIO (Z80 Parallel I/O)

| Port | Register |
|------|----------|
| 0x10 | Channel A Data (keyboard input) |
| 0x11 | Channel B Data (parallel output) |
| 0x12 | Channel A Control |
| 0x13 | Channel B Control |

### CTC (Z80 Counter/Timer Circuit)

| Port | Channel | Function |
|------|---------|----------|
| 0x0C | CTC Ch.0 | SIO Channel A baud rate generator |
| 0x0D | CTC Ch.1 | SIO Channel B baud rate generator |
| 0x0E | CTC Ch.2 | Display refresh / system tick (50 Hz) |
| 0x0F | CTC Ch.3 | Floppy disk interrupt trigger |

### CTC #2 (hard disk systems only)

| Port | Channel | Function |
|------|---------|----------|
| 0x44 | CTC2 Ch.0 | Hard disk interrupt trigger |
| 0x45 | CTC2 Ch.1 | Unused |
| 0x46 | CTC2 Ch.2 | Unused |
| 0x47 | CTC2 Ch.3 | Unused |

### SIO (Z80 Serial I/O)

| Port | Register |
|------|----------|
| 0x08 | Channel A Data (printer/list device) |
| 0x09 | Channel B Data (console serial / reader/punch) |
| 0x0A | Channel A Control |
| 0x0B | Channel B Control |

Note: After the RC702 SIO role assignment, Channel A serves the printer/data
port (directly connected to a serial printer or external device), while
Channel B serves the terminal/console port (connected to a host computer or
modem). This is the reverse of some documentation that labels Channel A as
"reader/punch" and Channel B as "printer".

### DMA (Am9517A-4)

| Port | Register |
|------|----------|
| 0xF0/0xF1 | Channel 0: Address / Word Count (hard disk) |
| 0xF2/0xF3 | Channel 1: Address / Word Count (floppy disk) |
| 0xF4/0xF5 | Channel 2: Address / Word Count (display data) |
| 0xF6/0xF7 | Channel 3: Address / Word Count (8275 second DMA channel — *roll function*, currently unused; see `docs/dma_ch3_8275_roll_function.md`) |
| 0xF8 | Command/Status Register |
| 0xF9 | Request Register |
| 0xFA | Single Mask Register |
| 0xFB | Mode Register |
| 0xFC | Clear Byte Pointer Flip-Flop |
| 0xFF | All Channel Mask Register |

### Display Controller (Intel 8275)

| Port | Register |
|------|----------|
| 0x00 | Parameter (FIFO read/write) |
| 0x01 | Command/Status |

### Floppy Disk Controller (uPD765)

| Port | Register |
|------|----------|
| 0x04 | Main Status Register (read) |
| 0x05 | Data Register (read/write) |

### Hard Disk Controller (WD1000)

| Port | Read | Write |
|------|------|-------|
| 0x60 | Data | Data |
| 0x61 | Error Register | Write Precompensation |
| 0x62 | Sector Count | Sector Count |
| 0x63 | Sector Number | Sector Number |
| 0x64 | Cylinder Low | Cylinder Low |
| 0x65 | Cylinder High | Cylinder High |
| 0x66 | Size/Drive/Head | Size/Drive/Head |
| 0x67 | Status | Command |

---

## 4. Interrupt Architecture

The Z80 operates in **Interrupt Mode 2**. The I register points to a page
containing an 18-entry vector table (36 bytes, 2 bytes per entry) at address
0xF600:

| Index | Source | Purpose |
|-------|--------|---------|
| 0 | CTC Ch.0 | Dummy (baud rate, no ISR needed) |
| 1 | CTC Ch.1 | Dummy (baud rate, no ISR needed) |
| 2 | CTC Ch.2 | Display refresh + system tick |
| 3 | CTC Ch.3 | Floppy disk operation complete |
| 4 | CTC2 Ch.0 | Hard disk operation complete |
| 5 | CTC2 Ch.1 | Dummy |
| 6 | CTC2 Ch.2 | Dummy |
| 7 | CTC2 Ch.3 | Dummy |
| 8 | SIO Ch.B TX | Console/terminal transmit buffer empty |
| 9 | SIO Ch.B EXT | Console/terminal external status change |
| 10 | SIO Ch.B RX | Console/terminal data received |
| 11 | SIO Ch.B SPEC | Console/terminal special/error |
| 12 | SIO Ch.A TX | Printer/data transmit buffer empty |
| 13 | SIO Ch.A EXT | Printer/data external status change |
| 14 | SIO Ch.A RX | Printer/data receive (ring buffer with RTS flow control) |
| 15 | SIO Ch.A SPEC | Printer/data special/error |
| 16 | PIO Ch.A | Keyboard key pressed |
| 17 | PIO Ch.B | Parallel port ready |

The vector table must be aligned to a 256-byte boundary. Systems without hard
disk omit CTC2 entries 4--7, and the SIO vector base shifts from 0x10 to 0x08
accordingly.

### 4.1 Display Refresh ISR (CTC Ch.2, 50 Hz)

This ISR is called at the display vertical retrace rate (50 Hz). It must
execute the following sequence with interrupts disabled:

1. **Read 8275 status register** (port 0x01) to acknowledge the interrupt.

2. **Reprogram DMA channels 2 and 3** for the next display frame:
   - Mask DMA channel 2: OUT (0xFA), 0x06
   - Mask DMA channel 3: OUT (0xFA), 0x07
   - Clear byte pointer flip-flop: OUT (0xFC), any
   - Set channel 2 address to 0xF800 (display buffer):
     OUT (0xF4), 0x00; OUT (0xF4), 0xF8
   - Set channel 2 word count to 1999 (0x07CF):
     OUT (0xF5), 0xCF; OUT (0xF5), 0x07
   - Set channel 3 word count to 0:
     OUT (0xF7), 0x00; OUT (0xF7), 0x00
   - Unmask channel 2: OUT (0xFA), 0x02
   - Unmask channel 3: OUT (0xFA), 0x03

3. **Update cursor position** on the 8275 (if changed since last frame):
   - OUT (0x01), 0x80 (Load Cursor command)
   - OUT (0x00), curx (column 0--79)
   - OUT (0x00), cursy (row 0--24)

4. **Reprogram CTC Ch.2** for the next interrupt:
   - OUT (0x0E), 0xD7 (counter mode, interrupt enabled)
   - OUT (0x0E), 0x01 (count 1)

5. **Increment the 32-bit real-time clock** at 0xFFFC--0xFFFF (low word
   first, carry into high word).

6. **Decrement timer variables** (each 20 ms per tick):
   - TIMER1 (0xFFDF): general-purpose exit timer. When it reaches zero,
     the BIOS must call the function at WARMJP (0xFFE5).
   - TIMER2 (0xFFE1): floppy motor-off timer. When it reaches zero, the
     BIOS must stop the floppy motor (OUT (0x14), 0x00).
   - DELCNT (0xFFE3): general delay timer. Decremented unconditionally;
     main code busy-waits on this reaching zero.

### 4.2 Floppy ISR (CTC Ch.3)

The BIOS must:
1. Set a completion flag to 0xFF.
2. After a short delay (5 iterations), check the FDC main status register
   (port 0x04) bit 4 (CB = controller busy):
   - If CB is set: the FDC is in result phase. Read all 7 result bytes
     (ST0, ST1, ST2, C, H, R, N) from port 0x05, checking CB between
     each byte to detect early termination.
   - If CB is clear: execute SENSE INTERRUPT STATUS (command 0x08) and
     read the 2-byte result (ST0, PCN).

### 4.3 Hard Disk ISR (CTC2 Ch.0)

Set a flag indicating the hard disk operation has completed. Also read and
save the WD1000 status and error registers.

### 4.4 Keyboard ISR (PIO Ch.A)

Read the key code from PIO Port A data (port 0x10) and store it in a
16-entry ring buffer (see Section 8.2).

### 4.5 SIO Channel A RX ISR (Printer/Data Port)

Read the received byte from port 0x08 and store it in a 256-byte ring
buffer. If the buffer fill level reaches 248 bytes (RXBUFSZ - 8), deassert
RTS to pause the sender (see Section 9.4 for flow control details).

### 4.6 SIO Channel B RX ISR (Console/Terminal Port)

Read the received byte from port 0x09 and store it in a 256-byte ring
buffer. No RTS flow control is applied on this channel.

### 4.7 SIO TX ISRs (Channels A and B)

Reset the TX interrupt pending condition (write 0x28 to the SIO control
port) and set the corresponding ready flag to 0xFF.

### 4.8 SIO External Status ISRs (Channels A and B)

Read and cache RR0, then write 0x10 to the SIO control port to reset the
external/status interrupt condition.

### 4.9 SIO Special Condition ISRs (Channels A and B)

Read RR1 (select register 1, then read control port), cache it, then
write 0x30 to the control port to reset the error condition. On Channel B,
the ring buffer head and tail pointers must be reset to zero (flushing the
buffer on error).

---

## 5. CP/M BIOS Entry Points

The BIOS provides a jump table at its base address (0xDA00 for 56K):

| Offset | Name | Parameters | Returns | Function |
|--------|------|-----------|---------|----------|
| +0x00 | BOOT | -- | -- | Cold boot |
| +0x03 | WBOOT | -- | -- | Warm boot |
| +0x06 | CONST | -- | A=0xFF if char ready, 0 if not | Console status |
| +0x09 | CONIN | -- | A=character | Console input (waits) |
| +0x0C | CONOUT | C=character | -- | Console output |
| +0x0F | LIST | C=character | -- | Printer output |
| +0x12 | PUNCH | C=character | -- | Punch output (SIO Ch.A TX) |
| +0x15 | READER | -- | A=character | Reader input (SIO Ch.A RX) |
| +0x18 | HOME | -- | -- | Home disk (seek track 0) |
| +0x1B | SELDSK | C=disk number | HL=DPH address, or 0 if error | Select disk |
| +0x1E | SETTRK | BC=track number | -- | Set track |
| +0x21 | SETSEC | BC=sector number | -- | Set sector |
| +0x24 | SETDMA | BC=DMA address | -- | Set DMA address |
| +0x27 | READ | -- | A=0 success, 1 error | Read sector |
| +0x2A | WRITE | C=write type (0,1,2) | A=0 success, 1 error | Write sector |
| +0x2D | LISTST | -- | A=0xFF if ready, 0 if busy | Printer status |
| +0x30 | SECTRAN | BC=logical sector, DE=XLT table | HL=physical sector | Sector translate |

---

## 6. IOBYTE Device Routing

The RC702 BIOS implements full IOBYTE routing as defined in CP/M 2.2
Table 6-4. The IOBYTE at address 0x0003 controls how the four logical
devices (CON:, RDR:, PUN:, LST:) are mapped to physical hardware.

### 6.1 IOBYTE Bit Field Layout

```
  Bit 7  Bit 6  Bit 5  Bit 4  Bit 3  Bit 2  Bit 1  Bit 0
  +------+------+------+------+------+------+------+------+
  |  LST field   |  PUN field   |  RDR field   |  CON field   |
  +------+------+------+------+------+------+------+------+
```

Each 2-bit field selects one of four physical device assignments:

| Value | CP/M Name | CON: | RDR: | PUN: | LST: |
|-------|-----------|------|------|------|------|
| 0 | TTY | SIO-B serial | SIO-A (PTR) | SIO-A (PTP) | SIO-B (TTY) |
| 1 | CRT | CRT display+kbd | SIO-A (PTR) | SIO-A (PTP) | CRT display |
| 2 | BAT | Batch (RDR:/LST:) | SIO-B (UR1) | SIO-B (UP1) | SIO-A (LPT) |
| 3 | UC1 | SIO-B + CRT joined | -- | -- | -- |

### 6.2 CON: Device Modes

The CON: field (bits 1:0) controls console input and output:

- **TTY (0):** Input from SIO-B serial only. Output to SIO-B serial only,
  but the CRT display is also updated (TTY falls through to CRT output).
- **CRT (1):** Input from keyboard only. Output to CRT display only.
- **BAT (2):** Batch mode. BDOS routes input to RDR: and output to LST:.
  BIOS treats CON: output as LIST.
- **UC1 (3):** Joined mode (RC702 extension). Input from keyboard OR SIO-B
  serial, whichever has data first. Output to both SIO-B serial and CRT
  display simultaneously. This is the default mode when a remote host is
  detected at cold boot.

Encoding rule: keyboard input is allowed when `(CON_field & 1)` is true
(CRT and UC1 modes). Serial input is allowed when `CON_field != 1`
(TTY, BAT, and UC1 modes).

### 6.3 LST: Device Modes

The LST: field (bits 7:6) controls printer output:

| Value | Target |
|-------|--------|
| 0 (TTY) | SIO-B serial (console port) |
| 1 (CRT) | CRT display (CONOUT) |
| 2 (LPT) | SIO-A (data/printer port) |
| 3 (UL1) | Parked (no output) |

### 6.4 PUN: Device Modes

The PUN: field (bits 5:4) controls punch output:

| Value | Target |
|-------|--------|
| 0 (TTY) | SIO-A (data port, PTP) |
| 1 (CRT) | SIO-A (data port, PTP) -- same as TTY |
| 2 (BAT) | SIO-B (console port, UP1, shared with LST:LPT flag) |
| 3 (UC1) | Parked (no output) |

### 6.5 RDR: Device Modes

The RDR: field (bits 3:2) controls reader input:

| Value | Target |
|-------|--------|
| 0 (TTY) | SIO-A ring buffer (PTR, with RTS flow control) |
| 1 (CRT) | SIO-A ring buffer (PTR) -- same as TTY |
| 2 (BAT) | SIO-B ring buffer (UR1, no RTS flow control) |
| 3 (UC1) | Parked (returns 0x1A = EOF) |

### 6.6 LISTST Return Values

The LISTST entry point returns status based on the current LST: assignment:

| LST: mode | Returns |
|-----------|---------|
| TTY (0) | SIO-B TX ready flag (0xFF=ready, 0x00=busy) |
| CRT (1) | Always 0xFF (CRT is always ready) |
| LPT (2) | SIO-A TX ready flag (0xFF=ready, 0x00=busy) |
| UL1 (3) | Always 0x00 (parked) |

### 6.7 Default IOBYTE Values

The BIOS defines two preset IOBYTE values:

| Value | Name | Meaning |
|-------|------|---------|
| 0x97 | Joined | CON:=UC1(3), RDR:=PTR(1), PUN:=PTP(1), LST:=LPT(2) |
| 0x95 | Local | CON:=CRT(1), RDR:=PTR(1), PUN:=PTP(1), LST:=LPT(2) |

Breaking down 0x97 = 0b10010111:
- LST: bits 7:6 = 10 = LPT (SIO-A printer)
- PUN: bits 5:4 = 01 = PTP (SIO-A)
- RDR: bits 3:2 = 01 = PTR (SIO-A)
- CON: bits 1:0 = 11 = UC1 (joined SIO-B + CRT)

Breaking down 0x95 = 0b10010101:
- LST: bits 7:6 = 10 = LPT (SIO-A printer)
- PUN: bits 5:4 = 01 = PTP (SIO-A)
- RDR: bits 3:2 = 01 = PTR (SIO-A)
- CON: bits 1:0 = 01 = CRT (local display only)

### 6.8 DCD Auto-Detection at Cold Boot

At cold boot, the BIOS must read SIO-B RR0 (port 0x0B) and test bit 3
(DCD). On the Z80-SIO, RR0 bit 3 has **inverted polarity**: the bit is
set (1) when DCD is asserted (carrier detected).

- If DCD is asserted (bit 3 = 1): a remote host is connected. The BIOS
  must set IOBYTE = 0x97 (joined mode, console on both CRT and serial).
- If DCD is deasserted (bit 3 = 0): no host connected. The BIOS must set
  IOBYTE = 0x95 (local CRT only).

The warm boot procedure must NOT clear or reset IOBYTE. This preserves
any runtime changes made by `STAT CON:=TTY:` or similar commands across
warm boots.

---

## 7. Hardware Initialization

The BIOS initialization code runs once at cold boot and must configure all
hardware in the following order. All values shown are the defaults from the
configuration block; the actual values must be read from the disk-resident
configuration (see Section 16).

### 7.1 Interrupt Vector Table

Before any device initialization, the BIOS must:
1. Copy the 18-entry ISR vector table to address 0xF600 (page-aligned).
2. Set the Z80 I register to 0xF6.
3. Execute IM 2 to enable interrupt mode 2.

### 7.2 PIO Initialization

The interrupt vector must be written BEFORE the mode word. This is required
by the Z80-PIO protocol: the first byte written to the control port after
reset that has bit 0 = 0 is interpreted as a vector, and subsequent bytes
with specific patterns set the mode.

| Step | Port | Value | Purpose |
|------|------|-------|---------|
| 1 | 0x12 | 0x20 | Channel A: set interrupt vector (0x20) |
| 2 | 0x13 | 0x22 | Channel B: set interrupt vector (0x22) |
| 3 | 0x12 | 0x4F | Channel A: input mode |
| 4 | 0x13 | 0x0F | Channel B: output mode |
| 5 | 0x12 | 0x83 | Channel A: enable interrupts |
| 6 | 0x13 | 0x83 | Channel B: enable interrupts |

### 7.3 CTC Initialization

CTC Ch.0 receives the interrupt vector base first (0x00), then each channel
gets a mode byte followed by a time constant byte:

| Channel | Mode | Count | Purpose |
|---------|------|-------|---------|
| Ch.0 | 0x47 | 0x01 | Timer mode, 38400 baud for SIO Ch.A |
| Ch.1 | 0x47 | 0x01 | Timer mode, 38400 baud for SIO Ch.B |
| Ch.2 | 0xD7 | 0x01 | Counter mode, display refresh trigger |
| Ch.3 | 0xD7 | 0x01 | Counter mode, floppy interrupt trigger |

CTC mode byte encoding:
- 0x47 = timer mode, interrupt disabled, auto trigger, time constant follows,
  prescaler divide-by-16
- 0xD7 = counter mode, interrupt enabled, auto trigger, time constant follows,
  rising edge

The CTC interrupt vector base (written to Ch.0 before its mode byte) must
be 0x00 so that CTC channels 0--3 generate vectors 0x00, 0x02, 0x04, 0x06
into the table at page 0xF6.

### 7.4 SIO Initialization

Each channel is programmed by writing a sequence of register-number/value
pairs to the control port. The channel reset command (0x18 to WR0) is sent
first, which does not require a register select prefix.

**Channel A (Printer/Data Port, control port 0x0A), 9 bytes:**

| Byte | Value | Meaning |
|------|-------|---------|
| 0 | 0x18 | WR0: channel reset |
| 1 | 0x04 | WR0: select WR4 |
| 2 | 0x44 | WR4: x16 clock, 1 stop bit, no parity |
| 3 | 0x03 | WR0: select WR3 |
| 4 | 0xE1 | WR3: RX enable, auto enables, 8 bits/char |
| 5 | 0x05 | WR0: select WR5 |
| 6 | 0x60 | WR5: 8 bits TX, TX disabled, DTR off, RTS off |
| 7 | 0x01 | WR0: select WR1 |
| 8 | 0x1B | WR1: RX int (all chars), TX int, ext/status int enabled |

**Channel B (Console/Terminal Port, control port 0x0B), 11 bytes:**

| Byte | Value | Meaning |
|------|-------|---------|
| 0 | 0x18 | WR0: channel reset |
| 1 | 0x02 | WR0: select WR2 |
| 2 | 0x10 | WR2: interrupt vector base 0x10 |
| 3 | 0x04 | WR0: select WR4 |
| 4 | 0x44 | WR4: x16 clock, 1 stop bit, no parity |
| 5 | 0x03 | WR0: select WR3 |
| 6 | 0xE1 | WR3: RX enable, auto enables, 8 bits/char |
| 7 | 0x05 | WR0: select WR5 |
| 8 | 0x60 | WR5: 8 bits TX, TX disabled, DTR off, RTS off |
| 9 | 0x01 | WR0: select WR1 |
| 10 | 0x1F | WR1: RX int (all), TX int, ext/status int, status affects vector, parity is special condition |

Channel B has 2 additional bytes because it carries the shared interrupt
vector in WR2 (only Channel B's WR2 is used by the SIO; Channel A's WR2
is not accessible). The vector base 0x10 offsets the SIO vectors past the
CTC and CTC2 entries in the interrupt vector table. With "status affects
vector" enabled in WR1, the SIO modifies bits 3:1 of the vector to encode
the interrupt source (TX empty, ext status, RX available, or special
condition).

After programming both channels, the BIOS must read the initial status
registers to clear any pending conditions:
- Read RR0-A (port 0x0A)
- Select RR1-A: OUT (0x0A), 0x01; read port 0x0A
- Read RR0-B (port 0x0B)
- Select RR1-B: OUT (0x0B), 0x01; read port 0x0B

### 7.5 DMA Initialization

| Step | Port | Value | Purpose |
|------|------|-------|---------|
| 1 | 0xF8 | 0x20 | Master clear (reset all channels) |
| 2 | 0xFB | 0x48 | Channel 0 mode: single, mem-to-IO (hard disk) |
| 3 | 0xFB | 0x4A | Channel 2 mode: single, mem-to-IO (display data) |
| 4 | 0xFB | 0x4B | Channel 3 mode: single, mem-to-IO (display attributes) |

Note: DMA channel 1 (floppy) is not configured here. It is programmed
per-operation by the floppy disk driver with the appropriate direction
(read or write).

### 7.6 FDC Initialization

Wait for the FDC main status register (port 0x04) to show all drives idle
(bits 4:0 = 0), then send the SPECIFY command (0x03) followed by two
parameter bytes:

| Byte | Value | Meaning |
|------|-------|---------|
| Command | 0x03 | SPECIFY |
| SRT/HUT | 0xDF | Step Rate Time = 3 ms, Head Unload Time = 240 ms |
| HLT/DMA | 0x28 | Head Load Time = 40 ms, DMA mode |

For mini (5.25") drives, the SRT byte must be changed to 0x0F (slower
stepping rate appropriate for 5.25" mechanisms).

Wait for the FDC main status register (port 0x04) to show RQM=1, DIO=0
before sending each byte.

### 7.7 Display Controller (8275) Initialization

| Step | Action | Port | Value |
|------|--------|------|-------|
| 1 | Clear display buffer | -- | Fill 0xF800 with 0x20 (space), 2000 bytes |
| 2 | Clear WorkArea | -- | Zero bytes from 0xFFD1 through 0xFFFF |
| 3 | Reset | 0x01 | 0x00 |
| 4 | Parameter 1 | 0x00 | 0x4F (80 characters per row) |
| 5 | Parameter 2 | 0x00 | 0x98 (25 rows, VRTC timing) |
| 6 | Parameter 3 | 0x00 | 0x7A (28 H retrace chars, 4 V retrace lines) |
| 7 | Parameter 4 | 0x00 | 0x6D (7 scan lines/char, steady block cursor) |
| 8 | Load Cursor | 0x01 | 0x80 |
| 9 | Cursor X | 0x00 | 0x00 |
| 10 | Cursor Y | 0x00 | 0x00 |
| 11 | Preset counters | 0x01 | 0xE0 |
| 12 | Start display | 0x01 | 0x23 |

8275 Parameter byte encoding:
- PAR1 (0x4F): (value & 0x7F) + 1 = 80 characters per row
- PAR2 (0x98): (value & 0x3F) + 1 = 25 rows; bits 7:6 = VRTC timing
- PAR3 (0x7A): bits 4:0 = (0x1A) + 2 = 28 H retrace characters;
  bits 7:5 = (3) + 1 = 4 V retrace scan lines
- PAR4 (0x6D): bits 7:4 = (6) + 1 = 7 scan lines per character row;
  bits 3:2 = underline position; bits 1:0 = cursor format (01 = blinking
  block, 10 = steady underline, 11 = steady block; 0x6D uses 01 = steady block)

### 7.8 Runtime Variable Initialization

After hardware setup, the BIOS must initialize runtime variables from the
configuration block:

- Copy WR5 bits/char mask from SIO-A config byte 6: extract bits 6:5
  (value & 0x60) and store in JTVARS.wr5a.
- Copy WR5 bits/char mask from SIO-B config byte 8: extract bits 6:5
  (value & 0x60) and store in JTVARS.wr5b.
- Copy cursor addressing mode from config to JTVARS.adrmod.
- Copy motor timer reload value from config to WorkArea.stptim_var.
- Copy drive format table (16 entries + terminator) from config to
  JTVARS.fd0[].

### 7.9 Disk Subsystem Initialization

For each configured floppy drive:
1. Allocate a Disk Parameter Header (DPH) with:
   - XLT = NULL (translation done internally by SELDSK)
   - DIRBF = shared 128-byte directory buffer
   - DPB = pointer to the 8" DD DPB (default; updated by SELDSK)
   - CSV = per-drive check vector (32 bytes each)
   - ALV = per-drive allocation vector (71 bytes each)
2. Clear all disk state: HSTACT=0, HSTWRT=0, UNACNT=0, ERFLAG=0.
3. Set the format cache to 0xFF (force reload on first SELDSK).
4. Set the last-disk tracker to 0xFF (force seek on first access).

---

## 8. Console Driver

### 8.1 Display Output (CONOUT)

Characters are written to the display buffer at DSPSTR (0xF800). The display
ISR refreshes the physical screen from this buffer via DMA at 50 Hz.

CONOUT processing depends on the IOBYTE CON: field (see Section 6.2):
- **TTY (0):** Send to SIO-B serial, then fall through to CRT display.
- **CRT (1):** Process on CRT display only.
- **BAT (2):** Send to LIST device.
- **UC1 (3):** Send to SIO-B serial, then process on CRT display.

For CRT display output, the character is dispatched as follows:
1. If the XY escape state machine is active (state != 0), process as an
   XY coordinate byte (see Section 8.3).
2. If the character is 0x00--0x1F: dispatch as a control character (see
   Section 8.4).
3. Otherwise (0x20--0xFF): display as a printable character (see below).

**Printable character processing (0x20--0xFF):**

The character encoding for the Intel 8275 CRT controller uses the following
ranges:
- 0xC0--0xFF: folded to 0x00--0x3F (the 8275 character ROM uses 7 address
  bits, so codes 192--255 map to the same glyphs as 0--63).
- 0x80--0xBF: semi-graphics control codes. Bit 2 of the value sets or
  clears a sticky "graphics mode" flag. When graphics mode is active,
  subsequent characters in the 0x00--0x7F range bypass the output
  conversion table.
- 0x00--0x7F: normal characters. Unless graphics mode is active, the
  character must be passed through the output conversion table (OUTCON at
  0xF680) before writing to display memory.

After writing the converted character to the display buffer at offset
(cury + curx), the cursor must advance right (see cursor_right behavior in
Section 8.4).

**Cursor position update:**

To minimize I/O overhead, cursor position changes must set a dirty flag
rather than immediately programming the 8275. The display ISR checks this
flag and sends the Load Cursor command (0x80) with the current curx/cursy
values only when the flag is set.

### 8.2 Keyboard Input (CONIN / CONST)

The keyboard sends 8-bit character codes via PIO Channel A. When a key is
pressed, the PIO triggers an interrupt (ASTB strobe). The ISR reads the key
code from port 0x10 and stores it in a 16-entry circular ring buffer.

**Ring buffer specification:**
- Size: 16 entries (KBBUFSZ = 16)
- Index mask: 0x0F (KBMASK = KBBUFSZ - 1)
- Write pointer (head): incremented by ISR after storing a byte
- Read pointer (tail): incremented by CONIN after consuming a byte
- Overflow: if `(head + 1) & KBMASK == tail`, the keystroke is silently
  discarded (buffer full).
- Status byte: set to 0xFF when data is available (head != tail), 0x00
  when empty.

CONST returns 0xFF if either keyboard data or serial data is available
(depending on IOBYTE CON: mode). CONIN waits in a HALT loop until data is
available from the appropriate source(s), then returns the character after
passing it through the input conversion table (INCONV at 0xF700). The
returned character has bit 7 cleared (7-bit ASCII).

For UC1 (joined) mode, CONIN must check both the keyboard buffer and the
SIO-B receive buffer on each iteration and return whichever has data first.

### 8.3 XY Cursor Addressing (Escape Sequence)

The control character 0x06 (ACK) initiates XY cursor addressing mode. The
BIOS enters a state machine that collects the next two bytes as cursor
coordinates:

- **State 0:** Normal character processing.
- **State 2:** Entered when 0x06 is received. The next byte is the first
  coordinate. Store it, decrement state to 1.
- **State 1:** The next byte is the second coordinate. Compute final
  position, return to state 0.

Each coordinate byte is decoded as: `(byte & 0x7F) - 32`, giving a range
of 0--95 (excess values are wrapped using modular arithmetic: values >= 80
for columns wrap by subtracting 80, values >= 25 for rows wrap by
subtracting 25).

The addressing mode variable ADRMOD (in JTVARS, see Section 19) selects
coordinate order:
- ADRMOD = 0 (XY mode): first byte = column, second byte = row (default).
- ADRMOD = 1 (YX mode): first byte = row, second byte = column.

After both coordinates are received, the BIOS must set curx, cursy, and
cury (= cursy * 80) to the new position and mark the cursor dirty.

### 8.4 Control Character Dispatch Table

When a character in the range 0x00--0x1F is received (and the XY state
machine is not active), the BIOS must reset the XY state to 0 and dispatch
based on the character code:

| Code | Name | Action |
|------|------|--------|
| 0x01 | SOH | Insert line at cursor row; shift rows below down by one |
| 0x02 | STX | Delete line at cursor row; shift rows below up by one |
| 0x05 | ENQ | Cursor left (same as BS) |
| 0x06 | ACK | Enter XY addressing mode (next 2 bytes are coordinates) |
| 0x07 | BEL | Sound bell (write any value to port 0x1C) |
| 0x08 | BS | Cursor left: decrement column; if at column 0, wrap to column 79 of previous row; if at row 0 column 0, wrap to row 24 column 79 |
| 0x09 | TAB | Move cursor right 4 positions (4 consecutive cursor-right operations) |
| 0x0A | LF | Cursor down: move to next row; if at row 24, scroll display up |
| 0x0C | FF | Clear screen: fill display buffer with spaces (0x20), home cursor to (0,0), clear background bitmap |
| 0x0D | CR | Move cursor to column 0 of current row |
| 0x13 | DC3 | Enter background mode: set background flag to 2, clear entire background bitmap to zero |
| 0x14 | DC4 | Enter foreground mode: set background flag to 1 |
| 0x15 | NAK | Clear foreground: erase screen positions where the background bitmap bit is NOT set (replace with space) |
| 0x18 | CAN | Cursor right: increment column; if past column 79, wrap to column 0 of next row; if at row 24 column 79, wrap and scroll |
| 0x1A | SUB | Cursor up: move to previous row; if at row 0, wrap to row 24 |
| 0x1D | GS | Home cursor to row 0, column 0 |
| 0x1E | RS | Erase from cursor to end of line (fill with spaces) |
| 0x1F | US | Erase from cursor to end of screen (fill with spaces) |

All other codes in the 0x00--0x1F range must be silently ignored.

**Scrolling:**

When the cursor moves below row 24 (the last row), the BIOS must scroll
the entire display up by one line: copy rows 1--24 to rows 0--23, then
clear row 24 (fill with spaces). The background bitmap (BGSTAR) must be
scrolled in the same manner if background mode is active.

**Background mode (BGSTAR):**

The BIOS maintains a 250-byte bitmap (80 * 25 / 8 = 250 bytes, 10 bytes
per row) that tracks which screen positions have been written in background
mode. When background mode is active (flag = 2), each character written to
the display also sets the corresponding bit in the bitmap. The
clear-foreground operation (0x15) erases only positions where the bit is
NOT set, preserving background content.

**Insert line (0x01):**

Shift rows from the cursor row through row 23 down by one row (backward
copy, destination = source + 80). Clear the cursor row with spaces. If
background mode is active, shift the corresponding bitmap rows and clear the
cursor row's bitmap bits.

**Delete line (0x02):**

Shift rows from cursor row + 1 through row 24 up by one row (forward copy).
Clear row 24 with spaces. If background mode is active, shift the
corresponding bitmap rows and clear row 24's bitmap bits.

---

## 9. Serial I/O Driver

### 9.1 Printer (LIST / LISTST)

The LIST entry point routes output based on the IOBYTE LST: field (see
Section 6.3).

When sending to SIO-A (LPT mode):
1. Wait for the SIO-A TX ready flag to become 0xFF.
2. With interrupts disabled:
   - Clear the ready flag to 0x00 (busy).
   - Write WR5 to SIO-A control port: select register 5 (OUT 0x0A, 0x05),
     then write (wr5a + 0x8A) where 0x8A = DTR + TX enable + RTS.
   - Write WR1: select register 1 (OUT 0x0A, 0x01), then write 0x1B
     (RX + TX + ext status interrupts).
   - Write the character to port 0x08 (SIO-A data).
3. Re-enable interrupts.

When sending to SIO-B (TTY mode), the same procedure is used with the
SIO-B ports and wr5b instead of wr5a.

LISTST returns the appropriate ready flag based on the current LST: mode
(see Section 6.6).

### 9.2 Punch (PUNCH)

The PUNCH entry point routes output based on the IOBYTE PUN: field (see
Section 6.4). The protocol for SIO-A transmission is identical to LIST/LPT
(Section 9.1). For BAT mode (UP1), the output is sent via SIO-B using the
LPT routine with the SIO-B ready flag.

### 9.3 Reader (READER / READS)

The READER entry point reads from the appropriate ring buffer based on the
IOBYTE RDR: field (see Section 6.5):

**PTR mode (SIO-A, with RTS flow control):**
1. Wait for data in the 256-byte SIO-A ring buffer (busy-wait until
   tail != head).
2. Read the character at the tail index and advance tail:
   `new_tail = (tail + 1) & 0xFF`.
3. **Reassert RTS only when the buffer becomes completely empty**
   (`new_tail == head`). This conservative strategy ensures that the
   sender pauses long enough for disk I/O operations (e.g., PIP file
   transfers) to complete before more data arrives.
4. Return the character.

**UR1 mode (SIO-B, no flow control):**
1. Wait for data in the SIO-B ring buffer.
2. Read and advance tail as above.
3. Return the character (no RTS management).

**UR2 mode:** Return 0x1A (CP/M EOF marker).

READS returns 0xFF if a character is available in the appropriate ring
buffer, 0x00 if empty.

### 9.4 SIO-A RTS Flow Control

The SIO-A receiver uses hardware RTS flow control with a 256-byte ring
buffer:

| Parameter | Value |
|-----------|-------|
| Buffer size | 256 bytes (RXBUFSZ) |
| Index mask | 0xFF (RXMASK) |
| High-water mark | 248 bytes used (RXBUFSZ - 8) |
| Low-water reassert | When buffer becomes empty |

**Deassert RTS:** When the ISR detects that the buffer fill level has
reached 248 bytes (or the buffer is full), it must deassert RTS by writing
WR5 with the RTS bit cleared: select register 5, then write
(wr5a + 0x88) where 0x88 = DTR + TX enable (no RTS).

**Reassert RTS:** The main-line READER code reasserts RTS only when the
buffer has been completely drained (tail catches up to head), by writing
WR5 with RTS set: select register 5, then write (wr5a + 0x8A) where
0x8A = DTR + TX enable + RTS.

### 9.5 WR5 Value Construction

The WR5 register value is constructed at runtime by adding signal control
bits to the stored bits/char mask:

| Purpose | Base (wr5a/wr5b) | Added bits | Result |
|---------|-------------------|------------|--------|
| TX with DTR + RTS | 0x60 (8-bit) | 0x8A | 0xEA |
| TX with DTR only (no RTS) | 0x60 (8-bit) | 0x88 | 0xE8 |
| Line release | 0x00 | 0x00 | 0x00 |

WR5 bit assignments: bit 7 = DTR, bit 6:5 = TX bits/char, bit 4 = send
break, bit 3 = TX enable, bit 1 = RTS.

### 9.6 Serial Configuration

Default configuration for both SIO channels: **38400 baud, 8 data bits,
no parity, 1 stop bit** (8N1).

The baud rate is generated by CTC channels 0 and 1 with a count of 0x01
(divisor 1) and SIO WR4 clock mode x16 (0x44), giving
614400 / (1 * 16) = 38400 baud. See Section 17 for the baud rate formula
and available rates.

### 9.7 SIO-B Console Serial Output

When the IOBYTE CON: field is TTY (0) or UC1 (3), CONOUT must also send
the character to SIO-B. The BIOS must use a non-blocking timeout: if the
SIO-B TX ready flag does not become set within 255 polling iterations, the
serial output is skipped (the CRT echo still shows the character). This
prevents a disconnected serial cable from hanging the system.

The transmission uses the same WR5 construction as Section 9.5, with wr5b
as the base and SIO-B ports (0x0B for control, 0x09 for data). WR1 must be
set to 0x1F (all interrupts + status affects vector) to match the Channel B
interrupt configuration.

---

## 10. Floppy Disk Driver

### 10.1 Sector Deblocking

CP/M operates on 128-byte logical sectors. The RC702 floppy formats use
256-byte or 512-byte physical sectors. The BIOS uses the standard Digital
Research blocking/deblocking algorithm from the **CP/M 2.2 Alteration Guide**
(Appendix G: "Blocking and Deblocking"). This is not RC702-specific -- the
algorithm, variable names (HSTBUF, HSTACT, HSTWRT, UNACNT, UNADSK, etc.),
and write-type semantics are taken directly from the DR sample code.

The algorithm maintains a single host-sector buffer (HSTBUF, 512 bytes):

1. **READ:** If the requested host sector is already in HSTBUF, copy the
   appropriate 128-byte portion to the DMA buffer. Otherwise, read the
   physical sector into HSTBUF first.
2. **WRITE:** Write the 128-byte data into the appropriate portion of
   HSTBUF. If the host sector changed, flush the previous sector to disk
   first. Flush is deferred until a different sector is needed (write-back
   caching).
3. **Write types:** Type 0 = deferred write, Type 1 = directory write
   (flush immediately), Type 2 = first sector of unallocated block (no
   pre-read needed).

Refer to the CP/M 2.2 Alteration Guide for the complete algorithm. An
implementor should use the DR sample code directly and adapt only the
physical disk read/write routines for the RC702 hardware.

### 10.2 SELDSK Format Dispatch

When SELDSK is called, the BIOS must look up the drive's format code from
the JTVARS fd0[] table (see Section 19) and select the appropriate format
descriptor chain:

1. Read fd0[drive_number]. If the value is 0xFF, the drive is not configured;
   return 0 (error).
2. Compute the format index: `idx = (format_code >> 3) & 3`.
3. Select the FSPA (Floppy System Parameters) entry at index `idx`.
4. Select the FDF (Floppy Disk Format) entry at index `idx`.
5. Copy the FSPA fields to working variables (DPB pointer, records per block,
   CP/M sectors per track, sector mask, sector shift, translation table
   pointer, data length value, disk type).
6. Update the DPH's DPB pointer to match the selected format.
7. If the format changed since the last SELDSK call, flush any dirty host
   buffer before switching.

**Format code encoding:**

| Code | Index | Format |
|------|-------|--------|
| 0 | 0 | 8" SS 128 B/S (FM, single density) |
| 8 | 1 | 8" DD 512 B/S (MFM, double density) |
| 16 | 2 | 5.25" DD 512 B/S (MFM, data tracks) |
| 24 | 3 | 8" DD 256 B/S (MFM, Track 0 Side 1) |
| 32+ | -- | Hard disk partitions (not covered by floppy driver) |

### 10.3 Multi-Density Track Handling

Each disk has an "end of track" value (EOT) from the FDF that defines the
boundary between head 0 and head 1 sectors. When mapping a host sector
number to physical parameters:

- If host sector < EOT: head 0, physical sector = translation_table[host_sector].
- If host sector >= EOT: head 1, physical sector = translation_table[host_sector - EOT].

The drive/head select byte encodes: bits 1:0 = drive number, bit 2 = head
number (0 or 1).

### 10.4 FDC Commands

All FDC communication follows the uPD765 protocol:

**Sending a command byte:**
1. Read main status register (port 0x04)
2. Wait until RQM=1 and DIO=0 (value 0x80 masked with 0xC0)
3. Write command byte to data register (port 0x05)

**Reading a result byte:**
1. Read main status register (port 0x04)
2. Wait until RQM=1 and DIO=1 (value 0xC0 masked with 0xC0)
3. Read data register (port 0x05)
4. Continue reading while CB (bit 4) is set in the main status register

**Read/Write command sequence (9 bytes out, 7 bytes result):**
```
Byte 1: Command + MF flag (0x46 = read MFM, 0x45 = write MFM,
                            0x06 = read FM, 0x05 = write FM)
Byte 2: Head/Drive select (bits 2-0 = drive, bit 2 = head)
Byte 3: Cylinder number
Byte 4: Head number
Byte 5: Sector number (1-based)
Byte 6: Sector size code (N: 0=128, 1=256, 2=512)
Byte 7: End of track (last sector number on track)
Byte 8: Gap length
Byte 9: Data length (0xFF for 256/512-byte, 0x80 for FM 128-byte)
```

**Result bytes:** ST0, ST1, ST2, C, H, R, N

### 10.5 DMA Setup for Floppy

- **DMA Channel:** 1
- **Read (disk to memory):** Mode 0x45 (single transfer, IO-to-mem, channel 1)
- **Write (memory to disk):** Mode 0x49 (single transfer, mem-to-IO, channel 1)

Setup sequence:
1. Mask channel 1: OUT (0xFA), 0x05
2. Set mode: OUT (0xFB), mode
3. Clear byte pointer: OUT (0xFC), any
4. Set address: OUT (0xF2), addr_low; OUT (0xF2), addr_high
5. Set count: OUT (0xF3), count_low; OUT (0xF3), count_high
6. Unmask channel 1: OUT (0xFA), 0x01

### 10.6 Motor Control (5.25" Mini Floppy Only)

Mini floppy drives require software motor control via port 0x14 bit 0:
- **Motor on:** OUT (0x14), 0x01; wait 1 second (50 ticks at 50 Hz via
  DELCNT)
- **Motor off:** OUT (0x14), 0x00
- **Auto-off timer:** Configurable via STPTIM_VAR (default 250 ticks =
  5 seconds of inactivity, via TIMER2)

If the motor is already running (TIMER2 != 0), the BIOS must reload the
timer with the configured timeout value but skip the spinup delay.

Maxi (8") drives have always-on motors; the BIOS must check port 0x14
bit 7 and skip motor control if it reads 0 (maxi drive).

### 10.7 Error Recovery

On a read or write error:
1. Retry up to 10 times
2. After 5 failures, recalibrate the drive (RECALIBRATE command 0x07,
   then SENSE INTERRUPT STATUS, then re-seek to the target track)
3. If ST0 bit 3 (Equipment Check / write protect) is set, abort
   immediately (hard error, no retry)
4. On total failure (10 retries exhausted), clear HSTACT and set ERFLAG=1

### 10.8 Sector Translation

CP/M logical sectors are mapped to physical sectors using translation tables.
The SECTRAN entry point passes through the sector number unchanged (returns
BC in HL). Actual sector translation is performed internally by the SELDSK
format dispatch, which selects the appropriate translation table. The tables
contain 1-based physical sector numbers in the interleaved access order.

---

## 11. Hard Disk Driver

### 11.1 WD1000 Command Protocol

1. Wait for READY (status bit 6) and SEEK COMPLETE (status bit 4)
2. Load the task file registers:
   - 0x61: Write precompensation cylinder
   - 0x62: Sector count (1 for single-sector operations)
   - 0x63: Sector number (physical)
   - 0x64: Cylinder low byte
   - 0x65: Cylinder high byte (bits 1-0 only)
   - 0x66: Size/Drive/Head (bit 5 = 512-byte sectors, bits 4-3 = drive, bits 2-0 = head)
3. Set up DMA channel 0 for the transfer
4. Write the command to port 0x67
5. Wait for the interrupt (CTC2 Ch.0)

### 11.2 WD1000 Commands

| Command | Code | Purpose |
|---------|------|---------|
| RESTORE | 0x10 + step_rate | Seek to track 0 |
| SEEK | 0x70 + step_rate | Seek to specified cylinder |
| READ | 0x28 | Read sector via DMA |
| WRITE | 0x30 | Write sector via DMA |
| FORMAT | 0x50 | Format track |

Step rate field (bits 3-0): rate x 0.5ms. Value 1 = 0.5ms (fastest).

### 11.3 DMA Setup for Hard Disk

- **DMA Channel:** 0
- **Read (disk to memory):** Mode 0x44 (single, IO-to-mem, channel 0)
- **Write (memory to disk):** Mode 0x48 (single, mem-to-IO, channel 0)

### 11.4 Logical-to-Physical Mapping

The BIOS maps CP/M logical sectors to physical hard disk sectors:
- Divide the CP/M sector number by sectors-per-page to get the head number
- The remainder is the physical sector within the page
- The track number maps directly to the cylinder

### 11.5 Configuration Sector

The hard disk configuration is stored in **sector 124 of the hard disk**. At
boot, the BIOS reads this sector and uses it to configure drive parameters
(format types, track offsets, partition sizes). If the configuration sector
cannot be read, the hard disk is marked offline.

---

## 12. Disk Format Specifications

### 12.1 Mini (5.25") Disk Format

| Track/Side | Encoding | Sectors | Bytes/Sector | Total |
|------------|----------|---------|--------------|-------|
| Track 0, Side 0 | FM (single density) | 16 | 128 | 2,048 |
| Track 0, Side 1 | MFM (double density) | 16 | 256 | 4,096 |
| Tracks 1--34, both sides | MFM (double density) | 9 | 512 | 4,608/track |

Total capacity: ~319 KB

### 12.2 Maxi (8") Disk Format

| Track/Side | Encoding | Sectors | Bytes/Sector | Total |
|------------|----------|---------|--------------|-------|
| Track 0, Side 0 | FM (single density) | 26 | 128 | 3,328 |
| Track 0, Side 1 | MFM (double density) | 26 | 256 | 6,656 |
| Tracks 1--76, both sides | MFM (double density) | 15 | 512 | 7,680/track |

Total capacity: ~1.2 MB

### 12.3 Sector Translation Tables

Each format has a translation table that maps CP/M logical sector numbers
(0-based) to physical sector numbers (1-based) with the appropriate
interleave factor:

**Table 0 -- 8" SS FM 128 B/S (26 sectors, skew 6):**
```
 1,  7, 13, 19, 25,  5, 11, 17, 23,  3,  9, 15,
21,  2,  8, 14, 20, 26,  6, 12, 18, 24,  4, 10, 16, 22
```

**Table 8 -- 8" DD MFM 512 B/S (15 sectors, skew 4):**
```
 1,  5,  9, 13,  2,  6, 10, 14,  3,  7, 11, 15,  4,  8, 12
```

**Table 16 -- 5.25" DD MFM 512 B/S (9 sectors, skew 2):**
```
 1,  3,  5,  7,  9,  2,  4,  6,  8
```

**Table 24 -- 8" DD MFM 256 B/S (26 sectors, identity / no interleave):**
```
 1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12,
13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26
```

### 12.4 Disk Parameter Headers (DPH)

Each drive has a 16-byte DPH structure (8 words) as defined by the CP/M 2.2
System Interface Guide:

| Offset | Size | Field | Contents |
|--------|------|-------|----------|
| +0 | 2 | XLT | Sector translation table pointer (NULL; translation done internally) |
| +2 | 6 | scratch | Three 16-bit scratch words (used by BDOS) |
| +8 | 2 | DIRBF | Pointer to shared 128-byte directory buffer |
| +10 | 2 | DPB | Pointer to Disk Parameter Block (updated by SELDSK) |
| +12 | 2 | CSV | Pointer to per-drive check vector (32 bytes) |
| +14 | 2 | ALV | Pointer to per-drive allocation vector (71 bytes) |

### 12.5 Disk Parameter Blocks

CP/M requires a Disk Parameter Block (DPB) for each disk format:

| Field | Description |
|-------|-------------|
| SPT | Logical sectors per track (in 128-byte CP/M records) |
| BSH | Block shift factor (log2 of block size / 128) |
| BLM | Block mask (2^BSH - 1) |
| EXM | Extent mask |
| DSM | Total blocks - 1 (storage capacity) |
| DRM | Directory entries - 1 |
| AL0, AL1 | Directory allocation bitmap |
| CKS | Check vector size (DRM+1)/4 for removable media, 0 for fixed |
| OFF | Number of reserved tracks |

**DPB for 8" SS FM 128 B/S (format 0 -- IBM standard single density):**
```
SPT=26, BSH=3, BLM=7, EXM=0, DSM=242, DRM=63,
AL0=0xC0, AL1=0x00, CKS=16, OFF=2
```

**DPB for 8" DD MFM 512 B/S (format 8 -- data area, tracks 1+):**
```
SPT=120, BSH=4, BLM=15, EXM=0, DSM=449, DRM=127,
AL0=0xC0, AL1=0x00, CKS=32, OFF=2
```

**DPB for 5.25" DD MFM 512 B/S (format 16 -- data tracks):**
```
SPT=26, BSH=3, BLM=7, EXM=0, DSM=242, DRM=63,
AL0=0xC0, AL1=0x00, CKS=16, OFF=0
```

**DPB for 8" DD MFM 256 B/S (format 24 -- Track 0 Side 1):**
```
SPT=104, BSH=4, BLM=15, EXM=0, DSM=471, DRM=127,
AL0=0xC0, AL1=0x00, CKS=32, OFF=0
```

### 12.6 Floppy System Parameters (FSPA)

Each format has an FSPA entry that bridges the CP/M DPB with the physical
format parameters:

| Index | DPB | Records/Block | CP/M SPT | Sector Mask | Sector Shift | Translation Table | Data Length |
|-------|-----|---------------|----------|-------------|--------------|-------------------|-------------|
| 0 | dpb0 | 8 | 26 | 0 | 1 | tran0 | 128 |
| 1 | dpb8 | 16 | 120 | 3 | 3 | tran8 | 255 |
| 2 | dpb16 | 8 | 26 | 0 | 1 | tran24 | 128 |
| 3 | dpb24 | 8 | 104 | 1 | 2 | tran24 | 255 |

Notes:
- Sector mask determines how many 128-byte CP/M records fit in one physical
  sector: mask=0 means 1 record (128B), mask=1 means 2 (256B), mask=3
  means 4 (512B).
- Sector shift is log2(records per physical sector) + 1.
- Format 2 (5.25") uses the identity translation table (tran24), not tran16.
  The tran16 table with skew 2 is used for the 5.25" main data format at the
  disk-driver level.

### 12.7 Floppy Disk Format Descriptors (FDF)

| Index | Phys SPT | DMA Count | MF | N | EOT | Gap | Tracks |
|-------|----------|-----------|-----|---|-----|-----|--------|
| 0 | 26 | 127 | 0x00 (FM) | 0 | 26 | 7 | 77 |
| 1 | 30 | 511 | 0x40 (MFM) | 2 | 15 | 27 | 77 |
| 2 | 26 | 127 | 0x00 (FM) | 0 | 26 | 7 | 77 |
| 3 | 52 | 255 | 0x40 (MFM) | 1 | 26 | 14 | 77 |

Notes:
- FDF index 0: 8" SS FM, 26 sectors of 128 bytes. Used for Track 0 Side 0.
- FDF index 1: 8" DD MFM, 15 sectors of 512 bytes. Used for data tracks.
  Physical SPT=30 accounts for both sides (15 * 2).
- FDF index 2: Same as index 0 (FM, Track 0 Side 0 format).
- FDF index 3: 8" DD MFM, 26 sectors of 256 bytes. Used for Track 0 Side 1.
  Physical SPT=52 accounts for both sides (26 * 2).

---

## 13. Boot Sequence

### 13.1 Cold Boot

1. Set SP to the BIOS private stack (0xF500).
2. Detect remote host on SIO-B: read SIO-B RR0 (port 0x0B) and test
   bit 3 (DCD, inverted polarity):
   - Bit 3 = 1 (DCD asserted): set IOBYTE = 0x97 (UC1 joined mode)
   - Bit 3 = 0 (DCD deasserted): set IOBYTE = 0x95 (CRT local mode)
3. Display signon message (clear screen with 0x0C, then the identification
   string including memory size and build date).
4. If DCD was detected, display "Console also on serial port B at 38400
   8N1" message.
5. Initialize CDISK = 0 (drive A:).
6. Clear all warm-boot state variables to zero (keyboard head/tail/status,
   SIO-A/B head/tail, disk cache flags, error flag).
7. Arm the SIO-A receiver (enable RTS, DTR, TX, and interrupts for
   the reader port).
8. Fall through to warm boot.

### 13.2 Warm Boot

1. Enable interrupts.
2. Select drive A: via SELDSK (drive 0).
3. Clear UNACNT and DSKNO.
4. **IOBYTE is NOT cleared or reset.** Any runtime changes (e.g.,
   `STAT CON:=TTY:`) are preserved across warm boots.
5. Home the selected drive (flush dirty buffer, recalibrate to track 0).
6. Set DMA address to CCP base (0xC400 for 56K).
7. Read track 1, loading NSECTS sectors (CPML / 128 = 0x1600 / 128 = 176
   sectors, covering CCP + BDOS = 5,632 bytes).
8. Reset DMA address to 0x0080 (default buffer).
9. Install warm boot vector at 0x0000: JP opcode (0xC3) and BIOS_BASE + 3.
10. Install BDOS entry at 0x0005: JP opcode (0xC3) and BDOS_BASE.
11. Re-select drive A: to ensure clean state.
12. Jump to CCP with current disk number in register C.

If a read error occurs during warm boot, the BIOS must display
"Disk read error - reset" and enter an infinite HALT loop.

---

## 14. Extended BIOS Entry Points

Beyond the standard CP/M 2.2 jump table, the RC702 BIOS provides additional
entry points starting at BIOS_BASE + 0x33 (after the 17-entry standard JP
table and the JTVARS block):

| Offset | Name | Parameters | Function |
|--------|------|-----------|----------|
| +0x4A | WFITR | -- | Wait for FDC interrupt; returns B=ST0, C=ST1 |
| +0x4D | READS | -- | Reader status (A=0xFF ready, 0 not) |
| +0x50 | LINSEL | A=port, B=line | Line selector (RC791 A/B switch) |
| +0x53 | EXIT | HL=callback, DE=count | Install timer callback |
| +0x56 | CLOCK | A=0 set, A!=0 read; DE,HL=time | Read/set 32-bit RTC |
| +0x59 | HRDFMT | -- | Format hard disk track |

### 14.1 EXIT Routine

Installs a callback function that the display ISR will call after a specified
number of 20 ms ticks (50 Hz). Used for floppy motor auto-off and other timed
events. The callback address is stored at WARMJP (0xFFE5) and the countdown
at TIMER1 (0xFFDF). The callback must NOT enable interrupts and must return
via RET.

### 14.2 CLOCK Routine

Reads or sets the 32-bit real-time clock at 0xFFFC--0xFFFF. The clock
increments at 50 Hz (20 ms per tick). To read: call with A != 0, returns
DE = low word, HL = high word (interrupts disabled during read for
atomicity). To set: call with A = 0, DE = low word, HL = high word.

### 14.3 LINSEL Routine (Line Selector)

Controls the external RC791 line selector via SIO DTR/RTS signaling:
- A = 0 for SIO Ch.A, A = 1 for SIO Ch.B
- B = 0: release line (DTR=0, RTS=0)
- B = 1: select line A (DTR=1, RTS=0)
- B = 2: select line B (DTR=1, RTS=1)
- Returns A = 0xFF if selected line responded (CTS asserted), 0 if not

Protocol:
1. Wait for all-sent (RR1 bit 0 = 1).
2. Delay 2 timer ticks (40 ms).
3. Release: DTR=0, RTS=0 (write 0x00 to WR5).
4. If B = 0, return 0 (release only).
5. Set RTS based on line number: B=1 gives RTS=0, B=2 gives RTS=1.
6. Assert DTR (add 0x80 to WR5 value).
7. Delay 2 timer ticks (40 ms).
8. Check CTS (RR0 bit 5 from cached status register):
   - CTS asserted: return 0xFF.
   - CTS not asserted: release line (DTR=0, RTS=0), return 0x00.

### 14.4 WFITR Routine

Waits for the floppy disk interrupt flag to be set, then clears it. Returns
the FDC result status in B (ST0) and C (ST1). Used by the RC700 FORMAT
utility to synchronize with FDC operations.

---

## 15. Character Conversion

The BIOS applies two lookup tables for character conversion:

- **OUTCON** (0xF680, 128 bytes): maps character codes 0x00--0x7F before
  display output. Applied by CONOUT before writing to screen memory.
  Identity mapping = ASCII pass-through.
- **INCONV** (0xF700, 256 bytes): maps raw keyboard/serial input bytes
  0x00--0xFF to internal character codes. Applied by CONIN after reading
  from the keyboard buffer. Identity mapping = no conversion.

These tables are loaded from **Track 0 sectors 3--5** (384 bytes total)
during cold boot initialization. They implement national character sets
(Danish/Norwegian, Swedish, German, UK ASCII, US ASCII, French). The CONFI
utility allows the user to switch between character sets by modifying the
Track 0 configuration sector.

Example: Danish/Norwegian mapping in OUTCON:
- '@' (0x40) becomes 'OE', '[' (0x5B) becomes 'AE', '\' (0x5C) becomes 'OE',
  ']' (0x5D) becomes 'AA', '{' (0x7B) becomes 'ae', '|' (0x7C) becomes 'oe',
  '}' (0x7D) becomes 'aa', '~' (0x7E) becomes 'ue'

---

## 16. Configuration

### 16.1 Track 0 Layout

Track 0, Side 0 contains the system bootstrap and configuration:

| Sector | Bytes | Contents |
|--------|-------|----------|
| 1 | 0--1 | Start address (entry point for ROM bootstrap) |
| 1 | 2--7 | Reserved (zero) |
| 1 | 8--13 | Machine identifier ('RC702 ' or 'RC703 ') |
| 1 | 14--127 | Reserved for ROM bootstrap loader |
| 2 | 0--127 | Configuration parameters (CONFI block, 128 bytes) |
| 3 | 0--127 | Output character conversion table (128 bytes) |
| 4--5 | 0--127 | Input character conversion table (256 bytes total) |
| 6+ | -- | Hardware initialization code + CP/M BIOS |

### 16.2 CONFI Configuration Block (Sector 2, 128 bytes)

The CONFI block contains all hardware initialization parameters. Each field
is shown with its byte offset within the 128-byte block, its size, and its
default value:

**CTC Configuration (8 bytes):**

| Offset | Size | Field | Default | Description |
|--------|------|-------|---------|-------------|
| +0x00 | 1 | CTC Ch.0 Mode | 0x47 | Timer mode, auto trigger, prescaler /16 |
| +0x01 | 1 | CTC Ch.0 Count | 0x01 | SIO-A baud divisor (1 = 38400 baud) |
| +0x02 | 1 | CTC Ch.1 Mode | 0x47 | Timer mode, auto trigger, prescaler /16 |
| +0x03 | 1 | CTC Ch.1 Count | 0x01 | SIO-B baud divisor (1 = 38400 baud) |
| +0x04 | 1 | CTC Ch.2 Mode | 0xD7 | Counter mode, interrupt enabled |
| +0x05 | 1 | CTC Ch.2 Count | 0x01 | CRT refresh trigger (1 pulse) |
| +0x06 | 1 | CTC Ch.3 Mode | 0xD7 | Counter mode, interrupt enabled |
| +0x07 | 1 | CTC Ch.3 Count | 0x01 | FDC interrupt trigger (1 pulse) |

CTC mode byte bits:
- Bit 0: 1 = control word
- Bit 1: 0 = software reset
- Bit 2: 1 = time constant follows
- Bit 3: 0 = auto trigger, 1 = external CLK/TRG edge
- Bit 4: 0 = falling edge, 1 = rising edge
- Bit 5: 0 = prescaler /16, 1 = prescaler /256
- Bit 6: 0 = timer mode (uses prescaler), 1 = counter mode
- Bit 7: 0 = disable interrupt, 1 = enable interrupt

**SIO Channel A Init (9 bytes):**

| Offset | Size | Field | Default | Description |
|--------|------|-------|---------|-------------|
| +0x08 | 1 | WR0 | 0x18 | Channel reset |
| +0x09 | 1 | WR0 | 0x04 | Select WR4 |
| +0x0A | 1 | WR4 | 0x44 | x16 clock, 1 stop, no parity (8N1) |
| +0x0B | 1 | WR0 | 0x03 | Select WR3 |
| +0x0C | 1 | WR3 | 0xE1 | 8-bit RX, auto enables, RX enable |
| +0x0D | 1 | WR0 | 0x05 | Select WR5 |
| +0x0E | 1 | WR5 | 0x60 | 8-bit TX, TX disabled, RTS off, DTR off |
| +0x0F | 1 | WR0 | 0x01 | Select WR1 |
| +0x10 | 1 | WR1 | 0x1B | RX/TX/ext int enabled |

**SIO Channel B Init (11 bytes):**

| Offset | Size | Field | Default | Description |
|--------|------|-------|---------|-------------|
| +0x11 | 1 | WR0 | 0x18 | Channel reset |
| +0x12 | 1 | WR0 | 0x02 | Select WR2 |
| +0x13 | 1 | WR2 | 0x10 | Interrupt vector base 0x10 |
| +0x14 | 1 | WR0 | 0x04 | Select WR4 |
| +0x15 | 1 | WR4 | 0x44 | x16 clock, 1 stop, no parity (8N1) |
| +0x16 | 1 | WR0 | 0x03 | Select WR3 |
| +0x17 | 1 | WR3 | 0xE1 | 8-bit RX, auto enables, RX enable |
| +0x18 | 1 | WR0 | 0x05 | Select WR5 |
| +0x19 | 1 | WR5 | 0x60 | 8-bit TX, TX disabled |
| +0x1A | 1 | WR0 | 0x01 | Select WR1 |
| +0x1B | 1 | WR1 | 0x1F | RX/TX/ext int + status affects vector + parity special |

**DMA Mode Registers (4 bytes):**

| Offset | Size | Field | Default | Description |
|--------|------|-------|---------|-------------|
| +0x1C | 1 | Ch.0 mode | 0x48 | Single, mem-to-IO (hard disk) |
| +0x1D | 1 | Ch.1 mode | 0x49 | Single, mem-to-IO (floppy default) |
| +0x1E | 1 | Ch.2 mode | 0x4A | Single, mem-to-IO (display data) |
| +0x1F | 1 | Ch.3 mode | 0x4B | Single, mem-to-IO (display attr) |

**8275 CRT Controller Parameters (4 bytes):**

| Offset | Size | Field | Default | Description |
|--------|------|-------|---------|-------------|
| +0x20 | 1 | PAR1 | 0x4F | 80 characters per row |
| +0x21 | 1 | PAR2 | 0x98 | 25 rows, VRTC timing |
| +0x22 | 1 | PAR3 | 0x7A | 28 H retrace, 4 V retrace |
| +0x23 | 1 | PAR4 | 0x6D | 7 lines/char, steady block cursor |

**FDC SPECIFY Command (4 bytes):**

| Offset | Size | Field | Default | Description |
|--------|------|-------|---------|-------------|
| +0x24 | 1 | Byte count | 0x03 | 3 bytes to send |
| +0x25 | 1 | Command | 0x03 | SPECIFY command |
| +0x26 | 1 | SRT/HUT | 0xDF | Step 3 ms, unload 240 ms |
| +0x27 | 1 | HLT/ND | 0x28 | Load 40 ms, DMA mode |

**CONFI User Settings (7 bytes):**

| Offset | Size | Field | Default | Description |
|--------|------|-------|---------|-------------|
| +0x28 | 1 | Cursor number | 0x00 | Blinking reverse block |
| +0x29 | 1 | Conversion table | 0x00 | Danish/Norwegian |
| +0x2A | 1 | Baud rate A index | 0x06 | Display value for CONFI menu |
| +0x2B | 1 | Baud rate B index | 0x06 | Display value for CONFI menu |
| +0x2C | 1 | XY flag | 0x00 | 0=XY (col,row), 1=YX (row,col) |
| +0x2D | 2 | Motor stop timer | 0x00FA (250) | 250 x 20 ms = 5 seconds |

**Drive Format Table (17 bytes):**

| Offset | Size | Field | Default | Description |
|--------|------|-------|---------|-------------|
| +0x2F | 1 | Drive A | 0x08 | 8" DD floppy |
| +0x30 | 1 | Drive B | 0x08 | 8" DD floppy |
| +0x31 | 1 | Drive C | 0x20 | Hard disk (1 MB partition) |
| +0x32--0x3E | 13 | Drives D--P | 0xFF | Not present |
| +0x3F | 1 | Terminator | 0xFF | End of table |

**Hard Disk Partition (4 bytes):**

| Offset | Size | Field | Default | Description |
|--------|------|-------|---------|-------------|
| +0x40 | 1 | Partition count | 0x02 | 2 HD partitions |
| +0x41 | 3 | Partition desc | 0x02,0x00,0x00 | Partition parameters |

**CTC2 (HD Interface Board, 3 bytes):**

| Offset | Size | Field | Default | Description |
|--------|------|-------|---------|-------------|
| +0x44 | 1 | CTC2 Ch.0 Mode | 0xD7 | Counter mode, interrupt enabled |
| +0x45 | 1 | CTC2 Ch.0 Count | 0x01 | 1 pulse trigger |
| +0x46 | 1 | CTC2 Ch.1 | 0x03 | Software reset (disable) |

**Boot Device (1 byte):**

| Offset | Size | Field | Default | Description |
|--------|------|-------|---------|-------------|
| +0x47 | 1 | Boot device | 0x00 | 0x00=floppy, 0x01=hard disk |

Bytes +0x48 through +0x7F are reserved (zero-padded to 128 bytes).

### 16.3 Drive Format Index

Each drive's format code in the fd0[] table selects a format descriptor chain:

| Code | Format |
|------|--------|
| 0 | SS FM 128 B/S (single density) |
| 8 | DD MFM 512 B/S (double density, standard data format) |
| 16 | DD MFM 512 B/S (5.25" data tracks) |
| 24 | DD MFM 256 B/S (Track 0 Side 1) |
| 32 | Hard disk 1 MB partition |
| 40 | Hard disk 0.8 MB partition |
| 48 | Hard disk 2 MB partition |
| 56 | Hard disk 4 MB partition |
| 64 | Hard disk 8 MB partition |
| 255 | Drive not configured |

---

## 17. Baud Rate Configuration

### 17.1 Clock Derivation

The baud rate clock for the SIO is derived from the system memory clock:

```
19.6608 MHz (memory clock)
    / 32 (two cascaded 74LS393 dividers on the PCB)
    = 614.4 kHz (CTC input clock)
```

This 614,400 Hz clock feeds CTC channels 0 and 1, which divide it by a
programmable time constant. The resulting clock feeds the SIO baud rate
generator, which further divides by the SIO clock mode factor (x16 or x64,
set in SIO WR4).

### 17.2 Baud Rate Formula

```
baud_rate = 614400 / (CTC_count x SIO_clock_mode)
```

Where:
- CTC_count = the time constant loaded into the CTC channel (1--256;
  a value of 0 means 256)
- SIO_clock_mode = 16 (WR4 bits 7:6 = 01) or 64 (WR4 bits 7:6 = 11)

### 17.3 Available Baud Rates

| Baud Rate | CTC Count | SIO Clock Mode | WR4 Value |
|-----------|-----------|----------------|-----------|
| 38400 | 1 | x16 | 0x44 |
| 19200 | 2 | x16 | 0x44 |
| 9600 | 4 | x16 | 0x44 |
| 4800 | 8 | x16 | 0x44 |
| 2400 | 16 | x16 | 0x44 |
| 1200 | 32 | x16 | 0x44 |
| 600 | 64 | x16 | 0x44 |
| 300 | 32 | x64 | 0xC4 |
| 150 | 64 | x64 | 0xC4 |
| 110 | 87 | x64 | 0xC4 |
| 75 | 128 | x64 | 0xC4 |
| 50 | 192 | x64 | 0xC4 |

The CTC mode byte for baud rate generation is always 0x47 (timer mode,
auto trigger, prescaler /16, time constant follows). The CTC interrupt
is disabled (bit 7 = 0) for baud rate channels since the SIO handles
timing internally.

### 17.4 Default Configuration

Both SIO channels default to 38400 baud, 8N1:
- CTC count = 0x01 (divisor 1)
- SIO WR4 = 0x44 (x16 clock, 1 stop bit, no parity)
- SIO WR3 = 0xE1 (8-bit RX, auto enables, RX enable)
- SIO WR5 = 0x60 (8-bit TX)

---

## 18. WorkArea Variables (0xFFD0--0xFFFF)

The WorkArea occupies the top 48 bytes of the Z80 address space, above the
display memory (0xF800--0xFFCF). These addresses are part of the BIOS ABI --
external programs may read or write them directly.

| Address | Size | Name | Description |
|---------|------|------|-------------|
| 0xFFD0 | 1 | (reserved) | Unused padding byte |
| 0xFFD1 | 1 | CURX | Cursor column position (0--79) |
| 0xFFD2 | 2 | CURY | Cursor row as byte offset (row x 80; 0, 80, 160, ..., 1920) |
| 0xFFD4 | 1 | CURSY | Cursor row number (0--24) |
| 0xFFD5 | 2 | LOCBUF | Scroll source pointer (temporary during scroll) |
| 0xFFD7 | 1 | XFLG | Escape sequence state (0=normal, 1=second byte pending, 2=first byte pending) |
| 0xFFD8 | 2 | LOCAD | Screen position offset (temporary during character output) |
| 0xFFDA | 1 | USESSION | Character currently being output (used by control dispatch) |
| 0xFFDB | 3 | (reserved) | Reserved gap (3 bytes) |
| 0xFFDE | 1 | ADR0 | First XY escape coordinate (saved between bytes 1 and 2) |
| 0xFFDF | 2 | TIMER1 | General-purpose exit timer countdown (ISR decrements every 20 ms) |
| 0xFFE1 | 2 | TIMER2 | Floppy motor-off countdown (ISR decrements every 20 ms) |
| 0xFFE3 | 2 | DELCNT | General delay counter (ISR decrements every 20 ms) |
| 0xFFE5 | 2 | WARMJP | Exit routine JP target address (called by ISR when TIMER1 reaches 0) |
| 0xFFE7 | 1 | FDTIMO | Motor-off timeout reload value (ticks, loaded into TIMER2 on motor start) |
| 0xFFE8 | 2 | (reserved) | Reserved gap (2 bytes) |
| 0xFFEA | 2 | STPTIM | Motor timer reload value (ticks, from CONFI configuration) |
| 0xFFEC | 2 | CLKTIM | Screen blank timer (ISR decrements; reserved for future use) |
| 0xFFEE | 14 | (reserved) | Reserved gap (14 bytes) |
| 0xFFFC | 2 | RTC0 | Real-time clock low word (ISR increments at 50 Hz) |
| 0xFFFE | 2 | RTC2 | Real-time clock high word (ISR carries from RTC0 overflow) |

All fields are zeroed during cold boot initialization (BSS clear).
Timer fields (TIMER1, TIMER2, DELCNT, CLKTIM, RTC0, RTC2) are modified
by the display ISR and must be accessed with interrupts disabled for
atomicity when reading or writing from main-line code.

---

## 19. JTVARS Runtime ABI

The JTVARS block occupies 22 bytes starting at BIOS_BASE + 0x33 (0xDA33
for 56K). It is located immediately after the 17-entry BIOS JP table
(17 x 3 = 51 = 0x33 bytes). External programs (CONFI.COM, FORMAT.COM, etc.)
depend on these exact addresses -- they are part of the BIOS ABI.

| Address | Size | Name | Description |
|---------|------|------|-------------|
| 0xDA33 | 1 | ADRMOD | Cursor addressing mode: 0=XY (column first), 1=YX (row first). Copied from CONFI xyflg at boot. |
| 0xDA34 | 1 | WR5A | SIO Channel A WR5 bits/char mask (0x60=8-bit, 0x20=7-bit). Extracted from CONFI sioa[6] & 0x60 at boot. |
| 0xDA35 | 1 | WR5B | SIO Channel B WR5 bits/char mask (0x60=8-bit, 0x20=7-bit). Extracted from CONFI siob[8] & 0x60 at boot. |
| 0xDA36 | 1 | MTYPE | Machine type: 0=RC700/RC702, 1=RC850/RC855, 2=ITT3290, 3=RC703. Set to 0 at init. |
| 0xDA37 | 16 | FD0 | Active drive format table (drives A--P). One byte per drive: format code (see Section 16.3) or 0xFF=not present. Initialized from CONFI infd[] at boot. |
| 0xDA47 | 1 | FD0_TERM | Drive table terminator. Always 0xFF. |
| 0xDA48 | 1 | BOOTD | Boot device: 0x00=floppy, 0x01=hard disk. Set from CONFI ibootd at boot. |

The extended BIOS entry points (WFITR, READS, LINSEL, EXIT, CLOCK, HRDFMT)
follow immediately after JTVARS at BIOS_BASE + 0x4A (0xDA4A for 56K).

---

## References

- Digital Research: CP/M 2.2 Interface Guide (BIOS entry points, DPB format)
- Digital Research: CP/M 2.2 Alteration Guide (blocking/deblocking algorithm)
- Zilog: Z80 CPU User Manual (instruction set, interrupt modes)
- Zilog: Z80 PIO Technical Manual (mode programming, interrupt protocol)
- Zilog: Z80 CTC Technical Manual (timer/counter modes, baud rate generation)
- Zilog: Z80 SIO Technical Manual (register programming, WR5 bit assignments)
- Intel: 8275 Programmable CRT Controller datasheet (command set, DMA interface)
- NEC: uPD765 Floppy Disk Controller datasheet (command protocol, status registers)
- AMD: Am9517A DMA Controller datasheet (channel programming, transfer modes)
- Western Digital: WD1000 Winchester Disk Controller (command set, task file)
