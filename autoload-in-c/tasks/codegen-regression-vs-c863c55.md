# Codegen regression analysis: current vs c863c55 (2026-10-09)

Side-by-side comparison of the autoload-in-c PROM listing produced by
c863c55-era llvm-z80 (pre-`ef0d16713601` "Model the accumulator as a
register class", baseline from `git show c863c55:autoload-in-c/clang/prom.clang.lis`)
and today's compiler on today's source.

**Current:** 2142 B PROM | **c863c55:** 2034 B PROM | gap: 108 B
(≈168 B intentional feature growth minus ≈60 B compiler improvements).

## Function-level size changes (|Δ| ≥ 3 B)

```
Function                                     Δ   base  curr   diagnosis
---------------------------------------------------------------------------
_floppy_completed_operation_interrupt      +20    29    49   split-out body (net −10 vs refresh_crt_dma_50hz_body)
_fdc_read_data_from_current_location       +17   130   147   see §4
_sem702_font                               +16  1401  1417   DATA — ROA327 font tweaks, not codegen
_fdc_read_result                           +11    37    48   see §3
_fdc_select_drive_cylinder_head            +10    37    47   see §1
_lookup_sectors_and_gap3_for_current_track  +9    49    58   not yet analysed
_floppy_legacy_boot                         +9    39    48   not yet analysed
_prom1_if_present                           +6    39    45
_boot_floppy_or_prom                        +6   122   128
_calc_size_of_current_track                 +5    43    48
_fdc_get_result_bytes                       +3    92    95
_check_fdc_result                           +3    38    41   see §2 — DEC (HL) fold lost
_fdc_detect_sector_size_and_density         −5    60    55
_start                                      −7    31    24
_main_relocated                           −294   484   190   split-out helpers (new funcs account for +250 B)
```

New functions in current (+388 B, mostly intentional features):
- `boot_from_floppy_or_jump_prom1` (131), `memcpy` (127), `display_banner_and_start_crt` (64),
  `display_sw1_status` (45), `draw_qr` (43), `refresh_crt_dma_50hz_body` (38),
  `load_chargen_font` (34), `memset` (26), builtin stubs (21)

---

## §1 — `fdc_select_drive_cylinder_head` (+10 B, lost OR (HL))

**Pattern (fdc_cmd.head << 2) | drive_select:**

```
baseline (c863c55):                     current:
3A 43 6D   ld a,(fdc_cmd.head)         3A F9 6D   ld a,(fdc_cmd.head)
87         add a,a                     87         add a,a
87         add a,a                     87         add a,a
21 57 6D   ld hl,drive_select          47         ld b,a           ; save
B6         or (hl)        ← 1-byte     3A F5 6D   ld a,(drive_select)
F5         push af        ← save       4F         ld c,a           ; shuffle
                                       78         ld a,b           ; shuffle
                                       B1         or c
                                       32 19 6E   ld (frame+1),a   ; static frame spill
= 8 B                                   = 14 B — regression 6 B
```

**Root cause:** `OR (HL)` not generated (issue
[ravn/llvm-z80#402](https://github.com/ravn/llvm-z80/issues/402)).
Compounded by the `push af` → static-frame-spill shift: baseline keeps
the computed byte on the stack across the following `fdc_write_when_ready`
call; current spills to a BSS frame slot (3 B store + 3 B reload each).

**Fix: #402 lands → recovers ~6 B here, more at similar sites.**

---

## §2 — `check_fdc_result` (+3 B, lost DEC (HL))

```
baseline:                                current:
21 58 6D   ld hl,retry_count            3A 04 6E   ld a,(retry_count)
35         dec (hl)       ← 1 byte      3D         dec a
                                        32 04 6E   ld (retry_count),a
= 4 B                                    = 7 B — regression 3 B
```

**Root cause:** `INC (HL)` / `DEC (HL)` memory-direct form (opcodes 0x34 / 0x35)
not generated. Analogous to CP (HL) / OR (HL): fold a single-use
G_LOAD + G_ADD(C,1) / G_SUB(C,1) + G_STORE into one 1-byte memory op
with GR16_HL constraint.

**New issue to file.** Estimated 3-15 B across autoload — many increment
counters.

---

## §3 — `fdc_read_result` (+11 B, callee-save vs static-frame regression)

```
baseline:                                current:
11 00 00   ld de,$0        ; i=0 in E   16 00      ld d,$0        ; i=0 in D
                                        ...
D5         push de         ; save i     7A         ld a,d
CD .. ..   call fdc_read                32 10 6E   ld (frame),a   ; static frame
D1         pop de          ; restore    CD .. ..   call fdc_read
21 4D 6D   ld hl,fdc_result             21 10 6E   ld hl,frame
19         add hl,de       ; p[i]=      56         ld d,(hl)      ; reload
77         ld (hl),a                    4A         ld c,d
                                        06 00      ld b,$0        ; zero-ext
                                        21 ED 6D   ld hl,fdc_result
                                        09         add hl,bc
                                        77         ld (hl),a
= 7 B save/call/index                   = 15 B — regression 8 B
```

Two separate regressions:
- **(3a) push DE / pop DE across call** replaced by static-frame
  save+reload. Baseline treats DE as callee-saved by pushing; current
  spills to BSS. The push/pop costs 2 B total; the spill costs 6 B.
  **Estimated 10-30 B across autoload if restored.**
- **(3b) Zero-extend of a byte index to BC** before `add hl,bc`. Baseline
  held `i` in E directly and used `add hl,de`. Current goes through
  `ld c,d; ld b,0; add hl,bc`. **Estimated 5-10 B across loop bodies.**

**Fix: codegen choice.** The old selector left byte counters in a GR8
register that aliased GR16's low half (e.g., E of DE, L of HL) and chose
`add hl,de`/`add hl,bc` based on which one was already live. New selector
reaches for a full GR16, which forces a zero-extend.

Related to [ravn/llvm-z80#38](...) IX cost model — same class of issue
(RA cost tier doesn't see the zero-extend+spill overhead when choosing
GR16 over an existing GR8).

---

## §4 — `fdc_read_data_from_current_location` (+17 B)

Signed `> 0` branch on a 16-bit value regressed from 9 B to 12 B.

```
baseline:                                current:
7c         ld a,h       ; sbc hl,bc res  7c         ld a,h
07         rlca         ; sign→carry     EE 80      xor $80       ; flip sign bit (bias)
9F         sbc a,a                       67         ld h,a
2F         cpl                           16 01      ld d,$1
47         ld b,a                        7D         ld a,l
7C         ld a,h                        D6 01      sub $1
B5         or l         ; nonzero        7C         ld a,h
A0         and b        ; AND positive   DE 80      sbc a,$80
20 ..      jr nz,...                     30 ..      jr nc,...
= 9 B                                    = 12 B — regression 3 B
```

Baseline uses the "shift sign bit to carry → SBC A,A → CPL → mask" trick
to materialize `>0` in flags cheaply.  Current uses an unsigned-bias
subtraction (`XOR 0x80` on the high byte → unsigned CMP against 1).

Both are correct; baseline is 3 B shorter per site.  Autoload has ≥2
such sites.

**Fix:** add peephole or legalizer canonicalization for `signed_v > 0`
specifically (contrast with `signed_v >= 0` which already uses the
cheaper sign-bit test).  Also contains OR-after-load patterns (§1) and
byte-index-into-pair patterns (§3b).  Likely 5-10 B more recoverable
once #402 lands.

---

## Summary — path back to ≤2048 B

| Issue | Estimated recovery | Status |
|---|---|---|
| ravn/llvm-z80#402: `op (HL)` folds (OR/AND/XOR/ADD/SUB) | 10-20 B | filed |
| NEW: `INC (HL)` / `DEC (HL)` fold | 3-15 B | to file |
| NEW: Prefer push/pop callee-save over static-frame for byte counters across single call | 10-30 B | to file |
| NEW: Keep byte counter in GR8-alias-of-GR16 for `add hl,xy` instead of zero-extending | 5-10 B | to file |
| NEW: `signed_v > 0` branch: use sign-bit trick (RLCA/SBC/CPL/AND) instead of XOR-bias | 3-10 B | to file |
| **Total compiler potential** | **31-85 B** | |
| Source-level: feature gates (SW1 line, QR) | 50-100 B | plan item B.5 |

Compiler recovery alone could close the 94 B gap. Three new ravn/llvm-z80
issues are warranted.

## How this report was generated

Baseline listing: `git -C .. show c863c55:autoload-in-c/clang/prom.clang.lis`.
Current listing: `clang/prom.clang.lis` as of commit 110400b.
The original analysis references `scratch/compare.py` for its function-size
diff, but that script is not present in the current `autoload-in-c/scratch/`
directory; the original function table was not regenerated during this test.

## Controlled pre-PR-40 backend comparison (2026-10-09)

To test whether the compiler before PR #40 reduced the current source's PROM
size, the current feature-neutral C IR was fed to both the current backend and
the pre-PR-40 backend. This isolates backend code generation; it does not use
the historical Clang frontend.

The original analysis records a 2142 B current PROM; this fresh production
build measured 2141 B. The one-byte discrepancy is left visible rather than
rewriting the earlier snapshot.

| Build | Compiler/backend revision | PROM | Raw `.text` | ZX0 payload |
|---|---|---:|---:|---:|
| Current production | `d6658ad` | 2141 B | 3565 B | 2022 B |
| Current, feature-neutral | `d6658ad` | 2190 B | 3758 B | 2071 B |
| Pre-PR-40 backend, feature-neutral | `1991786426b42cb678bcd2c38daf10bd853d0f25` | 2461 B | 4165 B | 2342 B |

All three final `.bin` files exceed the 2048 B production cap: by 93 B,
142 B, and 413 B, respectively.

The historical backend is 271 B larger in both the compressed payload and
final PROM than the comparable current feature-neutral build (+13.1% payload),
and emits 407 B more raw `.text` (+10.8%). The current production build is
shown separately because it enables features unavailable to the historical
revision; its result is not an apples-to-apples row.

Both comparison copies used the same current source and current-Clang-generated
feature-neutral IR. `+shadow-isr` was removed and `__no_recurse` made empty in
both copies because the historical backend lacks those features. Both backends
used `+static-frame` and `--disable-lsr` for code generation. The old `llc` was
invoked as:

```
llc -mtriple=z80 -filetype=obj -O2 --disable-lsr \
  --function-sections --data-sections <shared-current-IR> -o <object>
```

The current `llc` objects reproduced the current driver build byte-for-byte.
The non-C support objects were also byte-identical between links; both PROMs
used the current linker, objcopy, and ZX0 1.5. Both decompression roundtrips
matched the raw `.text` exactly.

Among 49 common text symbols, 20 were larger with the pre-PR-40 backend, 29
were unchanged, and none were smaller. The largest increases were
`_fdc_read_data_from_current_location` (+80 B),
`_lookup_sectors_and_gap3_for_current_track` (+53 B),
`_fdc_detect_sector_size_and_density` (+48 B),
`_calc_size_of_current_track` (+40 B), and
`_floppy_completed_operation_interrupt` (+22 B). These measurements show the
size difference, not its cause.

The pre-PR-40 `llc` was built at the parent revision above with assertions.
The historical `clang` target was not built: its dry run still required 1454
Ninja edges while the workspace had about 5 GB free. Ccache was configured,
but no material hit increase was observed; the shared cache was full at 20 GB.
The final `ccache -s` totals (8916 hits, 29281 misses, 13990 uncacheable calls)
are cumulative, not attributable solely to this build.

This comparison spans the pre-PR-40 parent (2026-09-07) to current revision
`d6658ad` (2026-10-09), so it does not isolate PR #40 from intervening
compiler changes. It also does not directly reproduce the archived `c863c55`
firmware listing: that is a different firmware/compiler snapshot.

Isolation note: one early copied-tree `make prom` used the shared MAME ROM
destination before the private `MAME` override was added. The shared file was
restored from the newest surviving `autoload-in-c/clang/prom0.ic66` copy, but
its exact pre-run bytes were not captured, so byte identity with the prior
shared file could not be verified. The historical build itself used a private
MAME directory.

## Full pre-PR-40 compiler attempt on c863c55 (2026-10-09)

Built the complete compiler/tool set from the pre-PR-40 parent revision
`1991786426b42cb678bcd2c38daf10bd853d0f25` and attempted to build the exact
`c863c55e27f82dadc73e7e15a2fbbc376d4b656c` autoload source. The compiler build
completed all 2458 Ninja steps and produced `clang`, `llc`, `ld.lld`,
`llvm-nm`, `llvm-objcopy`, and `llvm-objdump`.

The tool build command was:

```
ninja -C /Users/ravn/z80/llvm-z80/build-pre-pr40 -j4 \
  clang llc lld llvm-nm llvm-objcopy llvm-objdump
```

The first build attempt exposed stale absolute `clang`, `lld`, and third-party
source paths inherited from the copied CMake cache. Those paths were corrected
to the historical worktree, and the generated Ninja rules were checked for
remaining references to the current source tree before the build resumed.

The firmware build command targeted `clang/prom.clang.bin` directly, so it did
not install or overwrite the shared MAME ROM:

```
make -C rc700-gensmedet-pre-c863c55/autoload-in-c clang/prom.clang.bin \
  CLANG_BUILD=/Users/ravn/z80/llvm-z80/build-pre-pr40/bin \
  LLVM_Z80=/Users/ravn/z80/llvm-z80-pre-pr40 \
  CLANG_EXTRA='-Xclang -target-feature -Xclang +static-frame'
```

It stopped while compiling `rom.c`, before linking the PROM or running ZX0:

```
fatal error: error in backend: unable to legalize instruction:
G_STORE %0:_(s8), %10:_(p2) ... volatile store ... addrspace 2
(in function: fdc_write_when_ready)
```

The c863c55 Makefile requests `+static-stack` and `+shadow-regs`, but the
pre-PR-40 compiler warns that both feature names are unrecognized and ignores
them. Its supported static-frame spelling is `+static-frame`, supplied above
as the corresponding feature. Recompiling `rom.c` without that extra feature
failed on the same address-space-2 `G_STORE`, so this failure is not explained
by the spelling adjustment. A minimal `volatile address_space(2)` byte-store
to port 5 reproduced the Legalizer failure with the pre-PR-40 compiler.

The archived c863c55 source therefore did not yield a PROM, listing, or ZX0
payload with this full compiler; there is no new size measurement to compare
against the archived 2034 B result. This matches the current autoload header's
documented move away from address-space pointer I/O to inline assembly. A
separate attempt to use the existing `build-macos-asserts/bin/clang` as a
current-source control also failed the minimal store, but a Ninja dry run
reported 2968 pending steps in that build directory. That binary is not
accepted as a current-source control, and no current compiler rebuild was
performed. At this point in the investigation, the backend-only comparison above was the
only completed size comparison; the corrected full-compiler result below now
provides the exact-source measurement.

Ccache was active in the compiler commands. The aggregate counters moved from
8916 hits / 29281 misses at the saved baseline to 9096 hits / 32291 misses
after this attempt (cache at 20 GiB); those totals include the first
misconfigured build attempt and are not a clean measurement of hits from the
corrected historical-source build alone. The disposable historical worktrees
and 8.3 GiB compiler build directory were removed after verifying clean Git
status in both worktrees; the build and failure logs remain under `scratch/`.

## Correcting the historical compiler endpoint

The failed compiler revision above, `1991786426b42cb678bcd2c38daf10bd853d0f25`,
is the parent of PR #40, but it is already after the upstream merge that
reconstructed the backend and removed its local address-space-2 support. Its
`Z80InstrInfo.h` has no `AS_IO`, and its instruction selector has no port-I/O
lowering. Therefore the failure proves only that this intermediate tree could
not legalize the port store; it does not test a compiler tree that contains the
address-space-2 to IN/OUT mapping.

The first parent of merge `48c1b4b461a3` (`d52e23342de460f4512a52fe8e0941b50bc2d526`)
contains `AS_IO` and the corresponding `G_LOAD`/`G_STORE` selector paths.
It is tagged locally as `compiler-pre-pr40`; the annotated tag resolves to
that commit, dated 2026-09-05. The earlier commands and logs are retained as
evidence of the intermediate-tree failure.

## Full compiler and exact c863c55 PROM with port-I/O support (2026-10-09)

Built the complete compiler/toolchain at `compiler-pre-pr40` in a hardlink
copy of the configured macOS assertions build. The compiler source, Clang,
LLD, and third-party paths in the generated build rules were verified to point
at the historical worktree. The build completed all 3418 Ninja steps and
produced `clang`, `llc`, `ld.lld`, `llvm-nm`, `llvm-objcopy`, and
`llvm-objdump`. `clang --version` and `ld.lld --version` report revision
`d52e23342de460f4512a52fe8e0941b50bc2d526`.

Ccache was enabled and its cache contained 20.0 GiB before the build. The
statistics were zeroed immediately before the build; afterward, ccache
reported 0 hits and 2794 misses across 2794 cacheable calls (2 calls
uncacheable). Thus this run had 0% observed cache hits despite the warm cache;
the reason for the misses was not established.

Built the unmodified firmware source at
`c863c55e27f82dadc73e7e15a2fbbc376d4b656c` by targeting
`clang/prom.clang.bin` directly with `CLANG_BUILD` set to the corrected
compiler and `LLVM_Z80` set to its source worktree. No port-I/O source
adaptation was made, and the MAME-install target was not run.

The target completed successfully. The generated listing for
`fdc_write_when_ready` contains `in a,($4)` and `out ($5),a`, confirming the
address-space-2 accesses selected `IN A,(n)` and `OUT (n),A`. The raw `.text`
was 3393 B, compressed ZX0 payload 1915 B, and final PROM 2034 B. The ZX0
decompression roundtrip compared byte-for-byte equal to raw `.text`. The
committed c863c55 ZX0 payload decompresses to the same 3393-byte `.text`
except for the embedded build banner: the archived bytes say
`2026-07-01 18.21 ba7667b/ravn`, while this build says
`2026-10-09 23.53 c863c55/ravn`. All raw bytes before and after that banner
match. The compressed payloads therefore differ byte-for-byte because of the
banner, although both are 1915 B; both final PROMs are 2034 B. This confirms
the source can be built with a pre-upstream-merge compiler that
contains the mapping; the earlier failure at `199178...` was from an
intermediate post-merge tree without that feature, not evidence against the
pre-merge compiler. The resulting PROM, listing, raw text, compressed payload,
and full build logs are preserved under `scratch/premerge-c863c55/`. No MAME
boot was run; this result verifies the exact-source compile, link, compression,
and decompression roundtrip, not runtime behavior. The archived compressed
payload and its decompressed `.text` are also retained there for direct
comparison.

## Same-source c863c55 comparison against current compiler (2026-10-10)

This is a separate comparison from the earlier current-source analysis and
backend-only table above. It rebuilds the exact archived `c863c55` firmware
source with the pre-PR-40 compiler and with current backend `d6658ad`, so the C
source is held constant; the Clang frontends and static-frame mechanisms still
differ.

| Build | Raw `.text` | ZX0 payload | ROM image |
|---|---:|---:|---:|
| `compiler-pre-pr40` (`d52e233`) | 3393 B | 1915 B | 2034 B |
| `d6658ad` + temporary port-I/O restoration | 3685 B | 2095 B | 2214 B |
| Difference | **+292 B** | **+180 B** | **+180 B** |

The current 2214 B image is inspection-only and exceeds the 2048 B PROM
limit. A complete `check_sysfile` static-frame counterfactual saves 6 B after
ZX0, leaving a 174 B payload gap. A matched machine-outliner control changes
the payload by only 3 B (outlining enabled is larger), so it does not explain
the regression.

The listings also confirm a structural inlining difference: the historical
`_main_relocated` contains the character-generator loop and the banner,
SW1-status, and QR drawing bodies directly. Current `_main_relocated` calls
separate helpers for these operations. This is consistent with changed inline
decisions, but the builds use different Clang frontends, so the precise pass
or frontend cause has not been isolated. The per-function size table and
controlled measurements are in the workspace archive at
`scratch/pre-pr40-firmware-archive/reproductions/autoload-c863c55/COMPARISON.md`.
No MAME boot or runtime test was run; neither image is a production-size PROM.
