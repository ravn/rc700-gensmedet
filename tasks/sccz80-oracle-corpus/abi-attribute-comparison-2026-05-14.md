# Per-function ABI attribute comparison — 2026-05-14

Investigation: of the three z88dk-supported per-function ABI
attributes, which generates the tightest code?

## Setup

`abi_compare.c` compiles four function shapes in each of four ABI
variants (plus a combination), then 5 caller functions each making
3 sequential calls into one variant. Build flags match cpnos-rom
production: `zcc +z80 -compiler=sdcc -clib=sdcc_iy --opt-code-size
-SO3 -Cs"--max-allocs-per-node 25000" -Cs"--fomit-frame-pointer"`.

No global `--sdcccall 1` — each function opts in via the attribute.

## Body sizes (function code only)

| Shape              | `_def` | `_fastcall` | `_callee` | `_sdccc1` | `_s1+callee` |
|--------------------|------:|-----------:|---------:|---------:|------------:|
| `inc(u8)→u8`       |  10   |    2       |   13     |    2     |    2        |
| `add(u8,u8)→u8`    |  13   |    n/a *   |   16     |    2     |    2        |
| `store(u8)→void`   |  12   |    5       |   14     |    4     |    —        |
| `neg(u16)→u16`     |  16   |    7       |   19     |    7     |    —        |

\* `__z88dk_fastcall` is limited to **one** argument total. Per docs:
"At most a single parameter is passed in registers" via the DEHL
subset.

## Sample asm — `inc(uint8_t x) { return x + 1; }`

```asm
; _def (10 B) — IX-frame stack-args
_inc_def:
    call ___sdcc_enter_ix       ; 3 B
    ld   l, (ix+4)              ; 3 B   arg from stack via IX
    inc  l                      ; 1 B
    pop  ix                     ; 2 B
    ret                         ; 1 B

; _fastcall (2 B) — arg in L
_inc_fastcall:
    inc  l                      ; 1 B
    ret                         ; 1 B

; _callee (13 B) — _def + stack cleanup (callee pops args)
_inc_callee:
    call ___sdcc_enter_ix       ; 3 B
    ld   l, (ix+4)              ; 3 B
    inc  l                      ; 1 B
    pop  ix                     ; 2 B
    pop  bc                     ; 1 B   save return address
    inc  sp                     ; 1 B   discard 1-byte arg
    push bc                     ; 1 B   restore return address
    ret                         ; 1 B

; _sdccc1 (2 B) — arg in A
_inc_sdccc1:
    inc  a                      ; 1 B
    ret                         ; 1 B
```

## Caller sizes (3 sequential calls)

A "caller" measures the overhead at each call site: arg setup,
post-call stack cleanup, etc. Across N=3 calls per caller:

| Variant         | bytes | bytes/call | what the caller does                     |
|-----------------|------:|-----------:|------------------------------------------|
| `call_def`      |  37   |  12.3      | push arg, call, pop arg (each call)      |
| `call_fastcall` |  28   |   9.3      | `ld l, imm`, call (no stack op)          |
| `call_callee`   |  34   |  11.3      | push arg, call (callee pops)             |
| `call_sdccc1`   |  25   |   8.3      | `ld a, imm`, call (no stack op)          |
| `call_s1_callee`|  25   |   8.3      | tied with `call_sdccc1`                  |

`__z88dk_callee` saves 1 byte per call site (caller no longer
pops). The callee body grows by 3 B to do the cleanup itself.
Break-even at 3 callsites. For our cpnos-rom hot helpers (called
many times), `__z88dk_callee` is a net win — but only when combined
with default ABI (stack args). With sdcccall(1), there's nothing
on the stack to clean up.

## Total cost — function body + 3 call sites

This is the realistic comparison for a function used 3 times:

