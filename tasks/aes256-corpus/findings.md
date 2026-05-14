# AES-256 corpus — compiler-efficiency findings

Source: <http://z80.eu/downloads/aes256.zip> — byte-oriented AES-256
by Ilya O. Levin with CP/M-compat tweaks by Peter Dassow. ~13 KB C
source; ~20 functions; exercises real-world codegen patterns
(pointer chasing through nested struct fields, 16-byte byte-buffer
loops, sequential XOR/shift/rotate, register pressure from 4-deep
round keys).

The reference `DEMO.COM` in the upstream zip is 9216 B as built by
Peter Dassow's CP/M-targeted compiler. Provenance is NOT preserved
in the zip — see "DEMO.COM provenance" section below.

## Headline (baseline configs)

| Compiler | bin B | aes256.c text B | runtime tstates | × baseline |
|---|---:|---:|---:|---:|
| **clang `-Oz`** | 5114 | 4660 | 66,121,724 | 1.00 / 1.00 |
| **zsdcc** (cpnos-rom production flags) | 3604 | 2961 | 14,185,104 | **0.70 / 0.21** |

zsdcc wins this real-world workload by **42% on size and 4.66× on
runtime**. This **reverses** the micro-corpus result in
`sccz80-oracle-corpus/findings-2026-05-13.md` where clang was 1.5×
smaller than zsdcc on synthetic patterns.

