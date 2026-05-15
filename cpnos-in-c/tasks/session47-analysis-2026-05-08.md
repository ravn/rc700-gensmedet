# Session 47 follow-up — Path 6 lands, SDCC slave reaches CCP

Date: 2026-05-08
Branch: `session47-analysis-2026-05-08` (split from
`session47-cpnos-header-driven-relocator` at commit `8573a09`)

## tl;dr

The data-driven relocator + Path 6 TPA shrink got the SDCC slave
through NDOS handoff under TRANSPORT=pio-irq.  CCP runs.  But CCP
receives a flood of 0x10 (Ctrl-P) bytes from CONIN and prints
"Ctl-P OFF" instead of `E>`.  Source not yet identified; three
candidates listed below.  Clang side still PASSes the polypascal-test
end-to-end.

## What landed (workspace `b75b7ae..a9c9175`, rc700-gensmedet `b75b7ae..8573a09`)

19 commits in rc700-gensmedet, tied to one workspace bump:

| Layer | Commit (rc700-gensmedet) | Effect |
|-------|--------------------------|--------|
| Path 6 | `8573a09` | cpnos.com base 0xDE80 -> 0xDD80; NIOS 0xEE33 -> 0xED33; resident 0xEE00..0xF7FF (2560 B) -> 0xED00..0xF7FF (2816 B); `__stack_top` SDCC moved to 0xDD80 (below all clear/copy/LDIR regions). |
| Bus + safety | `d9bbc8b` | sdcc/hal.asm `__port_out` puts B=H so OUT (C),A's upper byte mirrors port; Makefile asserts cpnos.com size + NDOS load address fits below the IVT page (was 0 B clearance, now caught at build time). |
| Build speed | `f38b07a` + `ca93b5b` + `99f2bee` | SDCC incremental rebuilds 5-9 min -> 1-2 s.  MAKEFLAGS += -j$(NCPU); buildinfo regen via $(shell) at parse time (was .PHONY → propagated "always rebuild"); install-before-cpmsim ordering kills the cpmsim-cached-cpnos.com class of bug. |
| Persistent IVT | `833a595` + `0e8fc58` | SDCC IVT moved into a linker-placed `bss_ivt` section (no more 0xF500 / 0xEC00 literal); IVT pair appended to payload header so the relocator zeros it before checksum. |
| Test infra | `d1a3516` | polypascal-test harness now SDCC-aware (reads cpnos.map for symbols, was clang-only ELF). |
| Cleanup | `302ce24` | sdcc/prom_loader.asm deleted; relocator.c is the sole relocator source for both compilers. |
| Sundry | `8dd9fa2`, `8429b8d`, `55d68c2`, etc. | Audit gates, max-allocs documentation, opt-code-size lessons. |

Workspace bump: `a9c9175` "rc700-gensmedet: bump for Path 6 -- SDCC
slave reaches CCP".

## Verified state at HEAD (8573a09)

| Test | Result |
|------|--------|
| `make cpnos COMPILER=clang` | PASS (1809 non-padding bytes) |
| `make cpnos COMPILER=sdcc TRANSPORT=pio-irq` | PASS (resident 2558 B / 2816 B cap, audit OK) |
| `make cpnos COMPILER=sdcc TRANSPORT=sio` | PASS |
| `make cpnos-polypascal-test COMPILER=clang` | PASS end-to-end (PRIMES → 29989 → E>) |
| `make cpnos-polypascal-test COMPILER=sdcc TRANSPORT=pio-irq` | FAIL stage 1 (timeout waiting for E>) -- but slave reaches CCP for the first time |
| `make cpnos-polypascal-test COMPILER=sdcc TRANSPORT=sio` | FAIL — netboot doesn't even get one sector |

The SDCC PIO-IRQ failure mode under HEAD:

```
RC702 CP/NOS 55K PIO sdcc 2026-05-08 ...\r\n
.........................\r\n            (25 sectors loaded)
2026-05-08 ...\r\n                       (cpnos.com stamp from netboot)
Ctl-P OFFCtl-P OFFCtl-P OFFCtl-P OFF...  (CCP toggling printer-echo
                                          on each 0x10 received)
```

CCP IS running (it printed those messages); it just keeps reading
Ctrl-P (0x10) from CONIN.  Under clang this doesn't happen; CCP
prints `E>` and waits for input.

## Investigation of the Ctrl-P flood

Three working hypotheses, ranked by likelihood:

### 1. MAME null_modem loopback echoes the slave's banner back into SIO-B RX

