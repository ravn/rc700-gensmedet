# Debugging cpnos / rcbios under MAME via the GDB stub

Reference for interactive Z80 debugging of any slave software (cpnos,
rcbios, autoload-in-c, anything that runs in the RC702 MAME machine).
Captured 2026-06-12 while investigating the #115 INIR refactor — the
documentation gap was felt acutely there but the approach is general.

The short version: `regnecentralend -debug -debugger gdbstub` starts a
GDB remote-protocol server, and a `gdb-multiarch` running inside a
`debian:stable-slim` Docker container can attach to it from macOS host
without needing brew.  Works end-to-end with symbolic breakpoints,
hardware-emulated watchpoints, register inspection, memory dumps, and
scripted `commands` blocks.

## Verified working setup (macOS host, 2026-06-12)

| Component | Version |
|---|---|
| MAME (ravn/mame fork)         | `0.286 (unknown)` (`/Users/ravn/z80/mame/regnecentralend`) |
| Docker                        | 29.5.3 build d1c06ef |
| Container base                | `debian:stable-slim` (already in local registry) |
| GDB in container              | `gdb-multiarch` from Debian apt — knows Z80 via `set arch z80` |

## Launching MAME with the GDB stub

```bash
regnecentralend rc702 \
    -rompath /Users/ravn/z80/mame/roms \
    -nothrottle -window -skip_gameinfo \
    -seconds_to_run 240 \
    -rs232a null_modem -bitb1 /tmp/cpnos_sioa.raw \
    -rs232b null_modem -bitb2 /tmp/cpnos_siob.raw \
    -piob cpnet_bridge -bitb3 socket.127.0.0.1:4002 \
    -debug \
    -debugger gdbstub \
    -debugger_host localhost \
    -debugger_port 23946
```

Key flags:
- `-debug` arms MAME's debugger subsystem.
- `-debugger gdbstub` selects the GDB remote-protocol stub (alternatives
  are `osx`, `imgui`, `none`).
- `-debugger_host` / `-debugger_port` control where the stub listens.

The stub starts BEFORE the Z80 begins executing.  PC is `0x0000` on
first attach.  Use `continue` to let the slave boot.

## Attaching gdb-multiarch from Docker

Once-off image build (15 s including `apt update`):

```bash
docker build -t z80-gdb - <<'EOF'
FROM debian:stable-slim
RUN apt-get update -qq && apt-get install -y -qq gdb-multiarch
EOF
```

Then run a session, mounting the cpnos build directory so GDB can read
`payload.elf` for symbols:

```bash
docker run --rm -it \
    --network host \
    -v /Users/ravn/z80/rc700-gensmedet/cpnos-in-c/clang-prom1lineprog:/elf \
    z80-gdb \
    gdb-multiarch \
        -ex 'set arch z80' \
        -ex 'file /elf/payload.elf' \
        -ex 'target remote host.docker.internal:23946'
```

`host.docker.internal` resolves to the macOS host from inside Docker
Desktop — the macOS-specific bridge MAME's stub is listening on.
On Linux, use `--network host` and `localhost`.

## What works (verified)

- **`set arch z80`** — gdb-multiarch ships with Z80 support; no Z80-
  specific GDB build needed.
- **Symbol loading** — `file payload.elf` loads clang's DWARF info.  All
  C functions and globals are addressable by name
  (`b pio_b_recv_block_body`, `p pio_rx_head`).
- **Register inspection** — `info registers` returns main set (`af bc
  de hl sp pc ix iy`) plus shadow set (`af' bc' de' hl'`).
- **Disassembly** — `x/4i $pc` shows Z80 mnemonics.
- **Memory inspection** — `x/16b 0xEB24` dumps cfgtbl bytes, etc.
- **Hardware watchpoints** — `watch *(unsigned char *)0xECxx` fires on
  writes; `rwatch` on reads; `awatch` on either.  MAME emulates these
  by intercepting every memory access — software-cost, not real
  hardware-watchpoint registers.  Performance is fine with up to a
  handful of active watchpoints.
- **Scripted `commands` blocks** at breakpoints / watchpoints —
  log-and-continue without stopping the emulation.
- **Conditional breakpoints** — server-side eval (`b *0xEEEC if $b > 1`).

## Known issues / gotchas

### 1. `warning: Architecture rejected target-supplied description`

GDB prints this on every attach.  Harmless.

GDB's Z80 target description (`gdb/features/z80-cpu.xml` in GDB's
source tree, FSF copyright 2020-2024) uses feature name
`org.gnu.gdb.z80.cpu`.  GDB's `z80_gdbarch_init`
(`gdb/z80-tdep.c`) explicitly searches the target-supplied
description for this exact name:

```c
feature = tdesc_find_feature (tdesc, "org.gnu.gdb.z80.cpu");
if (feature == NULL)
    return NULL;           /* rejects the description */
```

