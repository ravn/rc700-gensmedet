# RC759 GSX-86 driver — initial RE findings (session 1, 2026-10-31)

## Repository housekeeping (2026-11-01)

### Final emulator validation (2026-11-01)

The workspace emulator is now at `a669fe9`, whose complete tracked tree
matches upstream `johnsonjh/emu2-cpm86` `c49b535`. The local S1 handling
change was removed; history was preserved. A separately compiled clean
upstream emulator first rebuilt H1 with zero errors and an 8576-byte CMD
identical to the original. After rebuilding the workspace emulator,
`make verify` freshly reproduced all twelve complete originals (12/12 PASS).
Local evidence: `scratch/unified-check-20261101-151824-993069/matrix.json`.

This establishes that the local S1 change is unnecessary for the current
driver sources. It does not isolate the cause of earlier failures or prove
all other CP/M programs work. The earlier 1678-byte OBJ was incomplete,
not a valid reference build. PTY/EOF handling was also a separate issue.

The CP/M-86 System Guide (June 1983, section 4.3, printed page 31)
describes S1 (FCB byte 13) as reserved for internal system use, not a
file-position counter. Concurrent CP/M's Programmer's Reference Guide
(January 1984, section 2.4, pages 2-11 and 2-13) calls the same byte CS:
the open-FCB checksum. Neither supports the former local comment that
RASM86 needs S1 preserved as a position counter or must initialize it
to zero at open. No isolated observation established those claims.
Both manuals are available locally in `open-watcom-v2/contrib/ravn/`.

Emulator relocation, CPU-level and timer checks passed. The separate
ASM86 input-size regression skipped because its expected `asm86.cmd`
was absent; it is not the RASM86/LINK86 full-image test above.
Driver integration checks remain local, not CI-gated. Runtime validation
of color/mouse/serial behavior and source/device provenance remain outside
the completed byte-reconstruction scope.

Sources, original binaries, build/comparison tools, Makefile and analysis
are tracked. `make` freshly builds all twelve variants and compares each
complete image with `originals/`; mismatches fail the command.

Old guest build directories, temporary assembler probes, logs, disposable
MAME disks/screenshots and the superseded MAME assembler scripts were
removed. Historical scratch paths in the notes below describe runs at
the time of investigation, not permanent evidence files. The reproducible
checks and recorded results remain; generate new evidence with
`make verify`.

Local reference collections in `scratch/gsx80_86`,
`scratch/dri-skeleton-search` and `scratch/seasip-sources` are retained,
not deleted or uploaded. They include user-supplied historical sources
and downloaded material beyond the already tracked reference subset;
redistribution rights are not established. The RASM-86 manual likewise
remains local; its title/archive reference is in `docs/README.md`.
Ignored scratch, NVRAM and host-specific capture configuration are not
required to rebuild the drivers.

## Unified-source experiment — verified 2026-11-01

Initially implemented on `rc759-gsx-unified-source` in both the workspace
and `rc700-gensmedet` repositories; subsequently committed, merged to
main and pushed. The experiment and default-build branches were removed.
This section supersedes the reconstruction status in the earlier inventory:
**all twelve originals now rebuild byte-for-byte from shared assembly.**

`src/dd759.a86` contains shared instructions, labels and explicit tables,
with RASM-86 `IF`/`ELSE` choices for `MEDIUM_RES`, `MOUSE_INPUT` and
`SERIAL_INPUT`. The color path has two pixel truth-table operations,
two-bit mask stepping, four-color palette handling and medium-resolution
geometry. The optional locator paths contain the XIOS mouse calls or the
serial QL transaction, decimal parsing, scaling and CODE-resident state.
No executable binary embedding, binary patching or original-image reads
are used by the builder. The original SYS files are read only by verification.

`src/dd759h1.a86` remains the H1 configuration entry. The build tool
generates the other wrappers and selects stored EXTRA padding plus the
LINK-86 additional allocation (`200h` or `800h` paragraphs, 8KB or 32KB).
CODE padding is respectively 10/2/14/14/4/0 bytes for H/HD/HM/M/MD/MM;
these values and the glyph terminator's final DATA alignment are now
calculated from segment offsets, not supplied by the build wrapper.
RASM-86 1.2 rejects nested INCLUDE, so staging inlines the common
body into the wrapper before assembly, leaving all actual variant IFs
and the sine/glyph INCLUDEs to the assembler.

From `rc759-gsx/`:

