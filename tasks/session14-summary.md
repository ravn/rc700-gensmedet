# Session 14 Summary

Date: 2026-04-08
Branch: main (3 feature branches preserved on remotes)

## Headline

Spent the session attempting to add a 26th display row used as a system
status line on the RC700, via the 8275's dual-DMA path (DMA ch.2 for
rows 1-25 from `0xF800`, DMA ch.3 for row 26 from a separate buffer).
The hardware mechanism works end-to-end (verified by buffer dumps and
screen rasterisation in MAME), but every flicker-mitigation we tried
left a visible cold-boot flicker, so we **shelved the feature** and
preserved the working implementation on feature branches.

In the process found and fixed a **latent ISR DCE bug** that was a
ticking time bomb for any future ISR work in this BIOS.

## Headline metrics

| | clang BIOS | SDCC BIOS |
|---|---|---|
| Session 13 final | 5827 | 5850 |
| Session 14 final on main | **5827** | **5850** |
| status-line-26 branch tip | 6150 | (not built) |

## Latent ISR DCE bug — fixed

The ISR stack-switch helpers in `bios.c` —
`isr_enter` / `isr_exit` / `isr_enter_full` / `isr_exit_full` — were
declared as `static inline` `__naked` functions whose body was a single
`__asm__("...")` block (no `volatile`).

**Without `volatile`, clang treats outputless inline asm as
side-effect-free and may DCE it after inlining**, silently stripping
the ISR's register save/restore and stack switch.

This was a latent bug. For a long time clang chose not to inline these
helpers and the asm survived. An unrelated change to an ISR body
shifted clang's inlining heuristics and exposed it: `isr_crt`'s body
got reorganised to do more work, clang inlined the helpers, the asm
got DCE'd, and the BIOS started crashing on RETI.

### Fix (commit `c179686` on main)

1. Made all four ISR helper asm bodies `__asm__ volatile`.
2. On the **clang build path** the wrappers in `clang/bios_shims.s`
   already do the SP switch + push/call/pop/RETI sequence, so the
   helpers MUST be empty no-op stubs there — otherwise we get a double
   save and a stray RETI inside the C body, corrupting `_sp_sav` and
   crashing on return. SDCC has no shim wrapper, so it gets the real
   asm bodies.
3. Defensively added `volatile` to **all 24 other** `__asm__("...")`
   blocks in `bios.c` and `bios_hw_init.c` — most are inside SDCC-only
   `#ifndef __clang__` paths and aren't actually at risk today, but
   the rule "outputless inline asm must be `volatile`" should hold
   project-wide.

### How to spot this class of bug going forward

After any change that touches an ISR or its callees, verify the
generated `_isr_*` body still contains the expected `ld (_sp_sav), sp`
+ `push af / bc / de / hl` instructions:

```
llvm-nm clang/bios.elf | grep _isr_crt
llvm-objdump -d --triple=z80 --start-address=<isr_crt_addr> --stop-address=<isr_crt_end> clang/bios.elf | head
```

A regression test that grep's the disassembly listing for these
sequences would catch any future recurrence — TODO if we touch the
ISR layer again.

## Status line on row 26 — design & shelving

Tracking issue: ravn/rc700-gensmedet#7
Full write-up: [`tasks/status-line-26.md`](status-line-26.md)

### Hardware mechanism (RC700 dual-DMA CRTC)

The 8275 has one DRQ output that the rc702/rc700 hardware routes
through a `74LS74` D flip-flop to either DMA channel 2 or channel 3:

- `Q = 0 / Qbar = 1` → DRQ goes to DMA ch.2
- `Q = 1 / Qbar = 0` → DRQ goes to DMA ch.3
- `~CRTC_IRQ` clears the flop at the start of every frame (→ ch.2)
- `D` is wired to `Qbar` (toggle), `CLK` is wired to DMA EOP

Inside one frame ch.2 transfers its byte count, EOP fires, the flop
toggles, the next batch of DRQs is serviced by ch.3, then EOP toggles
back. At the next frame the CRTC IRQ clears the flop and the sequence
restarts. rc702-bios never used this path — it fed the 8275 from a
single channel and used a `0xFF` end-of-screen sentinel instead.

### MAME emulation gap (patched on the feature branch)

Plain MAME's `regnecentralen/rc702.cpp` only wired the 7474's `CLR`
pin from `~CRTC_IRQ`; `D` and `CLK` were unconnected, so the flop sat
at `Q=0/Qbar=1` forever and only ch.2 ever serviced the CRTC.

