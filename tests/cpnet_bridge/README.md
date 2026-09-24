# CP/NET fast-link bring-up smoke test (MAME-side)

End-to-end verification of the host -> Z80 byte path of Option P
(see [`../../docs/cpnet_fast_link.md`](../../docs/cpnet_fast_link.md)).

## What it tests

```
Python harness.py
  -> TCP localhost:4003
    -> rc702_pio_cpnet_bridge_device  (MAME slot card on PIO-B)
      -> Z80 PIO-B Mode 1 input + ISR fires
        -> isr_pio_par reads byte, stores at 0xEA39, increments counter at 0xEA3A
          -> tap.lua write-tap on the counter prints "[tap] count=N byte=0xHH"
            -> harness matches stdout against expected bytes
```

PASS = all sent bytes round-trip and end up in the Z80 BSS counter
in order.

## Prerequisites

1. **MAME built with the `cpnet-fast-link` slot infrastructure.**
   `ravn/mame-rc702-rc759-rc750:cpnet-fast-link` branch built as
   `/Users/ravn/z80/mame/regnecentralend`.  See
   [`../../docs/MAME_RC702.md`](../../docs/MAME_RC702.md) for the build
   command.

2. **`cpnos-rom` built** so `isr_pio_par` is in the payload.
   ```
   cd cpnos-rom && make cpnos
   ```

3. **A working CP/NET netboot path.**  In MAME the autoload PROM
   waits for the netboot server before the Z80 ever runs cpnos-rom's
   `init_hardware()` (which is what arms PIO-B for IRQ-driven
   receive).  Without CP/NET running, the harness will time out
   because no tap lines appear — the Z80 hasn't enabled interrupts
   yet.

   See [`../../cpnet/run_test.sh`](../../cpnet/run_test.sh) for the
   standard z80pack-as-master-on-:4002 setup.

## Usage

```
python3 tests/cpnet_bridge/harness.py
```

Optional flags:

- `--keep-alive` — leave MAME running after the byte send so you can
  poke at it with the debugger or send more bytes manually.
- `--mame-bin /path/to/regnecentralend` — override the MAME binary.
- `--roms /path/to/roms` — override the ROMs path
  (default: `~/git/mame/roms`, also `MAME_ROMS` env var).
- `--seconds N` — overall timeout in seconds (default 20).

Exit codes:
- `0` — PASS, all bytes round-tripped.
- `1` — FAIL with a reason printed to stderr.

## Files

- `harness.py` — the Python harness (above).
- `tap.lua` — MAME autoboot script that installs a write-tap on the
  cpnos-rom BSS counter and emits one stdout line per write.
- `README.md` — this file.

## Address pinning

The tap watches the BSS variables `_pio_par_byte` and `_pio_par_count`
in `cpnos-rom/resident.c`.  Their addresses are not hardcoded — the
harness extracts them from `cpnos-rom/clang/payload.elf` via
`llvm-nm` on every run and writes them as a Lua table to
`/tmp/cpnos_bridge_addrs.lua`, which `tap.lua` reads via `dofile`.
This survives BSS-layout shifts (which silently broke the test before
2026-04-26).

## Caveats

- Bring-up scaffolding only.  The real CP/NET transport will replace
  `isr_pio_par` with a frame-aware ring buffer; this harness will be
  superseded by a frame-level round-trip test once the protocol layer
  lands.
- Mac/Linux only — the cpnet_bridge MAME device uses POSIX sockets.
  Windows builds disable the device with a logerror.
