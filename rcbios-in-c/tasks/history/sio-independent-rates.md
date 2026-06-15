# SIO-A split TX/RX rates — RESOLVED: not possible

**Status:** resolved 2026-04-18. TxCA and RxCA are tied to the same CTC
channel output.

## Finding

CTC channel 0 drives a single wire to **both** TxCA and RxCA on SIO
channel A. Confirmed from MIC 02 schematic (page 59 of the RC702/RC703
Microcomputer Technical Manual, RCSL 44-RT2056). Also verified in
MAME's rc702.cpp driver (CTC1 zc_callback<0> goes to both txca_w and
rxca_w).

All four CTC channels are allocated:
- Ch 0 (port 0x0C): SIO-A baud rate (TxCA + RxCA)
- Ch 1 (port 0x0D): SIO-B baud rate (TxCB + RxCB)
- Ch 2 (port 0x0E): CRT 8275 VRTC interrupt
- Ch 3 (port 0x0F): FDC uPD765 interrupt

No spare CTC channel exists to clock TX and RX independently.

## Consequence

SIO-A TX and RX always run at the same baud rate. The split-channel
transport cannot have 250 kbaud TX with 38400 RX on the same channel.
Either both run at 250 kbaud (RX unreliable for continuous async data)
or both at 38400 (reliable but slow).

## Alternatives identified

1. **HDLC/NRZI synchronous mode** on SIO-A with internal DPLL clock
   recovery. Bidirectional, potentially 250 kbit/s. SIO-A dedicated to
   CP/NET. See `cpnet/SPLIT_CHANNEL_TRANSPORT.md`.
2. **PIO parallel port** for the PC->RC702 direction, SIO-A TX-only for
   RC702->PC. Same split-channel doc.
3. **J8 bus expansion** with DMA channel 0. ~500-1000 KB/s. Requires
   external board. See `docs/j8_bus_expansion.md`.
