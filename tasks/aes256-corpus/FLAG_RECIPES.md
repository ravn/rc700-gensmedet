# Optimal clang/sdcc flag combinations per code shape

Persistent record of empirically-validated flag combinations that
produce the smallest / fastest output for specific code patterns
on ravn/llvm-z80. Diff this doc in git to surface either:
- New recipes added (a new pattern characterised)
- Existing recipe results changed (regression / improvement)

Update via measurement in the aes256-corpus or sccz80-oracle-corpus,
NEVER from theory. Each recipe must have a reproducible build line
and an empirical size/runtime number alongside.

## Clang baseline-of-record

All clang recipes below are deltas from this baseline:

```
clang --target=z80 -Oz -nostdlib -ffreestanding -std=c89 \
      -Wno-deprecated-non-prototype
```

Last validated against ravn/llvm-z80 HEAD `3369f137dd2d`,
2026-05-15.

## Recipes (verified on aes256-corpus)

### General — production cpnos-rom configuration (clang)

```
clang ... -Xclang -target-feature -Xclang +static-stack \
          -mllvm -disable-lsr \
          -mllvm -disable-machine-licm \
          -mllvm -disable-machine-cse \
          -ffunction-sections -fdata-sections
```

Linked with `--gc-sections`.

- **Use for**: cpnos-rom and similar BIOS/PROM-style code. Known to
  produce the smallest binaries on ravn/llvm-z80 for that workload
  shape.
