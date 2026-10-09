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
Function-size diff: `scratch/compare.py` (saved alongside baseline/current
listings in `autoload-in-c/scratch/`).