| ABI            | body | callsites | **total** | Δ vs default |
|----------------|----:|----------:|----------:|-------------:|
| default        | 10   |    37     |    **47** |        —     |
| `__z88dk_fastcall` |  2   |    28     |    **30** |       −17    |
| `__z88dk_callee`   | 13   |    34     |    **47** |        0 ★   |
| `__sdcccall(1)`    |  2   |    25     |    **27** |       −20    |
| `__sdcccall(1) + __z88dk_callee` | 2 | 25 | **27** | −20 (no add'l gain) |

★ `__z88dk_callee` by itself is break-even at 3 callsites. With
more callsites it eventually wins by 1 B per additional call.

## Key findings

### 1. `__sdcccall(1)` is the tightest overall

For every function shape and every call-site count tested, the
sdcccall(1) attribute produces the smallest combined code. The
8-bit ABI puts args in A directly (matches Z80 arithmetic), and
the lack of stack args eliminates both callee prologue and caller
cleanup.

### 2. `__z88dk_fastcall` is close behind for 1-arg

- **Tied** with sdcccall(1) on `inc(u8)` (both 2 B body).
- **Loses by 1 B** on `store(u8)` because the fastcall arg lands
  in L and the store needs A — adds `ld a, l`. sdcccall(1) puts
  the arg in A directly.
- **Tied** with sdcccall(1) on `neg(u16)` (both 7 B body, same
  HL/HL pattern).
- **Cannot be used** for 2+ argument functions — single hardest
  restriction.

### 3. `__z88dk_callee` is orthogonal, not a substitute

`__z88dk_callee` only adjusts who cleans the stack — it doesn't
change argument-passing. Body GROWS by 3-4 B; each callsite
SHRINKS by 1 B. Net win at 4+ callsites per function, neutral or
loss otherwise.

If combined with `__sdcccall(1)` it provides **no additional gain**
(sdcccall(1) has no stack args, so there's nothing for callee to
clean). The SDCC compiler appears to honour both attributes silently
but the second one becomes a no-op.

### 4. The combination matters more than the individual

`__sdcccall(1) + __z88dk_callee` is not additive; pick one based on
the actual ABI you want.

## Recommendation

For new SDCC-based work in cpnos-rom / rcbios-in-c:

1. **Default to `__sdcccall(1)` per-function** on hot paths. It
   dominates fastcall on every shape that fastcall handles, AND
   extends to multi-arg.

2. **Skip `__z88dk_fastcall`** unless you need it for library-API
   compatibility (e.g., calling into a function the library
   exposes as `__z88dk_fastcall`).

3. **Skip `__z88dk_callee` for cpnos-style code** unless a specific
   function is hot AND called from many sites AND uses default ABI.
   It's a niche optimisation.

4. **Combine with `__z88dk_callee` only if** you want callee-side
   stack cleanup AND can't use sdcccall(1) (e.g., interfacing with
   a library that expects stack-passed args). In sdcccall(1)
   contexts the callee attribute is silently no-op.

## Implications for cpnos-rom production

Current production uses global `-Cs"--sdcccall 1"` for everything
plus avoidance of helper-call sites. Per-function attributes are an
alternative that:

- Avoids warning 296 entirely (no `-Cs"--disable-warning 296"`
  needed).
- Lets non-hot code stay on default ABI (smaller per-function
  hot-path delta is offset by safer global ABI).
- Eliminates the helper-call trap: helpers stay sdcccall(0)-
  compatible because user code that calls them is also sdcccall(0).

Trade-off: source code becomes verbose (`__sdcccall(1)` annotation
on every hot function declaration and definition). For cpnos-rom's
~20-function profile that's not crushing; for BIOS's larger
function count it's a real ergonomic cost.

If we ever encounter the helper-trap in production (per the audit
none currently), switching to per-function attributes is the
documented z88dk-supported fix.

## Documentation references

- [SDCC 4.5.15 manual](https://sdcc.sourceforge.net/doc/sdccman.pdf) — §Z80 SDCCCALL conventions
- [z88dk wiki — CallingConventions](https://github.com/z88dk/z88dk/wiki/CallingConventions)
- [sdcccall-research-2026-05-14.md](sdcccall-research-2026-05-14.md) — the broader landscape