- **Watch out**: `+static-stack` miscompiles AES-class code with
  9+ byte locals (issue [ravn/llvm-z80#156](https://github.com/ravn/llvm-z80/issues/156)).
  Verify behavior on workloads with high register pressure.
- **Validation status**: validated on cpnos-rom (1928 B clang
  resident); FAIL on aes256-corpus.

### Universal IX-frame-pointer recipe (closes ravn/llvm-z80#157)

```
clang ... -fno-omit-frame-pointer
```

- **Use for**: any non-`+static-stack` build where the function
  has more than ~5 byte locals or otherwise spills.  This forces
  `hasFP=true` on the Z80 backend, reserving IX as frame pointer
  and switching all spill-slot access from `LD HL,N; ADD HL,SP;
  LD (HL),X` (5 B per access) to `LD (IX±N),X` (3 B per access).
- **AES corpus impact** (HEAD `3369f137dd2d`, post-#156):

  | Variant | default | `-fno-omit-FP` | Δ |
  |---|---:|---:|---:|
  | clang.bin (K&R) | 4450 B | **3805 B** | **−645 (−14.5%)** |
  | clang_ansi.bin | 4241 B | **3608 B** | **−633 (−14.9%)** |
  | clang_kr tstates | 65.98M | **41.79M** | **−37%** |
  | clang_ansi tstates | not measured | **36.97M** | (vs zsdcc 12.08M) |

- **Per-function (clang K&R)**:
  - `aes_mc_inv` 460 → **330 B** (−130; close to zsdcc 314)
  - `aes_mixColumns` 300 → **236 B** (−64; **beats** zsdcc 241)
  - `aes_expDecKey` 604 → **495 B** (−109)
  - `aes_expandEncKey` 529 → **442 B** (−87)
  - `aes_shiftRows`/`aes_sr_inv` each 271 → **200 B** (−71)
  - `gf_log` 153 → **113 B** (−40)
  - `aes_done` 54 → 58 B (**+4**; tiny leaf regression)
- **Gap vs zsdcc**: K&R was +846 B → +201 B; ANSI was +637 B → **+4 B**
  (essentially tied with the smallest sdcc config).
- **Combine with**: `+static-stack` superlatively beats it when re-entrancy
  is not needed (production cpnos-rom config, 2806 B on the same corpus).
- **Why this isn't the backend default**: small leaf functions with no
  spills pay ~4 B (PUSH IX / LD IX,0 / ADD IX,SP / POP IX) for no payback.
  ravn/llvm-z80 leaves the choice to the user via this flag; production
  PROMs already use `+static-stack` which is the strictly better option.

### Real-world u8-heavy code — runtime + size win (clang)

```
clang ... -mllvm -disable-machine-licm \
          -mllvm -disable-machine-cse \
          -mllvm -disable-machine-sink
```

- **Use for**: AES-class C code with byte locals and loop bodies.
  Validates open issue [#128](https://github.com/ravn/llvm-z80/issues/128).
- **AES headline numbers**: aes256.c text 4660 → 4329 B
  (**−7.4%**); runtime **66.1M → 31.6M tstates (−52%)** with
  `-disable-machine-licm/cse` alone.  Adding `-disable-machine-sink`
  saves an additional ~22 B per high-pressure function on the
  K&R-callee repro.
- **Combine with**: `-ffunction-sections -fdata-sections --gc-sections`
  for an additional ~50 B.
- **Watch out**: not validated to be a win on tight BIOS-style
  code. Re-measure cpnos-rom before adopting elsewhere.

### Workaround for K&R-callee bloat (issue #160)

```
clang ... -mllvm -disable-machine-licm \
          -mllvm -disable-machine-cse \
          -mllvm -disable-machine-sink
```

Plus, on each K&R-style u8-by-value function that has hot callers:

```c
__attribute__((always_inline)) static
uint8_t f(x) uint8_t x;
{ ... }
```

- **Use for**: AES-class code where you can't convert K&R to ANSI
  in the source (e.g. preserving upstream provenance).
- **Impact on canonical repro** (`repros/repro_kr_callee_propagates.c`):
  K&R baseline 914 B → 819 B with `-disable-machine-sink` family
  (−10.4%), or 839 B with `always_inline` alone.  Combined:
  somewhere in between (not yet measured).
- **Watch out**: `always_inline` eliminates only the call ABI; the
  int-promotion at the source-level parameter declaration is NOT
  fixed.  Closes ~17% of the K&R gap, not the full 48%.  The rest
  is genuinely a clang IR optimization gap (#158 + #160) and
  cannot be flag-worked-around at HEAD.

### Micro-corpus (synthetic patterns) — best-clang config

```
clang ... -Oz   (no production knobs)
```

- **Use for**: synthetic / pattern-isolation tests where clang's
  mid-end strengths matter (identity recognition, branchless
  boolify, LDIR-overlap, RRCA chains).
- **Don't combine with**: `+static-stack` — disables some
  mid-end narrowing on patterns we measured.

## What does NOT help (negative results)

These were tested and produced no improvement on the relevant
workload. Recorded so future sessions don't re-try them.

| Flag | Workload | Result |
|---|---|---|
| `-Os` (instead of `-Oz`) | AES | +5% bigger. Use `-Oz`. |
| `-O2` | AES | +95% bigger. Avoid. |
| `-O3` | AES | +198% bigger. Avoid. |
| `-mllvm -enable-knowledge-retention` | AES K&R repro | 0% change. No effect. |
| `-mllvm -disable-lsr` | AES K&R repro | 0% change on this shape; **+7% on full AES** (LSR HELPS u8-heavy code). Don't disable for AES; cpnos-rom production has it disabled but the choice should be re-measured. |
| `-mllvm -aggressive-instcombine` | AES K&R repro | **Flag not recognised** at ravn/llvm-z80 HEAD `0dd6f9e47330`. May exist in upstream LLVM. |
| `-mllvm -instcombine-max-iterations=100` | AES K&R repro | **Flag not recognised**. |
| `-flto` | AES K&R repro | Produces bitcode; doesn't integrate with the current ld.lld build path. Needs LTO toolchain setup before it can be evaluated. |
| `-mllvm -aggressive-ext-opt` | AES K&R repro | 0% change (this build's pass already at its default level). |
| `-mllvm -aggressive-machine-cse` | AES K&R repro | 0% change. |
| `-mllvm -enable-z80-loop-rotate` | AES K&R repro | **+34 B regression** (mc_loop 863→897). The flag is off-by-default per its help text "gates on #100"; off-by-default is correct. (Renamed from `-mllvm -z80-loop-rotate` in llvm-z80 commit `9bd19f5ac351` — old name collided with the legacy pass arg-name.) |
| `-mllvm -combiner-shrink-load-replace-store-with-store` | AES K&R repro | 0% change. |
| `-mllvm -combiner-reduce-load-op-store-width-force-narrowing-profitable` | AES K&R repro | 0% change. |
| `-mllvm -disable-postra-machine-licm` | AES K&R repro | 0% change. |
| `-mllvm -disable-postra-machine-sink` | AES K&R repro | 0% change. |
| `-mllvm -disable-machine-dce` | AES K&R repro | 0% change. |
| `-mllvm -enable-spill-copy-elim` | AES K&R repro | 0% change. |
| `-mllvm -enable-gvn-hoist`, `-enable-gvn-sink`, `-enable-newgvn` | AES K&R repro | 0% change individually or combined. |
| `-mllvm -enable-memcpy-dag-opt` | AES K&R repro | 0% change. |

## SDCC recipes (zsdcc)

### Production cpnos-rom configuration

```
zcc +z80 -compiler=sdcc -clib=sdcc_iy --opt-code-size -SO3 \
    -Cs"--sdcccall 1" -Cs"--disable-warning 296" \
    -Cs"--max-allocs-per-node 25000" \
    -Cs"--fomit-frame-pointer" \
    -create-app
```

- **AES headline**: zsdcc.bin = 3604 B (vs clang.bin 5114 B, **42% smaller**).
- **Watch out**:
  - `--sdcccall 1` only safe if NO arch-helper calls (no `x % N`
    for non-power-of-2 N, no 16-bit multiply, no division).  Use
    the `check_no_helper_calls.py` guard in cpnos-rom Makefile.
  - `-clib=sdcc_ix` produces wrong AES output (issue [ravn/z88dk#6](https://github.com/ravn/z88dk/issues/6)).  Stick with `sdcc_iy`.
  - `-Cs"--nogcse"` produces wrong AES output (issue
    [ravn/z88dk#5](https://github.com/ravn/z88dk/issues/5)).  Don't disable GCSE.

### Best size-only PASS (smaller than production by 15 B)

```
... + -Cs"--max-allocs-per-node 100000"   (100x default)
```

- **Marginal win**: −15 B over baseline 3604 B on aes256-corpus.
- **Cost**: significantly slower compile (regalloc effort 4×).
- **Use only**: for final release builds, not for iteration.

## Per-workload validated headlines

| Workload | Best clang config | Best sdcc config |
|---|---|---|
| AES-256 corpus | `-Oz -mllvm -disable-machine-licm -mllvm -disable-machine-cse -ffunction-sections -fdata-sections` → 4682 B | production flags → 3604 B (1.30× smaller) |
| cpnos-rom (BIOS/PROM-style) | production with `+static-stack` → 1928 B | production flags → 2068 B (clang wins on this shape) |
| Micro-corpus synthetic patterns | `-Oz` (no production knobs) → 115 B aes_text | production → 177 B |

## Process for adding a new recipe

1. Run `make sweep` (or manual measurement) on the corpus the
   recipe applies to.
2. Verify with `make test` that the output is functionally
   correct (esp. on AES — silent miscompiles are common with
   aggressive flags).
3. Record:
   - Exact flag string
   - Workload identifier (corpus path + config name)
   - Size delta (binary B AND aes_text B if relevant)
   - Runtime delta (tstates) if a speed claim
   - **PASS/FAIL** verification status
4. Commit with a body that lets future sessions diff the change.

## Things still open to investigate

- `-flto` with proper LLD/LTO toolchain hookup. Could close the
  K&R-callee-propagation gap (#160) if cross-TU narrowing kicks in.
- `__attribute__((always_inline))` on K&R u8 callees. Should
  eliminate the call ABI boundary entirely. Not tested yet.
- `__attribute__((flatten))` on the caller. Forces all callees
  inline. Same hypothesis as above.
- Whether upstream LLVM has `-mllvm -aggressive-instcombine` and
  whether porting it to ravn/llvm-z80 would help.
