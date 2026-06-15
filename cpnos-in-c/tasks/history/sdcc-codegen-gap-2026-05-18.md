# SDCC vs clang codegen gap — cpnos-in-c PROM1 line program

Date: 2026-05-18
Status: investigation complete; bug-filing pending

## Summary

cpnos-in-c PROM1-only build measured at session 73j-end:

| Section          | SDCC   | clang  | gap     |
| ---------------- | ------ | ------ | ------- |
| init_code.bin    | 677 B  | 606 B  | +71 B   |
| resident.bin     | 2196 B | 2026 B | +170 B  |
| **post-ZX0+pad** | 2246 B | 2027 B | +219 B  |

This document accounts for ~120 B of the resident gap as concrete SDCC code-quality issues, plus characterizes the remaining ~50 B as broadly distributed register-allocation churn.

## Per-function top offenders (RESIDENT)

Computed by treating SDCC top-level `_xxx` symbol addresses as function boundaries (next non-local symbol minus current).

| diff  | sdcc | clang | function                |
| ----- | ---- | ----- | ----------------------- |
| +48   | 144  | 96    | `_specc`                |
| +30   | 143  | 113   | `_scroll_lines`         |
| +16   | 88   | 72    | `_impl_conin`           |
| +14   | 40   | 26    | `_pio_b_set_input`      |
| +10   | 30   | 20    | `_transport_recv_byte`  |
| +9    | 41   | 32    | `_transport_pio_send_byte` |
| +8    | 23   | 15    | `_cursor_down`          |
| +7    | 26   | 19    | `_pio_b_set_output`     |
| +6    | 53   | 47    | `_resident_handoff`     |
| +6    | 17   | 11    | `_console_putc`         |
| +5    | 119  | 114   | `_impl_conout`          |

Total SDCC-heavier sum across the 59 common functions: **+209 B** (matches the +170 B raw gap plus a small attribution variance from BSS/rodata placement).

## Issue class 1 — switch dead code after tail-call `jp` (~36 B in `_specc`)

`_specc` is a 16-case switch over a ctrl byte; most cases tail-call into another function (`cursor_left`, `home`, ...).  SDCC's output (`sdcc/audit/resident.s:880`):

```
_specc:
    cp a,0x01
    jp Z,_insert_line       ; case 0x01 -> tail call
    cp a,0x02
    jp Z,_delete_line
    cp a,0x05
    jp Z,_cursor_left
    cp a,0x06
    jp Z,_start_xy
    cp a,0x07
    jr Z,l_specc_00105      ; case 0x07 needs inline body, branches
    cp a,0x08
    jr Z,l_specc_00106
    ...
    sub a,0x1f
    jr Z,l_specc_00115
    jr l_specc_00118        ; default: break
    jp _insert_line         ; <-- DEAD: control can never reach here
    jr l_specc_00118        ; <-- DEAD
    jp _delete_line         ; <-- DEAD
    jr l_specc_00118        ; <-- DEAD
    jp _cursor_left         ; <-- DEAD
    jr l_specc_00118        ; <-- DEAD
    jp _start_xy            ; <-- DEAD
    jr l_specc_00118        ; <-- DEAD
l_specc_00105:
    ld l,0x00
    ld a,0x1c
    jp __port_out
l_specc_00106:
    jp _cursor_left
    jr l_specc_00118        ; <-- DEAD: preceding jp is unconditional
l_specc_00107:
    jp _tab
    jr l_specc_00118        ; <-- DEAD
... (same pattern for 6 more cases)
```

Two distinct missed peepholes:

- **Duplicate dispatch block** (lines 912-919, 20 B dead): SDCC appears to emit
  the first four cases twice — once as `cp/jp Z` in the dispatch chain (the live
  copy) and once as a fallthrough sequence after the default branch (the dead
  copy).  Looks like a switch-lowering bug where SDCC reserves an "indirect"
  body block for tail-call cases even when the dispatch already inlined them as
  `jp Z`.
- **Dead `jr <break>` after unconditional `jp`** (8 occurrences × 2 B = 16 B):
  Every per-case body is `jp <handler>` followed by `jr l_specc_00118`.  The
  `jp` is unconditional — the `jr` is unreachable.

**Combined dead code in `_specc`: 36 B** (out of the +48 B gap).

Reproducer is small — a 10-case switch where each case tail-calls a function
should trigger both patterns.

## Issue class 2 — `_port_out` / `_port_in` indirect helper (~54 B across 18 sites)

z88dk-SDCC has no inlinable `OUT (n),A` or `IN A,(n)` intrinsic.  Project
defines a single helper in `sdcc/hal.asm`:

