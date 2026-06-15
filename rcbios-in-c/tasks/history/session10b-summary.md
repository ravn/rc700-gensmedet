# Session 10b Summary (2026-04-05)

Continuation of session 10. Focus: reliable serial transfer to
physical RC700, BIOS flow control improvement.

## Completed

### Serial transfer pipeline (verified working)

Full workflow for updating BIOS on physical RC700 hardware:

1. Build: `rm -f builddate.h clang/*.o && make bios`
2. Generate BIOS-only hex: `python3 mk_sysgen_hex.py clang/bios.cim clang/sysgen_bios.hex`
3. Copy to Linux: `scp clang/sysgen_bios.hex ravn@ravn-MacBookPro12-1.local:/tmp/`
4. On RC700: `PIP CPM56.HEX=RDR:`
5. Send: `ssh ravn@... 'python3 /tmp/send_hex_rtscts.py /dev/ttyUSB1 38400 /tmp/sysgen_bios.hex'`
6. On RC700: `MLOAD CPM56.COM=BDOSCCP.COM,CPM56.HEX` → `CPM56` → `SYSGEN CPM56.COM`

Transfer time: ~24 seconds for 363 records at 38400 baud.

### RTS flow control improvement

Changed BIOS READER to only re-assert RTS when the ring buffer is
**completely empty**, instead of using a low watermark (RXTHLO=240).

- Before: RTS reasserted when buffer < 240 bytes → rapid CTS cycling
  (5300 drops per transfer), potential for FTDI TX buffer overshoot
- After: RTS reasserted only when buffer empty → far fewer CTS cycles
  (59 drops per transfer), sender stays paused during disk writes

Change: `bios.c` line 1284-1286, replaced `used < RXTHLO` with
`new_tail == rxhead`.

Result: 2 bytes smaller (5635→5633), dramatically fewer CTS drops.

### macOS FTDI flow control investigation

Investigated why hardware flow control fails on macOS:

- **FTDI chip honors CTS in hardware** (confirmed by FTDI AN232B-04)
  — the chip stops transmitting within 0-3 characters of CTS going inactive
- **macOS problem**: `tcdrain()`/`flush()` returns in 0.0ms — the macOS
  FTDI kernel driver accepts data into a large kernel buffer and doesn't
  block until the chip's TX buffer is drained
- **Linux works**: the `ftdi_sio` driver properly blocks `tcdrain()` until
  the chip's TX buffer is empty
- **Conclusion**: use Linux for serial transfers. macOS needs pyftdi
  (direct USB, bypassing kernel driver) or libusb, neither easily available

### mk_sysgen_hex.py updated

- 16-bit checksum (was 8-bit)
- No zero-skip in BIOS region (prevents checksum mismatch)
- Split checksum over side 0 + side 1, skipping gap

### mk_cpm56.py updated

- 16-bit checksum validator
- No zero-skip in BIOS region
- Single Ctrl-Z in sender script (was double, caused stale buffer)

### FTDI AN232B-04 key findings

From FTDI's own app note "Data Throughput, Latency and Handshaking":
- FTDI chip can buffer up to 384 bytes
- RTS/CTS: chip transmits if CTS active, drops RTS if can't receive
- DTR/DSR: alternative 2-wire handshake (chip transmits if DSR active)
- "It is strongly encouraged that flow control is used because it is
  impossible to ensure that the FTDI driver will always be scheduled"
- USB packet-based nature means flow control is not byte-precise

### PIP options documented

Full PIP parameter table from CP/M 2.2 manual captured.
Key: `[H]` validates hex format during transfer, `[V]` verifies disk write.
`[B]` buffers until XOFF (Ctrl-S), not useful for our case.

## Files modified

- `bios.c` — RTS reassert on empty buffer (was low watermark)
- `mk_sysgen_hex.py` — 16-bit checksum, no zero-skip
- `mk_cpm56.py` — 16-bit checksum, no zero-skip
- `docs/serial_cable_wiring.md` — verified working configuration

## Open items

- [ ] IOBYTE support in BIOS for remote console control
- [ ] Investigate 115200 baud (SIO WR4 clock mode ×1)
- [ ] SAVE 68 BDOSCCP.COM on RC700 (one-time setup)
- [ ] Test PIP with [HV] options for hex-validated transfer
- [ ] macOS: investigate pyftdi for direct FTDI USB control
