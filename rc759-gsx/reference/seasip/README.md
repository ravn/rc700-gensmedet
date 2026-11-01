# Historical GSX-86 reference sources

Source page: <https://www.seasip.info/Cpm/software/gsx86.html>.
Retrieved for local RC759 driver analysis on 2026-10-31.

## Provenance

| Archive | SHA-256 |
|---|---|
| [gios11.zip](https://www.seasip.info/Cpm/software/gios11.zip) | `227ae117fe98ef953043fa2b9bd4aac866ca25a6d2c3ea52c0bd0dd671e2a45e` |
| [gdos1.3.zip](https://www.seasip.info/Cpm/software/gdos1.3.zip) | `1bbacb4df5df64cd1b19d9e3fc09962bdbfc4969c496b8b3a335f44422bdddc8` |

The retained files are byte-for-byte copies of the extracted archive entries,
including original line endings, notices, and disassembler control characters.
They are reference material, not part of the H1 build.
Existing copyright notices remain applicable; this directory does not grant
a new license or establish redistribution rights.

**GIOS11 is reconstructed source.** Its `README.TXT:4-10` explicitly says
"disassembled source" and describes the original high-level language as
"likely RATFOR". The language identification is the README author's hypothesis,
not an established fact. It distinguishes five original DRI/GSS implementations
from four later ports (`README.TXT:23-35`). Archive timestamps and edits from
2016 are not original release dates.

## Retained files

`gios11/` contains the five original driver implementations named in the README:
`DDIBM.A86`, `DDIBMC.A86`, `DDCSA1.A86`, `DDORCH.A86`, and `DDPLUS.A86`.
Their dependencies are `COMMON0..3.INC`, `CSA10/12/13.INC`, `FONT.INC`,
`FONT0.INC`, and `MACROS.INC`; the original `README.TXT` is retained too.
Compiled SYS files and later MCGA/VGA/VESA ports were not copied here.

`gdos13/` contains the CP/M-86 GDOS interface/loader sources `GSX.A86`,
`GSXCOMM.A86`, `GSXLDR.A86`, and `GSX.INP`, plus `READ.ME`.
The archive's later DOS adaptations (`GSXD.A86`, `GSXLDRD.A86`) were not retained.
This is a separate GDOS version, useful for checking the ABI; it is not proof
of which GDOS revision originally accompanied the RC759 driver.

FreeGEM sources are not used: the comparison targets historical GSX-86,
following the user's clarification.

Findings and original-driver offsets:
[GSX 1.1 source comparison](../../notes/04-gsx11-source-comparison.md).