```sh
sh tools/build.sh                    # All twelve, with comparison.
sh tools/build.sh h1                 # Retained H1 route.
sh tools/build.sh mm4                # One selected variant.
python3 tools/verify_variants.py      # Fresh builds of all twelve.
python3 tools/verify_variants.py h1 h4 hm1 hm4
python3 tools/verify_variants.py --baseline h1 h4 # Negative control: exits 1.
```

Each build uses a new `scratch/emu2-current-*` directory containing
staged sources, OBJ/CMD output, assembler/linker logs and `build.json`
with tool/source SHA-256 hashes and actual guest command lines.
The verifier creates a `scratch/unified-check-*` directory with
per-variant comparison logs and `matrix.json`, returns nonzero on any
failure, and checks that all twelve original oracle files remain unchanged.
These are local integration tests, not currently wired into CI.

| Family | One-console file | Four-console file | Full-image result |
|---|---:|---:|---|
| H | 8576 bytes | 7936 bytes | H1 PASS; H4 PASS |
| HD | 8576 bytes | 7936 bytes | HD1 PASS; HD4 PASS |
| HM | 8576 bytes | 7936 bytes | HM1 PASS; HM4 PASS |
| M | 8576 bytes | 7936 bytes | M1 PASS; M4 PASS |
| MD | 8576 bytes | 7936 bytes | MD1 PASS; MD4 PASS |
| MM | 8576 bytes | 7936 bytes | MM1 PASS; MM4 PASS |

Fresh baseline before variant implementation:
`scratch/emu2-current-20261101-091211/matrix.json` reports H1 PASS and
the other eleven targets FAIL against the same fresh H1 build.
Final all-variant evidence:
`scratch/unified-check-20261101-091928-653160/matrix.json`.
Every header, CODE, DATA, stored EXTRA and relocation/alignment trailer
matches independently preserved `originals/dd759*.sys`, including MD4's
zero-length stored EXTRA. A separate fresh build through the retained H1
launcher also matches; regenerating the glyph SVG produces the identical
existing `docs/glyphs.svg`. The negative-control H1/H4 comparison correctly
fails H4 and exits 1; an invalid variant selector exits 2.

**Scope limit:** no new runtime, MAME, optical-mouse or serial-device
hardware validation was performed. Byte equality establishes that these
builds reproduce the original programs, not that the original programs
are bug-free. The serial device model and literal suffix interpretation
remain unverified; the experiment does not resolve source-language provenance.

### Assembler-derived structure sizes — follow-up 2026-11-01

The following values are now calculated from start/end labels rather
than independently hardcoded:

- Dispatch maxima: primary table 34, ESCAPE table 19 and GDP table 7.
- DEV_TAB copy/returned word count 45; SIZ_TAB copy count 12 and returned
  coordinate-pair count 6.
- Input-mode array initialization count 5 and maximum array index 4.
- Line-style bounds/capability count 7; marker maximum index 5 from its
  glyph-table prefix; text maximum character index 127 from the complete
  glyph-pointer table.
- Drawing-color count 2/4 from the color-control table, default last color
  1/3, active pixel-LUT pointer count 1/2, RGB record stride 6 and component
  word count 3. The palette-default copy already used a label difference.
- Fill-tile record size 8, hatch/pattern counts 6, and the offset selecting
  the pattern family after the hatch family.
- Identification count 42/46 and all stored console-sequence counts 2/4.
  The original identification header counts text bytes as output words;
  the derived expression deliberately preserves that over-copy, rather
  than silently fixing the original program.
- Serial packet length 12 and decimal-field read count 4. Named field
  labels replace the Y/status offsets; the field allocations still
  explicitly describe the device's fixed four-digit wire format.
- CODE and DATA paragraph padding, segment lengths and stored EXTRA.
  `build_emu2_current.py` no longer has the six-family hardcoded length/
  padding table. The assembler subtracts its actual aligned CODE/DATA
  lengths from the selected historical stored-group budget.

RASM-86 1.2 accepted forward label-difference instruction operands in a
fresh H1 trial. EQU definitions involving table lengths must appear
**after** the referenced labels; instructions can forward-reference those
EQU symbols. Alignment arithmetic needs scalar `offset end-offset start`
values before MOD, not typed label arithmetic. All these rules were
checked with the real assembler, not inferred from modern assembler syntax.

