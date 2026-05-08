# Probe results — SDCC pio-irq Ctrl-P/0x00 flood (issue #57)

Date: 2026-05-08
Branch: session47-cpnos-header-driven-relocator (continued from Path 6)

## Setup

`make cpnos-polypascal-test COMPILER=sdcc TRANSPORT=pio-irq` with
`MIRROR_SIOB=1` (default for the polypascal-test recipe).  Probe
instrumentation in `resident.c` emits a labelled hex line over SIO-B
at the moment of `resident_handoff` (just before `enter_coldst()` JPs
to `NDOSE`):

  `[H]<kbd_head><kbd_tail><pio_rx_head><pio_rx_tail><kbd_ring[0]><kbd_ring[1]>\r\n`

Plus per-path `[S]` (SIO-B path) and `[K]` (kbd_ring path) one-shot
markers in `impl_const`.  Probe is gated on `MIRROR_SIOB && defined(__SDCC)`
to avoid clang static-stack frame overflow into the (smaller) clang
scratch_bss.

## Observed `/tmp/cpnos_siob.raw` (SDCC pio-irq, 391 bytes total)

```
RC702 CP/NOS 55K PIO sdcc 2026-05-08 11:28 67b6496+\r\n   (slave banner)
.........................\r\n                              (25 netboot dots)
2026-05-08 11:28 67b649\r\n                                (cpnos.com stamp)
[H]0000C0C00000\r\n                                        (probe data)
<1957 zero bytes, no non-zero, no [S] or [K]>              (the flood)
```

(The cpnos.com stamp's "67b649" is the netboot trailing-stamp emitted
by `netboot_mpm.c:172-176` from the last 23 B of the loaded payload —
it's a separate format from cpnos-rom's banner, not a truncation bug.)

### Decoded probe at `[H]`

| field            | value | meaning |
|------------------|------:|---------|
| `kbd_head`       | 0x00  | kbd_ring write index (ISR-only) |
| `kbd_tail`       | 0x00  | kbd_ring read index (CONIN-only) |
| `pio_rx_head`    | 0xC0  | PIO-B IRQ buffer write index |
| `pio_rx_tail`    | 0xC0  | PIO-B IRQ buffer read index |
| `kbd_ring[0]`    | 0x00  | first ring slot |
| `kbd_ring[1]`    | 0x00  | second ring slot |

`kbd_head == kbd_tail == 0` -> **kbd_ring is empty at handoff**.
`pio_rx_head == pio_rx_tail == 0xC0` -> **PIO-B IRQ buffer is empty at
handoff** (consumer drained everything; both pointers landed at the
same slot during netboot).

## Comparison: clang baseline (PASS, 26411 bytes)

```
RC702 CP/NOS 55K PIO clang 2026-05-08 11:27 67b6496+\r\n
.........................\r\n
2026-05-08 11:27 67b649\r\n
E>PPAS\r\n                                                 (CCP prompt + Lua keystroke)
PolyPascal-80 V3.10 ...
... (test runs to 29989 prime, returns to E>) PASS
```

Clang reaches `E>` immediately after the cpnos.com stamp — same MAME
wiring, same `cpnos.com` on disk, same path through `netboot_mpm`.

## What the data eliminates

- **kbd_ring stale at boot** — kbd_head/kbd_tail/kbd_ring[0..1] all
  zero at handoff.  Relocator's BSS-zero pass over `bss_compiler`
  did its job.
- **SIO-B FIFO power-on residue feeding 0x10** — flood is **0x00**,
  not 0x10.  (The session-47 analysis doc reported "Ctl-P OFF" flood;
  the current symptom is unambiguously 0x00.)
- **PIO-A spurious IRQ feeding kbd_ring** — kbd_head stayed at 0
  through resident_handoff, so PIO-A never IRQ'd.
- **SIO-B null_modem loopback** — `[S]` probe in `impl_const` would
  fire on the first 0xFF return from the SIO-B path; it never fires.
  Same for `[K]` and the kbd_ring path.
- **polypascal-test Lua early-write to a port** — Lua only writes to
  RAM (`prog:write_u8(KBD_RING + h, b)`), only after stage 1 fires,
  and stage 1 needs `E>` on SIO-B before injecting.  Lua is silent
  during the pre-`E>` window.
- **TPA / cpnos.com base mismatch** — `cpnos.com` is built at Path 6
  CODE_BASE=0xDD80 (matches CPNOS_NDOS_ADDR / payload.ld ASSERTs).
  cpnos.com is loaded at the right address via netboot.