Patched on `ravn/mame-rc702-rc759-rc750 @ status-line-26-dual-dma`:

- `D ← Qbar` (so each clock toggles)
- `CLK ← DMA EOP` (the chip's shared TC pin)

We tried gating `CLK` so only ch.2/ch.3 EOPs (not FDC ch.1 EOPs) toggle
the flop, by tracking DACK2/DACK3 state. The gate broke the toggle in
MAME — DACK timing relative to EOP is different from real hardware —
so the gate was reverted.

### Why we shelved it

7 mitigation attempts didn't eliminate the cold-boot flicker:

a. Move DMA reprogram to be the *first* thing in `isr_crt`
b. Pre-arm in `bios_hw_init` *before* the 8275 reset
c. Re-order so DMA is programmed before the 8275 reset+reprogram
d. Plant 8275 `0xF3 End-of-Screen-Stop-DMA` sentinel after the signon
e. Throttle `status_line_update()` to every 10th frame and gate it
   behind a `boot_done` flag set just before `jump_ccp`
f. Enable Am9517 **rotating priority** (cmd register bit 4) so FDC
   ch.1 doesn't starve the CRT channels during the disk read for
   CCP+BDOS
g. Memset `status_line[]` to spaces so the row 26 buffer has stable
   blank content from the very first frame

The residual flicker is from the ~80 ms window when the BIOS
reprograms the 8275 from 25 → 26 rows; the 8275 takes ~1-2 frames to
resync after a mode change. Eliminating it would require modifying
the autoload-in-c PROM to start in 26-row mode + pre-arm DMA ch.2/ch.3
before the BIOS runs.

It's also possible the residual flicker is purely a MAME emulation
timing gap and doesn't appear on real hardware.

## False alarms investigated and disproved

- **clang Z80 codegen bug for 64-iter loop with ternary inside the
  body.** Suspected during the dual-DMA debugging when the BIOS
  appeared to crash whenever `status_line_update()` had a loop with a
  ternary in it. Buffer dumps + binary disassembly showed the
  generated code is correct. The actual root cause was the latent
  `__asm__ volatile` bug above — adding the loop was just what
  shifted clang's inlining heuristics enough to expose it. **Not a
  codegen bug.** No issue filed.

## Tooling improvements

- New helper script at `/tmp/bios_c_status_dump.lua` (not in repo,
  ad-hoc) — autoboot lua that dumps display memory + status line BSS
  to `/tmp/screen.txt` and writes 100 raw PPM screenshots of the
  rendered display, so we can see what MAME is actually rendering
  without having to eyeball the window. Worth promoting to a project
  helper if we do more visual MAME debugging.

- The `screen_snapshot_pixels` MAME lua API expects `vm:snapshot_pixels()`
  with the colon syntax (not `vm.snapshot_pixels()`) — the dot syntax
  silently fails. Worth a memory note if we hit it again.

## Open issues filed this session

- ravn/rc700-gensmedet#7 — Status line on row 26 via 8275 dual-DMA
  (shelved, see `tasks/status-line-26.md` for write-up + next steps)

## Open issues remaining (no change from session 13)

- llvm-z80: 19 open
- rc700-gensmedet: 2 open (#6 z88dk memmove slow loop, #7 status line)

## Branches preserved on remotes (not merged to main)

- `ravn/rc700-gensmedet @ status-line-26` (2 commits)
- `ravn/mame-rc702-rc759-rc750 @ status-line-26-dual-dma` (1 commit)
- `ravn/z80-compiler-suite-workspace @ status-line-26` (2 commits)

These can be cherry-picked or merged later if we revisit the dual-DMA
approach. The MAME branch in particular is the most reusable —
modeling the dual-DMA path correctly is independent of whether we
ship the BIOS feature.

## Process notes

Spent a *lot* of cycles on the visual flicker debugging, much of it
asking the user "what do you see?" instead of capturing screenshots
myself. Eventually we built the `snapshot_pixels` lua helper and the
investigation became much faster. Lesson: when investigating visual
behaviour in MAME, **set up screen dumping infrastructure first**,
don't iterate through user-eyeball reports.

The other process win was the `ld -r0x6661` style screen dumps —
buffer dumps via the lua autoboot script proved over and over that
the BIOS-side state was correct and the bug was always somewhere
else (8275 underrun, MAME timing, DCE'd save/restore). Without the
dumps we would have wasted even more time chasing BIOS-side ghosts.