MAME's stub uses feature name `mame.z80` instead — part of a
uniform `mame.<cpu>` naming scheme across every CPU MAME's gdbstub
supports (`mame.m6502`, `mame.m6809`, `mame.score7`, etc., see
`src/osd/modules/debugger/debuggdbstub.cpp`).  Since the names
differ, `tdesc_find_feature` returns NULL, GDB rejects the
description, and falls back to its built-in `tdesc_z80` default.

The fallback works because the first 12 registers in GDB's built-in
match what MAME provides (see [§ Register set](#register-set-on-the-stub)).

Why MAME chose a custom prefix instead of the canonical name —
in the author's own words, from MAME commit `cb8a6b8e`
(2019-08-11, "gdbstub: add z80 and m6502"):

> Since GDB doesn't support those processors, I made up the
> features name with "mame.<cpuname>".  I also had to choose
> the registers to export in the target.xml file, and since I
> don't have any experience with these processors I don't know
> if I made the best choice.

Chronology:
- 2019-08-11: MAME adds Z80 + m6502 to its gdbstub (commit
  `cb8a6b8e`).  At this point GDB has no Z80 target description.
- 2020 (per FSF copyright on `gdb/features/z80-cpu.xml`):
  GDB adds Z80 target description with canonical feature name
  `org.gnu.gdb.z80.cpu`, defining 13 registers including `ir`,
  and with PC as 32-bit.
- Subsequent: MAME's `mame.z80` stays — both for consistency with
  the `mame.*` scheme its other CPUs follow, and because changing
  it would break any user workflow that already attached via the
  custom name.  The register layout would also need to be
  reconciled with GDB's (different order, missing `ir`,
  16-bit vs 32-bit PC).

The acknowledged "I don't know if I made the best choice" remains
visible in MAME's behaviour today — the warning + missing `ir` are
the cost of that early choice.  Not wrong, just dated.

The only consequence: GDB tries to fetch a 13th register `ir` that MAME
doesn't expose, producing one error message per `info reg` (see #2).

### 2. `Could not fetch register "ir"; remote failure reply '01'`

GDB's built-in Z80 description includes `ir` (a single 16-bit register
that GDB treats as the combined I+R pair, regnum 12).  MAME's
`target.xml` lists only 12 registers and stops there; when GDB asks
for register #12 the stub returns `E01`.

For RC702 debugging this is a non-issue:
- `I` is set once at boot (`set_i_reg(IVT_ADDR >> 8)` in `init.c`) and
  thereafter holds the IVT page (0xEB for cpnos).  Known statically.
- `R` is the dynamic-RAM refresh counter — not useful for debugging.

If `ir` is ever wanted, the fix is a small patch to MAME's
`src/osd/modules/debugger/debuggdbstub.cpp` to add an `i` and an `r`
state read for the Z80 (or one 16-bit pseudo-register) — about 10
lines.  Not done here.

### 3. Interactive stepping vs. master timeout

When you stop the slave's Z80 at a breakpoint and start single-
stepping interactively, the **mpm-net2 master keeps running**.  It's
a separate `cpmsim` process talking over TCP; MAME's debugger only
pauses the slave's emulated Z80, not the host wall clock and not the
peer.

For SNIOS protocol-level debugging this matters:
- The slave has just sent a frame, expects an ACK.
- You break, look at registers, type instructions.
- Master gets bored, times out the connection.
- When you continue, the slave's recv times out and the frame is
  retried — but the master may now be in a different protocol state.

**Workaround**: prefer `silent` + `commands` blocks that *log and
continue* over interactive stepping.  Reserve interactive stops for
single-shot, fast-resume inspection (`p`, `x`, `info reg`, `c`).

### 4. `remote get` (vFile) not implemented

`remote get target.xml /local/path` and similar host-side file I/O
commands return `Remote I/O error: Function not implemented`.  MAME's
stub doesn't support the vFile family.  Fetch `target.xml` via the
underlying `qXfer:features:read:target.xml:0,1000` packet if needed
(GDB does this automatically on attach; you can also script raw).

## Register set on the stub

MAME advertises:

| Regnum | Name | Bits | GDB type      | Notes |
|---:|------|---:|---------------|-------|
| 0  | `af`  | 16 | `af_flags`    | A in high byte, F in low |
| 1  | `bc`  | 16 | `int`         |   |
| 2  | `de`  | 16 | `int`         |   |
| 3  | `hl`  | 16 | `int`         |   |
| 4  | `af'` | 16 | `af_flags`    | shadow |
| 5  | `bc'` | 16 | `int`         | shadow |
| 6  | `de'` | 16 | `int`         | shadow |
| 7  | `hl'` | 16 | `int`         | shadow |
| 8  | `ix`  | 16 | `int`         |   |
| 9  | `iy`  | 16 | `int`         |   |
| 10 | `sp`  | 16 | `data_ptr`    |   |
| 11 | `pc`  | 16 | `code_ptr`    |   |
| —  | `ir`  | 16 | (GDB built-in) | Not exposed by MAME; see #2. |

