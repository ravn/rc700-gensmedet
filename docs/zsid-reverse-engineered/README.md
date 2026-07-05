# ZSID reverse-engineered sources — local mirror

Mirror of W. Cirsovius's disassembly/reassembly of DRI's ZSID debugger,
fetched 2026-06-17 from
<https://mark-ogden.uk/mirrors/www.cirsovius.de/CPM/Projekte/Disassembler/ZSID-en.html>.
The page mirror chain is Mark Ogden → cirsovius.de (original
maintainer).  Kept in-repo so the GDB-on-RC702 work has a stable
reference even if the upstream mirror moves.

## Files

| File | Lines | Purpose |
|---|---|---|
| `INDEX.html` | — | The Cirsovius landing page, captured for provenance |
| `SIDRELO-MAC.txt` | 3038 | **Kernel** — breakpoint setup/teardown, command dispatch, register save/restore, CCP-line + parameter parse, BDOS/BIOS shim.  Shared between SID (8080) and ZSID (Z80). |
| `ZSIDLA-MAC.txt` | 2282 | **Z80-specific layer** — instruction decoder used by the single-step engine (decides next-PC for `JP`, `CALL`, `RET`, `RST`, conditional jumps, computed jumps, etc.) plus the Z80 register file save/restore.  Co-designed with SIDREL. |
| `SIDCMD-MAC.txt` | 2332 | **Command interpreter** — the CLI surface: `D`, `H`, `I`, `L`, `M`, `O`, `R`, `S`, `T`, `U`, `W`, etc.  This is the file we'd **replace** if adapting ZSID as a GDB-RSP backend. |
| `HIST-MAC.txt` | 515 | Stand-alone utility: histogram of PC visits — for profiling. |
| `TRACE-MAC.txt` | 391 | Stand-alone utility: instruction trace logging. |

## Why this is in the project

ChatGPT suggested (relayed to us 2026-06-17) that adapting ZSID could
do the "heavy lifting" of the on-target debug engine while we keep only
the GDB-RSP packet layer.  The architectural alternative is to use the
upstream FSF stub at
[`gdb-17.2/gdb/stubs/z80-stub.c`](https://sourceware.org/git/?p=binutils-gdb.git;a=blob;f=gdb/stubs/z80-stub.c)
verbatim.  See `tasks/gdb-z80-stub-findings-2026-06-19.md` for the tradeoff analysis.

The two paths are **complementary**, not mutually exclusive:
- `z80-stub.c` → compiled into our firmware (rcbios) for debugging the
  components we build ourselves
- ZSID-adapted → loaded separately as a TPATOP utility for debugging
  **arbitrary CP/M programs** without recompiling them (the CCP,
  PolyPascal, autoload PROM after handover, anything else)

## License note

These reassembled sources are W. Cirsovius's reverse-engineering of
DRI's binary ZSID.COM.  DRI's CP/M and tools are now under a permissive
licence (BSD-like, via the Lineo handover), so the original binary is
legally redistributable.  The reverse-engineered sources are
W. Cirsovius's work; treat as reference material and check his stated
licence at the original site before any redistribution.