The reversal is the headline finding. The micro-corpus measured
clang's strengths (mid-end identity recognition, branchless boolify,
LDIR-overlap fill). AES is dominated by clang's weaknesses: regalloc
churn under high pressure, BSS spill traffic, the LICM+CSE
pessimization (open issue #128), and a `+static-stack` miscompile
(now filed as ravn/llvm-z80#156).

## Best PASS configs from the sweeps

### clang

| Config | bin B | tstates | vs baseline |
|---|---:|---:|---|
| `01_baseline_Oz` | 5114 | 66.1M | — |
| **`06_Oz_no_licm_cse`** | **4733** | **31.6M** | −381 B / −52.2% runtime |
| **`11_Oz_no_licm_cse_gc`** | **4682** | 31.6M | −432 B / −52.2% runtime (smallest PASS) |
| `10_Oz_no_licm_cse_lsr` | 5089 | 31.6M | −25 B / −52.2% runtime |
| `07_Oz_no_lsr` | 5480 | 66.1M | +366 B, no speed change |

The clear win: `-mllvm -disable-machine-licm -mllvm -disable-machine-cse`.
**−7.4% size + −52.2% runtime in a single flag pair.** Validates
[ravn/llvm-z80#128](https://github.com/ravn/llvm-z80/issues/128)
("MachineLICM and MachineCSE pessimize at -Oz on Z80") with
much sharper numeric evidence than the original cpnos-rom data.

Adding `-ffunction-sections -fdata-sections --gc-sections` on top
saves another 51 B (config 11). LSR helps on AES (+366 B without
it), counter to the cpnos-rom production decision to disable it —
worth re-measuring on cpnos-rom (open task).

### zsdcc

| Config | bin B | tstates | vs baseline |
|---|---:|---:|---|
| `01_baseline_prod` | 3604 | 14.2M | — |
| **`11_max_allocs_100000`** | **3589** | 14.2M | −15 B (smallest PASS) |
| `02_sdcccall_0` | 3682 | 14.2M | +78 B (stack-arg ABI cost) |
| `05_SO0` (no peephole) | 3802 | 15.4M | +198 B / +8.4% runtime |

Findings:
- **`--sdcccall 1`** is worth ~2% size over stack-arg ABI on this
  workload (smaller win than micro-corpus saw, because helper-call
  ABI mismatch isn't reached).
- **`--max-allocs-per-node 100000`** earns ~0.4% size over the
  production 25000 — diminishing returns; production setting is
  near-optimum.
- **`--no-peep`, `--all-callee-saves`, `--reserve-regs-iy`
  (keep_frame_ptr)**: byte-identical to baseline → these knobs have
  no effect on AES-shape code under production flags.
- **`-SO0`** costs ~5% size / 8% speed → peephole is real value.
- **`--opt-code-speed`** is 81 B BIGGER than `--opt-code-size`
  *and* only 1.2% faster → not a useful trade on this workload.

## Miscompile findings (filed as issues, NOT fixed)

Three real compiler bugs surfaced from the sweep:

### ravn/llvm-z80#156 — clang `+static-stack` miscompiles AES

`-Xclang -target-feature -Xclang +static-stack` produces a binary
36% smaller (3355 B aes_text vs 5114 B baseline) but at some point
during AES a `ret` pops a corrupted return address (`0x7E0C`) and
execution escapes into uninit RAM. Test never completes. Production
cpnos-rom uses `+static-stack` successfully on its own code shape;
AES is the first corpus where the flag triggers a miscompile.

If fixed, this would be a clear ~1.7 KB size win on AES-class code.

### ravn/z88dk#5 — zsdcc `--nogcse` AES miscompile (late absolute-pointer assign)

`-Cs"--nogcse"` causes silent miscompile when the source has:
```c
uint8_t *r;          /* declared early */
... aes256_encrypt_ecb(&ctx, buf); ...
r = (uint8_t *)0xC000;   /* late assignment */
r[i] = buf[i];           /* writes are dropped */
```
The function call before the late assignment is required to
trigger. Initialising `r` at declaration avoids the bug. `volatile
uint8_t *r` also masks it. Independent of `-SO`/`--opt-code-size`.

### ravn/z88dk#6 — zsdcc `-clib=sdcc_ix` AES miscompile

`-clib=sdcc_ix` with AES produces wrong ciphertext (deterministic
`20 01 3e 08 ...` instead of `8e a2 b7 ca ...`). End sentinel is
written, so execution completes — only the AES values are wrong.
Reproduces under both `--sdcccall 0` and `--sdcccall 1` with
different (still-wrong) outputs, so it's an sdcc_ix-clib codegen
issue not an ABI mismatch.

Code is also 33% larger than sdcc_iy on the same source (4163 vs
2961 B).

## Tooling findings (the ticks investigation)

`z88dk-ticks` has exactly two Z80 exit conditions (read from
`src/ticks/ticks.c`): `pc == end` or `st >= counter`. NOT HALT,
NOT `JP 0`, NOT any port output. Bare miscompiles whose escaped
PC wraps 0xFFFF→0x0000 trigger ticks's `if (pc == start) st = 0`
reset (default `start = 0x0000`), so the counter never fires —
ticks runs forever for an apparent 30s+ wallclock per binary.

**Mitigation in this corpus:** `fill_with_jp_done.py` pads each
binary with `c3 LO HI` (= `JP done_addr`) bytes from end-of-code
to 0xBFFD. Any escape into "uninit" RAM lands on a `c3`-prefixed
instruction within at most 2 fetches, jumps to `done_addr`, and
ticks exits via `-end` within a few cycles. Confirmed: turns a
30s/binary hang into a 10 ms exit on the `+static-stack` miscompile.

The fill is applied transparently in both `flag_sweep.sh` and
`flag_sweep_sdcc.sh` (between `objcopy` and `ticks`), so no source
or harness change is required.

## DEMO.COM provenance

The upstream zip's `DEMO.COM` is 9216 B. Hypothesis: HiTech 3.09
since z80.eu/c-compiler.html implies HiTech as the canonical CP/M
C compiler.

Tested: `ghcr.io/ravn/hitech` Docker (HiTech 3.09x) compile of
`aes256.c + demo.c` with `-O` produces **12581 B**, byte-different
from `DEMO.COM` starting at offset 1. So not HiTech 3.09x with
basic `-O`. Probably one of:
- HiTech with different flag combo (`-Z`, `-O1`, etc.)
- HiTech 3.09 (not 3.09x)
- BDS C, Aztec C, or another listed compiler on z80.eu

Pending task to bisect further (low priority — not blocking
anything, just curiosity).

## What we'd do next (per todo.md follow-ups)

1. **Adopt `-mllvm -disable-machine-licm -mllvm -disable-machine-cse`
   as the corpus baseline** — already in production cpnos-rom flags
   per CLAUDE.md.
2. **Re-measure cpnos-rom with LSR enabled** — AES shows LSR helps;
   production currently disables it. Worth a sweep on actual
   cpnos-rom workload before flipping the default.
3. **Add AES to the regular regression suite** — runtime tstate
   metric is a much sharper signal than size alone (the LICM/CSE
   regression would have been caught in days, not "discovered 2 years
   later in a flag sweep").
4. **Find the DEMO.COM-producing compiler** — try other HiTech flags,
   BDS C, Aztec C.
5. **Wait on the three miscompile fixes** (#156, z88dk#5, z88dk#6).

## How to interpret the sweep tables

`clang-flag-sweep.md` and `sdcc-flag-sweep.md` are checked into git.
After any compiler change, `make sweep` updates both and a
`git diff` surfaces any size or runtime regression on a specific
flag combination. PASS/FAIL column also catches correctness
regressions.