## What the data implies

The 0x00 flood originates **after** `enter_coldst()` JPs to NDOS+3.
Either:

1. NDOS COLDST itself enters a tight loop calling
   `impl_conout(0x00)` (or directly OUTs 0x00 to SIO-B DATA), OR
2. NDOS reaches CCP, but CCP is in a similar loop, OR
3. cpnos.com's NDOSRL data area is uninitialised garbage and NDOS
   reads zero bytes from a "banner string" pointer that points there.

`impl_const` is **never called** during the 30-second test window
(neither `[S]` nor `[K]` ever fires) — so NDOS-CCP is not polling
CONST.  The 0x00 bytes are pure CONOUT-side output, not echo from
CONIN.

Clang under the same `cpnos.com` reaches `E>`, so the bug is in
cpnos-rom's SDCC-compiled resident code or the SDCC-side hand-written
asm (sdcc/bios_jt.asm, sdcc/snios.asm, sdcc/hal.asm, sdcc/reset.asm).
SAME `bios_jt` ABI offsets, SAME `snios_jt == 0xED33`, same wire
protocol — but somewhere the implementation differs in a way that
breaks NDOS COLDST.

## Side finding: `_port_in` in `boot_probe` hangs the slave

Adding `p_hex(_port_in(PORT_SIO_B_CTRL))` inside `boot_probe`'s body
hangs the slave entirely (siob.raw stays 0 bytes — banner never
appears).  Removing the `_port_in` call but keeping all other p_hex
calls produces the data above.  Why a single port read inside
`boot_probe` (called from `resident_handoff`) breaks the slave under
SDCC is unknown — could be a register-clobber issue across SDCC's
sdcccall(1) call boundary or an interaction with IRQs that fire
between the IN and the surrounding stack manipulation.  Worth
filing as a separate task for the SDCC port; it does not block the
0x00-flood diagnosis.

## Next investigation step (NOT in this commit)

Diff the SDCC-vs-clang resident bytes that get called by `cpnos.com`'s
NDOS COLDST early path:

  - `_impl_boot` / `_impl_wboot` in resident.c — both compilers
  - `_bios_const_shim` / `_bios_conin_shim` / `_bios_conout_shim` —
    naked-C wrappers in resident.c
  - `_snios_jt` entries — NDOS calls into `_snios_ntwkin` first
  - `_zp_init_data` placement — ZP[0..7] seed
  - `enter_coldst` — should be identical (LD SP / JP NDOSE)

The most promising target is the SNIOS body under SDCC vs clang —
NDOS COLDST early calls SNIOS NTWKIN (slot 0) and SNIOS NTWKST.  If
either misbehaves, NDOS may go into a fault-recovery loop printing
0x00s.  Add probes to `_snios_ntwkin` / `_snios_ntwkst` body entry
points to confirm whether they're called and what they return.

## Update — bug #1 found and fixed (Path 6.1)

The SDCC pio-irq slave's stack was placed inside cpnos.com's NDOSRL
data region by Path 6's `LD SP, 0xDD80` at `sdcc/reset.asm:43`.  The
stale comment in that file claimed stack grew "into TPA RAM
(0x0100..0xDD7F)", but TPA actually only goes up to 0xD97F — the top
1024 bytes (0xD980..0xDD7F) are NDOSRL, cpnos.com's variable storage
that NDOS COLDST reads/writes.

Every push during init / netboot / resident_handoff stomped NDOSRL.
NDOS COLDST then read its own data, found stack frames there, and
ended up calling `impl_conout(0)` in a tight loop (the source of the
"1957 bytes of 0x00 flood" symptom).

Fix: `LD SP, 0xD980` (one byte below NDOSRL).  Stack now grows into
TPA proper (0x0100..0xD97F) which is genuinely unused at boot time.
After `enter_coldst` runs, SP=0x0100 anyway.

clang's stack at 0xF700 (in scratch_bss, set by `__stack_top`
linker symbol in payload.ld) was always safe — clang never had this
problem.

Verified post-fix:
  - 0x00 flood gone (siob.raw shrank from 391 B to 123 B)
  - `[H]` probe still shows kbd/pio_rx buffers empty at handoff
  - **but slave still does NOT reach E>** — SDCC is now silent
    after `[H]` rather than flooding; NDOS COLDST hangs at a second
    bug downstream

