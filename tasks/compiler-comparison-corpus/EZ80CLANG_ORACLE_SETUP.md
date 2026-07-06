# ez80clang as a 6th corpus oracle — setup & recipe (code-quality only)

`ez80clang` here means CEdev's **`ez80-clang`** binary
([CE-Programming/toolchain](https://github.com/CE-Programming/toolchain)
releases, built from
[CE-Programming/llvm-project](https://github.com/CE-Programming/llvm-project)).
It is a **SelectionDAG** eZ80 LLVM fork — a *different lineage* from
ravn/llvm-z80 (which is GlobalISel, z80-native). Its `-triple z80` sub-target
emits genuine 16-bit z80 code, and z88dk already knows how to drive it via
`zcc +cpm -compiler=ez80clang`.

**Scope: CODE-QUALITY comparison oracle only** (user decision 2026-07-06 —
"jeg ønsker kun ez80clang som sammenligningsorakel på kodekvalitet"). We read
its size/t-state numbers on the benches where it compiles *correct* code, and
nothing else. It is **not** a runtime-correctness oracle: three of the five
corpus benches fail and are **skipped** in `sweep.sh` (`SKIP_CELL`), tracked
for fixing in **rc700-gensmedet#122**. Only `word_fill` and `licm_pessimize`
contribute datapoints.

llvm-z80 (our fork) already *is* "clang for z80"; ez80clang exists in this
sweep purely as an external comparison point.

Status: **evaluation**. Not a git submodule (a prebuilt binary staged outside
the repos). This doc + `setup_ez80clang.sh` are the reproducible steps.

## 1. Install (prebuilt release, no from-source build)

```sh
./setup_ez80clang.sh                 # latest release, auto OS/arch
CEDEV_TAG=v15.0 ./setup_ez80clang.sh # pin a release tag
CEDEV_DIR=/path ./setup_ez80clang.sh # staging parent (default /Users/ravn/z80/cedev-eval)
```

Requires an authenticated `gh`. It downloads the CEdev release asset for your
platform (`CEdev-macOS-arm.dmg` / `CEdev-macOS-intel.dmg` / `CEdev-Linux.tar.gz`),
extracts the `CEdev/` tree to `$CEDEV_DIR/CEdev`, and symlinks the binary into
z88dk so `zcc` can find it:

```
$Z88DK/bin/ez80-clang -> $CEDEV_DIR/CEdev/bin/ez80-clang
```

**macOS DMG note (hard workspace rule):** the DMG is mounted at a
workspace-internal mountpoint (`$CEDEV_DIR/.mnt`), never `/Volumes` — the
workspace-search hook blocks `/Volumes` and mounting there forces iCloud
downloads. The script also clears the `com.apple.quarantine` xattr so the
binary runs.

**Building it from source ourselves gains nothing** (verified reasoning
2026-07-06): CE's fork produces the same codegen, the same ADL-24-bit runtime,
and the same CE-named libcalls (`__llmulu`/`__ldivu`/`__llshru`) baked into the
backend. The gaps below are library + codegen bugs, not build-config.

Verify:

```sh
$Z88DK/bin/ez80-clang --version   # -> clang 19.1.0, Target: ez80 (CE-Programming/llvm-project)
```

## 2. z88dk bridge fix required for CEdev v15.0 (`clang_rules.1`)

z88dk drives ez80-clang through `z88dk-copt` with `lib/clang_rules.1`. CEdev
v15.0's clang-19 asm printer emits directives that vanilla z88dk's
`clang_rules.1` (both ours **and** upstream master, byte-identical) does not
translate, so an unpatched z88dk + CEdev v15.0 **cannot build**. Two additions
were prepended to `z88dk/lib/clang_rules.1` (already committed on branch
`rc700-gensmedet-1`):

1. **Dotted GNU-as directives.** CE clang emits `.section`/`.ident`/
   `.note.GNU-stack` with a **leading dot**; the historical rules only match
   the no-dot form (`section .text,%1`). Added dotted variants that map
   `.section .text/.rodata/.bss/.data[.name]` → the z80asm `SECTION *_compiler`
   directives and drop `.section %1` / `.ident %1`. They must precede the
   no-dot rules.
2. **BSS even-align idiom.** CE clang emits `rb ($$ - $) and 1` before an
   aligned variable, but z88dk-z80asm rejects both `$$` and the word operator
   `and`. Mapped to the z80asm `ALIGN 2` directive. Must precede the generic
   `rb %1` rule.

If you stage a **different** CEdev version, re-check its `-S` output against
these rules — the directive shapes can change between CE releases. (A cleaner
fix likely belongs upstream in z88dk; not filed yet.)

There is also a `db "..."`-with-embedded-newline shape CE clang can emit for
string literals that z80asm rejects; the corpus benches use a 0xC000 sentinel
and no string literals, so it doesn't arise here.

## 3. How the sweep drives it

`build_ez80clang_corpus.sh` mirrors the llvm-z88dk lane so the opt level is the
only variable:

```
cat bench_<x>.c dcc_test_main.c              # single TU (harness concat)
  -> zcc +cpm -compiler=ez80clang <opt> -o prog -create-app
  -> wrap .COM at 0x0100 in a 64 KB image (JP0 warm-boot + BDOS stub)
  -> z88dk-ticks -pc 100 -end 0 -counter 3e9 (300 s alarm)
  -> verify 0xC000 sentinel: ram[0xC004]==1 && ram[0xC006]==0xA5
```

Opt knobs: `size` → `--opt-code-size` (clang `-Oz`); `speed` → default
(clang `-O3`). The `.COM` bundles the z88dk RTL, so `bin` is a **trend, not
parity** (same caveat as the dcc/llvm-z88dk/xcc lanes; `text` is `n/a`).

Run just this lane:

```sh
ONLY=ez80clang ./sweep.sh
```

`sweep.sh` skips the ez80clang lane with a one-line hint if `ez80-clang` is
absent from both `$PATH` and `$Z88DK/bin`.

## 4. The three skipped cells (rc700-gensmedet#122)

| cell | reason | status |
|---|---|---|
| `pi:ez80clang` | ez80-clang emits CE 32-bit libcall names `__llmulu`/`__ldivu`/`__llshru`, implemented only in CEdev's `lib/crt/libcrt.a` as **ADL-24-bit** eZ80 code; z88dk's z80 clib can't resolve them → link failure | **verified** — a runtime-library integration gap, NOT a codegen bug |
| `sieve:ez80clang` | CE z80 sub-target miscompiles above a complexity threshold: sieve array size ≤420 correct (`com`=7429 B), ≥450 **hangs** while the emitted binary paradoxically **shrinks** to 5787 B | symptom **verified** (bisected); CE-codegen-vs-z80asm cause **not confirmed** |
| `fannkuch:ez80clang` | same codegen-cliff class (wild jump to 0x0000) | symptom verified; not root-caused |

32-bit ops that **const-fold** under `-O3` work (no libcall emitted); it's only
*runtime* 32-bit mul/div/shift that hits the missing helpers.

When a cell is fixed, remove it from `SKIP_CELL` in `sweep.sh` so it re-enters
the sweep.

## Verified facts (2026-07-06, macOS-arm, CEdev v15.0, clang 19.1.0)

- `ez80-clang -triple z80` emits real 16-bit z80 code (not 24-bit ADL): 8-bit
  add ✓, 16-bit loop sum 0..999 = 40748 ✓, mini-sieve N=100 = 25 primes ✓,
  const-folded 32-bit mul ✓.
- Corpus: `word_fill` PASS (bin 6474, ts 233627), `licm_pessimize` PASS
  (bin 5593, ts 20141); `sieve`/`fannkuch`/`pi` fail → skipped (see §4).
- Provenance: CE-Programming/llvm-project `ef28e9c5…`, SelectionDAG eZ80 fork,
  distinct from ravn/llvm-z80's GlobalISel backend.
