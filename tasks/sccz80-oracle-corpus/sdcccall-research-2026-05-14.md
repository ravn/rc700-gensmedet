# How to properly make `--sdcccall 1` work — documentation research

Investigation 2026-05-14. Verifying with primary sources how the SDCC
+ z88dk + sdcccall story actually fits together, after the corpus
work surfaced the ABI mismatch repeatedly.

## The two camps

### SDCC upstream (sdcc.sourceforge.net)

- Since **SDCC 4.1.12** (late 2022), `--sdcccall 1` is the **default**
  for Z80. Quote from SDCC manual: "The current default is the SDCC
  calling convention, version 1. Using the command-line option
  `--sdcccall 0`, the default can be changed to version 0."
- `--sdcccall 1` passes "up to two arguments in registers" via the
  DEHL subset. 8-bit return in `A`, 16-bit in `DE`, 24-bit in `LDE`,
  32-bit in `HLDE`.
- SDCC's bundled stdlib is rebuilt to match the configured sdcccall
  value **at SDCC build time**. If you build SDCC with sdcccall 1
  default, every helper in `device/lib/z80/` (`__moduchar`,
  `__mulint`, `__divuchar`, …) is sdcccall-1-compatible.

### z88dk's zsdcc fork (github.com/z88dk/zsdcc)

- z88dk patches SDCC to **revert the default to `--sdcccall 0`**.
  Verified empirically:
  ```
  $ zcc +z80 -compiler=sdcc -clib=sdcc_iy --opt-code-size --list \
        -c foo.c -o foo.o
  ; emits IX-frame stack-args codegen (sdcccall 0)
  ```
  The override lives in zsdcc's patch series (not in any of the
  `*.patch` files in `src/zsdcc/` by string `sdcccall`, but the
  behaviour is observable and intentional).
- z88dk's hand-written runtime helpers in `libsrc/l/sdcc/` are all
  **sdcccall-0** (stack-passed args). The `_callee` variants differ
  only in stack cleanup, also stack args. zero file mentions
  "sdcccall" anywhere in z88dk's lib tree.
- Official reason (z88dk wiki on CallingConventions + forum threads
  on issue #1827): *"z88dk continues with the __sdcccall(0)
  convention because all the code is hand optimised assembly. It is
  a massive job to convert. z88dk already uses the sdcc __fastcall
  and __callee conventions, so the actual gain from register passing
  is not substantial."*

### What `zcc`'s warning 296 actually means

`warning 296: non-default sdcccall specified, but default stdlib or crt0`

= "You requested a non-default sdcccall ABI for your user code, but
the stdlib zcc is about to link is built for the default (sdcccall
0). zcc has no CLIB variant that ships sdcccall-1 helpers." It's a
deliberate guard, not a bug.

cpnos-rom production silences this warning with `-Cs"--disable-warning 296"`
and *also* writes source that never calls any of the mismatched
helpers — that's how production "makes sdcccall(1) work" without
fixing the underlying ABI mismatch.

## The four documented paths to use `--sdcccall 1` properly

### Path A — Use SDCC directly, bypass zcc

The most documentation-aligned answer per SDCC's manual. Workflow:

1. Install or build SDCC yourself (Homebrew is out per project
   rules; build from source from `sdcc.sourceforge.net` or Docker).
2. Invoke `sdcc -mz80` directly. SDCC's bundled stdlib in
   `share/sdcc/lib/z80/` is built for whichever sdcccall the SDCC
   binary was configured with (default 1 since 4.1.12).
3. Provide your own crt0 (`sdcc --no-std-crt0`) since z88dk's target
   crt0s assume zcc/z88dk env. Our cpnos-rom already does this with
   its own `reset.s`.

Pros: uses sdcccall(1) the way SDCC intends; helpers are auto-built
for the ABI; no warning.
Cons: lose z88dk's target libraries (machine-specific clib, embedded
crt0s, the `+target` ergonomics). For our PROM/BIOS work this loss
is minimal — we already use `--no-crt` and provide our own reset.

### Path B — Use z88dk normally; opt into register passing per-function

The z88dk-recommended path. Instead of `--sdcccall 1` globally, use
SDCC's per-function attributes that z88dk's library was built around:

```c
// 1-arg function, arg passed in register subset of DEHL
void __z88dk_fastcall foo(uint8_t x) { ... }

// caller pops args (saves N bytes at every callsite)
int __z88dk_callee bar(int a, int b) { ... }

// per-function sdcccall override (mixes with default)
void __sdcccall(1) hot_path(uint8_t a, uint8_t b) { ... }
```

