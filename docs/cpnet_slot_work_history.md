# CP/NET host-bridge slot work — history and current state

> Status as of 2026-04-27.  Living summary; update when material
> things change.  Companions:
> [`cpnet_fast_link.md`](cpnet_fast_link.md) (design context),
> [`cpnet_pio_direct_design.md`](cpnet_pio_direct_design.md) (no-slot
> alternative), [`mame-rc702-piob-slot-regression.md`](mame-rc702-piob-slot-regression.md) (ravn/mame-rc702-rc759-rc750#6 mirror, closed as not-a-bug).
>
> **Headline finding (2026-04-27)**: ravn/mame-rc702-rc759-rc750#6 was a misdiagnosis.
> The slot infrastructure on PIO-B is fine.  Every "black screen / IM2
> regression" symptom was caused by `prom1.ic65` not being loaded into
> the rc702 prom1 ROM region.  Both the empty-slot and `-piob
> cpnet_bridge` configurations boot cpnos-rom cleanly when prom1 is
> loaded.  Path 2 (Einstein topology revert), Path 3 (devcb /
> std::function bypass attempts), and the no-slot direct-bridge design
> were all chasing a non-existent bug.

## Goal

Plumb CP/NET frames between the Z80's PIO-B port inside MAME's
`rc702` driver and an external process (Pi/Mac harness, eventually
real MP/M-NET).  This is "Option P" in the fast-link design.

## Timeline

### Slot-based attempt (cpnet-fast-link branch)

Implemented as MAME's idiomatic peripheral pattern:

```
src/devices/bus/rc702/pio_port/
  pio_port.{h,cpp}    rc702_pio_port_device wraps device_single_card_slot_interface
  keyboard.{h,cpp}    generic_keyboard wrapped as a slot card on PIO-A
  cpnet_bridge.{h,cpp}  POSIX-socket TCP listener on :4003 + listener thread
                       + FIFO + emu_timer poll + STB pulse
```

`rc702.cpp` wired both PIO-A and PIO-B as slots:

```cpp
m_pio->in_pa_callback().set(m_pio_a, FUNC(rc702_pio_port_device::read));
m_pio->in_pb_callback().set(m_pio_b, FUNC(rc702_pio_port_device::read));
```

PIO-A defaulted to `keyboard` card (preserving existing behaviour);
PIO-B defaulted to empty slot (no card), `-piob cpnet_bridge`
populated it.

Merged into master via merge commit `588658b4327` "Option P slot
infrastructure + WIP fix" on 2026-04-25.

### Regression discovery (Session #32)

Symptom: with `-piob cpnet_bridge` (or `-piob keyboard`), cpnos-rom
guest initialization stalls — VRTC IRQ stops firing, CRT goes black,
CCP never loads.  Without `-piob` (empty slot), cpnos-rom appeared
to boot to A>.

Filed as **[ravn/mame-rc702-rc759-rc750#6](https://github.com/ravn/mame-rc702-rc759-rc750/issues/6)**.

### Workaround attempts (all failed)

**Path 2 — Einstein topology** (commit `54cccdbc3af`).  Hypothesis:
having two slots on a single Z80-PIO chip is the trigger; reverting
PIO-A to direct keyboard wiring while keeping PIO-B as the lone slot
should fix it.  Result: `-piob keyboard` still produced the regression.
**Falsified** the "two slots" hypothesis — a single slot card is
enough.

**Path 3 — bypass slot, wire `cpnet_bridge_device` directly to chip
callbacks**.  Two flavours:

- 3a: `devcb_write_line` + accessor pattern.
- 3b: `std::function<void(int)>` + lambda.

Both crashed at MAME config time (`device_t::config_complete + 428`)
with PAC-tagged garbage register dumps — before any data flowed.
Discarded.

### "Empty slot is benign" — wrong for cpnos — also wrong (2026-04-27)

A 2026-04-27 finding initially appeared to invalidate the
"empty slot is benign" claim — cpnos-rom on master (post-merge,
empty PIO-B slot) hung at `PC=0x0039`.  Conclusion at the time:
even an empty `RC702_PIO_PORT` wrapper breaks cpnos-rom IM2.

**That conclusion was wrong too.**  See "Misdiagnosis identified"
below — the actual cause was `prom1.ic65` missing from the loaded
ROM region.  The hang at `PC=0x0039` had nothing to do with the slot
wrapper.

### Master reverted (2026-04-27)

`master` was reverted to drop the merge: commit `b06f303737a`
"Revert 'Merge branch cpnet-fast-link'".  Working tree of the revert
is byte-identical to pre-merge `1f2d4d000db` (verified with `git
diff --stat 1f2d4d000db HEAD` returning empty).

Open puzzle: a freshly-built binary from the revert tree fails
cpnos-rom boot the same way the merge did, while the April-21
daily-use binary at `/Users/ravn/git/mame/regnecentralend` (built
from the same `1f2d4d000db` SHA) succeeds.  Same source, different
behaviour.  Suspects: stale `.o` cache pollution from earlier
slot-infra builds, or build-flag drift.  Still under investigation.

### Misdiagnosis identified — slot was always fine (2026-04-27)

The `1f2d4d000db` daily-use binary booted cpnos cleanly; my freshly
rebuilt revert binary (same SHA, byte-identical tree) failed at
`PC=0x0039`.  Investigation revealed the daily-use clone had an
**uncommitted local patch** in `rc702.cpp`:

```diff
-	ROM_FILL( 0x0000, 0x1000, 0xff ) // line program ROM (ROB388 on MIC705) - undumped prom1.ic65
+	ROM_LOAD_OPTIONAL( "prom1.ic65", 0x0000, 0x0800, NO_DUMP )
```

That patch made MAME load `prom1.ic65` from the rc702 rom path when
present.  cpnos-rom puts its resident helpers there (PROM1 chunk B
of the relocated payload, see `relocator.c`); without them, the
relocator copies 0xFF garbage to RAM, and the resident BIOS jumps
into nothing — hang at `PC=0x0039`.

The patch was promoted to the tree as `9ff362da529` "rc702:
ROM_LOAD_OPTIONAL for prom1.ic65 (CP/NOS resident helpers)".

**Verification** with the patch cherry-picked onto `cpnet-fast-link`
(commit `823a50a5230`) and `make cpnos-netboot` run in two configs:

| Config | prom1 loaded | Result |
|---|---|---|
| Empty PIO-B slot (no `-piob`) | yes | **PASS** — banner + A> render |
| `-piob cpnet_bridge` | yes | **PASS** — banner + A>, full LOGIN flow |

Both pass.  Slot infra and the cpnet_bridge card both work fine.

**Implications**:
- ravn/mame-rc702-rc759-rc750#6 closed as not-a-bug.
- Path 2 (Einstein topology revert) was unnecessary.  PIO-A could
  go back to a slot card.
- Path 3 (devcb / std::function bypass attempts) chased a phantom.
- The no-slot direct-bridge design (this repo's
  `cpnet_pio_direct_design.md`) is not needed for correctness.
  Slot approach works.

**Loader sanity check added** (commit follow-up): `relocator.c` now
checks a `'CPN1'` sentinel at PROM1 end (0x27FC..0x27FF) before
copying payload_b.  If the sentinel is absent (PROM1 reads as
0xFF padding), the relocator writes `'P','R','M','?'` to
0xFFFC..0xFFFF and busy-loops.  `mame_boot_test.lua` checks for
this marker and reports "FAIL: PROM1 missing" within 1 second of
boot, instead of the previous 60-second "no A>" timeout with
cryptic register dumps.

### Direct (no-slot) bridge attempt — branch `cpnet-pio-direct`

Designed in
[`cpnet_pio_direct_design.md`](cpnet_pio_direct_design.md):
drop slot/card entirely; wire `m_pio->in_pb_callback().set(FUNC(rc702_state::cpnet_pb_r))`
directly; use MAME's `osd_file` as TCP listener (no POSIX socket);
single emu thread via 1ms `emu_timer`; raw byte logs to
`/tmp/cpnet_pio_rx.bin` + `tx.bin`.

Implementation was written and built once.  At the byte layer it
worked: 6 bytes from the harness arrived in `rx.bin`, the strobe
fired once, the chip's `in_pb_callback` returned the right byte.
But the chip's IRQ never delivered (chip log: `IE=0 IP=1` at end —
cpnos-rom never enabled IRQ on PIO-B before our strobe arrived,
because cpnos-rom itself wasn't booting through to its PIO-B init
phase — the slot-infra regression was masking everything).

The implementation code was lost in a stash/checkout cycle.  Design
doc and rc700-gensmedet harness changes survive.  Re-implementation
should be straightforward from the design doc.

## Branch state (2026-04-27)

| Repo | Branch | Tip | Notes |
|---|---|---|---|
| `ravn/mame-rc702-rc759-rc750` | `master` | `b06f303737a` | Revert of merge `588658b4327`; not yet pushed (verification still pending) |
| `ravn/mame-rc702-rc759-rc750` | `cpnet-fast-link` | `54cccdbc3af` | Slot infra + Path 2 revert; pushed |
| `ravn/mame-rc702-rc759-rc750` | `cpnet-pio-direct` | (master tip) | No commits beyond master; design doc only in rc700-gensmedet |
| `ravn/rc700-gensmedet` | `main` | `3c0a1b1` | Has the merged Phase 3 cpnos-rom + harness pre-redesign |
| `ravn/rc700-gensmedet` | `cpnet-pio-direct` | (uncommitted) | `harness.py` switched mpm-net2 → `netboot_server.py`; `dump_logs.sh`; design doc |

## What we still don't know

1. **Why empty PIO-B slot breaks cpnos-rom IM2 vector**.  The
   structural mismatch (Z80-PIO is flat in MAME, no per-port
   subdevices) is suspicious but doesn't explain the specific
   failure mode (cpnos hangs at PC=0x0039 before its first SIO-A
   write).  Path 2 ruled out "two slots on one chip".  Path 3
   crashes ruled out one specific bypass approach.  The actual
   broken seam in MAME's slot/PIO interaction has not been
   localized.

2. **Why a freshly-built revert binary differs from the April-21
   daily-use binary built from the same SHA**.  Same source tree,
   different behaviour.  Build cache, link order, or compiler
   version drift are the candidates.

## Next steps

1. **Fix or work around the build delta** so the revert binary
   actually matches the daily-use binary's behaviour.  Without
   that, no clean baseline for the direct-bridge implementation.
2. **Re-implement the direct-bridge code** on `cpnet-pio-direct`
   from the design doc.  ~80 lines net change in `rc702.cpp`.
3. **Verify the direct bridge** with the harness: byte-level
   round-trip + cpnos-rom screen renders + isr_pio_par fires.
4. **Amend ravn/mame-rc702-rc759-rc750#6** comment to reflect "empty slot also
   breaks cpnos for IM2-using guests".
5. **(Eventually)** revisit the slot-on-PIO regression itself,
   either by debugging MAME's interaction or by accepting the
   no-slot pattern for RC702 and documenting the scope as a
   known limitation upstream.

## What survives if this work pauses

- `cpnet-fast-link` branch (mame): preserves all the slot work for
  reference, including the failed Path 2 attempt.
- `mame-rc702-piob-slot-regression.md`: factual bug report (needs
  amendment per the empty-slot finding).
- `cpnet_pio_direct_design.md`: the design doc for the no-slot
  approach, suitable for re-implementation.
- This file: connective tissue between them.