Comparison of bug-1 vs bug-2 byte signature (siob.raw, after `[H]`):

  bug-1 (SP=0xDD80): `[H]0000C0C00000\r\n` then 1957 × 0x00
  bug-2 (SP=0xD980): `[H]0000C0C00000\r\n` then 1 × 0x00, then silence

The single trailing 0x00 might be NDOS's first output before its
hang point.  More probes would narrow this further but each new
probe addition perturbs the static-stack frame layout enough to
break the boot path under SDCC z88dk (observed empirically — even
adding a one-shot `[O]` probe at top of `impl_conout` causes the
banner-print path to hang).  Probe budget is exhausted on this
build.

## Update — bug #2 isolated (control-flow loss at t=5.3)

MAME Lua probe traced PC + SP at 0.1 s granularity from boot through
the crash window.  Three phases visible:

| Phase | Window | PC range | SP range | What's happening |
|-------|--------|----------|----------|------------------|
| 1 | t=0..1.7 s | 0xED00..0xF3xx | 0xD954..0xD97A | cpnos-rom resident running (banner, netboot, resident_handoff) |
| 2 | t=1.8..5.3 s | 0xDExx..0xE7xx | 0xDACD..0xDBA1 | NDOS COLDST executing inside cpnos.com (0xDD80..0xE9FF) |
| 3 | t=5.3+ | RAM-walk | erratic, eventually wraps | control flow lost |

The `enter_coldst` JP to NDOSE at t=1.80 lands cleanly: NDOS sets up
its own SP in NDOSRL at ~0xDAD5 and runs its COLDST body for **3.6
seconds**.  This is the first time NDOS has been observed running at
all under SDCC pio-irq.

Crash transition between t=5.20 and t=5.30:

```
t=5.20  PC=0xDEFD  SP=0xDAD5    (normal NDOS execution)
t=5.30  PC=0xDEB9  SP=0x00FA    (SP suddenly at 0x00FA — inside ZP!)
t=5.40  PC=0x78A6  SP=0xE6C9    (PC jumped to random TPA address)
```

SP=0x00FA strongly suggests CCP started: CCP's first action is
typically `LD SP, 0x0100` followed by pushing register state, which
lands SP at exactly 0x00FA after 3 16-bit pushes.  The RET that
follows a CALL inside CCP then pops a corrupted return address ->
jump to 0x78A6 (in TPA) -> RAM-walk.

Stack fills unboundedly only AFTER the RAM-walk starts.  The
"stack-filling pattern" the user observed is a *consequence* of
control-flow loss, not the cause.  PIO-A and PIO-B IRQs never fire
post-crash (kbd_head=0, pio_rx_head=0xC0 unchanged) — only CTC ch2
keeps ticking the frame counter.

## Hypothesis for bug #2

A register that SDCC's `_impl_*` clobbers but clang's doesn't, AND
that NDOS/CCP relies on across its BIOS-JT calls.  Specifically: NDOS
or CCP makes a BIOS call (CONST/CONIN/CONOUT/...), the call returns
with garbage in some register, NDOS/CCP uses that register, RET pops
an address that isn't where execution should resume, jump to random.

The BIOS shims save BC + DE only.  IX/IY/AF'/HL'/I are NOT preserved.
If NDOS or CCP relies on any of those across a BIOS call, SDCC's
implementation could be the difference.

## Next investigation step (bug #2)

  - Capture full Z80 register state (A, F, B, C, D, E, H, L, IX, IY,
    AF', BC', DE', HL', I) at t=5.20 and t=5.30 via MAME Lua. Compare.
    The register that changes unexpectedly across the crash is the
    likely culprit.
  - Run the same MAME Lua trace under clang to confirm clang doesn't
    hit this transition (it reaches `E>` at the equivalent time).

## Files changed (in this commit)

  - `resident.c`: added `p_hex` + `boot_probe` (gated on
    `MIRROR_SIOB && defined(__SDCC)`), added once-fire `[S]`/`[K]`
    probes in `impl_const`.
  - `cpnos_main.c`: added `boot_probe('H')` call just before
    `enter_coldst()` in `resident_handoff`.
  - `mame_polypascal_test.lua`: line 25 now reads
    `dofile(os.getenv("COMPILER") .. "/cpnos_polypascal_addrs.lua")`
    so SDCC test runs use SDCC's kbd_head/kbd_ring addresses
    (issue #58, task #32).

Resident SDCC: 2712 B / 2816 B cap (+20 B vs pre-probe baseline).
Clang non-padding: 1809 B (unchanged from session-47 baseline).
