# TODO: zsdcc bench divergence — fannkuch + pi

**Status:** RESOLVED (2026-07-06).  Root cause confirmed + red-green validated (below).  Both cells are now **SKIPPED entirely** in `compiler-comparison-corpus/sweep.sh` (`SKIP_CELL`, commit `073ff82`) — it's a build-config/stdlib-ABI mismatch, not a compiler bug, so re-running adds no signal.  (Historically marked XFAIL.)

**Follow-ups filed:**
- **rc700-gensmedet#121** — optional register-arg runtime shims to restore `--sdcccall 1` coverage on these two benches (the `__modsint` shim is proven; pi needs 4 more 32-bit shims).
- **Deferred upstream (pending go-ahead):** (a) z88dk/z88dk — ships only stack-convention runtime arithmetic helpers, no `--sdcccall 1` variant; (b) retro-vault/xyz — xcc beta miscompiles fannkuchredux (unrelated, tracked as `fannkuch:xcc` XFAIL).

---

## ✅ ROOT CAUSE CONFIRMED (2026-07-06) — `--sdcccall 1` + default-convention stdlib

Both XFAILs share **one** root cause, red-green validated this session:

**The sweep builds the zsdcc lane with `--sdcccall 1` (register-arg ABI) but links z88dk's default stdlib/crt0, which is built for the default `--sdcccall 0` convention.**  The runtime arithmetic helpers therefore return their result in a register the `--sdcccall 1` caller does not read:

- **fannkuch:** `checksum += (permCount % 2 == 0) ? f : -f` — the signed `int % 2` lowers to a `__modsint` call.  The caller reads the remainder from `E`; under the mismatched stdlib that byte is `0`, so `permCount % 2` is `0` for *every* iteration.  The value emitted is unstable across surrounding code (all-`-f` = 40, all-`+f`, etc.) because the "always-0" parity feeds different branch selections after regalloc — hence the earlier confusing 40-vs-180 manifestations.
- **pi:** heavy `uint32_t` division/modulo hits the 32-bit sibling helpers (`__divulong`/`__modulong`); same return-register mismatch → the accumulator never advances → `0x0000`.

z88dk **explicitly warns** about exactly this: `warning 296: non-default sdcccall specified, but default stdlib or crt0`.  **`sweep.sh` suppresses it** with `-Cs"--disable-warning 296"`.

### Evidence (verified)
- Both benches **FAIL under `--sdcccall 1`, PASS under `--sdcccall 0`** (same compiler, clib, flags — only the ABI flag differs).  Runtime-verified via ticks exit code.
- Isolated `p % dv` (dv=2 volatile → forces `__modsint`) prints `00000000` under `--sdcccall 1` vs correct `01010101` under `--sdcccall 0` and on x86 gcc.  Fails with BOTH `-clib=sdcc_iy` and plain `-clib=sdcc`.
- asm: `call __modsint` / `pop bc` / `pop hl` / `ld a,e` — the caller reads the remainder from `E`.
- `(permCount & 1) == 0` (bitwise, no `__modsint`) computes the **correct** checksum → confirms the bug is the modulo runtime helper, not the ternary.
- **Not** signed-overflow UB: max intermediate `|checksum|` for N=7 = **269** (≪ INT16 32767).

### Not an SDCC upstream bug (inference, not runtime-verified)
Mainline SDCC 4.2.0 emits `ld de,(_dv)` / `jp __modsint` (tail-call), i.e. it *does* have a consistent internal convention; a matching-convention stdlib would compute correctly.  This is a **build-configuration mismatch** in the corpus (—sdcccall 1 with a —sdcccall 0 stdlib), which z88dk documents via warning 296 — **not** a bug to file upstream.

### Minimal repro
`compiler-comparison-corpus/zsdcc-repro/modsint_sdcccall1.c` (6-line core; prints `00000000` buggy / `01010101` correct).

### Fix options for the corpus (decision pending)
1. Switch the zsdcc lane to `--sdcccall 0` → both benches PASS (all-PASS corpus), but changes the ABI for *every* zsdcc cell (sizes/tstates shift; breaks parity with aes256-corpus `01_baseline_prod` and cross-run history).
2. Keep `--sdcccall 1` + XFAIL, now with a **confirmed** root cause instead of a guess (stop suppressing warning 296, or annotate it).
3. Build/link an `--sdcccall 1`-matched stdlib (heavy; not worth it for characterization benches).

---

## Original triage notes (2026-06-08, superseded by the confirmed cause above)

