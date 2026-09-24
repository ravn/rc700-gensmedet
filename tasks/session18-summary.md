# Session 17: SIO-B Receive + Baud Rate Experiments (2026-04-11/12)

## Goal
Get SIO-B serial receive working in MAME and investigate faster baud rates.

## Bugs Found and Fixed

### 1. MAME driver: rs232b missing null_modem (ravn/mame-rc702-rc759-rc750#1)
- `rs232b` had `nullptr` as default device — no null_modem attached
- Added `"null_modem"` default + `rs232b_defaults` (38400 8N1)
- Also wired `dcd_handler` for rs232b (from prior session)
- Side effect: two bitbangers now exist → `-bitb` became `-bitb1`/`-bitb2`
- Updated all scripts: `run_mame.sh`, `run_test.sh`, Makefile, server comments

### 2. Clang Z80 codegen: switch discriminant stale register (ravn/llvm-z80#69)
- `bios_reader_body()` switch on `IOBYTE_RDR(iobyte)` compiled to:
  ```asm
  and #3        ; A = discriminant (correct)
  cp  #2
  jr  nc, .L2   ; first branch uses A ✓
  ...
  .L2:
  ld  a, d      ; BUG: loads stale D, not discriminant
  cp  #2        ; IOB_BAT case unreachable unless D=2 by accident
  ```
- **Workaround**: restructured `switch` to `if-else` with explicit local variable
  `byte rdr = IOBYTE_RDR(iobyte)` — compiler then emits `ld d,a` to preserve it
- Same fix applied to `bios_reads_body()`
- Cost: +2 bytes (5965 → 5971 with other changes)
- XFAIL lit test: `llvm/test/CodeGen/Z80/switch-byte-field.ll`

### 3. Test program: BIOS READER clobbers registers
- BIOS calls (READER, READS) clobber B, C, D, E per sdcccall(1)
- Test program's DJNZ loop counter (B) and timeout counter (DE) were destroyed
- Fix: PUSH/POP BC and DE around BIOS calls

### 4. Test program: IOBYTE routing during BDOS calls
- BIOS READER routes through IOBYTE, but CP/M BDOS temporarily modifies IOBYTE
  during console I/O (observed IOBYTE=0x97 instead of expected 0x9B)
- Caused READER to read from SIO-A buffer instead of SIO-B
- Fix: bypass BIOS READER, read SIO-B ring buffer directly
  (rxhead_b/rxtail_b/rxbuf_b at BSS addresses from `nm bios.elf`)

### 5. SIO-B ring buffer not flushed at boot
- SIO-A buffer flushed at cold boot (rxhead=rxtail=0), but SIO-B wasn't
- Added `rxhead_b = 0; rxtail_b = 0;` to cold boot path

## Baud Rate Experiment

Created parameterized test: `make siob-baud BAUD_IDX=N`

| IDX | Rate | CTC | SIO mode | Result |
|-----|------|-----|----------|--------|
| 0 | 38400 | count=1 | ×16 | **PASS** |
| 1 | 76800 | count=8 | ×1 | **FAIL** — timeout |

### Analysis

**38400 is the hardware maximum for async serial** on the RC700:
- 614.4 kHz baud rate crystal → CTC minimum divisor 1 → 614.4 kHz
- SIO ×16 async mode → 614400 / 16 = 38400 baud
- SIO ×1 mode: no oversampling, clock/data phase misalignment even in MAME's
  digital simulation → receiver samples at bit transitions, not bit centers

**Synchronous mode** could theoretically give 5-20× improvement but requires:
- Shared clock wire (CTC ZC1 not routed to RS-232 connector)
- Non-standard host interface (FTDI only does async)
- Not viable with current cable/hardware

**DMA transfers**: not possible — no DREQ from SIO to DMA controller.

**Conclusion**: 38400 baud (~3.8 KB/s) is the practical ceiling for the
RC700's serial port with standard async serial and existing hardware.

## Commits (branch: sio-b-test-console)

1. `ee4dbf1` — Fix SIO-B receive: clang codegen workaround + MAME bitbanger updates
2. `9f4531a` — Fix SIO-B test: direct ring buffer access, flush at boot
3. `0c43cc6` — Add SIO-B baud rate experiment

## Issues Filed

- ravn/mame-rc702-rc759-rc750#1 — RC702: rs232b missing null_modem default and DCD wiring
- ravn/llvm-z80#69 — Switch on shifted byte field uses stale register for second case

## Open Items

- [ ] Merge `sio-b-test-console` to `main` — all tests pass, SIO-B works
- [ ] IOBYTE mystery: BDOS temporarily changes IOBYTE during console I/O
  (observed 0x97 instead of 0x9B). Root cause not fully traced — workaround
  (direct buffer access) is sufficient for now
- [ ] Parallel port investigation blocked on DB-25 cable (see todo.md)