`__z88dk_fastcall` is the closest match for "register passing where
it matters" without changing the global ABI. z88dk's library helpers
already use `__z88dk_fastcall` / `__z88dk_callee` throughout, so they
mix correctly with user code that uses these decorators.

Pros: no warning, no ABI mismatch, z88dk-supported.
Cons: per-function annotation (less ergonomic than a global flag).

### Path C — Production-aligned workaround (current cpnos-rom)

```
-Cs"--sdcccall 1" -Cs"--disable-warning 296"
```

plus source that contains zero `__mul/__div/__mod` reachable paths
plus *suppression* of the warning that would have caught any leak.

Pros: minimal change, register passing for user code, helpers stay
sdcccall-0-compatible.
Cons: silent miscompile if any source path ever reaches a helper;
trap waiting to fire. Already burned us twice in the oracle corpus
(`__mulint` and `__moduchar`).

This is what cpnos-rom + rcbios-in-c/sdcc do today. It works because
production code is helper-free by audit.

### Path D — Custom sdcccall-1 helper shims

Write per-helper sdcccall-1-compatible asm and link ahead of z88dk's
stdlib. Demonstrated in the earlier `moduchar_sdcccall1.asm`
(commit 2213e5b, since reverted).

Pros: keeps z88dk frontend + targets; closes the trap from Path C.
Cons: maintain a parallel mini-libc; reaches past the frontend; not
how z88dk is designed to be configured.

## Recommendation

For our project, in priority order:

1. **For cpnos-rom and rcbios-in-c/sdcc production**: stay on Path C
   (current). Documented: any new source that needs `x % N`, 16-bit
   multiply, etc. must use a power-of-2 form (`x & (N-1)`) or
   refactor — silently calling `__moduchar` would miscompile.
   Add to the project's commit-checklist for SDCC builds: grep new
   `.lis` files for `call __` helpers as a CI guard.

2. **For new SDCC-based work that wants register passing without the
   Path C trap**: Path B (per-function `__z88dk_fastcall` /
   `__z88dk_callee`). It's the z88dk-supported way to get the same
   performance gain on hot paths.

3. **If we ever want full register-ABI consistency across user code
   and stdlib**: Path A. Use SDCC directly. Worth investigating if
   we engage SDCC upstream (the BIOS clang-vs-SDCC code-density
   work could benefit). Cost: lose z88dk's target ergonomics, gain
   real sdcccall(1) end-to-end.

4. **Path D (custom shims)** is the wrong answer per z88dk's design;
   keep only as a debugging tool / regression repro, not for
   production.

## Documentation references

- [SDCC 4.5.15 manual (sdccman.pdf)](https://sdcc.sourceforge.net/doc/sdccman.pdf) — §4.x on Z80 sdcccall conventions
- [z88dk wiki — CallingConventions](https://github.com/z88dk/z88dk/wiki/CallingConventions) — __z88dk_fastcall, __z88dk_callee, __z88dk_sdccdecl
- [z88dk issue #1827 — SDCC changing its default calling convention](https://github.com/z88dk/z88dk/issues/1827) — discussion thread
- [z88dk forum #11835](https://www.z88dk.org/forum/viewtopic.php?t=11835) — user-reported issues with the new SDCC default (login required)
- [Oddbit Retro: "Inside SDCC: Mastering the New Z80 ABI"](https://www.oddbit-retro.org/sdcc-z80-abi-new-register-based-calling-convention/) — practitioner's guide to sdcccall(1)
- [SDCC z80 wiki](https://sourceforge.net/p/sdcc/wiki/z80/) — additional z80-specific notes
- [retro-vault/libsdcc-z80](https://github.com/retro-vault/libsdcc-z80) — third-party bare-metal helper library for SDCC z80

## Empirical confirmations from this investigation

- `zcc +z80 -compiler=sdcc` default produces sdcccall-0 codegen
  (verified — 13-byte `foo(uint8_t,uint8_t)` with IX frame).
- `zcc +z80 -compiler=sdcc -Cs"--sdcccall 1"` produces sdcccall-1
  codegen (verified — 2-byte `_foo: add a,l; ret`).
- All helpers in `libsrc/l/sdcc/` are stack-args (verified by
  reading each `.asm` file's header comment).
- cpnos-rom + rcbios-in-c/sdcc built .asm/.lis: zero helper calls
  (`call __mul*`, `call __mod*`, `call __div*`).
- Zero string `sdcccall` anywhere in `/Users/ravn/z80/z88dk/`
  tree (verified). z88dk treats sdcccall as not-its-concern at the
  frontend level.
