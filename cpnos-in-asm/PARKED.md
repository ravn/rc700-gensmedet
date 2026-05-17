# cpnos-in-asm — PARKED 2026-05-17

Superseded by cpnos-in-c's PROM1-only line-program build, which now
satisfies the original "CP/NOS slave fits entirely in PROM1 (2 KB)
alongside autoload-in-c in PROM0" goal that cpnos-in-asm was created
to chase.

This file documents where cpnos-in-asm landed and what would be
missing if anyone resumes work on it.

## Reason for parking

cpnos-in-asm was the asm-side complement to the compiler-side push
"fix llvm-z80 codegen until CP/NOS fits in PROM 1 (2 KB)".  As long
as cpnos-in-c needed both PROM0 + PROM1 (its 1858 B resident split
into a 736 B PROM0 chunk + 1122 B PROM1 chunk via the data-driven
relocator), the asm slave was the fallback for environments that
needed a clean "autoload in PROM0, CP/NOS in PROM1" deployment.

On 2026-05-17 the cpnos-in-c build gained a `prom1-lineprog` target
(see `../cpnos-in-c/clang-prom1lineprog/` and
`../cpnos-in-c/tasks/zx0-prom1-only-plan-2026-05-17.md`) that:

- ZX0-compresses `init.bin` (627 -> 545 B) and `payload.bin`
  (1858 -> 1275 B), sharing one 68 B `dzx0_standard` decoder.
- Builds a single 2 KB PROM1 image (1922 B used, 126 B free)
  satisfying autoload-in-c's `prom1_if_present` signature contract
  (" RC702" at PROM1 offset 0x0002 + jump target at 0x0000).
- Boots via the same chain cpnos-in-asm uses: autoload PROM0 ->
  PROM1 signature detect -> bootstrap_entry -> JP cpnos_cold_entry.
- PASSes the same `polypascal_test` end-to-end value oracle
  (PPAS -> R PRIMES -> 29989 -> Q -> E>) under clang × PIO.

cpnos-in-c is therefore the production CP/NOS slave going forward.
The C variant is easier to extend, gets automatic shrinkage from
llvm-z80 codegen improvements, and shares its codebase with the
disk-bound cpnos.com.  cpnos-in-asm's value proposition (PROM1 fit
when C wouldn't) no longer exists.

## How far cpnos-in-asm got

**End-to-end functional CP/NOS slave** that boots from autoload's
PROM1 line program handoff, brings up its own display + SIO + CP/NET
transport, fetches cpnos.com via CP/NET 1.2 LOGIN/OPEN/READ from
z80pack mpm-net2, hands off to NDOS, and supports running CP/M
programs that exercise console + disk I/O.

Concrete capabilities verified:

| Capability                                  | Status |
| ------------------------------------------- | ------ |
| Autoload PROM0 -> PROM1 signature chain     | DONE — phase 1, session 73e |
| Display + SIO + CTC + DMA cold init         | DONE — phase 2a, session 73e |
| SIO-B operator console (banner + echo)      | DONE — phase 2b, session 73e |
| CP/NET 1.2 frame send (header + data + EOT, HCS/CKS) | DONE — phases 3a/3b, session 73e |
| SIO-A as CP/NET wire, SIO-B as operator console | DONE — phase 3c, session 73e |
| CP/NET 1.2 receive (HCS/CKS validation, ACK/NAK) | DONE — phase 3d-γ, session 73e |
| ENQ/ACK handshake on transmit                | DONE — phase 3d-β, session 73e |
| LOGIN frame (real master interop, mpm-net2)  | DONE — phase 3e/g, session 73f |
| Full netboot (LOGIN/OPEN/READ-seq/CLOSE)     | DONE — phase 4a, session 73f |
| MAXRETRY + LOGIN decode + ack-and-loop       | DONE — phases 3f/3g, session 73f |
| ZX0-compressed SNIOS payload (saves ~260 B)  | DONE — session 73e |
| NDOS handoff (RAMEN OUT, jp 0xDD80)          | DONE — session 73f |
| Resident SNIOS jump tables at 0xED00..0xED4A | DONE — same layout as cpnos-in-c |
| PolyPascal end-to-end (PPAS PRIMES = 29989)  | PASS — session 73f, re-verified this session |
| CONOTEST.COM stress test                     | PASS — commit a358bb0 |
| Full RC700 text-mode control codes (15 of 18) | DONE — commit 3a31ec9 |
| PROM1 fit                                   | 1566 / 2048 B (482 B free) |

## What is missing

### Graphics-mode CONOUT codes (3 of 18)

`impl_conout` in `src/snios_payload.asm` implements 15 of 18 active
slots in the canonical RC700 BIOS `SPECC` jump table
(`../rcbios/src/DISPLAY.MAC` line 504 `TAB1`).  Missing:

