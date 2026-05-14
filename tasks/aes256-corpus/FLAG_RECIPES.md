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

Last validated against ravn/llvm-z80 HEAD `0dd6f9e47330`,
2026-05-14.

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

### Real-world u8-heavy code — runtime + size win (clang)

```
clang ... -mllvm -disable-machine-licm \
          -mllvm -disable-machine-cse
```

- **Use for**: AES-class C code with byte locals and loop bodies.
  Validates open issue [#128](https://github.com/ravn/llvm-z80/issues/128).
- **AES headline numbers**: aes256.c text 4660 → 4329 B
  (**−7.4%**); runtime **66.1M → 31.6M tstates (−52%)**.
- **Combine with**: `-ffunction-sections -fdata-sections --gc-sections`
  for an additional ~50 B.
- **Watch out**: not validated to be a win on tight BIOS-style
  code. Re-measure cpnos-rom before adopting elsewhere.

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
