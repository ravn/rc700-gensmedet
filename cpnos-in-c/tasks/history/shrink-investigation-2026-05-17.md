# cpnos-in-c shrink investigation -- session 73j

Branch: `cpnos-shrink-investigation-73j` (off main at `4de8b70`).

User asked (post-dual-transport landing): "investigate in a new branch
if cpnos-in-c code can be made tighter.  For instance removing debug
code not needed anymore."  PROM1 budget had dropped from 99 B free to
30 B free after the dual-transport commit -- worth a look.

Plus parallel ask: get the SDCC autoload build working.

## Baseline (HEAD of main pre-investigation)

- autoload-in-c clang: 1661 / 2048 B  (387 B free, 2 KB hard cap)
- autoload-in-c sdcc:  broken build  ("copt: can't open patterns file")
- cpnos-in-c PROM1-only (clang × dual transport): 2018 / 2048 B
  (30 B free, 2 KB hard cap)

## Applied changes (landed on branch)

### autoload-in-c/Makefile  (commit `cb9bea5`)

1. SDCC `copt-rules` absolute container path: third `zcc` call does
   `cd sdcc && zcc ...` and the previous relative `sdcc/peephole.def`
   resolved to a non-existent `sdcc/sdcc/peephole.def`.  Replaced
   with the Docker mount-absolute `/src/sdcc/peephole.def`.
2. Per-compiler size policy: clang = 2 KB hard ERROR ceiling (matches
   user's physical hardware -- no A11 bridge); sdcc = 4 KB hard
   ceiling (MAME-only parity testing).

After: sdcc autoload at 2201 / 4096 B (1895 B free in MAME 4 KB).

### cpnos-in-c install_transport word-store  (commit `69c897b`)

Replaced 8 individual `xport_*_byte[N] = ...` byte stores with two
`*(volatile uint16_t*)&xport_*_byte[1] = ...` word stores.  clang -Oz
now emits Z80's native `LD (nn),HL` (3 B) instead of two `LD (nn),A`
(6 B).  install_transport: 35 B -> 18 B.

PROM1: 2018 -> 1999 / 2048 B (49 B free, +19 B headroom).

### cpnos-in-c dead `#if 0` cleanup  (same commit `69c897b`)

Removed two `#if 0`-gated `boot_probe()` callsites in
resident.c::impl_const.  The boot_probe / probe_once symbols were
deleted in #72; the call-site shells survived as commented-out
preprocessor dead code referencing undefined identifiers.  Zero
PROM impact (preprocessor strips them); source-hygiene only.

## Investigated but NOT applied

### BOOT_MARK_ENABLED=0 -- saves ~67 B

`hal.h` defines `BOOT_MARK(col, ch)` as a write to display memory at
`0xF800 + 60 + col`, gated by `-DBOOT_MARK_ENABLED=1` (default).  17
call sites in init.c + cpnos_main.c emit cold-boot progress markers
to display row 0 cols 60..78 ('I' for init, 'N' for netboot,
'P' for prom-disable, 'J' for jp-to-NDOS, etc.).

Build with `BOOT_MARK_ENABLED=0` -> PROM1 **1951 / 2048 B (97 B free)**.
That alone undoes the dual-transport cost and then some.

Trade-off: lose visual confirmation of cold-init progression.  Marks
are useful when something fails mid-boot ("last mark before crash" =
diagnostic).  On a successfully booting slave they're decoration.

**Recommendation:** leave default 1.  Document the flag as a known
shrink lever (this file) and as a Makefile knob already exposed
(line 49: `BOOT_MARK_ENABLED ?= 1`).

**User policy (2026-05-17):** keep `BOOT_MARK_ENABLED=1` while memory
pressure is OK; do NOT flip to 0 unilaterally.  Ask the user first
before disabling -- the markers have diagnostic value when something
fails mid-boot, and the 67 B savings should be spent intentionally
on a specific feature that needs them.

### Larger functions worth deeper review (if more shrink needed)

`llvm-nm --size-sort` on `payload.elf` top entries (after applied
shrinks):

| Symbol | Size | Notes |
|---|---|---|
| `_snios_rcvmsg_c`    | 345 B | SNIOS frame receiver -- protocol-heavy |
| `_pio_rx_buf`        | 256 B | constrained to 256 by page-aligned ISR |
| `_snios_sndmsg_force`| 196 B | SNIOS sender |
| `_cfgtbl`            | 210 B | CP/NET config table -- mostly zeros? |
| `_netboot_mpm`       | 169 B | cold-init only -- could compress separately? |
| `_scroll_lines`      | 113 B | console scroll |
| `_port_init`         | 110 B | hw bring-up |
| `_specc`             |  96 B | special-char dispatch -- jump-table candidate |
| `_isr_crt`           |  95 B | hot, do not touch |
| `_impl_conout`       |  94 B | hot path |

Candidates ordered by risk:tractability:
- **`_cfgtbl`** (210 B data): inspect whether most fields are zero
  at link time -- if so, runtime-init the few non-zero ones, save
  most of the data block.  Cost: ~20-40 B of init code, saving
  ~150-180 B of data.  Need to confirm what fields CP/NET protocol
  requires non-zero at boot.
- **`_specc`** (96 B): probably a switch on the control character
  set (0x14/0x15/0x16 graphics codes + 18 text-mode CONOUT codes).
  A small dispatch table could shrink.
- **`_scroll_lines`** (113 B): straight memmove-style code.  Probably
  near-optimal already.

Not investigated:
- Banner string (54 B) -- minimum useful length
- IVT/ISR layout

### SDCC support for ZX0 compression

Asked separately by user.  z88dk ships ZX0 tooling so the host-side
compression step works regardless of compiler; the missing piece is a
SDCC equivalent of clang's two-pass link recipe (extract `.text`,
compress with `z88dk-zx0`, re-link against a `.s` containing the
compressed bytes + a `dzx0_standard.asm` decoder).  Not currently
needed -- SDCC autoload runs in MAME with the 4 KB ceiling.  Becomes
load-bearing only if: (a) byte-for-byte parity testing of the
compressed image, or (b) a SDCC variant of cpnos PROM1-only at the
2 KB ceiling.  Filed as future follow-up #18 (see timeline.md).

## Net result of branch

| Build              | Before  | After   | Delta |
|--------------------|---------|---------|-------|
| autoload clang     | 1661 B  | 1661 B  | 0 (no change) |
| autoload sdcc      | broken  | 2201 B  | unblocked |
| cpnos PROM1 clang  | 2018 B  | 1999 B  | -19 B |

PROM1 free space: 30 B -> 49 B.

If user accepts the BOOT_MARK_ENABLED=0 trade (lose visual cold-init
diagnostic markers), additional 67 B savings available, taking PROM1
to 1932 B (116 B free) -- below the original pre-dual-transport
1949 B baseline.  Not applied; recommendation to keep default.

## Recommended merge

The two applied commits (`cb9bea5` + `69c897b`) are low-risk and
already smoke-tested.  Suggest fast-forward merge to main with
`--no-ff` per the project policy.