- **0x14 SET_BACKGROUND** (`ESCSB`) — graphics-overlay bitplane set
- **0x15 SET_FOREGROUND** (`ESCSF`) — graphics-overlay bitplane set
- **0x16 CLEAR_FOREGROUND** (`ESCCF`) — graphics-overlay bitplane clear

These drive the RC702 optional 200x240 monochrome bitmap overlay
(separate display RAM, requires `BGFLG` / `BGSTAR` state cpnos has
no equivalent for).  Standard CP/M utilities (CCP, BDOS-disk
programs, PolyPascal, WordStar) don't touch them, so the omission
hasn't surfaced as a failing test, but the README's "full RC700
control-code set" claim was overstated -- it's the full **text-mode**
set.  This gap was discovered during the 2026-05-17 cross-check
against `DISPLAY.MAC:TAB1`.

cpnos-in-c also lacks these three codes; the gap is the same on
both variants and tracks back to a shared design choice (text-mode
only).

### RC703 hardware (later boards)

README section "PROM enable/disable scheme" notes:

> later RC703 models had a more advanced PROM enable/disable scheme
> than the RC702 single-port RAMEN mechanism

Before settling on the current `OUT (0x18), A` disabler in
`src/snios_payload.asm`, the RC703 BIOS sources at
`../rc703-div-bios-typer/` should be audited for the actual hardware
contract on those later boards.  Not done — the cpnos-in-asm slave
has only been verified on MAME's RC702 driver.

Same gap exists in cpnos-in-c (same RAMEN OUT).  Resolving for one
variant resolves it for both (the disable is RAM-resident on both,
moved out of the PROM by the handoff stub).

### Coverage of less-exercised CP/NOS functions

`src/snios_payload.asm` implements the BIOS jump table + SNIOS jump
table at the addresses NDOS expects.  PolyPascal + CONOTEST exercise
the common path (CONIN/CONOUT/CONST + SELDSK/SETTRK/SETSEC/READ/
WRITE/SETDMA via CP/NET dispatch).  Stress-testing the long tail of
the 50-function CP/NOS interface (per the DRI spec, README section
5 "Full NDOS") was never attempted -- if a workload uses LIST,
PUNCH, READER, or some uncommon SECTRAN translation, cpnos-in-asm
may or may not handle it.  cpnos-in-c is the production path now
and inherits its coverage from the C resident which has been
exercised more broadly.

### SDCC / dual-compiler parity

cpnos-in-c maintains clang × SDCC dual-compile parity as a behavioral
oracle (memory rule `feedback_dual_compiler_test`).  cpnos-in-asm by
its nature has no compiler-parity concept -- the assembly source is
the only build artifact.  This is a feature, not a gap, but it
means cpnos-in-asm can't act as a regression baseline for compiler
work the way cpnos-in-c does.  Now that cpnos-in-c is in production
this is moot.

## What lives in this directory after parking

Source tree is left intact for historical reference, byte-exact
reproduction of the 2026-05-17 PolyPascal PASS, and as a reference
implementation for the autoload->PROM1 line program contract.

- `src/prom1.asm` — PROM1-resident bootstrap (1015 lines): autoload
  signature contract, hardware init, CP/NET wire, netboot.
- `src/snios_payload.asm` — SNIOS payload (1118 lines): JTs + impls
  + handoff trampoline + ISRs, ZX0-compressed in `build/`.
- `Makefile`, `cfg/`, `asm/` — build infrastructure.
- `tasks/` — Python test rigs (sio_a_fake_master.py, peek_slave_state.lua,
  verify_mpm_login_response.py).
- `snap/` — historical screenshots from phase 1..3 bring-up.

No build target is removed.  `make` still works; `make cpnos-polypascal-test`
still PASSes against the asm slave's PROM1.  Parking just means new
feature work goes into cpnos-in-c.

## If resuming work

1.  Check `git log -- cpnos-in-asm/` for any changes since this
    parking notice was written -- the assumption "cpnos-in-c is in
    production" may have shifted.
2.  Re-verify the PolyPascal PASS still holds before adding features:
    `cd cpnos-in-asm && make cpnos-polypascal-test`.
3.  The 3 graphics-mode CONOUT codes are the smallest concrete
    completability gap; adding them gates parity with rcbios's
    DISPLAY.MAC.  Pattern would follow do_clear_screen / do_home in
    snios_payload.asm: maintain BGFLG/BGSTAR state in slave RAM,
    write to a (currently absent) graphics-overlay buffer address.
    Memory rule `feedback_slave_state_outside_tpa`: any new state
    must live in the SNIOS reserved area (0xED00..0xF7FF), not below.

## See also

- `../cpnos-in-c/tasks/zx0-prom1-only-plan-2026-05-17.md` — the plan
  that motivated the cpnos-in-c PROM1-only build.
- `../cpnos-in-c/clang-prom1lineprog/` — the production replacement.
- `../CLAUDE.md` section "Current Sizes" — header-line view of where
  cpnos-in-c PROM1-only lands.