The polypascal-test harness wires `-rs232b null_modem -bitb2 /tmp/cpnos_siob.raw`.
A single bitbanger file on a null_modem can act as TX→RX loopback (the
slave's own banner bytes appear on SIO-B RX one-shot).  `impl_conin`
checks SIO-B BEFORE kbd_ring, so any byte in the SIO-B FIFO becomes
CCP's input.

Why might this only show up on SDCC?  Timing: SDCC's longer init
(more code, less optimised) may give the loopback longer to land
bytes in the FIFO before CCP starts reading; clang outraces it.

**Tested fix**: drain SIO-B RX FIFO in `init_hardware` (read PORT_SIO_B_DATA
in a loop while RR0 bit 0 is set).  Result: Ctl-P flood stopped, but
slave fell silent — no `E>` either.  Either the drain consumed something
NDOS needs, OR the missing 0x10 bytes that triggered "Ctl-P OFF" output
were ALSO masking the lack of an actual `E>` print (i.e., CCP was never
printing E> in either case, and the Ctl-P flood was the ONLY visible
output proving CCP was running).

Action: instrument with SIO-B trace probes (Path 6 added 256 B
headroom, probes now fit) to pinpoint whether CCP reaches its prompt
print or not.

### 2. PIO-A keyboard ISR firing spuriously

`isr_pio_kbd` reads `IN A,(0x10)` (PORT_PIO_A_DATA) on every PIO-A IRQ
and pushes the byte into kbd_ring.  If MAME's keyboard model strobes
PIO-A at boot or at some periodic event, ISR fires and a stale data
byte (could be 0x10 by coincidence) gets enqueued.  16 stalls (ring
full, drops from there) per fire-storm matches "11 Ctl-P OFFs".

Why might this only show up on SDCC?  IVT placement / port_init
ordering.  But Path 6 reorganised IVT to bss_ivt which is exactly
where it should be.

Action: peek MAME's kbd_ring contents post-test via Lua memory probe
to see what bytes are actually in there.  (Requires fixing the test
driver's hardcoded `dofile("clang/cpnos_polypascal_addrs.lua")` to
honour `COMPILER=`.)

### 3. SIO-B 3-deep RX FIFO has stale power-on bytes

Z80 SIO-B has a 3-byte FIFO that survives WR0-reset (which only clears
RR0 status latches, not data).  Power-on chip state isn't documented;
MAME's emulation might leave 0x10 in it.

This is a sub-case of (1)'s drain-fix experiment.  The drain DOES
empty the FIFO, but the "no E>" outcome means draining alone doesn't
reveal whether (3) is the actual cause or just a co-symptom of (1).

Action: same as (1) — probe-based byte-trace post-CCP-start.

## Open follow-ups (file as GitHub issues + local tasks)

| # | Description | Where |
|---|-------------|-------|
| A | SDCC pio-irq Ctrl-P flood: CCP receives 0x10 from CONIN repeatedly | rc700-gensmedet issue + local task |
| B | polypascal-test driver hardcodes `clang/cpnos_polypascal_addrs.lua` — does not honour COMPILER=sdcc | rc700-gensmedet issue |
| C | MAME null_modem with single -bitb file: confirm loopback semantics | docs/MAME_RC702.md note |
| D | cpnos-rom Makefile odd-resident-pad shell hack should be a z88dk align directive | rc700-gensmedet issue + local task |
| E | reset.asm SP comment moved through 4 different layouts in 2 sessions — convert to a derived-from-symbols defc once Path 6 is verified stable | rc700-gensmedet issue (low priority) |
| F | tasks/scripts/check_sdcc_layout.py BSS_LO/BSS_HI hardcoded — read from cpnos.map symbols (`__scratch_bss_start/end`) instead | local task |

## Things that did NOT fix the SDCC pio-irq failure

- SP move (0xEC00 → 0xDE80 → 0xDD80) — stack-into-IVT hypothesis
  falsified.
- `__port_out` B=H mirror — bus-shape hypothesis falsified for RC702
  (which only decodes A0-A7 anyway).  Kept as a deterministic-by-
  default improvement.
- IVT-clobber Makefile assert — kept as a future safety guard; not a
  fix for this session's symptom.

## Things that DID fix the failure (cumulatively)

Path 6 alone unblocked NDOS handoff.  No single one-byte fix; the
visible cause was the 2560 B resident cap pinning code in places that
caused the post-handoff NDOS chain to misroute (exact mechanism not
fully mapped, but the symptom went from "hangs at handoff" to "reaches
CCP" with the resident grow + cpnos.com slide).

## Sources

- Comparison disassembly: `cpnos-rom/tasks/compare-clang-vs-sdcc-handoff-2026-05-08.md`
- Workspace plan: `~/.claude/plans/harmonic-sleeping-spring.md`
  (Path 6 + subsequent workspace bump)
- Earlier session 47 plan: same plan file before being overwritten
  (data-driven relocator, plan #19 steps 1-8 — done as of `302ce24`)

## Next session entry-point

If the user wants to chase the Ctrl-P flood: probe `kbd_ring` / SIO-B
RX state via Lua memory peek in the polypascal-test driver, BEFORE
adding more compiler-side code (which has been the trap pattern this
session — three "fixes" that didn't address the actual mechanism).
