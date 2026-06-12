# Future: GDB stub on the slave, talking over SIO

Parking ticket — not active work.  Captured 2026-06-12 during the MAME
GDB-stub investigation
(`docs/mame_gdb_debugging.md`), which showed how productive Z80 GDB
debugging is on the emulator side and made the gap on real-hardware
debugging feel sharp.

## The idea

Implement a small GDB Remote Serial Protocol stub on the slave that
listens on SIO-B (or SIO-A; per [`SW1`](../docs/SW1_BIT_MAP.md) routing,
SIO-B is the operator-console mirror today) and lets a host GDB attach
to a *real* RC702 over a serial cable.

Same `gdb-multiarch` + Docker workflow that works for MAME today
(per `docs/mame_gdb_debugging.md`) would then work against real
hardware — just point GDB at a `target remote /dev/tty.usbserial-XXXX`
instead of `host.docker.internal:23946`.

## Why interesting

- **Real-hardware debugging.**  cpnos, rcbios, autoload-in-c bugs that
  only manifest on real RC702 (timing-sensitive PIO/SIO behaviour, real
  PROM layout, real CTC/DMA quirks) become tractable: set a breakpoint,
  inspect state, single-step.
- **No emulator divergence.**  MAME's PIO emulation has documented
  bugs (`ravn/mame#7`); a real-hardware GDB session bypasses them.
- **Replaces ad-hoc `impl_conout` markers.**  Today the only on-device
  debug is BOOT_MARK to display memory or characters to SIO-B.  GDB
  gives proper interactive inspection without polluting the binary.

## Sketch of the work

### Protocol layer (~0.5 KB)

GDB RSP is text-based (`$<packet>#<csum>`) with a tiny state machine.
Need:
- Packet RX loop reading from SIO-B byte by byte.
- Packet TX with checksum + ack/NAK.
- Handler for: `g`/`G` (registers all), `m`/`M` (memory), `c` (continue),
  `s` (single step), `Z0`/`z0` (sw breakpoint set/clear), `?` (last stop
  reason), `qSupported`, possibly `qXfer:features:read:target.xml:...`.

Existing prior art (worth surveying first):
- `legumbre/gdb-z80` and `atsidaev/gdb-z80` — they're GDB *forks* with
  Z80 target support, but their sample stubs are reference material.
- `spectrumero/spectranet-gdbserver` — Z80 gdbserver running on a
  ZX Spectrum Spectranet, similar concept.  Reusable parts of the
  packet/checksum code.
- `flagbot/gambatte-libretro` (`libgambatte/src/debugger/GdbStub.cpp`) —
  full GDB stub on Game Boy CPU (LR35902, Z80 cousin).  Architecture-
  reference even if not directly reusable.

### Breakpoint mechanism (~0.2 KB)

Standard Z80 GDB-stub trick: replace target instruction with `RST 38h`
(`0xFF`, 1-byte trap).  Stub installs IM 1 handler at 0x0038 that:
1. Saves all registers (AF/BC/DE/HL/IX/IY + shadow + SP/PC).
2. Enters the packet loop.
3. Restores registers + returns.

For cpnos which uses IM 2 with custom IVT, would need to install the
RST 38h handler differently (RST is a direct jump regardless of IM mode,
to 0x0038 — but 0x0038 is in our resident region, easy to claim).

cpnos / rcbios already use IM 2 with custom IVT.  RST 38h hijack is
non-intrusive — it only fires when the stub explicitly patches a byte.
Regular IM 2 IRQs continue uninterrupted.

### Single-step

Trickier: Z80 has no real single-step.  Common approaches:
1. **Trap at next sequential instruction.**  Read current instruction,
   compute length, write RST 38h at PC+len.  Doesn't work for taken
   branches.
2. **Trap at next instruction AND at target of any branch.**  Need to
   decode the current instruction to find branch targets.  ~100 lines
   of decoder.
3. **Z80 "M1 single-step" via /WAIT.**  Hardware trick; not portable.

Probably (2) — minimal Z80 disassembler that handles JP, CALL, RET,
JR, DJNZ, conditional variants.  Reuse z88dk's disassembler or hand-
roll the ~30 opcode-family cases.

### Watchpoints

**Not implementable on real Z80 without external hardware.**  Z80 has
no watchpoint registers; every memory access would need to be checked
in software, which means single-stepping every instruction.  Acceptable
for "stop within N instructions" pattern (probably 100× slower run);
not for "transparent watch."

For now: ship breakpoints + single-step + register/memory inspection.
Skip watchpoints.  If needed later, document the slowdown.

### SIO transport details

- Need a dedicated UART for GDB, not shared with operator console.
  Current cpnos uses SIO-B for the operator-console mirror; would
  need a SW1 bit (S04 is free) to route SIO-B to GDB when set.
- Baud rate: 38400 default; can go to 115200 if the cable + driver
  cooperate.
- Flow control: SIO-B supports RTS/CTS in some configs; if absent,
  rely on RSP's ack/NAK + small packet sizes.

### Memory cost

Rough estimate based on similar projects:
- Packet parser + RSP state machine: ~400 B.
- Register-save/restore handler: ~100 B.
- Breakpoint table (16 entries × 4 B): ~64 B BSS.
- Single-step decoder: ~300 B.
- SIO byte recv/send: reuse `transport_sio.c` (already present).

Total: ~1 KB code, ~100 B BSS.  Would need a dedicated PROM slot or a
separate "debug build" of cpnos that swaps something out (e.g.,
locale tables) for the stub.

## Why parked

- Not blocking anything.  Real-hardware debugging has been done via
  BOOT_MARK + screen capture; tractable for current scope.
- The four "finishing firmware components" all work without it.
- Substantial work (~1 KB code, careful interrupt-handling, decoder).
- MAME-side GDB now covers the bulk of debugging needs
  (`docs/mame_gdb_debugging.md`).

## When to reconsider

- A real-hardware-only bug appears that MAME can't reproduce.
- We add a new transport (e.g., RS-485 multi-drop) that MAME can't
  emulate.
- Someone wants to teach Z80 debugging at a workshop / class.

## Related

- `docs/mame_gdb_debugging.md` — the MAME-side GDB workflow.
- `tasks/cpnet-pio-throughput-baseline-2026-06-12.md` — the kind of
  measurement that motivated this (per-byte timing inspection that's
  awkward without breakpoints).
- The four finishing-firmware components (`autoload-in-c`,
  `rcbios-in-c`, `cpnos-in-c`, CP/NET) are the consumers — pick the
  most-debugged one as the first target if/when we revive this.
