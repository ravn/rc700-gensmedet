# impl_conout: implement RC700 graphics-overlay control codes 0x14/0x15/0x16

Status: planned, not started.  Gap affects BOTH cpnos-in-c (`specc`
in `src/resident.c`) AND cpnos-in-asm (`impl_conout` in
`src/snios_payload.asm`).

## Gap

Authoritative RC700 BIOS `SPECC` jump table in
`../rcbios/src/DISPLAY.MAC:504` (label `TAB1`) maps:

| Code | Function          | Handler   | cpnos-in-c | cpnos-in-asm |
| ---- | ----------------- | --------- | ---------- | ------------ |
| 0x14 | SET_BACKGROUND    | `ESCSB`   | missing    | missing      |
| 0x15 | SET_FOREGROUND    | `ESCSF`   | missing    | missing      |
| 0x16 | CLEAR_FOREGROUND  | `ESCCF`   | missing    | missing      |

These drive the RC702 optional 200x240 monochrome bitmap overlay
(separate display RAM, requires `BGFLG` / `BGSTAR` state).  Both CP/NOS
variants currently DROP these codes silently because the slave does
not implement the graphics-overlay buffer + bitplane state machine
that the rcbios `DISPL` routine maintains around them (see
`DISPLAY.MAC:603-648`).

## Why the gap matters

  - CP/M utilities, PolyPascal, WordStar etc. don't touch these
    codes -- text-mode programs work fine without them today.
  - Graphics programs (rare on RC700, would target the optional
    bitmap overlay board) get silently corrupted output: their
    bitmap-write commands are dropped and the underlying text
    framebuffer is unaffected.
  - The commit message "full RC700 control-code set in cpnos-in-asm"
    (commit `3a31ec9`) was overstated -- it's the full **text-mode**
    set.  Same caveat applies to cpnos-in-c's `specc`.

## What "implement" requires

The graphics overlay is a separate hardware concept from the
character framebuffer at 0xF800:

  - **BGSTAR**: base address of the bitmap plane in display RAM.
    rcbios uses a separately-allocated buffer; the address is
    machine-configuration dependent.
  - **BGFLG**: tri-state flag (0=off, 1=foreground, 2=background)
    indicating which plane subsequent printable characters write
    to.  Set by 0x15 / 0x14; cleared by 0x16.
  - **Bitplane writes**: when BGFLG != 0, printable character writes
    consult the character's font bitmap, OR it into the appropriate
    plane at the cursor cell.  See `DISPL3` at `DISPLAY.MAC:622-648`.

Implementing 0x14 / 0x15 / 0x16 alone is incomplete -- they only set
flags; the actual bitplane writes require modifying the printable-
character path in impl_conout to honor BGFLG.

## Steps to implement (cpnos-in-c side)

1.  Allocate BGSTAR buffer.  Memory rule `feedback_slave_state_outside_tpa`:
    state must live in the SNIOS reserved area 0xED00..0xF7FF, not
    TPA.  Bitmap plane is large (200x240 monochrome = 6000 B);
    won't fit in residual SNIOS RAM (~256 B free at 0xEB00 scratch).
    Likely needs to share / overlay with display RAM near 0xF800
    or use the RC702 graphics-overlay hardware buffer directly
    (port-mapped on the optional board).

2.  Add BGFLG state variable (1 B) to .scratch_bss in `src/resident.c`.

3.  Add three case statements to `specc` (lines 320..340 of
    resident.c) dispatching to handlers that set/clear BGFLG.

4.  Modify the printable path in impl_conout (lines 384..387) to
    OR character font bitmap into bitplane when BGFLG != 0.

5.  Implementation in cpnos-in-asm mirrors the C path -- both
    variants share the rcbios `DISPL` reference logic.

## Open questions before implementing

1.  **Hardware availability.**  Does the user's actual RC702
    hardware have the optional graphics-overlay board?  If not,
    the implementation can only be MAME-tested.  Check
    `RC702_HARDWARE_TECHNICAL_REFERENCE.md` for the bitmap-board
    port map; if undocumented, the rcbios `BGSTAR` / `BGADDR` ops
    in DISPLAY.MAC tell us where the plane lives in physical
    address space.

2.  **MAME driver coverage.**  Does the rc702 driver in
    `/Users/ravn/z80/mame/` implement the bitmap overlay?  If not,
    correctness verification is bottlenecked on driver work.

3.  **Test programs.**  Find or write a CP/M binary that exercises
    0x14/0x15/0x16 (graphics-mode demos from era?  RC702 Comal?
    rcbios's own conout_test could be extended).

4.  **PROM1 budget impact.**  Current cpnos-in-c PROM1-only is
    1931/2048 B (117 B free).  Adding BGFLG state + 3 case
    handlers + bitplane-write branch in printable path is roughly
    +30..50 B of resident.  Fits with margin but consumes most
    of the remaining headroom.

## Lower-priority finish

Worth doing only if graphics-mode workloads become a real
requirement.  Text-mode coverage (which all known RC702 software
uses) is complete on both variants.  The gap is documented in
`cpnos-in-asm/PARKED.md` and now here, so resuming the work has a
clear entry point.