**Priority:** low.  Both benches are characterization tools, not production deliverables.  The four finishing-firmware components (rcbios, autoload-in-c, CP/NET, cpnos) work correctly under both compilers.  Picking this up only makes sense when (a) we want to clean the corpus to all-PASS as a precondition to claiming compiler-quality parity, or (b) the same bug class shows up in a production component.

**Origin:** `0ca7d3c` (2026-05-21).  Original commit added the benches noting "zsdcc divergence noted" and deferred investigation.  Documented again 2026-06-08 after the harness ED-FE-trap rewrite (`[[reference_ticks_canonical_exit_trap]]`) made the failures visible in the TSV instead of masking them behind a 200 M-counter cap.

---

## fannkuch — zsdcc returns wrong checksum

**Source:** `tasks/compiler-comparison-corpus/bench_fannkuch.c`

**Workload:** fannkuch-redux, N=7.  Adapted from the z88dk official compiler-comparison benchmark, originally from The Computer Language Benchmarks Game.

**Expected (mathematical, independently verifiable):**
- `maxFlipsCount = 16` (= 0x10)
- `checksum     = 228` (= 0xE4)
- packed: `(maxFlipsCount << 8) | (checksum & 0xff) = 0x10E4 = 4324`

**Observed (2026-06-08, sweep.sh):**

| compiler | actual | maxFlips | checksum | OK? |
|---|---:|---:|---:|:---:|
| llvm-z80 (clang `09_Oz_prod_like`) | `0x10E4` | 16 | 228 | yes |
| zsdcc (`+z80 -clib=sdcc_iy --sdcccall 1 -SO3`) | `0x1028` | 16 | **40** | NO |

The `maxFlipsCount` is correct under both compilers.  Only the `checksum` diverges.

**The suspect line** (bench_fannkuch.c:70):
```c
checksum += (permCount % 2 == 0) ? flipsCount : -flipsCount;
```
- `permCount` ranges 0..5039 (= 7! − 1) over the bench's lifetime.
- `flipsCount` is `int`, bounded by `maxFlipsCount` so 0..16.
- `checksum` is `int` (16-bit signed on Z80).

**Hypotheses (in order of likelihood):**

1. **Signed-int overflow UB.**  Worst-case |checksum| during accumulation could be `5040 × 16 = 80 640`, beyond INT16 range.  Standard C says signed overflow is UB; compilers can wrap, saturate, or assume-doesn't-happen.  If clang wraps and zsdcc assume-doesn't-happen (or vice versa), the final answer diverges even though both targets nominally use 16-bit int.

2. **zsdcc codegen bug in `(p % 2 == 0) ? f : -f`.**  Conditional-with-negation pattern.  Worth a minimized repro.

3. **zsdcc bug in `count[r-1] = r; r -= 1;` block or the inner swap.**  Less likely — `maxFlipsCount` is right, which is a function of the swap output.

**How to verify hypothesis 1:** rewrite the accumulation as unsigned (`unsigned int checksum`; `checksum += (permCount & 1) ? -(unsigned)flipsCount : (unsigned)flipsCount;`).  Unsigned wraparound is defined.  If both compilers then agree, it's UB.  If zsdcc still differs, it's a real codegen bug.

**How to verify hypothesis 2:** standalone reproducer:
```c
int test(int p, int f) {
    return (p % 2 == 0) ? f : -f;
}
```
Compile with both, check asm, run a small driver.

---

## pi — zsdcc returns zero

**Source:** `tasks/compiler-comparison-corpus/bench_pi.c`

**Workload:** spigot algorithm for π, 800 digits (`SCALE=280`, scaled down from upstream 2800 for tstate budget).  Heavy 32-bit integer arithmetic (`uint32_t d`, divisions by `(uint32_t)b`).

**Expected:** 28116 (= 0x6DD4) — captured from a clang reference run.  **Not independently verified** against any external oracle; could in principle differ from "the right answer" if clang's run had its own bug.  For triage purposes, treat clang as the de-facto oracle since zsdcc's result is unambiguously broken.

**Observed (2026-06-08):**

| compiler | actual | OK? |
|---|---:|:---:|
| llvm-z80 (clang) | `0x6DD4` (28116) | de-facto yes |
| zsdcc | `0x0000` | NO |

Zero is catastrophically wrong — the checksum accumulator never advanced from its initial 0, OR the function returned before any block was processed, OR a 32-bit operation silently produced 0 in every block.