The 8-bit halves (`a`, `f`, `b`, `c`, `d`, `e`, `h`, `l`, `f'`, `a'`,
etc.) are NOT separate GDB registers.  Access them as bytes within the
pair:

```gdb
(gdb) p $bc                                # full 16-bit
(gdb) p (unsigned char)($bc >> 8)          # B
(gdb) p (unsigned char)($bc & 0xff)        # C
(gdb) p (($af >> 8) & 0xff)                # A
```

Flag bits in F (the low half of AF) follow Z80 standard layout:
S Z F5 H F3 P/V N C from bit 7 to bit 0.  GDB's `af_flags` type
auto-decodes these:

```
af  0x40  [ Z ]               ← Z flag set, others clear
af' 0xffff [ C N P/V F3 H F5 Z S ]  ← all flags set in shadow AF'
```

## Recipes useful for cpnos work

### Watch the SNIOS ring head / tail

```gdb
(gdb) p &pio_rx_head           # find address (linker-resolved)
$1 = (volatile unsigned char *) 0xECxx
(gdb) watch *(unsigned char *)0xECxx
(gdb) commands
> silent
> printf "HEAD %02x by PC=%04x\n", *(unsigned char *)0xECxx, $pc
> continue
> end
```

Every byte the ISR pushes triggers one log line with the program
counter of the writer (= `isr_pio_par` body address).  Same idiom for
`pio_rx_tail` (the mainline drain side).

### Trace `pio_b_recv_block_body` invocations

```gdb
(gdb) b pio_b_recv_block_body
(gdb) commands
> silent
> printf "BLK B=%-3d HL=%04x head=%02x tail=%02x SIZ=%d\n", \
         $b, $hl, *(unsigned char *)0xECxx, *(unsigned char *)0xECxx, \
         *(unsigned char *)((cfgtbl_msg_addr) + 4)
> continue
> end
```

Each invocation logs the count being requested, the destination
pointer, the ring fill, and the SIZ byte from the just-received header
— exactly the visibility that was missing in the 2026-06-12 INIR
session.

### Dump the latest frame's data block

After `continue`-ing past a frame's data block, the bytes are in
`msg[5..5+SIZ]`.  Find `msg` (it's the netboot-side scratch buffer in
`init.c`, or `cfgtbl.msgbuf` for SNIOS):

```gdb
(gdb) p msg                    # or &cfgtbl.msgbuf
(gdb) x/8b msg+5               # first 8 data bytes
(gdb) x/132b msg+5             # full 128-byte sector (READ-SEQ frame)
```

### Find a symbol's runtime address

`payload.elf` has all addresses; clang lays everything out at the
final memory location, no relocation needed.

```gdb
(gdb) info address pio_rx_head
Symbol "pio_rx_head" is at 0xec2b in a file compiled without debugging.
(gdb) info address pio_b_recv_block_body     # only after #115 lands
```

For the SDCC build the symbol names are unchanged
(`_pio_rx_head`, `_pio_b_recv_block_body`); both compilers emit the
same export names.

## The Docker image

A pre-built image saves the per-run `apt install` overhead (~10 s →
<1 s container start).  Suggested Dockerfile in
`scripts/z80-gdb.Dockerfile`:

```dockerfile
FROM debian:stable-slim
RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends gdb-multiarch && \
    rm -rf /var/lib/apt/lists/*
```

Build: `docker build -t z80-gdb -f scripts/z80-gdb.Dockerfile scripts/`

Tag once, reuse for many sessions.  Image size ~100 MB on top of the
already-pulled debian:stable-slim base.

## When NOT to use GDB

This is interactive debugging.  For automated regression measurement
(timing, sector counts, byte traces across many runs) the MAME Lua
debugger is the better fit — it doesn't pause the emulation and integrates
with the existing `polypascal_test.lua` / `mame_capture.sh` pipeline.

Use GDB when you need:
- One-off "what's HL right now" inspection.
- Watchpoints firing once or twice per frame.
- Conditional breakpoints to catch rare events.
- Step-through of an inline-asm block.

Use Lua when you need:
- Per-frame snapshots across thousands of frames.
- Continuous timing measurement.
- Headless / CI integration.

## References

- MAME's gdbstub source: `src/osd/modules/debugger/debuggdbstub.cpp`
  (in the MAME tree).  Implements a subset of the GDB remote serial
  protocol.
- GDB's Z80 target description:
  `gdb/features/z80.xml` in the GDB source tree — defines the 13-register
  layout including `ir`.
- GDB Remote Serial Protocol reference:
  https://sourceware.org/gdb/current/onlinedocs/gdb.html/Remote-Protocol.html
- This project's polypascal-test harness (Lua approach):
  `cpnos-shared/mame/polypascal_test.lua`,
  `cpnos-in-c/Makefile` (`cpnos-polypascal-test` target).
- The #115 INIR investigation that motivated this writeup:
  `cpnos-in-c/tasks/pio-input-busy-wait-and-inir-2026-06-12.md`.
