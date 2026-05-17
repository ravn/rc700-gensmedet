# cpnos-in-c: make cpnos.img relocatable (.PRL/.SPR-style)

**Status:** TODO (filed 2026-05-17 from session 73j-locale follow-up).

## What

Replace the monolithic, fixed-address `cpnos.com` build with a
DRI-style page-relocatable image (.PRL or .SPR), and add a slave-
side relocator that patches absolute 16-bit addresses at load time
based on a chosen `CODE_BASE`.

## Why

The current `cpnos.com` is built by DRI RMAC+LINK at a fixed
`CODE_BASE` (today `LDD80`).  Every time the slave's resident BIOS
shrinks or grows, we either accept a TPA-size mismatch or rerun
`cpnos-build` via VirtualCpm (slow, depends on a working Java
runtime and the cpnet-z80 source tree at the right hash).  A
relocatable cpnos lets the slave pick `CODE_BASE` at boot from
its own link map (e.g. `(0xED00 - 0xC80)` for "butt against
resident").

## Mechanics

CP/NOS shipping NDOS+BDOS as `.SPR` files (Page-Relocatable
modules) is the standard DRI design -- exactly what MP/M and
CP/NOS use to handle "any system, any TPA".  Our slave today is
the outlier because it doesn't have an .SPR loader.

Build side:

  1. Tell RMAC+LINK to emit `.PRL` instead of `.COM`.  The format
     is documented in DRI's "Programmer's Utilities Guide for the
     CP/M Family"; effectively a flat-binary page with a trailing
     relocation bitmap (1 bit per byte, 1 = patch high byte of a
     16-bit address by `+page`).
  2. Replace `stamp_cpnos.py` with a `.PRL` stamper that finds
     the same 32-byte trailing region.

Slave side:

  1. Pick a `CODE_BASE` based on the resident link map (e.g.
     extract `__payload_start - 0xC80` symbolically).
  2. After netboot loads the .PRL image, walk the relocation
     bitmap and patch every flagged byte.
  3. Then JP into NDOS as today.

## Cost

  * Slave resident: ~100..200 B for the relocator walk.  Plus an
    extra ~12..16 B of trailing bitmap per loaded image.  This
    is the bind for PROM1-only (currently 27 B free; would need
    shrinking work elsewhere first).
  * Build: emit `.PRL`, write the stamper variant.  ~half a day.
  * Test coverage: every TPA-size variant becomes a runtime
    permutation, so the existing 4-cell matrix needs a TPA-axis.

## Wins

  * **No more `cpnos-build` rebuilds when resident layout shifts.**
    The slave just picks a different CODE_BASE and the .PRL adapts.
  * **TPA size becomes a runtime decision** -- could even be a
    SW1 bit, or read from cpnos.img header.
  * **Sets up the CP/M-3-style architecture** where BIOS and BDOS
    are independently loaded modules.  Future-friendly.

## Caveats

  * **Tight against PROM1 budget.**  The 100..200 B relocator
    needs space; today there are 27 B free.  Pair with the
    cpnos.img ZX0 compression work to recover bytes elsewhere,
    or wait until a resident shrink lands.
  * **Debugging gets harder.**  A relocator bug means cpnos.com
    looks correct on disk but executes wrong; the failure mode
    is "random NDOS crashes at random TPA sizes."  Add a strong
    pre-flight checksum in the .PRL header.
  * **VirtualCpm RMAC+LINK quirks.**  DRI's .PRL output mode is
    well-documented but RMAC's tooling is older than the .COM
    path; expect minor breakage.

## When

After cpnos.img ZX0 compression has settled and PROM1 has
recovered some headroom.  Probably a session of its own.