```
__port_out:    ; 5 B body
    ld c,a
    ld a,l
    out (c),a
    ret
```

Every call site costs 7 bytes:

```
ld l, VAL      ; 2 B
ld a, PORT     ; 2 B
call __port_out ; 3 B
```

clang lowers the same source (`address_space(2)` pointer) to a direct 4-byte
`ld a,VAL; out (PORT),a` inline.

Count of indirect calls in resident objects:
```
$ grep -c "call\s*__port_out\|call\s*__port_in" sdcc/audit/*.s
transport_pio.s:9
resident.s:6
transport_sio.s:3
```

**18 call sites × 3 B per-site savings = 54 B**, plus another 9 B for the
two helper bodies.

Mitigation candidates (best to worst):

1. Add a `__sfr` or `__port` intrinsic to z88dk's SDCC fork that lowers
   to a constant-folded `OUT (n),A` / `IN A,(n)` when port is a compile-time
   constant.  This is the cleanest fix but is upstream-SDCC territory.
2. Define helper macros that emit `__asm__` per call site.  Brittle (asm
   inside SDCC has tooling caveats) but doable today.
3. Replace `_port_out(p,v)` with two helpers `_port_out_FA(p,v)` (fast,
   for compile-time port) / `_port_out(p,v)` (current, variable port).
   Only the fast variant gets the asm.

Worth filing as a ravn/z88dk feature request before doing 2 or 3.

## Issue class 3 — IX frame for trivial scalar locals (~20 B in `_scroll_lines`)

`_scroll_lines(uint8_t down)` is called with a single 1-byte arg.  SDCC
prologue:

```
_scroll_lines:
    push ix
    ld ix,0
    add ix,sp
    push af
    dec sp
    ld (ix-1),a   ; stash arg
```
= 13 B prologue + 5 B epilogue (`ld sp,ix; pop ix; ret`) = 18 B frame overhead
for stashing one byte that could live in C.

clang with `+static-stack` avoids the IX frame entirely; if needed it puts
the arg in BSS.  In this specific function clang's prologue is bare (`scroll_lines`
keeps the arg in a register for the dataflow).

This is a known SDCC limitation when liveness across calls forces the local
to a stack slot, and SDCC always picks IX over allocating to a register pair.
Wider in scope than the other two; mitigation is structural (rework the
function so the flag doesn't need to live across the call) rather than a
compiler fix we can submit.

## Smaller findings

- **`_cursor_down` +8 B**: dead `jp _scroll_up` after a `ret` (3 B unreachable) + unnecessary 16-bit promotion when widening `cury` for the `+1 >= 25` compare (could stay in A, 4 B saved).  Same dead-code class as Issue 1 (peephole bug).
- **`_impl_conin` +16 B**: SDCC materializes `use_inconv` (bool) into a register via `if-then-else ld a,0/1` pattern; could keep flags live across the call.  Plus `inc c; dec c` (2 B) used as zero-test where `or c` (1 B) would do.  Lower-leverage.
- **`_pio_b_set_input` +14 B / `_pio_b_set_output` +7 B / `_transport_pio_send_byte` +9 B**: dominated by Issue 2 (port_out indirection).  Strip those and these gaps shrink to <3 B each.

## Attribution

```
Issue 1 (switch dead code)            ~36 B   _specc
Issue 1 (sibling: dead-after-ret)     ~3 B    _cursor_down + others
Issue 2 (port_out indirection)        ~54 B   spread across pio/sio/resident
Issue 3 (IX frame for 1-byte arg)     ~20 B   _scroll_lines
                                      ------
                                      ~113 B
remaining (regalloc churn, prologue   ~57 B   spread; smaller deltas
overhead, misc)
                                      ------
total observed                        ~170 B   matches resident.bin gap
```

## Bug filing candidates (ravn/z88dk)

Recommended priority:

1. **#1 — switch dead code** (concrete, minimal repro likely <30 lines, immediate
   wins for any project using switches with tail-call bodies).  Filing target:
   ravn/z88dk issues (same repo as the block-scope-extern bug filed 2026-05-17
   as issue #7).
2. **#3 — dead `jp` after `ret`** (peephole gap; same diagnostic class as #1;
   bundle if SDCC fix touches the same pass).
3. **#2 — port-IO intrinsic** (feature request, not a bug; mention in passing
   when filing #1 since it's high-leverage on embedded targets).

## Followups

- Author minimal repros for #1 and #3 and file as ravn/z88dk issues.
- Decide whether to mitigate #2 with site-local `__asm__` macros (~50 B win
  in the PROM1 build, makes hal.asm dead code) — separate task.
- Issue #3 (IX frame) is structural; defer.
