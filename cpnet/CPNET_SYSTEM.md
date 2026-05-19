# CP/NET System for RC702

## Quick Reference

**Status:** ✅ Production Ready
**Validation:** [TEST_RESULTS.md](TEST_RESULTS.md) (full test report)

## What is CP/NET?

CP/NET is a network file system for RC702 running CP/M 2.2. It allows mounting remote file servers as network drives (e.g., `H:`), enabling file transfer and file operations over a serial connection.

### Architecture

```
CP/M Application
      ↓
CP/M BDOS (calls intercepted by NDOS)
      ↓
NDOS (Network DOS) — Route F14-F23, F39, F70 to network
      ├─ Local: Pass to original BDOS for A:/B: drives
      └─ Remote: Call SNIOS for H: drive
           ↓
SNIOS (Network I/O) — DRI binary serial protocol
      ├─ ENQ/ACK/SOH/STX/ETX/EOT framing
      ├─ Two's complement checksum
      └─ NAK + retry on error (10 attempts)
                ↓
         Serial Port (38400 baud, RTS flow control)
                ↓
         Server (Python TCP bridge or real hardware)
```

See [DRI_PROTOCOL.md](DRI_PROTOCOL.md) for full protocol specification.

## Components

### On Disk

| File | Size | Purpose |
|------|------|---------|
| CPNETLDR.COM | 1.5 KB | Loader: copies SNIOS & NDOS, patches BDOS vector |
| SNIOS.SPR | 1.0 KB | Network I/O: DRI binary protocol, send/receive |
| NDOS.SPR | 3.7 KB | Network DOS: BDOS interception, drive mapping |
| NETWORK.COM | varies | Utility: assigns network drives (`NETWORK H:=B:`) |
| CCP.SPR | 3.2 KB | CP/M shell (required by CPNETLDR) |

### In RAM (after CPNETLDR initialization)

| Address | Size | Component |
|---------|------|-----------|
| 0005h | 2B | BDOS vector (patched to point to NDOS) |
| BC06h | ~1 KB | NDOS entry point |
| B800h | ~2 KB | SNIOS routines |
| DA00h+ | 6 KB | BIOS (unchanged) |

## Quick Start

### 1. Prepare Disk Image

```bash
cd rcbios
# Build custom 38400 baud BIOS
make rel30-maxi
# Patch BIOS onto disk
python3 patch_bios.py /path/to/disk.imd zout/BIOS.cim
# Inject CP/NET files (cpmtools3 must be on PATH)
cpmcp -f rc702-8dd /path/to/disk.imd ~/git/cpnet-z80/dist/ccp.spr 0:CCP.SPR
cpmcp -f rc702-8dd /path/to/disk.imd zout/SNIOS.SPR 0:SNIOS.SPR
cpmcp -f rc702-8dd /path/to/disk.imd ~/git/cpnet-z80/dist/ndos.spr 0:NDOS.SPR
cpmcp -f rc702-8dd /path/to/disk.imd ~/git/cpnet-z80/dist/cpnetldr.com 0:CPNETLDR.COM
cpmcp -f rc702-8dd /path/to/disk.imd ~/git/cpnet-z80/dist/network.com 0:NETWORK.COM
```

### 2. Start Server

```bash
cd cpnet
python3 server.py --port 4321 --wait --drive-dir B /path/to/files
```

### 3. Boot RC702 in MAME

```bash
cd ../mame
./mame -rc702 -flop /path/to/disk.imd \
    -rs232a null_modem -bitb socket.localhost:4321 \
    -autoboot_script ../rc700-sysgen/cpnet/cpnet_manual.lua
```

### 4. Use Network Drive

```
A>CPNETLDR          ; Load network system (node ID 1)
SNIOS active
A>NETWORK H:=B:    ; Mount remote directory as H:
A>DIR H:           ; List remote files
A>TYPE H:README    ; Display remote file
A>CHKSUM H:DATAFILE.DAT ; Verify file integrity
```

## BDOS Functions Supported

| F# | Name | Status |
|----|------|--------|
| F14 | Select Disk | ✅ Switch to network drive |
| F15 | Open File | ✅ Open file on network |
| F17 | Search First | ✅ List directory |
| F18 | Search Next | ✅ Continue listing |
| F20 | Read Sequential | ✅ Read 128B records |
| F21 | Write Sequential | ✅ Write records |
| F39 | File Info | ✅ File control |
| F70 | Network Status | ✅ Check connection |

See TEST_RESULTS.md for detailed protocol testing results.

## `$$$` filename rewrite (per-client temp files)

CP/NET's NDOS rewrites filenames that start with `$$$` before sending
them to the server.  The first three chars become `$NN` where `NN` is
the two hex digits of the slave's CP/NET network ID (`BSRID` byte at
`CFGTBL+1`).  Examples for a slave with `BSRID=0x01`:

  | Source filename | What master sees |
  | --------------- | ---------------- |
  | `$$$.SUB`       | `$01.SUB`        |
  | `$$$.SET`       | `$01.SET`        |
  | `$$$$$$.TMP`    | `$01$$$.TMP`     |

Purpose: temp files for SUBMIT (`$$$.SUB`), STAT mode-set
(`$$$.SET`), etc. need to be **per-client unique** so multiple slaves
on the same CP/NET don't trample each other's work.  CP/M was written
assuming `$$$.SUB` was unique on the local A: -- on a shared remote
A: drive that assumption breaks unless the name is mangled in.

Mechanism: slave-side, not server-side.  `CKDOL` in
`~/git/cpnet-z80/src/ndos3.asm:679` walks the FCB filename, and when
the first three chars are all `$`, increments a counter (`FNTMPF`)
and writes `$NN` over those three bytes using the slave's BSRID from
its CFGTBL.  The server sees the rewritten name on every FCB-bearing
BDOS call and treats it as ordinary, distinct.