Constants retained intentionally: GSX parameter-block layout/function
numbers and mode IDs; XIOS/BDOS call numbers and its 16-byte palette-buffer
layout; 560/280/256 display geometry and 32KB graphics memory; fixed-point
shifts, trigonometric samples and numeric scaling; wire field widths/
delimiters; original unidentified reserved DATA areas. The 8288/7664
stored-group budgets and 8KB/32KB additional allocations describe the
original CMD disk/runtime layout, not independently duplicated sizes of
source data structures. Chosen default marker IDs remain 5/3; they are
defaults, not both table-size limits.

Fresh pre-edit matrix:
`scratch/unified-check-20261101-092352-845821/matrix.json` (12/12 PASS).
Fresh post-edit matrix:
`scratch/unified-check-20261101-092739-742727/matrix.json` (12/12 PASS).
All twelve rebuild SHA-256 hashes match the pre-edit baseline, and all
original hashes remain unchanged. The retained H1 launcher passes a
separate fresh comparison; regenerating the glyph SVG remains identical.
No commits, pushes or new runtime/hardware tests.

## Verified inventory of all 12 RC759 variants (2026-11-01)

The sections below this inventory are historical first-session notes.
Their flat-file/header interpretation and proposed `1/4 = plane count`
are obsolete. These SYS files have CP/M-86 CMD group descriptors;
CODE and DATA are separate address spaces. The rebuilt H1 and the
later notes supersede those early hypotheses.

Scope: all twelve original files in `originals/`, parsed with
`tools/compare_sys_cmd.py:parse_groups`, pairwise byte comparisons,
aligned CODE comparisons and bounded Capstone disassembly. No variant
other than H1 was executed or reconstructed in this investigation.

| Family (both 1/4 files) | Screen | Drawing colors | Locator | CODE bytes | DATA bytes | EXTRA bytes, 1 / 4 |
|---|---|---:|---|---:|---:|---:|
| dd759h | 560x256 | 2 | Keyboard | 4160 | 3136 | 992 / 368 |
| dd759hd | 560x256 | 2 | Keyboard + serial absolute-coordinate device | 4448 | 3136 | 704 / 80 |
| dd759hm | 560x256 | 2 | Keyboard + XIOS optical mouse | 4192 | 3136 | 960 / 336 |
| dd759m | 280x256 | 4 | Keyboard | 4208 | 3168 | 912 / 288 |
| dd759md | 280x256 | 4 | Keyboard + serial absolute-coordinate device | 4496 | 3168 | 624 / 0 |
| dd759mm | 280x256 | 4 | Keyboard + XIOS optical mouse | 4224 | 3168 | 896 / 272 |

