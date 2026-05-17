# cpnos-in-c PROM1: compress further so BOOT_MARK can be re-enabled

**Status:** TODO (planned, not started).  Filed 2026-05-17 by user
right after the locale-tables feature landed at PROM1 2010 / 2048 B
with BOOT_MARK_ENABLED=0.

## What

Find ~67 B of PROM1 compression so the cold-boot visual progress
markers (`I N I L O R E + P J` in display row 0 cols 60..78) can be
restored.

## Context

The session 73j-late locale-tables feature (branch locale_tables_v3,
merged via TBD) added ~70 B of PROM1 code:

  * runtime IMG_BASE branch in init.c
  * install_locale_tables() in resident.c
  * impl_conin inconv lookup
  * impl_conout outcon lookup
  * prom1_only_sentinel BSS + bootstrap.s write
  * --defsym extraction in Makefile

That pushed PROM1 27 B over the 2 KB cap, which was closed by setting
`BOOT_MARK_ENABLED=0` (frees 67 B in PROM1 by elimating ~14 inline
display-memory writes scattered through init.c / cpnos_main.c).

After the change: PROM1 = 2010 / 2048 B (38 B free).  Visible markers
are no longer painted at cold-boot, removing a small but useful
"which stage did the slave reach" diagnostic.

## Goal

Find 67 B (or more) of PROM1 compression so BOOT_MARK_ENABLED can be
flipped back to 1 (default).

## Compression levers identified during session 73j

Per the session-73j shrink investigation
(`tasks/shrink-investigation-2026-05-17.md`), the larger functions
in PROM1's payload are:

  * `_snios_rcvmsg_c`     345 B  -- SNIOS frame receiver
  * `_snios_sndmsg_force` 196 B  -- SNIOS sender
  * `_netboot_mpm`        169 B  -- cold-init only
  * `_scroll_lines`       113 B  -- display scroll
  * `_port_init`          110 B  -- hardware bring-up
  * `_specc`               96 B  -- already uses a jump table

Plus rodata (cfgtbl init template, banner string, etc.).

Tractable shrink ideas:

1. **Refactor snios_rcvmsg_c**.  345 B is the single biggest function.
   The DRI frame-receive state machine has multiple state variables
   and error paths.  A factor of 1.2x improvement (60 B) would close
   most of the gap.  Risk: protocol correctness regression.

2. **Compact cfgtbl_init_template** (13 B rodata in INIT_RODATA).
   Hand-roll the LDIR-replacement byte stores -- but probably already
   optimal since session-58 work.

3. **Move netboot_mpm helpers into a shared subroutine**.  cpnet_xact,
   install_fcb, reuse_fcb are tiny but called 4-5 times.  Already
   factored.

4. **Shrink the IRQ-mode PIO ISR** in transport_pio.c.  Already
   hand-coded asm with PRESERVES_REGS_CLANG; little fat.

5. **Shrink the SNIOS jump table** in bios_jt.s.  17 entries x 3 B =
   51 B; ABI-fixed.  Cannot shrink without breaking BDOS/NDOS expectations.

6. **Compress more aggressively in ZX0** -- already using the standard
   decoder; "Salvador" / Megalz / aPLib variants might pack tighter at
   the cost of decoder size.  Probably net-negative for 67 B target.

7. **The dual-transport JT (xport_jt.s)** -- 6 B + ~30 B install_transport.
   If user accepts a single-transport build (PIO only, no SW1 bit 2
   switch), the JT + patcher can be removed.  Saves ~36 B.  Cost:
   loses the runtime PIO/SIO transport selection.

## Cost class

Medium to large.  Item 1 (snios_rcvmsg_c refactor) is the cleanest
target but real protocol-critical code.  Item 7 (drop dual-transport)
is mechanical but a feature regression.

## When

Pick up the next time PROM1 budget feels meaningfully tight, OR when
a real cold-init bug forces re-enabling BOOT_MARK_ENABLED for
diagnostic visibility.