Implications for our test harnesses (e.g.
`cpnet/polypascal_pio_test.sh`):

  * Pre-staging a `$$$.SUB` on the slave's *local* A: floppy (with
    `cpmcp ... '0:$$$.SUB'`) is fine -- the slave's CCP processes
    it locally without NDOS-rewrite, because local-disk BDOS calls
    don't route through SNIOS.
  * Pre-staging on the *master*'s A: drive (e.g. for a slave that
    `H:` 's into master A: and expects to see `$$$.SUB`) would need
    the file named `$NN.SUB` matching the slave's BSRID, **not**
    `$$$.SUB`, because that's the actual filename the server has.
  * Any debug listing on the master that shows `$01.SUB`, `$02.SUB`,
    ... is fine and expected -- those are SUBMIT-temp files for
    slaves 0x01, 0x02, etc.

## Serial Protocol

Uses the standard DRI binary serial protocol. See [DRI_PROTOCOL.md](DRI_PROTOCOL.md)
for the complete specification.

### Frame Summary

```
Send: ENQ -> ACK -> SOH+header(5)+HCS -> ACK -> STX+data+ETX+CKS+EOT -> ACK
Recv: ENQ -> ACK -> SOH+header(5)+HCS -> ACK -> STX+data+ETX+CKS+EOT -> ACK
```

- **Framing:** ENQ/ACK handshake, SOH/STX/ETX/EOT delimiters
- **Encoding:** Raw binary (8-bit clean, no hex encoding)
- **Checksum:** Two's complement sum (single byte)
- **Error recovery:** NAK triggers retry, up to 10 attempts

## Performance

- **Baud Rate:** 38400
- **Effective Speed:** ~4.8 KB/sec (binary protocol, no encoding overhead)
- **Ring Buffer:** 256 bytes (page-aligned)
- **Flow Control:** RTS/CTS hardware handshake
- **Max Stable Transfer:** 204 KB+ (tested with BIGFILE.DAT)

## Testing

### Automated Test Suite

```bash
bash cpnet/run_test.sh [--build] [--headless] [--auto]

Options:
  --build      Rebuild SNIOS.SPR, patch BIOS, inject files
  --headless   Run MAME without display (CI/automated)
  --auto       Automated Lua test (file verification, network ops)
```

### Test Coverage

- ✅ SNIOS initialization (FNC=0xFF handshake)
- ✅ NDOS loading (BDOS vector patching)
- ✅ Network disk mounting (NETWORK command)
- ✅ Directory listing (DIR H:)
- ✅ File reading (TYPE H:)
- ✅ Large file transfer (204 KB)
- ✅ DRI binary protocol framing (ENQ/ACK/SOH/STX/ETX/EOT)
- ✅ Two's complement checksum verification
- ✅ Zero packet loss (all records delivered)

See TEST_RESULTS.md for full test results.

## Troubleshooting

### "CP/NET init error"

**Symptom:** CPNETLDR prints error instead of "SNIOS active"

**Cause:** Server not responding to FNC=0xFF handshake

**Fix:**
1. Verify server is running: `python3 server.py --port 4321`
2. Check MAME null_modem is configured: `-bitb socket.localhost:4321`
3. Verify baud rate: Lua script sets 38400 (0x0b in RS232_BAUD)

### "Network drive assignment failed"

**Symptom:** `NETWORK H:=B:` returns error

**Cause:** SNIOS not loaded or NDOS vector not patched

**Fix:**
1. Ensure CPNETLDR ran successfully
2. Check BDOS vector changed (use DEBUG.COM or similar)
3. Verify server.py listening on correct port

### "File not found on network drive"

**Symptom:** `DIR H:` or `TYPE H:FILE` returns "?"

**Cause:** File doesn't exist on server, or path misconfigured

**Fix:**
1. Verify file exists in server directory: `ls /path/to/files/`
2. Check server was started with correct `--drive-dir`: `python3 server.py --drive-dir B /path`
3. Verify file is uppercase (CP/M 8.3 naming)

### Serial timeout / "Retry? Y/N"

**Symptom:** BDOS F20 (Read) times out after network operation

**Cause:** RTS flow control issue or serial buffer overflow

**Fix:**
1. Enable RTS in MAME Lua: `field.user_value = 0x01`
2. Increase SIO ring buffer size (currently 256B)
3. Reduce baud rate temporarily (test at 19200)

## Files

### Source Code
- `snios.asm` - Z80 SNIOS: DRI binary protocol implementation
- `server.py` - Python CP/NET server (localhost TCP bridge)
- `build_snios.py` - SNIOS assembler wrapper (builds SPR with relocation bitmap)
- `autotest.lua` - MAME Lua automation script
- `run_test.sh` - Test orchestration shell script

### Reference
- `DRI_PROTOCOL.md` - DRI binary serial protocol specification
- `SPR_FORMAT.md` - Relocatable program file format
- `TEST_RESULTS.md` - Full validation test report

### Related
- `~/git/cpnet-z80/` - Original SNIOS/NDOS source (Reference)
- `~/git/mame/src/mame/regnecentralen/rc702.cpp` - MAME rc702 emulation

## References

- **DRI Protocol:** Digital Research CP/NET Operating System Manual, Appendix E
- **Z80 Assembly:** Based on cpnet-z80 `src/ser-dri/snios.asm`
- **RC702 Hardware:** http://www.jbox.dk/rc702/

---

**Last Updated:** 2026-03-07
**Protocol:** DRI binary serial (ENQ/ACK framing, two's complement checksum)
**Validation Status:** COMPLETE
**Test Results:** See TEST_RESULTS.md