Each `1` file is 8576 bytes; each `4` file is 7936 bytes. Within
each family, CODE and DATA are byte-identical between 1 and 4.
EXTRA contains only zeros; the non-padding relocation records also
match (the trailer's leading alignment padding differs). Thus there
are six executable variants, not twelve distinct rendering engines.
File size alone is misleading: the more substantial CODE replaces
zero padding, and the smaller files reserve more runtime memory.

### 1 and 4: console save-buffer allocation, not pixel planes

For every pair, header differences are confined to offsets
13h, 17h, 18h and 7Dh. The EXTRA descriptor's minimum allocation
minus its stored length is exactly 8192 bytes for `1` and 32768
bytes for `4`. For H1: 9184 - 992 = 8192; H4: 33136 - 368 = 32768.
The same relation holds even for MD4's zero-length stored EXTRA.
Offset 7Dh is the relocation-record position in 128-byte units:
42h for `1`, 3Dh for `4`.

PICCOLINE Programmer's Guide section 4.5, printed pages 55-56
(`docs/PICCOLINE_Programmers_Guide_v2.txt:2159-2237`, relative to
the parent project), independently specifies 8KB for a one-console
system and 32KB when graphics must survive foreground/background
console swapping. This establishes the allocation distinction.
The filenames fit one/four-console installations; no original
GCONFIG filename-selection table was found to independently confirm
the literal `4` naming convention.

### H versus M: high-resolution monochrome versus medium-resolution color

All H families advertise maximum X/Y 559/255 and two drawing colors;
all M families advertise 279/255 and four drawing colors. Capability
tables begin at DATA:04B2h and DATA:04D4h respectively. All advertise
the same 232-character count; the embedded identification says
`1.1 RC750 B/W11/13/84` or `1.1 RC750 COLOR11/13/84`, despite
the RC759 filenames. This is not proof of the binary's distribution
history or original source language.

H1 initialization at CODE:1018h selects XIOS graphics mode AH=1;
M1 at CODE:1044h selects AH=2. The manual identifies these as
high and medium resolution. M1's address routine at CODE:048Bh
first doubles X, then uses the same strip-address arithmetic as H1.
Its pixel kernel at CODE:0450h applies two lookup tables to adjacent
bits, rotating the mask between them and restoring it afterward.
`load_pixel_lut` at CODE:04B5h accepts colors 0..3 and prepares two
tables. This is two bits per pixel, not four bitplanes.
Two-bit drawing values and the programmable display palette are
different concepts; the four-color count does not imply only four
physical palette entries.

### Extra M: mouse input without a new drawing engine

HM1/MM1 have an added helper at CODE:02DAh:
`PUSH ES; MOV AL,30; INT 28h; POP ES; RET`.
OPEN calls it with CL=1. The locator calls it with CL=3, then adds
the returned relative coordinates to the current locator position;
MM also halves the horizontal movement for medium resolution.
If no event is returned, it falls back to the keyboard locator.
PICCOLINE section 4.8, printed page 65
(`PICCOLINE_Programmers_Guide_v2.txt:2562-2588`), identifies exactly
this API as the optical mouse. Both advertise two locator devices,
versus one in H/M. HM1's CODE:0340h..04C9h is byte-identical to
H1's CODE:0336h..04BFh: the added mouse support is not a faster
line/pixel renderer.

### D: serial absolute-coordinate locator; exact device unverified

HD1 adds a 288-byte block before H1's locator-clamping routine;
MD1 adds the corresponding color variant. HD1 CODE:0E10h contains
`COMPORT:` followed by byte 04h. The input code selects a logical
console through BDOS function 148, sends ASCII `Q` then `L`, polls
direct-console input, receives a twelve-byte CR-terminated response,
and parses two four-digit decimal coordinate fields. It subtracts
100, clamps negative values to zero, then scales using 256/1850
and 560/2750. MD subsequently halves X. Status bytes determine
movement versus button/key events, with old coordinates retained
to detect change. A no-event result falls back to keyboard input.

HD1's line/pixel/address block CODE:0337h..04BFh is byte-identical
to H1. Its capability table advertises two locator devices.
This verifies a serial absolute-coordinate input extension.
`D = digitizer` is a plausible interpretation, but neither the
device model nor the protocol name nor that suffix expansion has
been established from an independent manual. Do not label it a
specific tablet without further evidence.

### Consequences for further work

For rendering/performance analysis, M1 is the next genuinely different
case: two-bit pixels, two truth-table operations and half-width
geometry. HD/HM are principally input extensions and share large
byte-identical rendering regions with H. The variants still do not
settle assembler versus Ratfor provenance: related binary layouts
are evidence of a common implementation family, not its source language.
The old `1 = mono, 4 = color` interpretation must not be reused.

### Rough code-sharing estimate (2026-11-01)

CODE-only comparisons use Python SequenceMatcher with autojunk disabled
to align insertions, rather than comparing the same offsets after an
inserted routine. The conservative column sums exact matching runs of
at least 16 bytes and divides by the shorter CODE length. The other
column is SequenceMatcher's symmetric ratio, including short matches.
Neither is an instruction-aware source similarity metric; short byte
matches can be coincidental, while changed absolute addresses and
relative calls can make shared algorithms look different.

| Pair | Exact aligned runs >=16 bytes / shorter CODE | All-match symmetric ratio | CODE length difference |
|---|---:|---:|---:|
| H1 / H4 (all 1/4 pairs are identical) | 100% | 100% | 0 |
| H1 / HD1 | 97.6% | 95.2% | +288 bytes |
| H1 / HM1 | 97.7% | 98.7% | +32 bytes |
| M1 / MD1 | 97.6% | 95.2% | +288 bytes |
| M1 / MM1 | 97.4% | 98.5% | +16 bytes |
| H1 / M1 | 67.8% | 91.3% | +48 bytes |
| HD1 / MD1 | 67.5% | 91.4% | +48 bytes |
| HM1 / MM1 | 67.2% | 91.0% | +32 bytes |

The input variants retain about 97-98% of the smaller driver's CODE
in long identical runs; the serial extension itself adds substantial
new code. Across H/M, about two thirds survives in long exact runs;
the earlier disassembly shows shared rendering/transform structure
with changed pixel handling, coordinates, tables and shifted addresses.
As an engineering estimate, roughly 85-95% common source logic is
plausible for a unified implementation, not a measured source-line ratio.

One assembly source with conditional assembly is therefore a reasonable
reconstruction design: high/medium resolution, keyboard/mouse/serial
locator selection, and 8KB/32KB save-buffer allocation are separate
build choices. Keep common glyph, transform, fill and dispatcher logic;
select variant pixel primitives, tables, locator hooks and allocation
descriptors at assembly time. This need not add runtime branches.
The original programs may already have been built that way, but binary
similarity does not establish their original source organization.

Producing all twelve original files byte-for-byte from that source is
plausible but unproven. It requires checking every variant-specific
instruction, table, padding rule and relocation record, not merely
matching behavior or these similarity percentages.

## Målsætning
Reverse-engineere `dd759h1.sys` (og de 11 varianter) til kommenteret
disassembly så vi kan vurdere om vi vil skrive en forbedret driver.

## Filer og organisation

- `originals/dd759*.sys` — 12 drivervarianter (`h/hd/hm/m/md/mm` × `1/4`).
  Historisk, afkræftet hypotese: "1" = 1 plan (mono), "4" = 4 planer (farve). Suffikser var antaget
  medie-/skærmvarianter — skal bekræftes mod GKONFIG eller rc759-manual.
- `docs/` — GSX-86 manualer fra bitsavers.
- `disasm/disasm.py` — Capstone-baseret 8086 linear-sweep disassembler.
- `disasm/dd759h1.a86` — rå disassembly (3666 linjer).

## Filformat

8576 bytes flad binær. Struktur:

| Offset | Størrelse | Indhold |
|--------|-----------|---------|
| 0x0000 | 0x80      | GSX parameter-tabel (DEVID + default workstation state) |
| 0x0080 | ~0x80     | GIOS entry-dispatcher |
| 0x0100 | variabel  | Jump-tabel over GIOS-funktioner |
| ~0x146 | ...       | Funktionsimplementationer + data |

### Header-felter (0x00–0x1F som 16-bit LE words)

| Offset | Værdi    | Formodet betydning                        |
|-------:|---------:|-------------------------------------------|
| 0x00   | 0x0401   | DEVID (muligvis workstation ID 1025 el. 1,4) |
| 0x02   | 0x0001   | ?                                         |
| 0x04   | 0x0400   | ?                                         |
| 0x06   | 0x0001   | antal planer? (1 for `h1`-varianten)      |
| 0x08   | 0x0200   | ?                                         |
| 0x0A   | 0x00C4   | 196 — ?                                   |
| 0x0E   | 0x00C4   | 196 — gentaget                            |
| 0x10   | 0x1000   | BSS/stack-størrelse?                      |
| 0x12   | 0x3E03   | formodet segmentreference                 |
| 0x16   | 0x3E00   | formodet segmentreference                 |
| 0x18   | 0x0002   | ?                                         |

Enkeltbytes: `0x7D=0x42`, `0x7F=0x80` — betydning uafklaret.

Felterne skal krydstjekkes mod GSX manual (vi har PDF nu) og mod andre
`dd*.sys` drivere i mappen (`dd604*.sys` = Partner CRT osv.) for at se
hvilke felter varierer.

## GIOS entry-dispatcher (0x80–0xCD)

Rå flow:

```asm
0080:  mov ax, sp              ; gem callers SS:SP
0082:  mov bx, ss
0084:  mov cx, 0
0087:  mov ss, cx              ; SS = 0 (CP/M-86 relokeres? eller fast 0)
0089:  mov sp, 0x791           ; drivers egen stak
008c:  push bx                 ; (SS, SP) på egen stak
008d:  push ax
008e:  push ds                 ; gem callers DS
008f:  mov si, dx              ; DX = pointer til parameter-blok
0091:  add si, 0x12
0094:  mov cx, 10
0097:  std
0098:  lodsw                   ; kopier 10 words (intin[0..9]) på stakken
0099:  push ax                 ; (nedad fra [DX+0x12])
009a:  loop 0x98
009c:  push bp
009d:  mov bp, sp
009f:  mov ax, 0               ; <-- CP/M-86 relokering: patches til driver-segment
00a2:  mov ds, ax              ; DS = driver-data-segment
00a4:  cld
00a5:  les di, [bp+2]          ; ES:DI = GSX contrl[]-array (far ptr)
00a8:  mov [es:di+4], 0        ; contrl[2] = nptsout = 0
00ae:  mov [es:di+8], 0        ; contrl[4] = nintout = 0
00b4:  mov bx, [es:di]         ; BX = contrl[0] = GIOS opcode
00b7:  cmp bx, 0x22            ; range-check (0..34)
00ba:  ja 0xc2                 ; out-of-range -> fall through til exit
00bc:  shl bx, 1
00be:  call [bx + 0x100]       ; dispatch via tabel i driverens eget segment
00c2:  pop bp
00c3:  add sp, 0x14            ; drop de 10 intin-words
00c6:  pop ds
00c7:  pop ax
00c8:  pop bx
00c9:  mov ss, bx              ; genskab callers stak
00cb:  mov sp, ax
00cd:  retf                    ; far return
```

Observationer:

1. **CP/M-86 relokering på `MOV AX, 0` ved 0x9F**: imm16 bliver patchet af
   loader til driverens dataseg. Så `[0x100]` i dispatcher-kaldet læser
   fra driverens eget segment, offset 0x100 — dvs. jump-tabellen i filen.
2. **`contrl` layout** (standard GSX): word[0]=opcode, word[1]=n_ptsin,
   word[2]=n_ptsout, word[3]=n_intin, word[4]=n_intout, word[5]=funct_id,
   word[6..]=device-handle. Driveren nulstiller nptsout/nintout op front,
   så enhver handler kan sætte dem hvis den har output.
3. **`intin`-parametre kopieres på stakken** (10 words = 20 bytes) via
   `STD; LODSW; PUSH; LOOP` — klassisk GSX ABI.
4. **Range-check 0x22 = 34**: GSX GIOS har standardfunktioner 1..11 og
   udvidelsesopcodes (set-attributes-subfunctions) der mapper til højere
   interne numre. En range på 35 passer med dette.

## Jump-tabel ved 0x100 (34 slots)

| op | mål     | kommentar                                   |
|---:|--------:|---------------------------------------------|
|  0 | 0x0e89  | handler                                     |
|  1 | 0x03e4  | lille stub (nær "return feature off")       |
|  2 | 0x1689  | handler (deler kode med op 4)               |
|  3 | 0x03e0  | lille stub                                  |
|  4 | 0x1689  | handler (= op 2)                            |
|  5 | 0x03e6  | lille stub                                  |
|  6 | 0x08b8  | handler                                     |
| 7+ | *       | pegerværdier ser ud som kode-bytes (0xd100, 0xd1e0, 0xa3e0…) — tabellen stopper reelt her, selvom dispatcheren accepterer op til 0x22 |

**Mulige hypoteser for "op 7+":**

A. Dispatcher-rangecheck er bare generøs; GSX kalder aldrig med op > 6
   på denne devicetype (fx hvis det er en printer/plotter mode uden tekst).
B. Jeg misforstår dispatcher-opsætningen og tabellen ligger et andet sted;
   `BX+0x100` kunne være i et andet segment end jeg antager.
C. Driveren leverer færre funktioner end andre GSX-devices og "op 7+"-
   slottene er bare uinitialiseret padding genbrugt som kode.

Dette skal afklares med:
- Opslag i GSX programmer manual: hvilke opcodes er obligatoriske for
  en skærmdriver vs. en printer.
- Sammenligning med `dd604h.sys` (Partner skærm) som har kendt opførsel.
- Dynamisk tracing i MAME/emulator.

## Næste skridt (foreslået prioritering)

1. **Læs GSX programmer manual** (`docs/5000-2024_…pdf`) kapitel om
   GIOS interface + funktionsnumre + parameter-formater.
2. **Diff header 0x00–0x7F** på tværs af alle 12 varianter — se hvad der
   adskiller `h` fra `m` fra `hd` osv.
3. **Annoter dispatcher + handlers for ops 0–6** med manuel symbol-navne.
4. **Identificer rc759 I/O-porte** i handler-koden (OUT instruktioner til
   grafikkontrolleren) — det er dét vi faktisk ønsker at forstå.
5. **Byg en symbol-fil** (`dd759h1.sym`) som disasm-scriptet kan læse
   til at påføre navne i output.

Først når ovenstående er på plads, kan vi beslutte om vi vil (a) kommentere
den eksisterende binær færdig, eller (b) reimplementere i asm86 fra bunden.
