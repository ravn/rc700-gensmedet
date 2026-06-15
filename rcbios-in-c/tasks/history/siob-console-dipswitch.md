# SIO-B console: DIP switch selection — DONE

## Resolution (2026-04-17)

Implemented on branch `siob-console-dipswitch`.  The post-merge main
already had a DCD-based probe (not the older ENQ probe); this replaces
that with a DIP switch read.

### What the switch does

Bit 0 of the DIP switch port (SW1 at I/O port 0x14):

- **Set** (bit value 1) → `IOBYTE_CON_JOINED` (0x97):
  - Console input: keyboard + SIO-B RX joined
  - Console output: SIO-B TX + CRT display
  - RDR:/PUN: routed to SIO-A as usual
  - LST: routed to SIO-B (LPT)

- **Clear** (bit value 0) → `IOBYTE_CON_LOCAL` (0x95):
  - Console input: keyboard only
  - Console output: CRT only
  - RDR:/PUN: routed to SIO-A
  - LST: routed to SIO-B — SIO-B behaves as printer like the original
    RC702 BIOS

With the switch off, the machine presents exactly the same console I/O
semantics as the stock RC702 BIOS — suitable for normal users who don't
need remote debug access.

### Implementation

`bios.c` `bios_boot_c()` now reads port 0x14 bit 0 and picks the IOBYTE
preset accordingly.  No probe, no timeout — instant.  One byte smaller
in clang than the previous DCD probe (6040 vs 6041).

Both SIO-A and SIO-B run at 38400 8N1 regardless of the switch.

### Questions closed

- Which DIP switch bit: bit 0 (the lowest).
- Should there be a runtime toggle: not needed — users can still
  `STAT CON:=TTY:` etc. at any time to override the boot-time choice.
- Fallback behavior: stock BIOS semantics when switch is off, no other
  fallback needed.

### Banner

On cold boot with the switch enabled the BIOS prints a second banner
line: `SIO-B debugging enabled (38400 8N1)`.  With the switch off only
the standard `RC700 56k CP/M 2.2 C-bios/...` signon appears.

### MAME testing

`make mame-maxi` now launches with
`-autoboot_script mame_enable_siob_debug.lua`, which sets DSW S01 on the
first frame so MAME boots with the debug banner visible.  The MAME cfg
file for DIP defaults can't be committed (gitignored to avoid stale
ioport overrides); the Lua script is the durable way to express the
intent.

Verified 2026-04-17 in MAME with clang BIOS (6033 B):
- Switch off → stock banner only, CRT console only
- Switch on  → "SIO-B debugging enabled" banner, CON on SIO-B + CRT

Screenshots captured at /tmp/mame_snaps/rc702_boot.png (switch off) and
rc702_debug.png (switch on).