**Hypothesis (the commit message's own guess in `0ca7d3c`):**

> "possibly --sdcccall 1 + sdcc_iy + uint32_t bug (similar to known z88dk#5/#6)"

That hypothesis is plausible — bench_pi.c uses `uint32_t` heavily, and z88dk has historical issues with `sdcccall(1)` + `sdcc_iy` clib + 32-bit arithmetic (`__umodsi3`, `__udivsi3` interactions).  **First step before deeper debug: check z88dk#5/#6 status** to see if either has landed a fix (in which case bump z88dk and retest) or has a documented repro pattern that matches.

**How to narrow:**

1. **Try `-clib=new` instead of `sdcc_iy`.**  If the bug disappears, it's a clib interaction.
2. **Try `--sdcccall 0`** (the older non-register-arg convention).  If the bug disappears, it's an ABI interaction.
3. **Add periodic `out (1), a` taps** inside the outer `for k` loop to dump partial state — see whether the loop even iterates, and whether `r[i]` ever gets a non-2000 value.
4. **Move `pi_init` inline and observe** — the original was split as NOINLINE for clang's #182 SCEV crash, but zsdcc doesn't have that crash, so the NOINLINE is a clang-only guard.  Worth a sanity check that the splitting itself isn't interacting badly with sdcc's optimizer.

---

## Upstream filing — preconditions per `[[feedback_no_local_zsdcc_fixes]]`

Both candidates require, **before any filing** (per `[[feedback_explain_before_filing]]` and `[[feedback_file_bugs_not_fixes]]`):

1. **Minimized C repro** (≤ 30 lines if possible).  Strip the bench's structure to just the failing pattern.
2. **Cross-compiler verification:** the repro must produce the right answer under x86 gcc/clang at `-O0` AND under z88dk-sccz80 (the alternative z88dk frontend), to rule out "my C is UB" as the explanation.
3. **Bisected zsdcc version:** which version started failing, if known-good earlier versions exist.  z88dk pins a specific SDCC snapshot; check the upstream SDCC bug tracker for `permCount % 2`-shaped issues.
4. **Plain-English explanation:** the user must understand the root cause well enough to defend the filing (per `[[feedback_file_bugs_not_fixes]]`) — no auto-generated bug reports.
5. **z88dk vs SDCC routing:** is this a z88dk frontend issue (zcc, clib, library) or an SDCC backend issue?  Different trackers.
6. **Per-filing user go-ahead** before posting anywhere upstream.

For fannkuch, the UB hypothesis would let us **fix the bench** (rewrite as unsigned) rather than file — close out without an upstream issue.  Try that first.

For pi, if it really is z88dk#5/#6 territory, we may not need to file at all — just link the existing issue and mark the bench XFAIL pending that bug's resolution.

## Rule applicability checklist

- `[[feedback_no_local_zsdcc_fixes]]` — these are zsdcc bugs; root-cause + repro + report upstream (or in fannkuch's case, possibly rewrite the bench to avoid UB).  No local SDCC patches.
- `[[feedback_file_bugs_not_fixes]]` — when filing, the report is a BUG (repro, current vs expected, root-cause, evidence, no proposed fix).
- `[[feedback_thorough_tests_for_upstream_bugs]]` — matrix-grade test case: minimal repro + ≥ 2 positive controls (sccz80 + x86 gcc) + ≥ 1 negative control.
- `[[feedback_explain_before_filing]]` — explain root cause in chat + per-filing user "go ahead" before any upstream post.
- `[[reference_ticks_canonical_exit_trap]]` — when re-running these for debug, the harness now reports `Ticks: N` + uses ticks exit code; no RAM dump.  Use `-iochar 1` (as I did 2026-06-08) for ad-hoc byte dumps.

## Reproduction commands (for the future-you picking this up)

```bash
cd rc700-gensmedet/tasks/compiler-comparison-corpus

# Run just one cell, with the diagnostic iochar dump re-enabled inline
# (was removed from test_main.c after capture; re-add temporarily — see
# the git history around 2026-06-08 for the exact block).
BENCH=fannkuch ONLY=zsdcc ./sweep.sh

# Or directly:
cd sweep
/Users/ravn/z80/z88dk/bin/z88dk-ticks -mz80 -iochar 1 -counter 200000000 \
    zsdcc_fannkuch.bin | xxd | head
```

Expected output bytes (current state, 2026-06-08, with iochar tap re-added):
```
zsdcc fannkuch: 28 10 e4 10 00 0a    actual=0x1028 expected=0x10E4 match=0
zsdcc pi:       00 00 d4 6d 00 0a    actual=0x0000 expected=0x6DD4 match=0
```

## XFAIL state to remove when fixed

`sweep.sh` line ~36 (`EXPECTED_FAIL=" fannkuch:zsdcc pi:zsdcc "`).  Drop the relevant entry; XFAIL becomes PASS naturally.  A regression (the cell PASSing while still in the list) will appear as `XPASS(unexpected_pass)` — investigate why before assuming the upstream fix landed.
