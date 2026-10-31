# DRI's 1983 GIOS skeleton guides and RC759 H1

The user's Lund archive link supplies the missing **8086-family skeleton
configuration documentation**, distinct from the general Programmer's Guide's
8080 Appendix A and from Seasip's disassembled GSX 1.1 drivers.
Retained documents and provenance:
[`reference/lth-writing-drivers/`](../reference/lth-writing-drivers/README.md).
Analysis date: 2026-10-31.

**Follow-up:** the later web search found the mono/color assembly packages.
They are now retained under `reference/dri-skeleton/`; see
[the actual-source comparison](06-dri-skeleton-oracle-comparison.md).
The negative filename/index findings below describe the initial guide-only
inspection, not the current reference inventory.

## What is actually present

The monochrome CP/M-86 & CCP/M-86 guide is dated September 17, 1983.
It identifies a hardware-specific source `BWMMSKCP.A86`, an included optimized
source `MONOMMRE.A86`, a common object `MONOMMOB.OBJ`, and `FONT.OBJ`
(`monmmskc.html:85-95,311-337`).
This is a different package description from GIOS11's shared high-level-style
disassembly. It makes the optimized skeleton a useful **candidate** for H1's
structure, but does not prove H1 came from that package: the named A86/OBJ
files themselves were not present in the inspected web indexes or found by
workspace filename searches.

The color guide explicitly identifies Digital Research and November 9, 1983
(`colrskel.html:29-31`). It targets three separate bitmap planes and says
two/four-plane cases were not yet addressed (`:63-115`). It must not be used
to infer RC759 suffix meanings or assume H1 is a three-plane driver.

## Verified routine-name correspondence

The guide names `concat` as the X/Y-to-physical-bitmap-address routine
(`monmmskc.html:293-307`). H1 `CS:046A` has exactly that role, but its
strip-based layout requires its own formula; the guide's contiguous-scanline
hardware assumption (`:51-76`) is not H1's memory arrangement.

The guide describes `get_loc_key` and AL status 0/1/2
(`monmmskc.html:509-545`). H1 `CS:0DB3` follows this protocol:
no key -> AL=0; nonmovement key -> AL=1, key in AH; movement -> AL=2.
It uses the signed delta table at `DATA:02B2`; keys C8/D0/CD/CB select
directions and C9 toggles the small/large movement-table offset.
H1 returns proposed absolute coordinates in BX/CX after adding the deltas,
so the full register ABI must not be inferred just from the routine name.
`loc_tbl` is a justified semantic name for `DATA:02B2`, not a GDP table.

The guide names cursor-sequence tables `cur_up`, `cur_down`, `cur_right`,
`cur_left`, `home_cur`, `erase_to_eop`, `erase_to_eol`, `cur_position`,
`reverse_on`, `reverse_off` (`monmmskc.html:371-455`).
H1 has these count-prefixed **word** sequences at DATA:0263,0269,026F,0275,
027B,0281,0287,0299,028D,0293 respectively.
For example DATA:0263 contains count 2 followed by ESC and 'A'.

## Important correction: source ESCAPE labels are off by one

The H1 dispatcher directly indexes `DATA:0146` with twice the requested
subfunction; it does not subtract one (`src/dd759h1.a86`, `CS:016E`).
The original SYS contains the following targets, independently decoded with
little-endian word reads. Compare the guide's ESCAPE definitions
(`monmmskc.html:358-485`), not the reconstructed source's current label names:

| ESCAPE | Original CS target | Established meaning / guide name |
|---|---|---|
| 0 | 017E | Extra identification response; not the character-cell inquiry |
| 1 | 018E | Character cells, escfn1; returns 24 rows and 80 columns |
| 2 | 01B0 | Enter graphics and clear, escfn2 |
| 3 | 01B7 | Exit graphics, escfn3 |
| 4 | 01BA | Cursor up, escfn4 |
| 5 | 01BF | Cursor down, escfn5 |
| 6 | 01C4 | Cursor right, escfn6 |
| 7 | 01C9 | Cursor left, escfn7 |
| 8 | 01CE | Home cursor, escfn8 |
| 9 | 01D4 | Erase to end of screen, escfn9 |
| 10 | 01D9 | Erase to end of line, escf10 |
| 11 | 01DE | Direct cursor address, escf11 |
| 12 | 01F9 | Alphanumeric text output, escf12 |
| 13 | 0206 | Reverse video on, escf13 |
| 14 | 020B | Reverse video off, escf14 |
| 15 | 021F | Cursor position inquiry, escf15 |
| 16 | 0239 | Input-device status inquiry, escf16; returns zero |
| 17 | 0248 | Hardcopy, escf17; RET stub |
| 18 | 0249 | Place graphic cursor, escf18 |
| 19 | 0261 | Remove graphic cursor, escf19; redraw saved XOR cursor |

The existing label `esc03_exit_graphics` at CS:01B0 is therefore wrong:
it is the handler for ESCAPE **2**, and calls Init Graphics then Clear.
Likewise `esc04_cursor_up` at CS:01B7 exits graphics.
This is an annotation error, **not a dispatch bug in the original binary**.
The row/column comments in the CS:018E handler are also reversed.

Labels have not been renamed in this documentation-only step. The table is
the verified basis for a coherent later rename, including every call site.
No claim is made that the RC759 routines retain the original skeleton's
literal symbol names; the guide establishes roles, not a symbol table for H1.

## The historical test suite directly addresses our oracle gaps

`tstsuite.html:62-75` explicitly warns that apparently working TESTGIOS output
does not establish complete driver correctness.
MODETEST renders text, polyline, bar, polygon and marker under **both pen 0
and pen 1 in all four writing modes** (`:192-214`). That is particularly
relevant to the color-zero discrepancy between the manual expressions and
the H1/IBM static models in [the earlier comparison](04-gsx11-source-comparison.md).

The suite also describes:

- `scrn12`: zero-length primitives/off-by-one cases (`:300-303`).
- `scrn13`: writing modes (`:305-307`).
- `scrnx1`: line generation across slopes (`:329-333`).
- `scrn15`: open/clear sequencing (`:312-316`).
- `scrn20a/b`, `scrn21/22/23`: locator, choice, string and valuator input.

These are descriptions, not executable tests we have run. The retained test
PDF supplies the referenced illustrations. No test binaries were downloaded
from these indexes, and no MAME or emu2 graphics validation was performed.

## Validation

The ESCAPE addresses and cursor-sequence words were read from the **original
SYS**, independently of the source annotations. Five downloaded guides were
checked for nonempty content; both PDFs have PDF signatures; SHA-256 hashes
are recorded in the reference README. Only documentation changed in this
step. The existing byte-identical H1 source and binaries were not modified.
