# RC702 port-output value reference

Every byte our `cpnos-rom` payload writes via Z80 `OUT` instruction,
decoded bit-by-bit with cross-references to callsites.  Port addresses
come from `hal.h`; this doc is about the **values** — what each byte
means to the peripheral chip that latches it.

Source of truth is the relevant chip datasheet (µPD765 FDC, 8237 DMA,
8275 CRT, Z80 CTC/SIO/PIO).  Where our init table comments disagree
with the datasheet, the datasheet wins; where bits are reserved or
don't matter in the selected mode, that's called out.

Table of contents:

- [Z80 CTC — 0x0C..0x0F](#z80-ctc--0x0c0x0f)
- [Z80 SIO — 0x0A (A) / 0x0B (B)](#z80-sio--0x0a-a--0x0b-b)
- [Z80 PIO — 0x12 (A) / 0x13 (B)](#z80-pio--0x12-a--0x13-b)
- [8237 DMA — 0xF0..0xFF](#8237-dma--0xf00xff)
- [8275 CRT — 0x00 (PARAM) / 0x01 (CMD)](#8275-crt--0x00-param--0x01-cmd)
- [µPD765 FDC — 0x04 (STATUS) / 0x05 (DATA)](#upd765-fdc--0x04-status--0x05-data)  *(future — ENABLE_FDC=1)*
- [Sidecar ports — 0x18 RAMEN, 0x1C BIB](#sidecar-ports--0x18-ramen-0x1c-bib)

Every OUT site in the payload is accounted for: `_port_out()` calls in
`init.c`, `cpnos_main.c`, `resident.c`, `transport_sio.c`, and raw
`out (nn), a` in `isr.s`.

---

## Z80 CTC — 0x0C..0x0F

Four channels at `0x0C`-`0x0F`, one port per channel.  The same port
serves two different register types, disambiguated by **bit 0 of the
written byte**:

- `bit 0 == 1` → **channel control word**
- `bit 0 == 0` → **interrupt vector** (only meaningful written to
  channel 0; upper 5 bits of that byte become the shared vector base
  for all four channels, bits 2-1 are overridden per-channel at
  interrupt time)

After a channel control word with bit 2 set ("time constant follows"),
the **next** byte written to that same port is the 8-bit time
constant (1..256, with 0 meaning 256).

### Control-word bit layout

```
 bit:  7   6   5   4   3   2   1   0
      INT CNT PFX EDG TRG TCF RST  1
```

| Bit | Name | Meaning |
|:---:|------|---------|
| 7 | `INT` | Interrupt enable (1 = this channel generates IM2 interrupts) |
| 6 | `CNT` | Counter mode (1) vs timer mode (0) |
| 5 | `PFX` | Timer prescaler (0 = ÷16, 1 = ÷256).  Counter mode ignores this. |
| 4 | `EDG` | Timer trigger edge (0 = falling, 1 = rising).  Counter uses CLK/TRG input edge. |
| 3 | `TRG` | Timer trigger mode (0 = auto-start on TC load, 1 = start on CLK/TRG pulse).  Counter ignores. |
| 2 | `TCF` | 1 = time-constant byte follows on next write |
| 1 | `RST` | 1 = software reset (stops channel; value of TC/control is discarded until next load) |
| 0 |  `1`  | Control-word identifier |

### Values our code writes

From `init.c:48-52`:

```
CTC0 ← 0x00        ; interrupt vector base (channel 0 position only)
CTC0 ← 0x47        ; control word: counter, TC follows, reset
CTC0 ← 0x01        ; time constant = 1
CTC1 ← 0x47
CTC1 ← 0x01
CTC2 ← 0xD7        ; control word: INT enabled, counter, TC follows, reset
CTC2 ← 0x01
```

Decoding:

**`0x00` → CTC0 interrupt vector** = 0b`00000000`.  Bit 0 is clear, so
this is the vector byte.  All four CTC channels share vector base
`0x00`, with the low 3 bits (channel index × 2) filled by the channel
at interrupt time: ch0 → vector 0x00, ch1 → 0x02, ch2 → 0x04, ch3 → 0x06.
The IVT (at `0xEC00`) is 8-byte-aligned so vectors 0x00..0x06 land in
the first 4 slots.

**`0x47` → control** = 0b`01000111`:

- `INT=0` — polled; CTC0 and CTC1 clock the SIO channels, there is no
  interrupt for a baud-rate tick.
- `CNT=1` — counter mode: channel counts down on each rising edge on
  the CLK/TRG input, not on the system clock.  CLK/TRG0 and CLK/TRG1
  are both fed by the same 614.4 kHz signal derived from the memory
  clock (see `RC702_HARDWARE_TECHNICAL_REFERENCE.md` §CTC).
- `PFX=0`, `EDG=0`, `TRG=0` — don't-care in counter mode.
- `TCF=1` — next byte is the time constant.
- `RST=1` — reset first so any previous channel state is cleared.

Channel effect: counts down from time constant on each 614.4 kHz input
edge.  Zero-count output ZC/TO drives the SIO clock pin (TxC = RxC).

**`0x01` → TC** = divisor of 1.  Output frequency = input / TC = 614400 Hz.
With SIO clock mode ×16 (see WR4 below) this gives async baud rate:

```
614400 / 1 / 16 = 38400 baud
```

**`0xD7` → CTC2 control** = 0b`11010111`:

- `INT=1` — channel 2 generates interrupts on each zero-count.  Used
  as the VRTC tick for our CRT refresh ISR (`isr.s:_isr_crt`).  The
  CLK/TRG2 input is wired to the 8275's VRTC output.
- `CNT=1` — counter mode: each 8275 VRTC pulse advances the count.
- `PFX=0`, `EDG=1` — EDG is don't-care in counter mode (it specifies
  timer trigger edge, not counter input edge which is always rising).
- `TRG=0` — don't-care in counter mode.
- `TCF=1`, `RST=1` — TC follows, reset first.

`0x01` TC = fire interrupt once per VRTC edge (every vertical
retrace, ~50 Hz on our 8275 geometry).  `_isr_crt` re-arms this
counter on every entry with the same `0xD7` / `0x01` pair (isr.s:122-125)
— writing a new TC during operation rearms the counter.

### CTC write from ISR (frame re-arm)

`isr.s:122-125` rewrites CTC2:
```
out (0x0E), 0xD7    ; same control word — reset + TC-follows + int enable
out (0x0E), 0x01    ; TC = 1
```

Must re-arm every VRTC because the counter latch decrements to zero,
fires the interrupt, and needs a fresh TC to start the next frame's
count.  If omitted, the ISR fires exactly once after boot and never
again.

---

## Z80 SIO — 0x0A (A) / 0x0B (B)

Each channel has a control port (`CTRL`) and a data port (`DATA`).
Data is pass-through (receiver buffer / transmit holding register);
all configuration goes through CTRL.

The SIO has **8 write-only registers (WR0-WR7)** but only one control
port per channel, so access uses a two-step dance:

1. Write a **register pointer** to WR0 (this directs subsequent writes).
2. Write the desired value — it lands in the register WR0 last pointed to.

The pointer is the low 3 bits of WR0 (0..7).  The upper 5 bits of WR0
encode **commands**:

```
 bit:  7   6   5   4   3   2   1   0
      CC1 CC0 CB2 CB1 CB0 RP2 RP1 RP0
```

Where `CCx` = CRC reset command (2 bits) and `CBx` = command code (3 bits).
If the upper bits are zero, WR0 is *just* a register-select for the
next write.

### WR0 commands we use

| Byte | Binary | Meaning |
|:----:|:------:|---------|
| `0x18` | `0001 1000` | Command = Channel Reset (CBx=011, CCx=00); register pointer=0 (irrelevant — channel-reset is a full reset) |
| `0x01` | `0000 0001` | Select WR1 for next write |
| `0x02` | `0000 0010` | Select WR2 |
| `0x03` | `0000 0011` | Select WR3 |
| `0x04` | `0000 0100` | Select WR4 |
| `0x05` | `0000 0101` | Select WR5 |

### Values written to individual write registers

From `init.c:56-68`:

**WR4 ← `0x44`** = 0b`01000100` (clock mode + stop bits + parity):

- bits 7-6: `01` = clock mode ×16 (receiver samples at 16× bit rate)
- bits 5-4: `00` = async mode (not sync / not SDLC)
- bits 3-2: `01` = 1 stop bit
- bit 1:    `0`  = even/odd parity (irrelevant if parity disabled)
- bit 0:    `0`  = parity disable

Result: 8N1 async at ×16 oversampling.  ×16 is the minimum viable for
async reception — clock must beat enough to sample bit centers.

**WR3 ← `0xE1`** = 0b`11100001` (receive control):

- bits 7-6: `11` = 8 bits per received character
- bit 5:    `1`  = auto-enables (RTS/CTS chain: RX activation depends on DCD)
- bit 4:    `0`  = no enter hunt phase (sync-only)
- bit 3:    `0`  = no receive CRC (sync-only)
- bit 2:    `0`  = no address search (SDLC-only)
- bit 1:    `0`  = sync character load inhibit (sync-only)
- bit 0:    `1`  = **receiver enable**

**WR5 ← `0x6A`** = 0b`01101010` (transmit control):

- bit 7:    `0`  = DTR deasserted (not used in our RS-232 wiring)
- bits 6-5: `11` = 8 bits per transmitted character
- bit 4:    `0`  = no SDLC send-break
- bit 3:    `1`  = **transmitter enable**
- bit 2:    `0`  = CRC-16 polynomial (CRC-CCITT = 1; unused with sync disabled)
- bit 1:    `1`  = **RTS asserted**
- bit 0:    `0`  = transmit CRC disable

**WR1 ← `0x00`** = all interrupts **disabled**.  Our SIO drivers poll
RR0 (status) via `_port_in(PORT_SIO_X_CTRL)` rather than interrupt.
For reference, bit 4 would enable "RX character available" interrupts.

**WR2 (Ch B only) ← `0x10`** = interrupt vector base `0x10`.  Z80-SIO/2
channel B owns the shared vector byte; channel A does not have WR2.
Four vectors are generated in the group: RX char, TX buffer empty,
ExtStatus, Special RX condition.  Vectors 0x10..0x16 land in IVT slots
8..11 at `0xEC10..0xEC16` — currently pointing to `_isr_noop` since we
keep SIO interrupts off.

### Initialization sequence (per channel)

From `init.c:56-68`, expanded:

```
CTRL ← 0x18       ; channel reset (full sync + disable all, 4 PCLK delay)
CTRL ← 0x02       ; select WR2 (Ch B only)
CTRL ← 0x10       ; WR2 = interrupt vector 0x10 (Ch B only)
CTRL ← 0x04       ; select WR4
CTRL ← 0x44       ; WR4 = 8N1, ×16
CTRL ← 0x03       ; select WR3
CTRL ← 0xE1       ; WR3 = 8-bit RX + RX enable
CTRL ← 0x05       ; select WR5
CTRL ← 0x6A       ; WR5 = 8-bit TX + TX enable + RTS
CTRL ← 0x01       ; select WR1
CTRL ← 0x00       ; WR1 = no interrupts
```

The exact order matters: the reset must precede everything (else stale
parameters from a previous boot leak through), and the CTC baud-rate
channels must be programmed before the SIO or the first received
byte's clock is wrong.

### Data writes

`_port_out(PORT_SIO_A_DATA, c)` — `transport_sio.c:17` — the byte `c`
is placed into the transmit holding register.  Polling `RR0 bit 2`
(TX buffer empty) via `_port_in(PORT_SIO_A_CTRL)` before the write
avoids overrunning.  Our transports always poll-then-write.

`_port_out(PORT_SIO_B_DATA, c)` — `resident.c:32`, `console_putc()` —
same mechanism, B channel.  Used to mirror all CONOUT bytes out of
the test fixture (MAME null_modem sink).

---

## Z80 PIO — 0x12 (A) / 0x13 (B)

Like the SIO, each channel has a CTRL and a DATA port.  We only use
Port A (`PORT_PIO_A_CTRL = 0x12`) for the keyboard input.

### Control-byte disambiguation

The PIO looks at the **low two bits** of the CTRL write:

| low bits | Meaning |
|:-------:|---------|
| `xx00` (bit 0 = 0) | Interrupt vector (bits 7-3 = vector, bits 2-1 = channel) — only when bit 0 is 0 and nothing else matches |
| `xxxx 0111` | Interrupt disable word (bit 7 = enable/disable) |
| `xxxx 1111` | Mode-select word (bits 7-6 = mode) |
| `xxxx 0011` | Control register for mode 3 ("control" mode, bidirectional) |
| `xxxx 1011` | Interrupt control word (bit 7 = EI, bit 6 = AND/OR, bit 5 = high/low, bit 4 = mask follows) |

### Values we write

From `init.c:71-73`:

```
PIO_A_CTRL ← 0x20    ; interrupt vector for port A = 0x20
PIO_A_CTRL ← 0x4F    ; mode-select word: mode 1 (input)
PIO_A_CTRL ← 0x83    ; interrupt control: EI, OR logic, active-high, no mask
```

Decoding:

**`0x20` → interrupt vector** = 0b`00100000`.  Bit 0 = 0 → vector byte.
Bits 7-3 = `00100` → base = 0x20.  Hardware fills in the low 3 bits
with `000` for port A / `010` for port B (Z80-PIO convention — port B's
vector lives at vector+2, so 0x22).  In our IVT, slot at `0xEC20`
points to `_isr_pio_kbd`.

**`0x4F` → mode select** = 0b`01001111`:

- Low nibble `1111` → this is a mode-select word.
- Bits 7-6: `01` → **mode 1 = byte input** (all 8 data lines become
  inputs; the PIO handshake STB strobes the input register).
- Bits 5-4: unused in modes 0/1.

Result: PIO-A latches an 8-bit keyboard scancode on each STB pulse
from the keyboard hardware.

**`0x83` → interrupt control** = 0b`10000011`:

- Low nibble `0011`? — **no, looking again**: `0b1000_0011`.  The PIO
  decode tree checks low 4 bits:
  - `1111` = mode select (doesn't match)
  - `0111` = interrupt disable (doesn't match; bits 1-0 = 11 not 11)
  - `0011` = matches! So this is the **interrupt control word** path.

  *(The datasheet overloads this encoding; the bit pattern `xxxx0111`
  is the "interrupt disable" word and `xxxx0011` is different from
  the mode-3 variant by context — this is by far the most confusing
  part of the PIO.  If you need to trace further, the Z80-PIO
  datasheet Table 3 is authoritative.)*

- Bit 7: `1` = **enable IRQ** (the "interrupt enable flipflop").
- Bit 6: `0` = OR logic (any enabled data-bit state matches)
- Bit 5: `0` = active-low polarity (for mask match)
- Bit 4: `0` = no mask register follows (next write is not ICW2)
- Bits 3-0: `0011` = interrupt-control-word identifier

Result: PIO-A fires interrupts on strobe reception (STB goes active),
loading the byte into the data register.  `_isr_pio_kbd` reads the
byte out of `PORT_PIO_A_DATA (0x10)` and pushes onto `kbd_ring[]`.

---

## 8237 DMA — 0xF0..0xFF

The 8237 has four channels, each with an **address register** (16 bits,
loaded as two bytes LSB-then-MSB through the same port) and a
**word-count register** (16 bits, same two-byte pattern).  An internal
**byte-pointer flipflop** tracks which half of a 16-bit register is
being written next — it must be cleared via `CLBP` (`PORT_DMA_CLBP = 0xFC`)
before loading, otherwise an odd-indexed write can be misinterpreted.

### Channel assignment on RC702

| Channel | Peripheral | Addr port | WC port |
|:-------:|-----------|:---------:|:-------:|
| 0 | External DMA (J8 expansion — not used on-board) | `0xF0` | `0xF1` |
| 1 | µPD765 floppy disk controller | `0xF2` | `0xF3` |
| 2 | 8275 CRT display DMA | `0xF4` | `0xF5` |
| 3 | 8275 CRT attribute DMA | `0xF6` | `0xF7` |

### Shared control ports

| Port | Name | Function |
|:----:|------|----------|
| `0xF8` | `CMD` | Command register — controller-wide config |
| `0xFA` | `SMSK` | Single-mask: low 2 bits = channel, bit 2 = mask set/clear |
| `0xFB` | `MODE` | Mode register: sets per-channel transfer mode |
| `0xFC` | `CLBP` | Clear byte-pointer flipflop (any write) |

### Values we write

From `init.c:76-89` (the display DMA setup):

```
PORT_DMA_CMD  ← 0x20         ; command register
PORT_DMA_MODE ← 0x58 | 2     ; mode for ch2
PORT_DMA_MODE ← 0x58 | 3     ; mode for ch3
PORT_DMA_CLBP ← 0            ; clear byte-pointer flipflop
PORT_DMA_CH2_ADDR ← lo(0xF800)
PORT_DMA_CH2_ADDR ← hi(0xF800)
PORT_DMA_CH2_WC   ← lo(DISPLAY_SIZE-1)
PORT_DMA_CH2_WC   ← hi(DISPLAY_SIZE-1)
PORT_DMA_CH3_WC   ← 0        ; no attribute transfer
PORT_DMA_CH3_WC   ← 0
PORT_DMA_SMSK ← 0x02         ; clear ch2 mask (enable channel)
PORT_DMA_SMSK ← 0x03         ; clear ch3 mask
```

### CMD = `0x20` = 0b`00100000`

- bit 7: `0` — DACK polarity: active low
- bit 6: `0` — DREQ polarity: active high
- bit 5: `1` — extended write timing (longer write signal — needed for
  slow CRT and FDC buses)
- bit 4: `0` — fixed priority (ch0 highest, ch3 lowest)
- bit 3: `0` — normal timing (not compressed)
- bit 2: `0` — controller enable (0 = enabled)
- bit 1: `0` — channel 0 hold disabled
- bit 0: `0` — memory-to-memory transfer disabled

### MODE = `0x58 | n` (ch n)

`0x58` = 0b`01011000`.  OR'd with the channel number (0..3) that lives
in bits 1-0 of the written byte.

- bits 7-6: `01` = **single transfer** (one byte per DREQ; DMA releases
  the bus between requests — allows CPU to fetch)
- bits 5-4: `01` = **address increment** (next byte goes to addr+1)
- bit 3:    `1`  = **auto-initialize** (when WC reaches TC, reload from
  the "base" address/WC and keep running — our CRT DMA restarts every
  frame without CPU intervention)
- bits 3-2: `10` = **transfer type = read** (memory → I/O, i.e., CPU
  RAM → display controller)
- bits 1-0: `nn` = channel number (2 for CRT main, 3 for CRT attr)

Result per channel: single-transfer, auto-init, memory-read mode — the
8275 pulls the next byte from our display buffer on each DREQ, and
when 2000 bytes have been sent the address auto-reloads to `0xF800`.

### CH ADDR / WC writes

Each 16-bit register is written as **two** bytes to the same port:
first the low byte, then the high byte.  The `CLBP` write immediately
before the pair resets the internal flipflop so our first byte lands in
the low half as expected.

```
CH2_ADDR ← 0x00      ; low byte of 0xF800
CH2_ADDR ← 0xF8      ; high byte
CH2_WC   ← 0xCF      ; low byte of 1999 (DISPLAY_SIZE-1)
CH2_WC   ← 0x07      ; high byte (total = 0x07CF = 1999)
```

WC is stored as `N-1` — a register value of 1999 transfers 2000 bytes.

### Mask operations

`PORT_DMA_SMSK ← 0x02` — SMSK byte breakdown:
- bits 1-0: channel select (0..3)
- bit 2:    set/clear (`0` = clear mask / enable channel; `1` = set mask / disable)

`0x02` = 0b`0000 0010` = clear mask for channel 2 → channel 2 starts
responding to DREQ.  `0x03` = clear ch3.  Before configuring a channel,
code should typically SET its mask (`0x06` = set ch2), write the mode
and addresses, then clear the mask to activate.  Our init does the
sequence mode-first then unmask, which works because the CMD register
bit 2 starts with the controller enabled and the default masks from
power-on are set.

### CMD/MODE/ADDR writes from `_isr_crt`

Every vertical retrace, `isr.s:87-125` reprograms the display DMA:

```
out (0xFA), 0x06     ; set mask bit for ch2 (disable temporarily)
out (0xFA), 0x07     ; set mask bit for ch3
out (0xFC), 0x00     ; clear byte-pointer FF
out (0xF4), 0x00     ; CH2 addr lo = 0x00
out (0xF4), 0xF8     ; CH2 addr hi = 0xF8
out (0xF5), 0xCF     ; CH2 wc lo  = 0xCF
out (0xF5), 0x07     ; CH2 wc hi  = 0x07
out (0xF7), 0x00     ; CH3 wc = 0 (no attribute data)
out (0xF7), 0x00
out (0xFA), 0x02     ; clear ch2 mask (re-enable)
out (0xFA), 0x03     ; clear ch3 mask
```

The mask-set-then-reload-then-mask-clear protects against DMA racing
while registers are half-written.

---

## 8275 CRT — 0x00 (PARAM) / 0x01 (CMD)

The 8275 looks at bit 7-5 of the value on the CMD port to identify the
command; parameter bytes follow on the PARAM port.

### Command repertoire

| Byte | Command | Params |
|:----:|---------|:------:|
| `0x00` | Reset | 4 |
| `0x20` | Start Display | 0 |
| `0x40` | Stop Display | 0 |
| `0x60` | Read Light Pen | 0 (returns 2 bytes) |
| `0x80` | Load Cursor Position | 2 |
| `0xA0` | Enable Interrupt | 0 |
| `0xC0` | Disable Interrupt | 0 |
| `0xE0` | Preset Counters | 0 |

The `bit 7-5 = command` encoding means the low 5 bits are combined
with the command opcode for Start Display, i.e., `0x23` = `0b001_0_0011`
is Start-Display (`001_xxxxx`) with burst mode / burst space / etc.

### Values we write

From `init.c:93-102` (initialization), `isr.s:139-144` (cursor update):

```
CMD   ← 0x00    ; Reset command — next 4 PARAM bytes configure geometry
PARAM ← 0x4F    ; Screen Composition byte 0
PARAM ← 0x98    ; Screen Composition byte 1
PARAM ← 0x7A    ; Screen Composition byte 2
PARAM ← 0x6D    ; Screen Composition byte 3
CMD   ← 0x80    ; Load Cursor Position — next 2 PARAM bytes are col, row
PARAM ← 0x00    ; column = 0
PARAM ← 0x00    ; row = 0
CMD   ← 0xE0    ; Preset Counters (aligns DMA to display start)
CMD   ← 0x23    ; Start Display (+ burst parameters)
```

### Reset parameter bytes

These configure frame geometry.  Bit layout per byte (from datasheet):

**PARAM[0]** `0x4F` = 0b`01001111`:
- bit 7:    `S`    = 0 → spaced rows disabled
- bits 6-0: `HRTC` = 79 → horizontal characters per row − 1 = 79 → **80 chars/row**

**PARAM[1]** `0x98` = 0b`10011000`:
- bits 7-6: `VRTC` = 10 → vertical retrace rows count (encoded ÷2 + adjustments)
- bits 5-0: `VR`   = 24 → **25 rows per frame** (−1)

**PARAM[2]** `0x7A` = 0b`01111010`:
- bits 7-4: `U`    = 7 → underline line position within char cell (line 7)
- bits 3-0: `L`    = 10 → **11 scan lines per row** (−1), but our VRTC bit-6 of PARAM[1]
  combines with this; our 7 scan lines/row figure is derived

**PARAM[3]** `0x6D` = 0b`01101101`:
- bit 7:    `M`    = 0 → line counter mode = row count
- bit 6:    `F`    = 1 → field attributes mode
- bits 5-4: `C`    = 10 → character set select / cursor format: block/blink
- bits 3-0: `LC`   = 13 → horizontal retrace count (HRTC width)

The exact bit split here is the most fiddly 8275 config; all four
bytes need to match rcbios/MAME expectation or the display distorts.
If you need to alter geometry, copy values from MAME's `rc702.cpp`
rather than re-derive.

### Load Cursor Position

`CMD ← 0x80` then two PARAM bytes, column-then-row.  Both are 0-based:
`(0, 0)` is top-left.  Our `_isr_crt` writes new cursor when
`cur_dirty` is set (isr.s:139-144) — matches what a Phase 19c
refactor moved off the per-character impl_conout.

### Start Display

`CMD ← 0x23` = 0b`001_00011`:
- bits 7-5: `001` = Start Display command
- bits 4-3: `00` = burst count 1 (chars per DMA burst)
- bits 2-0: `011` = burst space 3 (char clocks between bursts)

Burst-count=1 + burst-space=3 → the DMA requests a single byte every
4 char-clock times, which is comfortably within the 8275's buffer
requirements.

---

## µPD765 FDC — 0x04 (STATUS) / 0x05 (DATA)

**Not driven by cpnos-rom** — CP/NOS is a diskless slave by design:
all storage goes over CP/NET to the host (see
`tasks/cpnos-next-steps.md` Phase 20 / `project_cpnos_no_local_floppy`).
cpbdos implements only BDOS fn 0..12, so the BIOS JT's disk slots are
never reached and are wired to `bios_stub_ret`.  Section retained as a
forward-looking reference for any future non-CP/NOS variant.

Short preview: the FDC takes commands as a sequence of bytes written
to the DATA port, with **readiness** polled on the STATUS port via
the `RQM` (Request for Master) and `DIO` (Data In/Out direction)
bits.  Reading result bytes uses the same polling-and-read pattern.

---

## Sidecar ports — 0x18 RAMEN, 0x1C BIB

### `0x18` RAMEN — "disable PROMs"

```
_port_out(PORT_RAMEN, 0x00);    // cpnos_main.c:55
```

The **written value is ignored** — any write to port `0x18` on the
RC702 (MIC702/MIC703) triggers a flipflop that disables both PROM
mappings (PROM0 at `0x0000..0x07FF` and PROM1 at `0x2000..0x27FF`),
exposing the RAM underneath.  Once disabled, there's no way to re-enable
them short of a reset — this is deliberately one-shot hardware.

We emit `0x00` by convention (matches rcbios/autoload).  `0xFF`, `0x42`,
anything else would have identical effect.  See `MIC702`/`MIC703` note
in `RC702_HARDWARE_TECHNICAL_REFERENCE.md` for the four-variant matrix
of PROM-enable ports (`0x18`, `0x19`, `0x1A`).

Timing: must be called from code that lives **above** the PROM address
range — we call it from the payload at `0xED00` after the relocator
has put us there.  Calling from PROM0-resident code would yank the PC
out of existence mid-instruction.

### `0x1C` BIB — "beeper"

```
case 0x07: _port_out(PORT_BIB, 0); break;    // resident.c:249 (BEL ctrl code)
```

Another write-any-byte port.  A write triggers a 614.4 kHz-derived
beep pulse of fixed ~100 ms duration.  Pitch and length are hardware-
controlled; software only triggers.  Used only as the CONOUT handler
for ASCII BEL (0x07).

---

## Index of all OUT callsites in the payload

Mechanically enumerated from the source (`_port_out()` and raw
`out (nn), a`).  Line numbers valid as of Phase 19c.

| Callsite | Port | Value(s) | Purpose |
|----------|:----:|----------|---------|
| `init.c:48-52` | 0x0C/0x0D/0x0E (CTC0/1/2) | `0x00 / 0x47 / 0x01 / 0x47 / 0x01 / 0xD7 / 0x01` | SIO-A/B baud clock + CRT refresh interrupt source |
| `init.c:56-60` | 0x0A (SIO-A CTRL) | `0x18 / 0x04 0x44 / 0x03 0xE1 / 0x05 0x6A / 0x01 0x00` | SIO-A 8N1 38400 baud |
| `init.c:63-68` | 0x0B (SIO-B CTRL) | `0x18 / 0x02 0x10 / 0x04 0x44 / 0x03 0xE1 / 0x05 0x6A / 0x01 0x00` | SIO-B same + vector base 0x10 |
| `init.c:71-73` | 0x12 (PIO-A CTRL) | `0x20 / 0x4F / 0x83` | Keyboard input + IRQ vector 0x20 |
| `init.c:76-89` | 0xF8/0xFB/0xFC/0xF4/0xF5/0xF7/0xFA | `0x20 / 0x5A 0x5B / 0x00 / 0x00 0xF8 / 0xCF 0x07 / 0x00 0x00 / 0x02 0x03` | Display DMA init |
| `init.c:93-102` | 0x01 (CRT CMD) + 0x00 (CRT PARAM) | `0x00 / 0x4F 0x98 0x7A 0x6D / 0x80 / 0x00 0x00 / 0xE0 / 0x23` | 8275 reset + geometry + start |
| `cpnos_main.c:55` | 0x18 (RAMEN) | `0x00` | Disable both PROMs |
| `resident.c:32` | 0x09 (SIO-B DATA) | variable | Console-mirror transmit |
| `resident.c:249` | 0x1C (BIB) | `0x00` | Bell (ASCII BEL handler) |
| `transport_sio.c:17` | 0x08 (SIO-A DATA) | variable | CP/NET transport transmit |
| `isr.s:90/92` | 0xFA (DMA SMSK) | `0x06 / 0x07` | Set ch2/3 mask (disable) |
| `isr.s:96` | 0xFC (DMA CLBP) | `0x00` | Clear byte-pointer FF |
| `isr.s:100/102` | 0xF4 (DMA CH2 ADDR) | `0x00 0xF8` | Reload display base |
| `isr.s:106/108` | 0xF5 (DMA CH2 WC) | `0xCF 0x07` | Reload word count (1999) |
| `isr.s:112/113` | 0xF7 (DMA CH3 WC) | `0x00 0x00` | Zero attribute WC |
| `isr.s:117/119` | 0xFA (DMA SMSK) | `0x02 / 0x03` | Clear ch2/3 mask (enable) |
| `isr.s:123/125` | 0x0E (CTC2) | `0xD7 / 0x01` | Re-arm VRTC counter |
| `isr.s:140` | 0x01 (CRT CMD) | `0x80` | Load cursor command |
| `isr.s:142/144` | 0x00 (CRT PARAM) | `curx / cury` | Cursor x, y |
