# RC700-SYSGEN Project Timeline

## Session 73s: #112 full oracle with IY default-ON -> NOT clean (regalloc-class blockers remain) (May 25, 2026) — Medium

After the peephole fix, flipped `-z80-unreserve-iy` default ON and ran the full
oracle.  **Not shippable** -- reverted to OFF (production byte-identical).
IY-on regressions beyond the fixed loop-carried bug: **AES production target
MISCOMPILES** (deterministic C010=00); test-runner 696->694 pass (real:
test_48_dynamic_alloca FATAL all levels, test_40_hash_crc, test_38; rest is
known test_90/91 #136 noise); lit 3 codegen-shift FAILs.  Dig-in with reliable
repros (test_167_iy_crc32, test_168_iy_crc_inner) + `-print-after-all`: the crc
reduction-loop miscompile is a **register-allocation class** bug (allocator
shuffles a split 32-bit value through expensive `push iy`/`pop hl` round-trips
and corrupts it) -- the z80-late-opt copy removals there are LEGAL.  This is the
Phase-3 regalloc cost-model work #112 was always gated on; dynamic_alloca is a
separate frame-pointer class.  Loop-carried peephole fix stays shipped.
Commit `ecf6e39e6b6a`.  Filed **ravn/llvm-z80 #189** (regalloc i32-split gate)
and **#190** (dynamic_alloca); backlog task added to `unpark-2026-05-22.md`;
full writeup `session73s-issue112-iy-summary.md`.  **#192 FIXED** (commit 25656201a41d, #173 read-guard; AES + cpnos byte-identical, oracle clean); **#193** filed (separate pre-existing +static-stack Z80LateOptimization segfault on test_40 xorshift16).

**Deeper dig (instruction trace) reframed it:** the crc miscompile is an i32
select+shift+xor loop-carried-spill defect, NOT fundamentally IY.  #189 corrected
to an SP-relative-store-vs-push aliasing bug (non-static-stack).  Discovered
**#192**: the SAME loop pattern miscompiles under **`+static-stack` `-O1`/`-Os`
with IY reserved** -- a latent PRODUCTION-config bug, returns `0xB6662D3D` vs
`0x2D02EF8D`.  The test-runner never built `+static-stack`, so it was invisible;
added a `cargo run -- clang -static-stack` mode (commit `2d6ccd4`) that reproduces
it via `test_168` (`_ss`, FAIL O1/Os).  Also filed **#191** (llvm-objdump can't
auto-detect Z80 ELFs -- `ELFObjectFile::getArch` has no `EM_Z80` case; e_machine
8080 IS the correct LLVM `EM_Z80`).  New repros test_166-170.

## Session 73s: #112/#14 ROOT-CAUSED + FIXED -- IX/IY transfer peephole liveness guard (May 25, 2026) — Hard

The long-standing #14 "PUSH/POP for IY copies crashes when IY is allocatable"
finally root-caused and fixed.  Continuing the option-1 RegisterCoalescer
drill, an isolated reliable repro (`test_166_iy_shiftloop`: popcount via
`while(v){count+=v&1; v>>=1;}`, FAIL 0xFFFF at O1-Os IY-on, PASS O0/Oz) was
reduced through the test-runner oracle (NOT the unreliable DIY ticks harness).
`-print-after-all` pinned the corruption to **Z80 Late Optimizations**: the
"IX/IY transfer" peephole collapses `COPY16_PUSHPOP IY,bc ... COPY16_PUSHPOP
bc,IY` into `PUSH bc ... POP bc`, dropping the `IY <- bc` write on the
assumption IY is dead scratch.  But IY held the loop-carried i32 high word,
live-out via the back-edge, so its per-iteration update vanished -> loop froze.

Earlier hand-traces of the asm misled three times (the value is register-carried,
not slot-carried as it appeared); the MIR-pass bisection was the decisive tool,
exactly the "use the reliable oracle, not hand-reading" lesson.

Fix (commit `dfa073a23e99`): gate both peephole forms on
`computeRegisterLiveness(IXReg, after-closing-copy) == LQR_Dead`, mirroring the
existing #161 guard.  Genuine scratch transfers still fire, so production
(IY reserved, IX-only) is byte-identical.

Oracle: IY-on clang suite 684 -> **694 pass** (42 -> 38 fail); test_166 6/6.
IY-off production **696/37/56** (baseline + new test, no regression); AES corpus
byte-identical (11516046 ts; C010=01/C021=01/C022=a5; 3715 B); Z80 lit 112+5.
New lit guard `iy-loop-carried-112.ll`.  This unblocks #112 IY-unreserve: the
loop-carried residual is closed; remaining IY-on deltas are ~2 tests, down from
the original 70 regressions.

## Session 73s: #180 C2 peephole audit -- complete sweep over Z80LateOptimization (May 24, 2026) — Medium

Systematic "disable / measure / sweep / delete-or-keep" pass over the 16
"Migrate"-classified peepholes in `Z80LateOptimization.cpp`.  Outcome:
**5 deleted (~572 LOC), 11 confirmed live.**

Deleted as dead at HEAD (input shape no longer materializes after the
session-73p #128 LICM/CSE-disable + #177 TTI canonicalization changes):
#11 (ALU #imm idempotent collapse), #9 (OR A; LD r,0; JR Z -- also fixed
a latent miscompile of test_27_array_2d_Os, sweep +1 PASS), #2 (POP rr;
PUSH rr), #24 (BC ping-pong single-BB self-loop #97, ~340 LOC -- dead
because Z80LoopRotate is default-off), #23 (HL save-via-BC roundtrip #84).
Their dedicated lit tests were XFAILed with un-XFAIL conditions.

Re-tested and kept LIVE: #6, #7, #8, #10, #12, #13, #14, #16, #17, #18,
#19, #20, #21, #25, #79.  The resume after a disk-full interruption
re-tested the final four (#8 +18 B, #12 +4 B on AES; #21 and #79 AES/cpnos
byte-neutral BUT regress their dedicated lit canaries -- ISel still emits
their input shapes and each is the sole remover).

**Methodology lesson:** AES-byte-identical alone does NOT prove a peephole
dead.  The discriminator is the per-pattern lit test: it still FAILs when
a *live* byte-neutral peephole is disabled (opportunity exists), vs PASSes
for a genuinely dead one (opportunity gone upstream).

**Disk-full recovery:** a 547 MB stray z88dk-ticks register trace
(`aes256-corpus/icode_diff/ph_trace.txt`, the `feedback_docker_trace`
antipattern) had filled the volume; deleted, back to 70+ GB free.  No
campaign state was corrupted (work was committed; `.ninja_log` intact).

Production targets unchanged: cpnos PROM1 ~2028-2029 B (drift band), AES
09_Oz_prod_like .text 2228 B byte-identical, lit 109 PASS + 5 XFAIL,
test-runner sweep 990/690/37/56/207.  Commits on `session-73s`:
`4e82d95` (#8/#12/#21/#79 Keep annotations), `915b680` (audit-complete
doc), `e8f8731` (#17 conservative-keep upgraded to definitive LIVE).

**Also #181 (DAGISel/GISel coexistence audit) RESOLVED.**  Refuted the
"Z80ISelLowering.cpp is dead DAGISel code" hypothesis: there is NO
SelectionDAG path at all (no Z80ISelDAGToDAG.cpp, no SelectionDAGISel, zero
`setOperationAction`/`LowerOperation`/`SDValue`/`ISD::` in the backend).
`Z80ISelLowering` is the live shared `TargetLowering` base GISel requires
(used by Z80/SM83CallLowering, InlineAsmLowering, Subtarget) -- keep it.
Instruction selection is 100% hand-written (`Z80InstructionSelector::select`,
never delegates to the generated `selectImpl`).  SM83 shares the same GISel
selector.  Actionable cleanup: removed the dead `-gen-dag-isel` tablegen line
(Z80GenDAGISel.inc was generated but `#include`d by nothing -- vestigial from
the LLVM-MOS infra port).  `-gen-global-isel` left in place (also unused today
but conventional; flagged for discussion).  Commit `fe9a294` + roadmap Area 9 /
coherence-map updates.  Writeup: `llvm-z80/tasks/session73s-issue181-dagisel-gisel-audit.md`.

**Also #27 (per-pair 16-bit copy cost, last Cluster A item) DRILLED -> negative
result + reclassified.**  Measured the 16-bit copy population on AES: `copyPhysReg`
already uses `EX DE,HL` (1 B) optimally for dead-source DE<->HL; IX/IY copies don't
occur (always reserved -> that half gated on #38/#112).  The dominant BC/DE<->HL
traffic (~80 B on AES) is NECESSARY base-pointer re-materialization (a table base
held in BC/DE, copied to HL 2 B per `ADD HL,rr` at a different offset -- cheaper
than the 3 B reload).  Prototype peephole (retarget a dead-pair reload straight
into HL) was implemented + `.mir`-tested but instrumented to fire **0x** on AES
(14 matches, all source-pair LIVE = base reuse); reverted per the #180 "no
peephole that earns no bytes" rule.  #27 reclassified from "CopyCost tuning" to
"reduce base re-materialization under 3-pair pressure" (regalloc-level, pairs
#110/#115).  Commit `ad71a21`; writeup `llvm-z80/tasks/session73s-issue27-percopy-cost-drill.md`.

**Also #178/#166 (ADD16_tied remat) ROOT-CAUSED — Hard.**  The 73p blocker
("13/13 AES FAIL, root cause not isolated, corrupts values unrelated to the add
output") is now isolated in a **5-line repro** (`two_idx(p,i,j){return p[i]+p[j];}`).
Wired ADD16_tied behind a throwaway `-z80-add16-tied` flag and read the MIR: in the
base-reuse shape the pointer base dies at its last indexed use, where the
**RegisterCoalescer merges the GR16 base + the HLI accumulator copy + the
HLI-classed tied-def into one interval and keeps the base's physreg (BC) — OUTSIDE
the tied def's HLI class** (HLI is a proper subclass of GR16, so the join should
clamp to HLI but widens to GR16).  dst=BC then hits the BC-accumulator fallback
(`PUSH BC;POP HL;ADD HL,rr;PUSH HL;POP BC`) whose `POP HL` clobbers a `p[i]` stashed
in H — the "unrelated value corruption."  Confirmed the obvious patches fail: adding
HL to ADD16_tied Defs => "ran out of registers" (implicit HL-def collides with tied
HL-def when dst==HL); narrowing the dst class doesn't help (coalescer escapes to GR16
anyway).

**Then BUILT the non-tied fix `ADD16_acc` (in scope -- fork-local, not upstream).**
`(outs HLI:$dst),(ins GR16:$base, GR16_BCDE:$rhs)`, NO tie -> no SSA copy for the
coalescer to fold the surviving base into -> dst stays HL, base independent.
**Correctness SOLVED** (repro: both adds `ADD HL,DE`, dst=HL, no fallback; lit
`add16-acc.ll`).  **But lever exhausted:** AES09 .text 2228 -> 2447 B (+219 / +9.8%);
remat on/off byte-identical (FLAGS-clobber blocks the rematerializer -- same obstacle
as ADD_HL_rr; SSA output doesn't dodge it) + HL-pinning spikes pressure under the
3-pair file.  Kept default-OFF behind `-z80-add16-acc` (HLI class covers IX/IY ->
revisit after #112 un-reserve).  Default codegen byte-identical (AES09 2228); lit
110+5.  Writeup `llvm-z80/tasks/session73s-issue178-add16-tied-rootcause.md`.
Correction logged: "generic LLVM code in the fork" != "upstream"; the coalescer
fix is also in scope (wider blast radius), just not the path taken.

**Also #112/#38 (un-reserve IX/IY) REFRAMED via a live IY probe — Medium.**  CLAUDE.md
frames this as "Phase 3 regalloc cost-model work"; that's stale.  Env-gated un-reserve
of IY (IX left reserved) + rebuild: the session-40 "387 FATAL opcode-0 encoder crashes"
are **GONE** (lit 110+5, identical to baseline) -- the GR16NoIR/GR16_BCDE operand
discipline on all ~25 decomposing expansions (added since session 40) fixed the encoder
blocker.  Audited every decomposition site: all already use IX/IY-excluding classes.
BUT a **runtime miscompile remains**: IY-allocatable AES runs away (300M vs 11.5M tstates,
PASS sentinels never written) -- no undoc-instruction leak, so it's a control-flow/value
clobber, likely the parked #14 'y'-screen-crash class.  Prize behind it: **AES09 .text
2228 -> 2195 B (-33 / -1.5%)** + relieves the 3-pair pressure behind #27/#110/#115/#178.
Probe reverted; baseline re-verified (AES make clang.ram PASS 11.5M ts, lit 110+5).
Reframes #112 from open-ended to "isolate one IY-allocation miscompile".  Writeup
`llvm-z80/tasks/session73s-issue112-iy-unreserve-scope.md`.

**Then ISOLATED + FIXED the dominant IY bug — Hard.**  Used the test-runner as a
breadth oracle: IY-on regressed 70 tests (PASS->FAIL/FATAL).  Drilled the smallest
named repro (test_28_pointer_arith, array-of-pointers summed in a loop, returns 0x0B
vs 0x0F).  Diffed IY-on MIR/asm: `LEA_IX_FI %stack.0` with $iy dest emitted NOTHING
-> IY read uninitialized by a downstream spill.  Root cause: `LEA_IX_FI`
eliminateFrameIndex had no IY case -> `llvm_unreachable`, which in a **Release build
is a no-op** -> pseudo erased, no def emitted.  FIXED (commit `27be55e2569d`): added IY
cases to all three LEA_IX_FI branches + hidden `-z80-unreserve-iy` flag (default OFF,
production byte-identical) + lit `lea-fi-iy-112.ll`.  Test-runner IY-on **622/85/76 ->
684/42/57** (baseline 690/37/56) -- **63 of 70 regressions cleared by one fix**.
Residual 6 tests (test_04_i32_bitwise, test_40_hash_crc): i32 decomposition emits
**undocumented IYH/IYL** half-ops (BCIY-class i32 split) -- separate next-drill bug
(exclude IX/IY from i32 classes when !undocumented).  Production verified byte-identical
(flag off): AES09 2228 B, AES runtime PASS 11.5M ts, lit 111+5.  Big de-risk: #112 is no
longer "Phase 3 regalloc theory" -- it's 1 fixed missing-case + 1 known residual.

**Then drilled the residual: it's PERVASIVE, and a strategic decision.**  Tried constraining
`G_UNMERGE_VALUES` source to GR16NoIR (!undoc) -- test_04 STILL had 26 undocumented IYH/IYL
refs (8-bit ALU folds bypass it; 40+ sub-register extraction sites).  Reverted.  Crux: IY's
byte halves are undocumented (the original reason it was reserved).  Pure-16-bit IY values
(pointers/`ADD IY,rr`/load-store) are safe today (the LEA_IX_FI fix); byte-decomposed values
(i32 chunks, byte-wise logic) need EITHER **(A) +undocumented in production** (real Z80+MAME
run IYH/IYL fine; only the no-undocumented-default rule blocks it -- cheapest, needs user
policy sign-off) OR **(B) a regalloc constraint keeping IY off byte-accessed vregs** (large).
The -33 B AES win is real under either; it's an (A)-vs-(B) decision for the user.  No source
change (G_UNMERGE attempt reverted); LEA_IX_FI fix stays committed; production byte-identical.

## Session 73p Phase 2 (#184 fix): peephole #148 fall-through MBB safety check (May 22, 2026) — Hard

End state: `session-73p-issue184` merged.  #184 root cause 1 identified
+ fixed.  cpnos PROM1 -1 B as side benefit.  Second root cause filed
as ravn/llvm-z80#185.

### Codegen landed (1 commit)

`Z80LateOptimization.cpp` peephole #148 safety check tightened.  When
the branch is conditional (CP_n; JR/RET/JP cond) and the fall-through
MBB reads A (e.g. `push af` to save across CALL), the peephole used
to mis-fire because `Succ->liveins()` was stale post-regalloc.  Now
walks the fall-through MBB instructions directly via `targetDeadA`.
Also recognizes `XOR_A` (self-clear idiom) as a full def.

### Concrete miscompile (AES `aes_sb_inv` with i16=2 cost)

  inc  a            ; (was cp $FF after peephole #148 mis-fire) A=c+1
  jp   z, exit
  ... body uses C
  push af           ; saves A = c+1
  call ...
  pop  af           ; A = c+1
  dec  a            ; A = c (NOT c-1!)
  ld   c, a         ; C unchanged → infinite loop

### Production yield

  cpnos PROM1 (clang): 2028 -> **2027 B** (-1 B; 21 B free)
  Lit: 106 -> 107 PASS + 3 XFAIL (new test added)
  AES corpus baseline: byte-identical (production 2562 B unchanged)
  AES with i16=2 cost: 05_Oz_static_stack now PASS @ 11.16M ts
                      (was FAIL @ 100M ts)
  cpnos polypascal-test: PASS @ 51 s

### #184 second root cause (ravn/llvm-z80#185) — FIXED

After deeper investigation, the bug was not regalloc-level but in
the DJNZ peephole itself.  The peephole `DEC A; LD B, A; [OR A;]
JR NZ → DJNZ` dropped the LD_B_A reload, which was essential when
the body had clobbered B (via `ld c, l; ld b, h` etc.).  DJNZ
then operated on the clobbered B (high byte of pointer) → 200+
extra iterations writing zeros through bumping HL → low memory
corruption.

Fix on commit `fcce7b2c83e8` (merged via `ea3e3a0eff46`): refuse
the peephole rewrite when B is defined anywhere in the MBB between
begin() and the DEC_A.  Byte-neutral at clean baseline; 2 B cost
per fired site where the peephole correctly refuses.

With both #184 r/c 1 and #185 r/c 2 fixed, i16=2 TTI cost is now
SAFE to ship — but the production-target tradeoff still applies
(i16=2 +44 B on AES `09_Oz_prod_like` vs -362 B on `07_Oz_no_lsr`).
The decision is a tuning choice, not correctness.

### #185 verified

- AES 13/13 PASS with i16=2: 02_Os 10.86M ts, 04_O2 11.04M ts,
  05_Oz_static_stack 11.17M ts (was: ts=28 false-positives or
  100M ts timeout).
- Z80 lit suite: 107 -> 108 PASS + 3 XFAIL.
- cpnos PROM1 2028 B unchanged.
- BIOS clang 5922 B unchanged.
- cpnos polypascal-test PASS at 51 s.

### Methodology note for #185

I declared "regalloc-level fix needed" prematurely.  The deeper drill
showed the bug was in the LATE PEEPHOLE itself, not regalloc — the
peephole assumed an MIR shape (B holds counter, never redefined)
without verifying.  Five-line fix in Z80LateOptimization.cpp,
not the multi-week regalloc work I had originally estimated.

Yet another instance of the lesson: when a bug looks intimidating,
dig one level deeper before estimating.

## Session 73p Phase 2 (#173 peephole): bare-store + 4-instr A-preserving reload (May 22, 2026) — Hard

End state: `session-73p-issue173` merged to main.  Z80LateOpt peephole
catches the dominant residual bloat shape in AES static-stack code.

### Codegen landed (1 commit)

`Z80LateOptimization.cpp` adds 254-line peephole + 56-line lit test:

  ;; Before (9 B per pair):
  ld   (slot), a           ; bare store -- A held the value
  ... push hl; call; ...
  push af                  ; reload-preserving-A template
  ld   a, (slot)
  ld   r, a
  pop  af
  pop  de                  ; existing across-CALL pair tail

  ;; After (3 B per pair, saves 6 B):
  ld   r, a; push rr       ; spill via stack
  ... push hl; call; ...
  pop  de                  ; existing across-CALL pair tail
  pop  rr                  ; at stack-balanced point

Two-phase stack tracking handles matched-reloads nested inside other
PUSH/POP brackets (existing across-CALL peephole's push hl/pop de).

### Production yield (measured)

- AES `09_Oz_prod_like`: 2574 -> **2562 B (-12 B)**; ts -0.11%.
- cpnos PROM1 (clang): 2029 -> **2028 B (-1 B)**.  20 B free.
- Z80 lit: 106 + 3 XFAIL (was 105 + 3).
- AES 13/13 PASS; wider oracle byte-identical.
- cpnos polypascal-test PASS at 51.11 s.

### Investigation arc

1. First MVP scoped wrong (symmetric 4+4 same-MBB).  AES sweep byte-
   identical to baseline.  Initial conclusion "Path A doesn't fire."
2. User redirect: "reinvestigate thoroughly."
3. Programmatic catalog of 11 bare-store + 4-instr-reload pairs.
4. Implementation bailed everywhere because CALL implicit-defs
   counted as partner modifications.
5. Fix: exclude implicit defs / CALL clobbers.  aes_subBytes +
   aes_sb_inv fire; multi-reload and cross-MBB cases bail correctly.

### Methodological lessons (in issue173-investigation.md)

1. **Catalog before implementing**.  Pattern frequency in real code
   is the prerequisite, not the original issue text's yield estimate.
2. **CALL clobbers are not value-producing definitions**.  Exclude
   implicit defs from "register has been modified" checks.
3. **Two-phase stack tracking** for nested PUSH/POP brackets.
4. **The user redirect was load-bearing**.  Bisect-style depth pays
   off (same lesson as Phase B1 -> B2 earlier today).

## Session 73p Phase 2: #177 Z80 TTI -- investigation arc, ship clean cases, file #184 (May 22, 2026) — Medium

End state: `session-73p-phase2-issue177` merged to main (commit
`541b687bbecc`).  Two TTI hooks ship; one filed for follow-up;
#177 stays open with much clearer scope.

### Codegen landed (1 merged commit `e585f3301c5f`)

Three `Z80TargetTransformInfo.h` overrides:
- `prefersVectorizedAddressing=false` (Z80 has no SIMD).
- `getArithmeticInstrCost`: only `Mul -> TCC_Expensive`.
- `getCastInstrCost`: trunc i16->i8 free, zext i8->i16 free,
  sext i8->i16 = 2.

Production delta: cpnos PROM1 2030 -> **2029 B** (-1 B; 19 B free).
AES 13/13 PASS, lit 105+3, wider oracle byte-identical.

### Investigation arc

- **Phase A** -- mapped IR pass -> TTI hook usage.  Found
  MachineLICM / MachineCSE do NOT use TTI.  Retired Phase E
  (~1 wk saved).
- **Phase B0** -- predicted near-zero impact from Tier 1 hooks.
  PREDICTION WRONG.
- **Phase B1** -- ran the bundle, found miscompile in
  `05_Oz_static_stack` (100M ts timeout) + silent fails in
  `02_Os`/`04_O2`.  Parked #177.  WRONG REFLEX.
- User redirect: "i am fine with you accidentially introducing
  bugs, as long as you fix them correctly."
- **Phase B2** -- bisected the bundle in 4 cycles (~15 min each).
  Isolated to ONE line: `getArithmeticInstrCost` returning 2 for
  i16.  Shipped sibling clean cases; filed bad case as #184.

### Issues filed

- **ravn/llvm-z80#184** -- `getArithmeticInstrCost(i16)=2`
  miscompiles AES under `+static-stack`.  Reproducer + asm diff
  included.

### Methodological lessons (in Phase-B2 doc)

1. When predicting "near-zero impact" from IR cost hooks: RUN
   THE FULL ORACLE before documenting the prediction.
2. When the oracle shows a miscompile: BISECT on first failure;
   don't park.  Bisect cost ~1 hour, recovers the clean cases.

### Estimate accuracy

- Phase A: estimated ~30 min, actual ~30 min.  ✓
- Phase B0: estimated "Phase B is 2-3 days, near-zero impact".  ✗
- Phase B2 bisect: estimated ~1 hour, actual ~1 hour.  ✓

The session's larger value was process discipline, not the single
byte of production yield.

## Session 73p Phase 1: clang DOMINATES SDCC on AES production target (May 21, 2026) — Hard

End state: AES corpus production target `09_Oz_prod_like` flipped
from +23% slower / -20% smaller to **-11% faster / -23% smaller**
vs SDCC.  All 13 AES corpus configs are now faster than SDCC by
4.8-11%; 4 of 13 are also smaller than SDCC.

### Codegen landed (3 commits)

1. **#179 P1** (`4f5562c99228`) — new `Z80ReorderTestDec` pre-RA
   pass.  Rewrites `LD_A_R; DEC_A; LD_<r2>_A; LD_A_R; OR_A; JR_Z`
   to `LD_A_R; SUB_n 1; LD_<r2>_A; JR_C`.  -5.1% AES ts.
2. **#179 P2** (`6820930cc156`) — extends same pass.  Rewrites
   `LD_A_R; ADD_A_A; LD_<r2>_A; LD_A_R; RLCA; JR_C/NC` by dropping
   the redundant `LD_A_R; RLCA` (ADD_A_A's carry suffices).
   Additional -23.9% AES ts.  **This is where the production
   target flipped to dominate SDCC.**
3. **#128** (`7d5b4e5ea86c`) — `Z80PassConfig` disables
   `EarlyMachineLICM` + `MachineLICM` + `MachineCSE` globally.
   Default `-Oz`: -281 B AES.  Closes ravn/llvm-z80#128.

### Infrastructure landed

- New `rc700-gensmedet/tasks/compiler-comparison-corpus/` (wider
  oracle, mirrors AES corpus pattern).  3 z88dk-official
  benchmarks ported: sieve, fannkuch, pi.
- New lit tests: `issue-179-test-then-dec.ll`.
- `Z80ReorderTestDec.{h,cpp}` pre-RA MIR pass.
- Reset stub BSS-zero workaround for ravn/llvm-z80#182.

### Issues filed Phase 1 (10 total)

- **#173** — 8-bit BSS spill peephole (open)
- **#174** — gf_log/gf_alog redundant reload (effectively closed
  by #179)
- **#175** — Missing 8-bit ALU with memory operand (revised:
  only `(IX+d)`/`(IY+d)` forms missing)
- **#176** — Auto-infer +static-stack safety per-function (open)
- **#177** — No Z80-specific TargetTransformInfo (meta-fix, open)
- **#178** — Pseudos with implicit physreg outputs (open)
- **#179** — GISel + scheduler $a-chained reorder (closed by
  Z80ReorderTestDec)
- **#180** — Z80LateOptimization peephole audit tracker (open)
- **#181** — DAGISel vs GISel coexistence audit (open)
- **#182** — LLVM ScalarEvolution capacity overflow on init+reader
  loop pattern (NEW high-priority upstream-LLVM bug, open)

### Strategic documents

- `llvm-z80/tasks/aes-speed-gap-analysis.md`
- `llvm-z80/tasks/all-modes-competitive-plan.md`
- `llvm-z80/tasks/structural-deficiency-survey.md`
- `llvm-z80/tasks/issue174-implementation-plan.md`
- `llvm-z80/tasks/session73p-summary.md` (early session)
- `llvm-z80/tasks/session73p-phase1-summary.md` (this milestone)

### Value oracle preserved

All Decision E gates green after each commit:
- Z80 lit: 106 PASS + 3 XFAIL (+2 new tests this Phase 1)
- AES corpus: 13/13 PASS, byte-exact verifier
- compiler-comparison-corpus: sieve + fannkuch + pi PASS
- test-runner clang: 681/46/56/207 baseline maintained
- cpnos PROM1: 2030/2048 B (unchanged from session start)

### Estimates vs reality

- #179 plan estimated 1.5 M ts saved.  Actual P1+P2 combined:
  ~4.1 M ts (3× HIGH).  P2 fired on far more shapes than just
  gf_alog -- the bit-7 test idiom is everywhere in AES.
- #128 estimated -320 B at -Oz default.  Actual: -281 B
  (12% low).
- #173 and #175 estimates were too high; both turned out smaller
  than my speed-gap analysis suggested (clang already uses (HL)
  ALU fusion in +static-stack mode; the missing forms are
  `(IX+d)` only).

### Difficulty: Hard

Each fix required substantial pattern analysis BEFORE
implementation per the "do it right" directive.  TDD discipline
(write failing lit test first) caught one near-miss correctness
bug in #179 (the I2-destination-vreg safety gate).  The full
Decision E oracle gating discovered a side-effect on cpnos PROM1
(+1 B post-P2, recovered by #128).

The Hard parts:
- Recognizing #179's fix layer was pre-RA MIR pass, not
  late-opt peephole (per project_z80_backend_unfinished).
- Diagnosing why my P1 worked in single-PHI lit tests but not
  on multi-PHI gf_alog shape (regalloc pressure interaction).
- The I2-destination-vreg safety gate (caught
  issue-132-bss-spill-cross-mbb.ll regression before commit).

### Phase 2 next-best-steps

In yield-per-session-hour order:
1. **#173** — BSS spill peephole (~3-4 h)
2. **#175 (IX+d) form** — 16 missing instructions (~1 day)
3. **#176 auto-static-stack** — closes default-Oz size (1-3 wk)
4. **#177 Z80 TTI** — meta-fix (1-2 wk)
5. **#172 A-pin liveness** — residual ts gap (smaller now)



End state: three lines of investigation, each ending with a
documented negative result rather than a landed fix.  One new
high-yield issue surfaced from the analysis.  Net codegen change is
zero; net artifact is documentation density (3 commits, 1 new issue,
2 existing-issue comment updates) so future drillers don't repeat
the dead-ends.

### Investigations

1. **#172 A-pin scope tightened** — segfault from 73o gone; pin=on
   still net negative (+24 to +81 B on safe cases); default stays
   OFF.  Real fix needs LiveIntervals + PHI walk to pin loop
   carriers, not proxies.  (Commit `862321520547`, AReg infrastructure
   preserved.)

2. **#166 ADD_HL_rr remat dead-end** — direct attempt is impossible.
   `ADD_HL_rr` has no SSA output (HL implicitly defined via
   `Defs = [HL, FLAGS]`), so `isReMaterializable` is silently
   ignored.  AES corpus byte-identical with the flag set.  In-place
   comment in `Z80InstrInfo.td` prevents re-attempt.  (Commit
   `34b1732266c4`.)

3. **#166 ADD16_tied wire-up at G_PTR_ADD** — two routes tried.
   - `$dst` GR16: BC/DE fallback in expansion clobbered HL undeclared.
     All 13 AES configs FAIL.
   - `$dst` HLI (BC/DE fallback removed): still miscompiles.  13/13
     AES FAIL, test-runner 173/990 FAIL (vs baseline 46), 4 lit
     regressions.  Root cause: unisolated tied-operand regalloc
     interaction.
   In-place comment at the call site captures both failure modes for
   future.  (Commit `8400050dd2bf`.)

### New issue filed

**ravn/llvm-z80 #173** — 8-bit BSS spill via A goes through a 6 B
`push af; ld a, r; ld (nn), a; pop af` shape because Z80 has no
`LD (nn), r8` except for A.  PUSH/POP-pair peephole (when partner
half is dead) saves 4 B per spill; mixed-mode BSS (8-bit via IX,
16-bit via direct) saves 3 B.  ~15+ instances per parallel-XOR
function (`aes_mc_inv`, `aes_mixColumns`, `aes_subBytes`).
Estimated 100-200 B saving across AES corpus.  Highest-yield-per-
session-hour open lever.

### Verification

| Oracle | Result |
|---|---|
| Z80 lit suite | 104 PASS + 3 XFAIL (unchanged) |
| AES corpus | 13/13 PASS (byte-identical baseline) |
| test-runner clang | 681/46/56/207 (baseline noise band) |
| AES verifier 4 cells | PASS (K&R + ANSI × clang + zsdcc) |

No regressions in defaults; no codegen change.

### Open levers ranked by likely yield-per-session-hour

1. **#173 — 8-bit BSS spill peephole** (NEW this session)
2. **#170 — Z80NarrowIV parallel-phi guard removal** (narrow scope)
3. **#166 — ADD16_tied MIR-after-two-addr diagnosis**
4. **#172 — A-pin liveness-aware version** (~5 pp yield bounded)
5. **#169 — LSR + backend miscompile root-cause** (multi-session)

### Files (llvm-z80)

  - `llvm/lib/Target/Z80/Z80PinAluAccumulator.cpp` — scope rewrite
  - `llvm/lib/Target/Z80/Z80InstrInfo.td` — ADD_HL_rr comment
  - `llvm/lib/Target/Z80/Z80InstructionSelector.cpp` — ADD16_tied
    dead-end comment at G_PTR_ADD call site
  - `llvm/tasks/session73p-issue172-conservative-scope.md` — #172 log
  - `llvm/tasks/session73p-summary.md` — umbrella session summary

### Difficulty: Medium

No single difficult crux — three small drills, each ending honestly.
The Hard moment was the second ADD16_tied route (HLI-restricted)
catastrophically failing despite the obvious fix to the first route
— established that the real ADD16_tied wire-up needs MIR-after-two-
addr inspection, not just operand-class tweaking.

The Easy parts: the conservative #172 rewrite, the #166 ADD_HL_rr
no-SSA-output diagnosis (5 min), the aes_mc_inv inspection that
surfaced #173.

## Session 73p (initial): #172 A-pin scope tightened -- segfault gone, default still OFF (May 21, 2026) — Easy

[OBSOLETED by the umbrella entry above; preserved for commit-history
continuity since the initial session-73p commit referenced this.]

End state: `Z80PinAluAccumulator` rewritten with a strict per-MBB
invariant -- pin only vregs whose single-MBB liveness puts them in a
candidate bucket of size 1 within that MBB.  Multi-candidate blocks
(the parallel-XOR shape in aes_mixColumns / aes_subBytes that
segfaulted in 73o) are skipped entirely.

### Result

Segfault on `05_Oz_static_stack` from 73o is gone.  AES corpus
13/13 PASS with pin both on and off.  But pin=on still **regresses**
even on the safe single-candidate cases:

| Config              | Δbin | Δts    |
|---------------------|-----:|-------:|
| 01_baseline_Oz      |  +61 | +0.19% |
| 05_Oz_static_stack  |  +81 | +0.36% |
| 09_Oz_prod_like     |  +24 | +0.02% |

Compared to 73o's +261 B / +3.8 % on 01, the regression is ~4× smaller
and the crash is gone, but the metric is still wrong-direction.

### Why even the safe case loses

Pinning a short-lived proxy vreg to AReg forces a materializing `LD A,
source_reg` upstream that greedy was previously eliding by routing the
proxy's allocation to share the source's physreg.  The savings from
collapsing the round-trip don't cover the new mandatory LD.  Pinning
proxies isn't enough; the carrier (PHI cycle) is what needs to live in
A.

### Path forward (#172 stays parked)

Real fix is the same as 73o flagged: MachineLoopInfo + LiveIntervals +
PHI walk to pin the loop carrier interference-free.  Not landing this
session.  Other levers (#166 HL remat, #169 LSR root-cause, #170/#171
narrow guards) likely higher-yield per session.

### Verification

  - Z80 lit: 104 PASS + 3 XFAIL unchanged.
  - AES corpus 01/05/09: PASS both pin=on and pin=off.
  - z80-utils test-runner clang suite: 681 PASS / 46 FAIL / 56 FATAL /
    207 SKIP -- matches recent baseline (default-off, no codegen
    change).

### Files (llvm-z80)

  - `llvm/lib/Target/Z80/Z80PinAluAccumulator.cpp` -- per-MBB scope
    rewrite (uniqueRefMBB + DenseMap bucketing); updated comments
    with the 73p empirical result.
  - `llvm/tasks/session73p-issue172-conservative-scope.md` -- log.

### What was Easy / Hard

**Easy**: switching to per-MBB bucketing.  ~30 lines.  Builds clean,
fixes segfault.

**Medium**: A/B-confirming the regression persists.  Quick targeted
sweep on 01/05/09 (~60 s) showed +24 to +81 B even on safe cases.
Negative result is the artifact.

**Honest**: stopping here rather than building the full liveness-
aware version on speculation.  73o + 73p together establish that
proxy-pinning isn't the answer regardless of safety scope.

## Session 73o: #172 A-shuttle drilled -- structural infrastructure landed (default off) (May 21, 2026) — Medium

End state: ravn/llvm-z80 adds new `AReg` single-register class + new pre-RA pass `Z80PinAluAccumulator`, commit `2c4627c80ef1`.  Default OFF pending a liveness-aware selector.  Targets the dominant residual SDCC speed gap on AES: clang routes XOR/AND/OR chains through A via `ld a, r; OP; ld r, a` round-trips while SDCC keeps the accumulator in A directly (4 ts vs 12 ts per ALU op).

### What landed

1. **#172 filed** with the MIR pattern, the SDCC asm comparison, and four fix paths.
2. **Hint attempt** in `getRegAllocationHints`: fires correctly, greedy regalloc ignores it.  Reverted.  Confirms the existing comment at `Z80RegisterInfo.cpp:1891` that hints don't move the allocator on this path.
3. **Structural attempt**: new `AReg` class containing only A, new `Z80PinAluAccumulator` MachineFunctionPass that rewrites GR8 vregs matching the ALU accumulator chain pattern to `AReg`.  Mirrors `Z80SplitDjnzCounters` (the documented #99 workaround for the same regalloc gotcha at i16 width).
4. **Default OFF** -- first-implementation pins too aggressively without interference checks.  AES `01_baseline_Oz` regressed +261 B / +3.8 % ts, `02_Os` +285 B / +3.9 % ts, `05_Oz_static_stack` segfaulted during regalloc.  The pass works correctly in isolation (`gf_alog_mini` chain collapsed in A) but breaks when multiple accumulators have overlapping live ranges.

### What's needed for default-on (#172 follow-up)

A liveness-aware selector that:
1. Uses MachineLoopInfo to find natural loops + their headers / latches.
2. Uses LiveIntervals to check for overlap with already-pinned vregs.
3. Walks PHI cycles to identify the full accumulator chain (not just the COPY-boundary vregs).
4. Picks ONE primary accumulator per loop via use frequency.

Estimated 200-400 lines.  Multi-session work.

### SDCC-gap status snapshot

Post-#168 + post-Z80NarrowIV, on the AES production target:

| | clang `09_Oz_prod_like` | SDCC `01_baseline_prod` | gap |
|---|---|---|---|
| size | 2667 B | 3323 B | clang **-20 %** |
| tstates | 14,887,472 | 12,080,289 | SDCC **-18.9 %** |

Breakdown of the residual 2.8M ts clang lag (suspected):

- A-shuttle (#172): ~1.5M ts (~5 pp)
- Other regalloc churn (#27, #115): ~0.8M ts (~3 pp)
- Per-function gaps (aes_mc_inv +549 B, etc.): ~0.5M ts (~2 pp)

### Verification

  - Z80 lit: 104 PASS + 3 XFAIL unchanged (default-off = no codegen change).
  - AES corpus: 13/13 PASS (default-off).
  - z80-utils test-runner: not re-checked (default-off = same as no pass).

### Files (llvm-z80)

  - `llvm/lib/Target/Z80/Z80RegisterInfo.td` -- new `AReg` class.
  - `llvm/lib/Target/Z80/Z80PinAluAccumulator.{h,cpp}` -- the pass.
  - `llvm/lib/Target/Z80/Z80TargetMachine.cpp` -- pipeline hook.
  - `llvm/lib/Target/Z80/Z80.h` + `CMakeLists.txt` -- registration.
  - `llvm/tasks/session73o-issue172-a-pin.md` -- full investigation log.

### Commits (llvm-z80 main)

  - `2c4627c80ef1` -- AReg + Z80PinAluAccumulator (default off)
  - `6a6f38255608` -- session 73o summary

### What was Easy / Hard

**Easy**: filing #172.  The asm comparison wrote itself.

**Easy**: the hint experiment.  Confirmed negative result in 30 min.

**Medium**: implementing the structural pass.  Mirroring `Z80SplitDjnzCounters` made the scaffolding straightforward.

**Hard**: pattern detection for the accumulator chain.  First try required both COPY-to-A and COPY-from-A on the SAME vreg; fires zero times because chains have separate vregs at the boundaries.  Relaxed to either-side; pins partial chains, leaves the PHI carrier in a non-A reg.

**Painful**: the segfault on 05.  No diagnostic.  Backing out to default-off was correct.

## Session 73n: Z80NarrowIV pass lands default-on -- closes #77 fix path 1 (May 21, 2026) — Medium

End state: ravn/llvm-z80 ships a target-specific `Z80NarrowIV` IR pass that narrows i16 loop counters to i8 when SCEV proves the unsigned range fits in [0, 255].  Merged to main as `bbcc6f6047c3` from branch `session-73n-issue77-peephole`.

Two conservative guards make default-on safe:

1. **After-LSR placement**: pass invoked from legacy-PM `Z80PassConfig::addIRPasses` AFTER `TargetPassConfig::addIRPasses()` (which is where LLVM core's `LoopStrengthReduce` is added).  LSR runs first, our narrowing runs second -- prevents LSR from rewriting our narrowed phi into a "shift-by-1" form that the Z80 backend mishandles (carrier register preserved across CALL ends up off-by-one, infinite loop).
2. **Single-phi-header gate**: skip any loop whose header has > 1 phi.  Parallel `phi i8` + `phi i16` IVs in `main` verifier loops (test_94) silently miscompile when only the i16 phi is narrowed -- regalloc/coalescer handles two `i8` phis differently from `i8 + i16`.

### Verification (default-on vs default-off, 13-config AES sweep)

| Config | Δ bin | Δ tstates | Notes |
|---|---:|---:|---|
| `07_Oz_no_lsr` | **-148 B** | **-129,888 (-0.84 %)** | narrowing fires + helps |
| `09_Oz_prod_like` (production target) | **-12 B** | +5,214 (+0.04 %) | size win, tstates in noise band |
| `10_Oz_no_licm_cse_lsr` | -22 B | -12,706 (-0.08 %) | small win |
| 10 other configs | 0 | 0 | unchanged |

  - **z80-utils test-runner clang**: 681 / 46 / 56 / 207 (exact baseline match).
  - **Z80 lit**: 104 PASS + 3 XFAIL (unchanged).
  - **cpnos clang PROM1**: 2031 B / 17 B free under 2 KB hard cap (within build-date drift of the 2030 B baseline).  polypascal-test PASS 51.05 s.
  - **AES 13 / 13 PASS**.

### Three open issues stay as fix-later trackers

The guards are workarounds, not root-cause fixes -- the underlying regalloc/backend bugs still exist and would fire if a user disabled the guard.  Each issue has the relevant reduction-hint + comment trail:

  - **ravn/llvm-z80#169** -- Backend miscompiles narrowed-then-rewidened IV loops with CALL in body (LSR-corruption shape).  Tried standalone reduction; bug doesn't reproduce outside the full AES context.  Worked around by after-LSR placement.
  - **ravn/llvm-z80#170** -- Z80NarrowIV miscompiles parallel `phi i8` + `phi i16` loops.  test_94 silently wrong DE bits at O1/O2; timeout at O3/Os/Oz.  Worked around by single-phi guard.
  - **ravn/llvm-z80#171** -- Z80NarrowIV times out test_96 IY-spill loop.  Also parallel-phi shape.  Same guard.

### Honest assessment of #77 closure

The original #77 comment proposed a post-RA `ld a,r; or a; jr nz` -> `dec r; jr nz` peephole.  Investigation (session 73n start) showed that peephole would fire on **zero** instances in current AES/cpnos output -- the patterns always have flag clobbers between dec and test.  Retracted as a comment on #77.

The IR-level IV narrowing (Fix path 1 from that retract comment) IS the right tool: it targets the dominant Pattern A (`dec bc` 16-bit flagless) directly by replacing it with a flag-setting `dec c`.  Z80NarrowIV ships that.

Closes #77 in spirit; the structural transform works.  Residual SDCC gap on AES is **regalloc A-register churn** (Pattern B / C, tracked separately by **#89** + **#27**), not anything that loop-level IV narrowing can solve.

### Files (llvm-z80)

  - `llvm/lib/Target/Z80/Z80NarrowIV.{h,cpp}` -- new pass (377 + 38 lines)
  - `llvm/lib/Target/Z80/Z80TargetMachine.cpp` -- legacy-PM hook in `addIRPasses` AFTER LSR
  - `llvm/lib/Target/Z80/CMakeLists.txt` -- build
  - `llvm/lib/Target/Z80/Z80.h` -- initialize hook
  - `llvm/tasks/session73n-issue77-peephole-investigation.md` -- full bisection trail

### Commits (llvm-z80 main)

  - `95f0951f27d8` -- initial Z80NarrowIV pass (default off, exposed downstream bugs)
  - `c022023f91be` -- legacy-PM after-LSR placement (closed #169 path)
  - `12f2fd8c1aec` -- single-phi-header guard + default ON (closed #170 + #171 paths)
  - `bd4217c4db86` -- AES tstate regression check recorded
  - `bbcc6f6047c3` -- merge --no-ff to main

### What was Easy / Hard

**Easy**: identifying LSR as the corruptor.  Single bisect pass over `-disable-machine-licm / -disable-machine-cse / -disable-lsr` cleanly fingered LSR.

**Easy**: the single-phi-header guard.  Once I had the test_94 failure shape (parallel `phi i8` + `phi i16`), the guard was 5 lines and fully fixed both test_94 and test_96.

**Medium**: deciding NOT to root-cause the underlying bugs.  Tempting to keep digging since the bugs are real and the guards are conservative -- but the workarounds cleanly unblock the AES wins, and each underlying bug is its own session.

**Hard**: standalone reduction for #169.  Spent ~30 min trying to reduce the AES `aes_subBytes` failure to a minimal C / IR repro; the bug only manifests in the full pipeline (probably needs inlining, multiple loops competing for registers, or specific data layout).  Filed without a reduced repro.

**Painful**: the test_94 / test_96 silent miscompile during the default-on attempt.  AES verified clean, but the test-runner suite caught 15 regressions.  Caught only because I ran test-runner separately; would have been a real production bug if AES alone had been the gate.  Lesson: never trust a single oracle for default-on flips of a codegen pass.

## Session 73m: #168 SimplifyCFG cost-gate lands; #77a guards refined; SDCC AES gap dissected (May 21, 2026) — Medium

End state: ravn/llvm-z80#168 closed by a 12-line cost-gated bailout in
`foldTwoEntryPHINode` (commit `cd2a2ace8754`).  Every `xor 27` in AES
hot paths is now reached only via a taken conditional branch — the
branchless-XOR pattern from #167 is fully eliminated.  AES
`09_Oz_prod_like` clang 2695 → **2679 B**, tstates 15.05M → 14.88M
(−1.1% global, −16 B / −167 K ts at the production target).  cpnos
clang PROM1 within 18 B of the 2 KB hard cap (2030 / 2048).
`experiment-cpnos-prom-4k` merged back to main; `CPNOS_PROM1_CAP`
reverted to 2048 B.  cpnos-polypascal-test PASS 51.69 s; z80-utils
test-runner clang suite 681/46/56/207 unchanged.

Headline framing question for the session: **"are clang as fast as
SDCC now?"** → No, still 19% slower.  clang `09_Oz_prod_like`
2679 B / 14.88M ts vs SDCC `01_baseline_prod` 3323 B / 12.08M ts —
clang **19% smaller**, **19% slower**.  Gap dissected via per-instr
counting on `_gf_alog`: the residual 24 ts/iter (37% per-iter) is
**A-register churn from regalloc**, not pattern recognition.
Tracked by:

  - **#77** — 8-bit `dec r; jr nz` instead of `ld a,r; dec a; ld r,a; ld a,r; or a; jr nz`
  - **#89** + **#27** — broader regalloc cluster (A-shuttle, copy cost)

Per-iter decomposition posted on #167 with the side-by-side asm so
future readers don't expect the SimplifyCFG fix alone to recover the
full +38% headline regression.

**#77a rotation default-on attempt** (commit `5118ca7b97b7`): added
CALL-skip + min-trip-count (≥8) guards to `Z80LoopRotate.cpp`,
briefly flipped default on to measure.  Results mixed: cpnos −4 B,
AES prod-like −2.2% tstates, but AES `01_baseline_Oz` regressed
**+11% tstates** (size recovered, speed didn't).  Per-iter math on
`gf_alog` shows rotated form is 4 ts cheaper, so the +11% lives in
another function (`aes_mixColumns` / `aes_mc_inv` suspected,
LICM/CSE-touched header).  Diagnosed but not isolated.  Default
stays off; guards land regardless because they make manual opt-in
safer.  Comment on #100 records the measurements + the cleaner
alternative path (post-RA `ld a,r; or a; jr nz` → `dec r; jr nz`
peephole, surgical, no LICM interaction risk).

### Files touched (llvm-z80)

  - `llvm/lib/Transforms/Utils/SimplifyCFG.cpp` — cost gate
  - `llvm/lib/Target/Z80/Z80LoopRotate.cpp` — guards + documentation
  - `llvm/test/CodeGen/Z80/issue-167-branchless-conditional-xor.ll` — XFAIL test
  - `llvm/test/CodeGen/Z80/issue-77a-loop-rotate.ll` — commentary refresh
  - `llvm/tasks/session73m-summary.md` — session summary

### Files touched (rc700-gensmedet)

  - `cpnos-in-c/Makefile` — `CPNOS_PROM1_CAP ?= 2048` (revert
    `experiment-cpnos-prom-4k`'s 4 KB experiment)
  - `tasks/timeline.md` — this entry

### Commits

  - llvm-z80 `cd2a2ace8754` — SimplifyCFG cost-gate (#168 / refs #167)
  - llvm-z80 `5118ca7b97b7` — Z80LoopRotate guards (refs #77 / #100)
  - rc700-gensmedet `dec28de` — cpnos cap revert
  - rc700-gensmedet `71c131f` — experiment branch `--no-ff` merge to main
  - workspace `efb1ee3` / `423c88c` — banner removed + submodule bumps

### What was Easy / Hard

**Easy:** diagnosis.  Per-instr counting on `_gf_alog` made the
SimplifyCFG-vs-regalloc split obvious within ~20 minutes.

**Easy:** the #168 patch.  12 lines, threshold `Cost > TCC_Free`
(not `TCC_Basic` which would silently miss the gf_alog case
because the XOR has `Cost = 1 = TCC_Basic`).

**Medium:** the cost-gate threshold choice.  Initial blanket
bailout (672f24188ca8) regressed cpnos +23 B; #168 form is +5 B.
Difference is the threshold; same callsite.

**Hard:** the #77a rotation +11% regression.  Per-iter math
predicts a *win*; sweep measures a *loss*.  The function actually
costing the tstates wasn't isolated this session — handed off as
a #100 comment.

**Painful:** instrument debug.  Two false starts on the cost-gate
investigation (DEBUG output via stderr produced 0 firings even
though the fix was firing) — root cause was a stale `git stash
pop` re-introducing a separate blanket-bailout patch.  Resolved
via `git diff` to inspect actual file state.

## Session 73l-fix: SDCC K&R REGPARM-preserve patch closes ravn/z88dk #5, #6 (K&R), #14 (May 21, 2026) — Medium

End state: a ~10-line patch to SDCC's \`mergeKRDeclListIntoFuncDecl\`
(in \`src/sdcc-build/src/SDCCsymt.c\`) closes three open ravn/z88dk
bugs in a single change.  K&R AES sweep now matches ANSI sweep
byte-for-byte across all 13 configs.

### Root cause

SDCC's \`processFuncArgs\` runs on a K&R function definition while
the parameter still has its default int type (per K&R rule).  It
calls \`port->reg_parm\` which returns argreg=1 for size-2 pointer
args under \`--sdcccall 1\`, and sets \`SPEC_REGPARM(parLoop->etype) = 1\`.

Then \`mergeKRDeclListIntoFuncDecl\` walks the K&R parameter
declaration list and REPLACES \`parLoop->type\` and \`parLoop->etype\`
with the K&R-declared type's pointers (e.g., \`ctx_t *\`).  The
REGPARM flag was on the now-orphaned int etype, NOT on the new
etype.

Downstream \`geniCodeReceive\` (SDCCicode.c:3815) queries
\`IS_REGPARM(args->etype)\` on the new etype, sees false, emits no
RECEIVE iCode.  Function body emits stack-args reads
(\`ld c,(ix+4); ld b,(ix+5)\`) regardless of \`--sdcccall 1\`.

When ANSI callers in other TUs see only the function's ANSI
prototype, they emit register-args calls.  Cross-TU ABI mismatch.

### Fix

In \`mergeKRDeclListIntoFuncDecl\`, save \`SPEC_REGPARM\` and
\`SPEC_ARGREG\` before the type replacement and restore them on
the new etype (and \`sym->etype\`) afterwards.

Patch saved as \`src/zsdcc/sdcc-kr-regparm-preserve-z88dk.patch\`
in the local z88dk fork (commit \`57a9a8f2\`).  Bin replaced in
\`bin/z88dk-zsdcc\` after native rebuild.

### What was Hard

- The original #5 description ("writes through r are dropped") was
  a misdiagnosis.  Three rounds of issue updates before the trace
  showed the writes actually happen and a LATER call clobbers same
  memory.  Saved by full \`-trace\` capture (10M lines) and grep for
  PC=0x0D2A (the zeroing instruction).
- Single-function isolated repro is impossible — the bug only fires
  when the caller TU sees only the ANSI prototype.  Resolved by
  building a 2-file repro with separate caller / callee TUs.
- Three SDCC code sites (SDCC.y, SDCCsymt.c \`processFuncArgs\`,
  SDCCsymt.c \`mergeKRDeclList\`) all touch K&R handling.  Took
  per-pass \`fprintf\` instrumentation + rebuild to confirm WHICH
  ran in what order and where REGPARM got lost.
- Initial fix hypothesis (PFA called BEFORE merge) was correct, but
  the print-debug showed PFA ran TWICE for the same function before
  merge.  Both runs marked REGPARM on the same (about-to-be-replaced)
  etype.  Merge ran AFTER both and clobbered the marks.

### Sweep impact (K&R AES, post-fix)

\`\`\`
                            pre-fix         post-fix          delta
01_baseline_prod K&R    3604 / 14.19 Mts   3323 / 12.08 Mts   -7.8% size, -14.9% runtime
08_nogcse        K&R    3711 / 14.20 Mts F 3368 / 12.08 Mts P FAIL -> PASS  (#5)
09_clib_ix       K&R    4793 / 31.90 Mts F 4579 / 12.32 Mts P FAIL -> PASS  (#6 correctness)
\`\`\`

K&R now matches ANSI byte-identical on every config.  The original
"K&R int-promotion penalty" (#14) was the stack-args overhead, not
a separate int-promotion issue.

### Memory rule extractable

When tracing apparent codegen bugs: instrument all upstream and
downstream passes, not just the one closest to the symptom.  Per-pass
\`fprintf\` of \`getenv ("DEBUG_X")\` lets one rebuild + run repeatedly
without code-stream changes.

### Issues closed in local toolchain

- ravn/z88dk#5 — root-caused, FIX-CONFIRMED comment posted.
- ravn/z88dk#6 — K&R correctness half FIXED, size bloat half left
  as separable concern.
- ravn/z88dk#14 — FIXED (was the same root cause as #5).
- ravn/z88dk#15 — already landed in #73l (cosmetic version banner).

The size-bloat half of #6 (sdcc_ix is 38% larger than sdcc_iy)
remains and should be re-filed as its own issue or left as a
known quality gap.

## Session 73l: AES corpus full 4-cell sweep + ravn/z88dk K&R-only finding (May 20, 2026) — Easy

End state: AES-256 corpus now measures all four combinations of
{clang, zsdcc} × {K&R, ANSI} on its 13-config flag sweep.  Previous
"K&R-only" coverage left three of four cells unmeasured; this
session filled them in and surfaced a major reframing of the
corpus headline numbers plus a new SDCC quality issue and a
K&R-only re-classification of two existing SDCC correctness bugs.

### What landed

- **Sweep scripts parameterized** (`AES_SRC`, `TSV_NAME`,
  `MD_NAME`, `MD_TITLE_SUFFIX` env vars; defaults preserve K&R).
  Both `flag_sweep.sh` and `flag_sweep_sdcc.sh` accept the same
  knobs.  Two new committed markdown tables: `clang-flag-sweep-ansi.md`
  + `sdcc-flag-sweep-ansi.md`.
- **`findings.md` rewritten**: headline 4-cell matrix replaces
  the stale pre-session-73b table; Best-PASS tables rebuilt with
  post-S3' numbers for both variants; z88dk issue table notes
  both bugs are K&R-only; old "What we'd do next" pruned.

### Headline reframings

1. **Apples-to-apples reversal.**  Comparing smallest-PASS to
   smallest-PASS rather than zsdcc-tuned vs clang-baseline, clang
   is **20-25% smaller** on AES (K&R 2695 vs 3589; ANSI 2636 vs
   3323).  The "zsdcc wins 1.29×" line was apples-to-oranges.
2. **Runtime ratio collapsed.**  Old documented 4.65× clang
   slowdown is post-S3' down to 1.07-1.28×.  zsdcc is still
   faster on tstates, but as a percentage gap not a multiplier.
3. **SDCC K&R int-promotion is 4.9× clang's.**  zsdcc loses 7.8%
   size + 14.8% runtime to K&R prototypes; clang loses 1.6% size
   + 2.0% runtime.

### Issues filed / updated

- **Filed ravn/z88dk#14** — "K&R int-promotion penalty: 7.8% size
  + 15% runtime that recovers under ANSI prototypes".  Includes
  reproducible sweep delta + hypothesis (iCode allocator not
  narrowing through promoted-int operations) + workaround.
- **Updated ravn/z88dk#5** — `--nogcse` miscompile is K&R-only on
  ANSI sweep, then diagnostic narrowed further: actually
  `--sdcccall 1`-only.  Same trigger class as #14.
- **Updated ravn/z88dk#6** — first pass said "K&R-only correctness +
  size bloat both variants"; diagnostic cross-product then
  showed the bug fires on every K&R `-clib=sdcc_ix` variant
  regardless of `--sdcccall` or `--nogcse`.  Single data-flow
  miscompile, no control-flow layer (initial "early HALT /
  runaway" reading was the ticks counter-reset artefact — see
  Tooling lesson below).

### Diagnostic cross-product (`diagnostic_sweep.sh`)

8-config K&R sweep designed to test the hypothesis that #5/#6
share root cause with #14 (all `--sdcccall 1` + K&R triggers):

| config | --sdcccall | -clib | --nogcse | verify |
|---|:---:|---|:---:|:---:|
| 01 | 1 | iy | — | PASS |
| 02 | 0 | iy | — | PASS |
| 03 | 1 | iy | yes | **FAIL** (#5) |
| 04 | **0** | iy | yes | **PASS** (#5 fixed by --sdcccall 0) |
| 05-08 | × | ix | × | FAIL (#6, all variants) |

Clean clustering: 3 issues, 2 underlying bug classes (#5 ⊂ #14;
#6 independent).

### Tooling lesson — `feedback_verify_pass_condition` applies to FAIL too

First diagnostic run skipped `fill_with_jp_done.py`.  Without
JP-fill, miscompiled bins escape into NOP-sled, PC wraps
0xFFFF→0x0000, `z88dk-ticks`'s `start==pc` counter-reset clobbers
the tstate total.  Reported runtimes (0.93 Mts for K&R sdcc_ix)
were ~30× shorter than the true value (31.9 Mts).  Same md5 bin,
different tstate output between sweep (filled) and diagnostic
(unfilled).

The "0.93 Mts for a FAIL" reading was implausibly fast and
should have prompted a sanity check before being written into
issue comments.  Memory rule [[feedback-verify-pass-condition]]
already covers this — its scope expands to FAIL signals when
runtime characteristics are part of the claim.  Diagnostic script
now mirrors the main sweep's fill step.

### #5 deep-dive — original "writes dropped" diagnosis was wrong

After the cross-product diagnostic, I attempted to extract a
single-function isolated repro for the #5/#14 cluster.  Minimal
isolation impossible (original #5 filer's note confirmed: bug
needs full AES register pressure).  Switched to iCode dump diff +
`z88dk-ticks -trace`.

**Root cause** (traced via 10M-line ticks trace + binary
disassembly): the writes through `r` at $C000..$C00F DO happen
correctly (PC=0x01EA `ld (hl), a` runs 16× with HL=$C000+i and
A=cipher byte).  Subsequent call to `aes_done(&ctx)` then zeros
$C000..$C01F because `aes_done`'s body reads its ctx parameter
from BC instead of from HL (where main correctly placed &ctx).
BC still holds $C000 = main's `r` pointer at the call site
(under `--nogcse` it survives there; under default GCSE it gets
overwritten by the loop counter pattern, so the symptom
disappears).

This is a callee-side register-convention violation in `aes_done`
(and likely the second `aes256_init` call).  Triggers under
K&R + `--sdcccall 1` + `--nogcse`; `--sdcccall 0` masks it because
the stack-args ABI doesn't depend on BC's leftover value.

Filed deep-dive analysis in
`tasks/aes256-corpus/repros/analysis_5_root_cause_2026_05_20.md`
and posted to ravn/z88dk#5.  Three prior issue comments contained
wrong intermediate diagnoses; the bug took four rounds of
refinement to localize.  Memory rule for me to extract: trace
before theorizing on "writes elided" — always verify the actual
store opcode runs with the expected operands FIRST, before
hypothesizing about codegen suppressing it.

### Also filed: ravn/z88dk#15 — wrong version banner

zsdcc reports build platform as "Mac OS X ppc" on macOS aarch64.
Cosmetic but misleading.  Spotted by user during the deep-dive
session.

### What was Easy

- Sweep script parameterization (minimal env-var diff).
- Running the four sweeps (mechanical, total wallclock ~6-7 min).
- Cross-checking the K&R-vs-ANSI failure pattern on `08_nogcse`
  and `09_clib_ix` — both flipped cleanly, no edge cases.

### What was Painful

- Initial concurrent `make sweep` collision (forgot CWD twice,
  three sweeps running in parallel until pkill).  Resolved fast,
  but a textbook example of why concurrent fire-and-forget kicks
  benefit from `lsof`-style guard or an outer flock.
- Edit tool dropped exec bit on `flag_sweep_sdcc.sh` once during
  the edits; `bash ./script.sh` works around it but `./script.sh`
  needed `chmod +x` after editing.

## Session 73k: rcbios CP/NET PIO transport + cpnos __sfr port-IO + single MAME tree (May 18, 2026) — Hard

End state: both clang and SDCC BIOS variants of rcbios run a full
PolyPascal PRIMES regression over CP/NET via the new PIO transport
in `cpnet/snios.asm`, end-to-end through CPNETLDR / LOGIN / NETWORK
/ H: drive change / PolyPascal load from master / PRIMES through
29989 / Q return to CCP.  cpnos's PROM1-only build also got its
own polypascal-test green for both compilers via a content-driven
`xport_aliases.asm` regen.

### What landed (commits on `main`)

  - **`754b901`** `cpnos: __sfr-backed IO_WRITE/IO_READ macros for
    compile-time-constant ports` — closed ravn/z88dk#9.  SDCC
    PROM1-only resident: 2196 -> 2120 B (-76 B raw, -39 B post-ZX0).
    All 18 of cpnos's `_port_out`/`_port_in` indirect helper calls
    now lower to bare `OUT (n),A` / `IN A,(n)`.  Audit guard
    confirms zero helper calls remain.

  - **`732f2b0`** `cpnos-polypascal-test: drive PROM1-only topology,
    single MAME tree` — `cpnos-polypascal-test` no longer chains
    through the parked two-PROM `cpnos-install` (broken at
    `__stack_top` since `a6b8948`).  New install path: autoload-in-c
    clang ROA375 -> PROM0 + cpnos lineprog -> PROM1 + locale-prefixed
    cpnos.img on mpm-net2 disk.  `MAME_IRQ` consolidated into single
    `MAME` tree.

  - **`e26dfff`** `cpnos: SDCC PROM1-only polypascal-test PASS —
    content-driven xport_aliases regen` — root cause of the SDCC
    "LOGIN hang" was a stale `sdcc/xport_aliases.asm` newer than its
    `transport_stamp` mtime, generated for `TRANSPORT=sio` while the
    build ran `TRANSPORT=pio-irq`.  Slave's SNIOS dispatched CP/NET
    frames to SIO-A (raw file sink) instead of PIO.  Decisive
    diagnostic: TCP MITM tap between MAME and mpm-net2 captured
    "S>M: 00" then silence.  Switched the .asm regeneration rule
    from mtime-dep to `$(shell) + grep` of an embedded `TRANSPORT=`
    marker.

  - **`fe95af8`** `cpnet/snios.asm: dual SIO+PIO transport, runtime
    select via SW1 bit 2` — rcbios CP/NET driver gains a PIO
    transport mirroring cpnos's `transport_pio.c`.  `SENDBY` /
    `RECVBY` / `RECVBT` become 3-byte `JP nn` trampolines; NTWKIN
    reads SW1 bit 2 and patches the operand in place.  PIO impl:
    direct Mode 1 input + IRQ ring buffer (256 B SPSC) installed at
    IVT slot 17.  SNIOS code 673 -> 1149 B, SPR file 1024 -> 1664 B.

  - **`496f687`** `cpnet/polypascal_pio_test: SDCC BIOS PASS — fix
    SDCC build path + byte pacing + CR` — `rcbios-in-c/sdcc/Makefile`
    repathed the helper-call-guard from pre-split
    `cpnos-rom/tasks/scripts/check_no_helper_calls.py` to its
    post-split home `cpnos-shared/scripts/check_no_helper_calls.py`.
    Without this the SDCC BIOS build silently failed and tests ran
    against stale BIOS.

  - **`86ab3b8`** `cpnet/polypascal_pio_test: keep PPAS inject +
    record investigation` — final form of the rcbios CP/NET PIO
    PolyPascal regression test.  Mirrors cpnos's
    `polypascal_test.lua` pattern: SUB carries CPNETLDR / LOGIN /
    NETWORK / H:; injector picks up at H>, types `PPAS\r`, drives
    interactive L PRIMES / R / Q.  Both compilers green (clang
    10.50 s, SDCC 10.71 s).

### Bugs / issues filed at ravn/z88dk

  - **#8** zsdcc switch with tail-callable case bodies emits a dead
    `jp` block after default `ret`.  Concrete repro in 15 lines;
    36 B unreachable in cpnos's `_specc`.
  - **#9** (closed) inline port-IO intrinsic / address_space — user
    pointed out `__sfr __at` already handles this; commit `754b901`
    uses that idiom.
  - **#10** zsdcc IX-frame fallback for cross-call spills; spends
    ~17 B prologue/epilogue on functions that just need to save one
    byte across a single call (`_scroll_lines`).  Structural; filed
    for tracking, not blocking.

### Memory rules filed this session

  - **`feedback_build_var_artifacts_content_check`** — generated
    files whose content depends on a Make-level variable
    (`TRANSPORT`, `COMPILER`, build-info-string, ...) must regen via
    parse-time content-check, not mtime dep on a stamp file.  Bitten
    twice in one session (xport_aliases.asm + buildinfo.h -> .o
    dependency).  Diagnostic shortcut: `head -1 generated.file`.

  - **`feedback_verify_pass_condition`** — when a test prints PASS,
    cross-check elapsed time vs plausibility + scan post-test
    artefact for setup-step evidence + look for working-reference
    example.  False-positive bitten when polypascal-PIO "PASS"ed in
    4.55 s by short-circuit (PPAS staged on local A:, CP/NET never
    ran; CPNETLDR/LOGIN/NETWORK ran AFTER the inject had declared
    PASS).  Workaround without explanation = red flag.

### Key decisions

  | Decision | Rationale |
  | -------- | --------- |
  | rcbios SNIOS gains PIO as opt-in via SW1 bit 2 (default = PIO) | Matches cpnos's canonical convention in `docs/SW1_BIT_MAP.md`; future hardware likely wired PIO; existing SIO users flip S03=Off |
  | Self-modifying `JP nn` trampoline dispatch | Same idiom cpnos uses for xport_aliases; zero per-call overhead once patched at NTWKIN |
  | ISR ring buffer is SNIOS-local (256 B in SPR data) | Avoids the IVT-page constraint cpnos pio_rx_buf hits; SPR relocation bitmap handles ISR address fixup |
  | PPAS launched via injector typed-with-CR, not SUB | cpnos's polypascal_test.lua pattern; SUB-fed PPAS works through TCP proxy but is brittle direct -- byte-timing on CP/NET PIO load |
  | Single MAME tree (was MAME + MAME_IRQ) | Cross-tree sync clobbered freshly-installed PROMs; consolidation eliminates that class of stale-ROM trap |
  | Content-check, not mtime-check, for build-var artifacts | mtime drifts through interrupted builds, sub-makes, ad-hoc target invocations; embedded marker is authoritative |

### Test snapshot (post-session)

  | Test                              | clang   | SDCC    |
  | --------------------------------- | ------- | ------- |
  | cpnos-polypascal-test             | 51.33 s | 49.67 s |
  | cpnet/polypascal_pio_test.sh      | 10.50 s | 10.71 s |
  | cpnos pio-irq-netboot             | PASS    | PASS    |

### Painful moments

  - **False-positive PASS** (motivated `feedback_verify_pass_condition`):
    polypascal-PIO "PASSed" in 4.55 s; I committed it.  Reality: PPAS
    was staged on local A: as a "workaround" for a SUB-order bug I
    hadn't understood, so the test ran PolyPascal purely on CP/M with
    CP/NET never engaged.  Caught by user pushback "I am not sure you
    are bringing in the latest work in the cpnet driver to rcbios" and
    later "do ppas sdcc and clang run to completion".  Lesson +
    rule filed.

  - **Stale Makefile path** in `rcbios-in-c/sdcc/Makefile` pointed at
    pre-split `cpnos-rom/...` that no longer exists; SDCC BIOS build
    silently failed; tests ran against stale clang BIOS and reported
    bogus SDCC results.  Fixed; rule already covered by
    `feedback_check_banner_timestamp`.

  - **Multiple investigation pivots on "what's wrong with SDCC".**
    Misdiagnosed as "PIO drive-change hang" -> "SDCC SIO RX drops CR"
    -> "stale BIOS".  Real cause was always stale builds; the
    pretty-asm-debugging detours cost ~2 hours.  User correction
    "if you have no idea what the problem is, stop and investigate"
    was the right course adjustment.

## Session 73j: SEM702 RAM chargen in MAME + autoload sextants + QR test (May 17, 2026) — Medium

End state: MAME `rc702sem702` machine variant models the SEM702
programmable character generator (replaces ROA327 ROM in IC82).
autoload-in-c calls `define_sextants()` unconditionally on every boot
to populate SEM702 RAM with the 64 ROA327-codepoint sextant glyphs
(0x20-0x3F, 0x60-0x7F).  New `sem702-qr-test/` subproject builds a
small CP/M .COM that paints two side-by-side QR codes (1x + 2x scale)
of `https://github.com/ravn` and warm-boots back to CCP after a 10 s
view delay.  Verified end-to-end via MAME snapshot.

### What landed

  - **MAME `rc702sem702` machine variant**
    (`mame/src/mame/regnecentralen/rc702.cpp` + `mame.lst`).  Clone of
    `rc702` 8" with `roa327.rom` dropped from the chargen region;
    upper 2 KB backed by a 2 KB `m_sem702_ram` array (init 0xFF =
    visibly "unprogrammed").  Ports 0xD1/0xD2/0xD3 wired as pure
    latches (ACHAR/ALINE/AWR) with no side effects -- matching the
    two software sources we have (autoload's `define_sextants` and
    the COMAL80 example in `docs/RC702tech.txt:17191+`).
    `display_pixels` reads from `m_sem702_ram[(charcode << 4) | line]`
    when `GPA0=1` on this variant; ROA296 (lower half of "chargen")
    still serves `GPA0=0` text mode.  Handlers no-op when
    `m_has_sem702==false` so wiring them in `io_map` for all rc702
    variants is safe.  Save-state plumbing added for ram + latches.

  - **autoload-in-c: `load_chargen` -> `define_sextants`**
    (`rc700-gensmedet/autoload-in-c/rom.c`).  Removed the
    PROM1->SEM702 font-copy path (uninteresting now).  New
    `define_sextants()` runs unconditionally in `main_relocated()`
    before `init_fdc()`; programs 64 sextant glyphs at the same
    codepoints they occupy in ROA327 (`0x20-0x3F` patterns 0..31,
    `0x60-0x7F` patterns 32..63), blanks every other codepoint.  A
    real ROA327 ROM in IC82 silently ignores the OUT writes, so the
    call is a safe no-op on baseline hardware -- no SW1 gating.
    Half-byte LUT `{0x00, 0x0F, 0x70, 0x7F}` matches MAME's
    bit-0-leftmost `display_pixels` convention; bit layout per
    `ROA327_CHARACTER_ROM.md:155-194` (bit 0 = top-left).  Clang PROM
    1509 -> 1656 B (+147 B; 392 B free in 2048 B socket).
    `docs/SW1_BIT_MAP.md` updated; SW1 bit 1 is no longer overloaded
    as a chargen-load gate (label retained for historical clarity).

  - **`sem702-qr-test/` CP/M test program**
    (`rc700-gensmedet/sem702-qr-test/`).  Python `gen_qrtest.py`
    renders `https://github.com/ravn` as a v2 QR at both 1x (15x10
    cells) and 2x (29x20 cells) scale, emits a single 811 B
    `qrtest.asm` paint program with both QRs side-by-side starting at
    (row 1, col 0) + col 18.  Paint code: `LDIR`-clears display to
    sextant blanks, writes 0x84 field-attribute byte at 0xF800 to
    flip `GPA0=1` for the rest of the screen, copies both data blocks
    row-by-row, busy-waits ~10 s at 4 MHz (24 outer x 65536 inner x
    26 T = 40.9 M T), then `JP 0` for CP/M warm boot.  Floppy
    injection via `cpmcp -f rc702-8dd` into a /tmp copy of
    SW1711-I8.imd (original never modified); MAME autoboot lua waits
    for `A>` prompt, posts `QRTEST\r` via natkeyboard, snapshots when
    the 0x84 sentinel lands at 0xF800.  Snapshot at
    `sem702-qr-test/snap/qrtest.png` shows both QRs with clear finder
    patterns and proper 2x3 sextant sub-cells (gitignored; rebuild
    via `make run`).

### Cost-of-error: bit encoding rediscovered the hard way

  - **First `define_sextants()` attempt was wrong twice over** -- bit
    direction (claimed bit 0 = top-right; actual is top-left) AND
    byte format (claimed SEM702 wanted bit-reversed bytes vs ROA327;
    actual is no reversal, both LSB-first / bit-0-leftmost).  First
    QR snapshot showed visibly-broken thin vertical stripes inside
    each cell -- not 2x3 blocks.  `ROA327_CHARACTER_ROM.md:155-194`
    already documented the correct convention exactly; I didn't read
    it before writing the code.  Cost: 2 screenshot iterations + 1
    autoload rebuild.  New memory rule
    [[feedback-grep-repo-docs-before-deriving]] filed.

### Issues raised / follow-ups

1. **SDCC autoload build broken (pre-existing).**  `copt: can't open
   patterns file` from `Makefile`'s `cd sdcc && zcc
   -custom-copt-rules=sdcc/peephole.def` -- after `cd sdcc`, the path
   becomes `sdcc/sdcc/peephole.def`.  Confirmed identical failure on
   stashed-tree (not caused by this session).  Blocks SDCC-side
   verification of `define_sextants()`.  TODO: fix path or move
   peephole.def.

2. **Real-hardware SEM702 verification needed.**  User has a physical
   RC702 with SEM702 fitted in IC82.  Untested: (a) does the chip
   accept our byte format end-to-end, (b) does it auto-increment
   ALINE on AWR write (both software paths set ALINE explicitly so
   it's invisible), (c) does the screen render the expected QR.
   Plan: burn the freshly built autoload + boot, photograph
   `QRTEST.COM` output, scan QRs with a phone.

3. **SDCC variant of autoload doesn't exercise define_sextants.**
   Only clang autoload built and verified in MAME (per #1).  Need
   parity check once SDCC build is fixed -- SDCC may produce
   different OUT-sequence timing that hits an undocumented chip
   constraint we don't see in MAME's strict-latch model.

4. **MAME SEM702 model is conservative; real chip may auto-increment.**
   If physical-hardware testing confirms ALINE auto-advances on AWR
   write, the explicit `port_out(chargen_dot, ...)` inside
   `define_sextants()`'s inner loop becomes redundant -- ~32 B
   savings.  Worth a follow-up once we have hardware data.

5. **Lua A> prompt detection is loose.**  `qrtest_run.lua` scans
   every screen row for "A>" anywhere, could false-positive on user
   text containing the sequence.  Tighten to (cursor_y, col 0) like
   `rcbios-in-c/mame_boot_screenshot.lua` does.  Minor; only affects
   test harness.

6. **`gen_qr.py` in autoload-in-c and `gen_qrtest.py` in
   sem702-qr-test duplicate sextant rendering.**  Different
   deployment targets (boot-time autoload PROM display vs CP/M .COM)
   but the `pattern_to_charcode()` + sextant-packing loop is
   identical.  If a third user appears, factor into a shared module.

7. **MAME ROM_LOAD_OPTIONAL deprecated.**  Compile warning on every
   build of `rc702.cpp`; not our doing, but worth tracking for the
   day MAME removes it.

### Addenda (after the session-73j commits)

  - **`autoload-in-c/BOOT_SEQUENCE.md` TL;DR table.**  Added a 6-row
    outcome table at the top of the doc covering the floppy-vs-PROM1
    priority -- the three gates inside `boot_from_floppy_or_jump_prom1`
    (drive ready / format detected / Track 0 signature).  Phase 5/6
    detail below the table unchanged.  Commit `654e3f0`, workspace
    bump `f8baacf`.

### Follow-ups discovered while documenting boot priority

8. **`** NO KATALOG **` halt path doesn't try PROM1**  (rom.c:704).
   When the floppy is readable but Track 0 has no recognised signature
   (neither ` RC702` CP/M nor ` RC700` ID-COMAL), autoload halts
   instead of falling back to `prom1_if_present()`.  All four other
   floppy-failure paths *do* try PROM1.  **RESOLVED 2026-05-17:**
   user-confirmed intentional -- a readable Track 0 we cannot
   recognise is treated as an inserted stranger's disk, and silently
   running PROM1 would be a surprise (potentially executing a CP/NET
   lineprog the operator didn't ask for).  Policy locked in via code
   comment at rom.c:704; #9 below remains as optional regression
   coverage.

9. **No MAME test covers the readable-disk-no-signature path.**
   Optional after #8's resolution.  We have oracles for "bootable
   CP/M floppy" (qrtest_run.lua) and "no floppy at all" (sw1-test
   target); none for a disk that is readable but unrecognised.  Add
   a fixture (e.g. an IMD file containing a single Track 0 of
   garbage) and a lua test asserting the `"NO KATALOG"` string
   appears in display memory + that PROM1 is NOT jumped into.
   Useful as regression coverage for the locked-in policy from #8.

10. **MAME's `rc702_maxi` / `rc702_mini` DIP label "S02 PROM1=lineprog
    (skip chargen)" is partially stale.**  After session 73j the
    "skip chargen" half of the label is meaningless -- `define_sextants`
    runs unconditionally.  The "PROM1=lineprog" half is still
    accurate (S02 selects the signature autoload looks for at PROM1).
    Rename to "S02 PROM1=lineprog" for clarity.  Lives in
    `mame/src/mame/regnecentralen/rc702.cpp` `rc702_maxi` +
    `rc702_mini` PORT_DIPNAME labels.  **RESOLVED 2026-05-17:** label
    shortened to "S02 PROM1=lineprog" + matching comment block (line 214)
    updated to drop the chargen-gating prose.

11. **cpnos-in-c: reserve translation-table space + hook default tables.**
    rcbios-in-c provides `outcon` / `inconv` tables at a fixed address
    (0xF680, see `rcbios-in-c/bios.c:779,934,1372`) which CONFI.COM and
    locale-aware utilities expect.  cpnos-in-c (the diskless slave) has
    no equivalent today, so programs assuming the BIOS layout render
    wrong glyphs against the slave.  Reserve byte-compatible slots in
    the slave image and bundle a default table set.  PROM1 budget is
    now critical (30 B free post-#16); needs ZX0 compression or
    RAM-decompressed placement.  Planning note:
    `cpnos-in-c/tasks/todo-translation-tables-2026-05-17.md`.  Cost
    class: Medium.  Deferred -- not blocking anything live, pick up
    next time the slave is touched.

### Addenda (SW1 wiring + dual-transport cpnos, late session 73j)

  - **SW1 bit 0 + bit 1 wired across autoload / rcbios / cpnos**
    (commit `14846e3`).  Final semantics per user spec:
      - bit 0 (S01): On = joined console (SIO-B + kbd in, SIO-B + CRT
        out); Off = local-only.  rcbios + cpnos both honour.
        rcbios's previous condition was *inverted* from this spec;
        fixed.  cpnos's compile-time `MIRROR_SIOB` flag still strips
        SIO-B output entirely for size-constrained builds; runtime
        flag gates the joined behaviour inside `MIRROR_SIOB=1`.
      - bit 1 (S02): On = autoload checks PROM1 signature on
        floppy-boot failure and jumps if present; Off = halt with
        NO DISKETTE NOR LINEPROG (operator-side lockout without
        pulling the EPROM).  Was unused before this commit.
    Doc updates: top-level `README.md` "DIP switch SW1" section,
    `docs/SW1_BIT_MAP.md` rewrite, MAME prose comment.

  - **cpnos PROM1-only is now dual-transport, SW1 bit 2 selects**
    (commit `ab606b0`).  Both `transport_pio.o` and `transport_sio.o`
    linked in.  3-byte JP-NN trampolines for `_xport_send_byte` /
    `_xport_recv_byte` in `.resident` (NOT `.resident.jumptable` --
    that would push `_snios_jt` past the linker ASSERT at 0xED33).
    `install_transport()` in `.resident` (because `.init` was at its
    640 B cap) patches the trampolines at cold-init based on PORT_SW1
    bit 2.  Cost +69 B; PROM1 2018 / 2048 B (30 B free).
    Buffer-sharing was trivial: SIO uses no RX buffer (polls SIO-A
    directly).  SIO-A vs SIO-B independent chip channels => no
    conflict with bit-0 joined console.

### Follow-ups discovered while wiring SW1 bits + dual-transport

12. **PROM1 budget critical -- 30 B free.**  Down from 99 B before
    dual-transport.  Any further cpnos growth (e.g. follow-up #11
    translation tables) must be paired with an equal-or-larger shrink
    elsewhere in the slave.  Memory rule
    `project_rc702_2kb_prom_hard_limit` covers the underlying hard
    constraint (no A11 bridge on user's hardware).  Active monitoring
    -- worth checking PROM1 size after every cpnos-touching commit.

13. **rcbios SW1 bit-0 inversion fix untested under MAME.**  The
    inversion was a correctness fix (was bit=1 → JOINED, now
    bit=0 → JOINED matching MAME's "On" = bit-clear convention).
    Existing `mame_siob_*` tests in `rcbios-in-c/` predate the fix
    and may be asserting the old behaviour; run them and update
    expectations if they fail.  Particularly: confirm that with
    default SW1 (bit 0 = 0), CON: comes out as UC1 (joined) not
    CRT-only.

14. **SIO-mode cpnos PROM1-only runtime untested.**  Default-PIO
    smoke-tested (banner appears via JP trampoline); SIO-mode (SW1
    bit 2 set) is link-clean and the patcher logic is correct by
    code inspection, but no MAME run with bit 2 = Off + SIO-A wired
    to mpm-net2 has been executed.  Add a dedicated test target
    (something like `cpnos-prom1-sio-smoke`) that boots
    rc702/rc702sem702 with the PROM1-only image + DSW bit 2 set +
    SIO-A wired to a fake-master end, asserts a known SNDMSG/RCVMSG
    pair round-trips.

15. **`transport_sio.c` naming asymmetry.**  PIO transport exports
    `transport_pio_send_byte` / `transport_pio_recv_byte`; SIO
    transport exports the bare `transport_send_byte` /
    `transport_recv_byte`.  Rename the SIO pair to
    `transport_sio_send_byte` / `transport_sio_recv_byte` for
    symmetry; cascades into `Makefile` TRANSPORT_DEFSYMS aliases
    + init.c install_transport() references.  Cosmetic / readability.

16. **Two-PROM cpnos builds still single-transport at compile time.**
    `make cpnos-burn` picks TRANSPORT=pio-irq or TRANSPORT=sio.
    Could be extended to dual-transport too (same JT + install_transport
    machinery), but no concrete user benefit while two-PROM is the
    legacy path.  Low priority.

17. **`install_transport()` lives in `.resident` not `.init`.**
    .init was at its 640 B cap.  Cost: ~30 B of RAM stays resident
    after cold-init although the function is never called again.
    Reclaimable if .init slack appears (e.g. some cold-init code
    moves into bootstrap or is removed).  Low priority.

### Addenda (branch `cpnos-shrink-investigation-73j`)

  - **SDCC autoload build unblocked**.  Docker-absolute path for
    `copt-rules` (commit `cb9bea5` on branch).
  - **Per-compiler size policy.**  clang autoload = 2 KB hard cap
    (matches user's physical 2716 sockets; no A11 bridge);
    SDCC = 4 KB ceiling for MAME-only parity testing.
  - **cpnos PROM1 shrink** (commit `69c897b`): install_transport
    word-store rewrite + dead `#if 0` cleanup -> 2018 -> 1999 B
    (30 B free -> 49 B free).
  - **impl_conout hot-path reorder** (session 73j late addendum):
    branch order now `xflg, c>=0x20, CR, LF, specc` instead of
    `xflg, LF, CR, c<0x20, specc`.  Printable hot path drops from
    5 tests to 2 tests (~24 T saved per char at 4 MHz).  PROM1
    1999 -> 2000 B (+1 B, negligible).  Default-PIO slave still
    boots banner cleanly through the new dispatch.

### Follow-ups added late session 73j

18. **SDCC PROM1-only build path.**  User-asked, then PARKED.
    Requires a SDCC-side equivalent of clang's two-pass extract +
    ZX0-compress + relink pipeline because SDCC `.o` is z88dk
    format (not ELF, so `ld.lld` can't be used).  Path A is a
    post-process Python hack reading the SDCC map + section
    binaries; Path B is a proper SDCC linker recipe.  Either way
    the projected SDCC image is ~2360 B -- over the 2 KB cap but
    fits the 4 KB SDCC ceiling.  Planning note:
    `cpnos-in-c/tasks/todo-sdcc-zx0-2026-05-17.md`.

19. **MAME ROM-install footgun.**  Three different make targets
    cp their PROM0 to `mame/roms/rc702/roa375.ic66`:
    autoload-in-c (`make prom`), cpnos-in-c (`make cpnos` two-PROM
    via SDCC), and probably others.  Last-one-wins; previous
    operator state silently breaks when switching build targets
    (caught this session: SDCC cpnos two-PROM build overwrote the
    autoload PROM0 in MAME, causing later PROM1-only boots to
    hit "PROM MISMATCH").  Mitigate by: per-target MAME ROM
    paths (e.g. roa375.ic66 reserved for autoload, separate slot
    for cpnos PROM0), or a check-before-install that refuses to
    clobber a different-purpose binary.

20. **cpnos.img-loaded locale tables + ROA327 font** (user-asked
    feature-completion item).  Refines #11: instead of fitting
    `outcon`/`inconv` tables inside PROM1, fetch them from the
    master via existing CP/NET file I/O during cold-init.  Same
    mechanism can load a full 2 KB ROA327 image and stream it
    through 0xD1/0xD2/0xD3 to program the SEM702 with the full
    character set (not just the 64 sextant subset autoload
    programs).  Both gracefully degrade if files absent.
    Planning note:
    `cpnos-in-c/tasks/todo-load-from-cpnos-img-2026-05-17.md`.

21. **DMA dual-buffer scroll experiment** (user-asked, marked
    experimental).  Avoid the 1920 B LDIR in scroll_lines (~3.6
    ms per scroll at 4 MHz, 113 B of resident code) by feeding
    the 8275 from two alternating regions in RAM and swapping
    the DMA source address.  User-flagged: "will ruin the 0xF800
    memory layout" if direct-poke software compat isn't preserved.
    Large project; defer until other hot paths are optimised.
    Planning note:
    `cpnos-in-c/tasks/todo-dma-dual-buffer-2026-05-17.md`.

## Session 73j-end: SDCC PROM1-only end-to-end + ravn/z88dk#7 block-scope-extern bug (May 17-18, 2026 night) — Hard

End state: both clang and SDCC PROM1-only line programs build, boot,
and pass `cpnos-polypascal-test` PRIMES to completion.  SDCC reached
functional parity with clang for the autoload + cpnos-PROM1-only
topology -- the only supported slave architecture going forward
(two-PROM parked).

### Concrete deliverables

  * **SDCC PROM1-only line-program pipeline** (
    `cpnos-in-c/sdcc-prom1lineprog/`).  Mirror of clang's
    `clang-prom1lineprog/` two-pass ZX0 build using z88dk-zcc +
    z80asm rather than ld.lld + objcopy.  Image 2246 B (4 KB
    padded); init 689 -> 585 B ZX0, payload 2192 -> 1559 B ZX0.

  * **Unified Makefile target.**  `make prom1-lineprog
    COMPILER={clang,sdcc}` dispatches to the right pipeline; legacy
    `sdcc-prom1lineprog{,-try}` aliases preserved.

  * **MAME companion changes** (ravn/mame@d0a7dcd81f2 + earlier):
    * `ROM_LOAD_OPTIONAL prom1.ic65` size 0x800 -> 0x1000 so 4 KB
      cpnos PROM1 images load completely.
    * `PORT_CONFNAME` PROM1 default = 0x02 (2732 4KB) so bank2h
      maps the upper PROM1 half by default.

  * **Block-scope `extern` SDCC bug** (filed
    https://github.com/ravn/z88dk/issues/7).  Root cause of the
    "SDCC netboot stalls at 28 dots" symptom -- SDCC's z88dk
    back-end silently drops function-scope `extern` declarations
    from its .asm GLOBAL symbol list, producing undefined-symbol
    errors when z80asm assembles the file.  The error masked
    itself because make didn't rebuild stale .o files from a prior
    commit that pre-dated the gate-removal; tested slave was
    running pre-locale-machinery code that wedged in netboot for
    unrelated reasons.  Fix: file-scope extern (one-line move in
    init.c and cpnos_main.c).

  * **SDCC polypascal-test PASS** (49.81 s) -- matches clang's
    50.99 s for the same workload; both routes through the same
    init.c / resident.c source with compiler-specific cold-init
    paths (bootstrap.s vs bootstrap.asm + relocator.c shared as
    portable C between them).

### Diagnostic story (worth a memory rule)

The "SDCC netboot stalls at 28 dots" was investigated for several
hours with the wrong hypothesis (SNIOS protocol bug).  The
diagnostic chain that found the real cause:

  1. **dzx0 verified correct** via lua dump_resident.lua of slave
    RAM 0xED00..0xF58D + cmp against host-side z88dk-dzx0 of
    payload.zx0.  Byte-identical.  Rules out ZX0 stream / decoder
    bug.
  2. **SNIOS jumptable at 0xED33** verified consistent across all
    three builds (SDCC PROM1-only, SDCC two-PROM, clang PROM1-only)
    via cpnos.map grep.  Rules out cross-build address drift.
  3. **PC probe** identified stall at `_transport_pio_recv_byte`
    (0xEDEF+).  Hypothesised SNIOS 29th-frame issue.
  4. **Banner timestamp** said `2026-05-17 21:07 00791ce+` -- an
    OLDER commit than HEAD.  This was the actual smoking gun: the
    slave wasn't running fresh code.  `make` had skipped the
    rebuild because the stale .o was newer than the .c (which I
    had since edited but make couldn't tell why the .o was wrong).
  5. **Deleted sdcc/init.o** + retry: rebuild now FAILS with
    `undefined symbol: _install_locale_tables`.
  6. **Inspected SDCC -S asm output** -- block-scope extern emits
    `call _install_locale_tables` with no matching `GLOBAL
    _install_locale_tables` line; file-scope extern emits both.
  7. **Move declarations to file scope** -> SDCC build clean,
    slave boots to E>, polypascal PASSes.

Lesson: when an old build artifact shows older provenance than
expected (banner timestamp / build hash / image checksum), trust
that signal IMMEDIATELY.  Don't waste cycles assuming the slave is
running the source you just edited; verify.

### Followups filed / closed this session

  * todo-sdcc-prom1lineprog-netboot-stall-2026-05-17.md -- CLOSED.
  * todo-sdcc-locale-impl-2026-05-17.md -- CLOSED.
  * todo-sdcc-zx0-2026-05-17.md -- CLOSED.
  * todo-cpnos-prom1lineprog-single-chunk-2026-05-17.md -- open.
  * todo-mame-build-binary-name-2026-05-17.md -- open.
  * todo-polypascal-no-mirror-stage4-2026-05-17.md -- open.
  * todo-56k-tpa-2026-05-17.md -- open.
  * todo-cpnos-img-zx0-compression-2026-05-17.md -- open.
  * todo-cpnos-relocatable-2026-05-17.md -- open.
  * todo-prom1-compression-to-restore-bootmark-2026-05-17.md -- open.

## Session 73j-late: locale-tag in stamp, two-PROM parked, video pipeline, MAME col-80, autoload polish (May 17, 2026 evening) — Hard

End state: production slave topology firmly = autoload-in-c (ROA375)
in PROM 0 + cpnos-in-c PROM1-only line program (prom1-lineprog) in
PROM 1.  Two-PROM build PARKED.  Locale machinery (outcon pre-fill +
sentinel write) consolidated into one C site (init.c::cpnos_cold_
entry), shared by clang/SDCC × PROM1-only/two-PROM cold paths.

### Concrete deliverables

  * **Locale tag moved off the PROM1 banner** onto the cpnos.img
    build stamp (row 2 of the display).  User pointed out PROM1
    cannot truthfully name the locale until netboot has loaded the
    prefix.  stamp_cpnos.py grew from 24 → 32 bytes, accepts
    `--locale TAG`, cpnos-disk-install-with-locale passes
    `--locale $(CPNOS_LOCALE_TAG)` (default `da_US`).  Banner row 2
    now reads e.g. `2026-05-17 19:14 0aa5e7e da_US`.
  * **MAME video-capture pipeline.**  `scripts/mame_capture.sh`
    wraps MAME with `-aviwrite`, transcodes to H.264 MP4 via
    dockerised ffmpeg (`jrottenberg/ffmpeg:7-alpine`), pads to the
    rc702.lay layout view (904×590 with rgb(0xC0,0x60,0x00) bezel
    around 864×550 screen), prunes scratch/mame-videos/ to last 50
    captures.  Typical cpnos boot+CCP-idle 50-s run = ~160 KB MP4.
    `.gitignore` excludes the MP4/MNG/AVI outputs.
  * **cpnos-polypascal-test wired through mame_capture.sh** so the
    test leaves a video on every run.  PASS in ~50 s (clang).
  * **MAME rc702 driver col-80 fix.**  Edited
    `mame/src/mame/regnecentralen/rc702.cpp`: `set_size` 544 → 560,
    `set_visarea(0, 559)`.  i8275 is configured at 7 px/char so 80
    cols need exactly 560 px; previous value clipped the rightmost
    ~2 chars on every row.  Verified: autoload's "SW1 12345678:
    00000000" right-justified line now shows all 8 zeros with
    breathing room.  Committed to ravn/mame@035d29086bf.
  * **Autoload cold-boot screen-clear** (`autoload-in-c/rom.c::
    display_banner_and_start_crt`): added `memset(dspstr, 0x20,
    80*25)` before the banner memcpy so display RAM doesn't show
    the 0x00 Danish-accent glyph during the autoload-to-cpnos
    handoff window (~250 ms emulated, visible frame-by-frame in
    MP4 captures).  PROM0 cost: +6 B (still 1667/2048).
  * **Autoload banner restored to descriptive form**:
    `RC700 ROA375 CL 2026-05-17 20.34 bcd1a80/ravn` (46 chars,
    matches the SDCC variant's "ROA375" identifier; adds a git
    hash mirroring cpnos's stamp format).  PROM0 unchanged (ZX0
    absorbs the +15 chars).
  * **Two-PROM build PARKED.**
    `cpnos-in-c/tasks/TWO_PROM_PARKED.md`.  User clarified:
    "please park the two-prom scenario.  it is only the autoload+
    cpnos scenario that interests e".  Two-PROM was rebuilt for
    locale parity earlier in session (cpnos-shared/ld/payload.ld
    layout surgery: SCRATCH 0xEB00/256, PIO_RX 0xEC00, CFGTBL_RAM
    0xF53C, stack 0xF680) -- still works under clang, but no
    further investment.
  * **Locale pre-init consolidated into init.c.**  Was duplicated
    in clang-only inline asm (relocator.c) + asm (bootstrap.s).
    Single 25-byte for-loop + sentinel store at the top of
    cpnos_cold_entry() now serves clang/SDCC × PROM1-only/two-PROM.
  * **SDCC ZX0 measurement.**  z88dk-zx0 on the 2192 B SDCC
    resident → 1554 B (-29%).  Estimated SDCC PROM1-only total
    ~2080 B, ~32 B over the 2 KB cap; tractable with init-region
    shrinking.  Recorded in TWO_PROM_PARKED.md.
  * **SDCC build compiles** (was broken from session 73j-locale's
    `__asm__ volatile` push); two-PROM SDCC image is link-broken
    now (`_get_img_base` undefined in sdcc/init.o), but that's
    acceptable since two-PROM is parked.
  * **ROA296 glyph-bitmap doc** (`docs/ROA296_GLYPH_BITMAPS.md`)
    auto-generated from `mame/roms/rc702/roa296.rom` via
    `docs/render_rc702_charrom.py`.  Confirmed (after correcting
    my LSB-vs-MSB pixel-order mistake) that ROA296 places
    0x05=`@`, 0x0B/0x0C/0x0D=`[\]`, 0x1B/0x1C/0x1D=`{|}`,
    0x0F=`~`, 0x16=acute, which is what `us_ascii_tables.h`
    (from CONFI.COM) remaps the standard-ASCII bracket positions
    into.
  * **us_ascii_tables.h wired into gen_locale_prefix.py.**  Was
    byte-identity outcon (rendered Danish glyphs at [\]{|}~
    because that's where ROA296 has the Æ/Ø/Å/æ/ø/å variants);
    now uses CONFI.COM's canonical US-ASCII outcon table so the
    screen renders proper bracket / brace glyphs.

### Followup TODOs filed this session

  * todo-56k-tpa-2026-05-17.md
  * todo-cpnos-img-zx0-compression-2026-05-17.md
  * todo-cpnos-relocatable-2026-05-17.md
  * todo-polypascal-no-mirror-stage4-2026-05-17.md
  * todo-sdcc-zx0-2026-05-17.md (extant; folded user direction in)
  * todo-sdcc-locale-impl-2026-05-17.md
  * todo-mame-build-binary-name-2026-05-17.md
  * todo-prom1-compression-to-restore-bootmark-2026-05-17.md

### Lessons

  * **PROM-knowing should rarely live in pre-resident code.**  The
    locale pre-init initially landed in bootstrap.s (PROM1-only's
    asm) + relocator.c (two-PROM's clang-only asm).  Same logic in
    two places, two compilers, one of them with #ifdef branches.
    Consolidating into init.c made the duplication go away.
    Generalises: any "after the resident bytes are live but before
    init runs" hook is better as a C function at the top of
    cpnos_cold_entry than as compiler-specific pre-init bytes.
  * **Banner that PROM cannot truthfully fill should not lie.**
    PROM1's banner can't include the locale tag because the locale
    tables aren't loaded yet; putting "da_US" there is a fabrication.
    Moving the tag to cpnos.img's stamp (row 2) corrected the
    architecture in one stroke.
  * **MAME source build artifacts drift.**  `regnecentralend` is a
    legacy custom-named binary used by every recipe; a fresh MAME
    build emits `mame`.  Without a top-level alias the new binary
    sits next to a stale `regnecentralend` and tests run the old
    code.  Memory rule `feedback_mame_osd_sdl` covers the OSD=sdl-
    not-sdl3 gotcha; the binary-name drift is the next-class issue.
  * **Cold-boot RAM = 0x00 = "Danish ü-ish glyph" on RC702.**  The
    autoload PROM's dspstr buffer at 0x7A00 is power-on RAM; without
    a memset, every cell renders as the ROA296 0x00 glyph (accented
    char), producing a screen-wide "dot pattern" flicker during the
    ~250 ms autoload-to-cpnos handoff.  Invisible to a live
    operator; obvious in frame-by-frame video captures.  Fix is a
    single memset to 0x20 (space).

## Session 73j-locale: cpnos-in-c PROM1-only locale tables + banner sentinel fix (May 17, 2026) — Medium

End state: PROM1-only cpnos-in-c boots with locale tables (US-ASCII
outcon + Danish inconv) installed from a 384 B prefix prepended to
cpnos.img by `cpnos-disk-install-with-locale`.  Layout v3 freed
0xF680..0xF7FF for the tables (moved scratch_bss, pinned cfgtbl to
0xF53C, dropped BOOT_MARK_ENABLED for 67 B headroom).  PROM1 fit:
2011 / 2048 B (37 B free).  Verified end-to-end by running
`TYPE A:ASCII.TXT` against a 95-byte file containing the printable
ASCII range; rows 7-12 of the slave's 0xF800 display rendered
` !"#$%&'()*+,-./` through `pqrstuvwxyz{|}~` byte-exact, with the
RC702 character ROM applying the expected Danish-variant glyphs
to 0x5B..0x5E and 0x7B..0x7E (Æ/Ø/Å/Ü ... æ/ø/å/ü).

### The banner-NUL bug (caught during this session's verification)

Initial PROM1 build with locale tables produced a banner row 0 of
all NULs even though the tables were correctly installed.  Cause:
bootstrap.s set `_prom1_only_sentinel = 0x5A` BEFORE the C `init.c`
called `print_banner()`.  `impl_conout` keyed its outcon lookup on
the sentinel, so the banner indexed into a still-zero outcon at
0xF680 (install_locale_tables doesn't run until `resident_handoff`
after netboot).  Fix: removed the sentinel write from bootstrap.s
and added it in `init.c::cpnos_cold_entry` between `print_banner()`
and `netboot_mpm()`, so banner output passes through identity, then
the sentinel arms `get_img_base()` for the shifted netboot, then
`install_locale_tables` LDIRs the prefix to 0xF680.

### Verification harness

`/tmp/ascii_test/ASCII.TXT` (95 B file, chars 0x20..0x7E in 16-char
lines + CR/LF + CP/M ^Z terminator) installed on master library
disks `cpnetsmk-1.dsk` + `mpm-net2-1.dsk`, then MAME rc702 launched
with PIO/cpnet_bridge + `ascii_run.lua` autoboot script that waits
for the slave's `E>` prompt, sends `TYPE A:ASCII.TXT\r`, snapshots
rc702 display + dumps 0xF800 rows 0..15 to /tmp.  Two pre-test CRs
flushed three stale bytes ("RC>" garbage) that surfaced from an
uninitialised kbd_ring at cold boot (separate issue, filed below).

### Followup TODOs (filed)

  - `cpnos-in-c/tasks/todo-prom1-compression-to-restore-bootmark-2026-05-17.md`
    — find 67 B of PROM1 compression so BOOT_MARK can return.
  - Zero kbd_ring head/tail in port_init (3 stale bytes consumed
    by leading CR on cold boot); cheap and removes a latent class
    of "first keystroke disappears" symptoms.

### Lessons

  - **Stamp sentinels at the latest safe moment.**  Setting a flag
    that gates table lookups before the tables exist is a class of
    bug that can mask itself in development (when the only output
    happens after install) and surface only when boot-time output
    is added.

  - **Hardware-rendered Danish chars look like a bug from the
    outside.**  A row of `PQRSTUVWXYZÆØÅ?_` next to test-expected
    `PQRSTUVWXYZ[\]^_` initially reads as a translation-table error;
    confirming the 0xF800 byte was 0x5B (`[`) and the glyph ROM
    mapped it to Æ closed the loop.  Identity outcon + Danish
    glyph ROM is the correct combination on physical RC702.

## Session 73i: ZX0 on autoload + cpnos-in-c PROM1-only, park cpnos-in-asm (May 17, 2026) — Medium

## Session 73i: ZX0 on autoload + cpnos-in-c PROM1-only, park cpnos-in-asm (May 17, 2026) — Medium

End state: autoload-in-c ZX0-compressed (1846 -> 1509 B, +337 B free),
cpnos-in-c builds as a 2 KB PROM1 line program (1922 / 2048 B, 126 B
free) that pairs with autoload-in-c in PROM0.  cpnos-in-asm parked --
its original "fit CP/NOS in PROM1 alongside autoload" goal now
satisfied by cpnos-in-c without needing the asm variant.

### What landed

  - **autoload-in-c ZX0 compression** (clang only).  `.text` section
    (1742 B) ZX0-compresses to 1330 B, decompressed at boot by 68 B
    `dzx0_standard` into RAM at 0x6000.  Two-pass build with
    host-side `z88dk-dzx0` roundtrip verification refusing any
    non-exact unpack.  PROM0 free space 202 B -> 539 B (2.7x more
    headroom).  Boot to CP/M `A>` PASS, no behavioural change.
    Files: `autoload-in-c/clang/{dzx0_standard.s,text_compressed.s,
    rc700_prom.ld}` + boot_rom.c reloc_zx0 swap + Makefile two-pass.

  - **cpnos-in-c PROM1-only line program build** (clang × PIO).
    `clang-prom1lineprog/` subdir with `bootstrap.s` (header +
    signature + entry that calls `dzx0_standard` twice), shared
    decoder, separate `payload.ld` variant relinking init at VMA
    0xC000 (RAM, decompressed at boot).  init.bin 627 -> 545 B ZX0,
    payload.bin 1858 -> 1275 B ZX0, both roundtrip-verified.  Final
    PROM1 image 1922 / 2048 B fits in a single socket and satisfies
    autoload-in-c's `prom1_if_present` contract (` RC702` signature
    at 0x2002 + jump target at 0x2000).  PolyPascal end-to-end
    PASS (PPAS PRIMES -> 29989 -> Q -> E> at 49s).  Plan:
    `cpnos-in-c/tasks/zx0-prom1-only-plan-2026-05-17.md`.

  - **cpnos-in-asm PARKED.**  New `cpnos-in-asm/PARKED.md`
    documents capability state (PolyPascal + CONOTEST PASS, 15 of 18
    RC700 text-mode CONOUT codes, full netboot via mpm-net2, NDOS
    handoff), gaps (graphics-mode 0x14/0x15/0x16 -- also gap in
    cpnos-in-c, RC703 hardware unaudited, less-exercised CP/NOS
    functions not stress-tested), and rationale (cpnos-in-c
    PROM1-only supersedes).  README.md gains a parking banner.
    Source tree preserved for historical reproduction and as
    reference implementation of the autoload->PROM1 contract.

### What's still missing (carried over from this session)

  - **cpnos-in-c PROM1-only: 3 of 4 value-oracle cells remaining.**
    Verified: clang × PIO.  Pending: clang × SIO, SDCC × PIO, SDCC
    × SIO.  Memory rule `feedback_value_oracle_all_transport_cells`
    requires all 4 before commit.
  - **Graphics-mode CONOUT codes 0x14/0x15/0x16.**  Missing on BOTH
    cpnos-in-c and cpnos-in-asm.  Standard CP/M utilities don't
    touch them; gap only matters for RC702 graphics-overlay
    workloads.  README/commit-message claim "full RC700 control-code
    set" was overstated -- it's the text-mode set only.
  - **autoload-in-c SDCC variant unchanged.**  ZX0 build path only
    on clang side; SDCC PROM still 1910 B raw.

### Follow-ups filed

  - `autoload-in-c/tasks/todo-later.md` gained two entries: ZX0
    decoder split around the NMI vector to reclaim ~35 B of pre-NMI
    PROM padding; ID Comal compatibility (decompress above sector-
    read area + relocated display base).
  - `cpnos-in-c/tasks/zx0-prom1-only-plan-2026-05-17.md` -- the
    full plan that drove this session, including the SDCC + SIO
    cells that remain.

## Session 73h: cpnos-in-asm shrink + full RC700 control-code set (May 17, 2026) — Medium

Started at 1937 / 2048 B PROM1 (post-session-73g) and ended at 1844 /
2048 B (204 B free) WITH the full RC700 console control-code set
implemented inline -- where session 73g had only CR + LF + printables.

### Shrink wins (cumulative ~290 B before adding the new code)

  - **Resident SNIOS dedup (~430 B):**  Moved the snios_payload LDIR
    to the top of slave_entry so do_netboot / cpnet_xact can call
    `snios_sndmsg` (0xED3C) and `snios_rcvmsg` (0xED3F) at their
    fixed resident entries instead of carrying the duplicate
    `send_cpnet_msg` / `recv_cpnet_msg` in prom1.asm.  Same wire
    protocol, half the code.
  - **Dead-code removal (~250 B):**  Reduced `combined_io_loop`
    (netboot-fail fallback) from a SIO-A→SIO-B forward + raw
    CP/NET frame recv/decode/dump diagnostic to just `di; halt`.
    Took out `recv_cpnet_frame` + `decode_rx_frame` +
    `dump_rx_to_siob` as orphans.  Operator sees "FETCH FAIL" on
    SIO-B and the slave goes quiet -- no useful state to maintain
    on a netboot failure anyway.
  - **Marker stripping (~40 B):**  The eight SNIOS per-call markers
    ('A'/'a'/'c'/'S'/'r'/'e'/'B'/'d') that were diagnostic during
    bring-up no longer fire useful info now that the SrSr loop is
    well-understood.  Kept the per-frame markers in cpnet_xact /
    NTWKIN/NTWKBT path indirectly through their behavior.
  - **BSS out of PROM (~20 B):**  `kbd_head` / `kbd_ring` /
    `snios_msg_ptr` / `snios_rx_soh` were zero-initialized `db`
    declarations inside the snios_payload binary -- moving them to
    bare-RAM `equ` addresses in the 0xF400 reserved range drops
    their 20 B from the PROM image.  `kbd_head` + `XY_STATE` are
    explicitly zeroed at handoff_entry; the rest get rewritten on
    every use so initial value doesn't matter.

### Full RC700 control-code set (cpnos-in-c parity)

Implemented per cpnos-in-c's `specc()` (resident.c:322-340):

  - 0x01 insert line / 0x02 delete line  (LDIR up / LDDR down)
  - 0x05 cursor left (ENQ) / 0x08 backspace
  - 0x06 XY cursor address (2-byte state machine via XY_STATE +
    XY_FIRST in the 0xF400 reserve)
  - 0x07 bell (PIB port 0x05 out)
  - 0x09 TAB (4× cursor right)
  - 0x0C clear screen + home (LDIR-fill 1920 B with spaces)
  - 0x18 cursor right / 0x1A cursor up / 0x1D home
  - 0x1E erase-to-EOL / 0x1F erase-to-EOS

Per user direction CR (0x0D) and LF (0x0A) remain INDEPENDENT --
CR sets col=0 only, LF advances row only with scroll on overflow.
cpnos-in-c folded LF -> CR+LF; we don't.

### Lesson logged

PolyPascal-test runtime is the proof the dedup is wire-equivalent --
sndmsg/rcvmsg go through the same resident path before and after,
they just consume one copy of the wire-protocol implementation
instead of two.

### Difficulty marker

Medium -- shrink + extend on a known-good baseline; one stumble when
the awk pattern in `cpnos-polypascal-test` didn't match the `equ`
form of kbd_head / kbd_ring (zmac formats them with a leading `=`).

## Session 73g: cpnos-in-asm reaches PolyPascal PRIMES end-to-end on CRT (May 16-17, 2026) — Hard

End-to-end POlyPascal `R PRIMES.PAS` running on the pure-Z80-asm CP/NOS
slave with full CRT visibility -- not just SIO-B mirror.  `make
cpnos-polypascal-test` PASSes in ~58 s wall, primes-through-29989
scrolling correctly across the screen, `>>Q` and post-Run `E>` prompt
at the bottom, cursor block tracking CONOUT live.

### Functional layers added

  - `kbd_head` + `kbd_ring` BSS in `snios_payload`, with `impl_const`
    (peek) + `impl_conin` (block-wait + LDIR-down-shift dequeue) wired
    to it.  `cpnos-shared/mame/polypascal_test.lua` writes keystrokes
    directly to the ring via a CPU memory tap.
  - `impl_conout` drives the CRT framebuffer at 0xF800 directly:
    write-at-cursor, col-80 wrap, row-23 LDIR scroll, AND mirrors to
    SIO-B for the test harness.  CR and LF independent (no CRLF
    folding, contrary to cpnos-in-c which treats LF as CR+LF).
  - `co_recompute` computes DOT_CURSOR from (row, col); `co_sync_cursor`
    pushes (col, row) to the 8275 via LOAD CURSOR; called tail-style
    at every CONOUT exit so the chip cursor tracks output live.
  - `snios_ntwkin` sets `cfgtbl.netst = CFG_NETST_ACTIVE` (0x10) so
    NDOS's downstream sndmsg/rcvmsg gate passes; mirrors cpnos-in-c.
  - `handoff_entry` copies the 51 B BIOS-JT to NDOSRL+0x300 = 0xDC80
    (cpnos-in-c convention).
  - Drive-table fix (the real-master gate): slave drive **E -> master
    drive I** (0x88), F -> J.  mpm-net2 only exposes A..D and I, J
    (4 MB hard disks); the earlier 1:1 slave-E -> master-E mapping
    drew `NDOS Err 04 Func 0E` ("no such drive") from the master.
    Verified by reading the master message format in `cpndos.asm`'s
    `nderr` -- the 04 was the second DAT byte of the response (the
    master's error subcode), not the BDOS return.

### Memory-map fixes (HARD lessons logged)

  - **`dot_*` state moved out of TPA.**  Originally at 0x4000..0x4003
    (inherited from prom1.asm's netboot-progress state, where it's safe
    pre-handoff).  Post-handoff `0x0100..0xE715 = TPA` -- any CP/M
    program clobbers whatever lives there.  Caught when the cursor
    jumped from row 3 to row 23 mid-PolyPascal-banner: PPAS's stack /
    working memory was stomping on `dot_row`.  Diagnosed with an
    instrumented `#NN` marker on every dot_row save plus a Lua memory
    dump.  Pinned at 0xF400 inside the SNIOS reserved area
    (0xED00..0xF7FF) per [[feedback-slave-state-outside-tpa]].
  - **Banner moved BEFORE `snios_payload_blob` INCBIN** in prom1.asm
    source order.  When snios_payload grew past ~700 B, banner's PROM
    file offset crossed 0x800, mapping to memory address >= 0x2800.
    The RC702 PROM1 socket is 2 KB; 0x2800..0x2FFF is the **bank2h
    mirror** which returns PROM1[0..0x7FF] again -- `ld hl, banner`
    fetched code bytes from PROM1[0x33] instead of banner text from
    PROM1[0x833].  Mid-stream visual symptom: row 0 of the CRT showed
    Z80 opcode bytes interpreted as glyphs.  See
    [[feedback-rc702-bank2h-mirror]] + [[feedback-state-address-phase-audit]].
  - **`feedback_no_taps_in_polled_rx`** from session 73f stayed clean
    throughout the session -- the new debug instrumentation lives
    inside per-frame markers, never inside polled RX/TX hot paths.

### Cursor-sync ISR investigation (parked)

Attempted a 50 Hz CTC-CH2 ISR that would push (DOT_COL, DOT_ROW) to
the 8275 only when changed, plus a 32-bit JIFFY counter.  Setup
verified end-to-end via Lua memory dump: `I = 0xF5`, `IFF1 = 1`,
`IM = 2`, IVT at 0xF500 with slot 6 = `isr_cursor`, CTC CH2 control
word `0xD7 + TC=1`.  Yet JIFFY stayed at 0 -- the ISR never fired
in 60 s of test.  Hypotheses (in order of suspicion): CTC ch2 IUS
bit stuck from autoload's last RETI'd-or-not ISR; cpnos.com/NDOS
doing DI during the SrSr loop; MAME RC702 CTC trg2 plumbing not
matching real-hardware semantics.  Manual `call isr_cursor` from
handoff_entry (to emit RETI on bus and clear stuck IUS) ticked
JIFFY exactly once but didn't unlock subsequent fires.  Parked;
per-CONOUT-call cursor sync is the working alternative.

### Code shape + budget

`make cpnos`: PROM1 at 1937 / 2048 B (111 B free) AT the burn budget.
Dead-code removal (`send_cpnet_init_*` chain, ~100 B unreachable since
session 73e's snios_sndmsg refactor) plus most per-handler debug
markers were the source of headroom.

The full RC700 control-code set (BS / TAB / 0x0C clear / XY cursor
addressing / insert-delete-line / bell / erase-to-EOL/EOS) was
implemented as `do_*` handlers + `dispatch_control` switch but
needed ~250 B more than current budget allows AND had bugs in the
backward-LDDR / mul_a_80 helpers that stalled the slave at boot.
Reverted to CR + LF + printables only -- covers PolyPascal, CCP,
PRIMES.PAS, and likely the majority of CP/M apps.  Add-back work
is queued for after a shrink pass on cfgtbl + emit_a helpers.

### Difficulty marker

Hard -- 3 separate memory-map traps (TPA / bank2h / IVT page), a
"500x slowdown" regression that turned out to be the IVT/CTC re-init
correlation with NDOS state, a "phantom" 20-row cursor jump that
took dot_row write-tap + display-memory dump to root-cause as TPA
stomping, plus a full ISR-vs-poll architectural pivot driven by
the realization that interrupts don't survive NDOS/CCP/PPAS run.

## Session 73f: cpnos-in-asm #75 -- RCVMSG vs real-master + tap-induced FIFO overrun (May 16, 2026) — Medium

Session 73e ended with phase 4c+ (real SNDMSG/RCVMSG) FAILing the
`cpnos-mpm-test` oracle: NDOS-driven SELDSK against z80pack mpm-net2
timed out on the 7th header byte (SOH + 5 received, HCS missing).
Phase 4c+ commit (`8d75986`) added per-byte `>XX` / `<XX` wire taps
to `snios_sio_a_rx_to` / `snios_sio_a_tx_a` to localise the loss.

### Diagnosis via cpnos-in-c comparison

Per user "investigate cpnos-in-c where this worked": the C and asm
slaves are identical on the protocol-byte count (1 SOH + 6 more —
whether organised 5+1 or 6+0 is checksum-equivalent), both run with
WR1 polled / no SIO RX interrupts, and the master in
`netwrkif-0.asm:929-935` sends a textbook 7-byte header.  The only
substantive divergence: cpnos-in-c never inlines blocking debug-emit
between successive `recv_byte_t` calls; cpnos-in-asm's phase-4c+
taps do — 3 SIO-B chars per RX byte = ~1.9 ms of blocking poll-and-out
at the shared CTC TC=1 + clk/16 baud (~640 µs / byte).  Z80 SIO RX
FIFO is 3-deep, so a sustained per-byte service time longer than the
master's byte time guarantees overrun within a handful of bytes —
matches the "first 6 OK, 7th lost" trace pattern exactly.

### Fix

Strip per-byte `>XX` / `<XX` and the now-orphaned `emit_hex_a` /
`emit_hex_nyb` helpers from `snios_payload.asm`.  Keep per-frame
markers ('r' / 'S' / 'B' / 'c' / 'T') — those fire once per
handler, never inside the rx hot path.

### Result

6/6 oracles PASS on the same boot path that was 1 FAIL/5 PASS:

  - `cpnos-banner-test`     PASS  banner in display memory
  - `cpnos-siob-test`       PASS  banner on SIO-B
  - `cpnos-sioa-test`       PASS  ENQ on SIO-A (no master)
  - `cpnos-echo-test`       PASS  PING/PONG via Python echo
  - `cpnos-cpnet-test`      PASS  6/6 ACKs + LOGIN OK on SIO-B
  - `cpnos-mpm-test`        PASS  real mpm-net2: LOGIN OK -> 25 dots
                                  -> FETCH OK on SIO-B

PROM1 1950 / 2048 B non-padding (was ~2110 B with taps; ripping
the now-dead `emit_hex_a` cluster recovered ~160 B).

### Followups

  - #76 (`ustack` uninit on `nerror`) becomes inert with #75 fixed —
    NDOS now reaches NTWKBT/FETCH cleanly without entering the
    error path.  Keep the issue open in case a future failure mode
    re-exposes it, but no patch needed today.
  - New memory rule: `feedback_no_taps_in_polled_rx.md` —
    per-byte blocking instrumentation inside polled-RX overruns
    Z80 SIO's 3-deep FIFO.  Generalises the
    "instrumentation introduces the bug it's diagnosing" pattern.

### Difficulty marker

Medium — symptom was easy to misread as a master / wire / timeout
issue (the commit msg author explicitly listed those three as
candidates).  cpnos-in-c side-by-side made the divergence obvious
once the byte-count contracts were confirmed identical: same protocol,
same FIFO, only the asm version inlines blocking debug work between
recv polls.

## Session 73e: cpnos-in-asm bring-up phase 1..3d-γ + autoload polish (May 15-16, 2026) — Hard

End-to-end CP/NET 1.2 slave in pure Z80 assembly, fitting in PROM1
alongside autoload-in-c in PROM0.  Started the session at "scaffold
only" (post-session-73d split); ended with a full bidirectional
frame exchange against a Python fake master, all five MAME-based
value oracles green, PROM1 at 550 / 2048 B (1498 B free).

### Phases shipped (cpnos-in-asm)

| Phase | What | Verified by |
|---|---|---|
| 1 | Stub boots in MAME with banner on CRT | `cpnos-banner-test` |
| 2a | SIO-B TX (banner stream) | `cpnos-siob-test` |
| 2b | SIO-B RX polled echo loop | `cpnos-echo-test` (Python socket) |
| 3a | CP/NET INIT header w/ runtime HCS | siob/sioa-test |
| 3b | DAT section + CKS + EOT | siob/sioa-test |
| 3c | Split: SIO-B = console, SIO-A = CP/NET | both above |
| 3d-α | SIO-A RX -> SIO-B forwarding | manual + Lua snapshot |
| 3d-β | ENQ/ACK handshake on send + RX timeout | `cpnos-cpnet-test` phase A |
| 3d-γ | Receive state machine (RCVMSG) | `cpnos-cpnet-test` phase B |

Final asm sequence on boot:

  1. autoload-in-c (PROM0) inits hardware, fails floppy boot,
     jumps to PROM1 via " RC702" signature.
  2. cpnos-in-asm slave: 8275 stop -> reset+params (non-blinking
     block cursor) -> load cursor -> CTC ch2 IRQ disable ->
     DMA ch2 autoinit at 0xF800 (display relocate; frees
     0x7A00..0x81CF TPA) -> 8275 preset+start -> CTC ch0/ch1 +
     SIO-A + SIO-B init.
  3. Banner to CRT (0xF800) and SIO-B + CRLF.
  4. send_cpnet_init_frame: ENQ -> wait ACK -> SOH+5+HCS ->
     wait ACK -> STX+1DAT+ETX+CKS+EOT -> wait ACK (no retry yet).
  5. Combined poll loop: SIO-A RX dispatches ENQ to
     recv_cpnet_frame (full RCVMSG state machine with HCS/CKS
     validation + ACK or NAK), other bytes forward to SIO-B;
     SIO-B RX echoes on SIO-B.

### Bug fix story (task #66, the time-sink)

phase B of cpnos-cpnet-test failed: slave consistently read
`08 20 20 52 43 37 30` from SIO-A instead of master's
`01 01 FF 00 FF 00 00`.  Diagnosis path:

  1. Phase A (slave-send) worked end-to-end.  Wire layer good.
  2. tasks/sio_a_probe.py confirmed SIO-A RX delivered the right
     bytes when slave was in combined-loop forward path.
  3. Per-byte SIO-B forward inside recv_cpnet_frame's loop showed
     A held correct received bytes.
  4. So `ld (hl), a` was succeeding (A right) but post-loop reads
     from rx_frame_buf returned wrong bytes -- meaning HL pointed
     at non-RAM.
  5. Grep MAME's rc702.cpp found bank2h covering 0x2800..0x2FFF
     as PROM1's "extended-EPROM" mirror.  rx_frame_buf at 0x2800
     was sitting in ROM-mirrored space; writes vanished, reads
     returned PROM1's own first 7 bytes
     (`dw slave_entry; db " RC702"`).
  6. Moved rx_frame_buf to 0x3000 -- everything passed.

Captured as memory rule feedback_rc702_bank2h_mirror.md so future
asm work picks safe BSS regions on the first try.

Also captured feedback_zmac_local_label_scope.md (zmac doesn't
scope dotted labels per parent; multiple `.wait:` collide as
multi-def) -- caught during the same investigation when adding a
sio_b_tx_d helper.

### autoload-in-c polish (same session)

  - SW1 (port 0x14) bit 1 added as PROM1=lineprog selector.
    load_chargen() gated on it (currently commented out anyway,
    since current baseline RC702 has no SEM702 board; the ROA327
    in IC82 provides the font directly to the 8275).
  - SW1 status line drawn on display row 0 right side
    ("SW1 12345678: 00000000") so operator can see DIP settings
    without lifting the cover.  Compact 22-char format chosen to
    fit PROM0 budget.
  - Halt messages moved to row 2 (row 1 blank as separator).
  - `make sw1-test` target: boots autoload with stock-0xFF PROM1,
    greps display memory for the SW1 prefix, PASS/FAIL.
  - MAME's rc702.cpp DIP-switch labels updated to match (S01 =
    rcbios console, S02 = lineprog PROM).
  - Size policy relaxed to soft-warn at 2048 B, hard fail at
    4096 B -- "make it work first, then make it fit" per user
    directive.  Burning real EPROMs still requires <= 2 KB.

### Sizes (final)

  - autoload PROM0: 1846 / 2048 B (202 B free; 6 B over original
    1859 B baseline for the SW1 gate + dispatch).
  - cpnos-in-asm PROM1: 550 / 2048 B (1498 B free).
  - cpnos.bin combined: 4096 B (autoload + asm slave).

### Oracles (final, all green)

| Test | Asserts |
|---|---|
| `cpnos-banner-test` | CRT row 0 banner at 0xF800 |
| `cpnos-siob-test` | Banner on SIO-B raw stream |
| `cpnos-sioa-test` | ENQ-only (no-master case after phase 3d-β) |
| `cpnos-echo-test` | SIO-B probe round-trips through echo loop |
| `cpnos-cpnet-test` | Bidirectional CP/NET 1.2 frame exchange, 6/6 ACKs |

### Memory rules added (this session)

Two specific facts:
  - `feedback_rc702_bank2h_mirror.md` -- 0x2800..0x2FFF is the
    bank2h PROM1-extended mirror; bank1h (0x0800..0x0FFF) is the
    paired bank for PROM0.  Writes vanish, reads return PROM bytes.
  - `feedback_zmac_local_label_scope.md` -- zmac doesn't scope
    dotted local labels per parent; `.wait:` in different
    subroutines collide.  Prefix with subroutine initials
    (`.a_wait`, `.b_wait`).

Three disciplines that would have caught the class of bug
prophylactically (the user prompted me to extract these after the
rx_frame_buf episode -- pre-existing rule
[[feedback-extract-rules-from-time-sinks]] in action):
  - `feedback_grep_memmap_before_bss.md` -- before allocating BSS
    at a literal address on an embedded target, grep the emulator
    driver's mem_map first.  10 s saved several debug iterations.
  - `feedback_verify_writes_before_chasing_reads.md` -- when a
    buffer reads back wrong, the FIRST diagnostic is "did the
    write succeed?" not "where are these bytes coming from?".
    Inverting that order in session 73e cost ~4 iterations on
    red-herring loopback / baud / echo hypotheses.
  - `feedback_recognize_rom_shadow_patterns.md` -- when a buffer or
    port read returns structured-looking "wrong" bytes,
    `xxd build/prom*.bin | head` and grep for the sequence BEFORE
    wire-level hypotheses.  Session 73e: `08 20 20 52 43 37 30`
    was literally `prom1.bin[0..6]`; recognising that pattern
    would have short-circuited the whole investigation.

Project-side mirror: `cpnos-shared/docs/MEMORY_MAP.md` updated
with a "Gotcha" subsection covering bank1h/bank2h so future asm
work (and future maintainers) sees it without having to dig
through MAME source or stumble on the same bug.

### Follow-on tasks filed

  - #67 phase 3e: LOGIN frame (FNC=64, password "PASSWORD") so
    real mpm-net2 master answers.  Today's INIT (FNC=0xFF) is
    ignored by mpm-net2.
  - #68 phase 3f: MAXRETRY=10 whole-frame retries per CP/NET spec.
  - #69 phase 3g: interpret received frames (update slave SID
    from INIT response DAT[0], dispatch BDOS replies, etc.).
  - #70 cpnos-mpm-test: Makefile target patterned on
    cpnos-polypascal-test for end-to-end mpm-net2 verification.
  - #71 build-info in banner (date + short git hash).
  - #55 still pending: RC703 PROM-disable compat audit before
    phase 4 disable-stub lands.
  - #61 still pending: semigraphics QR code at boot in
    autoload-in-c (parked TODO).

### Hard vs Easy

Hard.  Three deep bugs (mid-frame DMA-reprogram CRT artifact,
preset-counters needed between STOP and START, rx_frame_buf in
PROM mirror RAM) that each cost a debug cycle.  Each surfaced as
"output looks subtly wrong" not "build fails" -- the screenshot
rule (always verify CRT visually, not just byte-dump grep) caught
the first two; per-byte instrumentation caught the third.

## Session 73b/c: INC16/DEC16 rematerialization (#115/#27 S3') + prod-target analysis (May 15, 2026) — Medium

After session 73's #165 landed, opened the regalloc-cluster investigation
(`llvm-z80/tasks/plan-115-27-regalloc-cluster.md`).  S2 (hint-flavored
fix) confirmed inert in one session.  S3 (single-register-class `HLReg`
pre-RA pass) deferred via shape-mismatch reconnaissance: aes_mc_inv has
4 simultaneously-live i16 pointer vregs in a single MBB, so pinning one
to HLReg would just relocate the spill to DE/BC.

**S3' lever**: mark `INC16` and `DEC16` pseudos `isAsCheapAsAMove` +
`isReMaterializable` in Z80InstrInfo.td (8 LOC).  Real Z80 INC/DEC rr
(16-bit) does not modify flags, so remat is sound.  Greedy now
recomputes `base+small_const` chains at the use site instead of
spilling each derived pointer to BSS.

**AES corpus** (rc700-gensmedet/tasks/aes256-corpus, 13-config sweep):

| Config | post-#165 | post-S3' | Δ |
|---|---:|---:|---:|
| 01_baseline_Oz | 4205 | 4111 | **−94** |
| 02_Os | 4480 | 4417 | −63 |
| 03_O3 | 12559 | 12472 | −87 |
| 04_O2 | 8529 | 8411 | −118 |
| 05_Oz_static_stack | 2855 | 2830 | −25 |
| 07_Oz_no_lsr | 4571 | 4477 | −94 |
| 08_Oz_gc_sections | 4185 | 4091 | −94 |
| 09_Oz_prod_like | **2695** | **2695** | 0 |
| 12_Oz_no_omit_fp | 3606 | 3568 | −38 |
| 06/10/11/13 (no_licm_cse variants) | unchanged | — | 0 |

8 of 13 configs improved (−25 to −118 B).  No regression on any
config.  Inert on LICM/CSE-disabled configs (which is also the
production knob 09_Oz_prod_like) because LICM creates the cross-
iteration chain that remat unwinds.

**Production-target A/B** (autoload PROM, cpnos-rom resident, rcbios
BIOS): **byte-neutral**.  S3' is workload-limited to AES-shaped
code; production targets don't exhibit the chain pattern.

| Target | Pre-S3' | Post-S3' | Δ |
|---|---:|---:|---:|
| autoload PROM (clang, -Oz -g) | 1861 B | 1859 B | −2 |
| cpnos-rom resident (PIO transport, .payload) | 2003 B | 2003 B | 0 |
| rcbios BIOS | 5925 B | 5925 B | 0 |

CLAUDE.md size figures updated to reflect current reality.  Note:
the prior CLAUDE.md "autoload 1756 B" was the *non-`-g`* size; the
Makefile-default `-Oz -g` build was always ~1861 B.

**Value oracle**: Z80 lit suite 104 PASS + 2 XFAIL (unchanged);
test-runner 685/42/56/207 (identical); AES verifier all 4 cells PASS;
AES tstates 15.7M (unchanged from post-#165).

**Build-infrastructure additions** (`llvm-z80/tasks/tools/`):

1. `llvm-snap.sh` — snapshot bin/clang+llc+ld.lld for A/B (~200 MB,
   ~2 s save vs ~120 s full rebuild).  Use:
   `eval $(tasks/tools/llvm-snap.sh use NAME)`.
2. sccache wired into `build-macos/` cmake cache.  Measured speedup
   on typical iteration:
   - `.cpp` touch + `ninja llc`:      120 s → 18 s  (6.5×)
   - `.td` touch + `ninja clang llc`: 120 s → 42 s  (2.9×)
   Cache lives in `~/Library/Caches/Mozilla.sccache/`.

**Issues filed**:
- ravn/llvm-z80 **#166** — S3'-extension follow-up: investigate
  `ADD_HL_rr` / `LD_HL_a16` rematerialization.  Has potential to
  reach production code (chain root doesn't need LICM).

**TODO (parked)**: investigate why `-Oz -g` autoload PROM links
~100 B larger than `-Oz` alone — referenced as ravn/llvm-z80 #123.

**Commits** (llvm-z80, this session):
- `006ba9607dd1` — [Z80] #115/#27 S3' INC16/DEC16 isAsCheapAsAMove + isReMaterializable
- `6ee7df71a0af` — tasks/tools: llvm-snap.sh + sccache notes
- `da1ac7a33181` — S3 deferred, shape-mismatch reconnaissance (session 73 close-out)

## Session 73: Outside-user allowlist extensions (#165) — gf_log 153 → 28 B (May 15, 2026) — Medium

Extends `TruncInstCombine`'s outside-graph user allowlist with two
parallel paths, both addressing residual blockers in the gf_log-shape
phi loop in `aes256.c` (post-#162 path 2).

**Path A (icmp non-const Other)** — companion of #160.  When the
icmp's non-graph operand is provably narrow via `computeKnownBits`
(e.g. `(and W, 2^M - 1)`), narrow alongside the graph.  Cost-gate:
`Other->hasOneUse()`.

**Path B (and-mask outside-user)** — dominant blocker for gf_log.
Accept `(and X, Const)` where X is in-graph and Const fits in the
narrow type.  Rewritten as `(zext (and Xnarrow, ConstTrunc) to OrigTy)`
so downstream consumers keep their original type; InstCombine
canonicalises the zext-and-consumer chains afterward.

**Latent bug fixed**: phi-erase RAUW'd in-graph phis with poison
BEFORE the rewrite loops, leaving outside-graph users (icmp or
and-mask) holding poison operands.  `cast<ConstantInt>(poison)` →
crash.  Fix: reorder so rewrite loops run first, phi-erase last.

**Phase-2 (and-mask synthetic trunc root, #163) transient flag**:
The parent And being narrowed gets erased by phase 2 itself.  Added
`AndMaskParentSkip` transient member set by phase 2 so the outside-
user check ignores the parent.

**Results** (AES corpus, key functions):

| Function | post-#162-p2 | post-#165 | Δ |
|---|---:|---:|---:|
| `gf_log` | 153 | **28** | **−125 (5.4×)** |
| (rest of corpus stable) | | | |

13/13 AES configs improved, range −26 to −129 B.  Production knob
`09_Oz_prod_like` 2721 → **2695 B**.  Runtime tstates dropped 65M →
15M on baseline_Oz (4× speedup); 22M → 15M on production knob (30%
speedup).  Test-runner clean (685 / 42 / 56 / 207).  All 4 AES
verifier cells PASS.

Commit `c48824ce135f` merged --no-ff.

## Session 72: TruncInstCombine cost gate (#164) + per-callee body peek (#162 path 2) — closed #162 + #163 (May 15, 2026) — Medium

Two AggressiveInstCombine extensions in llvm-z80, both driven by the
AES-256 corpus parity work.

**#164 phase 1 (`d7c37aa6e928`)** — plumbed `TargetTransformInfo`
through `TruncInstCombine` and added a phase 2 of `run()` that
synthesises a trunc-rooted graph from `(and X, MASK)` patterns where
`MASK = 2^M - 1`.  Cost gate `!hasOneUse && !isZExtFree(NarrowTy, OrigTy)`
suppresses Z80 regressions; on x86 family the synthetic root fires
unconditionally and upstream `trunc_multi_uses.ll` PASSes via the new
path.  Z80 outcome: inert by design (AES corpus byte-identical).  Side
fix: pre-existing UB in `getMinBitWidth` when trunc's direct operand
is an Argument (`cast<Instruction>` without check).  Closes #163 as
infrastructure-landed.

**#162 path 2 (`86eded565de7`)** — phase 3 of `run()`: walk call sites,
peek each callee's entry block for either `trunc iW %argN to iM` or
`(and iW %argN, 2^M - 1)`, and on a match inject a synthetic
`(zext (trunc V to iM) to iW)` bracket at the call boundary so the
narrowing engine can shrink V's chain.  Critical ordering subtlety:
swap the call's argument to the synthetic Zx **before** probing,
otherwise multi-use guard bails.  Closes #162 (K&R u8 chain).

**Results**:
- `rj_sb_inv` K&R: 156 → **36 B** (−120, 4.3×, matches ANSI)
- AES corpus: 11/13 configs improved 84–121 B
- Production knob `09_Oz_prod_like`: 2806 → 2721 B (clang now beats
  zsdcc by 883 B on AES-class C code)
- Best non-static-stack `13_Oz_no_omit_fp_no_licm_cse_gc`: 3488 → 3373 B
- z80-utils test-runner: 685/42/56/207 unchanged

**Filed**: ravn/llvm-z80#165 (extend icmp outside-user to narrowable
non-constant operands) for the remaining `gf_log` 153 B / 4.78× gap —
phi-loop pattern with `icmp eq i16 %6, %2` where both operands are
narrowable but neither is a `ConstantInt`.

**Issues closed**: #162, #163.
**Issues open**: #164 (phase 2 byte-budget), #165 (NEW).

Detailed summary: [`llvm-z80/tasks/session72-truncinstcombine-cost-gate-and-callee-peek.md`](../../llvm-z80/tasks/session72-truncinstcombine-cost-gate-and-callee-peek.md).

## Session 71: HiTech V4.11 cross-compiler deep-dive — RE-PARKED (May 13, 2026) — Hard

Followup to session 70's V3.09-only parking. Discovered the V4.11
DOS-hosted cross-compiler (Microchip 2018 freeware release; agn453
vendoring at `ravn/hitech-v411`) has the ROM-target features V3.09's
manual described but freeware lacked: ROM as default, `-A
ROMADR,RAMADR,RAMSIZE`, native `interrupt` / `port` qualifiers,
ROM library, inlined function prologue/epilogue saving ~40% on
microbenchmarks.

Built a Docker wrapper around V4.11 (DOSBox), an integration test
suite, and DOS-side diagnostic tools (`runcap.com` for INT 21h/46h
stderr capture, `scrdump.com` for VGA text-buffer dump). Committed
to ravn/hitech-v411 (commit `b9c02d7`).

Added a HITECH compile path to `rc700-gensmedet/autoload-in-c/`
(commit `c131b85`): SECTION/NORETURN/USED macro shim layer, HITECH
branches in rom.h, `hitech/` subdir with banner/stdint shims and
build-htc.sh (host gcc -E + python filter + DOSBox p1+cgen+zas).
`intvec.c` and `boot_rom.c` compile cleanly under V4.11 end-to-end.

`rom.c` does NOT compile. V4.11 cgen.exe has two structural bugs
blocking it:

  Bug V4.11-A: trees.c:1230 'tp->t_type' assertion on (i) compound
  shift `tb <<= 1` on word, (ii) sizeof(struct) as loop bound,
  (iii) cast-then-index `((byte *)&fdc_cmd)[i]`.  Per-site rewrites
  fix each, but Bug B fires next.

  Bug V4.11-B: sym.c:433 'pp->s_nelem == 0' assertion -- V4.11 cgen
  conflates struct member count with array element count, then scalar-
  only paths trip on the struct symbol's non-zero count.  Fires on
  `fdc_cmd = {0};`, `fdc_result = {0};`, `(byte *)&fdc_cmd`.  Structural;
  requires reshaping the struct globals to byte arrays + named indices,
  ~30-50 sites.

These were invisible in headless mode: V4.11 writes errors to BIOS
console rather than handle 2, and DOSBox 0.74 in headless drops it
all.  Identified by writing scrdump.com (a 60-byte DOS tool that
reads the text-mode VGA buffer at B800:0000) and running V4.11
interactively in DOSBox Staging.  The screen text revealed the
specific cgen assertion mechanism.

Full analysis in `tasks/hitech-shortcomings-report.md` (the comprehensive
parking report covering both V3.09 and V4.11 investigations).

### Re-park reasoning

Same value-calculus conclusion as session 70: clang Z80 with `sdcccall(1)`
+ `z80_preserves_regs` will beat 1989/1992-era HiTech on byte count
for any register-pressure-sensitive code.  HiTech is fundamentally a
stack-args compiler; no flag, pragma, or attribute changes that.

V4.11 specifically also has cgen bugs that block the most-relevant
source file (rom.c).  Fixing requires either source restructuring
(~30-50 site refactor of struct globals to byte arrays) or
compiler-side fixes that aren't possible because V4.11's cgen source
isn't shipped (only the ZC.C driver source ships in the freeware).

### Cumulative findings recorded

  ravn/hitech (V3.09): 4 bugs filed and fixed (issues #1-#4); docs note
  open as #5.  ghcr.io/ravn/hitech:latest now passes its 11-cell suite.

  ravn/hitech-v411: Docker wrapper + tests + tools committed.  Two cgen
  bugs identified, no fix possible without source we don't have.

  rc700-gensmedet/autoload-in-c: HITECH compile path landed in `c131b85`,
  intvec.c+boot_rom.c compile clean, rom.c partial.  Workaround sweeps
  attempted and reverted; final state has the macro shim layer + sources
  unchanged.

### Files touched

  rc700-gensmedet/tasks/hitech-shortcomings-report.md  (this entry's
                                                       full backing report)
  rc700-gensmedet/tasks/hitech-port-parked.md          (cross-ref updated)
  rc700-gensmedet/tasks/timeline.md                    (this entry)

### Why "Hard"

V4.11 internals are closed-source.  Diagnosis required writing two
NASM-built DOS .COM tools (runcap, scrdump) to capture state that
DOSBox in headless mode silently discards.  V3.09 source (Nikitin
RE) had to be read carefully as a proxy for V4.11 internals (sufficiently
similar but not identical).  Each of the two cgen bugs surfaced only
after an interactive lab session was set up.  Long tail of false-start
hypotheses ("DOSBox file flush issue", "6KB output buffer", "Out of
memory") were ruled out by direct experiment before the actual
mechanism (cgen assertion failures) became visible.

## Session 70: HiTech-C investigation + ravn/hitech bug sweep — port PARKED (May 13, 2026) — Medium

Investigated using `ghcr.io/ravn/hitech` (vendored HI-TECH C 3.09)
as a third compiler alongside clang Z80 and SDCC. Found and fixed
real bugs upstream; concluded the source-side port is doable but
not worth the work given the value gap. Full parking note:
`tasks/hitech-port-parked.md`.

### `ravn/hitech` bug sweep — 4 issues filed, 4 fixes merged

Image was effectively broken for any non-trivial input: `zc -O`
produced "optim: Can't find op" on almost every C source. Root
cause: `optim/optim.c:1189` declared `char cmp` then stored
`strcmp()`'s return; on aarch64 Linux (char defaults to unsigned
per AAPCS64) the `cmp < 0` test was always false, making the
binary search of the 110-entry `operators[]` table unreachable for
roughly half of all Z80 mnemonics including `ld`, `add`, `jr`,
`djnz`. Identical idiom to the cgen fix already landed in
ogdenpm/hitech PR #6 — that PR didn't sweep sibling tools.

| Commit | Issue | Fix |
|---|---|---|
| `6b07966` | #1 | `optim/optim.c:1189` `char cmp` → `int cmp` |
| `546cab1` | #4 | latent `uint8_t hi/lo/mid` widened to `int` in optim/cgen/p1 binary searches |
| `3515251` | #3 | `-fsigned-char` added to global `CFLAGS` in `Linux/hi.mk` |
| `596cf3c` | #2 | `tests/Makefile` adds 5 `zc -O` cells (`helloO/prfmtO/stropsO/arithO/pairO`) |

All four pushed to `ravn/hitech` `main`; Container CI republished
`ghcr.io/ravn/hitech:latest` for each. Integration suite is 11/11
green (5 base + 5 -O + 1 negative) on the published image.
Issue #5 (docs note on V3.09 manual claims vs freeware reality)
remains open as documentation, not a bug.

Optim now actually shaves bytes: hello -14, prfmt -38, strops -69,
arith -42, pair -44 — small fractions of total, but real and
verifiable.

### Why the port is parked (full reasoning in `hitech-port-parked.md`)

Three weighted reasons:

1. **Stack-only calling convention, no escape hatch.** HiTech V3.09
   hardwires `call ncsv / (ix+N) args / jp cret` for every function.
   No flag/pragma/attribute switches to register-passing. The
   user's framing was "use HiTech as a reference for Z80 codegen
   clang should aspire to" — but clang with `sdcccall(1)` +
   `z80_preserves_regs` will beat 1989-HiTech-stack-args on byte
   count for any register-pressure-sensitive code (session 58 saved
   36 B on `xport_send_byte` callers via exactly this). HiTech
   serves as a qualitative instruction-selection reference, not a
   quantitative byte-count target. Smaller value than imagined.

2. **Source-language adaptation cost.** 35 .c+.h files contain
   substantial C23/C99 surface that HiTech's K&R-ANSI parser
   rejects: `inline` (93), C23 SDCC-compat attributes (219),
   `0b…` literals (42), `_Static_assert` (14), `address_space(2)`
   (12), for-loop decls (10), plus unknown count of mid-block
   declarations. Estimate: 1.5d cpnos-rom + 1d rcbios-in-c + 0.5d
   autoload-in-c. Mechanical but tedious.

3. **Manual ≠ freeware reality.** The V3.09 manual describes a ROM
   cross-compiler mode (`-A ROMADR,RAMADR,RAMSIZE`, ROM startoff
   .obj, `interrupt`/`port` qualifiers) that was part of HI-TECH's
   commercial product and never entered the agn453 freeware
   vendoring. We'd be writing the ROM startup, the linker
   invocation, and asm wrappers for ISRs and port I/O ourselves —
   that's possible (`csv.obj`/`brelop.obj` in `libc.lib` are
   bare-metal-safe, and `link -Ptext=ADDR,bss=ADDR -Cbase` placement
   works) but expands the per-subproject Makefile rework.

A `zc -C -DHITECH=1 -UCPM` dry-run against `autoload-in-c/boot_rom.c`
hit the wall on item 2 immediately (`static inline` and
`address_space(2)` both reject at parse time), confirming the
estimate before deeper investment.

### Resume conditions

See `tasks/hitech-port-parked.md` for full unblockers. Headline:
pick scope first (codegen-reference-only is dramatically cheaper
than bootable-ROM), then start with `compat.h`'s already-stubbed
`__HITECH__||HI_TECH_C` branch and grow outward. Drop the
"quantitative byte-count comparison" framing — that goal isn't
reachable through HiTech V3.09.

### Files touched (rc700-gensmedet)

- `tasks/timeline.md` — this entry
- `tasks/hitech-port-parked.md` — new, parking note + resume plan

Nothing in `cpnos-rom/`, `rcbios-in-c/`, or `autoload-in-c/`
changed — investigation was read-only against our sources.
`compat.h` and `hal.h` `__HITECH__` stubs remain `#error`'ed as
before.

### Files touched (ravn/hitech)

- `optim/optim.c`, `cgen/cgen.c`, `p1/lex.c` — widened types
- `Linux/hi.mk` — `-fsigned-char`
- `tests/Makefile` — 5 new -O cells

### Why "Medium"

Bug investigation was satisfying and yielded real fixes that
benefit anyone using the image. Port-scoping was harder than
expected because the manual misled on multiple fronts; that
asymmetry cost a couple of iterations. The parking decision
itself is clean.

## Session 59b: smoke harness rehab (#98 + #99) — sio-smoke green end-to-end (May 11, 2026) — Easy

Followup to session 59.  Fixed the two pre-existing smoke-harness
issues caught during session 59's runtime verification, and got
`sio-smoke` to runtime-PASS for the first time since the slave's
default drive moved from A: to E: in Phase 27 (2026-04-28).

### #98: drive-letter-agnostic CCP prompt match

`testutil/smoke_inject.py` was hardcoded to wait for `A>` as the
CCP prompt before sending the next workload step.  With the
post-Phase-27 default drive now `E:`, every workload's first step
never fired (`steps sent: 0/3`).

- Restructured `WORKLOADS` from `[(prompt, cmd), ...]` to
  `[cmd, ...]` — prompts are all the same (CCP), no per-step
  variation needed.
- New `_is_ccp_prompt(buf)` helper matches any `[A-P]>` at the
  buffer tail (CP/M supports up to 16 drives).
- Caller `maybe_fire_step()` uses the helper instead of literal
  byte-tail comparison.

### #98 follow-on: workload drive switch

`A>`-fix alone wasn't enough — the slave defaulted to `E:` (local
netboot drive, carrying cpnos.com + PolyPascal payload), but
`M80.COM` / `L80.COM` / `sumtest.asm` live on slave `A:` (mapped
to MP/M's `drivea.dsk` per `init.c:147` cfgtbl_init_template).
Sending `m80 ...` on E: produced `M80?` (CP/M unknown-command).

Prepended an `A:\r` step as the first command in every workload
(`sumtest`, `filecopy`).  4-step workload now: A: -> m80 -> l80 ->
sumtest.

### #99: daemon cleanup discipline

Five test targets (`cpnet-smoke`, `pio-irq-netboot`,
`pio-irq-smoke`, `cpnos-polypascal-test`,
`cpnos-bios-jt-trace`) each had a 7-line entry preamble of
`screen -X quit / sleep / lsof check / error-if-busy`.  That
preamble only killed the screen master — orphan
`login -pflq ravn ./mpm-net2` children got reparented to PID 1
and outlived screen.  Subsequent runs erroed on :4002 still bound
and the user had to manually pkill (session 59 friction).

- New `.PHONY: _kill-mpm` Make target factors the cleanup into one
  recipe: screen -X quit + pkill the login chain + pkill cpmsim +
  verify :4002 free at the end.
- Replaced the five 7-line preambles with `$(MAKE) _kill-mpm`.
- Added `-$(MAKE) _kill-mpm` after every MAME run (best-effort
  exit-side reap so successful runs don't leak daemons either).
- `make _kill-mpm` is idempotent on a clean state (no-op).

### Verification — sio-smoke end-to-end PASS

First successful `sio-smoke` since Phase 27.  Run from a clean
state with both fixes active:

```
[step 0] CCP prompt b'E>' matched; sending b'A:\r' (t+0.000s)
[step 1] CCP prompt b'A>' matched; sending b'm80 sumtest,=sumtest.asm\r' (t+0.579s)
[step 2] CCP prompt b'A>' matched; sending b'l80 sumtest,sumtest/n/e\r' (t+30.578s)
[step 3] CCP prompt b'A>' matched; sending b'sumtest\r' (t+35.500s)
[marker] CPNET OK found (bench=36.354s)
peer closed
done (steps sent: 4/4, marker seen: True)
...
A>sumtest
CPNET OK A314

PASS: marker 'CPNET OK A314' present
BENCH (-nothrottle, m80+l80+sumtest): bench=36.354s
```

- M80 assembled sumtest.rel
- L80 linked sumtest.com
- `sumtest` ran to completion and emitted the deterministic
  `CPNET OK A314` marker (16-bit sum of 1..1000 = 0xA314)
- bench=36.354s
- Exit-side `_kill-mpm` ran; no daemon leak
- Total wall: 46 s (vs 4-minute timeout pre-fix)

This run also **closes the runtime loop** on session 59's SIO
push-de/pop-de correctness fix: M80 + L80 + sumtest each call
through `_xport_send_byte` -> `_transport_send_byte` thousands of
times, each push/pop'ing D correctly to preserve SNIOS state
across the call.  Prior to session 59 this would have worked by
coincidence-of-protocol; now it's honest.

### Pre-existing files touched

- `cpnos-rom/Makefile` — `_kill-mpm` recipe; five entry-side
  cleanup replacements; five exit-side reaper additions.
- `cpnos-rom/testutil/smoke_inject.py` — `WORKLOADS` simplified,
  `_is_ccp_prompt()` helper, drive-switch `A:` prepended.

### Why "Easy"

Two filed issues; mechanical fixes; runtime test exposed a third
sub-issue (drive switch) the audit didn't anticipate; one more
edit closed it.  Total ~30 minutes including the two `sio-smoke`
runs.  Both issues closeable.


## Session 59: z80_preserves_regs Part C — close latent TRANSPORT=sio correctness gap (May 11, 2026) — Easy

Picked up ravn/rc700-gensmedet#97 Part C: mirror
`PRESERVES_REGS_CLANG` to `transport.h` + `cpnos_main.c`.  Part A
already obviated by session 58's #133 layer 1 work; Part B audit
re-confirmed (recv-side `("b")` annotation costs +4 B with no
caller-side win — recorded in `snios_c.c:96-111`).

During the audit I caught a **latent correctness gap on
TRANSPORT=sio**: snios_c.c declares `xport_send_byte` preserves D,
which under `TRANSPORT=sio` `--defsym`-aliases to
`_transport_send_byte`.  Clang's SIO body uses `ld d,a` to stash
the `c` argument across the IN-loop just like the PIO body — but
`transport_sio.c` had no matching `PRESERVES_REGS_CLANG` on its
definition, so #133 layer 1 didn't fire, no push/pop wrapped the
body, and SNIOS callers were silently relying on the body's
coincidental `ld a,d ; out (..),a` to restore D=c (true only
because the value clobbered IS the argument).  The 4-cell test
passed by coincidence-of-protocol.

### Changes

- `transport.h` — `transport_send_byte` declaration gets
  `PRESERVES_REGS_CLANG("d","e","h","l","b","c")`; recv stays
  unannotated per snios_c.c audit.  `#include "compiler/compat.h"`
  added for the macro.
- `transport_sio.c` — `transport_send_byte` definition gets the
  matching `PRESERVES_REGS_CLANG(...)` so #133 layer 1 fires.
  `Z80FrameLowering` emits `push de` in prologue + `pop de` in
  epilogue.  Body cost +2 B; correctness now honest end-to-end.
- `cpnos_main.c` — externs for `transport_pio_send_byte` /
  `transport_pio_recv_byte` (gated by `PIO_SPEED_TEST` /
  `PIO_LOOPBACK_TEST`) get the matching annotation on send; recv
  unannotated.  Init-time path; zero observed delta on production
  build.

### Verification — 4 cells + runtime

| Cell | Resident pre | Resident post | Delta |
|---|---|---|---|
| clang+pio-irq | 1906 B | **1906 B** | 0 |
| clang+sio     | 1818 B | **1820 B** | **+2 B** (push de / pop de) |
| sdcc+pio-irq  | 1875 B | 1875 B | 0 (SDCC ignores macro) |
| sdcc+sio      | 1875 B | 1875 B | 0 |

- `make cpnos-polypascal-test COMPILER=clang TRANSPORT=pio-irq`
  → **PASS** (all 5 stages, 29989 seen, Q→E>, 47 s wall).
- `make sio-smoke COMPILER=clang TRANSPORT=sio` exercises the
  SIO send path through netboot + login + `dir`; slave reaches
  `E>` with `2026-05-11 13:56 9ff8a61+` banner.  Final marker
  check `CPNET OK A314` FAILED — pre-existing harness bug
  (`smoke_inject` waits for `A>` but default drive is now `E:`,
  flagged as caveat in this file at line 3927).  Byte-transport
  itself is exercised hundreds of times before the failed grep,
  proving the +2 B push/pop fix is runtime-clean.

### Inline asm verification

Disassembly of the new SIO send body (TRANSPORT=sio + clang):

```
0000f0d2 <_xport_send_byte>:
    f0d2: d5           push de       ; <- new
    f0d3: 57           ld   d,a
    f0d4: db 0a        in   a,($a)
    f0d6: e6 04        and  $4
    f0d8: 28 fa        jr   z,$f0d4
    f0da: 7a           ld   a,d
    f0db: d3 08        out  ($8),a
    f0dd: d1           pop  de       ; <- new
    f0de: c9           ret
```

11 B → 13 B.  D is now genuinely preserved by callee push/pop, not
by argument-equals-clobber coincidence.

### Issues touched

- ravn/rc700-gensmedet#97 — Part A obviated by session 58;
  Part B audit closed (no shippable set on recv-side without
  body refactor); Part C **done**.  Recommend closing #97.

### Why "Easy"

Single design decision (mirror declaration + audit SIO definition);
edits surgical; verification mechanical (4 builds + 1 polypascal +
1 smoke); the latent SIO correctness gap was a bonus catch on top
of the originally-scoped consistency work.


## Session 58: z80_preserves_regs end-to-end (clang frontend + backend + cpnos), -36 B resident (May 11, 2026) — Medium

Closed the pure-C-vs-asm SNIOS spill-traffic gap diagnosed in the
prior session's investigation by building out the
`z80_preserves_regs` attribute end-to-end.  Resident payload
1964 B -> **1928 B** (-36 B / -1.8 %, matches the lower end of the
ravn/llvm-z80#131 original 30-50 B estimate).

### Phases

- **#131 caller-side backend** (llvm-z80 `2940fec8`): `Z80CallLowering`
  reads the callee's `"z80-preserves-regs"` LLVM IR function attribute
  via `Info.CB->getCalledFunction()->getFnAttribute(...)`, narrows the
  call-site RegMask by setting bits for the declared regs + sub-regs,
  and strips the matching `implicit-def` operands from the `CALL_nn`
  MI (since CALL_nn's TableGen `Defs = [A, BC, DE, HL, IY, FLAGS]`
  otherwise override the RegMask per LLVM semantics).  Lit fixture
  `preserves-regs.ll`.

- **#131 clang frontend** (llvm-z80 `70eed199`): new
  `Z80PreservesRegs` attribute in `Attr.td` with
  `VariadicStringArgument`, function-only subject, validated against
  the register-name set in `SemaDeclAttr.cpp`, lowered in
  `CGCall.cpp::ConstructAttributeList` to the IR string attribute
  `"z80-preserves-regs"="d,e,..."`.  Custom diagnostic
  `err_z80_preserves_regs_unknown` for unrecognised register names.
  Sema + CodeGen lit fixtures.

- **cpnos-rom integration** (rc700-gensmedet `773c641`, `51082c8`,
  `e4857e8`): `xport_send_byte` declared
  `PRESERVES_REGS_CLANG("d","e","h","l","b","c")` in `snios_c.c`,
  with a matching `PRESERVES_REGS_CLANG` on
  `transport_pio_send_byte`'s definition in `transport_pio.c`.
  New `PRESERVES_REGS_CLANG(...)` macro in `compiler/compat.h`
  bridges the syntax gap (SDCC's `__preserves_regs(d, e)` takes
  bare identifiers; clang's takes string literals).  Bisected the
  preserved set against `cpnos-polypascal-test` empirically.

- **#133 layer 1: callee-side honoring** (llvm-z80 `f1a4200`):
  `Z80RegisterInfo::getCalleeSavedRegs` extension that builds a
  per-function CSR save list when the function carries the
  attribute.  PEI's `spillCalleeSavedRegisters` (unchanged) then
  emits `push de` in prologue and `pop de` in epilogue for any
  declared-preserved register the body modifies — making the
  attribute a genuine end-to-end assertion, not just a programmer's
  unenforced promise.  Lazy per-function cache in
  `Z80FunctionInfo::ExtendedCSRSaveList`.  Pair completion: lone
  halves promote to their pair (Z80 push/pop is pair-granular).
  Lit fixture `preserves-regs-callee.ll`.

- **pio_b_set_input tightening** (rc700-gensmedet `7958021`): the
  one-A-write helper called from inside `transport_pio_recv_byte`
  declared `PRESERVES_REGS_CLANG("b","c","d","e","h","l")` on its
  definition.  Body cost zero (no body-modified regs from the
  declared set); caller-side
  `push hl ; call _pio_b_set_input ; pop de` collapses to a single
  `ex de,hl` (-1 B in recv body, absorbed by alignment in total
  payload).

### New issues filed

- ravn/llvm-z80#132 — cross-MBB BSS-spill->PUSH/POP peephole
  (SP-balance correctness across bypass-LOAD escape edges, gated
  on adding `MachineDominatorTree` to `Z80LateOptimization`).
- ravn/llvm-z80#133 — callee-side honoring layer 1 (done) +
  layer 2 (regalloc allocation-order tweak, open) +
  `-Wz80-preserves-regs-violation` diagnostic (open).
- ravn/llvm-z80#134 — initially filed for an "all-three-pairs
  regression" that turned out to be a test-harness flake
  (`cmp -l` showed byte-identical binaries).  **Closed as
  not-a-bug** + memory rule extracted (see below).
- ravn/rc700-gensmedet#96 — `cpnos-polypascal-test` orphan
  cpmsim leak (`./cpmsim` instead of `exec ./cpmsim` in
  `mpm-net2`).  One-line fix proposed.
- ravn/rc700-gensmedet#97 — expand `z80_preserves_regs` coverage:
  Part A obviated by #133 layer 1.  Parts B (recv body refactor)
  and C (transport.h + cpnos_main.c declarations) still pending.

### Issues closed in code

- ravn/llvm-z80#129 — closed with explanatory comment: in-MBB
  BSS-spill->PUSH/POP peephole was already complete in tree (line
  4859 since `0c74b56` 2026-03-27, cross-class extension at line
  5104 in `fc34593` the prior HEAD).  Empirical awk scan of
  `cpnos.lis` for `STORE_BSS rr ; CALL ; LOAD_BSS rr` with no
  intervening terminator: zero residuals.  Cross-MBB form (the
  SNIOS-pattern residual) split out as ravn/llvm-z80#132.

### New memory rules

- `feedback_dont_kill_ninja.md` — SIGTERM/SIGKILL on ninja
  truncates `.ninja_log`; the next run prints "premature end of
  file; recovering" and conservatively rebuilds 1700+ steps.
  Wait builds out; if interrupt is essential, Ctrl-C ONCE; never
  run two ninja processes against the same `build-macos/`.
- `feedback_diff_binaries_before_blaming_codegen.md` — when two
  compiler configurations seem to "behave differently",
  `cmp -l a.bin b.bin` FIRST.  Byte-identical binaries can't have
  a codegen miscompile; the failure is environmental.  Caught
  the ravn/llvm-z80#134 phantom regression after I'd already
  bisected attribute subsets and filed an issue.

### Final state

| Metric | Pre-session | Post-session | Δ |
|---|---:|---:|---:|
| cpnos resident (clang+pio-irq) | 1964 B | **1928 B** | **-36 B** |
| LLVM Z80 lit suite | 90 PASS + 2 XFAIL | **91 PASS + 2 XFAIL** | +1 PASS (new fixture) |
| test-runner clang -Oz | 113 PASS / 0 FAIL | **113 PASS / 0 FAIL** | unchanged |
| cpnos-polypascal-test 4-cell | PASS | **PASS** | unchanged |

Engagement-mode gate from the roadmap (Phase 3 Cluster A close):
**satisfied under both loose and strict readings** after this
session.  Remaining residuals (cross-MBB BSS-spill #132,
`z80_preserves_regs` callee-side layer 2 in #133, recv-side body
refactor in `rc700-gensmedet#97 Part B`) are all well-scoped
multi-session follow-ups.



User: "goal is still to have clang emit better code aspiring to
reach handwritten assembly.  Investigate"  /  "and if clang needs
fixing raise that issue".

### Analysis

Current pure-C clang sizes:
- `_snios_rcvmsg_c`: 384 B C vs 154 B asm (`-230` B / `-60 %`)
- `_snios_sndmsg_force`: 265 B C vs 114 B asm (`-150` B / `-57 %`)

Per-slot spill traffic in `_snios_rcvmsg_c` (15 sites, 29 BSS
events):
- slot-2: 6 stores + 6 loads (the `uint16_t r` recv result)
- slot-8: 1 store + 3 loads (likely msg ptr, set once, read in
  three separate phases)

The hand-rolled asm keeps `D` (running checksum), `E` (byte
counter), `HL` (msg ptr) alive across recv calls **because it
knows the recv routine preserves them**.  Clang's default
sdcccall(1) treats EVERY call as clobbering everything except IX,
so values must be spilled to BSS before each call and reloaded
after.

### Source-level workaround attempts

Tried inlining `(uint8_t)recv_byte_t()` cast directly at the
timeout-fold sites (eliminating the `uint16_t r` named local).
clang's optimizer already produces identical code — no change.

The bottleneck is genuinely **regalloc behavior across CALL
boundaries**, not C-source-level patterns.

### Backend fix needed

Filed `ravn/llvm-z80#131` for a clang Z80 calling-convention
attribute analogous to SDCC's `__preserves_regs(d, e)`.  Estimated
savings on cpnos-rom SNIOS: 70-110 B clang once implemented,
closing most of the 312 B asm-vs-C gap.

Other relevant filed issues remain open:
- #128 (LICM/CSE pessimize at -Oz; workaround in Makefile)
- #129 (BSS-spill peephole; cross-class single-load implemented
  Phase 65; cross-BB extension would help more)
- #130 (memset_pattern lowering; mostly subsumed for
  constant-pattern case)
- #131 (preserves_regs attribute; HIGHEST LEVERAGE for the
  remaining pure-C gap)

### Pure-C ceiling

Without backend changes: ~1964 B clang payload.  Phase 64's asm
rewrite reached 1652 B, parity with hand-rolled assembly.  The
gap (312 B) is structurally addressable only via the Z80 backend
changes filed above; no source-level pure-C work can close it.

## Phase 68: revert SNIOS to plain C (May 10, 2026) — Easy

User: "i'd rather continue with the new c code instead of the
assembly".

Phase 64 had rewritten the SNDMSG/RCVMSG state machines as inline-
asm bodies in `__naked` C functions, saving 312 B clang / 272 B
SDCC at the cost of maintainability.  User now prefers the pure-C
version (Phase 63 baseline with all Phase 62 source-level
optimizations).

**Reverted** `cpnos-rom/snios_c.c` to the pre-Phase-64 content (git
`70db0df:cpnos-rom/snios_c.c`).  Restored:
  - `try_send_frame`, `try_recv_frame` as plain-C state machines
  - `snios_sndmsg_force` / `snios_sndmsg_c` as plain-C functions
  - `snios_rcvmsg_c` as a plain-C function
  - All Phase 62 source-level optimizations preserved (timeout-fold,
    direct slaveid check)

**All other session phases stay in place** — they're orthogonal to
the SNIOS body choice:
  - Phase 65 (cross-class BSS-spill peephole in llvm-z80) — helps
    pure-C builds too (just less dramatically)
  - Phase 66 (scroll_lines unify, crlf factor, install_fcb fold)
  - Phase 67 (setup_ivt volatile drop)
  - Phase 62-63 Makefile flags (`-disable-machine-licm`,
    `-disable-machine-cse`)

**IX-frame baseline** restored: `try_send_frame:2` and
`try_recv_frame:10` re-added (same counts as Phase 62-63; Phase 65's
peephole is clang-only and doesn't affect SDCC's iCode allocator).

Sizes:

  | metric              | post-Phase-67 (asm) | post-Phase-68 (C) | Δ    |
  |---------------------|--------------------:|------------------:|-----:|
  | clang payload       |               1652 |              1964 | +312 |
  | SDCC resident       |               1796 |              2068 | +272 |
  | clang INIT_CODE     |                627 |               627 |    0 |

Cumulative session vs pre-session HEAD:

  | | clang payload | SDCC resident |
  |---|---:|---:|
  | Pre-session         | 2138 B | 2152 B |
  | Post-Phase-68 (C)   | **1964 B (-174 / -8.1 %)** | **2068 B (-84 / -3.9 %)** |

Both compilers PASS cpnos-polypascal-test 4-cell at parity (clang
49.75 s, SDCC 49.79 s).

## Phase 67: drop volatile from setup_ivt (-3 B), filed llvm-z80#130 (May 10, 2026) — Easy

User asked me to plan llvm-z80#130 (Recognize and lower memset_pattern
for arbitrary fill widths via LDIR-overlap).  Step 0 of the plan
("verify the IR pipeline emits the intrinsic") immediately produced a
surprising result:

- Built a minimal repro: `fill_ivt(uint16_t *ivt)` with the
  18-iteration constant-fill loop, **no volatile**.
- Compiled with current `-Oz`: **clang already emits LDIR-overlap**
  (~17 B function).  `LoopIdiomRecognize` converted the loop to
  `store + memcpy(dst+P, dst, (N-1)*P)` at IR level; Z80 ISel
  lowered the overlapping memcpy to LDIR (which IS the
  pattern-fill idiom by Z80 semantics).

- Re-tested with `volatile uint16_t *`: clang fell back to a
  per-iteration loop (~22 B).  The volatile qualifier matches
  `LoopIdiomRecognize::isLegalStore`'s first guard
  (`if (SI->isVolatile()) return None`) and bypasses LIR entirely.

**The volatile was blocking the optimization in cpnos-rom's
setup_ivt.**  Posted the testcase + finding as a comment on
`ravn/llvm-z80#130` (https://github.com/ravn/llvm-z80/issues/130#issuecomment-4416394819);
downgraded the issue's scope — the constant-pattern case is
already handled, only the runtime-pattern-pointer case (rare in
practice) would need new backend work.

**Cpnos-rom fix:** dropped the local `volatile` from setup_ivt's
`ivt` pointer.  Safe because setup_ivt runs once before EI/IM2 with
no other CPU activity.  Saves **−3 B INIT_CODE** (630 → 627 B).

Captured the underlying rule in user-side memory as
`feedback_volatile_blocks_loop_idiom.md` — default-adding
`volatile` is a Z80 footgun because it blocks the most powerful
size-reducing pass (LIR → memset/memcpy/LDIR).

## Phase 66: scroll_lines unify + crlf factor + install_fcb fold (May 10, 2026) — Easy

User said "i still want to apply all those things you suggested
earlier" (referring to remaining candidates from `#95`).  Applied:

- **scroll_lines unify**: collapsed `delete_line` (71 B) + `insert_line`
  (76 B) into one `scroll_lines(uint8_t up)` with direction flag.
  Result: 5 + 4 + 113 = 122 B (one shared body + two 5-B wrappers).
  NOINLINE on the body (clang's inliner thinks 2-caller bodies are
  always good to inline but on Z80 they aren't — see explanation
  about TTI inline-cost model in commit `0ab1168`).

- **crlf() factor**: factored `impl_conout(0x0d); impl_conout(0x0a)`
  out of netboot_mpm (2 callers).  NOINLINE.  Saves a few bytes in
  INIT_CODE.

- **install_fcb fold**: prepended the user-number byte to `FCB_HEAD`
  so install_fcb does ONE 13-byte LDIR instead of a byte store + 12-
  byte LDIR.  Saves 3 B in INIT_CODE.

- **Baseline cleanup**: removed `try_recv_frame:10` + `try_send_frame:2`
  entries (Phase 64 made them inline asm, no SDCC C frame violation
  possible).  Replaced `delete_line:2` + `insert_line:2` with
  `scroll_lines:7` (the unified function has more simultaneously-live
  locals on SDCC).

Sizes:

  | metric            | before | after | Δ    |
  |-------------------|-------:|------:|-----:|
  | clang payload     |   1678 |  1652 | -26  |
  | clang INIT_CODE   |    637 |   630 |  -7  |
  | SDCC resident     |   1848 |  1796 | -52  |

The SDCC win (52 B) is BIGGER than clang's (26 B) because the two
old functions had separate ABI prologue/epilogue overhead that SDCC
paid twice; one combined function pays once.  Plus the IX-frame
spills are 6 B each (worse than clang's BSS-spill cost) but there
are fewer of them total than two separate function frames.

cpnos-polypascal-test 4-cell PASS at parity for both compilers
(clang 49.77 s, SDCC 50.89 s).

Cumulative session impact through Phase 66:

  | | clang payload | SDCC resident |
  |---|---:|---:|
  | Pre-session HEAD | 2138 B | 2152 B |
  | Post-Phase-66    | **1652 B** | **1796 B** |
  | Δ | **-486 B (-22.7 %)** | **-356 B (-16.5 %)** |

## Phase 65: cross-class BSS-spill peephole in llvm-z80 (May 10, 2026) — Medium

Per user follow-up request to "get clang closer sizewise to handrolled
assembly using your knowledge of the compiler" and "you may use every
trick in the book, including looking at dri and clang sources":

- **Investigation**: pure-C SNIOS state machines (Phase 63) trail
  Phase 64's asm by +312 B.  Disassembly showed the cost is dominated
  by BSS-spill-around-CALL patterns (commit b88b210 → 9 detectable
  pairs in clang payload alone).  The existing same-class peephole
  (`Z80LateOptimization.cpp`, around line 4860) handles only
  rr_src == rr_dst spills.  Our state machines have many cross-class
  spills (HL stored, BC reloaded; etc.) that bailed out.

- **Action**: extended the peephole to handle the cross-class
  single-load case.  `PUSH rr_src ... CALL ... POP rr_dst` works via
  the 16-bit stack channel even when classes differ.  Same safety
  guards as the existing peephole (sfrend symbols only, no other slot
  use in same BB, stack balanced, single-BB, slot unused in other BBs).

- **Empirical result**:

  | configuration | clang payload | Δ vs Phase 63 baseline |
  |---|---:|---:|
  | Phase 63 pure-C | 2004 B | 0 |
  | Phase 63 + cross-class peephole | 1990 B | -14 B |
  | Phase 64 asm | 1692 B | -312 B |
  | Phase 64 asm + cross-class peephole | **1678 B** | **-326 B** |

  The peephole helps both paths equally (-14 B).  Most wins land in
  non-SNIOS functions (`_delete_line`, `_insert_line`) where the
  spill-load pair is intra-BB.  The SNIOS state machines themselves
  have multi-BB spill patterns (store at function-top, loads in
  inner loop bodies hundreds of lines away) that single-BB peephole
  can't reach.

- **Honest framing**: the user wanted pure-C to match asm.  This
  peephole moves pure-C from 2004 → 1990 B but the gap to asm
  stays at +312 B.  Closing more would require cross-BB analysis
  (dominator trees, full liveness) which is genuine backend work,
  not a peephole.

- **Decision**: keep Phase 64 (asm) as the production code per the
  user's earlier explicit approval ("this is really nice please
  commit").  Land the peephole as a strict improvement on top
  (clang payload now **1678 B**, the smallest configuration of this
  session).

- **llvm-z80 commit**: `fc3459368794` adds 176 lines to
  `Z80LateOptimization.cpp`.

- **Verification**: cpnos-polypascal-test 4-cell PASS at parity for
  both compilers (clang 48.83 s on Phase 64 + peephole;
  clang 50.29 s on Phase 63 pure-C + peephole).

## Phase 64: SNIOS state machines reverted to inline asm (May 10, 2026) — Big

- **Goal**: per user directive "get clang as close to pure assembly as
  you can," recover the +308 B SNIOS asm→C migration tax (#94) by
  reverting the SNDMSG/RCVMSG state machines and shared helpers to
  hand-rolled inline asm in `__naked` C functions.

- **Approach**: ported the original `snios.s` (commit 0bd7515)
  byte-for-byte into ASM_VOLATILE blocks inside `snios_c.c`, with
  globally-unique labels and the Phase 6 timeout-bearing-recv fix
  preserved (replaced original `RECVBY` busy-wait with `RECVBT`
  everywhere; existing `ret c` propagation handles the new timeout
  outcome).

- **What stayed in plain C**: the trivial JT impls
  (NTWKIN/NTWKST/CNFTBL/NTWKER/NTWKBT/NTWKDN/SNDERR1) — each ~10 B
  in C, identical to the asm.

- **What is now `__naked`**:
  * Public entry points: `snios_sndmsg_c`, `snios_rcvmsg_c`,
    `snios_errrtn`
  * Shared helpers: `snios_sendby`, `snios_recvbt`, `snios_netout`/
    `_snios_preout`, `snios_netin`, `snios_msgin`, `snios_msgout`,
    `snios_sndack`, `snios_badcks`
  * `snios_sndmsg_force` is exposed via `.globl` inside
    `snios_sndmsg_c`'s body (fall-through entry without ACTIVE check,
    used by NTWKDN).

- **Result**: clang payload **2004 → 1692 B** (-312 B, -15.6 %).
  Per-function:

  | function           | before | after | Δ     |
  |--------------------|-------:|------:|------:|
  | `_snios_rcvmsg_c`  |   384  |  154  | -230  |
  | `_snios_sndmsg_c`  |   264  |  114  | -150  |
  | helpers (8 fns)    |    -   |   79  |  +79  |
  | `_snios_errrtn`    |    13  |   11  |   -2  |
  | net SNIOS surface  |   661  |  358  | **-303** |

- **vs pure assembly baseline (apples-to-apples after applying
  the same Phase 6 fix to both)**:

  | | original ASM | original ASM minus RECVBY (Phase 6) | Phase 64 clang |
  |---|---:|---:|---:|
  | body | 434 B | 417 B | 407 B |
  | JT + bridges | 24 B | 24 B | 34 B |
  | **TOTAL** | **458 B** | **441 B** | **441 B** |

  With the same Phase 6 bugfix applied (RECVBY removed, all
  receives via RECVBT), **the C build is byte-identical to
  hand-tuned assembly written by a domain expert** — 441 B both
  ways.

  The +10 B bridge cost (sdcccall(1) HL vs DRI's BC convention) is
  offset exactly by clang's tighter codegen on:
  - trivial impls (constant reuse across consecutive zero-stores
    via absolute addressing where asm used IX-relative)
  - NTWKDN (24 B asm → 21 B C)
  - small encoding wins across the trivial JT impls

  Earlier commit messages (`29278d9`, `7f1c608`) reported "−17 B
  smaller" or "−69 B smaller" — both wrong.  The honest answer is
  **parity with hand-tuned asm**, given equivalent algorithms.

- **Cumulative session deltas**:

  | | clang payload | SDCC resident |
  |---|---:|---:|
  | Pre-session HEAD | 2138 B | 2152 B |
  | Post-Phase-63 | 2004 B (-134) | 2120 B (-32) |
  | Post-Phase-64 | **1692 B (-446 / -20.9 %)** | **1848 B (-304 / -14.1 %)** |

- **Verification**:
  * cpnos-polypascal-test 4-cell PASS for clang at 49.45 s.
  * SDCC build clean; resident chunk B 1418 -> 1112 B (-306 B);
    polypascal-test in progress.
  * check_no_frame_ptr / check_unreferenced_publics TBD.

- **Trade-off**: the SNIOS body is now mostly inline asm — the
  user's directive ("as close to pure assembly as you can")
  explicitly authorized this trade against the original #75 "plain
  C" goal.  Wire-protocol behaviour is unchanged (byte-for-byte
  identical to the asm); the C wrapper still provides the JT
  contract and the trivial impls.

## Remaining-shrink estimate (May 10, 2026 — second addendum)

Followup to the post-session analysis: estimate of how much more
clang payload reduction is realistic *without* changes to
ravn/llvm-z80 backend.

**Floor: roughly 1900 B clang payload** (current HEAD: 2004 B), so
**~60-110 B more** addressable through source / build-flag work
alone.  Beyond that the asymptote is set by:
- +308 B SNIOS asm→C migration tax (#94)
- llvm-z80 backend issues (#128, #129, Cluster A)

Filed `ravn/rc700-gensmedet#95` as a consolidated tracker for the
remaining candidates by category:

- A. Unblock `-disable-block-placement` (8 B; existing #93)
- B. Cold-path C tightening (20-40 B): `_netboot_mpm` build-stamp
  print loop, `_print_banner`, `setup_ivt`
- C. Hand-asm cold blobs per the new "size > speed for cold
  paths" rule (30-60 B): cfgtbl_init template, similar
- D. Phase 62 pattern audit of remaining receive paths (5-15 B)

Verified one estimate as already-applied: `_recv_byte_t` static
inline trampoline IS dropped post-link by `--gc-sections` despite
appearing in `snios_c.o`.  No win available there.

#95 is parked unless: PROM-1 single-PROM stretch goal forces it
(via #82 ZX0 landing), a specific feature pushes payload over 2 KB,
or backend fixes land and we re-baseline.

## Post-session deep analysis (May 10, 2026 — addendum)

After the Phase 59-63 commits landed, two follow-up investigations:

### SDCC flag bisection (the symmetric question to clang's)

User asked whether SDCC has equivalents for clang's
`-disable-machine-licm` / `-disable-machine-cse` flags, and
whether enabling them helps.  Bisected on `snios_c.c`:

| SDCC flag | clang analog | snios_c.o Δ |
|---|---|---:|
| `--noinvariant` | `-disable-machine-licm` | 0 (no-op) |
| `--noloopreverse` | (none) | 0 (no-op) |
| `--nogcse` | `-disable-machine-cse` | **+88 B (worse)** |
| `--nolabelopt` | (none) | **+116 B (worse)** |
| `--noinduction` | `-disable-lsr` | **+140 B (worse)** |
| all 3 (inv+cse+ind) | combined | **+164 B (worse)** |

**The asymmetry is the diagnostic finding.**  Same Z80 ISA, same
C source, same register pressure — clang benefits from disabling
LICM/CSE, SDCC suffers.  Architectural reason: clang's MachineLICM
/ CSE run *before* regalloc and rely on TargetTransformInfo cost
estimates (Z80 TTI under-predicts spill cost — open Cluster A in
ravn/llvm-z80).  SDCC's loop opts run on iCode where the iCode
allocator runs concurrently — invariants only get hoisted when a
register is available.

Documented in `cpnos-rom/README.md` "Compiler tuning notes" section
and added as a comment to ravn/llvm-z80#128.

### SNIOS asm→C residual gap accounting

After all Phase 62-63 wins, current vs pre-migration assembly:

| | pre-migration ASM | post-Phase-63 C |
|---|---:|---:|
| body + JT + bridges | 461 B | 769 B |
| Δ | — | **+308 B (+67 %)** |

Recovered from the original +419 B (+91 %) via this session's
Phase 62-63 work: −111 B / 26 % of the migration tax.

Per-cluster breakdown:
- SNDMSG state machine: 113 B asm → 265 B C (+152)
- RCVMSG state machine: 168 B asm → 384 B C (+216)
- trivial JT impls: 27 B asm → 49 B C (+22, NTWKDN
  correctness fix)

Where the +308 B comes from (in priority order):
1. sdcccall(1) ABI overhead at every C call boundary (asm
   shared register meanings by convention across the state graph)
2. No "fall-through into next function" optimization in C
   (asm's `GOTFST: ... ; falls through into SNDACK` saves a JP
   per chained label)
3. `__builtin_memcpy` materializing as runtime call on small
   constant sizes (already filed as #50)
4. NTWKDN went 0 B → 21 B as a correctness fix (DRI-conformant
   shutdown)

Filed as ravn/rc700-gensmedet#94 (tracking-only, parked) with
reduction paths.  Updated #83 to lower priority — the
try_recv_frame IX-frame loosening was deliberate this session;
the original premise of "refactor to remove spills" is now
mostly academic.

## Session-end summary (Phases 59–63, May 10, 2026)

Single session covering file consolidation + LLVM-flag bisection +
SNIOS source tightening.  Headline numbers:

| | clang payload | SDCC resident | C-file count |
|---|---:|---:|---:|
| Pre-session HEAD | 2138 B | 2152 B | 12 |
| Post-Phase-63 (HEAD) | **2004 B** | **2120 B** | **7** |
| Δ | **−134 B (−6.3 %)** | **−32 B (−1.5 %)** | **−5** |

Phase breakdown:

- **59** — Cold-init 4-into-1 file merge (cfgtbl + init + netboot_mpm
  + cpnos_cold → init.c).  Byte-stable, unlocked file-static of
  cfgtbl_init / init_hardware / netboot_mpm.
- **60** — Dead-code drop (rc700_console.{c,h} never built);
  isr.c → transport_pio.c (shared RESIDENT_PRE_CODE);
  payload_checksum.c → resident.c.  Byte-stable.
- **61** — Closed ravn/rc700-gensmedet#88 (cross-TU barrier) with
  empirical re-measurement: structural mitigations exhausted,
  remaining cross-TU edges all non-inlinable.
- **62** — `-mllvm -disable-machine-licm` (clang only, −74 B
  payload) + SNIOS source tightening: timeout-folding trick at 6
  sites + direct `slaveid != 0xFF` check (−44 B clang on snios_c.o).
  Total: −118 B clang / −34 B SDCC.  Loosened SDCC IX-frame
  baseline (try_recv_frame 2 → 10) per user authorization.
- **63** — `-mllvm -disable-machine-cse` (clang only, −16 B
  payload).  Tested but rejected `-disable-block-placement` (1 B
  over INIT region budget — see #93 to unlock).

New issues filed this session:

- ravn/llvm-z80#128 — MachineLICM and MachineCSE pessimize at -Oz on
  Z80 (workaround flags now in cpnos-rom Makefile; backend should
  default-disable at -Oz)
- ravn/llvm-z80#129 — Peephole: convert BSS-spill-around-CALL to
  PUSH/POP-around-CALL (9 detectable pairs in HEAD payload, ~36 B
  potential savings)
- ravn/rc700-gensmedet#93 — Unlock `-disable-block-placement` by
  moving chunk-A LMA 0x0520 → 0x0540 (8 B clang + 32 B headroom)

Issues closed:

- ravn/rc700-gensmedet#88 — cross-TU barrier (structural
  mitigations exhausted)

New memory rule captured (user-side):

- `feedback_size_over_speed_for_cold_paths.md` — for code that
  runs only a few times, code size is more important than speed
  (user guidance 2026-05-10).

All polypascal-test 4-cell PASS at parity through every phase
(both compilers).

## Phase 63: -disable-machine-cse (-16 B clang) (May 10, 2026) — Easy

- Continued the LLVM-flag bisection past Phase 62.  Found
  `-mllvm -disable-machine-cse` saves 11 B on snios_c.o and 16 B
  on full payload.  Common-subexpression elimination introduces
  spills on Z80's limited register file; disabling pushes the
  recomputes back inline (which Z80 prefers because its memory
  loads are 3 B / instruction).

- Tested but rejected: `-disable-block-placement` would have given
  another -8 B on snios_c.o but pushed init.c 1 B over the 640 B
  INIT_CODE budget.  Multi-file budget grow not worth 8 B.

- Result: clang payload **2020 → 2004 B** (-16 B).  Cumulative
  reduction since pre-Phase 62: 2138 → 2004 B (-134 B / -6.3 %).
  SDCC unchanged (LLVM-only flag).

- cpnos-polypascal-test PASS at 51.93 s (clang).

## Phase 62: -disable-machine-licm + SNIOS source tighten (May 10, 2026) — Medium

- **Goal**: investigate whether `+static-stack` (and similar build
  flags) can be undone or replaced for a smaller resident, and whether
  the C source itself has slack the compiler isn't recovering.

- **Method**: per-flag bisection on snios_c.c text-section size,
  one knob at a time:

  | configuration | snios_c.o |
  |---|---:|
  | -O3 | 1484 |
  | -O2 | 1480 |
  | -Os | 1255 |
  | -Oz | 1225 |
  | -Oz +static-stack | 875 |
  | -Oz +static-stack -disable-lsr (current HEAD pre-62) | **868** |
  | -Oz +static-stack -disable-lsr -disable-machine-licm | **795** |
  | -Oz -disable-machine-licm | 1320 |
  | -Os +static-stack -disable-lsr -disable-machine-licm | 899 |

  `+static-stack` is essential (saves ~450 B alone — locals to BSS
  vs IX-frame).  `-disable-lsr` saves another 7 B.  New finding:
  `-disable-machine-licm` saves another **73 B** — MachineLICM
  hoists invariants out of loops, but on Z80 with limited register
  pressure the spill/reload cost often outweighs hoisting wins.

- **Source-level changes**:

  1. Timeout-folding trick: `0xFFFF & 0x7F = 0x7F` differs from every
     CP/NET 1.2 control byte (SOH=1 .. ACK=6), so the explicit
     `if (r >= 0x100) return RC_RETRY;` can fold into the existing
     `(r & 0x7F) != X` check.  Applied 6 sites; -44 B clang on
     snios_c.o.

  2. Direct slaveid==0xFF check: replaced the
     `(uint8_t)(slaveid+1) != 0` indirection with `slaveid != 0xFF`;
     -5 B clang.

  3. Read-once `b = (uint8_t)r` pattern in the byte-receive loops
     was tested and reverted: 0 B clang win, +8 SDCC IX-frame
     entries.  Not worth doing.

- **Result**:

  | | clang payload | SDCC resident |
  |---|---:|---:|
  | Pre-62 (HEAD) | 2138 B | 2154 B |
  | Post-62 | **2020 B** (-118 B, -5.5%) | **2120 B** (-34 B, -1.6%) |

  Per-function deltas (clang -Oz):
  - `_snios_rcvmsg_c`: 471 -> 396 B (-75 B)
  - `_snios_sndmsg_force`: 311 -> 264 B (-47 B)
  - snios_c.o total: 868 -> 746 B (-122 B)

- **Verification**:
  - cpnos-polypascal-test 4-cell PASS at parity (clang 51.23 s,
    SDCC 47.95 s).
  - check_no_frame_ptr SDCC try_recv_frame raised 2 -> 10
    (timeout-folding eliminated live-range boundaries SDCC was
    using to recycle registers).  User-authorized loosening
    (2026-05-10); baseline updated with rationale.

- **Rule captured**: user said "for code only running a few times
  code size is more important than speed" — folded into
  `feedback_size_over_speed_for_cold_paths.md` (user-side memory).

## Phase 61: close #88 cross-TU barrier (structural mitigations exhausted) (May 10, 2026) — Easy

- **Goal**: re-measure the cross-TU compilation barrier (#88) after
  Phase 59 + 60 file consolidation, decide whether to keep it open.

- **Findings** (full comment on the issue):

  - Phase 59 merged 4 INIT_CODE TUs (cfgtbl + init + netboot_mpm +
    cpnos_cold) into one `init.c` — all candidates from Option A.
  - Phase 60 merged isr + transport_pio (shared RESIDENT_PRE_CODE),
    folded payload_checksum into resident, deleted dead
    rc700_console.
  - Empirical byte recovery from the merge phases: **0 B**.  The
    only cross-TU win came from Phase 58's `__preserves_regs(d, e)`
    declaration (-12 B SDCC), which works *because* of the cross-TU
    boundary, not despite it.
  - Cold-init functions are called exactly once each — inlining a
    once-called function nets zero bytes (saves 4 B call/ret, adds
    body inline).
  - Remaining cross-TU edges are all non-inlinable:
    cold-init-once-calls, fixed-ABI JT, `--defsym` alias
    indirection, inline-asm BSS data loads.

- **Decision**: closed #88 as "structural mitigations exhausted,
  residual cost empirically negligible".  Re-open under the
  original trigger conditions (resident size budget tight, ZX0
  lands, hot-path inlining wins identified).

- **Net diff**: 0 source changes; one issue closed, one timeline
  entry.  Engagement-mode-gate book-keeping: parked-issue count
  -1.

## Phase 60: cpnos-rom dead-code drop + isr/payload-checksum merges (May 10, 2026) — Easy

- **Goal**: continue file consolidation past Phase 59.  Three actions:

  1. **Delete `rc700_console.{c,h}`**: dead code.  Header declared
     `rc700_console_init` / `rc700_console_putc`; no caller anywhere
     in the project; not in any Makefile object list.  A
     parallel-implementation that was never wired up.  −250 LOC.

  2. **Merge `isr.c` → `transport_pio.c`**: both halves share the
     SDCC `RESIDENT_PRE_CODE` codeseg and the PIO-B receive ring
     buffer (`pio_rx_buf` + head/tail).  Co-locating lets `isr_pio_par`
     push directly into the file-static buffer instead of crossing
     TUs.  isr.c body (set_i_reg, enable_im2, enable_interrupts,
     disable_interrupts, isr_noop, isr_crt, isr_pio_kbd, isr_pio_par)
     appended after the transport recv path.

  3. **Fold `payload_checksum.c` → `resident.c`**: 24-line file with
     4 lines of actual code (a `SECTION_PAYLOAD_CKSUM` 0xFFFF
     placeholder).  Lives in its own clang section regardless of
     hosting TU; SDCC default codeseg works either way.

- **Linkage**: no externally-visible symbols changed; isr's
  `pio_rx_head`/`pio_rx_tail` externs are now redundant (both are
  defined earlier in the same TU).  pio_rx_buf_page stays a
  linker-defined constant.

- **Result**: clang payload byte-stable at **2138 B**; SDCC resident
  **2154 B** (+2 B vs Phase 59's 2152 B — noise from layout shift,
  not a regression).  Both polypascal-test 4-cell PASS at parity
  (clang 50.85 s; SDCC TBD).

- **Net diff**: −3 source files (`isr.c`, `payload_checksum.c`,
  `rc700_console.c`); −2 Makefile recipes; −1 SDCC per-target
  CFLAGS override.  C-source file count after Phase 60: **7 files**
  (cpnos_main, init, resident, snios_c, transport_pio, transport_sio,
  relocator).

## Phase 59: cpnos-rom cold-init 4-into-1 file merge (May 10, 2026) — Easy

- **Goal**: merge the four cold-init translation units (`cfgtbl.c` +
  `init.c` + `netboot_mpm.c` + `cpnos_cold.c`) into a single `init.c`
  so the compiler sees the full call graph in one TU and the three
  helper functions can become file-static.

- **Source order in merged init.c** (mirrors call order from
  `cpnos_cold_entry`):

  1. CFGTBL ABI declarations + `cfgtbl_init` template
  2. Hardware bring-up (`port_init` table, `setup_ivt`, `init_hardware`)
  3. CP/NET netboot of `A:CPNOS.IMG` (`netboot_mpm` + helpers)
  4. Cold-boot orchestrator + banner (`cpnos_cold_entry`, `print_banner`)

- **Linkage cleanup**: `cfgtbl_init`, `init_hardware`, `netboot_mpm`
  all become `static`; only `cpnos_cold_entry` (named in `payload.ld`
  ENTRY and in `reset.s`) stays externally visible.  Dead extern
  declarations in `cpnos_main.c` removed.

- **Makefile**: `PAYLOAD_OBJS` and `SDCC_C_OBJS` lose three entries
  each; per-file recipes for `cpnos_cold.o`, `cfgtbl.o`,
  `netboot_mpm.o` deleted; SDCC `--codeseg INIT_CODE` per-target
  override now lists only `init.o`.  `NETBOOT_OBJ` variable removed.

- **Result**: clang payload byte-stable at **2138 B**; SDCC resident
  byte-stable at **2152 B**.  Both polypascal-test 4-cell PASS at
  parity (clang 50 s, SDCC 50 s).

- **Net diff**: −1 source file (4 → 1), -3 object recipes, no size
  change.  The merge unlocks future intra-TU optimization (current
  `static` keyword pinning yields 0 B because the four functions are
  each called exactly once and the compiler already inlined or
  preserved them across the TU boundary; future shared rodata or
  helper extraction can now happen freely).

## Phase 58: cpnos-rom SNIOS C size optimization investigation (May 10, 2026) — Easy

- **Goal**: investigate size-optimization angles for the plain-C
  SNDMSG/RCVMSG state machines that landed in Phase 57.

- **Approaches tested**:

  | Approach | Clang Δ | SDCC Δ | Decision |
  |---|---:|---:|---|
  | Un-reserve IX (`-fno-omit-frame-pointer`) | +7 B per fn ✗ | n/a | DROP |
  | File-scope `static` state-machine locals | −18 B | **+98 B** ✗ | DROP |
  | `__preserves_regs(d, e)` on `xport_send_byte` | 0 (no-op) | **−12 B** ✓ | **LANDED** |

  Net: clang unchanged at 2138 B, SDCC 2164 → **2152 B** (−12 B).

- **Lessons**:

  - **`+static-stack` on clang already does the "no-recursion → no-stack"
    optimization** for named locals.  Adding `-fno-omit-frame-pointer`
    on top is pure overhead because there's no SP-relative stack frame
    to point at -- each function gets +7 B prologue/epilogue with no
    payback.  Cross-referenced as a data point on ravn/llvm-z80#40.

  - **Forcing locals to `static` BSS pessimizes SDCC**.  SDCC's
    local-only iCode allocator KEEPS auto-locals in registers within
    a basic block; explicit `static` makes every access an `ld a,
    (var)` (3 B) where SDCC was using `ld a, c` (1 B).  Don't fight
    the allocator's chosen register tier.  Lesson captured in memory
    rule below.

  - **`__preserves_regs(...)` is SDCC-only** (clang ignores via the
    `compiler/compat.h` shim `#define __preserves_regs(...)`).  When
    declaring it, audit the actual SDCC asm output of the target
    function to verify the claim is honest -- a lie produces silent
    register clobbering and crashes that are hard to debug.

  - **Diagnostic discipline**: I had originally proposed "un-reserve
    IX would save ~100 B" based on a quick clang -Oz test compile
    that did NOT include the cpnos-rom flags.  Real cpnos-rom builds
    with `+static-stack` emit 3-byte BSS stores, not 6-byte
    SP-relative arithmetic.  Always inspect WITH the target build's
    actual flags before quoting hypothesis-savings numbers.

- **Bigger wins NOT pursued this round** (parked behind #83 trigger
  conditions):

  1. **Inline-asm hot inner loops** (header-walk and data-walk
     loops) -- estimated −50 to −80 B per compiler.  Defeats "as
     much C as possible" but is the largest mechanical lever.
  2. **Split `try_send/recv_frame` into 3 helpers each** --
     estimated −30 to −60 B SDCC; potentially neutral on clang.
  3. **Per-byte send-wrapper** preserving more registers via a
     `__naked` thin wrapper -- estimated −20 to −40 B SDCC.

  Trigger to pursue: cpnos-rom resident growing past current
  headroom (~400 B clang / ~330 B SDCC out of 2.5 KB resident
  region), or ZX0 compression integration via #82.

- **Issue activity**:
  - Commented on ravn/llvm-z80#40 (data point: IX frame pointer is
    net loss on `+static-stack` cpnos-rom code).
  - Commented on ravn/rc700-gensmedet#83 (full investigation
    findings; #83 stays parked).

- **Memory rule worth capturing for future SDCC work**:
  "Don't preempt the iCode allocator with `static`.  SDCC's
  local-only iCode allocator keeps auto-locals in registers within
  basic blocks; forcing them to `static` BSS converts cheap
  register accesses to expensive memory accesses.  Trust the
  allocator; only force `static` when you've measured a specific
  IX-frame elimination win that exceeds the access-cost regression."

## Phase 57: cpnos-rom SNIOS — plain-C SNDMSG/RCVMSG state machines (May 10, 2026, #75 CLOSED) — Hard

- **Goal**: complete the SNIOS asm→C migration (#75 Phases 5+6)
  with **plain C** state machines implementing the CP/NET 1.2 wire
  protocol against `cpnos-rom/CPNET_WIRE_PROTOCOL.md` (the spec
  authored in Phase 56).  Per the user's stated principle: "i want
  a plain c implementation of the wire-protocol spec" -- not a
  byte-for-byte port of the historical asm, but an implementation
  of what the master expects on the wire.

- **What landed (commit `fe609fc`, branch `phase-5-6-test-config`
  merged --no-ff into main)**:
  - `snios_c.c` rewritten with plain-C `try_send_frame` and
    `try_recv_frame` (~190 lines C, structured retry loops, no
    `pop hl` discard-caller-return tricks).
  - `snios.s` + `sdcc/snios.asm` reduced to JT (24 B ABI-fixed) +
    two 5 B BC->HL bridges for the SNDMSG/RCVMSG JT entries.  Down
    from ~470 B of hand-written asm.
  - One DRI-spec deviation FIXED: the prior `RECVBY` busy-wait used
    mid-frame would hang the slave forever if the master paused
    mid-frame.  C version uses timeout-bearing `xport_recv_byte`
    everywhere, matching DRI's reference and propagating mid-frame
    timeouts to the outer retry loop.
  - SCRATCH region relocated from 0xF500 to 0xEB00 in payload.ld
    (using the previously-unused 512 B gap above IVT in the
    cpnos.com layout).  This single linker-script change accommodated
    the larger C state machines without needing PROM expansion or
    MAME-side changes.

- **Sizes** (clang / SDCC):

  | Stage | Clang | SDCC |
  |---|---:|---:|
  | Pre-#75 baseline (Phase 0) | 1712 B | 1858 B |
  | Phase 1+2 (housekeeping)    | 1720 B | 1868 B |
  | Phase 3+4 (byte-I/O + checksum helpers) | 1720 B | 1868 B |
  | Phase 5+6 (protocol state machines)     | **2138 B** | **2164 B** |
  | Cumulative Δ over baseline  | **+426 B** | **+306 B** |

- **Verification** (4-cell polypascal-test, byte-level
  end-to-end through SNDMSG/RCVMSG against z80pack mpm-net2):

  | cell | wall-clock | status |
  |---|---:|---|
  | clang / pio-irq | 51.09 s | PASS |
  | clang / sio     | 59.83 s | PASS |
  | sdcc  / pio-irq | 47.83 s | PASS |
  | sdcc  / sio     | 60.53 s | PASS |

  All four cells PASS at parity wall-clock with the prior asm
  version.  PPAS PRIMES runs end-to-end (compute primes 0..29989
  via cross-network drive access), Q returns to E> prompt.  This
  exercises every path: ENQ-ACK at all three sync points, header
  send + HCS verify, data send + CKS verify, ETX+CKS+EOT framing,
  DID validation on receive, retries on noisy CKS (rare).

- **The plain-C state machines speak the protocol correctly**.  This
  is the strongest possible correctness signal short of a multi-day
  soak test on physical RC702 hardware.

- **Two follow-ups filed**:

  - **#83** (`snios_c.c try_send_frame / try_recv_frame: refactor
    to remove SDCC IX-frame spills`): each function has 2 IX+/IY+
    spills due to multiple simultaneously-live locals; SDCC's
    local-only iCode allocator can't keep them all in registers.
    Estimated savings if refactored: ~100 B per compiler.  Parked
    until size pressure justifies the refactor.

  - **#82** (`investigate ZX0 payload compression`): authored
    earlier; ZX0 measurements show ~450 B potential savings on the
    payload.  Parked because current sizes fit fine; revisit if
    cpnos-rom adds a feature that pushes resident past current
    headroom.

- **The "4 KB PROMs / 7 KB payload" plan was over-budget** for
  current Phase 5+6 sizes.  The actual minimum-change path was a
  single-line `payload.ld` SCRATCH-region relocation.  Documented
  for future reference: when reconfiguring layouts, audit address-
  space usage for unused gaps before assuming hardware (PROM size)
  changes are needed.

- **Lessons captured during the rewrite**:

  - **clang Z80 backend is ~4× the asm baseline on state-machine
    code**.  The DAG combiner + GISel give clean code on
    straight-line C, but multi-block state-machine functions with
    many live locals get worse codegen than hand-tuned asm.  Phase
    5+6 went from `~190 B asm` to `~782 B clang C` for the
    equivalent state machines; ~80 B of bloat came from uint16_t
    arithmetic on the `xport_recv_byte` return-value compare path.

  - **SDCC's local-only iCode allocator forces IX frames sooner**
    than expected on functions with >3-4 simultaneously-live
    locals.  Splitting into helpers (Option A in #83) is cheaper
    than fighting the allocator.

  - **Layout-driven shifts beat compression-driven shifts** when
    available.  ZX0 compression (#82) would have given ~450 B of
    PROM headroom; the SCRATCH relocation gave functionally
    unlimited resident headroom (up to display memory at 0xF800)
    with one line of linker-script change.  Audit space before
    compression.

  - **Wire protocol cross-checking matters**.  Phase 56's authoring
    of `CPNET_WIRE_PROTOCOL.md` (cross-checked against master
    `netwrkif-0.asm`, DRI reference, and our slave) caught the
    mid-frame busy-wait deviation BEFORE the C rewrite — so the
    rewrite restored DRI semantics rather than faithfully
    reproducing our slave's bug.

- **Issue activity**:
  - Closed: ravn/rc700-gensmedet#75 ("rewrite SNIOS body in C") --
    DONE in 6 phases over sessions 51-57.
  - Filed: ravn/rc700-gensmedet#83 (IX-frame refactor follow-up).
  - Open: ravn/rc700-gensmedet#82 (ZX0 compression, parked).

## Phase 56: CP/NET wire-protocol spec — authored, cross-checked, and corrected (May 10, 2026) — Medium

- **Trigger** (user prompt 2026-05-10): "where did you find the
  wire-protocol spec? ... please record your findings in the project."
  Honest answer was that I had been planning the SNIOS Phase 5+6
  rewrite from one side of the wire (cpnos-rom asm) without
  consulting the master code we actually talk to.

- **Investigation**: cross-checked four sources to nail down the
  actual wire-byte contract:

  | Source | Role | Outcome |
  |---|---|---|
  | `cpnet-z80/src/ser-dri/snios.asm` | DRI 1980-1982 reference slave | Same protocol as cpnos-rom (binary ENQ/ACK/SOH/STX/ETX/EOT). |
  | `cpnet-z80/src/serial/snios.asm` | durgadas311 ASCII variant | DIFFERENT protocol (`++..--` hex), not what we use. |
  | `z80pack/cpmsim/srcmpm/netwrkif-0.asm` | Authoritative master (z80pack mpm-net2) | Same protocol as DRI reference; modified Sep 2014 by Udo Munk for Z80SIM. |
  | `cpnet-z80/dist/mpm/server.asm` | DRI master BDOS dispatcher | Validates `FNC < netend (76)`; rejects FNC >= 76 as invalid. |

- **Authored**: `cpnos-rom/CPNET_WIRE_PROTOCOL.md` (367 lines, commit
  `60661c0`) — authoritative byte-level spec covering encoding modes
  (binary 8-bit only; ASCII not implemented), control bytes, frame
  layout (FMT/DID/SID/FNC/SIZ/DAT), checksum construction (8-bit
  two's complement of running sum, raw 8-bit accumulation, 7-bit
  masked compares), retry semantics (master/slave timing asymmetry),
  SID rewriting on send, DID-mismatch handling on receive, special
  FNC values (0xFF init, 0xFE shutdown), and unsupported features.

- **Three things found and corrected during write-up**:

  (a) **cpnos-rom slave deviates from DRI in mid-frame recv**: DRI's
  reference has one `recvby` (timeout-bearing); cpnos-rom split it
  into `RECVBT` (timeout) + `RECVBY` (busy-wait, retries forever).
  Mid-frame uses busy-wait, so the slave hangs forever if the master
  pauses mid-frame.  The `ret c` checks after `call RECVBY` in
  `snios.s` are dead code.  Latent bug; not seen under
  polypascal-test because z80pack mpm-net2 is reliable.  Flagged for
  the upcoming SNIOS Phase 5+6 rewrite to fix by restoring DRI's
  semantics.

  (b) **FNC=0xFF (init / get-node-ID) is NOT supported by our master**:
  The CP/NET 1.2 protocol defines FNC=0xFF for slave-ID negotiation
  (slave sends `00 00 00 FF 00 00`, proxy returns `01 NN 00 FF 00 00`
  with the assigned ID), but this is implemented only by
  `CpnetSerialServer.jar` (a Java host-side proxy in the cpnet-z80
  family) — NOT by z80pack mpm-net2.  Our wire path (cpnos-rom →
  MAME cpnet_bridge → TCP 4002 → cpmsim → MP/M II → DRI server.asm)
  reaches DRI's `server.asm:val2` which rejects any `FNC >= netend
  (76)` as invalid.  cpnos-rom hardcodes `RC702_SLAVEID = 0x01` at
  build time via the Makefile; no dynamic ID negotiation runs.

  (c) **FNC=0xFE (shutdown) is similarly proxy-only**: Same dispatch
  pattern; z80pack mpm-net2 rejects it.  cpnos-rom's `NTWKDN` (now
  `snios_ntwkdn_impl` in C since #75 Phase 2) builds the frame and
  sends it via `_snios_sndmsg_force` regardless; the master rejects
  it but the slave doesn't care (`xor a; ret` discards the result
  per DRI behaviour).  Effectively a no-op end-of-session marker for
  our setup.

- **Spec hygiene fix** (commit `78505d8`): removed a stream-of-
  consciousness self-correction ("Wait, that's wrong. Let me re-read
  ...") that leaked from drafting into the published reference doc.
  Captured as new memory rule
  `feedback_no_self_correction_in_published_docs` so it won't recur.

- **Spec FNC clarification** (commit `3fed75d`): rewrote the special-
  FNC section to distinguish three layers cleanly:
    - "Protocol-defined behaviour" — what CpnetSerialServer.jar would do.
    - "What z80pack mpm-net2 actually does" — rejects as invalid FNC.
    - "What cpnos-rom actually does" — hardcoded SLAVEID, no
      negotiation, FNC=0xFE sent as best-effort marker.

- **README pointer added**: `cpnos-rom/README.md` now has a
  "Reference docs" section linking the new spec, alongside
  `MEMORY_MAP.md` and `PORT_OUTPUTS.md`, so the spec is discoverable
  from the entry-level doc.

- **Lessons captured for the upcoming Phase 5+6 SNIOS C rewrite**:

  - The C rewrite should target the SPEC (DRI / mpm-net2 wire
    contract), NOT the existing cpnos-rom asm — that asm has the
    busy-wait deviation.  Restoring DRI's timeout-bearing mid-frame
    recv is more robust on real hardware and against host hiccups.
  - SID rewriting on send (slave overwrites msg[2] with
    cfgtbl.slaveid before the first ENQ) is a slave-side hardening
    measure NOT mandated by the master.  Should be preserved in the
    rewrite.
  - DID-mismatch handling: on the slave, frame received with wrong
    DID still gets ACKed (so master doesn't retransmit) but slave
    returns 0xFF to NDOS so it rejects the message.  Subtle but
    matches DRI; preserve.
  - All control-byte compares mask bit 7 (`b & 0x7F == ACK`); all
    checksum accumulations use the raw 8-bit byte.  Asymmetric, easy
    to get wrong.
  - The `pop hl`-discard-caller-return pattern in the asm collapses
    cleanly into a structured-C retry loop.  No `setjmp`/`longjmp`
    needed.

- **Issue activity**: no new issues filed; #75 still open (will be
  resumed for Phase 5+6 against the now-authoritative spec).
  Spec doc resides in cpnos-rom/ alongside MEMORY_MAP.md / PORT_OUTPUTS.md.

## Phase 55: cpnos-rom SNIOS asm→C migration, Phase 4 of #75 (May 10, 2026) — Easy

- **Goal**: continue #75 by porting the checksum helpers (NETOUT,
  PREOUT, NETIN, MSGOUT, MSGIN) from asm to portable C, written as
  `__naked` C functions with `ASM_VOLATILE` bodies that match the
  original asm byte-for-byte.

- **Functions ported (4)**: NETOUT (collapsed with PREOUT, since they
  were alias labels at the same asm address), NETIN, MSGIN, MSGOUT.
  ~31 B of asm body removed from each of `snios.s` + `sdcc/snios.asm`.

- **Call site updates** (12 sites in each compiler's asm file):
  - `call NETOUT` -> `call _snios_netout` (5 sites)
  - `call PREOUT` -> `call _snios_netout` (3 sites; PREOUT collapsed)
  - `call NETIN`  -> `call _snios_netin`  (4 sites)
  - `call MSGIN`  -> `call _snios_msgin`  (2 sites)
  - `call MSGOUT` -> `call _snios_msgout` (3 sites)

- **Result** (4-cell polypascal-test all PASS, BYTE-NEUTRAL):

  | metric | before (Phase 3) | after | Δ |
  |---|---:|---:|---:|
  | Clang payload | 1720 B | **1720 B** | **0 B** |
  | SDCC resident | 1868 B | **1868 B** | **0 B** |
  | clang/pio-irq polypascal | 50.75 s | 50.67 s | ~0 |
  | clang/sio polypascal     | 59.57 s | 59.43 s | ~0 |
  | sdcc/pio-irq polypascal  | 51.19 s | 51.61 s | ~0 |
  | sdcc/sio polypascal      | 60.19 s | 60.69 s | ~0 |

- **Bring-up gotcha (re-confirmed `feedback_check_banner_timestamp`
  HARD rule)**: first cell-1 retest after Phase 4 changes FAILED stage
  2 with a STALE SDCC banner displayed (`PIO sdcc 2026-05-10 09:14`)
  even though `make cpnos-polypascal-test COMPILER=clang` had run.
  Root cause: leftover ROM bytes in `/Users/ravn/git/mame/roms/rc702/`
  from the previous Phase 3 SDCC test cycle; the `make cpnos
  COMPILER=clang` rebuild produced clang/prom0_padded.ic66 + .ic65
  but the install-to-MAME-roms step had been short-circuited by
  Make's "no .o changes" check.  Resolution: explicitly rm
  `clang/cpnos.bin` etc. to force the install step.  Polypascal-test's
  banner-check would have caught this earlier if it inspected
  `cpnos_siob.raw` instead of just stage timeouts -- filed as a
  followup observation but not blocking Phase 4.

- **Cumulative across Phases 1+2+3+4 (#75)**:
  - 15 SNIOS functions in portable C (Phase 1: NTWKIN/NTWKST/CNFTBL/
    NTWKER/NTWKBT; Phase 2: NTWKDN/ERRRTN/SNDERR1; Phase 3: SENDBY/
    RECVBY/RECVBT; Phase 4: NETOUT/NETIN/MSGIN/MSGOUT).
  - Asm side now owns: JT (24 B, ABI), 3 calling-convention bridges
    (_snios_sndmsg_c, _snios_rcvmsg_c, _snios_sndmsg_force, ~14 B),
    2 trampolines (SNDMSG_DISPATCH, RCVMSG_DISPATCH, 6 B), and the
    SNDMSG/RCVMSG state machines (~190 B).  Roughly 235 B of asm
    remaining out of an original ~470 B SNIOS body -- a 50% asm
    reduction without any byte cost.
  - Both compilers stable at +8/+10 B over Phase 0 baseline (the
    Phase 2 split-cost), unchanged across Phases 3 and 4.

- **Issue activity**: Phase 4 of #75 done.  Phases 5 (SNDMSG state
  machine, ~80-90 B) and 6 (RCVMSG state machine, ~110 B) remain.
  These are the highest-risk pieces because:
  (a) `pop hl` discard-caller-return pattern (SNDRET) is structured
      C-hostile -- needs a setjmp/longjmp equivalent OR explicit
      `__naked` + inline asm preserving the stack manipulation;
  (b) wire-protocol semantics need byte-for-byte preservation against
      the CP/NET 1.2 spec to avoid silent interop breakage with the
      mpm-net2 host.
  The conservative path (matching Phases 1-4): port both as `__naked`
  + ASM_VOLATILE bodies, byte-neutral, just relocate the source.

## Phase 54: cpnos-rom SNIOS asm→C migration, Phase 3 of #75 (May 10, 2026) — Easy

- **Goal**: continue #75 by porting the byte-I/O wrappers (SENDBY,
  RECVBY, RECVBT) from asm to portable C, written as `__naked`
  functions with `ASM_VOLATILE` bodies that match the original asm
  byte-for-byte.  These wrappers preserve HL+DE for asm callers
  (SNDMSG/RCVMSG state machines hold the message pointer in HL across
  many calls) -- a contract that sdcccall(1) C does not natively
  express, hence the inline-asm bodies.

- **Functions ported (3)**: SENDBY (~7 B), RECVBY (~17 B), RECVBT
  (~16 B).  ~40 B of asm body removed from each of `snios.s` +
  `sdcc/snios.asm`.  14 call sites in each file re-pointed:
  `call SENDBY` -> `call _snios_sendby` (and likewise for RECVBY/RECVBT,
  including the two `jp SENDBY` tail-calls in NETOUT/PREOUT and BADCKS).

- **Result** (4-cell polypascal-test all PASS, BYTE-NEUTRAL):

  | metric | before (Phase 2) | after | Δ |
  |---|---:|---:|---:|
  | Clang payload | 1720 B | **1720 B** | **0 B** |
  | SDCC resident | 1868 B | **1868 B** | **0 B** |
  | clang/pio-irq polypascal | 50.57 s | 50.75 s | ~0 |
  | clang/sio polypascal     | 59.19 s | 59.57 s | ~0 |
  | sdcc/pio-irq polypascal  | 49.95 s | 51.19 s | ~0 |
  | sdcc/sio polypascal      | 60.75 s | 60.19 s | ~0 |

  Both compilers emit identical bytes to the asm version because the
  bodies ARE the asm version, hosted in `__naked` C functions.  The
  only thing that moved was the source language; the resulting
  machine code is unchanged.

- **Two compiler-specific gotchas captured during bring-up**:

  (a) **Clang `__naked` forbids non-ASM C statements**: even
  `(void)b;` (a cast-to-void to silence unused-parameter warning)
  triggers `error: non-ASM statement in naked function is not
  supported`.  Resolution: drop the C-level parameter declaration
  from `void snios_sendby(uint8_t b)` to `void snios_sendby(void)`
  -- the byte-in-A arrival is invisible to C anyway and asm callers
  don't care about C parameter declarations.  Future C callers can
  add a parallel prototype if they need to declare the arg.

  (b) **z88dk's z80asm rejects GAS-style numeric local labels**:
  `1:` / `jr z, 1b` is clang-inline-asm idiom but z80asm requires
  alphanumeric labels.  Resolution: use globally-unique alphanumeric
  names (`_snios_recvby_loop`).  This is the same gotcha session 45
  flagged for cross-compiler inline asm; capturing it here as a
  recurring pattern in future SNIOS phases.

- **Cumulative across Phases 1+2+3 (#75)**:
  - 11 SNIOS functions in portable C (NTWKIN, NTWKST, CNFTBL, NTWKER,
    NTWKBT, NTWKDN, ERRRTN, SNDERR1, SENDBY, RECVBY, RECVBT).
  - All 6 trivial JT entries, all 2 error-path stubs, and all 3
    byte-I/O wrappers now in C.  Asm side still owns: JT (24 B,
    ABI-fixed); calling-convention bridges (_snios_sndmsg_c,
    _snios_rcvmsg_c, _snios_sndmsg_force, ~12 B); JT trampolines
    (SNDMSG_DISPATCH, RCVMSG_DISPATCH, ~6 B); checksum helpers
    (NETOUT/PREOUT, NETIN, MSGOUT, MSGIN, ~25 B); and the protocol
    state machines (SNDMSG/RCVMSG and their internal labels, ~190 B).
  - Clang +8 B over Phase 0 baseline (1712 -> 1720, all from
    Phase 2's NTWKDN/ERRRTN/SNDERR1 split).
  - SDCC +10 B over Phase 0 baseline (1858 -> 1868, same provenance).
  - 4-cell polypascal-test PASS at every phase boundary.

- **Lesson** (style): for functions whose contract is expressed in
  Z80 register conventions that sdcccall(1) doesn't reach, "C
  function with __naked + ASM_VOLATILE body matching the asm
  byte-for-byte" is the cleanest answer per the user's stated rule.
  Cost is exactly 0 bytes (the asm IS the function body) and benefit
  is that all SNIOS source lives in `snios_c.c` for future
  edit/grep/review.  The .c file becomes the single source of truth.

- **Issue activity**: Phase 3 of #75 done; #75 remains open for
  Phases 4 (NETOUT/NETIN/MSGOUT/MSGIN), 5 (SNDMSG state machine),
  6 (RCVMSG state machine).  Phases 4-6 will ALSO need inline asm
  bodies for the parts that pass D-as-running-checksum and CY-as-
  timeout-flag, OR a structural rewrite of the calling contract.
  The structural rewrite likely yields cleaner C but unknown byte
  cost; the inline-asm-body approach is byte-neutral and preserves
  the existing asm-side contract.  Decision deferred to Phase 4
  start.

## Phase 53: cpnos-rom SNIOS asm→C migration, Phase 2 of #75 (May 10, 2026) — Easy

- **Goal**: continue #75 by porting the housekeeping entry points
  (NTWKDN, ERRRTN, SNDERR1) from asm to C, and expose SNDMS0 (the
  asm-internal "send-frame-bypassing-ACTIVE-check" entry) as a
  public C-callable symbol `_snios_sndmsg_force` for NTWKDN's use.
  This sets up Phase 3+ to call into protocol entry points by
  well-named public symbols rather than internal local labels.

- **Functions ported (3)**: NTWKDN, ERRRTN, SNDERR1.  ~28 B of asm
  body removed from each of `snios.s` + `sdcc/snios.asm`.  Three new
  C functions added to `snios_c.c`.  ERRRTN's asm-side fall-through
  to SNDERR1 (which produced the trailing `ld a, 0xFF; ret`) was
  replaced by an explicit `return 0xFF` at the end of
  `snios_errrtn_impl`; SNDERR1 stands alone as `snios_snderr1_impl`.

- **New public asm bridge** (4 B per compiler, declared in both
  snios.s and sdcc/snios.asm):

  ```
  _snios_sndmsg_force:
      ld   b, h        ; HL (sdcccall arg) -> BC (SNDMS0 arg)
      ld   c, l
      jp   SNDMS0      ; tail-call into the bypass entry
  ```

  Used by `snios_ntwkdn_impl` to send the FNC=0xFE shutdown frame
  even when the slave's cfgtbl.netst.ACTIVE flag is clear.

- **Asm callers re-pointed**: `jp ERRRTN` -> `jp _snios_errrtn_impl`
  (2 sites in each compiler: SNDTMO + RCVTMO); `jp z, SNDERR1` ->
  `jp z, _snios_snderr1_impl` (2 sites: SNDMSG-not-active +
  RCVMSG-not-active).

- **Result** (4-cell polypascal-test all PASS):

  | metric | before (Phase 1) | after | Δ |
  |---|---:|---:|---:|
  | Clang payload | 1712 B | **1720 B** | **+8 B** |
  | SDCC resident | 1860 B | **1868 B** | **+8 B** |
  | clang/pio-irq polypascal | 50.73 s | 50.57 s | ~0 |
  | clang/sio polypascal     | 59.19 s | 59.19 s | 0 |
  | sdcc/pio-irq polypascal  | 50.91 s | 49.95 s | ~0 |
  | sdcc/sio polypascal      | 59.95 s | 60.75 s | ~0 |

- **Cumulative across Phases 1+2 (#75)**:
  - 8 SNIOS functions (NTWKIN, NTWKST, CNFTBL, NTWKER, NTWKBT,
    NTWKDN, ERRRTN, SNDERR1) now in portable C.  All 6 trivial JT
    entries (everything except SNDMSG / RCVMSG) are C-side.
  - Clang +8 B over baseline (1712 -> 1720).
  - SDCC +10 B over Phase-1-baseline (1858 -> 1868).
  - 0 protocol-state-machine code touched.  4-cell PASS at parity.

- **Lessons**:
  - **Bridge wrappers are cheap and clarify boundaries**: the 4 B
    `_snios_sndmsg_force` wrapper costs almost nothing and makes the
    asm-internal SNDMS0 entry callable from C with the standard
    sdcccall(1) HL convention.  Worth doing whenever a C-side caller
    needs an internal asm label.
  - **Explicit `return 0xFF` reads cleaner than asm fall-through**:
    The asm version's ERRRTN -> SNDERR1 fall-through saved 0 bytes
    (the `ld a, 0xFF; ret` was shared) but obscured the contract.
    The C split with both functions ending in `return 0xFF` costs
    2 B but makes the success/error semantics explicit in the source.
  - **NTWKDN's `xor a; ret` discarded SNDMSG's return value**: the
    asm version called SNDMS0 (which returns 0 on success / 0xFF on
    error) but always returned 0 to NDOS regardless.  Faithfully
    preserved in the C version (`snios_sndmsg_force(...)` result
    is discarded).  Documented in source so future readers don't
    "fix" what looks like a bug.

- **Issue activity**: #75 progresses; Phase 3+ candidates remain
  (SENDBY/RECVBY/RECVBT character I/O wrappers; NETOUT/NETIN/MSGOUT/
  MSGIN checksum helpers; SNDMSG/RCVMSG state machines).  Phase 3
  blocked by HL/DE-preservation contract -- character-I/O wrappers
  are inherently asm-shaped under sdcccall(1) without a structural
  rewrite of their callers (which is Phase 5+).  Honest assessment:
  Phase 2 captured most of the easy wins; further C migration
  requires structural changes to the protocol state machines.

## Phase 52: cpnos-rom SNIOS asm→C migration, Phase 1 of #75 (May 10, 2026) — Easy

- **Goal** (per #75): rewrite SNIOS body from hand-written asm to
  portable C, eliminating the dual hand-port maintenance burden.  This
  phase ports the trivial non-protocol functions; protocol state-machine
  bodies (SENDBY/RECVBY/RECVBT, NETOUT/NETIN/MSGOUT/MSGIN, SNDMSG/RCVMSG
  and helpers) and NTWKDN deferred to later phases.

- **Functions ported (5)**: NTWKIN, NTWKST, CNFTBL, NTWKER, NTWKBT.
  ~17 B asm body removed from each of `snios.s` + `sdcc/snios.asm`.
  New file `cpnos-rom/snios_c.c` (~50 LOC) holds the C bodies; JT
  slots updated to `jp _snios_<name>_impl`.  ERRRTN's `call NTWKER`
  (asm-side caller) re-pointed to `call _snios_ntwker_impl`.

- **Result** (4-cell polypascal-test all PASS):

  | metric | before | after | Δ |
  |---|---:|---:|---:|
  | Clang payload | 1712 B | **1712 B** | 0 (byte-neutral) |
  | SDCC resident | 1858 B | **1860 B** | **+2 B** (≈1%) |
  | clang/pio-irq polypascal | 50.73 s | 50.73 s | ~0 |
  | clang/sio polypascal     | 59.19 s | 59.19 s | ~0 |
  | sdcc/pio-irq polypascal  | 50.91 s | 50.91 s | ~0 |
  | sdcc/sio polypascal      | 59.95 s | 59.95 s | ~0 |

- **Two compiler-specific gotchas captured in code comments**:

  (a) **CNFTBL pointer return**: NDOS's contract is HL=cfgtbl, but
  both compilers' sdcccall(1) ABI returns 16-bit pointers in **DE**,
  not HL.  Clang emitted `ld de,_cfgtbl; ret` and SDCC the same.
  The C declaration `struct cfgtbl *snios_cnftbl_impl(void)` cannot
  satisfy NDOS's ABI on either compiler.  Resolved with `__naked` +
  `ASM_VOLATILE("ld hl,_cfgtbl\n\tret")` -- single inline asm site.

  (b) **NTWKER tail-call alias**: SDCC's optimizer detected that
  `void f(void) {}` is a `ret` and aliased `_snios_ntwker_impl` to
  z88dk's runtime `l_ret` symbol (`code_l_sccz80` library section).
  Aliasing is harmless because (i) `check_sdcc_layout.py` verified the
  alias resolves inside the resident range, (ii) NDOS's `ret`-only
  contract for NTWKER is satisfied either way, and (iii) clang doesn't
  perform the alias.  Documented in the source comment so future
  readers don't re-investigate.

- **Bring-up bug found and fixed**: first build of `snios_cnftbl_impl`
  as plain C (without `__naked`) compiled but boot-hung the slave at
  the truncated-banner-reprint pattern (Phase 51A.3-style stack
  corruption).  Bisect via `llvm-nm` + audit dump took ~10 minutes
  to localise to gotcha (a).  Polypascal-test caught the regression
  before commit per `feedback_no_commit_first_version`.

- **Lessons captured for #75 future phases**:
  - Functions whose asm body relies on a register-return convention
    different from sdcccall(1) (HL vs DE for pointers, CY flag for
    timeout, D for running checksum) need `__naked` + inline asm at
    the call boundary -- they are NOT pure C.  Audit the existing asm
    for these conventions BEFORE assuming portable C will work.
  - SDCC's tail-call aliasing to `l_ret` / `code_l_sccz80` symbols
    is safe when the audit catches them, but generates non-obvious
    map-file output.  Document the alias in the C source so future
    readers understand the linker symbol pointing to a library
    section is intentional.

- **Issue activity**: Phase 1 of #75 done; #75 stays open.  Next
  phases: SENDBY/RECVBY/RECVBT (Phase 2), NETOUT/NETIN/MSGOUT/MSGIN
  (Phase 3), SNDMSG/RCVMSG state-machine (Phase 4 -- HIGHEST risk).

## Phase 1: SYSGEN Reconstruction (Apr-May 2023)
- **2023-04-28**: Initial commit. SYSGEN.ASM from CP/M 2.2 source, RCSYSGEN.COM from RC702 system
- **2023-04-28**: MAC assembler chosen (Digital Research native CP/M assembler)
- **2023-04-29**: SYSGEN.COM byte-identical to RCSYSGEN.COM — first byte-exact reconstruction
- **2023-04-29**: Multi-density track/sector mapping documented (mini/maxi translation tables)
- **2023-05-07**: Added SYSTEM.ORG for reference comparisons

## Phase 2: Toolchain Modernization (Sep 2025)
- **2025-09-21**: Added zmac assembler (macOS native) — cross-assembly without CP/M emulator
- **2025-09-21**: Toolchain decision: zmac with DRI syntax compatibility over MAC under emulation

## Phase 3: ROA375 Boot PROM (Jun 2025, then Feb 2026)
- **2025-06-29**: Added ROA375 autoload PROM binary and ROB358 (RC703 variant) source reference
- **2026-02-08**: Ghidra seeding script for ROM analysis; Makefile for SYSGEN
- **2026-02-08**: Fresh ROM disassembly started with PORT14 documentation
- **2026-02-09**: Byte-exact disassembly of ROA375 achieved (z80dasm + manual cleanup)
- **2026-02-10**: Raw disassembly converted to annotated style with EQUs and labels
- **2026-02-11**: CLAUDE.md created; rob358.mac adapted for zmac
- **2026-02-14**: Systematic documentation: port values, CRT work area, comment style standardized

## Phase 4: ROA375 C Rewrite (Feb 16-19, 2026)
- **2026-02-16**: Architectural decision: rewrite ROA375 in C using z88dk with sdcc backend
- **2026-02-16**: z88dk toolchain added; autoload-in-c/ scaffold created
- **2026-02-16**: Full C implementation: boot logic, FDC driver, HAL abstraction, host tests
- **2026-02-17**: Code too large for 2KB PROM — all C moved to hand-written assembly
- **2026-02-17**: Key decision: switch to sdcccall(1) ABI — params in A/HL/DE
- **2026-02-17**: Reversed course: globals-only C experiment showed sdcc can be small enough
- **2026-02-18**: Progressive migration back to C: boot7, hal_delay, init functions
- **2026-02-18**: Final result: 1984 bytes (64 to spare), boots in rc700 emulator
- **2026-02-19**: CRT/display interrupt handler documented and renamed

## Phase 5: CP/M BIOS Reverse Engineering (Feb 19-21, 2026)
- **2026-02-19**: BIOS RE analysis started — imd2raw.py extracts Track 0 from disk images
- **2026-02-20**: jbox.dk rel.2.1 BIOS sources obtained — modular structure identified
- **2026-02-20**: 58K Compas BIOS disassembled from disk image, byte-verified
- **2026-02-20**: verify_bios.py created for automated BIOS verification
- **2026-02-21**: patch_bios.py, imdinfo.py tools created for disk image manipulation
- **2026-02-21**: Conditional assembly restructured: COMPAS renamed to REL14
- **2026-02-21**: CONFI.COM reverse engineered (SIO label swap bug discovered)

## Phase 6: BIOS Source Reconstruction — All 13 Variants (Feb 21 - Mar 1, 2026)
- **2026-02-21**: rel.2.3 MAXI build added; RC703 analysis began
- **2026-02-24**: PHE358A.MAC analyzed (RC702E variant PROM with RAM disk)
- **2026-02-25**: bin2imd.py: RC703 format support added
- **2026-02-27**: 14 unique BIOSes extracted from 20 disk images
- **2026-02-27**: MAME boot testing: UPD765 ST0 HD bit regression discovered
- **2026-02-28**: REL20 conditional assembly added — 5 variants from shared source
- **2026-03-01**: All 13 BIOS variants byte-verified:
  - src/ (shared): REL20, REL21, REL22, REL23-mini, REL23-maxi (5)
  - src-58k/: REL13-mini, REL14-mini, REL14-maxi (3)
  - src-rc703/: REL10, REL12, RELTFj (3)
  - src-rc702e/: REL201-mini, REL220-QD (2)

## Phase 7: REL30 New BIOS Development (Mar 1-3, 2026)
- **2026-03-01**: BIOS rel.3.0 created — new features, not a reconstruction
- **2026-03-01**: SIO ring buffer (256B, page-aligned) + PIO keyboard ring buffer (16B)
- **2026-03-01**: 8-N-1 at 38400 baud on SIO Channel A (was 7-E-1 at 1200)
- **2026-03-01**: Bidirectional serial verified: PIP file transfer byte-identical
- **2026-03-02**: RTS flow control with hysteresis (deassert at 248, re-assert at 240)
- **2026-03-02**: AUTOEXEC.COM disassembled; run_mame.sh automation script
- **2026-03-03**: Ring buffer optimization: register-cached TAIL, parametric size
- **2026-03-03**: SCROLL optimization: unrolled LDIR into 16-wide LDI loop (20% faster)

## Phase 8: CP/NET Implementation (Mar 4-6, 2026)
- **2026-03-04**: SNIOS.SPR written (1280B Z80 assembly): hex-encoded CRC-16 serial framing
- **2026-03-04**: Python CP/NET server: BDOS F13-F40, F64-F65, F70-F71 over TCP
- **2026-03-04**: SPR relocatable format implemented (dual-assembly bitmap technique)
- **2026-03-04**: File transfer validated: 204KB BIGFILE.DAT, 1600 records, zero packet loss
- **2026-03-06**: Automated test suite: autotest.lua (MAME Lua) + run_test.sh orchestrator
- **2026-03-06**: imd_cpmfs.py: CP/M file injector for IMD disk images
- **2026-03-06**: Server expanded: F28/F30/F33-F35/F40 handlers added
- **Key decision**: Custom hex-encoded CRC-16 protocol (from cpnet-z80 serial SNIOS)
  over DRI's original ENQ/ACK protocol — simpler, proven in other Z80 implementations
- **Key decision**: BIOS READER/PUNCH entry points for I/O (not direct SIO access)
  — simpler SNIOS, ring buffer handled by BIOS ISR

## Phase 9: RC702E Modular Source (Mar 7, 2026)
- **2026-03-07**: RC702E BIOS split into modular source files (current branch: rc702e-modular)
- **2026-03-07**: Work area 0xFFD0-0xFFFF mapped with ORG+DS layout

## Phase 10: CP/NOS autoloader PROM — bring-up (Apr 20, 2026)
- **2026-04-20**: New subtree `cpnos-rom/` — combined autoloader + runtime BIOS image
  intended to burn into RC702's two 2 KB EPROMs.  Goal: cold-boot a CP/NOS slave
  directly from PROM, no 8″ floppy required.  **(Easy)** basic skeleton (reset.s,
  linker script, clang Z80 build) landed in hours.
- **2026-04-20**: PROM-disable hazard diagnosed and fixed — `OUT (0x18),A` has
  to be issued from RAM-resident code, not from PROM-backed code that's about
  to vanish from under the program counter.  **(Hard)** MAME boot test reliably
  reproduced the hazard only after explicit PROM-mapping assertions were added.
- **2026-04-20**: SIO-B (polled) + SIO-A (transport) + CTC bring-up in C;
  38400 8N1 TX verified.  **(Easy)** — same ports as rcbios-in-c, semantics
  unchanged.
- **2026-04-20**: Netboot protocol wired end-to-end against the Python server;
  cold-boot fetches a remote image into RAM.  First hang was in FNC=4 (execute)
  — server-side protocol quirk, not Z80 side.  **(Medium)**

## Phase 11: CP/NET on bare CP/NOS — real NDOS/CCP (Apr 20, 2026)
- **2026-04-20**: Ported SNIOS from rcbios-in-c into cpnos-rom, dropped BIOS_BASE
  to 0xF200 to make room; SNDMSG/RCVMSG round-trip PASS.  **(Easy)** — SNIOS was
  already hardware-independent above the BIOS layer.
- **2026-04-20**: DRI .SPR page-relocator written in C — streams NDOS.SPR and
  CCP.SPR from the server, walks the bitmap, installs at chosen RAM addresses.
  **(Hard)** the 128-byte "ignored sector" at the head of the .SPR threw off
  the relocator until the alignment bug was caught.
- **2026-04-20**: CCP reaches PC inside NDOS entry — first sign the relocated
  modules are cross-calling correctly.
- **2026-04-20**: 8275 CRT + 8237 DMA bring-up in C; display refreshes from RAM.
  **(Medium)** — CRT parameter values were transcribed from rcbios-in-c, DMA
  autoinit-mode discovered experimentally.
- **2026-04-21**: Zero-page convention switched from null-trap to real WBOOT
  vector so NDOS's TLBIOS-walk patches the right BIOS JT.  **(Hard)** —
  debugging NDOS's opaque post-handoff behaviour required memory dumps at
  multiple instants to find where page 0 was getting scribbled.
- **2026-04-21**: SIO-B captured to `/tmp/cpnos_siob.raw`; ^C warm-boot via
  SIO-B injection works.
- **2026-04-21**: Server gains full CP/NET BDOS surface: OPEN/READ/WRITE,
  SEARCH FIRST/NEXT, MAKE, DELETE, RENAME, GET VERSION, plus R/O and SYS
  attribute handling.  `$$.SUB` automation lets MAME execute scripted
  CCP command sequences for regression tests.

## Phase 12: DRI CP/NOS monolith build (Apr 21, 2026)
- **2026-04-21**: `cpnos-build/` — a separate subdir that runs DRI's original
  RMAC+LINK under VirtualCpm (Java) to assemble and link `cpnos.asm` +
  `cpndos.asm` + `cpnios.asm` + `cpbdos.asm` + `cpbios.asm` into one
  flat `cpnos.com` image.  **(Medium)** — most friction was in VirtualCpm
  invocation, not the 8080 sources themselves.
- **2026-04-21**: Link addresses relocked to `CODE=0xD000 / DATA=0xCC00`
  so CP/NOS doesn't collide with our resident BIOS + display RAM above.
- **2026-04-21**: `dri_split.py` + `dri2gnu.pl` bridge — one-instruction-per
  -line reformatted DRI sources, then mechanical translation into GNU-as
  Z80 syntax.  Enables double-assembly for byte-verification of CCP.SPR.
- **2026-04-21**: First full boot: `cpnos.com` streams from server, NDOS
  routes BDOS through SNIOS, CCP reaches `A>`.  **This was the first
  end-to-end PASS.**

## Phase 13: MP/M II retarget (Apr 22, 2026)
- **2026-04-22**: Decision: replace the Python proxy server with a live
  MP/M II running on the host under z80pack cpmsim.  Goal: prove the
  stack works against a stock unmodified master.  Motivation: the Python
  server risked drifting into a bespoke protocol the DRI slave wouldn't
  accept on real MP/M.  **(Hard)** the decision itself — and documenting
  which MP/M version + disk images to use.
- **2026-04-22**: `netboot_mpm.c` replaces the legacy FMT=0xB0 custom
  protocol with standard CP/NET 1.2 LOGIN (fn 64) + OPEN (fn 15) +
  READ-SEQ (fn 20) + CLOSE (fn 16) against a virtual A:CPNOS.IMG.
  **(Medium)** — the DRI functions were documented but MP/M's exact
  response framing needed trial-and-error.
- **2026-04-22**: `netboot_server.py` rewritten to implement the same
  CP/NET 1.2 surface, so the slave can be tested without cpmsim running
  — the two servers are now wire-compatible.
- **2026-04-22**: SLAVEID normalized to 0x01 end-to-end (was 0x70 from
  historical RC-in-house choice).  `Makefile: $(OBJS): Makefile` dep
  added after a stale `cfgtbl.o` sent 0x70 on the wire despite flag
  change — **(painful)** lesson in build-graph hygiene.
- **2026-04-22**: BIOS_BASE moved 0xF200 → 0xED00 (RESIDENT grows 1.5 KB
  → 2.75 KB).  Three follow-up bugs fell out: IVT at 0xF100 got copied
  over by the resident memcpy (fixed by moving IVT to 0xEC00, issue #35
  added a linker ASSERT); SNIOS JT constant in cpnios.s stale; impl_wboot/
  impl_boot traps re-pointed at 0xD000 (issue U).  **(Hard)** — each bug
  was silent at build time and only showed up as a mid-boot lockup.

## Phase 47: cpnos-rom data-driven relocator (header-prefixed payload) (May 6-7, 2026) — branch `session47-cpnos-header-driven-relocator` in rc700-gensmedet/cpnos-rom

- **Goal**: stop the four-way coupling (C decl + linker script + Makefile
  awk + Makefile defsym) that wires payload metadata into the relocator,
  before adding any more BSS regions or page-aligned reservations.
  Replace it with a payload header the relocator reads at boot.

- **Reached** (clang side, plan steps 1-5 of 8):
  - `payload_header.h` defines the on-PROM struct (magic + chunk
    srcs/sizes + cold_entry + checksum_magic + variable-length BSS-pair
    list, sentinel-terminated).
  - `tasks/scripts/gen_payload_header.py` reads payload.elf symbols
    (clang) or cpnos_payload.map (SDCC) and emits payload_header_data.s.
  - `relocator.c` rewritten to read `_payload_header` and act on its
    fields — no externs, no compile-time constants except the magic.
    Preserves the LDIR → BSS → checksum → JP ordering invariant (user-
    restated 2026-05-07).
  - `relocator.ld` places `.payload_header` right after relocator code;
    emits `__chunk_a_start`/`__chunk_b_start` symbols at chunk physical
    PROM offsets (linker-decided, no hardcoded 0x0400).
  - `payload.ld` `INIT origin: 0x0100 → 0x0200` to give the data-driven
    relocator a 512 B code budget.
  - `Makefile` `PROM0_TAIL_SIZE: 1024 → 768` (chunk B grows from 708 to
    964; total payload size unchanged).
  - **6 of 7 cross-stage `--defsym` lines deleted** from the relocator-
    link rule; only `__stack_top` remains (consumed by reset.s before
    the relocator runs).
  - Compiler stamped in the boot banner via `CPNOS_COMPILER_NAME` macro
    in `compiler/compat.h` — selects `clang`/`sdcc`/`hitech`/`host`
    from predefined compiler macros at preprocess time.

  Verification: `make cpnos-polypascal-test` PASS end-to-end (PPAS
  PRIMES → 29989 → E>) at every step that touched the relocator
  pipeline.  `_payload_header @ 0x185` in the relocator binary, 30 B
  contents.  **(Medium)** — required two iterations on the .init VMA
  shift (relocator code grew from 110 B to 393 B), one on the indirect-
  call lowering (used `__call_iy` which we don't have; replaced with
  inline asm).

- **Side fix** (this session): `_pio_rx_buf_page` derived from
  `HIGH(_pio_rx_buf)` in BOTH pipelines instead of being a hardcoded
  literal that disagreed with the actual buffer placement.  SDCC: new
  `bss_pio_rx` SECTION at 0xEC00 (page-aligned, 256 B); buffer at
  0xEC00, page constant = 0xEC.  Clang: page-alignment ASSERT in
  `payload.ld` plus shift-and-mask in the symbol expression.

- **Side fix** (this session): clang build hygiene — `relocator.c`
  was missing `<stddef.h>`; `payload.ld` was missing
  `__pio_rx_bss_start/end` symbols; Makefile was missing 4 `--defsym`
  lines (now all dropped along with the rest in plan #19 step 5).
  Without these, the inherited "BSS-clearing relocator" change from a
  prior session wouldn't link.

- **Documented** (this session):
  - `cpnos-rom/tasks/memory-layout-investigation-2026-05-06.md` — full
    survey of both pipelines' MEMORY-region / SECTION / `defc` /
    ASSERT vocabularies, catalog of pinned-vs-movable items,
    recommendation for fully linker-driven layout.
  - `tasks/session47-cpnos-header-driven-relocator.md` — this session's
    delivery + open issues + risks.
  - 4 new memory rules (`feedback_memory_layout_on_port.md`,
    `feedback_extract_rules_from_time_sinks.md` (meta — write rules
    from time-sinks proactively), `feedback_relink_dependencies_atomically.md`,
    `feedback_kill_stale_servers_on_test_target.md`).

- **Reached** (afternoon/evening continuation 2026-05-07, steps 6-8):
  - **Step 6** (commit `d2485c8`): `relocator.c` compiles under SDCC and
    replaces `prom_loader.asm` at link time.  SDCC slave boots through
    the unified C relocator (banner `RC702 CP/NOS 55K SIO sdcc ...` on
    display, slave reaches netboot wait loop).  Two side-fixes folded
    in: SDCC `reset.asm` SP changed 0xF700 → 0xEC00 (library calls
    during the relocator must not push into resident bytes the
    checksum is about to read), and a `__naked` `relocator_zero` helper
    inlines LDIR-from-self to side-step a z88dk-zsdcc 4.5.0 calling-
    convention mismatch where `--sdcccall=1` codegen for `memset(d,0,n)`
    doesn't match `_memset`'s sdcccall=0 stack-arg preamble (filed
    upstream-bug task #26).
  - **Step 7 clang side** (commit `0e8fc58`): `--include-ivt` added to
    `gen_payload_header.py` invocation; `(__ivt_start, __ivt_end)`
    lands in the header's bss_pairs list and the relocator zeroes the
    IVT region during the BSS-clear pass before checksum verification.
  - **Step 8** (commit `302ce24`): `sdcc/prom_loader.asm` physically
    deleted; `check_sdcc_layout.py` extended with payload-header sanity
    check (verifies magic 0x6350, version 0x0001, sentinel pair within
    64 B after header).  Both fail paths verified by manual tampering.
  - **Persistent SDCC IX+/IY+ frame-pointer regression gate**
    (commit `55d68c2`): `tasks/scripts/check_no_frame_ptr.py` scans
    per-source `.s` files for `(ix±d)` / `(iy±d)` operands, identifies
    the violating function, and fails the build if any new (file,
    function) appears or a baselined function's count grows.  Two
    known violators captured (`relocator.c::relocate` 10 hits,
    `resident.c::delete_line` 2 hits — tasks #27/#28).
  - **`--opt-code-size` investigation + revert** (commit `8429b8d`):
    User flagged that SDCC was at default speed-tuned codegen.
    Lifting `--opt-code-size` to zcc level (matching
    `rcbios-in-c/sdcc/Makefile`'s established pattern, captured as
    HARD memory rule `feedback_check_sibling_subprojects.md`) flips
    z88dk's peephole file from `sdcc_peeph.3` to `sdcc_peeph_cs.3`
    and saves ~17 B across the resident.  But `--opt-code-size` also
    factors out an 11 B `___sdcc_enter_ix` shared helper — amortises
    only with many IX-frame functions, and our build has just 2
    (the audit's known violators).  Net: +5 B resident, overflows
    display memory at 0xF800.  Reverted; documented in Makefile
    comment for the next attempt.

- **Memory-map gap analysis (2026-05-07 evening) — initial 0xFFD0
  IVT plan was WRONG; corrected 2026-05-08**: display memory is
  0xF800..0xFFCF (2000 chars, 80×25); bytes 0xFFD0..0xFFFF are 48 B
  of scratch RAM (CRT frame counter at 0xFFFC..0xFFFF + 44 B free).
  Initial plan was to host the IVT there with `I = 0xFF` -- **this
  is unsafe**: under Z80 IM 2 the I register fixes a 256 B page and
  the CPU reads its ISR pointer from anywhere in that page based on
  the device-supplied vector low byte; with I = 0xFF the page is
  0xFF00..0xFFFF, of which 0xFF00..0xFFCF IS on-screen character
  RAM.  Any spurious or misprogrammed vector with low byte < 0xD0
  jumps to a pointer composed of screen bytes.  All pages I=0xF8..
  0xFF are similarly forbidden.  Valid IVT pages are pages whose
  entire 256 B range is owned by the slave AND not display: the
  actual fix landed in Phase 47b (Path 6) by placing the SDCC IVT
  inside a page-aligned `bss_ivt` SECTION in scratch BSS at 0xEA00
  (I = 0xEA), zero resident cost.  The 44 B at 0xFFD0..0xFFFB stays
  scratch RAM (frame counter, future use), NOT IVT.  Tracked as
  **#29**; SDCC side closed by Path 6, clang side still uses
  `__ivt_start = 0xF500` in resident (could mirror SDCC for symmetry
  to free 36 B of clang resident).

- **Two more memory rules captured (session 47 evening)**:
  `feedback_no_stale_dump_files.md` (`rm -f /tmp/foo` BEFORE every
  producer-command iteration); `feedback_no_dotall_backtracking.md`
  (don't combine Python `re.DOTALL` with non-greedy `.*?` over
  multi-line source — catastrophic backtracking).

- **Plan #19 status**: 7 of 8 structural steps fully done (1-6, 8);
  step 7 done on clang side; SDCC side closed by Phase 47b Path 6
  (IVT placed in `bss_ivt` page-aligned section at 0xEA00).  No more
  architectural unknowns.

- **Pending** (separate from plan #19):
  - **#29** clang-side mirror: move `__ivt_start` from 0xF500 in
    resident to a BSS-scratch page (matches SDCC) to free 36 B of
    clang resident.  Optional symmetry fix; no functional blocker.
  - **#27/#28** drive IX-spill audit baseline toward zero.
  - **#26** file the SDCC `--sdcccall=1`/`_memset` mismatch upstream.
  - **#21** runtime version check at boot (low priority).
  - **#13** hunt remaining JP-0 sources in SDCC build (gated on #29).

## Phase 51A: cpnos-rom SDCC resident shrink toward clang parity (May 9, 2026) — Medium

- **Goal** (user-stated): "I want to get the sdcc build to be as close
  in resident memory size to clang as reasonably possible.  The code
  should be as close to standard c as possible with as few ifdefs as
  possible, keeping the differences in the linker configuration.
  Consider if assembly code can be reverted back to C."

- **Strategy**: structural / linker-only fixes first (no codegen risk),
  then `#ifdef` collapses, then asm-to-C.  Phase 51A executed the
  first two layers.

- **Phase 51A.1 (commit f9ebadd, closes #19)**: retire NETBOOT_LEGACY
  / SERVER=proxy / netboot.c.  netboot_server.py was deleted in Phase
  48b leaving SERVER=proxy with no working server.  Removed:
  cpnos-rom/netboot.c (-220 lines), Makefile SERVER dispatch (-12
  lines), -DNETBOOT_LEGACY define, #ifdef NETBOOT_LEGACY block in
  cpnos_main.c (-1 #ifdef).

- **Phase 51A.2 (commit fad1efd, closes #68, -108 B resident)**:
  split cpnos_main.c -> cpnos_cold.c.  cpnos_cold.c (NEW) holds
  cpnos_cold_entry + print_banner in INIT_CODE / INIT_RODATA;
  cpnos_main.c keeps resident_handoff + zp_init_data in RESIDENT.
  Mirrors clang's `__attribute__((section))` per-function placement
  using SDCC's per-file `--codeseg` flag.  Linker structural change:
  PROM0 chunk A start 0x0400 -> 0x0520 to mirror clang's payload.ld
  layout, freeing INIT_CODE budget by 288 B.  sdcc/sections.asm
  __payload_chunk_a_size 1024 -> 736.  gen_payload_header.py
  --chunk-a-src=0x0400 -> 0x0520.  No codegen change.

- **Phase 51A.4 (commit 1ee8053, -22 B resident; intermediate 51A.3
  attempts not committed -- see #72)**: drop two diagnostic-cleanup
  pieces after #57/#60 closed.  cpnos_main.c::resident_handoff drops
  the `boot_probe('H')` call site (-4 B, -1 #ifdef).  sdcc/snios.asm
  drops the NTWKIN_W instrumentation wrapper (-18 B RESIDENT_SNIOS).
  Plus a correctness fix: cpnos_cold.c now includes cpnos_addrs.h so
  CPNOS_TPA_KB expands to "55" in the banner instead of literal
  "CPNOS_TPA_KB".

- **Result** (cumulative Phase 51A: f17e826 -> 1ee8053):

  | metric | start (Phase 50) | after 51A | Δ |
  |---|---:|---:|---:|
  | Resident (RAM) | 2180 B | **2050 B** | **−130 B (−6%)** |
  | Cumulative since Phase 49 | 2756 B | 2050 B | **−706 B (−26%)** |
  | Gap vs clang | +538 B (+33%) | **+408 B (+25%)** | gap closed by 24% |
  | SDCC pio-irq polypascal | 52.91 s PASS | 53.25 s PASS | ±20 ms |
  | SDCC sio    polypascal | 60.79 s PASS | 60.83 s PASS | ±20 ms |

- **Issue #72 (filed, blocking ~123 B more savings)**: removing the
  `boot_probe` + `p_hex` + `bios_log_byte` function bodies in
  resident.c (closes #57/#60 fully) triggers a slave warm-boot loop
  with a truncated banner reprint.  Mechanism not identified; root
  cause investigation deferred.  Functions kept alive in this phase.

- **Lessons**:
  (a) When Phase 51A.3 broke boot, bisected by reverting individual
      Phase 51A.3 changes one at a time.  NTWKIN_W bypass alone =
      PASS; removing boot_probe/p_hex alone (keeping bios_log_byte) =
      FAIL.  The breakage is structurally unrelated to NTWKIN_W and
      lives in the boot_probe/p_hex/probe_once removal.  Surfaces
      that bisecting structural-change failures by file is faster
      than bisecting by line.

  (b) Truncated banner reprint pattern (banner bytes appearing AFTER
      PROM disable, missing trailing chars) is a hallmark of stack
      corruption causing a wrong PC to land in INIT_RODATA's banner
      string.  But INIT_RODATA is only valid PRE-disable, so the
      mechanism must involve something running before disable that
      gets re-entered post-disable, OR PROM disable not actually
      happening.  Filed as #72 for next-session follow-up.

  (c) The `--chunk-a-src` and `__payload_chunk_a_size` constants
      must move in lockstep when relocating chunk A.  Initial Phase
      51A.2 attempt forgot to update __payload_chunk_a_size in
      sdcc/sections.asm and the relocator read 256 B beyond PROM0
      tail (junk into RAM).  Black screen until both touched.

- **Issue activity**:
  Closed: #19 (NETBOOT_LEGACY retired), #68 (cpnos_main split).
  Filed:  #72 (boot_probe / bios_log_byte removal warm-boot regression).
  Not yet addressed: #69 (boot_probe to INIT, blocked by #72),
                     #70 (inline _memset, deferred),
                     #71 (--opt-code-size, untested).

## Phase 51D: cpnos-rom clang vs SDCC compiler-output comparison — exposed clang silent miscompile (May 9, 2026 late evening) — Medium

- **Goal**: per user request, compare clang Z80 vs z88dk-zsdcc cpnos-rom
  output and identify any glaring per-function discrepancies
  (≥ 1.5× ratio OR ≥ 50 B absolute Δ) — investigate those, ignore
  the long tail (memory rule `feedback_outlier_first_not_sweep`).

- **Comparison methodology**: pulled clang sizes from
  `llvm-nm --print-size --size-sort` on `payload.elf`; SDCC sizes from
  `cpnos.map` by partitioning addr-public-or-local symbols by section
  and computing `next_addr - this_addr`.  Initial pass that filtered
  out local symbols produced false positives (`_clear_screen` looked
  like 505 B because the next *public* symbol was 16 functions later;
  actual size was 16 B).  Including locals fixed it.

- **Single glaring outlier found**: `_resident_handoff`
    - clang: 18 B
    - SDCC: 58 B
    - Δ: +40 B, ratio 3.22×

  Other "borderline" entries (`_pio_b_set_input` 1.54×, `_cursor_down`
  1.53×) had absolute Δ ≤ 14 B — below the actionable threshold.

- **Investigation revealed clang silent miscompile**: clang's
  `_resident_handoff` ended at `jr $f331` infinite loop after
  `snios_ntwkin()` — the entire `if (entry != 0) { ... }` block
  containing the BIOS-JT memcpy + zero-page LDIR + `enter_coldst()`
  call was elided.  `_enter_coldst` had ZERO callers in the linked
  payload.  Polypascal-test under clang FAILED stage 1 (banner +
  25 netboot dots, then silence — never reaches `E>` prompt).

- **Root cause** (commit ca5663f, earlier this session): the #73
  ifdef-collapse work replaced inline asm with portable
  `__builtin_memcpy((void *)0, zp_init_data, sizeof(zp_init_data))`.
  Writing through a literal NULL pointer is undefined behaviour per
  ISO C; clang's optimizer detects the UB and treats every path that
  reaches it as unreachable, eliding the entire enclosing if-block
  AND the preceding BIOS-JT memcpy AND the `enter_coldst()` call.
  SDCC's non-aggressive optimizer compiled the body fine, hiding the
  bug behind the recent sessions' "tested SDCC PASS" pattern.

- **Why `volatile` didn't help** (attempted before inline asm):
  `volatile uint8_t *p = (volatile uint8_t *)0` qualifies the pointee
  for *accesses through p*, not the pointer's value.  Clang's
  constant-prop folds `p = 0` across the local; `__builtin_memcpy`'s
  signature drops the volatile qualifier (its dst is plain `void *`);
  UB detection re-fires.  Volatile would only help with a hand-rolled
  loop, not a memcpy call.

- **Fix** (commit `2db9aad`): inline asm via `ASM_VOLATILE` for the
  zero-page LDIR.  Both compilers accept the syntax (no
  register-pinning constraints).  `_resident_handoff` 18 → 54 B clang;
  `_enter_coldst` becomes a real callee.

- **Verification**:
  | metric                    | before fix | after fix |
  | ------------------------- | ---------: | --------: |
  | `_resident_handoff` clang | 18 B (broken) | 54 B (correct) |
  | clang polypascal-test     | FAIL stage 1 | **PASS** (50 s) |
  | SDCC polypascal-test      | PASS (52 s) | **PASS** (52 s) |
  | clang/payload.bin         | 1676 B     | 1712 B (+36 B for the if-block) |

- **Filed `#81`** to revisit later — is there a portable C alternative
  to inline asm for zero-page writes?  Candidates: per-TU
  `-fno-delete-null-pointer-checks`, runtime-computed pointer via
  linker symbol, llvm-z80 backend opt-out for nullptr-deref UB
  optimization, attribute suppression.  Current inline asm is a
  working solution; #81 is a followup not a blocker.

- **Lessons** (memory rules updated):
  - **`feedback_outlier_first_not_sweep` added (HARD RULE)**: when
    comparing two systems, find ≥1.5× / ≥50 B divergences and dig in;
    do NOT methodically chase every per-item difference.  Stated by
    user after I drafted a methodical sweep plan.
  - **Compilers-disagree-means-investigate** is the inverse of the
    existing `feedback_compilers_agree_means_harness` rule.  When
    two compilers DISagree at byte level on the same C source,
    suspect a real codegen / source UB issue and investigate; don't
    dismiss as "compilers differ."

- **Net session add**: 12 commits on origin/main, 8 issues closed
  (#73, #79, #64, #58, #59, #63, #62, #65), 1 reopened (#71), 2 new
  filed (#80 netboot overflow check, #81 portable-C zero-page LDIR).
  Clang slave booting again under polypascal-test for the first time
  since ca5663f's regression earlier today.

## Phase 51C: cpnos-rom build hygiene + dual-header SDCC parity + literal-address audit (May 9, 2026 evening) — Medium

- **Goal**: cluster of independent small-to-medium cpnos-rom hygiene
  improvements after Phase 51B.  Eight issues closed, one reopened
  with regression note, one filed.

- **Closed (8)**: #73 (inline-asm ifdef extraction), #79 (build gate
  for dead user PUBLICs + drop dead `_jump_to`), #64
  (`check_no_frame_ptr.py` switches to z88dk's `; Function NAME`
  comment for reliable function-entry detection), #58 (polypascal-test
  passes COMPILER env var through to MAME), #59 (`align 2` in
  RESIDENT_CHECKSUM replaces shell-pad odd-resident hack), #63
  (relocator stamps "MAGIC FAIL" on bad header magic, display init
  runs first), #62 (SDCC dual-header cross-PROM mismatch check —
  PROM1 byte 0 anchor + check_sdcc_layout.py PROM1 audit), #65
  (literal-address audit — `0xF800` -> `DISPLAY_ADDR`,
  `0xFFFC` -> `FRAME_COUNTER_ADDR`).

- **Reopened (1)**: #71 (`--opt-code-size`).  Initially landed at
  commit 25292cb claiming +5 B init savings, then bisect during
  polypascal-test run revealed silent boot regression — slave hangs
  in early init with SIO-B 0 bytes, no MAGIC FAIL / PROM MISMATCH /
  BAD CHECKSUM display message.  Suspected: `___sdcc_enter_ix`
  IX-prologue helper from `code_l_sdcc` interacts badly with
  sdcccall(1) state.  Reverted via local rebase; #71 stays open
  pending root-cause investigation.

- **Filed (1)**: #80 (netboot_mpm.c:163 dma overflow check uses
  `0xEE00` while comment talks about 0xED00 — discrepancy
  surfaced during #65's audit, may be off-by-256 safety bound bug).

- **Process lessons** (memory rules updated):
  - **HARD rule strengthened** (`feedback_no_commit_first_version`):
    any change to `relocator.c` / `payload_header_data.s` /
    `sdcc/sections.asm` anchored sections / `chunk_*_src` /
    `build_prom_image.py` invocations REQUIRES
    `make cpnos-polypascal-test COMPILER=sdcc` BEFORE commit.  The
    polypascal-test recipe AUTO-RESTARTS MP/M itself (steps 2/4 of
    the recipe), so "MP/M not running" is never a valid excuse to
    skip the runtime test.  I committed #62 (and earlier #71) without
    runtime verification; #71 had a silent regression that wasn't
    caught until I ran the test.
  - **§0 ABSOLUTE BAN added to MEMORY.md** for filesystem traversal
    outside `/Users/ravn/z80/`.  I ran `find / -name "..."` as a
    fallback in this session; user explicitly said "make it very bad
    to do this again."  Rule body now says "one more strike = trust
    broken" and explicitly bans `mdfind`, `locate`, fallback
    escalation, and `2>/dev/null` silencing.

- **Pushed commits (10 on main, 7c9a4cf -> 66c31a0)**:
  - 0bd7515 build gate: detect dead user PUBLIC symbols (#79); drop
    dead `_jump_to`
  - 8a850ab `check_no_frame_ptr`: detect functions via z88dk's
    `; Function NAME` header (#64)
  - 368538c SDCC: replace shell-pad odd-resident hack with linker
    `align 2` (#59)
  - da73aa9 polypascal-test: pass `COMPILER` env var through to MAME
    (#58)
  - e54cba7 relocator: stamp "MAGIC FAIL" on bad header magic, init
    display first (#63)
  - 1d259ea `check_unreferenced_publics`: ignore z88dk library paths
    (`../l/sdcc/`) — latent false-positive surfaced during bisect
  - 7739510 relocator: replace literal `0xF800` with `DISPLAY_ADDR`
    (#65)
  - fa23865 SDCC: enable dual-header cross-PROM mismatch check (#62)
  - 66c31a0 isr: replace literal `0xFFFC` with `FRAME_COUNTER_ADDR`
    (#65)

- **Test verification**: every commit on main was verified with
  `make cpnos-polypascal-test COMPILER=sdcc` PASS (PRIMES program
  ran to completion, 29989 seen, returned to E> prompt).  Both
  compilers build clean.

## Phase 51B: cpnos-rom SDCC resident shrink — followups #76, #70, #72, #73 (May 9, 2026 cont.) — Medium

- **Goal**: continue Phase 51A's structural+ifdef shrink toward clang
  parity.  Six commits this session (40d30b8 -> 8b9f611), three of
  them codegen-area shrinks, two structural+correctness, one new
  inline asm helper.

- **#76 narrow port API (commit 0ea01bd, -60 B SDCC resident)**:
  `_port_in(uint16_t)` / `_port_out(uint16_t, uint16_t)` -> 8-bit
  arguments.  Z80 I/O is hardware-8-bit; A8-A15 not decoded for I/O
  on RC702.  sdcccall(1) packs the 8-bit port into A and val into L
  (no stack), shrinking the per-call sequence.  Helper rewritten in
  hal.asm uses `ld c,a; in a,(c)` / `ld c,a; ld a,l; out (c),a`.

- **#70 inline _memset (commit 76c138c)**: replaces `__builtin_memset`
  in resident.c::erase_to_eol/eos with hand-rolled byte loops.  z88dk
  was emitting a libc `_memset` call (~30 B + dispatch); the inline
  loop is 6 B per site.  Eliminates the last z88dk libcall in
  resident code.  Sister fix: clang's `__builtin_memset` already
  inlines via LDIR-from-self for short constant counts.

- **#72 fix (commits 501efb4 + e8bd1f1, -174 B SDCC resident)**:
  bisected the Phase 51A.3 warm-boot regression.  Root cause:
  patch_payload_checksum.py overwrites the last 2 bytes of the
  linked resident image to make the word-additive checksum equal
  0xCAFE.  When resident shrank in Phase 51A, those 2 bytes
  collided with `_zp_init_data[6..7]`.  ZP[7] became 0x2D instead
  of 0xE7; CCP loaded with garbage in zero-page; warm-boot loop.
  Fix: dedicated `RESIDENT_CHECKSUM` section at end of resident
  chain holding a 2-byte placeholder.  Removed dead boot_probe /
  p_hex / bios_log_byte function bodies post-fix (-174 B).

- **#73 partial collapse, two of N sites (commits ca5663f, 8b9f611)**:
  collapse `#if defined(__clang__)` ifdefs gating inline LDIR/LDDR.
  - **cpnos_main.c LDIR site** (ca5663f): replaced with portable
    `__builtin_memcpy((void *)0, zp_init_data, 8)`.  Discovery: z88dk
    sdcc_peeph.3 inlines memcpy() to LDIR for both constant AND
    runtime sizes — no libcall.  Byte-neutral on both compilers.
  - **resident.c::insert_line LDDR site** (8b9f611): replaced with
    `__builtin_memmove(row + SCRN_COLS, row, count)`.  Added
    sdcc/runtime.asm with tight `_memmove_callee` (33 B) that
    overrides z88dk libc's 150 B version.  Refactored to share
    `row = CELL(0, cury)` once (hand-CSE for SDCC's local-only iCode
    optimizer).  **Side effect, correctness fix**: the previous SDCC
    `_insert_line` was a no-op stub (`(void)src; (void)dst;
    (void)count;`).  CP/NOS slave never scrolled-down on Ctrl-A;
    only the bottom row got blanked.  This commit makes insert_line
    work under SDCC for the first time.  +100 B SDCC resident is
    "0 -> working", not "small -> bigger".

- **#77 (Phase 51B.7, commit TBD)**: `_memmove_bwd_callee` for
  callers that statically know dst > src.  Saves direction check +
  add-bc/dec-hl preamble (~13 B inside helper).  insert_line is the
  obvious caller.  See implementation below.

- **Cumulative result** (Phase 51A.4 -> Phase 51B):

  | metric | start (51A.4) | after 51B | Δ |
  |---|---:|---:|---:|
  | SDCC resident | 2050 B | **1874 B** | **−176 B (−9%)** |
  | Cumulative since Phase 49 | 2756 B | 1874 B | **−882 B (−32%)** |
  | Gap vs clang | +408 B | **+158 B (+9%)** | gap closed by 61% |
  | Clang resident | 1714 B | 1716 B | +2 B (~neutral) |
  | Clang PROM0 | 1986 B | 1987 B | +1 B (~neutral) |
  | ifdef sites collapsed | — | 2 | — |

- **Lessons (session 51B)**:

  (a) **Z88dk's sdcc_peeph.3 inlines `memcpy` to LDIR** for both
      constant and runtime counts.  No need for `intrinsic_ldi(...)`
      or hand-rolled inline asm; portable `__builtin_memcpy` is the
      tightest option.  Discovered by probe-compile after the
      `__builtin_memmove blows up payload size` comment turned out
      to be stale.  Update the lessons doc when the toolchain has
      moved on; comments rot fast.

  (b) **`memmove` does NOT inline** — z88dk's `<string.h>` rewrites
      `memmove(d,s,n)` to `_memmove_callee(d,s,n)` which is ~150 B in
      libc.  Override in user object file (linker prefers user
      symbols over libc) for ~33 B custom callee-cleanup version.
      Three 16-bit args force fully-stack-passed callee-cleanup ABI
      (sdcccall(1) only register-passes first two).

  (c) **No-op stubs are silent correctness bugs**.  `_insert_line`
      had `#else (void)src; (void)dst; (void)count;` — SDCC built it
      as a literal no-op for sessions.  Audited every clang/SDCC
      ifdef site for similar patterns; no other harmful stubs found.
      Three "stubby"-looking sites are intentional alternate-mode
      markers (TRANSPORT_PROXY) or empty-but-functional helpers.

  (d) **SDCC has no global CSE** — local-only iCode CSE inside a
      basic block, no GVN/PRE pass, no flag toggles a global pass.
      Pointer-arithmetic shift-add chains expand at codegen time
      after iCode CSE has finished.  `cury * SCRN_COLS` repeated 3
      times = 3 separate shift-add chains in asm.  Hand-CSE in C
      source (assign to a local) is the only fix.  Clang doesn't
      care because LLVM has GVN + InstCombine + DAG combiner.

  (e) **0x520 is derived bottom-up** from upstream-region size
      caps in relocator.ld: reset (16 B) + relocator+header (672 B
      via `ASSERT __reloc_code_end <= 0x2A0`) + init (640 B via
      `ASSERT __init_end <= 0x520`) = 0x520.  PROM0 chunk-A budget =
      0x800 - 0x520 = 736 B (full on both compilers).  Three places
      must agree: relocator.ld, Makefile (`PROM0_TAIL_SIZE`),
      sdcc/sections.asm (`__payload_chunk_a_size`).

- **Issue activity**:
  Closed: #76 (narrow port API), #70 (inline _memset), #72 (checksum
          overlap with zp_init_data), partial #73 (2 of N ifdef sites).
  Filed:  #77 (`_memmove_bwd_callee` for direction-known callers).
  Open:   #73 (remaining ifdef sites — needs sdcc/runtime.asm
          additions or upstream z88dk peephole rules), #75 (SNIOS
          asm-to-C, multi-session, biggest remaining lever), #71
          (--opt-code-size, deferred).

## Phase 50: cpnos-rom SDCC cold-init code -> PROM-only (May 9, 2026) — Easy

- **Goal**: shrink SDCC resident size by mirroring clang's `.init`
  treatment for cold-init code.  Three .c files (`init.c`,
  `netboot_mpm.c`, `cfgtbl.c`) contain only code that runs once before
  `resident_handoff` does `OUT (0x18),A` to disable PROMs; under SDCC
  they were nevertheless landing in `RESIDENT_PRE_CODE` (RAM-resident),
  costing ~577 B of RAM persistently.

- **Triggering analysis**: a per-function size comparison done in this
  session (using `z88dk-z80nm` to distinguish function entries from
  local labels, and crediting clang's 62 B `LJTI20_0` jumptable to its
  consumer `_specc`) showed the matched-function codegen gap is
  +27 B / +2% across all matched functions — NOT the 30-50% per-function
  bloat I had been claiming since session 45.  The 1114 B whole-payload
  gap was decomposed:
    * z88dk runtime library: 28 B (2.5%) — `_memset` only
    * cold-init code in RAM (this fix): ~580 B (52%)
    * SDCC-only debug helpers + asm body diffs: ~510 B
  The user's hypothesis "library routines are the primary reason" was
  empirically false.  My prior "codegen quality is the primary reason"
  was also false.  The actual primary reason was **structural** (linker-
  script choice on where cold-init code lives), recoverable by an
  11-line Makefile change.

- **Fix** (`cpnos-rom/Makefile`, commit `1efd194` on branch
  `sdcc-resident-init-section`):
    Move `init.o`, `netboot_mpm.o`, `cfgtbl.o` from the
    `SDCC_PRE_CFLAGS` (`--codeseg RESIDENT_PRE_CODE`) variant to the
    `SDCC_INIT_CFLAGS` variant (`--codeseg INIT_CODE`).  Existing
    infrastructure: per-target Makefile CFLAGS already worked, the
    `INIT_CODE` section already existed (used by `relocator.o`),
    `check_sdcc_layout.py` already accepted INIT_CODE as a valid
    PROM0 section.  Eleven-line diff.

- **Result** (4-cell matrix all PASS, identical wall-clock):

  | metric | before | after | Δ |
  |---|---:|---:|---:|
  | Resident (RAM 0xED00..0xF7FF) | 2756 B | **2180 B** | **−577 B (−21%)** |
  | RESIDENT_PRE_CODE | 847 B | 413 B | −434 B |
  | RESIDENT_PRE_RODATA | 143 B | 0 B | −143 B |
  | INIT_CODE | 250 B | 684 B | +434 B (PROM-only, doesn't cost RAM) |
  | INIT_RODATA | 43 B | 186 B | +143 B (PROM-only) |
  | PROM0 reset+loader | 350 B | 927 B | +577 B (still ≤ 1024 B chunk-A start) |
  | Gap to clang resident | +1114 B (+68%) | **+538 B (+33%)** | gap halved |
  | SDCC pio-irq polypascal | 52.93 s PASS | 52.91 s PASS | ±20 ms |
  | SDCC sio polypascal | 60.77 s PASS | 60.79 s PASS | ±20 ms |

- **Why this works**: cold-init functions (cfgtbl_init, init_hardware,
  setup_ivt, netboot_mpm, cpnet_xact, install_fcb, reuse_fcb) execute
  ONCE during cold-boot, before resident_handoff disables the PROMs.
  They live at PROM0 0x015E..0x0386 (in the gap between PAYLOAD_HEADER
  end and chunk A start at 0x0400).  After OUT (0x18),A the PROM is
  unmapped and these bytes are gone — but they were never going to be
  called again, so we save 577 B of RAM forever.  cfgtbl's BSS variable
  (the runtime CFGTBL state NDOS reads from) stays in `bss_compiler`
  regardless: only the cold-init code/rodata moves to PROM-only.

- **Remaining gap (538 B vs clang)**: bulk is in hand-written asm
  (snios.asm body 453 B) which should be near byte-identical to clang's
  snios.s.  The other ~85 B is residual codegen + SDCC-only debug
  helpers (boot_probe 63 B, bios_log_byte 27 B, p_hex 33 B).  Filed
  follow-on issues #68 (cpnos_cold_entry to INIT_CODE, ~108 B),
  #69 (boot_probe to INIT_CODE, ~50-63 B), #70 (inline _memset, 28 B),
  #71 (re-investigate --opt-code-size now that headroom is 636 B).

- **Lesson** (added to memory rules): when comparing two compilers
  for a single project, compare TOTAL section sizes (.text + .rodata
  + .data, all loaded sections) — not per-function `.text` sizes.
  `llvm-nm --print-size` reports `.text` only; a switch table that
  clang offloads to `.rodata` is invisible at that granularity, but
  IS visible in the whole-payload total.  The per-function bias led
  me to claim "30-50% per-function gap" for many sessions; the truth
  was 2%.

- **Branch state**: `sdcc-resident-init-section` (rc700-gensmedet);
  pending merge into main with `--no-ff` milestone-style commit.

## Phase 49: cpnos-rom SDCC SIO transport validated end-to-end (May 9, 2026) — Easy

- **Goal**: close issue #66 — validate `make cpnos-polypascal-test
  COMPILER=sdcc TRANSPORT=sio` PASS at HEAD.  Phase 48 left this gap
  open (only `pio-irq` was tested).

- **Diagnosis**: both compilers (clang + SDCC) failed identically
  with TRANSPORT=sio — banner reached, then 1 byte out SIO-A and
  hang.  Identical-failure-across-compilers ruled out a compiler
  bug; root cause was harness wiring.  The polypascal-test MAME
  invocation wired PIO-B to mpm-net2:4002 via `cpnet_bridge`, but
  SIO transport sends CP/NET frames out **SIO-A**, which was wired
  to a write-only file capture.  No CP/NET responder on the SIO
  side → slave blocks on first read.

- **Fix** (`cpnos-rom/Makefile`): make the polypascal-test MAME
  invocation conditional on TRANSPORT.  For TRANSPORT=sio, wire
  `-rs232a null_modem -bitb1 socket.127.0.0.1:4002` (SIO-A direct
  to mpm-net2's TCP console socket; no `-piob` slot).  TRANSPORT=
  pio-irq keeps existing wiring (PIO-B -> cpnet_bridge -> :4002,
  SIO-A -> file capture).

  mpm-net2's :4002 is a z80pack cpmsim console socket (per
  `cpmsim/conf/net_server.conf`) — a raw TCP byte pipe, identical
  semantics to the PIO `cpnet_bridge` byte pass-through.  No
  framing or BRDY-handshake-equivalent needed.

- **Result** (4-cell matrix, all PASS):

  | compiler / transport | wall clock | status |
  |---|---:|---|
  | SDCC pio-irq | 52.93 s | PASS (regression) |
  | SDCC sio     | 60.77 s | PASS (new)        |
  | clang sio    | 59.63 s | PASS (new)        |
  | clang pio-irq | (prior session, parity at ~50 s)| — |

  SDCC and clang within ~1 s on TRANSPORT=sio — full parity.

- **Closes**: ravn/rc700-gensmedet#66.  Phase 46's "FAIL — netboot
  doesn't even get one sector" comment for SIO is retroactively
  attributable to the same harness gap, not a compiler bug.

- **Lesson**: when both compilers fail identically end-to-end at
  byte-level (1 byte out, hang), suspect harness/topology before
  compiler.  This is the inverse of Phase 48's "compilers diverge
  at byte level → dump runtime data structures" rule: when they
  *agree* at byte level on a failure, the divergence is somewhere
  outside the binary.  Recorded in `feedback_compilers_agree_means_harness.md`.

## Phase 48b: cpnos-netboot harness retired (May 9, 2026) — Easy

- **Goal**: remove the dead Python netboot harness that closed
  issues #38 and #60 left behind.  All five targets that depended on
  it had been broken since Path 6 (cpnos.com base shifts) and the
  SDCC port (different cfgtbl/BIOS-JT placements); the supporting
  test scripts hardcoded pre-Path-6 addresses.

- **Removed**:
  - Files: `netboot_server.py`, `sio_b_driver.py`, `mame_boot_test.lua`,
    `mame_sub_test.lua`, `mame_acid_test.lua`, `mame_smoke_dump.lua`,
    `mame_jt_probe.lua`, `testutil/acid.c`.
  - Targets: `cpnos-mame`, `cpnos-netboot`, `cpnos-warmboot-test`,
    `cpnos-sub-test`, `conout-acid`, `cpnos-trace`, `cpnos-interactive`
    (last one had become non-functional with the Python harness retirement).
  - Vars: `NETBOOT_PORT`, `SIOB_PORT`, `SIOB_TRIGGER`, `SIOB_INJECT`,
    `Z88DK_ROOT`/`Z88DK_ZCC` (acid build).
  - `testutil/acid.com` build rule.
  - Stale `mame_smoke_dump.lua` reference in `MEMORY_MAP.md`.

- **Kept** (still in active use):
  - `mame_polypascal_test.lua` (canonical end-to-end test).
  - `mame_bios_jt_trace.lua` (BIOS-JT/SNIOS-JT diagnostic).
  - `mame_minimal_trace.lua` (Phase 48 BDOS+SNIOS-body diagnostic).
  - `mame_extended_trace.lua` (this session's exploratory probe).
  - `mame_porttap.lua` (used by smoke targets).
  - `cpnet_pio_server.py` (used by `pio-proxy-smoke`).

- **Side note**: SERVER=proxy mode (slave-side `netboot.c` legacy)
  now has no working server.  Comment in Makefile updated to point
  at issue #19 ("decide fate of legacy netboot.c / SERVER=proxy")
  for the eventual decision.

- **Verification**: `make cpnos COMPILER=clang` and `COMPILER=sdcc
  TRANSPORT=pio-irq` both build clean; `make cpnos-polypascal-test
  COMPILER=sdcc TRANSPORT=pio-irq` -> PASS (t=52.1 s, no
  regression from Phase 48).

## Phase 48: cpnos-rom SDCC pio-irq PASS — z88dk-zsdcc constant-folding bug found and worked around (May 9, 2026) — Painful

- **Goal**: close issue #60 (cpnos-rom SDCC: control-flow lost ~3.6s
  after NDOSE handoff).  Symptom: SDCC slave reaches CCP via NDOS
  COLDST then warm-boots in a tight cycle; clang under same wiring
  PASSes polypascal-test end-to-end.

- **Hypotheses ruled out before finding the cause**:
  - ISR misbehavior (audit confirmed all four ISRs save/restore
    registers correctly, end with `RETI`, IVT verified intact at
    runtime, slot 0..15 -> isr_noop, slot 2 -> isr_crt, slots 16/17
    -> kbd / pio_par as expected).
  - Memory-map overlap (cpnos.com fits exactly into 0xDD80..0xE9FF
    with IVT adjacent at 0xEA00; `__stack_top = 0xD980` consistent
    everywhere; no overlap with NDOSRL or display).
  - Calling-convention mismatch between slave's hand-written asm
    (snios.asm, hal.asm, bios_jt.asm, xport_aliases.asm) and the
    SDCC sdcccall(1) C functions -- every push/pop verified balanced
    at the callsites; `__port_out`'s callee-cleanup convention is
    matched by the caller's `push af; inc sp` pattern at every site.
  - Address handshakes (BIOS_JT_COPY @ 0xDC80, NIOS @ 0xED33, NDOSE
    @ 0xDD83, ZP[1..2] = JP 0xDC83, ZP[6..7] = JP 0xD986) all
    byte-correct under SDCC.

- **Found**: extended BIOS-JT/SNIOS/BDOS trace with a minimal tap
  set (`mame_minimal_trace.lua`) showed under SDCC: 202 BDOS calls,
  201 NDOSA dispatches, 200 NDOSE entries, **zero SNDMSG/RCVMSG**
  during the 8 s window.  Clang for comparison: 14 SNDMSG + 14
  RCVMSG + the same NTWKIN/CNFTBL pattern, 28 BDOS calls.  NDOS
  under SDCC was routing every BDOS call through local BDOS
  (cpnos.com 0xE716) instead of dispatching to SNIOS for the
  network drives.

- **Smoking gun**: dumped slave's `_cfgtbl` at runtime (SDCC: 0xEC1D
  in scratch_bss; clang: 0xF520 in resident_data).  SDCC bytes:

    `EC1D: 10 01 80 FF 81 FF 82 FF 83 FF 88 FF 89 FF 00 00`

  Each network drive's server-slave-id field (high byte of the 2-byte
  drive map entry) is 0xFF, not 0x00.  NDOS interprets server 0xFF as
  "no master" and falls through to local-disk routing.  Source code
  (`cfgtbl.c::cfgtbl_init_template`) uses `NET_DRV(letter, 0x00)` which
  per the macro definition produces `(uint16_t)0x0080`; `>> 8` of that
  is `0x00`.  Source is correct; bytes in the binary are wrong.

- **Diagnosed compiler bug**: z88dk-zsdcc 4.5.0 mis-evaluates
  `((uint16_t)0x80 >> 8) & 0xFF` to **0xFF** in const initializers.
  Likely cause: the constant folder treats the `0x80` literal as a
  signed 8-bit value (-128), promotes via sign-extension to `0xFF80`,
  arithmetic-right-shifts `>> 8` yielding `0xFF`.  Standard C says
  `0x80` is `int = 128` (positive), so `>> 8` should be `0`.  Verified
  by reading clang's `payload.elf` bytes at `_cfgtbl_init_template`:
  clang correctly emits `01 80 00 81 00 82 00 83 00 88 00 89 00`.
  Filed as **ravn/z88dk#4**.

- **Fix applied to `cfgtbl.c`**: replaced the macro-based template
  with explicit byte literals (semantics identical, sidesteps the
  buggy `>> 8` constant-folding path).  No NET_DRV macro use in the
  initializer list:

    `0x80, 0x00, 0x81, 0x00, ...`

- **Verification**:
  - `make cpnos-polypascal-test COMPILER=sdcc TRANSPORT=pio-irq` ->
    **PASS** at t=51.6 s (full PPAS PRIMES -> 29989 -> Q -> E\>).
    First time SDCC pio-irq has reached PASS.
  - `make cpnos-polypascal-test COMPILER=clang` -> **PASS** at
    t=50.3 s (no regression).

- **Causal chain (now closed)**:
  1. SDCC miscompiled `cfgtbl_init_template` -> high bytes 0xFF.
  2. cfgtbl_init LDIRed the broken template into `_cfgtbl[+1..+13]`.
  3. NDOS COLDST called SNIOS CNFTBL -> got cfgtbl pointer.
  4. NDOS read drive entries: every drive marked "network with
     server 0xFF" (no master).
  5. NDOS's drive-routing logic fell through to local BDOS.
  6. BDOS handled OPEN/READ via BIOS_JT (which routes to slave's
     `_bios_stub_ret = ret` because FDC is disabled); BDOS thinks
     read succeeded with A=0.
  7. NDOS's `load` returned A=0 -> `nwboot` jumped to `goccp` ->
     `ret` to NDOSRL where CCP "should be" -> empty memory.
  8. Wild PC eventually hit `RST 00` / `JP 0x0000` -> corrupted
     ZP[0..7] -> warm-boot cycle (NTWKBT firing every 153 ms).

- **Lessons** (added to memory + this entry):
  - Runtime memory-byte dumps are the cheapest way to find a const
    miscompile -- the bytes in the binary are the source of truth,
    not the C source that "looks right".  Took ~10 hours of
    investigating ISRs/stacks/calling conventions before checking
    the data NDOS was actually reading.
  - When two compilers diverge on the same C source, compare the
    runtime data structures the foreign code (here: cpnos.com)
    reads from each compiler's binary.  Difference there -> the
    bug.  Difference only in code paths -> harder hunt.
  - Issue trackers earn their keep: issue #60 had the right next
    step ("MAME instruction-level trace inside cpnos.com NDOS code
    in the 0xDE50..0xE01A window") in its 2026-05-08 comment.  The
    reinterpretation in this session (NTWKBT firing means
    `goccp` SUCCESS path, not warm-boot signal) flipped the search
    space and led to dumping cfgtbl directly, which exposed the
    miscompile in 5 minutes.

- **Changes**:
  - `cpnos-rom/cfgtbl.c` — explicit-byte template (workaround comment
    cites ravn/z88dk#4).
  - `cpnos-rom/mame_minimal_trace.lua` — new diagnostic script (taps
    BDOS entry + NDOSA/NDOSE/COLDST + SNDMSG/RCVMSG body addresses;
    filters by retaddr to focus on NDOS-side activity).
  - GitHub: `ravn/z88dk#4` filed (compiler bug + minimal repro).
  - GitHub: `ravn/rc700-gensmedet#60` to be closed by this commit.

- **Status**: `main` branch.  cpnos-rom SDCC pio-irq is at parity with
  clang for polypascal-test.  Still TODO: SDCC sio transport (current
  test target uses pio-irq); cleanup of the older trace artifacts
  (mame_extended_trace.lua) which were intermediate exploration tools.

## Phase 47c: clang IVT mirror + #29 plan correction (May 8, 2026 evening) — branch `session47-analysis-2026-05-08` in z80, `main` in rc700-gensmedet

- **Goal**: extend Phase 47b's structural IVT cleanup to the clang
  side and fix a wrong-headed plan that had crept into CLAUDE.md /
  timeline.md / a draft #29 doc -- "place IVT at 0xFFD0 with I=0xFF".

- **Catch**: under Z80 IM 2 the I register fixes a 256 B page; the
  CPU reads its ISR pointer from anywhere in that page determined by
  the device-supplied vector low byte.  With I=0xFF the page is
  0xFF00..0xFFFF, of which **0xFF00..0xFFCF IS on-screen character
  RAM** (display memory occupies 0xF800..0xFFCF on RC702).  Any
  spurious or misprogrammed vector with low byte < 0xD0 would jump
  to a pointer composed of screen bytes.  All pages I=0xF8..0xFF are
  similarly forbidden.  The 48 B at 0xFFD0..0xFFFF is fine as scratch
  RAM (frame counter at 0xFFFC..0xFFFF + 44 B free) but unsuitable
  as an IM 2 IVT page.  Captured as new HARD-RULE memory entry
  `project_rc702_ivt_page_constraint.md`.

- **Reached**:
  - `cpnos-rom/payload.ld` — IVT relocated from literal `__ivt_start
    = 0xF500;` (above resident, costing 36 B of resident-adjacent
    BSS slack) to a `.ivt (NOLOAD)` SECTION pinned at **0xEA00** in
    a new IVT MEMORY region.  Same page as SDCC's `bss_ivt`
    (sdcc/sections.asm:156); cross-compiler structural parity
    achieved.  The 0xEA00 page is in the 768 B gap between
    cpnos.com's tail (0xE9FF; cpnos.com is 3200 B at NDOS=0xDD80)
    and the resident region (0xED00).  No literal IVT address
    remains; `init.c::setup_ivt` derives `IVT_ADDR` from the linker
    symbol and `set_i_reg(IVT_ADDR >> 8)` produces I=0xEA.  ASSERTs
    updated: new `__cpnos_load_end <= 0xEA00` enforces clang's
    cpnos.com-vs-IVT clearance (Makefile:391 already enforced this
    for SDCC at 0xEA00; now applies symmetrically).  Net: payload
    1733 B → 1732 B; `__scratch_bss_start` 0xF524 → 0xF500 (36 B
    BSS recovered).  All 11 link-time ASSERTs pass.

  - **Functional verification** via custom Lua probe of CRT frame
    counter at 0xFFFC..0xFFFF: counter incremented 0x000000 → 0x18A
    across 8 emu seconds (~50 Hz, exactly the VRTC rate); MAME CPU
    state shows `I = 0xEA` live; PC sits in slave main loop
    (0xF305..0xF315) servicing IRQs.  This is the value-oracle the
    "no commit on lit+size alone" rule asks for: not just that
    things link clean and pass ASSERTs, but that IM 2 IRQ delivery
    actually works through the new IVT page.

  - **Doc corrections**: top-level `CLAUDE.md` item (12), this
    timeline's Phase 47 entry (lines 269-291), and a new
    `cpnos-rom/tasks/issue-29-ivt-relocation-plan.md` capturing
    actual fix vs. wrong initial plan.  Sweep of project for stale
    "0xFFD0 IVT" / "I=0xFF" references: clean (remaining 0xFFD0
    references are all legitimate -- rcbios WorkArea at 0xFFD0,
    lessons.md ORG context, status-line-26 display-row mention).

- **Tasks filed** (`tasks/todo.md` Parked):
  - `cpnos-warmboot-test` is the wrong harness for `TRANSPORT=
    pio-irq` builds (wires SIO-A but slave talks PIO-B; appeared as
    a hang during this session's verification, but baseline showed
    same symptom -- harness mismatch, not regression).
  - `mame_boot_test.lua` finish() never fires under canonical 8 s
    `cpnos-mame` -- emulation runs out before the lua's 60 s
    frame-timeout, leaving the result file empty.

- **Lessons (extracted as new memory rule via the
  feedback_extract_rules_from_time_sinks meta-rule)**:
  - `project_rc702_ivt_page_constraint.md` -- IM 2 IVT page (I*256)
    cannot overlap RC702 display memory at 0xF800..0xFFCF; pages
    I=0xF8..0xFF are forbidden.  The 0xFFD0 scratch tail looks like
    free RAM but cannot host an IVT.

  - "If you need more space, lower TPA more" (user, this session)
    is the right framing for cross-compiler resident pressure: the
    resident-vs-TPA boundary is the binding constraint, not the
    intra-resident layout.  Path 6 (Phase 47b) demonstrated this
    on SDCC; the clang IVT mirror this session validates the same
    boundary works for clang.

  - Wrong-test-harness symptom looks identical to genuine boot
    regression (banner prints, no E>).  Verify by stashing
    candidate changes and re-running -- if baseline shows the same
    symptom, the harness is wrong, not the change.  This caught
    me wasting time on `cpnos-warmboot-test` before remembering
    that pio-irq builds need `pio-irq-netboot` (memory rule
    `project_pio_irq_test_topology.md`).

## Phase 47b: Path 6 TPA shrink + SDCC slave reaches CCP (May 8, 2026) — branch `session47-cpnos-header-driven-relocator` then `session47-analysis-2026-05-08`

- **Goal**: get the SDCC `cpnos-polypascal-test` past the post-NDOS-
  handoff hang.  Slave reached netboot completion (25 sectors received,
  cpnos.com stamp printed) but never produced an `E>` prompt under
  TRANSPORT=pio-irq; clang at the same checkpoint reaches `E>` cleanly.

- **Reached**:
  - **Comparison disassembly** (`cpnos-rom/tasks/compare-clang-vs-sdcc-handoff-2026-05-08.md`):
    side-by-side analysis of resident_handoff / enter_coldst / BIOS jt /
    cfgtbl placement.  Found three candidate divergences (port-bus shape,
    IVT-at-0xEB00 stack collision, cfgtbl in BSS vs RESIDENT_DATA);
    documented two as benign, one as latent class-of-risk fix.
  - **commit `d9bbc8b`** "sdcc: __port_out mirrors port high byte;
    IVT-clobber build assert" — closes the bus-shape divergence
    (deterministic `B = port_high` before `OUT (C),A` matching clang's
    `D3 nn`); adds Makefile assert that cpnos.com size + NDOS load
    address fits below the IVT page.  Side fix: MSGADR/RETCNT moved
    from RESIDENT_DATA to bss_compiler so they don't burn 3 zero PROM
    bytes (write-before-read at every entry point makes the move safe).
  - **commit `8573a09`** "Path 6: shrink TPA 256 B to grow resident
    from 2560 to 2816 B" — the actual fix.  cpnos-build CODE_BASE
    LDE80 → LDD80 (cpnos.com 0xDE80 → 0xDD80), DATA_BASE LDA80 →
    LD980, NIOS in cpnios-shim.asm 0xEE33 → 0xED33.  cpnos-rom
    resident lower bound 0xEE00 → 0xED00 (PROM1 chunk-B cap raised
    1536 → 1792 B).  SDCC SCRATCH_BSS slid 0xEB00 → 0xEA00.
    `sdcc/reset.asm` SP moved to 0xDD80 (clear of resident, BSS-clear,
    netboot LDIR, AND IVT).  Side fix: Makefile cpnos.bin recipe pads
    the resident image to even bytes with 0xFF if z88dk produced odd
    (checksum patcher needs even input).
  - **Workspace bump `a9c9175`** (in `/Users/ravn/z80`):
    rc700-gensmedet pointer `b75b7ae` → `8573a09`, recording 19
    commits at workspace level (Phase 47 step 7 SDCC + Path 6 cluster
    + build-speed cluster + SDCC polypascal harness).

  Verification: `make cpnos-polypascal-test COMPILER=clang` PASS
  end-to-end.  `make cpnos-polypascal-test COMPILER=sdcc TRANSPORT=
  pio-irq` reaches CCP (was hanging at NDOS handoff before Path 6),
  but FAILs stage 1 because CCP receives 0x10 (Ctrl-P) bytes from
  CONIN repeatedly and prints "Ctl-P OFF" instead of `E>`.

- **Open** (analysis branch `session47-analysis-2026-05-08`):
  - **Ctrl-P flood from CONIN under SDCC pio-irq** — three suspects:
    MAME null_modem TX→RX loopback, PIO-A spurious IRQ, SIO-B FIFO
    power-on state.  Naive fix attempts (drain SIO-B FIFO at init,
    SP relocation, B=H mirror) did NOT close it.  See
    `cpnos-rom/tasks/session47-analysis-2026-05-08.md` for the full
    suspect ranking and rejected-fix log.
  - **polypascal-test driver hardcodes `clang/...` addrs lua path** —
    doesn't honour `COMPILER=sdcc`; would mis-inject keys into
    SDCC-build BSS at clang's addresses.  Not a stage-1 issue (no
    inject needed for the boot prompt) but blocks stage 2+.
  - **Makefile odd-resident-pad shell hack** — should be a z88dk
    align directive (or a relocator-side accept-odd fix).
  - **reset.asm SP moved through 4 different layouts in 2 sessions** —
    convert to `defc __stack_top = ...` derived from symbols, not a
    literal in a comment.

  Lessons:
  - "Same problem, three candidate fixes, none close it" → step back
    and instrument before proposing fix #4.
  - Resident at the byte-cap blocks debug instrumentation as a class.
    The 256 B Path 6 grow buys headroom; future SDCC work should
    target keeping ≥64 B free for probes.
  - Plan-mode-then-execute workflow caught a stale plan (the existing
    `harmonic-sleeping-spring.md` was plan #19 done; rewrote it for
    the workspace bump task).

## Phase 46: cpnos-rom SDCC port reaches NDOS handoff (May 6, 2026 evening) — branch `main` in rc700-gensmedet

- **Goal**: continue the SDCC dual-compile port (Phase 45) past the
  Makefile dispatch into actual link + runtime, push it as far as
  `cpnos-polypascal-test` passes.

- **Reached**: SDCC build boots cleanly, netboots cpnos.com (25 of
  25 sectors), disables PROM, hands control to NDOS COLDST.  Boot
  marks `I PNILOREC+P J` confirm every cold-init phase.  NDOS coldst
  runs (NTWKIN, tlbios, CNFTBL all return correctly), nwboot starts
  CCP.SPR load via `call load`.  **(Medium-Hard)** — required eight
  bring-up bug fixes catalogued in `cpnos-rom/tasks/sdcc-port.md`
  "Bugs fixed this session".

- **Two `JP 0` cascades found and squashed**:
  (a) **NIOS placement** — `cpnos-build/src/cpnios-shim.asm` hardcodes
  `NIOS = 0xEE33`.  Initial SDCC layout had BIOS jt at 0xF200 → SNIOS
  jt at 0xF233, so NDOS's `call nios+0` jumped into uninitialised
  resident bytes.  Fixed by relocating `RESIDENT_JUMPTABLE` to
  `org 0xEE00` so SNIOS jt naturally lands at 0xEE33.  **(Easy once
  spotted)** — symptom was 22-of-25 dot stall; root cause needed
  symbol-table inspection.
  (b) **`_bios_stub_ret` mis-placement** — SDCC link of
  `void f(void){}` placed it in z88dk's `code_l_sccz80` runtime
  section at 0xEDF4, OUTSIDE the prom_loader's LDIR target range
  (0xEE00..0xF7FF).  Every NDOS call to an unimplemented BIOS entry
  (LIST/PUNCH/SELDSK/READ/...) jumped into uninit RAM → garbage
  execution → eventual JP 0 → ZP[0]=0xC3 → JP WBOOT → impl_wboot →
  re-COLDST.  Classic warm-boot loop, exactly the user's "JP 0"
  hypothesis.  Fixed by defining the symbol directly in
  `sdcc/bios_jt.asm SECTION RESIDENT_CODE` (NOT in
  RESIDENT_JUMPTABLE — would shift SNIOS jt off 0xEE33).
  **(Painful)** — required gdbstub probing of stack contents at
  hang to spot the 0x00 0x00 return addresses; symptom was
  silent post-handoff hang.

- **`cpnos-build` Path 4 — CODE_BASE shift**: cpnos.com originally
  loaded 0xE180..0xEE00 (3200 B); SDCC's larger BSS at 0xEC00
  collided with cpnos.com sectors 22+, killing
  `_cfgtbl.netst.ACTIVE` mid-netboot.  Shifted `CODE_BASE` LE180
  → LDF80, `DATA_BASE` DDD80 → DDB80 — cpnos.com now ends at
  0xEC00, leaves 0xEC00..0xEDFF for slave BSS.  TPA 56→55 KB.
  Both compilers re-tested at new address; clang reaches `E>`
  prompt cleanly.  Long-term fix tracked as relocatable cpnos.SPR
  refactor (`cpnos-rom/cpnos-build/RELOCATABLE_SPR.md` option a,
  task #11).  **(Medium)** — requires rebuilding cpnos.com (DRI
  RMAC+LINK via VirtualCpm), regenerating `cpnos_addrs.h`,
  re-testing both compiler builds.

- **Phase 2D `zp_init_data`**: `cpnos_main.c::resident_handoff`'s
  LDIR was `#ifdef __clang__`-gated with a no-op `else`; ZP[0..7]
  was never written under SDCC, so NDOS's WBOOT calls jumped via
  uninit ZP.  Replaced with `ASM_VOLATILE("ld hl,_zp_init_data;
  ld de,0; ld bc,8; ldir")`.  **(Easy)** — straightforward port;
  `resident.c::insert_line` LDDR still TODO (task #17).

- **Diagnostic infrastructure landed**: MAME's gdbstub (`-debugger
  gdbstub -debugger_port 23946`) confirmed working without a debug
  build; Python probe at `/tmp/gdb_probe.py` reads memory + dumps
  registers/stack at break.  Bitbanger TCP proxy at
  `/tmp/cpnet_proxy.py` logs every byte slave↔master with timestamps.
  Both used heavily this session to localise the JP-0 sources.
  **(Useful for future debugging)** — tools should be promoted out
  of /tmp.

- **Open**: SDCC build still hangs post-handoff with stack
  corruption — more JP-0 paths suspected (task #13).  Polypascal
  test cannot run for either compiler until MAME_IRQ branch built
  (task #15) and test harness adapted for SDCC's symbol extraction
  (task #16).  Resident.c insert_line LDDR still gated (task #17).

- **Phase 2F — link-time audit landed (closes task #14)**: hard
  build gate `tasks/scripts/check_sdcc_layout.py` added to the
  SDCC `cpnos.cim` recipe.  Parses `cpnos.map`, walks every `addr`
  symbol and every `__SECTION_head/size/tail`, fails the build
  if a `code_*`/`rodata_*`/`data_*` symbol resolves outside
  0xEE00..0xF7FF, a `bss_*` symbol resolves outside 0xEC00..0xEDFF,
  or any two non-zero-size sections overlap.  On its first run it
  caught a NEW outside-resident symbol — `_memset @ 0xEDF1` (with
  `code_string` overlapping RESIDENT_JUMPTABLE at 0xEE00..0xEE0D),
  meaning every `__builtin_memset` in resident.c (`clear_screen`,
  `scroll_up`, `erase_to_eol/eos`, `insert/delete_line`) was a
  dormant JP-0 source independent of #8 above.  Fix in `sections.asm`:
  pin every z88dk runtime section explicitly inside its proper chain
  (`code_clib` / `code_string` / `code_l_sccz80` / `code_home` /
  `code_crt_init` / `code_compiler` at end of resident chain;
  `rodata_*` / `data_*` aliases right after RESIDENT_RODATA;
  `bss_clib` / `bss_string` after `bss_compiler`).  Audit re-runs on
  every SDCC build and is a permanent build failure on regression.
  Generalises bug #8's manual fix into a class of bugs caught
  automatically.  **(Medium)** — root cause was systemic, the fix
  is too.

- **Lessons** (in `cpnos-rom/tasks/sdcc-port.md`): (1) SDCC drops
  block-scope `extern` decls from asm output silently; declare
  cross-file at file scope.  (2) z88dk's link places runtime-lib
  sections in gaps; small `void f(void){}` functions can land
  OUTSIDE the user-controlled resident region — define stubs in
  asm or annotate placement explicitly.  (3) Build-time stack-
  mismatch / out-of-region symbol detection would catch (2)
  earlier (task #14).  (4) cpnos.com address shifts cascade
  through `cpnos_addrs.h` regeneration; rebuild both compiler
  outputs after every shift.

## Phase 45: cpnos-rom dual+triple compile port — Phase 1 + 2A (May 5-6, 2026) — branch `main` in rc700-gensmedet

- **Goal**: make `cpnos-rom` build under SDCC (z88dk-zsdcc) in
  addition to clang Z80, with both builds coexisting (deploy time
  picks one).  Scaffold for a third compiler (HiTech zc, ravn/hitech)
  in the same pass.

- **User-stated principles** (recorded as feedback memories):
  - "clarity in the c code is very important" — drives every
    compiler-dispatch decision: identical call shape across
    backends, all `#ifdef` confined to `compiler/compat.h`, no
    `#ifdef __SDCC` in business logic.
  - "z88dk has intrinsic definitions for many z80 specific code" —
    SDCC builds pull z88dk's `<intrinsic.h>` (e.g. `intrinsic_di`,
    `intrinsic_ei`, `intrinsic_im_2`); clang Z80 has matching
    `static inline` wrappers; same call shape.

- **Phase 1 — source-level dual-compile (DONE)**:
  - `hal.h` rewritten with 3-backend dispatch (`__clang__ + __z80__`,
    `__SDCC || __SCCZ80`, `__HITECH__`/`HI_TECH_C`, host fallback).
    `_port_in(p)` / `_port_out(p, v)` keep the same call shape in
    every backend.  Clang Z80 inlines via `address_space(2)`; SDCC
    declares an extern (Phase 2D will provide the asm body in
    `runtime.asm`); HiTech `#error "not yet implemented"`.
  - New `compiler/compat.h` is the keyword/macro shim: `ASM_VOLATILE`,
    `__naked` / `__sdcccall(x)` / `__interrupt(n)` / `__critical` /
    `__preserves_regs`, `STATIC_ASSERT`, `NORETURN`, `USED`,
    `NOINLINE`, `SECTION_*` (one macro per `.payload_checksum` /
    `.bss.cfgtbl` / `.init.text` / `.init.rodata` / `.resident*` /
    `.prom0_*` / `.prom1` / `.pio_rx_bss`), `CPNOS_STR(x)`
    preprocessor stringify (replaces clang's `%0` operand syntax in
    `enter_coldst` -> `jp <CPNOS_NDOSE_ADDR>`), and a uniform
    `intrinsic_di / _ei / _halt / _nop / _im_2 / _ld_i_a` API.
    Header renamed from `compiler/intrinsic.h` to `compiler/compat.h`
    so the SDCC `#include <intrinsic.h>` reaches z88dk's system
    header rather than recursing.
  - `tasks/scripts/bin2inc.py` is the `#embed` workaround.
    SDCC has no `#embed` (not in `--std-sdcc23`).  A 25-LOC Python
    script reads `<name>.bin` and emits `<name>.inc` (comma-separated
    bytes) which both compilers `#include` inside an array
    initializer.  C source identical between compilers.  Was offered
    a 1.5-3-day SDCC patch; user chose the workaround.
  - `relocator.c` / `cfgtbl.c` / `init.c` / `netboot_mpm.c` /
    `payload_checksum.c` / `isr.c` / `resident.c` / `transport_pio.c`
    / `transport_sio.c` / `cpnos_main.c` all rewritten to use
    `compiler/compat.h` vocabulary.  Numeric local labels
    (`8:`/`jr nz, 8f`) replaced with globally-unique labels
    (`_isr_crt_count_done`).  Naked-keyword positioned after
    declarator (`void f(void) __naked`) for cross-compiler parity.
    All 10 .c files compile clean under both clang Z80 and SDCC `-S`.
  - Clang Z80 build remains byte-stable through the entire port:
    payload **1738 B**, PROM0 **1778 non-padding B** — same as
    before the port started.

- **Phase 2A — Makefile dispatch (DONE)**:
  - `make cpnos COMPILER=clang|sdcc|hitech` selects the build path.
  - `BUILDDIR = $(COMPILER)` parameterizes 96 hardcoded `clang/`
    paths.  Clang path byte-stable; SDCC path reaches the assembler
    and stops at the first `.s` file (Phase 2C); HiTech path
    `$(error not yet implemented)`.
  - Per-compiler tool/flag block: clang uses ld.lld + llvm-objcopy;
    SDCC uses `+z80 -compiler=sdcc -clib=sdcc_iy --no-crt
    -Cs"--std-sdcc23" -Cs"--sdcccall 1"`; native zcc preferred,
    Docker (`z88dk:2.4`) fallback retained.

- **Phase 2 remaining (NOT DONE)**:
  - **2B linker layout**: `cpnos_rom.ld` (4 memory regions
    PROM0/PROM1/RESIDENT/SCRATCH, 6 ASSERTs) → z88dk
    `sdcc/sections.asm` + `appmake +rom`.  rcbios pattern
    (`rcbios-in-c/sdcc/z88dk_section_layout.asm`) is the reference;
    cpnos has 4 regions vs rcbios's 2 so it's harder.
  - **2C asm files**: parallel `.asm` files per SDCC for `reset.s`,
    `runtime.s`, `bios_jt.s`, `snios.s`.  Direct semantic translation;
    different syntax.
  - **2D LDDR/LDIR helpers**: replace the two
    `#if defined(__clang__) && defined(__z80__)` gates around inline
    asm (`resident.c::insert_line`, `cpnos_main.c::resident_handoff`)
    with calls to a shared `mem_copy_forward` / `mem_copy_backwards`
    helper hosted in per-compiler runtime.{s,asm}.  Tried
    `__builtin_memmove` first — it inflates the clang Z80 payload
    past the budget (causes `IVT overlaps .payload` link error);
    reverted.
  - **2E validation**: run `cpnos-polypascal-test` against the SDCC
    build; confirm functional parity with clang.

- **Realistic remaining**: 8-14 hours focused work to a SDCC PROM
  that boots through cpnos-polypascal-test.

- **Lessons (session 45)**:
  - **Header naming clash bites silently**.  My initial
    `compiler/intrinsic.h` name caused `#include <intrinsic.h>`
    inside that file to recurse into itself instead of finding
    z88dk's system intrinsic.h.  Renamed to `compiler/compat.h`.
    Lesson: when bridging to a system header by the same canonical
    name, do not reuse the name — even with header guards, the
    include just becomes a no-op.
  - **`__builtin_memmove` is not a free portability fallback on
    Z80**.  Looks like the right choice for "let the compiler emit
    LDIR/LDDR per direction"; in practice clang's memmove dispatch
    grew the payload by enough bytes to break the section layout.
    Always measure size cost before swapping inline asm.
  - **Parallel Edit-tool batches can drop file content silently**.
    Mid-session, 7 sequential Edits on `cpnos_main.c` issued in one
    tool batch came back with "file modified since read" errors but
    left the file at 0 bytes.  `git checkout HEAD -- cpnos_main.c`
    restored it.  Lesson for future sessions: do edits one at a time
    on the same file; verify with `wc -l` after batches.

- **Files committed in this phase** (planned, not yet done):
  - `cpnos-rom/hal.h` (3-backend dispatch)
  - `cpnos-rom/compiler/compat.h` (new shared shim)
  - `cpnos-rom/tasks/scripts/bin2inc.py` (new `#embed` workaround)
  - `cpnos-rom/Makefile` (COMPILER dispatch + 96-path parameterize)
  - 10 .c files updated to compat.h vocabulary
  - `cpnos-rom/tasks/sdcc-port.md` (scope/progress doc)
  - `compiler/MEMORY` updates (added `feedback_clarity_in_c_code.md`,
    updated `project_cpnos_clang_only.md` to reflect direction reversal)

## Phase 33: close ravn/llvm-z80#97 BC ping-pong (May 2, 2026) — branch `session-35-issue-97` in llvm-z80

- **Goal**: close #97 (BC ping-pong in rotated single-BB self-loops),
  the gate on #77a (Z80LoopRotate default-on), and measure whether
  flipping rotation default-on is now profitable.

- **Result** (final, end of session):
  - **#97** closed.  Post-RA peephole in `Z80LateOptimization.cpp`
    handles 3 pred shapes × 2 body orderings; covers param-pointer
    (`LD C,L; LD B,H`), constant-in-both (`LD HL,nn N; LD BC,nn N`),
    and constant-in-BC-only (`LD BC,nn N` rewritten to `LD HL,nn N`).
  - **#99 filed**: i16-counter sub-case of #97 (counter and pointer
    compete for HL).  XFAIL test pinned; deferred — needs regalloc-
    level swap.
  - **#100 filed**: rotation-around-CALL BSS-spill regression.
    `Z80LoopRotate` stays default off despite #97 closing.
    Measurement on 2026-05-02 with rotation forced on showed rcbios
    +33 B, cpnos-rom +4 B (e.g. `_netboot_mpm` inner banner loop
    +28 B alone).  Tracked at `tasks/followup-77a-rotation-around-
    call.md` in llvm-z80; closes #77a once a fix lands (peephole
    rewriting the spill-around-CALL shape, or a regalloc cost-model
    tweak).
  - **rcbios BIOS**: 5920 B unchanged from session 33 baseline.
  - **cpnos-rom payload**: 1708 B unchanged from session 33
    baseline.  PROM0 init code -1 B (the peephole still fires on
    Case 1 hand-written shapes even with rotation off).
  - **Z80 lit suite**: 76 PASS + 1 XFAIL → **77 PASS + 1 XFAIL**.

- **Pain points caught** (all in llvm-z80):
  - LD_HL_nn operand layout: passing `RegState::Define` plus a
    second `addReg(HL)` produced the literal `ld hl,hl` — operand 0
    is the immediate / global / MC-symbol; the def is implicit.
    **(Easy)**.
  - Symbol vs. immediate operand comparison: Case 2 matcher only
    checked `isImm()` and silently bailed on `__ivt_start`-style
    global / MC-symbol operands.  Required diffing cpnos-rom asm
    function-by-function to spot.  **(Medium)**.
  - Two body orderings (anchor-first vs. anchor-last in the loop
    block): visible only after flipping rotation default-on.
    Restructured matcher to walk three regions regardless of order.
    **(Medium)**.
  - Rotation-around-CALL spill regression: ~30 min chasing the
    +4 B mystery on cpnos-rom before realising it was a separate
    regalloc-spill-around-CALL shape, not a residual ping-pong.
    **(Medium)**.

- **Files touched**:
  - `llvm-z80/llvm/lib/Target/Z80/Z80LateOptimization.cpp` (new
    ~250-LOC peephole after the existing #84 peephole).
  - `llvm-z80/llvm/lib/Target/Z80/Z80LoopRotate.cpp` (default
    confirmed off; comment updated to document the new gate).
  - `llvm-z80/llvm/test/CodeGen/Z80/issue-97-bc-pingpong-singlebb.ll`
    (XFAIL dropped, i16 case extracted, header rewritten).
  - `llvm-z80/llvm/test/CodeGen/Z80/issue-97a-bc-pingpong-i16-counter.ll`
    (new XFAIL).
  - `llvm-z80/llvm/test/CodeGen/Z80/issue-77a-loop-rotate.ll`
    (header refreshed; RUN lines unchanged).
  - `llvm-z80/tasks/session35-summary.md` (new).
  - No source touched in `rc700-gensmedet`.

## Phase 32: llvm-z80 codegen-fix burst (May 1-2, 2026) — branch `z80-close-all-issues` in llvm-z80

- **Goal**: tighten cluster 2 (DJNZ + LDIR family) and adjacent
  pessimizations, flip the long-standing XFAIL test to PASS, and
  measure the BIOS / cpnos-rom size delta.

- **Result** (final, end of session):
  - **rcbios BIOS**: 5998 B → **5967 B** (-31 B, -0.52 %).  Smallest
    yet; 54 B below the 6021 B initial baseline.
  - **cpnos-rom payload**: 1738 B → **1730 B** (-8 B).
  - **Z80 lit suite**: 65/66 + 1 XFAIL → **73/73**, no XFAILs.
  - **GitHub issues**: 46 open at session start → **28** open at
    end (-18, including 5 newly filed, so 23 net closed).

- **Issues fixed this session (8 with code changes)**: #78, #88, #64,
  #91, #82, #76, #93, #86.  Each landed with reproducer + lit test
  + measured size delta.

- **Issues closed retrospectively (10)**: #65, #67, #68, #69, #71, #75,
  #79, #83, #84, #85, #87, #73, #80, #60, #90.  Earlier-session
  fixes that hadn't been closed on GitHub; verified each has a
  corresponding commit + lit test on the branch.

- **Issues filed (5)**: #91 (LDDR setup quality, fixed same session),
  #92 (nested-loop DJNZ direction reversed), #93 (constant-trip
  countdown emits count-up + carry-test; fixed same session via
  path b), #94 (sequential loops: B not re-hinted between loops),
  #95 (long-term path a -- prevent the IV rewrite at IR level).

- **Mechanism (per fix)**:
  - **#78 LDIR aftermath**: late peephole rewrites
    `LD HL,(slot); LD DE,N; ADD HL,DE; <sink>` to direct DE-reuse
    (LD H,D / LD L,E, or skip-EX, or store-DE-back), with ±1 INC/DEC
    fixup.  Order-independent matcher.  cpnos READ-SEQ inner loop
    -6 B/iter absorbed into payload alignment.
  - **#88 pattern-fill loop idiom**: new IR-level pass
    `Z80LoopIdiomFill` (both new-PM and legacy-PM entry points)
    rewrites K-byte (K∈{1,2,3,4}) constant-trip-count fill loops as
    `seed K bytes; memcpy(base+K, base, K*(N-1))`, which the backend
    lowers as `seed; LDIR`.  K=3 (jump-table / IVT shape) was
    explicitly requested.
  - **#64 memmove inline**: `G_MEMMOVE` `.libcall()` → `.custom()`
    in `Z80LegalizerInfo` with direction analysis (same pointer,
    G_PTR_ADD chains, common base).  Picks LDIR or LDDR; otherwise
    libcall.
  - **#91 LDDR setup quality**: when Size is constant, fold Size-1
    + chained G_PTR_ADDs at legalization so end-pointers collapse
    to single G_PTR_ADD(base, total).  Global-base case 22 B → 12 B.
  - **#82 BSS-spill peephole orphan-reload bug**: spill→PUSH/POP
    rewrite was missing a check for orphan loads to a different
    register pair.  Added the check; the long-standing XFAIL flips
    to PASS.
  - **#76 LD A,(HL); LD r,A → LD r,(HL)** (and symmetric store):
    direct-form is 1 B / 4 T cheaper than A-via.  Peephole rewrites
    both directions when A is dead after.  Hits CONOUT and FDC
    paths in BIOS.
  - **#93 carry-roundtrip elimination** (path b -- post-RA peephole):
    two composing peepholes — `SBC A,A; AND 1; XOR 1; RRCA; JR C`
    → `JR NC` and `LD A,r; ADD A,1; LD r,A; JR NC` → `INC r;
    JR NZ`.  11 B → 3 B per loop body for constant-trip-count
    countdowns.
  - **#86 u8 switch range-check 16→8 bit**: GISel switch lowering
    widens the discriminator to i16 BEFORE the bound check.  New
    peephole detects the 9-byte 16-bit subtract chain and rewrites
    as `CP_n; JR_C/NC` (3 B), with the carry condition flipped
    (the chain computes `limit-offset` while CP computes
    `offset-limit`).

- **Pain points caught**:
  - lit `CHECK-NOT djnz` matched the substring inside function names
    like `_call_in_body_no_djnz`.  Fixed by anchoring on whitespace.
    **(Easy)**, but caught only when writing the comprehensive DJNZ
    test.
  - cmake/ninja not on PATH on macOS; user has no brew.  Found
    CLion-bundled cmake/ninja under `/Applications/CLion.app`.
    Recorded path in user memory `reference_build_binaries.md`.
    **(Medium)** — 15 min lost.
  - SCEV's `getBackedgeTakenCount` semantics: returns body iteration
    count (= trip count), NOT trips-1, for the while-style for-loop
    shape tested.  Initial #88 pass had off-by-one CopyLen.
    **(Medium)** — caught by lit CHECK on the `LD BC,N` immediate.
  - `clang` driver caches built artifacts; the new #88 IR pass only
    fired via `llc` until clang was rebuilt too (separate
    `ninja clang` from `ninja llc`).  **(Painful)** — spent ~30 min
    wondering why `errs()` didn't print before realising clang
    binary was stale.
  - #89 LICM extern-addr investigation hit a deeper issue: the
    constant gets rematerialised INTO the loop body by the register
    coalescer before regalloc can place a hint.  Backed out the
    exploratory hint extension; documented on the issue (no commit
    this round). **(Hard)** — open follow-up.

- **Easy/Medium/Hard/Painful tags**:
  - LDIR aftermath / LD r,(HL) / memmove inlining peepholes:
    **(Easy)** — pattern matches in late-opt are well-tooled.
  - `Z80LoopIdiomFill` new IR pass with both PM hooks:
    **(Medium)** — legacy + new PM dual entry, cmake registration,
    pass-pipeline placement.
  - #93 chain matching with two distinct forms: **(Medium)**.
  - clang stale-artifact debugging: **(Painful)**.

- **Files touched** (in llvm-z80):
  `llvm/lib/Target/Z80/Z80LateOptimization.cpp`,
  `llvm/lib/Target/Z80/Z80LegalizerInfo.cpp`,
  `llvm/lib/Target/Z80/Z80LoopIdiomFill.{h,cpp}` (new),
  `llvm/lib/Target/Z80/Z80TargetMachine.cpp`,
  `llvm/lib/Target/Z80/Z80.h`,
  `llvm/lib/Target/Z80/CMakeLists.txt`,
  `llvm/lib/Transforms/InstCombine/InstCombineCalls.cpp` (#87 guard),
  9 new `llvm/test/CodeGen/Z80/*.ll` lit tests.
  No source touched in `rc700-gensmedet`; size deltas are pure
  compiler-side wins.

- **Not yet fixed** (deferred to future sessions):
  - **#92** nested-loop DJNZ direction (regalloc hint needs
    MachineLoopInfo).
  - **#93** partial: INC counter still in D, not B, so DJNZ
    doesn't fire (needs path a -- #95 -- or a count-up→countdown
    rewrite chained with B-hint).
  - **#94** sequential-loops B re-hint.
  - **#89** LICM extern-addr (deeper rematerialisation cost-model
    work).
  - **#95** long-term path a for #93 (target-aware IV rewrite
    suppression at IR level).
  - All pinned via lit tests (`djnz-comprehensive.ll` and
    per-issue files) so they're regression-locked.

## Phase 31: Init/resident split + Option β (Apr 30 - May 1, 2026) — branch `init-resident-split`

- **Goal**: shrink cpnos-rom resident RAM footprint by moving init-only
  code out of the relocated payload, then exploit the freed RAM for TPA.

- **Result**: resident 2438 B -> 1746 B (-692 B, -28 %); TPA 55 K -> 56 K
  reported.  8 commits, all green through `make integration-test`.

- **Mechanism**: `.init.text` / `.init.rodata` sections at PROM 0 0x0100,
  embedded by relocator and run in place from PROM (never copied to
  RAM).  cpnos_cold_entry split into init-phase (PROM, runs to netboot
  end) + resident_handoff (RAM, does PROM disable + NDOS coldstart).
  Option β raised cpnos.com CODE_BASE 0xDEA0 -> 0xE080, moving
  scratch_bss + IVT from 0xEB20+ up to 0xF410+ to clear the path.

- **Pain points caught (and now linker-asserted)**:
  - Initial Option β attempt left `SP=0xED00` while cpnos.com loaded
    up to 0xED00; stack pushes during `impl_conout` calls overwrote
    the loaded build stamp at 0xECE8.  Symptom: "no E> prompt".  Fix:
    moved SP to 0xF500 + added 4 layout ASSERTs in payload.ld (cpnos
    end ≤ resident base, stack top > load end, etc).  **(Hard)** —
    silent corruption, only visible by hex-dumping the SIO output.
  - First attempt to move ZP_INIT to `.init.rodata` broke NDOS COLDST
    silently (zero-page LDIR'd from PROM-shadowed RAM post-disable).
    Fix: pinned as global `zp_init_data` in `.resident.data` with
    linker ASSERT that its address is in 0xED00..0xF7FF.
    **(Painful)** — caught only by integration test, not link-time;
    ASSERT now turns the same trap into a build error.

- **Compiler issues filed during the work**:
  - ravn/llvm-z80 #88 — N×16-bit constant fill loop should lower to
    seed-and-LDIR idiom (~6-8 B per call site, hits `setup_ivt`).
  - ravn/llvm-z80 #89 — Loop-invariant 16-bit constant reloaded into
    DE every iteration despite IR-level hoist (regalloc clobbers DE
    for loop counter).  IR is clean; backend-side bug.
  - ravn/llvm-z80 #90 — `(uint8_t)(extern_addr >> 8)` byte-arg call
    routes through DE→L→H→A in 10 B instead of `ld a, high(sym); call
    fn` in 5 B.  Hits `set_i_reg(IVT_ADDR>>8)` for 5 B savings.

- **Easy/Medium/Hard/Painful tags**:
  - Tagging sources with section attrs: **(Easy)**.
  - Two-region linker script + relocator embed update: **(Medium)**.
  - Stack collision diagnosis: **(Hard)**.
  - ZP_INIT post-PROM-disable trap: **(Painful)**.

- **Files touched**: `init.c`, `cfgtbl.c`, `netboot_mpm.c`,
  `cpnos_main.c`, `reset.s`, `payload.ld`, `relocator.c`, `relocator.ld`,
  `Makefile`, `cpnos-build/Makefile`, `docs/memory_map.md`,
  `tasks/todo.md`.

## Phase 30: cpnos TPA growth (Apr 30, 2026) — Phase A + B

- **Goal**: maximize the TPA on the cpnos slave by sliding NDOS
  upward in RAM.  cpnos.com is non-relocatable and link-addressed,
  so each lift is a coordinated change to `cpnos-build/Makefile`
  CODE_BASE/DATA_BASE plus the resident BIOS layout in
  `cpnos-rom/payload.ld`.

- **Phase A (commit `6251525`)**: NDOS 0xD000 → 0xDD80 (TPA 51 K → 55 K
  reported, +1.7 KB strict).  Blockers cleaned up along the way:
  - `nos_handoff()` used to memcpy a 24 B SNIOS jump table to a fixed
    0xEA00 slot every cold boot (~16 B of code + the 24 B copy at
    0xEA00 was forced live).  Replaced by pinning the cpnet-z80 NIOS
    extern at 0xED33 (= the resident `_snios_jt` symbol) via
    `cpnos-build/src/cpnios-shim.asm` -- a build-time constant.
    `payload.ld` now asserts `_snios_jt == 0xED33` so any drift is a
    link error, not a silent runtime stomp.
  - Resident `enter_coldst()` had `jp 0xD003` hard-coded; replaced
    with inline-asm `jp %0 : "i" (CPNOS_NDOS_ADDR + 3)` so the target
    follows `cpnos.sym` automatically.
  - `nos_handoff()`'s BIOS-JT copy address (was 0xCF00 hard-coded)
    becomes parametric via `BIOS_JT_COPY_ADDR = CPNOS_NDOS_ADDR -
    0x100`.  `cpnos_addrs.h` is generated from `cpnos.sym` at PROM
    build time -- one source of truth.  **(Medium)** -- the
    individual edits were small, but each was a chase to find a
    hard-coded address that had been "fine forever" because NDOS had
    never moved.
  - cpnos.com payload-stamp: a 23-char "YYYY-MM-DD HH:MM <git>" tag
    written into the trailing 0x1A record padding by
    `cpnos-build/stamp_cpnos.py` and printed by `netboot_mpm.c` after
    EOF.  Operator can read off the screen which build of the
    monolith landed -- decoupled from the resident BIOS's banner
    stamp.  Two distinct stamps because the PROM and the cpnos.com
    are produced in separate make sub-builds.

- **Phase B (commit `a1e9ce9`)**: NDOS 0xDD80 → 0xDEA0 (+288 B, but
  `CPNOS_TPA_KB = (NDOS+0x22)/1024` rounds down to the same 55 K).
  - `_msg` (200 B netboot frame buffer) moved out of low scratch_bss
    via `__attribute__((section(".scratch_bss_hi")))` into a new
    SCRATCH_HI region in the previously-unused 0xEC24..0xECEC IVT->
    payload gap.
  - Low scratch_bss (now just `_cfgtbl` + `_kbd_ring` + smalls,
    ~218 B) shrinks to 0xEB20..0xEC00 and butts up against IVT.
    cpnos.com's record-padded file end (0xDEA0+0xC80 = 0xEB20)
    butts up against the new low scratch start with 0 B headroom.
  - Path 2 was bounded: in the 0xEA20..0xED00 budget, scratch_bss
    (418 B) + IVT (36 B) only fit if `_msg` moves out (the post-IVT
    220 B gap is the only single hole large enough to absorb 200 B
    in one piece).  Going further requires moving IVT itself or
    sliding the payload origin -- Path 3 territory, hits the brittle
    `cpbios.asm` hand-typed addresses noted in the
    `feedback_state_certainty` memory.
  - Off-by-one bug found mid-test: netboot's safety check was
    `if (dma >= 0xEB20)`, which fires on the *successful* last
    sector landing exactly at the limit.  Changed to strict `>` so
    the next iteration's READ-SEQ EOF response can still drive the
    break.  **(Painful)** -- the symptom was 25 dots then silence,
    not a test failure with a clear cause.
  - `mame_ppas_test.lua` had hard-coded `KBD_HEAD = 0xEA24` /
    `KBD_RING = 0xEA2A`; broke on the Phase B move.  Fixed by
    auto-extracting via `llvm-nm` into `clang/cpnos_ppas_addrs.lua`
    in the integration-test target.  **(Medium)** -- caught only
    because the harness sat in stage 2 timeout for 60 s; quick to
    fix once located.  Audited the rest of the cpnos-rom tree for
    similar hard-coded scratch_bss addresses -- only one stale
    *comment* in `init.c` (now fixed); no other live references.

- **Integration-test alias added** (commit `e08f963`): `make test`
  and `make integration-test` both run `cpnos-ppas-test`.  Plain
  `make` still only builds.  The PPAS regression covers transport
  + NDOS + BDOS + console + keyboard + file load + run + output
  framing, which is enough to catch any layout move that broke a
  load-time invariant.  **(Easy)** -- mechanical Makefile edit.

- **Cumulative result**: NDOS rose 0x11A0 = 4512 B over Phases A+B
  (51 K -> 55 K reported, ~55.7 K strict).  The net TPA growth on
  Phase B alone (288 B) is real but doesn't show in `STAT`-style
  reporting because of integer KB rounding.  To reach 56 K reported,
  NDOS needs to land at 0xDFDE or higher -- another ~318 B of
  layout work, which hits Path 3.

## Phase 19: PROM-oblivious payload + C23 #embed relocator (Apr 23, 2026) — branch `conout-codes`

- **Goal**: split the 2 KB PROM0 budget across both physical EPROMs
  (PROM0 0x0000..0x07FF + PROM1 0x2000..0x27FF) to fit a full RC700
  CONOUT control-code set (ported from `rcbios-in-c/bios.c:specc`),
  AND restructure the build so the payload linker has *no* knowledge
  of ROM geometry — class-of-bug elimination.

- **Before**: one ELF, `.reset`+`.init` packed into PROM0, `.resident`
  LMA'd into PROM0 tail, copied to 0xED00 at cold boot.  Switch
  jumptables emitted to `.rodata` landed in `.init` (PROM0) with
  absolute addresses baked in; after `OUT (0x18)` that RAM was
  overwritten by CCP TPA and the dispatch table JP'd to garbage.
  Root-caused during the first CONOUT refactor attempt when a new
  `switch (c)` in `specc()` triggered exactly this — serial trace
  showed banner then silence post-netboot.

- **After** — new architecture in 4 new files + a refactor:
  | File | Role |
  |---|---|
  | `payload.ld` | Links everything at VMA=LMA=0xED00 as one blob `.payload`.  No PROM regions, no AT(), no LMA tracking. |
  | `relocator.c` | C23 `#embed` of `payload_a.bin` (PROM0 tail) and `payload_b.bin` (PROM1), two `__builtin_memcpy`s into 0xED00, tail call to `cpnos_cold_entry`. |
  | `reset.s` | 3 instructions: `di; ld sp,0xED00; jp _relocate`.  Required because clang-z80 doesn't reliably honor `__attribute__((naked))` to set the stack before its own C prologue pushes. |
  | `relocator.ld` | Places `.reset` at 0x0000, C body below 0x80, `.prom0_tail` at 0x80, `.prom1` at 0x2000.  Knows about PROMs — that knowledge is *only* here. |
  | Makefile | Two-stage link: payload → `nm` extracts `_cpnos_cold_entry` → relocator linked with `--defsym` of that address.  `dd` splits `payload.bin` at byte 1920 into the two `#embed` inputs. |

- **Side effects / collapses**:
  - `cpnos_main.c`'s LMA-copy loop deleted (relocator does the copy).
  - `resident_entry` merged into `cpnos_cold_entry`; two-stage
    init/resident split was only there because of the LMA dance.
  - `.resident`/`.init` section attributes kept for minimal churn
    — the payload script just globs `.resident.*` + `.text.*` into
    `.payload`.  No jumptable-routing footgun anymore: switch
    tables and their readers are now co-located inside the payload.
  - `cpnos_rom.ld` deleted.
  - `impl_conout` gained full RC700 control-code dispatch (specc):
    CR, LF, BS, TAB, BEL, clear, home, erase-EOL/EOS, insert/delete
    line, cursor L/R/U/D, XY addressing (ctrl-F + two coord bytes).
    Excludes bg/fg (0x13/14/15) — need BGSTAR buffer we don't carry.

- **Sizes**: payload 2126 B at 0xED00.  PROM0 = 33 B relocator + 95 B
  pad + 1920 B payload_a.  PROM1 = 206 B payload_b + 1842 B pad.
  Both EPROMs actively used for the first time since Phase 18.

- **Smoke**: `make cpnet-smoke` PASS end-to-end.  Full CCP + M80
  assembly + L80 link + `sumtest.com` execution prints `CPNET OK A314`.

- **Lessons**:
  - A single switch statement was enough to trip the jumptable-
    landed-in-wrong-PROM class of bug.  Architectural fix > local
    workaround (`-fno-jump-tables` would have papered over it).
  - C23 `#embed` is the right tool for carrying a binary payload
    through a compile — it keeps the tool-flow declarative instead
    of Python-shell-string-munging.  Two `#embed`s + linker-placed
    sections is cleaner than one array + a runtime split.
  - Clang-z80 lacks `naked` + reliable `[[noreturn]]` tail calls —
    tiny asm shim for SP setup, accept `CALL` at end of `relocate`
    (payload's cold entry is marked noreturn, so the return slot
    is harmless).
  - Reserving a fixed 128 B budget for the relocator code avoids
    a chicken-and-egg (its size determines where payload_a lives,
    but payload_a's size is known only after the split).

- **Filed / TODO**:
  - #50 — Investigate why `memcpy`/`memmove` compile to large code
    at call sites (118 B for one `memmove` before inline-LDDR rewrite).
  - #51 — Clean up dead `build_loader.py`, `cpnos-loader` target.
  - #52 — Replace `EXX` in CRT/PIO ISRs with selective register
    save: slave programs can legally use shadow regs (was #48).
  - Earlier todo-laters still open: ISR-driven SIO-B RX ring (#44),
    MEMORY_MAP.md needs a Phase 19 refresh.

### Phase 19b: CONOUT acid test (Apr 23, 2026) — Medium

- **Goal**: reproducible test that exercises all 15 RC700 CONOUT
  control codes end-to-end (not just `make cpnet-smoke` which only
  touches print+CR/LF) and asserts the resulting 8275 framebuffer.
- **Shape**: `testutil/acid.c` — z88dk `+cpm` C program using
  stdlib `bdos(6, c)` (Direct Console I/O) to bypass BDOS fn 2's
  TAB-to-spaces expansion so raw control bytes reach our BIOS
  CONOUT JT.  `mame_acid_test.lua` boots the slave, waits for
  `DONE\r\n` on SIO-B, dumps 0xF800..0xFFFF, asserts 30 specific
  cells.  `make conout-acid` target wires it up — runs in ~7 s.
- **Lessons / footguns hit**:
  - BDOS fn 2 expands TAB to spaces at the BDOS layer; fn 6 is
    the right call for exercising raw BIOS CONOUT.
  - Don't pass `--sdcccall 1` to z88dk when linking against the
    default crt/stdlib — mismatch produces a working-looking
    .COM that corrupts its first BDOS call arg.
  - RC700 `start_xy` (0x06) coord bytes are ASCII-offset by `' '`
    (matches rcbios `specc`).  Sending raw binary col/row
    underflows `uint8_t` in `xy_step`, and our unrolled
    `mod SCRN_ROWS` only subtracts 3× — residual `val` ≥ 25
    makes `CELL()` write outside display RAM and corrupt the
    payload.  Fixed in acid.c by adding 32 to both coords; file
    a follow-up to either bound-check in `xy_step` or widen the
    mod-unroll to cover 0..255 input.
  - Netboot server's `_seed_sub_file` default was `slave_id=0x70`
    but our build hardcodes `RC702_SLAVEID=0x01`.  Added
    `CPNOS_SLAVEID` env var overriding the default to 0x01 so
    `cpnos-sub-test` and `conout-acid` both hit the right `$nn.SUB`.
- **Result**: `PASS: all 15 CONOUT codes verified at frame 370
  (7.4s emulated)`.  Display shows the full intended pattern —
  HELLO! at (20,5), smiley at rows 10-11, STAY/GONE preserved,
  erase_to_eol/eos regions blank.

### Phase 19c: payload size analysis + clang-z80 codegen audit (Apr 23, 2026) — Medium

Read-only pass over the payload (2126 B at 0xED00; 688 B slack before
the 0xF800 resident ceiling; PROM1 has 1842 B of pad).  Nothing
ROM- or RAM-constrained; savings below are tidiness, not unblocking.

- **Size-sorted symbol dump** (`llvm-nm --size-sort clang/payload.elf`):
  top 6 by function size are `netboot_mpm` (170), `port_init` (104),
  `specc` (101), `init_hardware` (99), `impl_conout` (97), `delete_line`
  (76).  Biggest data: `_msg` 200 B (CP/NET frame, fixed), `_cfgtbl`
  173 B (DRI layout, fixed).

- **Tier 1 savings (~95 B, mechanical)**:
  1. `scroll_up` triplicated — exists as 26 B symbol AND inlined in
     `cursor_right` (25 B tail of 52 B) AND `cursor_down` (25 B tail
     of 38 B).  `__attribute__((noinline))` reuses standalone copy.
     ~50 B.
  2. `xy_step` 3×-unrolled `mod SCRN_ROWS` — 48 of 68 B is two
     triple-subtracts for row + col.  Replacing with a clamp-on-
     overflow fixes the acid-test underflow bug AND shrinks the
     function.  ~35 B.
  3. `init_hardware` inlines a 4th copy of the scroll/clear LDIR —
     calling `clear_screen` saves ~10 B.

- **Tier 2 savings (~35 B, medium)**: impl_conout BSS spill of `c`
  (~12 B), cfgtbl_init LDIR-template for pointer fields (~10 B),
  port-init + IVT-fill 16-bit-for-small-count loops (~10-15 B).

- **Tier 3 uncertain (~40-80 B)**: specc switch + 60 B jumptable →
  hand-rolled dispatch; netboot_mpm `sframe` BSS spills.  Both
  higher-effort, unclear savings.

- **Nothing reclaimable**: `_msg`, `_cfgtbl`, `_FCB_HEAD`, and
  clang's per-switch `LJTI_*` jumptable overhead — all intrinsic.

- **Recursion check**: zero.  Call-graph is a DAG (Tarjan's on the
  disasm), no self-loops.  Deepest chain: 5 levels
  (`cpnos_cold_entry → netboot_mpm → cpnet_xact → snios_rcvmsg_c
  → transport_recv_byte`).  Two `jp (hl)` sites exist — one is the
  `specc` switch jumptable, other is the `_jump_to` CCP trampoline.
  Neither introduces cycles.  ISRs contain zero `CALL`s so they
  add nothing to stack depth when they fire.  Worst-case stack
  high-water ~14 B against SP=0xED00.

- **BSS spill attribution**: 13 B total across 6 functions
  (`delete_line` 4 B, the rest 1-2 B).  **Zero** of it is parameter
  overflow — every payload fn takes 0-2 args, well within
  sdcccall(1)'s register budget.  All 13 B is register-alloc
  spill of locals or parameters that can't stay live across a
  CALL or LDIR setup.

- **Push/pop vs BSS spill** (filed as ravn/llvm-z80#74): Z80
  `push hl`/`pop hl` is 2 B / 21 T for a spill-reload pair vs
  BSS `ld (nn),hl`/`ld hl,(nn)` at 6 B / 32 T.  Dropping
  `+static-stack` doesn't help — clang falls back to SP-relative
  alloca (10 B per spill side) which is +77 B worse across
  resident.c.  Minimal self-contained repro posted on the issue.
  Interesting: clang-z80 *does* use push/pop for simple "one
  value crosses one CALL" but gives up on the multi-value
  LDIR-setup shape.

- **Tail-call peephole** (filed as ravn/llvm-z80#75): TCO exists at
  `Z80LateOptimization.cpp:2913` but is MBB-local.  Common early-
  return pattern produces `CALL` in one MBB that falls through to
  a separate `RET`-only MBB — branch folding already handles the
  explicit early-return (`ret c` in-place) but misses the CALL-
  fall-through-to-RET case.  Likely pass-ordering (BranchFolding
  considers the merge before `JR_C → RET_C` drops the other
  predecessor).  Fix: run TCO peephole *after* branch folding,
  or widen it to follow the fall-through edge.

- **SDCC peephole.def vs clang**: 20+ rules in the custom
  `sdcc/peephole.def` — ALL handled by clang natively at -Oz:
  `ld a, 0 → xor a`, redundant trailing `xor a`, `out (p), a` A-
  preservation, dead `jp`/`ret` sequences, `jp X; X:` fall-
  through, `jr cond; jp` → inverted-cond consolidation.  Clang
  goes *beyond* the rules in several cases: branchless ?: (r5
  repro emits `sub 0; add ff; sbc a,a; and 1` — 7 B, zero
  branches); vectorizes 4×byte-zero into `ld hl, 0; ld (n), hl;
  ld (n+2), hl` (9 B vs SDCC's 13+ B); OUT-chain A reuse
  generalizes beyond SDCC's 2-OUT rule.  The .def file exists to
  paper over zsdcc gaps that clang doesn't have.  Nothing to
  port.

### Phase 19c follow-throughs (Apr 23, 2026) — applied

Three commits after the audit:

1. **CR inline fast-path** (`c38ff77`): `\r` (0x0D) was routing through
   the `specc()` switch jumptable (two CALLs deep); hoisting it inline
   alongside `\n` lets clang tail-merge both into the same
   `xor a; ld (curx), a` tail.  +4 B impl_conout, ~-50 T per CR,
   +7 T per printable char.
2. **CRT-ISR-deferred cursor update** (`0773f09`): `impl_conout` used
   to reprogram the 8275 cursor via 3 port OUTs per character —
   visibly flickered on fast streams.  Replaced with `cur_dirty = 1`;
   `_isr_crt` reads the flag at each VRTC and pushes curx/cury once
   per frame.  impl_conout 101→88 B, -40 T per CONOUT call, bounded
   flicker → zero.  Also trimmed two leading CR/LFs from the signon
   banner in cpbios.asm.
3. **Tier 1 shrink** (`03fbc78`): `scroll_up __attribute__((noinline))`
   (cursor_right 52→30, cursor_down 38→15), `xy_step` clamp instead
   of 3×-unrolled mod (68→50, also fixes the acid-test underflow
   bug directly instead of just dodging it in acid.c), and
   `init_hardware` calls `clear_screen` instead of inlining a 4th
   LDIR copy (99→87).  Payload .text 2126 → 2054 B (−72 B).

- Three issues filed against `ravn/llvm-z80` for codegen gaps
  surfaced during the audit (all open, no PRs yet):
  - **#74** register-alloc spills go to BSS instead of push/pop
  - **#75** `CALL; RET → JP` peephole misses on fall-through MBB
    pairs (common early-return fan-in pattern)
  - **#76** `ld a, (hl); ld r, a` not peepholed to `ld r, (hl)`

- Tier 2 (~35 B) and Tier 3 (~40-80 B) savings from the audit
  remain on the table if payload pressure returns.  Not urgent:
  760+ B slack remains below the 0xF800 resident ceiling.

### Phase 21: Tier 2 mini-pass (Apr 25, 2026) — Easy

- Investigated the audit's Tier 2 candidates.  Shipped what worked,
  filed issues for the rest.  Payload .text 2054 → 2047 B (-7 B).

- **Applied** (`init.c`):
  - `setup_ivt`: pointer-walk + 8-bit countdown loop instead of
    `for (i=0; i<18; ++i) ivt[i]=...`.  -1 B.  clang still emits a
    parallel BC pointer dance and `dec a; ld d, a; or a; jr nz`
    instead of `dec d; jr nz` — see #77.
  - `init_hardware` port-init loop: pointer-walk + 8-bit countdown,
    same shape.  Drops 16-bit DE counter for 8-bit L counter.  -7 B.
    Same flag-routing pessimism applies.

- **Tried, rejected**:
  - `cfgtbl_init` 4× sequential `cfgtbl.drive[i] = 0x80+i` →
    `__builtin_memcpy(const)`: **+19 B**.  clang refuses to inline
    LDIR for 8-byte memcpy, unrolls into a base-pointer dance.
    Worse than direct stores.
  - `impl_const` invert second `if`: 0 B.  The 12 B
    `(x != y) ? 0xFF : 0` mask chain is the same regardless of
    polarity — see #79.

- **Blocked, deferred to llvm-z80 fixes**:
  - `impl_conout` BSS spill of `c`: ~12 B, blocked on #74.
  - `netboot_mpm` `sframe` reload-after-LDIR: ~7 B, file as #78.
  - `impl_const` mask chain: ~7 B, file as #79.

- Three more issues filed against `ravn/llvm-z80` from this
  mini-pass (all open, with self-contained C reproducers):
  - **#77** 8-bit countdown loops emit `dec a; ld r, a; or a` instead
    of flag-using `dec r` (or `djnz`) — hits every countdown loop.
  - **#78** LDIR's post-state `DE = dst+count` not used; subsequent
    `dst += count` reloads from BSS.  ~10 B per occurrence.
  - **#79** `(x != y) ? 0xFF : 0` materialised as 7-instruction mask
    chain instead of 2-instruction `add a,$ff; sbc a,a`.  ~9 B per
    occurrence.

- **Verdict**: audit's "~35 B" Tier 2 estimate optimistic by ~5×.
  Real mechanical wins cap around 7 B without compiler fixes;
  rest is gated on llvm-z80.  6 issues now open against codegen.

### Phase 21b: cross-codebase codegen sweep (Apr 25, 2026) — Easy

- User asked for a wider scan: walk BIOS + autoload + CP/NOS payload
  for clang-z80 anti-patterns worth filing as enhancements against
  ravn/llvm-z80.  Three Explore agents in parallel.

- **rcbios-in-c** — clean against #74-#79.  The only oddity is the
  `push hl; pop iy; call __call_iy` indirect-call thunk used for
  `((void(*)(void))warmjp)()`; that's load-bearing for the chosen
  sdcccall(1) ABI (no native indirect-call instruction; runtime.s
  funnels through IY).  Volatile reloads in `isr_ctc_a` are
  semantically required.  No new issues.

- **autoload-in-c** — one new actionable pattern surfaced (filed
  as #80).  The mask chain in `check_sysfile` is already covered
  by #60.  Rest is clean.

- **cpnos-rom** — the deep-scan agent flagged five candidates,
  three of which are duplicates of existing issues (#60, #74) or
  semantically required.  Two genuinely new patterns are minor:
  - sequential 16-bit immediate stores to consecutive addresses
    not folded to `ld hl, K; ld (a), hl; inc hl; ld (a+2), hl;...`
    (cfgtbl_init: 4× `ld hl, $80..$83; ld (...), hl` could be
    one `ld hl` + 3 `inc hl` + 4 stores — saves ~6 B).  Not filed:
    very narrow, single-function impact.
  - tail-merge of multiple `ld de, $0; ret` early-exit paths in
    `netboot_mpm` (~3 sites).  Not filed: generic LLVM tail-merge
    territory, may be Z80 ABI-specific quirk worth investigating
    only if anyone hits it elsewhere.

- One new issue filed:
  - **#80** `ld bc, (nn)` / `ld de, (nn)` direct addressing not
    used; clang loads to HL then `ld c, l; ld b, h`.  ~1 B per
    site, mechanical fix.

- Spurious agent finding worth recording: the autoload audit
  suggested `ld (nn), (hl)` as a fold target.  **That instruction
  does not exist on Z80** — agent hallucinated.  Pattern dropped.

- 7 codegen issues open against ravn/llvm-z80 from the cpnos
  audit cycle: #74, #75, #76, #77, #78, #79, #80.

### Phase 20: drive B: as local floppy on CP/NOS (Apr 24-25, 2026) — branch `fdc-variant` — Painful

- **Goal**: give the RC702 slave a local 8" floppy as drive B:
  alongside its existing CP/NET-served drives.  Read-only initially,
  with `pip a:foo=b:bar` style file movement as the acceptance test.
- **What got built (correct, on the dead branch)**:
  - `fdc.c`/`fdc.h` — clean µPD765 primitives (init/recal/seek/sense_int/
    READ DATA + DMA ch1 setup).  Globals-based arg passing to dodge
    clang-z80's IX-frame overhead.  ~330 B.
  - `disk.c`/`disk.h` — CP/M disk layer.  rcbios's DISKDEF macro
    verbatim for byte-identical DPB derivation; `dpb_maxi_data =
    DISKDEF(15,512,2,2048,450,128,1,2)`; DPH with `xlt=NULL` so BDOS
    skips SECTRAN; xlt_maxi_side[15] real skew-4 table; impl_read
    with 128↔512 deblocking; hostbuf-aliased dirbuf saves 128 B BSS.
  - `cpbios.asm` shims (dskshim/trkshim/...) tail-calling our BIOS.
  - `cfgtbl.drive[1] = LOCAL` so NDOS's chkdsk classifies B: local.
  - BIOS_BASE relocation from 0xED00 → 0xDD00 → 0xDE00 to make
    room for the disk BSS region.
  - 8"-DSDD MFI disk-builder pipeline (`mkmfidisk.sh` +
    `bin2imd.py` 8" maxi auto-detect).
- **Wall hit**: instrumented MAME CPU-fetch trace showed
  `_bios_seldsk` and `_bios_read` get **0** fetches during
  `dir b:`.  NDOS correctly classified B: local and JP'd to BDOS,
  but BDOS never made the BIOS calls.
- **Root cause** (the deliverable): `cpnet-z80/dist/src/cpbdos.asm`
  line 1: *"diskless BDOS for CP/NOS - functions 0-12 only.  may be
  ROMable"*.  By design.  CP/NOS was a 1982 diskless-workstation
  spec — no BDOS fns 14/15/17/18/20/21/22.  Local disks need a
  different BDOS.  See `tasks/cpnos-next-steps.md` for the three
  non-session-sized fix paths (replace BDOS / port disk fns / NDOS
  bypasses BDOS).
- **Resolution**: parked.  `pip a:=b:` over CP/NET already covers
  practical file transfer.  Cherry-picked the standalone-useful
  artifacts onto main:
  - `PORT_OUTPUTS.md` (621-line bit-level OUT-byte reference).
  - `cpnos-rom/testutil/mkmfidisk.sh` + `rcbios/bin2imd.py`
    8" maxi support (any future CP/M-floppy work benefits).
  Reverted on main: fdc.c, disk.c, BIOS_BASE move, cpbios.asm
  shims, cfgtbl.drive[1]=LOCAL, fdc-acceptance target.  Branch
  `fdc-variant` preserved locally for reference.
- **Lessons**:
  - Read the asm source headers FIRST.  The "diskless BDOS" comment
    on line 1 of cpbdos.asm was the answer to the entire mystery,
    visible the whole time.  ~3 sessions of debugging in BIOS/JT/
    NDOS/cfgtbl space could have been minutes of reading.
  - RMAC 1.1 silently emits `c3 0000` for forward references >
    ~0x90 bytes (no error, no warning, just `I` prefix in the
    listing).  And RMAC 1.1 is ASCII-only — UTF-8 em-dashes/
    arrows in comments break the parser silently.  Two foot-guns
    worth a comment in `tasks/cpnos-next-steps.md` for any future
    cpnos-build edit.
  - clang-z80's `--gc-sections` is good — fdc.c/disk.c never made
    it into the live payload bytes despite being compiled and
    linked, because nothing called them.  Made the experiment
    cheap to keep around (no PROM cost) and clean to revert.

### Phase 22: CP/NET fast-link design — Option P pinned (Apr 25, 2026) — Easy

- **Goal**: pick a host<->RC702 transport that beats the current 38400-
  baud async path (~3.8 KB/s) for CP/NET + CP/NOS traffic, without PCB
  modifications, while leaving the machine "usable normally" — physical
  RC722 keyboard plugged into J4, both SIOs free for terminal/printer.

- **Design phase only.** User does not have Pi 4B / 3B host hardware on
  hand and explicitly asked for design artifacts only — no Pico
  firmware, no Z80 bench tests, no MAME patches yet. Bring-up deferred
  until hardware is acquired.

- **Investigated scenarios** (using SIO and PIO ports, no J8):
  - SIO-only async tweaks — capped at 38400 baud, dead-end without mods.
  - SIO-only SDLC — TX works but RX blocked by missing DPLL + NC TxC/RxC
    pins on J1.  Asymmetric only.
  - PIO-A (J4) repurposed for fast link — ruled out by RC722-keyboard
    constraint and missing ARDY chip pin (Mode 2 impossible).
  - PIO-B half-duplex via J3 — full handshake (BSTB+BRDY both routed),
    keyboard untouched, SIOs untouched.  ~30-50 KB/s sustained.
  - Hybrid PIO-B in + SIO-A SDLC TX — ~70 KB/s response side, costs
    SIO-A.  Documented as future upgrade if response throughput needs.

- **Pinned**: Option P — PIO-B half-duplex via J3, direction-switched at
  CP/NET frame boundaries.  Design doc at `docs/cpnet_fast_link.md`.
  Hard upper bound: ~30 KB/s in, ~50 KB/s out (8-13× current).
  Production target: Pi 4B running z80pack-as-CP/NET-master natively,
  driving J3 cable through level shifter (Topology B).  Development
  iteration shape: Mac + Pico USB-CDC (Topology A), same wire protocol.

- **Languages locked**: C (clang-z80) for Z80 BIOS, Python 3 for host
  bridge, C with Pico SDK for optional Pico firmware, C++ for MAME.

- **Superseded**: `rcbios-in-c/docs/parallel_host_interface.md`
  Mode-2-on-PIO-A plan.  Deprecation banner added; previous "three
  options" / cable-shopping notes in `tasks/todo.md` rewritten.

- **Verified hardware facts** (consolidated from sessions 16/18/20-21
  and the schematic):
  - SIO-A bit clock at ÷1 = ~614 kbaud TX-direction signaling works.
    Framing layer (SDLC vs monosync) **uncertain** — earlier
    "SDLC specifically verified" claims should be treated as
    unverified bit-level signaling only.
  - PIO-A Mode 1 input + ASTB strobe works on this RC702 (`ravn/cbl923`
    Pico keyboard rig is the existence proof).
  - PIO-B (J3) is electrically symmetric to PIO-A but has never been
    bench-tested — first bring-up step when hardware arrives.

- **Memory pinned**: project goal "fast link is CP/NET-only", "physical
  RC722 keyboard remains attached", "Pi as production sidecar (Pi
  hardware not yet acquired)" all recorded in user memory so future
  sessions inherit the constraints without re-deriving them.

- **Decision rationale formalised** (later in same day, after the
  initial design pin): user requested a thorough report in the project
  on the Option-P decision and why the alternatives were rejected.
  Added a "Decision rationale" section at the top of
  `docs/cpnet_fast_link.md` with: priority-ordered constraint list,
  full options-considered matrix (P, H, H', Mode-2, K, A1-A4, B/C
  variants, Y-cable, keyboard-relocation, J8), per-option rejection
  analysis, and an explicit "Long-term: full-speed SIO TX comparison"
  subsection capturing the user's plan to ship P, bench it, then
  build an H prototype to determine empirically whether the response-
  side throughput improvement justifies H's costs.  Existing "Option H
  alternative / future upgrade" subsection retitled "long-term
  comparison target" to match.

- **MAME side implemented** (2026-04-25, follow-on to design):
  branches `ravn/mame:cpnet-fast-link` (slot device + bridge card)
  and `ravn/rc700-gensmedet:cpnet-fast-link` (Z80 stub + harness).
  Three commits land the work:
  - `mame 0e6ee52260d` — `bus/rc702/pio_port/` slot infrastructure
    (modelled on Einstein userport), keyboard slot card refactor,
    `cpnet_bridge` slot card (POSIX TCP listener), `rc702.cpp`
    machine_config refactored, misleading "parallel port" comment
    dropped.  690 insertions / 27 deletions across 8 files.
  - `rc700-gensmedet bcdb181` — `cpnos-rom/init.c` PIO-B init triplet
    + IVT slot 17 routed to new `_isr_pio_par` (in `isr.s`) which
    counts received bytes into resident.c BSS variables.  ~40 byte
    PROM growth, well within budget.
  - `rc700-gensmedet a71d7c1` — `tests/cpnet_bridge/` Python+Lua
    harness that drives the host -> Z80 byte path end-to-end inside
    MAME via TCP localhost:4003 and a write-tap on the BSS counter.
    `make cpnet-mame-test` target wires it in.

  Verification done so far: `mame -validate rc702` passes,
  `-listdevices`/`-listslots` show pioa/keyboard/kbd nesting + empty
  piob, both slots accept `keyboard` and `cpnet_bridge` options,
  `make cpnos` builds clean with the new ISR.  End-to-end harness
  PASS gate is conditional on the CP/NET netboot server being up
  (z80pack-as-master on :4002) — without it the Z80 stays in the
  autoload PROM and `_isr_pio_par` never fires.

  Topology B production deployment (Pi 4B + Pi Pico) still parked
  pending hardware acquisition, per the original phase 22 scope.

- **MAME bridge design specified** (same day, post-cleanup):
  expanded the "MAME side" section of `docs/cpnet_fast_link.md` from
  a 3-bullet stub to a full design spec.  Initially scoped narrowly
  (CP/NET-specific PIO-B wiring); user redirected the same day to
  a generic-slot pattern that mirrors how MAME exposes RS-232 ports.
  Branch: `cpnet-fast-link`.

  Final shape (4 changes in `ravn/mame`), anchored after a source
  survey of upstream MAME conventions for Z80-PIO peripherals:

  - **Precedent identified**: `einstein_userport_device`
    (`src/devices/bus/einstein/userport/`) is the closest existing
    upstream pattern — a `device_single_card_slot_interface` with
    exactly the methods we want (`read()`, `write(uint8_t)`,
    `brdy_w(int)`).  Verified by source fetch.  Most other Z80-PIO
    drivers (`mz700`, `pasopia`, `kc`, `prof80`, `rt1715`)
    hardcode their peripherals.
  - **No upstream generic 8-bit + STB/RDY slot exists**.
    `centronics_device` is wrong topology (unidirectional
    Centronics-shaped); `cg_parallel_slot_device` lacks STB/RDY.
  - **Verified gap, then closed**: `z80pio_device` has no
    MODE-change callback — but neither does the physical Z80-PIO
    chip (no mode-signal pin; per-port external signals are only
    data + STB + RDY + INT, verified Zilog datasheet).  Real
    peripherals don't observe mode either — they cope by being
    fixed-mode (printer, keyboard) or by following higher-level
    protocol on the wire.  The CP/NET bridge takes the latter
    route: implements both `read()` and `write()` and lets the
    chip route events to the right one based on its current mode;
    direction state on the socket-facing side comes from CP/NET
    SCB length counting.  No port-0x13 sniff, no upstream PIO
    patch, no control-word parser in the bridge.  (Earlier draft
    had option-(a)/option-(b) hedging; closed by realising the
    bridge mirrors real hardware and doesn't need to know mode.)

  - (1) `rc702_pio_port_device` in `bus/rc702/pio_port/` — modelled
    verbatim on Einstein userport; `device_single_card_slot_interface`
    with `read()` / `write(uint8_t)` / `brdy_w(int)` interface.
    Promotable to `bus/z80pio_port/` later if it earns adoption.
  - (2) `rc702_pio_port_cards` slot-option list mirroring
    `default_rs232_devices`: `keyboard` (existing model,
    slot-ified), `cpnet_bridge` (new), open for future entries.
    No "null_pio" entry — MAME's idiom for "no default card" is
    passing `nullptr` as the slot's third argument, not a named
    no-op card.  (`null_modem` is a misleading naming
    inspiration: it actually forwards bytes to a host bytestream;
    not the same as "empty slot".)
  - (3) Refactor `rc702.cpp` to expose PIO-A and PIO-B as slots.
    Default config: PIO-A=keyboard, PIO-B=nullptr (empty slot).
    Matches today's
    behaviour exactly when no `-piob` argument given.  Drops the
    incorrect 2016 comment "Printer (PIO port B commented out)" —
    PIO-B was never the printer port (printer is on a SIO channel
    per the hardware reference and per `bios.h:185-195`).
  - (4) `rc702_cpnet_bridge_device` slot card implementing the
    `device_rc702_pio_port_interface` — talks Z80-PIO handshake on
    one side, Unix/TCP socket on the other, same wire protocol the
    Pi+Pico USB-CDC bridge will speak in production.

  Why generic-slot framing matters: lets us run any historical
  RC702 software (CP/M, COMAL, BASIC) in MAME with PIO-B simply
  empty, exactly as on real hardware.  CP/NET activation becomes
  a `-piob cpnet_bridge:localhost:4003` command-line argument,
  not a build-time wiring decision.  Steps (1)-(3) are also a
  credible upstream MAME contribution candidate; only the bridge
  peripheral (step 4) needs to stay fork-only.  Bridge is the
  first concrete bring-up step — needs only a working `ravn/mame`
  build (already maintained) and a stub `isr_pio_par` on the Z80
  side, no Pi 4B or J3 cable required.

- **Level-shifter requirement dropped** (same day, post-rationale):
  user pointed out that the existing `ravn/cbl923` Pi Pico keyboard
  rig drives the Z80 PIO directly from 3.3V GPIO without level
  shifting, and the Z80 reads it cleanly (TTL VIH min 2.0V).  Z80 PIO
  is signal-only on J3 (no +5V or +12V rail — unlike J4 which powers
  the keyboard).  Updated `docs/cpnet_fast_link.md` cable spec, host
  side, and constraint-#5 satisfaction text:  no TXS0108E / 74LVC245
  / shifter chip required;  add 470 Ω - 1 kΩ series resistor on each
  Pico-input pin to current-limit protection diodes in the
  Z80-drives-Pico direction;  Topology B switched from "Pi 4B GPIO
  direct + level shifter" to "Pi 4B + Pi Pico over USB-CDC" so one
  firmware codepath covers both dev and production.  Cable BOM is
  now 11 wires + 9 series resistors.  Open question retained:
  measure Z80 PIO VOH on this RC702 at bring-up to confirm the
  no-shifter cable holds.

### Phase 23: Option P MAME bring-up — slot infra and unwinding (Apr 26-27, 2026) — Painful

- **Goal**: implement the Option P host bridge in MAME so external
  Pi/Mac processes can plumb CP/NET frames into the Z80's PIO-B port.

- **Path 1 — slot device** (committed on `cpnet-fast-link` branch,
  merged via `588658b4327`).  Built `src/devices/bus/rc702/pio_port/`
  with `pio_port`, `keyboard`, `cpnet_bridge` cards; wired both PIO-A
  and PIO-B as `device_single_card_slot_interface` slots in
  `rc702.cpp`.  POSIX socket listener on :4003 + listener thread +
  FIFO + emu_timer + STB pulse logic.  Filed
  [ravn/mame#6](https://github.com/ravn/mame/issues/6) when
  `-piob cpnet_bridge` (or `-piob keyboard`) blocked cpnos-rom IM2
  IRQ delivery — VRTC stops firing, CRT goes black, CCP never loads.

- **Path 2 — Einstein topology** (commit `54cccdbc3af`).  PIO-A
  reverted to direct keyboard wiring, PIO-B kept as the lone slot.
  `-piob keyboard` still produced the regression.  **Falsified** the
  "two slots on one chip" hypothesis.

- **Path 3 — bypass slot, wire `cpnet_bridge_device` directly to
  chip callbacks** (devcb_write_line / std::function flavours).
  Both crashed at MAME config time
  (`device_t::config_complete + 428`) before any data flowed.
  Discarded.

- **Empty-slot regression discovered (2026-04-27)**: even with NO
  card plugged in, the bare `RC702_PIO_PORT(config, m_pio_b)` slot
  wrapper breaks cpnos-rom boot.  Hangs at `PC=0x0039` before its
  first SIO-A transmit, never sends ENQ, never reaches A>.  The
  earlier "empty slot is benign" claim on ravn/mame#6 was true only
  for autoload-PROM CP/M floppy boot, which doesn't engage PIO-B's
  IM2 IRQ vector.  cpnos-rom uses that vector for `isr_pio_par`,
  hence sensitive.  Issue title amended.

- **Path 4 — direct (no-slot) bridge** (designed in
  `docs/cpnet_pio_direct_design.md`, branch `cpnet-pio-direct`).
  Drop slot/card entirely; `m_pio->in_pb_callback().set(FUNC(rc702_state::cpnet_pb_r))`
  directly to driver methods; use MAME's `osd_file` as TCP listener
  (no POSIX socket); single emu thread via 1 ms `emu_timer`; raw byte
  logs to `/tmp/cpnet_pio_rx.bin` + `tx.bin`.  Implementation written
  + built once.  Byte-level path verified working (6 bytes from
  harness arrived in rx.bin, strobe fired, in_pb_callback returned
  the right byte) but PIO-B IRQ never delivered — chip log showed
  `IE=0 IP=1` because cpnos-rom itself wasn't booting through to its
  PIO-B init phase, the slot-infra regression masking everything.
  Implementation code lost in a stash/checkout cycle.

- **Master reverted** to `b06f303737a` "Revert merge".  Working tree
  byte-identical to `1f2d4d000db` (verified via `git diff --stat`).
  Open puzzle: a freshly-built revert binary fails cpnos-rom boot
  the same way the merge did, while the April-21 daily-use binary at
  `/Users/ravn/git/mame/regnecentralend` (built from the same SHA)
  succeeds.  Suspects: stale `.o` cache or build-flag drift.  Under
  investigation.

- **Painful** because three workarounds in a row didn't fix the
  underlying break, the empty-slot finding invalidated yesterday's
  ravn/mame#6 comment, and the direct-bridge code was lost in a
  git stash/checkout cycle and will need re-implementation.

- **What survives**:
  `docs/cpnet_pio_direct_design.md`, `docs/cpnet_slot_work_history.md`
  (this work's connective tissue), `tests/cpnet_bridge/harness.py`
  switched from mpm-net2 to `netboot_server.py`,
  `tests/cpnet_bridge/dump_logs.sh`, the ravn/mame#6 issue mirror
  `docs/mame-rc702-piob-slot-regression.md`.

### Phase 27: IRQ-driven snios-on-PIO + 3-way bench (Apr 28, 2026) — Hard

- **Goal**: fix the snios-on-PIO direct path so it actually works,
  then bench it against SIO and PIO-proxy modes.  Phase 26 left it
  failing at "INIT OKPNILOR..." stalls after 4-25 sectors, filed as
  ravn/rc700-gensmedet#56 with a "fourth race" framing.
- **Root cause** (not a race): `transport_pio_recv_byte` treated the
  byte value `0xFF` as "no byte yet" sentinel, but `0xFF` is a valid
  data byte that mpm-net2 sends throughout cpnos.com.  Sector 4 of
  cpnos.com contains 19 0xFF bytes — the first sector with any —
  matching the "stall after ~4 iterations" report.  The "intermittent"
  framing was misleading: `cpnos.com.count(0xff)` would have nailed
  it in 30 seconds.  Saved as memory
  `feedback_intermittent_is_hypothesis.md`.
  Full RCA: `tasks/session34-direct-pio-stall-rootcause.md`.
- **Fix** (architecturally correct, ~50 LoC):
  - PIO-B chip IE on (init.c).
  - 256-byte SPSC ring buffer at 0xF700 (page-aligned, in unused
    tail of PAYLOAD region).  uint8_t head/tail = free mod-256 wrap.
  - `isr_pio_par` reads `PORT_PIO_B_DATA` and pushes into ring.
  - `transport_pio_recv_byte` pops from ring with timeout.
  - `enable_interrupts()` moved before `NETBOOT()` (otherwise the
    ISR can't fire during the boot phase).
  - `cpnet_bridge::poll_tick` re-gated on `m_brdy_high && buffer_non_empty`
    (the "always strobe" workaround for the polled path's 0xFF=empty
    issue would over-strobe and overwrite m_input under the IRQ
    design).
- **MAME-side issue uncovered**: Mode 1 entry doesn't auto-raise
  BRDY (Zilog datasheet says it should, 2 cycles after mode select).
  Bridge's optimistic-init `m_brdy_high=true` self-bootstraps via
  `set_mode(OUTPUT)` callback.  Filed **ravn/mame#8**.
- **Banner reorder**: signon now prints BEFORE `NETBOOT()` so the
  screen layout is row 0 = banner, row 1 = netboot progress dots,
  row 2 = blank, row 3 = `A>`.  Wire-mode banner tag extended from
  3 chars to 7 chars (`"WWW-MMM"`); branch ships `"PIO-IRQ"`.
- **Bench results** (sumtest workload pending; netboot only here):

  | Mode | Wall median (-nothrottle) | Wall median (real-time) |
  |------|---:|---:|
  | PIO-PROXY (raw OTIR/INIR + host proxy) | 1668 ms | (not measured) |
  | PIO-IRQ direct (snios envelope on PIO) | 1874 ms | 3738 ms |

  Both 9/9 OK with strict success check (boot marker `+PSJ` AND
  clean `A>` prompt).  PROXY is ~12% faster cold-boot; IRQ-direct
  is more variable (stddev 68 ms vs 3 ms) due to per-byte ISR
  cascade vs bulk OTIR/INIR.

- **`smoke_inject.py` fix**: prompt-check now runs on recv-timeout,
  not just on data-received.  Removed the 10s nudge mechanism; it
  was injecting phantom CRs during program work and creating extra
  A> echoes.  This is the "I had to type Enter manually" report.

- **sumtest port-write done signal**: sumtest.asm now does
  `mvi a, 055h; out 080h` after printing CPNET OK.  Lua tap traps
  port 0x80 via `install_write_tap` for deterministic completion
  detection — no SIO-B byte parsing, no display memory scanning.
  (Tried port 0xFF first; that maps to 8237 DMA on rc702.cpp:175.)

- **Lessons** (saved as feedback memories):
  - Sentinel preconditions must travel with the value across use
    sites; promoting context-specific sentinels to a shared `#define`
    invites silent breakage when the precondition no longer holds.
  - "Intermittent" is a hypothesis label, not a property — falsify
    it with cheap data-content checks before chasing timing causes.

- **Issues + TODOs raised**: see `tasks/session35-irq-fix-and-bench.md`
  for the full list (Pico-side proxy port, 32-bit CRT counter mirror,
  multi-channel SNIOS investigation).

### Phase 27b: warm-boot port instrumentation (Apr 28, 2026) — Easy

- **Goal**: generic "Nth program exited" detection for harnesses
  driving multi-program workloads, without screen/SIO-B scraping.
- **Mechanism**: 4-byte OUT in `impl_wboot` (resident BIOS) writes
  0x57 to port 0x81 on every CP/M warm boot.  Companion
  `mame_porttap.lua` extends the existing port-0x80 sumtest-done tap
  with a port-0x81 wboot tap; `/tmp/cpnos_wboot.txt` carries a
  saturating counter + `emu.time()` per fire.  Catches every program
  that overwrites CCP (m80, l80, sumtest, all non-trivial transients);
  by-design misses programs that just RET back into a still-resident
  CCP — those don't warm-boot, so there's nothing to instrument.
- **End-to-end verification deferred**: netboot reported as regressed
  after Phase 27 commit (NETBOOT returns 0, `-PS` boot marker).  OUT
  mechanism itself verified by disassembly at clang/cpnos.lis +
  0xefc8: `3e 57 d3 81`.

### Phase 28: cpnos-rom payload codegen audit (Apr 29, 2026) — Easy

- **Goal**: assess whether the 2536 B cpnos-rom payload is at the
  llvm-z80 codegen ceiling, or if the gap to slot-1 (2 KB, ~488 B) is
  a compiler-fix away vs a refactor away.
- **Method**: ranked all 130 functions by size from `clang/cpnos.lis`,
  read the largest (`_netboot_mpm` 202 B, `_cpnos_cold_entry` 137 B,
  `_init_hardware` 110 B, `_specc` 101 B, `_isr_crt` 101 B,
  `_impl_conout` 88 B, `_xport_*` family) and looked for recurring
  patterns.  Built minimal repros for each new finding, verified
  against the project flags (`-Oz +static-stack -disable-lsr`).
- **Verdict**: **not at the ceiling.**  Several recurring missed
  optimizations identified.  Hand-written 8080 SNIOS asm is tight;
  the C-side functions show common gaps.
- **Filed (4 new ravn/llvm-z80 issues)**:
  - **#83** — dead `and 1` after `ld a,1` for `_Bool` store
  - **#84** — loop body backs up HL through BC unnecessarily
    (in-place writes already advance HL); plus DJNZ miss
  - **#85** — sequential consecutive-address stores not lowered to
    HL-walked `ld (hl),v / inc hl` chain
  - **#86** — switch range-check on `u8` discriminant uses 16-bit
    SUB/SBC instead of 8-bit CP
- **Comments added** to existing issues:
  - **#60** (Redundant LD A,reg) — `xor a; out; ld a,$0; out`
    instance from `_isr_crt`
  - **#18** (Known-value register copy) — constant routed
    DE→L→A in `_init_hardware`'s `set_i_reg($EC)` call
- **Already covered** by prior issues #73 (small memcpy unroll),
  #74 (BSS spill across single CALL), #78 (LDIR post-state DE/HL
  not reused) — no refile.
- **Source-side wins** independently of compiler (filed in
  tasks/todo.md): drop the vtable indirection (~38 B; build is
  already TRANSPORT-specific), gate BOOT_MARK in production
  (~30-50 B), pad LOGIN_PWD copy to 12 B to hit the LDIR
  threshold.
- **Realistic shave estimates**:
  - Source-only: ~80-100 B → ~2440 B
  - + compiler fixes: ~100-150 B → ~2300 B
  - + drop vtable: → ~2260 B
  - Closing the full ~488 B gap to slot-1 needs a console
    subsystem refactor on top.  Not yet planned.
- **Lessons**: the `+static-stack` BSS-spill policy is the single
  biggest source of waste in C-side functions; #74 (push/pop for
  short-lived spills) would be the most impactful fix.  Dense-range
  switches on u8 keys are a recurring 8-bit->16-bit promotion source.

### Phase 28e: source-side size shave + PPAS regression test + IMD pipeline doc (Apr 30, 2026) — Medium

User declared cpnos "feature complete for my purposes now" -- this
session focuses on cleanup, size, and capturing the workflow.

**TPA in banner.**  Banner now reads `RC702 CP/NOS 52K PIO-IRQ
<date> <hash>`.  The `52K` is computed at PROM build time from the
NDOS address extracted from `cpnos-build/d/cpnos.sym` (TPA top =
NDOSE = NDOS + 0x0122; TPA size = (NDOS + 0x22 - 0x100) / 1024).
Auto-updates whenever NDOS placement shifts.

**Vtable removal (-134 B).**  `cpnet_transport_t` was a remnant of
a planned runtime SIO/PIO probe that never shipped.  Replaced the
indirect dispatch with `#define cpnet_send_msg snios_sndmsg_c`
aliases in `transport.h`.  Killed `cpnet_dispatch.c`, the two
vtable structs, the `active_transport` pointer, the static
`sio_probe` stub, and the BC<->HL juggling in
`snios.s`'s `SNDMSG_DISPATCH` / `RCVMSG_DISPATCH`.  Banner uses
`TRANSPORT_NAME` literal directly -- no runtime patch from
`active_transport->name`.

**BOOT_MARK_ENABLED build flag.**  19 BOOT_MARK call sites x ~5 B
each were ~95 B that don't ship in production.  New default-1 flag
collapses the macro to `((void)0)` when set 0; dropping the marker
saves 98 B (yet better than the 30-50 B audit estimate -- clang
cleared more dead code than expected).

**LOGIN password copy (-6 B).**  `__builtin_memcpy(8)` unrolls into
4 immediate stores (~40 B); a byte for-loop runs ~16 B; the
"manual byte 0 + memcpy 7" idiom drops below clang's unroll
threshold and dispatches to the runtime `_memcpy` LDIR stub
(shared, ~3 B per call site).  Stays in plain C per project rule
"prefer C over inline asm".

**Cumulative size impact**:
  - default (MIRROR_SIOB=1): 2548 -> 2410 B (-138 B)
  - production (MIRROR_SIOB=0 BOOT_MARK_ENABLED=0): 2528 -> 2280 B (-248 B)

PROM-1 budget is 2048 B -- so default is 362 B over, production is
232 B over.  The remaining gap likely needs llvm-z80 codegen fixes
(BSS-spill across CALL is the biggest single offender).

**ravn/llvm-z80 #87 filed.**  `__builtin_memcpy(8)` unrolling at
`-Oz` is a `MaxStoresPerMemcpyOptSize` setting too high for Z80 --
on this target the "inline stores" branch is much larger than the
"call shared LDIR stub" branch.  Threshold of ~1 byte would
recover ~50-80 B project-wide on top of this session's work.

**`make cpnos-ppas-test` regression.**  End-to-end driver:
  `E>` -> `PPAS<CR>` -> `>>` -> `L PRIMES<CR>` -> `>>` -> `R<CR>`
  -> wait for "29989" in SIO-B mirror -> `>>` -> `Q<CR>` -> `E>`.
Wall-clock ~50 s.  Direct kbd_ring injection (MAME's
natural-keyboard layer doesn't fully wire to the RC702 driver).
Critical lesson: split the keystroke feed at `>>` boundaries --
queueing "L PRIMES<CR>" during PPAS's CP/NET load of PPAS.ERM
caused the leading 'L' to be dropped (some part of the load path
flushes the input ring).

**`docs/imd_to_mpm.md`.**  Captures the IMD -> cpmsim recipe used
this session for PolyPascal v3.10: imd2raw parser + sector skew +
EXM=1 extent semantics + per-disk diskdef table + the bounce-mpm
step.  Generic enough to extract any RC700 5.25" mini disk.

**Open follow-ups.**
- ravn/llvm-z80 #87 (memcpy threshold) — would unlock another
  ~50-80 B of free shrinkage.
- "Rewrite ISRs in C with __attribute__((interrupt)) + port vars"
  (todo.md, parked).  All prereqs verified working today.
- "Replace or re-install WS for cpnos" (todo.md, parked from
  Phase 28d) -- not blocking, but would let the WS-on-E: tree
  actually be usable.
- "NDOS into the PROMs" (todo.md, parked) -- collapses cold-boot
  netboot from ~4 KB to ~2 KB.
- 18 commits ahead of origin/main + 1 commit ahead in z80pack
  submodule, awaiting an explicit `git push`.

### Phase 28d: WS 3.x from rc703-div-bios-typer is unusable as-is (Apr 30, 2026) — Easy

- **Symptom**: `WS PRIMES.PAS`; load works; opening the help-level menu (`^J H 2`) consistently corrupts the cpnos slave -- screen freezes / shows garbage / cury+curx clobbered to 0x20, frame counter at 0xFFFC..0xFFFF gets overwritten with spaces.
- **Root cause** (verified by Lua probe + state dumps): the `ws.com` we lifted from `rc703-div-bios-typer/` was installed for a memory-mapped screen layout that differs from our cpnos slave's.  WS does direct memory writes (not BIOS CONOUT) to its configured screen base; that base + size assumption overlaps both our scratch BSS at `0xEAxx` (cury/curx/kbd_ring/cfgtbl) and the resident BIOS frame counter at `0xFFFC..0xFFFF`.  Each WS status redraw fills 48+ bytes past `0xFFCF` plus stomps low BSS.
- **Why PPAS works**: PolyPascal-compiled binaries use BIOS CONOUT for all screen output -- no direct memory writes -- so their 80x25 view stays inside our display range.  (PolyPascal v3 is a native Z80 compiler -- precursor to Turbo Pascal -- not a P-code interpreter, despite the term being misused in earlier notes.)
- **Not a cpnos-rom bug.**  The ISR refactor and frame-counter placement are correct against any well-installed CP/M program.  Moving the counter wouldn't help -- WS also corrupts BSS at `0xEAxx`, same root cause.
- **Action**: track the "re-install or replace WS" task in `tasks/todo.md`.  Either find a WS that uses BIOS CONOUT only (no direct video) or run WINSTALL.COM (not in our `ws/` set) to retarget the existing copy.

### Phase 28c: ISRs preserve shadow regs (PPAS no longer corrupted) (Apr 29, 2026) — Easy

- **Trigger**: extracted PolyPascal v3.10 (PPAS.COM, 28416 B) onto E:.
  Disassembly showed PPAS uses the shadow bank as persistent
  workspace — 216 `EXX` and 208 `EX AF,AF'` opcodes, with dense
  clusters in the editor / runtime dispatch.  Cpnos-rom's three IM2
  ISRs (`isr_crt`, `isr_pio_kbd`, `isr_pio_par`) bracket their bodies
  with `EX AF,AF'; EXX` / `EXX; EX AF,AF'`, which clobbers PPAS's
  shadow registers on every interrupt.  At 50 Hz CRT VRTC alone, the
  Pascal runtime state corrupts within milliseconds.
- **Investigation (clang interrupt attribute)**:
  `__attribute__((interrupt))` is fully wired in llvm-z80
  (`Z80FrameLowering.cpp`, `Z80CallLowering.cpp`,
  `Z80RegisterInfo.cpp`).  CSR list `Z80_Interrupt_CSR =
  {AF,BC,DE,HL,IX,IY}` filters down to actually-clobbered regs.  Lit
  test `llvm/test/CodeGen/Z80/interrupt.ll` shows a one-store ISR
  emits exactly `push af / ... / pop af / ei / reti`.  Cpnos build
  doesn't pass `+shadow-regs`, so the EXX-based EXX_CSR_SaveList
  isn't used today.
- **Fix**: keep the ISRs as `__attribute__((naked))` with manual asm
  (the bodies are 100% inline asm anyway), but replace `EX AF,AF';
  EXX` bracket with explicit PUSH/POP for only the registers each
  ISR actually clobbers:
  | ISR | Uses | Save set |
  |-----|------|----------|
  | `isr_crt` | A, F, HL | AF + HL (4 B) |
  | `isr_pio_kbd` | A, F, BC, DE, HL | AF + BC + DE + HL (8 B) |
  | `isr_pio_par` | A, F, DE, HL | AF + DE + HL (6 B) |
  | `isr_noop` | none | none |

  None of the ISRs touch IX/IY; all userspace shadow registers are
  preserved by definition since we never EXX.
- **Cost**: payload 2548 -> 2554 B (+6 B with MIRROR_SIOB=1, mirrors
  to 2528 -> 2534 B with mirror off).  T-states: isr_crt +26 T at
  50 Hz = 0.03% CPU; isr_pio_par +47 T per byte at 31 KB/s peak =
  ~37% of CPU during netboot bursts only (acceptable, netboot is
  one-shot).
- **Verified**: `PPAS PRIMES` runs cleanly under MAME with the new
  ISRs after extracting PPAS.COM/ERM/HLP onto E: (master I: 4 MB HD).
- **Followup TODO**: convert each ISR to a C function with
  `__attribute__((interrupt))` and inline-asm clobber lists, so the
  compiler computes the save set automatically.  Current naked form
  produces identical code; the conversion is purely an ergonomics
  win.

### Phase 28b: bigger MP/M disks; CCP boots on E:=master I: (Apr 29, 2026) — Easy

- **Goal**: stop being constrained to 256 KB 8" SS-SD floppies for
  master-side MP/M, and have the slave's first prompt land on a
  4 MB drive instead of A:.
- **Method**: master MP/M's `bnkxios-net-2.mac` already declares HD
  DPHs at drive numbers 8/9/15 (I/J/P).  No XIOS rebuild — just
  populate `disks/drive[ij].dsk` and extend the slave's CFGTBL.
  - `cpnos-rom/cfgtbl.c`: added `drive[4]=NET_DRV('I',0)`,
    `drive[5]=NET_DRV('J',0)` so slave E:/F: route to master I:/J:.
  - `cpnos-rom/cpnos_main.c`: ZP[4] = 0x04 so CCP comes up at E>
    instead of A>.  CCP.SPR LOAD path was unaffected — that uses
    `ccpfcb` (cpndos.asm) which hardcodes drive byte 1 (A:), so
    boot still pulls CCP.SPR from master A:.  Fixed an outdated
    cfgtbl.c comment that claimed CDISK drove the LOAD.
  - `z80pack/cpmsim/mpm-net2`: cp library copies of
    `mpm-net2-drive[ij].dsk` -> `disks/drive[ij].dsk` on every
    launch, with mkdskimg fallback if the library disks are
    missing.  Pre-formatted 4 MB images created via
    `mkfs.cpm -f z80pack-hd` and staged in `disks/library/`.
- **Verdict**: live-tested via PIO-IRQ netboot.  Banner +
  18-char boot strip ending in `J` (NDOS COLDST reached) +
  25 sector dots + `E>` prompt confirmed on both the SIO-B mirror
  (`/tmp/cpnos_siob.raw`) and the MAME CRT screenshot.
- **Cost**: payload 2536 -> 2548 B (+12 B for two extra
  `NET_DRV('I'/'J',0)` stores).  Still ~480 B headroom under
  PROM0+PROM1 = 4 KB.
- **Caveat**: existing pass criteria (`pio-irq-netboot`,
  `pio-irq-smoke`, `cpnet-smoke`) grep for `A>` in SIO-B; they need
  updating to match `E>`.  Smoke workloads that explicitly do
  `A:`/`B:`/`C:` etc. are unaffected since A:..D: still mount the
  same 256 KB floppies as before.

### Phase 27d: 3-way bench complete (SIO / PIO-IRQ / PIO-PROXY) (Apr 28, 2026) — Medium

- **Goal**: comparable workload bench across the three CP/NET transports
  on the same `m80 + l80 + sumtest` workload (sumtest = unrolled
  sum-of-1..1000).  Session 35 had netboot-only numbers; this is the
  first apples-to-apples workload comparison.
- **TRANSPORT= build flag** (`make cpnos TRANSPORT=sio|pio-irq|pio-proxy`):
  - snios.s calls indirect through `_xport_send_byte` /
    `_xport_recv_byte`; Makefile aliases via `ld --defsym` to the
    chip-specific primitives at link time.
  - `clang/transport_stamp` invalidates .o cache when TRANSPORT changes
    (without it, switching modes incrementally relinks stale objects).
  - Banner tag from `-DTRANSPORT_NAME='"$TRANSPORT_NAME"'` so the
    on-screen banner reflects the chosen wire.
  - For pio-proxy: `-DTRANSPORT_PROXY` triggers a different
    active_transport (`&transport_pio_vt`, raw OTIR/INIR frames),
    skips the 256 B IRQ ring at 0xF700 (transport_pio.c +
    isr.c #ifndef TRANSPORT_PROXY), preprocesses payload.ld so the
    upper-bound ASSERT relaxes to display memory at 0xF800.
- **Auto-exit**: mame_porttap.lua reads `/tmp/cpnos_smoke_inject.log`
  every periodic; on `[marker] CPNET OK found` schedules
  `manager.machine:exit()` 0.5 s later.  Without this, `make
  *-smoke` ran to `-seconds_to_run 1200` (20 minutes) on every PASS
  — masked by manual `pkill regnecentralend` between iterations.
  Saved as memory `feedback_bench_must_self_terminate`.
- **Bench results** (-nothrottle, mpm-net2 backend; smoke_inject
  step1->marker is the timed window):

  | Workload  | SIO     | PIO-IRQ          | PIO-PROXY        |
  |-----------|--------:|-----------------:|-----------------:|
  | sumtest   | 35.8 s  | 27.5 s (1.30×)   | 25.4 s (1.41×)   |
  | filecopy  | 14.8 s  |  8.4 s (**1.81×**) |  7.7 s (**2.02×**) |

  Frames-to-completion (filecopy, 32-bit CRT counter @ 50 Hz):

  | Workload  | SIO    | PIO-IRQ | PIO-PROXY |
  |-----------|-------:|--------:|----------:|
  | filecopy  | 3416   | 1883    | 1687      |

  Workload shape:
    sumtest = `m80 sumtest,=sumtest.asm` + `l80 sumtest,sumtest/n/e`
              + `sumtest` (run).  CPU-dominated; the m80 step alone
              takes ~25 s of the wall in SIO mode.
    filecopy = pre-assembled FILECOPY.COM reads SUMTEST.ASM record-by-
              record via BDOS F_READ and writes SUMTEST.CPY via F_WRITE.
              ~358 reads + ~358 writes over CP/NET — no compiler in
              the timed window.  Verify step extracts both files via
              cpmcp and byte-compares (first 45735 B identical in all
              three modes; CPY's last 89 B is record-pad).

  PIO-PROXY beats PIO-IRQ by ~8% (envelope avoidance) and SIO by
  ~30% on the CPU-bound sumtest.  On the I/O-dominated filecopy the
  parallel-transport advantage is much clearer: PIO-IRQ ~1.8×,
  PIO-PROXY ~2.0× over SIO.
- **Reproducible via**: `make {sio,pio-irq,pio-proxy}-smoke
  WORKLOAD={sumtest,filecopy}`.  Each target preflight-checks the
  cpnos build's wire-mode tag (SIO / PIO-IRQ / PIO-PRX in cpnos.bin),
  MAME tree has the bridge gate fix (`m_brdy_high` in
  cpnet_bridge.cpp), and the binary is newer than the source.
- **32-bit CRT frame counter** added to isr_crt at 0xFFFC..0xFFFF
  (50 Hz CRT VRTC), mirroring rcbios.  filecopy.com snapshots S/E
  and prints both in the FILECOPY OK marker; the verify step diffs
  them for emulation-second-precise timing immune to MAME wall-clock
  jitter.
- **NDOS Err 06, Func 10**: appears between m80 exit and l80 start
  in all three runs.  Per session 23, this is "Close Checksum Error"
  from MP/M's FCB checksum mechanism — m80 (CP/M 2.2 era, predates
  CP/NET) clobbers FCB reserved bytes between F_MAKE and F_CLOSE.
  Cosmetic in this bench (m80 still produces correct .REL output);
  same root cause as the PIPNET fix from session 23.

### Phase 27c: netboot "regression" was a test-setup mismatch (Apr 28, 2026) — Easy

- **Symptom** carried over from 27b: every netboot run today produced
  boot strip `INIT OKPNI...-PS` (LOGIN never fired), reported as a
  regression vs Phase 27's 9/9 OK.
- **Root cause**: the test entry point was wrong for this branch, not
  the code.  The irq-fix slave drives SNDMSG/RCVMSG on PIO byte
  primitives but keeps the SNIOS envelope.  Compatible host: anything
  that speaks SNIOS envelope on TCP — mpm-net2 itself does.  Setups
  tried during the burn:
  - `make cpnet-smoke`: wires only SIO-A → :4002.  Slave's PIO bytes
    go nowhere; slave doesn't use SIO-A in this branch.
  - `tests/cpnet_bridge/harness.py --mode pio-netboot`: spawns
    `cpnet_pio_server` in self-contained mode, which expects RAW SCB
    frames — protocol mismatch with envelope-on-PIO slave.  Also
    blocked at the symbol-extract step because `_pio_par_byte` /
    `_pio_par_count` were dropped by `ld.lld --gc-sections` after the
    IRQ-ring rewrite removed their writers (commit f10c99f).
  - **Correct setup** (committed in `be1059c` as `make pio-irq-netboot`):
    `-piob cpnet_bridge -bitb3 socket.127.0.0.1:4002` — MAME PIO-B
    bridge connects directly to mpm-net2's TCP port; slave envelope
    bytes flow straight through.  Boot strip `INIT OKPNILOREC+PSJ`,
    A> on SIO-B, 30 s -nothrottle.
- **Side fixes** in `be1059c`:
  - `__attribute__((used))` + explicit `KEEP(*(.bss._pio_par_*))` in
    payload.ld so the harness's symbol-extract step works.  ld.lld
    drops sections marked SHF_GNU_RETAIN regardless of `((used))`,
    needs the linker-script KEEP.
- **Lesson** (saved as `project_pio_irq_test_topology` memory):
  before assuming a regression, verify the test harness was designed
  for the slave's *current* transport configuration.  When the slave
  protocol changes (envelope on serial → envelope on PIO), every
  test entry point that wires the host needs to be re-evaluated for
  shape compatibility.

### Phase 26: PIO-to-mpm-net2 — proxy vs direct snios (Apr 27, 2026) — Hard

- **Goal**: get CP/NOS netboot working against real `mpm-net2`
  (z80pack MP/M + SERVER.RSP) over the PIO transport, not just our
  Python `netboot_server.py` responder.  Two designs compared:
  - **Proxy**: Z80 sends raw PIO SCBs; a host-side Python translator
    wraps them in the SIO ENQ/ACK/SOH/CKS/EOT envelope and forwards
    to mpm-net2 :4002.  Z80 work unchanged from Phase 25.
  - **Direct (snios on PIO)**: snios.s envelope code is left intact
    but its byte primitives are rewired from SIO chip ports to PIO
    chip ports.  No host-side proxy; MAME's PIO bridge connects
    directly to mpm-net2.  Bytes on the wire are the same envelope
    SIO would produce, just on the PIO line.
- **Proxy implementation**: extended `cpnet_pio_server.py` with a
  `--upstream HOST:PORT` flag.  `upstream_send` / `upstream_recv`
  mirror snios.s as a Python client (slave-side ENQ/ACK exchange).
  PING (FNC=0xC0) handled locally; everything else forwarded.
  End-to-end netboot against mpm-net2: **1.44 s emulated, full
  NDOS COLDST**, 60 frames, ~10 ms host wall per frame for the
  envelope round-trips.  Works robustly.
- **Direct implementation**: snios.s `_transport_send_byte` /
  `_transport_recv_byte` calls swapped for `_transport_pio_*`
  versions.  Frame-level transport_pio_vt and pio_probe deleted
  on the experiment branch (saves ~340 B payload).  cpnos_main's
  probe block dropped (always default to SIO transport vtable;
  SIO vtable's send_msg/recv_msg = snios_sndmsg_c/snios_rcvmsg_c
  which now use PIO bytes).
- **Three bugs found and patched**:
  1. **Stale-prefix byte on Mode 1→0** (transport_pio.c).  MAME's
     z80pio.cpp `set_mode(MODE_OUTPUT)` immediately fires
     `out_pb_callback(m_output)`, leaking the previous send's last
     byte before the actual data.  mpm-net2 saw a stale `05`
     between ACK and SOH, errored.  Fix: pre-load `m_output` via
     data-port write while still in Mode 1 (the chip's
     `MODE_INPUT::data_write` latches `m_output` without firing
     the callback), then flip to Mode 0 — `set_mode` then emits
     the byte we want.
  2. **PIO-B chip IRQ stealing bytes** (init.c).  Default init
     enabled chip-side IE (`0x83`); `isr_pio_par` fired on each
     byte arrival and `IN A,(0x11)` from the ISR consumed the
     byte before snios's busy-poll could see it.  LOGIN's 1-byte
     payload survived; OPEN's 37-byte payload didn't.  Fix:
     chip IE off at init (`0x83` → `0x03`).
  3. **Bridge `rdy_w` skipping strobe on empty buffer** (the
     smoking gun for OPEN; `mame:cpnet_bridge.cpp@9c2cbb4e1a9`).
     The bridge gated its strobe on `m_input_index < m_input_count`.
     When the buffer drained mid-frame and Z80 kept polling, the
     chip's `m_input` retained the last *real* byte, not 0xff.
     Each Z80 IN returned the same stale byte; snios's NETIN
     stored duplicates and accumulated wrong CKS, eventually
     bailing with retry-exhausted timeout.  Fix: drop the gate;
     always strobe on BRDY rising edge.  When buffer is empty,
     `read()` returns `0xff`; chip latches `0xff`; Z80's
     `transport_pio_recv_byte` correctly polls past the
     `0xff` sentinel.
- **Why SIO worked but PIO didn't** (the question that drove this
  whole investigation): SIO uses MAME's stock `null_modem` slot,
  which sits on `bitbanger_device` + `posix_osd_socket` directly.
  The SIO chip emulation paces bytes at the configured baud rate
  (38400 here) and reports availability via the RR0 char-available
  bit; Z80 only reads `PORT_SIO_A_DATA` when that bit is set, and
  the chip emulation never caches "the last byte" across a
  no-data window.  PIO goes through our project-specific
  `cpnet_bridge.cpp` slot; the Z80-PIO chip emulation caches
  `m_input` between strobes, exposing every quirk above.
- **Status after the three fixes**: snios-on-PIO reaches LOGIN,
  OPEN, and several READ-SEQ iterations against mpm-net2.
  Stalls intermittently after 4-25 sectors — a fourth race remains.
  Filed as **ravn/rc700-gensmedet#56**.
- **Verdict**: proxy wins for routine use (robust, 1.44 s
  end-to-end, simple).  Direct is functional but flaky;
  filed for future work.
- **Branches**: `ravn/rc700-gensmedet:pio-mpm-netboot` (commits
  `62c2b61` proxy WIP, `20d9203` snios-PIO experiment, `7a50843`
  initial comparison report, `ba9277c` init.c IE-off, `4afa036`
  deeper-investigation report).  `ravn/mame:master` (`9c2cbb4e1a9`
  rdy_w fix — landed directly to master since merged from earlier
  Phase 25 work).

### Phase 25: PIO CP/NET driver + MAME bridge to standards (Apr 27, 2026) — Medium

- **Goal**: real PIO transport in CP/NOS (not just speed-test
  scaffolding), boot-time runtime selection, full netboot over
  PIO, and figure out why MAME measured PIO as *slower* than SIO
  end-to-end despite the wire-speed bench from Phase 24 saying
  the opposite.
- **Phase A — Z80 driver + probe**:
  `cpnos-rom/transport_pio.c` rewritten as frame-level (OTIR send,
  INIR recv, no `di`/`ei` around block instructions, chip IE off
  with Z80 IFF on so CRT VRTC keeps firing).  Vtable in
  `transport.h`, `cpnet_dispatch.c` provides `active_transport` +
  `cpnet_send_msg`/`_recv_msg`.  `pio_probe()` sends 7-byte PING
  SCB, awaits PONG with bounded timeout; success → flip
  `active_transport` to PIO.  `BOOT_MARK(7,'P'/'S')` on screen
  records the choice.  `snios.s` jt SNDMSG/RCVMSG slots dispatch
  through `cpnet_send_msg` so NDOS at runtime hits whatever probe
  selected.  `netboot_mpm.c::cpnet_xact` likewise.
- **Phase B — host-side server**: `cpnos-rom/cpnet_pio_server.py`
  reads SCBs raw (no SOH envelope), strips MAME's chip-emulation
  stale-prefix byte by structure (SID at offset 2 vs 3),
  dispatches via `netboot_server.dispatch_sndmsg`.  Z80 reaches
  NDOS COLDST through 25 round-trips (LOGIN / OPEN / READ-SEQ × 25
  / CLOSE).  PASS.
- **Linker guard**: `payload.ld` ASSERT on
  `__payload_end <= 0xF800`.  Discovered while debugging blank
  boot markers — payload growth had pushed `.rodata` into display
  memory; `clear_screen()` then wiped the marker[] string.  Now
  fails at link time.
- **Performance investigation**: per-frame ~130 ms emulated /
  ~53 ms wall on host.  Profiled cpnet_pio_server:
  recv 53 ms, dispatch 0.02 ms, send 0.01 ms.  ~99.96 % of host
  time blocked in `socket.recv()`.  Tracked to MAME's own
  `cpnet_bridge.cpp:266` listener-thread `select()` with **50 ms
  timeout** — chip-side `write()` queues bytes but doesn't wake
  the listener thread, so flush latency = 50 ms wall × 2 (each
  direction).
- **MAME bridge refactor**: rewrote `cpnet_bridge.{cpp,h}` on the
  MAME-standard `BITBANGER` sub-device pattern (matches
  `null_modem`).  No private threads, no mutex, no atomics, no
  std::deque buffering.  -192 net lines.  Result: end-to-end
  CP/NOS netboot **3.82 s emulated → 0.28 s emulated (13.6×
  faster)**.  Per-frame host recv 53 ms → 0.5–3 ms wall.
- **Banner**: signon now reads `RC702 CP/NOS PIO 2026-04-27 12:58
  f6c43a4+` — transport, UTC date, HH:MM, git short hash with `+`
  on dirty tree.  `cpnos_buildinfo.h` regenerated each build via
  `.PHONY` Makefile rule with `cmp`-then-`mv` so cpnos_main.o
  rebuilds only when the date or hash actually change.
- **MAME OSD finding**: `socket.host:port` syntax means CONNECT
  (not listen) — required flipping `cpnet_pio_server.py` to be
  the listener and adding a "dummy listener" pre-spawn to the
  harness for non-PIO modes (otherwise MAME aborts at startup
  with "Connection refused" from bitbanger's first I/O).
- **Numbers (MAME -nothrottle)**:
  - PIO end-to-end: 0.28 s emulated (was 3.82 s pre-refactor).
  - SIO end-to-end: 2.08 s emulated (rate-bound at 38400 baud).
  - PIO is now **7.4× faster than SIO in MAME**, projects to
    ~40× on real hardware.
- **Branches**: `ravn/rc700-gensmedet:cpnet-pio-direct` (commits
  `46b5479…3f30d8f`); `ravn/mame:cpnet-fast-link-remerge`
  (`f9f1efdc1ce` — the bitbanger refactor).  Master/main untouched.

### Phase 24: Option P parallel-port driver + throughput bench (Apr 27, 2026) — Medium

- **Goal**: implement and measure the Option P transport over PIO-B
  end-to-end through the (now-working) `cpnet_bridge` slot card.
- **Driver**: `cpnos-rom/transport_pio.c` — Mode 0/1 lazy switching,
  32-byte RX ring, ISR push.  Two Z80-PIO chip-state quirks worked
  around explicitly:
  1. `set_mode(MODE_OUTPUT)` immediately fires `out_pX_callback` with
     stale `m_output` — leading 0x00 prefix on first Mode 1→0
     transition.  Filed as ravn/mame#7.
  2. Mode 0 STB pulses set `m_ip` even with `m_ie=false`.  Plain
     `0x83` IE-enable on Mode 1 entry causes a spurious IRQ.  Fixed
     with ICW + mask-follows (0x97 + 0x00) which atomically clears
     `m_ip`.
- **Frame round-trip**: 10-byte CP/NET-shaped SCB
  (FMT/DID/SID/FNC/SIZ + 4 payload + CKS) sent + mirrored back +
  validated on Z80 side.  PASS at 4.3s emulated.
- **Throughput bench (MAME 100% throttle, wall ≈ Z80 emulated)**:
  - TX C-loop:  22 KiB/s
  - **TX OTIR: 156 KiB/s**
  - RX ISR-driven: 15 KiB/s (lower bound; MAME emu overhead)
  - **RX INIR busy-poll: 148 KiB/s** (10× ISR; matches TX)
  Full report at `docs/cpnet_pio_speed_results.md`.
- **Compiler bug**: clang Z80 `+static-stack` miscompile of a
  `uint16_t` loop counter — held in BC for the loop test, read from
  a never-written frame slot at the call-arg use.  Filed as
  ravn/llvm-z80#82, XFAIL lit test pushed.  Workaround: nested
  `uint8_t` loops.
- **Architectural finding**: in Mode 1 input, the chip's BRDY toggle
  in `data_read` is the natural flow-control mechanism — disable IE,
  run INIR, get 21 T/byte without any IRQ overhead.  The original
  ring-based recv_byte path is unusable for sustained streaming
  (back-to-back ISRs starve mainline; ring overflows).  Filed as
  ravn/rc700-gensmedet#54.
- **Boot markers** moved to row 0 cols 60-78 (upper-right) so they
  survive the nos_handoff banner overwrite on row 1.
- **Issues filed**: ravn/llvm-z80#82, ravn/mame#7,
  ravn/rc700-gensmedet#53 (tap.lua banner check on wrong row),
  ravn/rc700-gensmedet#54 (recv_byte ring path unusable).
- **Branch**: all on `cpnet-pio-direct`; `2517ba0` is the throughput
  report.  Master/main untouched per project convention; promotion
  is a future decision.

## Phase 18: PROM shrink pass (Apr 23, 2026) — branch `snios-compact`
- **Goal**: create breathing room in the 2 KB PROM0 ceiling (11 B
  slack after #39).  Target: ≥ 200 B for future work (signature
  prefix for #46, ISR-driven SIO-B ring, etc.).
- **Analysis-first**: built a per-function size breakdown of the
  2037 B payload; cross-compared with `rcbios-in-c` patterns
  (table-driven port init, shared ISR structure, SBC A,A idioms)
  to pick high-yield / low-risk changes.  See
  `cpnos-rom/MEMORY_MAP.md` + the GH issue #47 task list.
- **Tier 1 (c54229c)**: strip all trace instrumentation added
  during Phase 16-17 — SNIOS per-FNC counter, CONOUT/CONIN/CONST
  counters, CONIN ring, netboot breadcrumbs.  **-121 B** (vs ~70 B
  predicted — the compiler compacted adjacent basic blocks after
  the bumps went).
- **Tier 2a (0dae340)**: collapse ~30 inline `_port_out` calls
  in `init_hardware` + folded-in `init_pio_kbd`/`init_display`
  into one unified `port_init[]` table + for-loop.  **-39 B**.
- **Interim (9add5ba)**: smoke_inject now sends a CR nudge after
  10 s of SIO-B silence — practical workaround for issue #44 (the
  "had to type Enter manually" annoyance) until Tier 4 gives us an
  ISR-driven SIO-B ring.  Doesn't change PROM size.
- **Current slack after 12 commits**: **524 B** (from 11 B).
  | Step | Delta | Slack |
  |---|---|---|
  | main@155cca7 baseline | — | 11 B |
  | Tier 1: strip trace code | +121 | 132 B |
  | port-init table | +39 | 171 B |
  | netboot memcpy + banner trim | +90 | 261 B |
  | impl_conout dedup + no-FF | +54 | 315 B |
  | cfgtbl → BSS (runtime init) | +130 | 445 B |
  | SNIOS RECVBT tail merge | +4 | 449 B |
  | crt_scroll_up memcpy/memset + FCB trim | +29 | 478 B |
  | zero-page + JT inline LDIR | +32 | 510 B |
  | display-clear memset + 8-byte loop fix | +14 | 524 B |
- **Filed along the way**: #47 (tracking issue), #48 (ISRs unconditionally
  EXX/EX AF,AF' — unsafe), #49 (clang elides memcpy-to-0), and
  ravn/llvm-z80#73 (8-byte inline memcpy cost model).
- **Lessons**: (a) Compiler's `-Oz` inliner can still generate
  pathological code for small memcpys — always disassemble and
  measure, don't trust the intent; (b) BSS-as-ROM-substitute for
  mostly-zero static data paid the biggest single win (130 B);
  (c) Inline `ldir` via clang-z80's +{de}/+{hl}/+{bc} constraints
  is the right tool when \_\_builtin_memcpy gets UB-elided or
  cost-modeled into a pessimal inline.
- **Lessons**: (a) kill diagnostic code with the bug it diagnosed,
  not later — it had been burning space in every boot for two
  phases; (b) when a pattern appears N times inline, a table + loop
  break-evens at N ≈ 3; (c) unify before optimising — consolidating
  init_pio_kbd + init_display into one table was a bigger win than
  any local micro-opt.


- **Goal reached 2026-04-22**: "CP/NOS on a physical RC702 against a
  live MP/M II over serial" validated in emulation — cpnet-smoke PASS
  with stock MP/M (z80pack mpm-net2) serving a slave that assembles a
  1000-iter unrolled program via M80 + L80, executes it, and prints
  the correct checksum.  Eight commits this session; closed #40 and
  #41; filed #43/#44/#45 for polish work.
- **Lessons crystallized**:
  - When the network clearly delivers correct bytes (TYPE works,
    buffer dumps match disk), stop theorizing transport bugs and
    look at *interpretation* differences (CRLF, segments, ABI).
  - BDOS return codes are *function-specific*: OPEN (fn 15) returns
    0..3 on success, 0xFF on fail — don't apply the generic
    "0 ok / non-zero error" heuristic.
  - A Lua tap on 0x0005 with per-call DMA-buffer dump is the single
    most valuable diagnostic we have for slave-side BDOS behavior.
    Kept as permanent infrastructure in mame_smoke_dump.lua.
  - Any text file destined for a CP/M disk image needs CR+LF.  Saved
    as a standing memory rule.

## Phase 17: cpnet-smoke harness + "DIR was a Python false positive" (Apr 22, 2026)
- **2026-04-22**: User asked for a non-trivial regression test that
  exercises the OS end-to-end by having the on-master assembler (M80)
  compile a computed program on the slave's behalf.  Scaffolded
  `testutil/sumtest.asm` (fully unrolled sum-of-1..1000 = 0xA314),
  `mksmokeasm.py`, `mksmokedisk.sh`, `smoke_inject.py` (prompt-aware
  SIO-B sequencer with per-char pacing), and `Makefile: cpnet-smoke`.
  Per user direction: pass oracle = what the program prints,
  not byte-exactness of artifacts — any CP/NET read/write corruption
  makes the assembler emit a wrong COM → program prints wrong
  string → test fails.  **(Medium)** — several orchestration gotchas
  (RMAC label mangling was old; new ones: M80 source extension,
  SIO-B FIFO overrun from burst-inject).
- **2026-04-22**: **Fourth fragility class discovered.**  Multiple
  recent "A>" successes — including today's DIR test against what we
  thought was MP/M — were actually served by a stray
  `python3 netboot_server.py` still listening on :4002 from an
  earlier manual test.  MAME's bitbanger bound to it instead of
  cpmsim-hosted MP/M; Python's mock CP/NET responses looked plausible
  enough to fool the test harness.  Killing the zombie Python exposed
  that real MP/M gets past LOGIN (NB_step=0x03) but OPEN returns
  rc=0x02.  **(Painful)** — had to backtrack days of work because
  the oracle was wrong.  Filed #42 for test-hygiene guard.
- **2026-04-22**: Related finding: `cpnos.com` on stock
  `mpm-net2-1.dsk` (4292 B) targets z80pack's generic slave, not our
  RC702 BIOS/SNIOS layout.  Even with MP/M serving correctly, the
  fetched image would drive wrong I/O.  `mksmokedisk.sh` now
  overwrites CPNOS.IMG with our `cpnos-build/d/cpnos.com`.
- **Remaining:** #40 — real-MP/M OPEN rc=0x02 after LOGIN.  Harness
  (#41) blocked on this.
- **2026-04-22 (post-compact)**: **#40 fix identified.**  `rc=0x02` is
  NOT an error — it's a CP/M BDOS OPEN success code.  BDOS fn 15
  returns directory code 0..3 on success (the found entry's offset
  mod 4), 0xFF on not-found.  `netboot_mpm.c` treated any non-zero
  rc as failure; changed the guard to `if (rc >= 0x04) return 0;`.
  **(Easy)** once misread — hours were burned assuming 0x02 was an
  error code before re-reading the BDOS spec.  Underscores the rule:
  when a retcode looks weird, check whether it's BDOS-passthrough
  (raw directory code) vs. CP/NET transport (normalized 0/0xFF).
- **2026-04-22 (later still)**: **cpnet-smoke PASS.**  Program
  assembled on the slave by M80+L80 over CP/NET prints
  `CPNET OK A314` — sum(1..1000) & 0xFFFF computed correctly.
  Root cause chain (not what I first thought): **M80 requires
  CR+LF line endings.**  Our generator wrote LF-only source; M80's
  line scanner couldn't recognize statement boundaries, so every
  pseudo-op including `END` read as part of a single mega-line.
  Buffer-content dump via Lua tap (reading M80's read-DMA area)
  proved the file *did* reach M80 with END in it — M80's parser
  just didn't see it without the CR.  Two secondary source-level
  bugs surfaced after that: (a) M80 defaults to relocatable, need
  explicit `ASEG` for CP/M .COM output; (b) BDOS PRINTS (fn 9)
  does not preserve HL, so the print-then-format logic needs
  PUSH/POP H around the BDOS call.  Saved `feedback_crlf_cpm_disk`
  as a standing rule.  **(Painful → Easy once found)** — seven
  rounds of "it's CP/NET extent handling" / "it's READ_SEQ return
  values" / "it's source syntax" before the buffer-dump made the
  CR-LF gap obvious.  Deep lesson: when content clearly reaches
  the target correctly, look for *interpretation* differences
  before blaming transport.
- **2026-04-22 (late)**: Netboot fix validated end-to-end — CP/NOS
  loads, banner, CCP prompt, M80 + L80 run.  But assembled program
  is empty (3-byte stub).  Built cpnet-smoke harness with TYPE +
  M80 + DIR + L80 + exec stages, a saturating uint8 counter per
  CP/NET FNC at 0xEC80..0xECFF (plus 16-bit READ_SEQ at 0xEC7E),
  and a MAME Lua tap on 0x0005 to capture the **full** BDOS call
  stream (6351 calls in a typical run).  TYPE reads the source
  perfectly — CP/NET READ is not the transport-level problem.
  zmac assembles the same source cleanly — the source is valid.
  **Hypothesis confirmed via trace analysis:** M80 issues exactly
  17 READ_SEQ calls per OPEN regardless of file size (tested with
  TINY.ASM=20B and SUMTEST.ASM=5790B).  Since TINY.ASM fits in a
  single record, 16 of those reads are past-EOF.  Implication: the
  CP/NET slave chain (SNIOS → NDOS → slave BDOS) is returning
  `rc=0` (success) for past-EOF reads instead of `rc=1` (EOF),
  so M80 never sees the EOF signal that would make it finalize
  assembly.  Next: instrument the return value (A on BDOS RET)
  to prove it, or fix the NDOS/BDOS EOF path in our cpnos.com
  build.  **(Hard)** — needed three distinct diagnostic layers
  (FNC counter, BDOS tap, trace analysis) to triangulate.

## Phase 16: First end-to-end DIR against live MP/M (Apr 22, 2026)
- **2026-04-22**: CONST/CONIN echoed `F G H I` (0x46..0x49) for input
  `d i r \r`.  Diagnosis via a 4-slot CONIN input ring at 0xEC46+:
  impl_conin delivered the correct bytes `64 69 72 0d`.  The corruption
  was in the monolith's cishim/cshim: `mov a, l` after the call, on
  the assumption sdcccall(1) returns 8-bit values in L.  Disassembly of
  impl_conin / impl_const showed both end with `ld a,d; ret` — clang
  Z80 returns 8-bit in **A**, not L.  Fixed by removing `mov a, l`.
  **(Painful)** — the stale HL happened to track the input-ring scratch
  address, producing a deceptively-plausible incrementing pattern that
  looked like an off-by-one input bug rather than an ABI mismatch.
- **2026-04-22**: **First successful DIR over the wire.**  CP/NOS slave
  in MAME, bitbanger SIO-A to TCP 4002 = z80pack cpmsim mpm-net2 MP/M II
  master.  `A>dir` lists `CCP SPR / CPNETLDR COM / CPNOS IMG / NDOS SPR
  / PIPNET COM ...` — real files on `mpm-net2-1.dsk` served by MP/M's
  stock CP/NET server through our RC702-retargeted cpbios + cpnios-shim.
  CONOUT=254 for that one command, confirming full BDOS+NDOS+BIOS chain.
  The goal ("physical RC702 against live MP/M over 38400 8N1") is met
  in emulation; physical hardware next.

## Phase 15: Remote drives for slave workload (Apr 22, 2026)
- **2026-04-22**: `z80pack/cpmsim/mpm-net2` launcher now stages four disks:
  A=mpm-net2-1 (boot + CPNOS.IMG), B=cpm22-1 (DRI/MS assemblers: ASM, MAC,
  RMAC, M80, L80, LINK, Z80ASM, SLRNK, CREF80 + DDT/SID/STAT/PIP),
  C=cpm22-2 (sources: BIOS.Z80, BOOT.Z80, SURVEY.MAC, W.ASM, CLS.MAC,
  BYE.ASM, SPEED.C), D=mpm-net2-2 (MP/M system image kept around for
  tinkering).  Goal: prove CP/NET remote file access with a real workload
  (e.g. `B:MAC C:SURVEY.MAC`).  **(Easy)** — slave `cfgtbl.c` already
  declared A/B/C/D as network-mapped to master drives of the same letter,
  so no slave-side change was needed.
- **Pending:** confirm MP/M `SERVER.RSP` exposes B: and C: to slave
  SID=0x01; if not, reconfigure via GENSYS or direct edit.

## Phase 14: RC702 retarget of DRI reference modules (Apr 22, 2026)
- **2026-04-22**: Decision: the slave must NOT ship DRI's Altos-targeted
  reference code.  The stock `cpbios.asm` bangs ports 0x1C/0x1D/0x1E/0x1F
  (Altos console) and `cpnios.asm` bangs 0x3E/0x3F (Altos serial) — both
  absent on RC702.  **(Easy, once it was seen.)**
- **2026-04-22**: `cpnos-build/src/cpbios.asm` added — RC702 BIOS as a
  trampoline into the cpnos-rom resident at 0xED00+.  17-entry JT matches
  DRI's ABI exactly; CONOUT/CONIN/CONST/LIST shims translate CP/M's
  C-register arg convention and A-register return into clang's sdcccall(1).
- **2026-04-22**: Two RMAC syntax pitfalls surfaced during the cpbios
  retarget.  **(Very hard — silent failures.)**  First, `jmp` is a reserved
  mnemonic; `jmp_op equ 0c3h` assembled but resolved to zero, so the
  zero-page `sta 0000h / sta 0005h` wrote NOPs and CP/M saw a broken
  BDOS vector.  Second, RMAC truncates labels containing underscore, so
  `const_shim` appeared in the sym table as `CONST` and JT entries
  referencing the full name resolved to `JP 0x0000`.  Fixed by renaming
  to short no-underscore labels (`jpopc`, `cshim`, `coshim`, …).
- **2026-04-22**: `cpnos-build/src/cpnios-shim.asm` — 24-byte trampoline
  from the DRI SNIOS JT slot (linked at NIOS=`0xD993` in the monolith)
  into our resident SNIOS JT at `0xEA00`.  Filename carries `-shim`
  suffix per user preference; Makefile maps `cpnios-shim.asm` →
  `d/cpnios.asm` because the link needs the module name RMAC+LINK
  expects (`NIOS:` label).  **(Easy)** now the pattern was established.
- **2026-04-22**: Both trampolines in place; first end-to-end PASS on the
  RC702-retargeted monolith: banner at row 2, `A>` at row 4, 38 CONOUT
  calls (banner 22 + prompt 4 + NDOS addenda 12).  **This closes the
  tripwire that had been blocking since the BIOS_BASE move.**

## What was Hard vs Easy (through Phase 14)

**Easy** (hours, straightforward):
- Initial cpnos-rom skeleton + clang Z80 + lld linker script.
- Porting SNIOS from rcbios-in-c (hardware-abstracted cleanly).
- Adding breadcrumb counters + Lua snapshots for post-hoc analysis.
- Local-override mechanism in cpnos-build/Makefile for shim modules.

**Medium** (a session of focused debugging):
- 8275 CRT + 8237 DMA bring-up.
- DRI .SPR page-relocator (once the 128 B skip-sector was understood).
- MP/M II CP/NET 1.2 wire protocol from DRI docs.

**Hard** (multi-session, required instrumentation to root-cause):
- PROM-disable hazard and its subtle interaction with resident-copy ordering.
- NDOS's TLBIOS-walk of the zero-page BIOS vector.
- BIOS_BASE move and the cascade of silent-until-runtime address drift.
- RMAC's reserved-mnemonic + underscore-label mangling — both assemble
  cleanly, both produce `JP 0x0000` at runtime, neither generates a warning.

**Painful** (wasted time until caught):
- **Stray Python server on :4002 fooling the oracle** — hours of
  "real MP/M" tests were actually Python.  Kill-before-test guard
  filed as #42.
- **Stock CPNOS.IMG on MP/M disk was z80pack-generic, not our RC702
  build** — even when MP/M was in the loop, the fetched image would
  have driven wrong I/O ports.  `mksmokedisk.sh` now overwrites it.

- Stale `.o` files after `-D` flag changes (SLAVEID=0x70 persisted despite
  source edit) — fixed by `$(OBJS): Makefile` dep.
- PROM1 install step missing from `cpnos-install` when `.resident` LMA
  overflowed into PROM1 — silent, produced garbage at the JT LMA.
- Chasing "baseline was flaky" for hours when really one PASS had been a
  lucky single run on an otherwise broken baseline.

## Format for ongoing entries

Each new entry should record: date, phase, what changed, and a
`**(Easy|Medium|Hard|Painful)**` difficulty marker with one-line reason.
Aggregate into a "What was Hard vs Easy" summary at phase boundaries or
when the project reaches a stated goal.

## Key Architectural Decisions

| Decision | Rationale |
|----------|-----------|
| zmac over MAC | Cross-assemble on macOS without CP/M emulator |
| z88dk/sdcc for C rewrite | Only Z80 C compiler that fits 2KB PROM constraint |
| sdcccall(1) ABI | 36% smaller code than sccz80, params in registers |
| Byte-exact reconstruction | Proves understanding of original code; enables verification |
| Conditional assembly | Single source tree for 5 BIOS variants (src/) |
| Separate source trees | 58K, RC703, RC702E too different for conditional assembly |
| Ring buffers in REL30 | Enable reliable serial at 38400 baud for CP/NET |
| BIOS entry points for SNIOS | Simpler than direct SIO access, ring buffer in BIOS ISR |
| Hex-encoded CRC-16 protocol | Proven in cpnet-z80, simpler than DRI ENQ/ACK |
| Python CP/NET server | Quick iteration, handles all BDOS functions over TCP |
| verify_bios.py approach | Compares code bytes only, ignoring runtime-modified variables |
| patch_bios.py | Direct IMD patching avoids SYSGEN round-trip |
| cpnos-rom clang+lld | Z80 backend produces small, readable asm; same toolchain as autoload-in-c |
| DRI RMAC+LINK for monolith | Keep cpnos.com binary-compatible with CP/NET 1.2 semantics rather than reinvent |
| Local-override source dir | `cpnos-build/src/` overrides `cpnet-z80/dist/src/` on a per-file basis |
| -shim suffix for DRI replacements | Makes "this is our RC702 trampoline, not DRI's reference code" explicit at file level |
| Shim at 24 bytes (cpnios) | Smaller than re-implementing SNIOS on the CP/NOS side; resident owns wire logic |
| Breadcrumbs stay until goal is green | Keeps post-hoc trace analysis cheap across sessions; remove only after reliable PASS |
| Monolith addresses locked 0xD000/0xCC00 | Cpnos.com is non-relocatable; acceptable while we ship one slave hardware target |
| Live MP/M over serial as the target | Avoids bespoke-protocol drift vs. goal of stock-MP/M compatibility |

## Key Tools Created

| Tool | Purpose |
|------|---------|
| verify_bios.py | Verify assembled BIOS against reference binaries |
| patch_bios.py | Patch assembled BIOS onto IMD disk images |
| imdinfo.py | Show disk image summary (format, geometry, boot status) |
| imd2raw.py | Extract raw Track 0 from IMD images |
| bin2imd.py | Convert raw BIN to IMD format (mini, maxi, RC703) |
| run_mame.sh | Automated build+patch+launch cycle for MAME testing |
| diskdefs | RC700/RC702/RC703 disk definitions for cpmtools3 |
| build_snios.py | Build SNIOS.SPR with relocation bitmap |
| server.py | Python CP/NET server (BDOS emulation over TCP) |
| autotest.lua | MAME Lua test automation for CP/NET |
| run_test.sh | Full CP/NET test orchestration |
| chksum.asm | CP/M file checksum utility (16-bit sum) |
| bin2ihex.py | Binary to Intel HEX converter for serial transfer |

## Session 73s: crash investigation — #193 fixed; zero compiler crashes remain (May 25, 2026) — Medium

Investigated compiler crashes (user request).  **#193** (Z80LateOptimization
EXC_BAD_ACCESS) root-caused via code-reading + confirmed via lldb on the
assertions build: the "BSS spill->PUSH/POP" peephole did `MII = erase(store)` then
erased the matching-load iterators then `--MII`; when the reload was adjacent to
the store, MII dangled and `--MII` dereferenced freed memory (also UB at MBB
begin()).  Fixed (commit `25fa914f662d`) by anchoring resumption to the inserted
PUSH and erasing the store last.  Oracle: ZERO compiler crashes (`grep signal`=0)
across the FULL default AND new `-static-stack` suites (1020 tests each); AES
byte-identical; cpnos PROM1 2028->2027 B (one more safety-checked conversion) and
polypascal-test PASS (PRIMES->29989, 50.79 s); lit 114+5; default 720/37/56.
Lit guard `bss-spill-pushpop-crash-193.ll`.

Separate finding (NOT crashes): the `-static-stack` sweep surfaced ~60 runtime
FAILs + a few emulator-timeouts (test_166/test_54).  The production `+static-stack`
config is under-tested -- some are real bugs (e.g. test_166 i32 popcount loop, the
#192 i32-select-loop family), some are likely `+static-stack`-incompatible test
patterns (recursion/dynamic-alloca: test_48 even fails on a missing `alloca.h`).
Needs a future triage pass; left as a noted finding, not filed half-triaged.

## Session 73s: build-determinism check + +static-stack triage (#195) (May 25, 2026) — Medium

Two follow-ups after the late-opt audit.  (1) **Build determinism**: `llc` is
run-to-run DETERMINISTIC (5/5 identical on AES) — the genuinely-bad flaky form is
absent; the cpnos 2027↔2028 flux was build-to-build (±1 B, ~19 B margin),
deprioritized.  (2) **+static-stack triage (#195 filed)**: the new `-static-stack`
mode surfaces multiple failures in the PRODUCTION config.  Triaged by opt-level
dependence (layout/reentrancy = opt-independent; codegen bugs = opt-dependent):
real production-opt-level (`-Os`) codegen bugs = test_166 (i32 popcount loop),
test_11 (f32/i64), test_27 (2D array), test_36, test_38; O0-only = test_01/04/15/
28/54; layout/incompatible = test_58, test_48 (alloca).  cpnos/BIOS/AES build+boot
(don't hit the exact shapes) but these are latent in the shipped `-Os +static-stack`
compiler.  Each needs a focused root-cause like #192.  All session-73s work pushed.

## Session 73s: #195 — BSS-spill->PUSH/POP drops loop-carried store-back (3 prod bugs fixed) (May 25, 2026) — Hard

Root-caused the top production `-Os +static-stack` bug (test_166 i32 popcount loop
HANG).  The BSS-spill->PUSH/POP peephole converted the high-half store+reload
(`LD (slot),BC ... LD BC,(slot)`) to PUSH/POP, dropping the store -- but the loop
also reads that slot at the top via the back-edge reload (`LD HL,(slot)`), which
the peephole's checks miss (forward-only orphan scan; 'used elsewhere' skips the
current block + same-class only).  So the slot was never written, the high half
never decreased -> infinite loop.  Fix (commit `c2bbe80d4623`): bail when the slot
is read earlier in the same block, before the matched store (loop-carried-reload
signature); surgical, cpnos byte-neutral.  **One fix resolved THREE production
items: test_166, test_11 (f32/i64), test_58 (fixed_point)** -- all now PASS all
opt levels under `-static-stack`.  AES byte-identical; cpnos 2028 B + polypascal
PASS (50.73s); lit 115+5.  Remaining #195 items (separate wrong-value bugs):
test_27_array_2d, test_36_stack_pressure.

## Session 73s: #195 test_27 fixed (address-taken) + test_36 reclassified (May 25, 2026) — Hard

test_27 (volatile 2D-array sum): SECOND BSS-spill->PUSH/POP defect — when the
+static-stack frame base is materialized into a register (`LD HL,__sfrend_main`,
array indexed in a loop), slots are read INDIRECTLY via pointers, which the
direct-load orphan scan misses; it dropped m[0][0]'s store-back -> sum off by one.
Fix (commit `02e56e81fabb`): refuse the conversion for address-taken frame slots.
test_27 -static-stack PASS all levels; AES byte-identical; cpnos 2029 B (+1 B) +
polypascal PASS; lit 116+5.

test_36 (stack_pressure, bit 2 = mutual-recursion chain): RECLASSIFIED as a
test-mode artifact, NOT a codegen bug.  Without forced +static-stack, AutoStaticStack
correctly excludes chain_a/b/c (CallGraph SCC>1) and they use the normal stack;
the -static-stack mode forces +static-stack globally, bypassing that SCC safety,
so recursive functions wrongly get fixed-address BSS frames.  Production firmware
is non-recursive, so not a production concern.

**#195 production-config (+static-stack -Os) outcome: 4 real codegen bugs fixed
(test_166/11/58/27); test_36 = recursion artifact; test_48 = alloca-incompatible;
test_01/04/15/28/54 = O0-only (production uses -Os).**  Both BSS-spill->PUSH/POP
defects (loop-carried-reload + address-taken) closed.  Validated in the production
+static-stack config (AES byte-identical, cpnos +1 B over baseline, polypascal PASS).

## Session 73s cont. (2026-05-26) — #198 fix + -verify surface triage [Hard]

**#198 (real -O2 miscompile) FIXED + closed.**  MachineCSE on AES `rj_sb_inv`
triggered a same-class BSS-spill->PUSH/POP peephole (Z80LateOptimization ~4470)
whose cross-block guard matched only the spilled pair's own opcodes; a cross-class
reader (`LD_DE_nnind` of a BC-spilled slot) in another block was orphaned ->
read a slot PUSH never wrote -> garbage.  Fix: widen the cross-block guard to any
register class (`isAnyBssLoad||isAnyBssStore`), matching the sibling peephole.
Root-caused via `-opt-bisect-limit` + per-pass MIR (verified, not inferred).
New MIR regression test (PASS-with/FAIL-without).  Full oracle green; cpnos PROM1
2028->2036 B (12 B free), autoload +10 B, BIOS unchanged; cpnos polypascal PASS.

**`-verify-machineinstrs` -O2 surface triaged (171/174) -> 3 classes:** #112/#189
(illegal-vreg, GR16NoIR pseudos), #194 (undefined-physreg liveins, gf_log), #200
(SPILL_GR16 too-few-operands, new).  All invalid-MIR-that-runs; tracked under #197
(CI-hardening), with the test-runner `clang -verify` flag landed.  Stood up an
assertions build (`build-macos-asserts`) for bug-hunting.

**Process:** filed #199 as a duplicate of pre-existing #194 (didn't search issues
first) -> closed it, hardened `feedback_grep_repo_docs_before_deriving` to cover
issue-filing.  Corrected two overclaimed root-cause statements after the source
contradicted them -> hardened `feedback_state_certainty` (HARD; familiarity != fact)
and put the certainty discipline + a proactive "survey the toolbox" rule into AGENTS.md
across all repos.

Summary: `llvm-z80/tasks/session73s-198-verifier-summary.md`.

## Session 73s cont. (2026-05-26) — #38 IY size-gate + verify-clean cluster [Hard]

**#38 IY size-gate LANDED.** Un-reserve IY as a 4th 16-bit pair at -Os/-Oz +static-stack
only (size win, ~+0.1% tstate cost so reserved for speed). z80IsIYAllocatable(MF) threaded
through getReservedRegs/getLargestLegalSuperClass/Z80NarrowNoIndex. Production byte win:
cpnos 2033->2026, autoload 1483->1478, BIOS 5920->5897 (~33 B), in the hot functions
(_specc, _scroll_lines, _main_relocated). 0 undoc ops, cpnos boots, autoload boots to A>.

**Two latent miscompiles fixed en route:** (1) BSS-spill->PUSH/POP peephole was blind to
explicit SP writes (ld sp,hl) -> push/pop bracket spanning a call-arg cleanup popped the
wrong slot (test_58_fixed_point -O0 +static-stack); added an SP-write guard. (2) ISel built
tied INC16 as `%t = INC16 %t` (SSA multiple-def) -> miscompiled test_38_sort_search at O1;
gave it a fresh dst vreg. Both with MIR/lit regression tests.

**Verify-clean cluster (#197): 2 of 4 classes cleared** (illegal-vreg #201, multiple-vreg-defs
INC16); #194 (liveins) + #200 (SPILL_GR16) remain. Filed rc700#100 (autoload stale clang
banner check -- harness bug, boot fine). Summary: llvm-z80/tasks/session73s-iy-sizegate-summary.md.

## Session 73s cont. (2026-05-26/27) — differential oracles + 3 miscompiles closed [Hard]

**IX un-reserve investigated, reverted, #12 documented.** Mirrored the #38 IY size-gate to
IX; rigorous A/B showed it's a REGRESSION (BIOS +91 B) because IX is callee-saved (PUSH/POP
tax), and the greedy CSR cost model can't even reach neutral (+18 B perturbation floor). All
3 firmware images have ZERO frame-pointer functions, so the only IX win is making it
caller-saved -- which needs FP-elimination (#12). Reverted; full write-up on #12. rc700#100
(autoload banner check) fixed + CLOSED.

**Three real miscompiles found, fixed, CLOSED:**
- #202 -- cross-block BSS-spill->PUSH/POP peephole dropped a loop-carried store-back (read
  before store across a back-edge). Unified the loop-carried guard across all 4 spill
  peepholes.
- #204 -- FOUND BY THE NEW NATIVE ORACLE: address-taken slot's store converted to PUSH (a
  double-pointer swap read it via a pointer). Unified the address-taken guard across all 4
  peepholes. (#203 tracks the remaining structural guards; OPEN.)
- #136 -- the long-standing "38 mystery O1 fixtures". Root-caused via the cross-opt-level
  oracle + opt-bisect to Z80LoopIdiomFill emitting an OVERLAPPING memcpy (UB) that InstCombine
  inlines to a wide load+store at -O1, breaking the LDIR forward-propagation. Fixed with a
  one-line `volatile` (forces LDIR lowering). All 3 fixes production byte-identical.

**Built two differential test oracles** (`test-runner`):
- `-diff-opt` -- every opt level of a program must return the same value (cross-opt-level);
  caught #202/#15, found nothing the expect-directive didn't for #136 until paired with...
- `-native-oracle` -- compares each test's Z80 result to the HOST C compiler's (computed
  reference, doesn't trust hand-written `expect`s); found #204, confirmed #136's wrong side.
  Both now sit at a CLEAN baseline (0 DIFFOPT / 0 NATIVE) in default AND +static-stack configs
  -- ready as a CI gate. SKIP-IF gained `+feature` support; test_36 (recursion, invalid under
  non-reentrant +static-stack) skipped there.

**Discipline:** hardened AGENTS.md + memory -- certainty in *filed issue diagnoses* (a root
cause is a hypothesis until checked; #202 was filed with a wrong cause), "baseline before you
change", and "a bug found by luck is a bug in your oracle" (audit the detector, not just the
cause). Lit 121+5 throughout. Summary: llvm-z80/tasks/issue12-ix-unreserve-measurement-2026-05-26.md.

## Session 73s (cont.) — Cluster 1 small-peephole wins: #18 fixed, #151/#152 closed (2026-05-27)  [Easy]

Verify-first pass through the Cluster-1 candidates (`llvm-z80/tasks/issue-closeout-plan-2026-05-27.md`), then one real fix landed.

- **#151 CLOSED (already fixed):** sext(icmp eq/ne) lowers to clean `sub 1; sbc a,a; ld e,a; ld d,a` — the old `and 1; rrca; sbc a,a` residual is gone. Verified, no code change.
- **#152 CLOSED (implemented + tested):** the #147 SET/RES-on-memory peephole already handles intervening A-readers via the `LD A,(HL)` form (`u8 t=g; port=t; g|=8` -> `ld hl,_g; ld a,(hl); ld (_port),a; set 3,(hl)`). Lit `issue-152-set-res-with-a-reader.ll` PASS. Was open but done.
- **#18 FIXED:** new per-MBB peephole in Z80LateOptimization — `LD r,n` -> `LD r,A` when A already holds the constant (from `xor a`/`sub a`=0 or `ld a,n`). Saves 1 B/fire; reads A only (value+flags preserved; fires consecutively). Within-block tracking, invalidated by any A def incl. CALL RegMask clobber. llvm-z80 main `bfce0fff25db`.
  - Oracle: lit 122+5; differential oracles 0 DIFFOPT/0 NATIVE (default + static-stack); cpnos PROM1 **2028 -> 2026 B** (-2 B, 22 B free); cpnos-polypascal-test PASS 51.17 s.
- **#122 ruled out as miscompile:** the suspicious `and 254` for a `& 0xFF` source at threshold 10 is value-preserving demanded-bits folding (threshold 11 drops the mask entirely). The 8-bit load already happens; only the 16-bit subtract tail is suboptimal (the marginal/risky #122 size win, deferred).

Open Cluster-1 remainder: #117 (i16 EQ/NE neither-in-HL, ~1 B, risky compare-lowering), #122 (8-bit CP fast path, marginal), #146 (epilog `pop;inc sp;inc sp;push;ret` -> `pop hl; ex (sp),hl`, narrow), #173 (8-bit BSS spill via A, medium).

## Session 73s (cont.) — #42 CLOSED: compiler ships <intrinsic.h> (same source clang+SDCC) (2026-05-27)  [Medium]

User directive refined the fix: "the same rcbios source must compile under clang AND sdcc without ifdefs" and "the intrinsic.h file must live in the compiler, not the project."

Delivered at the compiler level (llvm-z80 main `81b46fe614d8`):
- **clang now ships `<intrinsic.h>`** (clang/lib/Headers/intrinsic.h -> lib/clang/<v>/include/). `#include <intrinsic.h>` resolves to clang's copy under clang, z88dk's under SDCC — identical `intrinsic_*` API, no -I, no #ifdef in source.
- Two new intrinsics `llvm.z80.im2` / `llvm.z80.set.i` + selection (IM 2 / move-to-A + LD I,A) + legalizer whitelist.
- Six clang builtins `__builtin_z80_di/ei/halt/nop/im2/set_i`: BuiltinsZ80.td, tablegen wiring (CMakeLists + TargetBuiltins.h), Z80TargetInfo::getTargetBuiltins, EmitZ80BuiltinExpr (TargetBuiltins/Z80.cpp), CGBuiltin dispatch.
- Shipped header mirrors z88dk's API (di/ei/halt/nop + im_2 z80-only). `set_i` (LD I,A) stays a clang-only builtin (z88dk has no such intrinsic) — fixes the rcbios bios_hw_init.c inline-`ld i,a` mis-fire that needed an asm shim.

Clang path is now inline-asm-free; optimizer models the side effects precisely.

Verified: lit intrinsics.ll + clang/test/CodeGen/z80-builtins.c + clang/test/Headers/z80-intrinsic.c (Z80 suite 122+5); end-to-end `clang --target=z80 -S` with NO -I emits `di; im 2; halt; ei`; codegen-neutral (cpnos PROM1 2026 B, two builds byte-identical, polypascal PASS 51.87 s); differential oracles 0 DIFFOPT/0 NATIVE (default + static-stack).

### rcbios adoption of the compiler-shipped <intrinsic.h> (2026-05-27)

rcbios-in-c/clang/intrinsic.h now `#include_next <intrinsic.h>` (under __z80__) to
pull intrinsic_di/ei/halt/nop/im_2 from the COMPILER instead of defining them via
inline asm; keeps only host-CLion stubs + SDCC keyword stubs.  Realizes "the
intrinsic.h file lives in the compiler, not the project."

Verified both compilers on the SAME source (no #ifdef):
- clang BIOS **5922 -> 5897 B (-25 B)** — intrinsics let the optimizer treat DI/EI
  as precise side-effects vs the opaque `__asm__ volatile` barrier.  MAME boot:
  signon "RC700 56k CP/M 2.2 C-bios/clang", A> prompt, disk ERR=0 across 77 tracks.
- SDCC BIOS 6091 B builds clean (uses z88dk's <intrinsic.h>, untouched).

### #4 CLOSED: rcbios __critical now real (z80_critical attribute) (2026-05-27)

clang/intrinsic.h: `#define __critical __attribute__((z80_critical))` (was a
silent no-op).  The backend's pre-existing Z80FrameLowering DI/EI handling is
now reachable from C.  rcbios's `__critical __interrupt` SIO ISRs: DI suppressed
(HW disables on entry), EI;RETI unchanged -> clang BIOS 5897 B (unchanged), di
count 21 (no spurious DI).  MAME boot: signon + A> + disk ERR=0 across 77 tracks.
Compiler side: llvm-z80 main 736f83f.

Note: cpnos final-bin size wobbles 2026<->2027 B purely from the embedded cold-init
build date+githash string (byte 585 = a timestamp digit) compressing differently;
the uncompressed payload (compiled code) is byte-identical -- #4/#42 are codegen-neutral.

### Cluster 2 started: #203 step 1 (predicate unification) landed (2026-05-27)

Verify-first: #155/#143/#140 already CLOSED; remaining open Cluster-2 = #203 (guard
unification) + #139 (diagnostic) + #188 (meta) + #20 (deferred).

#203 **step 1 (predicates)** — llvm-z80 main `f3282df`.  The four BSS-spill->PUSH/POP
peepholes each had drift-prone copies of isAnyBssLoad/Store/isAnyPush/Pop/sameAddress;
added shared z80IsAnyPush/z80IsAnyPop and aliased every copy to the file-scope z80*
helpers (opcode sets diffed identical first).  Behavior-preserving: lit 123+5, cpnos
payload BYTE-IDENTICAL, oracles 0/0.  −42 net lines.  NOT pushed.

#203 **step 2 (sequences)** scoped + deferred: the four `UsedElsewhere` blocks genuinely
diverge (peephole #3 has the #155 dominator-relaxation; #1/#2/#4 are strict), so unifying
is a behavior-CHANGING semantic reconciliation needing runtime verification — a focused
session, not tail-end work (peephole-safety discipline).

### #203 step 2 landed: UsedElsewhere unified + predicate aliasing completed (2026-05-27)

llvm-z80 main `f009ab4`.  Extracted the four hand-mirrored `UsedElsewhere` orphan
guards into one parameterized `z80SlotUsedElsewhere` (SkipBlocks/SkipMIs/MDT params
capture the #1/#2 whole-block-skip, #3 #155 dominator-relaxation, #173 MI-skip
variants); completed the predicate aliasing step 1 missed (sameAddr ×2, isAnyBssAccess
with its dead isStore out-param).  Behavior-preserving: cpnos payload BYTE-IDENTICAL,
oracles 0/0, lit 123+5.  −35 net lines (−77 across step 1+2).  NOT pushed.
Remaining #203: the forward-scan guards (orphan/stackdepth/SP-write) are interleaved
with load-collection — the harder factor-out, deferred.

### #203 step 3 (SP-write) + #139 closed (2026-05-27)

#203 step 3: extracted the explicit-SP-write guard (#198 family) into shared
`z80IsExplicitSPWrite`.  Behavior-preserving (cpnos byte-identical, oracles 0/0,
lit 123+5).  llvm-z80 main `4bdeea1`.  All historically drift-prone SHARED guards
of the spill->PUSH/POP family now single-sourced (predicates, UsedElsewhere,
loop-carried, address-taken, SP-write).  #203 stays open only for the forward-scan
orphan/stack-depth (interleaved with per-peephole load-collection — a restructure).

#139 CLOSED: stale diagnostic — its cpnos-rom `_snios_rcvmsg_c` candidate was removed
(cpnos-rom parked/superseded); the cross-MBB peephole is now comprehensively guarded
+ oracle-verified, so a candidate not firing is correct guard behavior, not a bug.

### Cluster 3 started: test_48 fixed, #200 root-caused (2026-05-27)

test_48_dynamic_alloca: `<alloca.h>` -> `__builtin_alloca` (freestanding, #35) — builds
+ PASSES O0-Oz default, removes 6 FATALs (#190 test-setup part).  llvm-z80 `6589e2a`.
#200 fully root-caused: the 2-op `SPILL_GR16 $de,-2` is INTENDED (expanded by
expandPostRAPseudo Z80InstrInfo.cpp:1010); the verifier runs between PEI and that
expansion.  Asymmetry: large-offset path expands at PEI, small-offset leaves the
survivor.  Fix options A (expand at PEI) / B (variadic decl) posted; deferred (deep, benign).
Remaining Cluster 3: #200 (fix), #194 (stale liveness, delicate), #125 (-O0 crash), #197 (meta).

### Session 73s-cont2 (2026-05-27) — Cluster 3 verifier sweep (#197). Medium.
Cleared 4 root-cause classes of the `-O2 -verify-machineinstrs` red surface, each
fully gated (lit + diff-opt + native-oracle + cpnos/AES where bytes moved).
**#200 CLOSED** (fix C: restore the folded `$offset` operand as a 0 placeholder in
the small-offset SPILL/RELOAD FI survivor path; the 2-op form was intended but
under-counted vs the 3-op decl — neutral, `47db108`).  **#194 CLOSED** (two
Z80LateOptimization peepholes left stale `$a` liveness: cross-block `LD A,r`
removal -> addLiveIn; `LD A,#0`->`XOR A` -> undef use — neutral, `46fbafb`).
**#209 filed+fixed** (don't-care-read family): `PUSH AF` stack reserve (frame
lowering, neutral, `99ee190`) + `EX DE,HL` one-way copy dest (`copyPhysReg`,
`8ff4208`).  The EX DE,HL one is NOT neutral — undef-dest let the optimizer drop
dead dest-defs: **cpnos PROM1 2028 -> 2022 B (-6 B, 26 B free)**, polypascal PASS
50.65 s, AES enc/dec PASS (ts 11516046 unchanged).  Lit 123+5 -> 127+5.
Remaining #197 surface (next): `aes_mixColumns` `PUSH_HL` undef `$hl` — frame-index
SP-relative scratch save guarded by `isRegLiveAt(HL)`, a liveness-reconciliation
issue (not a clean undef) + the #112/#189 GR16NoIR class.  Entry point:
`llvm-z80/tasks/session73s-cont2-verifier-sweep-2026-05-27.md`.  All on `main`, NOT pushed.

## Session 75 (cont.) — cpnos polypascal SIO harness fix + clean both-transport pass (2026-05-31) [Medium]

Root-caused the "clang `TRANSPORT=sio` cpnos polypascal is broken" report to a
**test-harness config gap, NOT a clang bug**.  The prom1-lineprog is a single
dual build: `TRANSPORT=pio-irq` and `=sio` produce a **byte-identical** payload
(`TRANSPORT_NAME` only feeds the two-PROM server banner).  The runtime transport
is chosen by `install_transport()` reading **SW1 bit 2 (S03)** at cold-init, and
the polypascal test/lua **never set the MAME DIP** — so `TRANSPORT=sio` ran PIO
under the default DIP (S03=On) and the "failure" (boots to banner, no E>) just
meant SIO was never selected.  (Wiring was already transport-correct: pio uses
`-bitb3` PIO-B↔MP/M `:4002`, sio uses `-rs232a -bitb1` SIO-A↔MP/M.)

**Fix** (`51deb4e`, pushed to main): `cpnos-shared/mame/polypascal_test.lua`
sets the `:DSW` S03 field from `$TRANSPORT` (Off/0x04=SIO, On/0x00=PIO) at the
first periodic tick — autoboot scripts load *after* machine start so
`register_start` never fires, but the periodic runs frame-1, before cold-init
reads SW1.  `cpnos-in-c/Makefile` exports `TRANSPORT` so the lua sees it.

**Clean back-to-back both-transport PASS (proper MP/M hygiene, no mid-run
`pkill mame`):**

  | TRANSPORT | DIP set        | result                                    |
  |-----------|----------------|-------------------------------------------|
  | pio-irq   | SW1 S03=0x00 PIO | PASS — PPAS PRIMES 29989, Q→E>           |
  | sio       | SW1 S03=0x04 SIO | PASS — PPAS PRIMES 29989, Q→E>           |

So **clang-SIO was always correct — it was simply never selected**; the
`cpnos-polypascal-test` now genuinely exercises BOTH transports.  Back-to-back
runs remain subject to the known intermittent stage-1 E> MP/M flake
(`feedback_polypascal_stage1_flake`) — both pass on retry/clean hygiene.
Diagnostic note: `BOOT_MARK` instrumentation of this path is blocked (enabling
it overflows the `.init` 640 B region by 61 B — the build is at the size edge).
Context: this was a follow-up to the llvm-z80 #150 ship (i16 EQ/NE HighByteZero
sub_lo extraction; cpnos −8 B RAM) which surfaced the sio cell.

## Session 2026-06-08 — #23 LICM/CSE workaround retired + sweep harness modernized

Two intertwined work threads, same session.

**Compiler-comparison-corpus harness (early):** the sweep was masking
zsdcc bench failures behind a -counter cap (zsdcc CRT never terminated
cleanly, so ts hit 200M).  Switched termination to the canonical
z88dk-ticks ED FE syscall trap (A=CMD_EXIT, L=verify status), discovered
via `z88dk/test/suites/make.config` after ~40 min of derivation from
ticks source.  Memory rule `[[reference_ticks_canonical_exit_trap]]`
pins the mechanism.  Added `EXPECTED_FAIL` set: fannkuch zsdcc + pi
zsdcc XFAIL (pre-existing, deferred at commit time per `0ca7d3c`); full
writeup `tasks/zsdcc-bench-divergence-2026-06-08.md`.  New bench
`bench_word_fill.c` targets the ravn/llvm-z80#99 XFAIL with a clean
i16-counter + walking-pointer shape; clang measured +63 % slower than
zsdcc on the predicted shape (`tasks/compiler-comparison-corpus/word_fill_baseline_2026-06-08.md`).

**#23 LICM/CSE revalidation (late):** historical
`disablePass(LICM + EarlyLICM + CSE)` workaround in `Z80PassConfig`,
shipped for ~2 months on (a) cpnos/AES size pessimization grounds
(#128 / #177 Task 3) and (b) -O2 MachineCSE miscompile correctness
guard (#198), was re-measured today on a clean rebuild after the user
flagged stale-build risk.  Re-measurement (byte-identical to
incremental rebuild, sound) inverted both grounds: AES -Oz LICM+CSE on
saves 13 B + 8.9 % tstates; -O2 saves 118 B + 9.2 % tstates and the
#198 miscompile no longer reproduces (verifier clean, 854 PASS / 0 FAIL
across O0..Oz).  User direction "don't let short-term size block
structural fixes" cleared the autoload +64 B raw / +25 B compressed
short-term regression; cpnos PROM1 -15 B (improves); rcbios +7 B
(marginal).  Workaround retired by flipping `-mllvm -z80-enable-licm`
/ `-mllvm -z80-enable-cse` defaults FALSE -> TRUE; flags preserved as
escape hatches.  `Z80InstrInfo::shouldHoist` heuristic added (refuses
hoist when loop body contains a CALL) — gated by
`-mllvm -z80-licm-block-on-call`, default OFF awaiting count-based
refinement (see `[[B11]]` in `llvm-z80/tasks/known-suboptimal-codegen.md`).
Session writeup: `llvm-z80/tasks/session-2026-06-08-issue23-licm-cse-revalidation.md`.

Memory rules added this session: `[[feedback_check_memory_before_coding]]`
(HARD: scan at task start, name applicable rules, then code),
`[[feedback_revalidate_historical_compiler_claims]]` (HARD: re-validate
on clean rebuild before acting on a historical perf claim — this session
is the pinned example), `[[reference_ticks_canonical_exit_trap]]` (ED FE
syscall trap is the canonical z88dk-ticks termination).

### memset.pattern target hook: POC verified, RFC issue body ready (2026-06-09)

User asked to "finish the work on retire Z80LoopIdiomFill"; chose
"doc + issue body + prototype branch" via AskUserQuestion.  Discovered the
prototype was already committed to llvm-z80 main as
`6839ebc4bcbf [Z80][PROOF-OF-CONCEPT] TTI hook for experimental_memset_pattern`
— implements stages 1–5+7+8 of the design doc's implementation plan
(TTI hook default-true, PreISelIntrinsicLowering consumer, Z80 TTI
override for K∈{1,2,4}, Z80LegalizerInfo new arm, idiom pass emits
upstream intrinsic, new `experimental-memset-pattern.ll` lit test).
Stage 6 (delete fork-local `llvm.z80.pattern.fill`) deferred — K=3 still
routes to the fork intrinsic because the upstream `iN`-typed pattern
would need i24 generalisation in the seed-store path.  Z80LoopIdiomFill
retirement itself is out of scope: it requires upstream `LoopIdiomRecognize`
to grow multi-byte pattern-fill recognition (different pass, different
review audience).

**Verification on macbook native build:** Z80 CodeGen lit 151 PASS + 5
XFAIL (incl. new test + existing pattern-fill tests; the one MC failure
is pre-existing host-build tooling gap, not a regression).
`Transforms/PreISelIntrinsicLowering` supported subset 8/8 PASS.
Production binaries vs current CLAUDE.md headlines: autoload **1669 B**
(−4 B from the #221 DJNZ `-g` fix, not the POC), cpnos PROM1 **2030 B**
(exact), BIOS **5905 B** (exact).  K=2 lowering shape byte-identical
between fork-local and upstream-intrinsic paths.

**Artefacts** (llvm-z80 commit `d953651`):
- `tasks/design-upstream-memset-pattern-target-hook-2026-06-09.md` →
  DRAFT → v1; section 7 now maps each stage to the POC commit; new
  section 7.1 (K=3 deferral rationale) + 7.2 (what still anchors
  `Z80LoopIdiomFill` to the fork); section 8 carries the verification
  numbers above.
- `tasks/upstream-memset-pattern-issue-body.md` → new file; RFC-style
  body ready to file at `llvm-z80/llvm-z80` with `gh issue create
  --body-file …`.  Self-contained for an audience that doesn't know
  the fork's history; five specific questions for @zlfn (in-scope-for-
  fork, TTI vs TLI, staging order, demonstrating-consumer in same PR
  vs follow-up, K=3 fate).  Filing **gated** on explicit per-filing
  go-ahead per HARD rule `[[feedback_explain_before_filing]]`; NO PR
  alongside the issue (section 6.4 of the design doc — "no PR before
  substantive response").

**Rules:** `[[feedback_explain_before_filing]]` (per-filing go-ahead),
`[[feedback_file_bugs_not_fixes]]`, `[[feedback_no_pull_requests]]`,
`[[feedback_no_upstream_issues]]`, `[[feedback_upstream_routing_two_targets]]`,
`[[project_z80_upstream_goal]]` (staged collaboration: fork-of-record
first, mainline later).

### Z80LoopIdiomFill → Z80PatternFillRecognize + LoopIdiomRecognize-extensibility analysis (2026-06-09)

Same-day follow-up to the memset.pattern hook work above.  User asked
whether the pass was correctly named and whether `LoopIdiomRecognize`
could be made overridable.

**Rename** (llvm-z80 commit `65cb811`, pushed): the pass's body is
target-agnostic (SCEV add-rec recognition, store-slot partition
validation, loop-invariant value guards) — the `Z80` prefix was tracking
where it lives, not what it knows.  `Fill` was also ambiguous (single-byte
memset vs multi-byte K-pattern).  Renamed to `Z80PatternFillRecognize`,
mirroring upstream `LoopIdiomRecognize::recognize*` shape.  Touched:
file (`git mv`), class, legacy-pass class, `create*` factory,
`initialize*Pass*` registrar, `DEBUG_TYPE`, pipeline name, display name,
all callers (`Z80.h`, `CMakeLists.txt`, `Z80TargetMachine.cpp`,
`Z80LegalizerInfo.cpp` comments, `IntrinsicsZ80.td` comment), three lit
tests, design doc, RFC issue body.  Header notes preserve the original
name as a greppable rename-history marker.

**Verification post-rename:** Z80 CodeGen lit 151 PASS + 5 XFAIL
(identical pass count); autoload **1669 B** unchanged; cpnos PROM1
**2029 B** (-1 from prior 2030, builddate-timestamp ZX0-compression
noise; uncompressed payload byte-identical); BIOS **5905 B** exact.
Rename functionally inert as expected.

**LoopIdiomRecognize-overridability analysis** (new design doc §7.3):
the symmetric extensibility hook would be `TTI::tryRecognizeCustomLoopIdiom`
called from `LoopIdiomRecognize::runOnLoop` before the built-in matchers.
**Deliberately NOT proposed**:
1. Recognition contracts are open-ended (preserved-analyses + delete-
   permission matrix is large; spec surface big).
2. No rule-of-three second consumer — extensibility hooks need ≥3 would
   -be users; today only Z80's recogniser exists.
3. The lowering hook this RFC already proposes
   (`shouldExpandExperimentalMemSetPattern`) plus a future direct
   addition of K-pattern recognition to upstream `LoopIdiomRecognize`
   cover the same ground without any extensibility surface —
   recognition becomes uniformly upstream-owned; lowering stays
   target-driven.

Status-quo de-facto extensibility is `TargetPassConfig::addIRPasses`
(our parallel pass); costs zero today because upstream
`LoopIdiomRecognize` doesn't match our K-byte shape at all.

**New findings landed in the project:**
- `llvm-z80/tasks/upstream-coherence-map-2026-05-22.md` Tier I — new
  row "memset-pattern-hook (2026-06-09)" cross-refs the RFC body +
  design doc + POC commit.
- `tasks/memory/feedback_fork_local_pass_naming.md` (new) — reusable
  rule: fork-local pass naming is upstream-candidacy honesty; if the
  body is target-agnostic, name with the operation
  (`*Recognize`/`*Combine`), record the upstream debt in the coherence
  map, carry a one-line rename-history note in the header.  Sister
  Z80-prefixed passes worth auditing under this lens: any whose `.cpp`
  doesn't dereference `Z80Subtarget` / `Z80TargetMachine` /
  `Z80InstrInfo`.

**Rules:** `[[feedback_fork_local_pass_naming]]` (new — fork-local pass
naming is upstream-candidacy honesty), `[[project_z80_upstream_goal]]`,
`[[feedback_explain_before_filing]]`.

### rc700 issue triage + LTO production adoption + cpnos cleanup (2026-06-10, single session)

Started from "list open issues"; spanned issue triage + LTO production
adoption + #85/#87 investigation + cpnos cleanup.  rc700 open issues
**42 → 22** (-20 net).

**Issue work** (rc700-gensmedet):
- **Closed (16):** #18, #21, #25, #27, #29, #37, #48 (FIXED 2026-04-29
  in code, found during retarget), #50 (memcpy/memmove resolved — 15
  inline LDIR sites, zero runtime helpers), #82, #83, #85
  (investigated → structural shim layer is required, projected 30–50 B
  savings don't materialise), #89 (LTO adopted, default flipped), #90,
  #92, #93, #95.
- **Re-targeted (4):** #17 → cpnos-in-c/src/init.c:371 (LOGIN PASSWORD
  hardcode LIVE in production tree), #20 (file-path corrected:
  z80pack/cpmsim/srcmpm/), #36 → rcbios-in-c/bios.c:973, #87 partial.
- **Parked (6):** #7, #17, #31, #32, #34, #84.
- **Doc fix:** #101 (CLAUDE.md IVT slot table autoload-PROM-era
  annotated; rcbios CTC base 0x00 → display ISR at slot 0x04, not 0x14;
  pointer to bios_hw_init.c lines 79-103 as the authoritative
  CP/M-context source).
- **8 new labels created and applied** to all 42 originals
  (cpnos-rom-superseded, cpnos-in-c, rcbios-in-c, cpnos-in-asm-parked,
  harness, awaiting-hardware, parked, compiler-debt) — previously zero
  label coverage; sweep doc at workspace
  `tasks/rc700-issue-reevaluation-2026-06-10.md`.

**Upstream 5-bug queue** (workspace `tasks/upstream-5bug/`):
- STATUS.md rewritten with AVR-triage verdicts: bug 2 FILED upstream
  (llvm/llvm-project#202112, OPEN); bug 3 MOVED to fork as
  ravn/llvm-z80#223 (no in-tree consumer for
  getPredictableBranchThreshold().isZero() path); bug 4 HOLD
  (#219 contaminated by icmp-narrow soundness gate); bug 5 v2 reframed
  consistency-led (draft-bug5-v2.md; awaiting per-filing verdict).
- Original draft-bug5.md kept as historical record.

**cpnet/server.py decommissioning** (per user "no, server.py is not
used anymore.  delete it"):
- Deleted `cpnet/server.py` (1280 lines) and 6 dependents:
  `run_test.sh`, `setup.lua`, `autotest.lua`, `serial_monitor.lua`,
  `serial_graph.py`, `bin2ihex.py` (only live caller was run_test.sh).
- Total: **−2001 LOC dead code removed**.
- Kept: `build_snios.py`, `cpnet12_client.py`,
  `polypascal_pio_inject.py` (each has a non-server.py purpose).
- Closed #23, #28, #30 (cpnet/server.py-specific defects — moot once
  the file is gone).
- Doc cleanup deferred (CPNET_SYSTEM.md "Quick Start" still references
  server.py; flagged in 60a2769 commit for separate scope).

**LLVM-Z80 compiler work**:
- `[lld][Z80] Map Triple::z80/sm83 to EM_Z80 for LTO bitcode linking`
  (llvm-z80@978fca2) — 4-line addition to
  `lld/ELF/InputFiles.cpp::getBitcodeMachineKind` + 1-line addition to
  `lld/test/lit.cfg.py` target-feature map.  Unblocks any out-of-tree
  Z80 backend from end-to-end LTO.  New lit test
  `lld/test/ELF/lto/z80.ll` exercises both triples via
  split-file + llvm-as + ld.lld + llvm-readobj.  Same upstream-
  relevance shape as session 77's elf32-z80 auto-detect for
  llvm-objdump (generic-LLVM tooling plumbing).  Tracked under #186
  U-LLVM queue.

**rcbios-in-c LTO production adoption** (rc700#89, closed):
- `[rcbios-in-c] Make boot_header LTO-safe (#89 follow-up)`
  (rc700@bdd2af2) — `__attribute__((used, retain, section(".boot")))`
  on `boot_header` + linker-script `KEEP(*(.boot))` first matcher.
- `[rcbios-in-c][#89] Default clang BIOS to -flto (saves 15 B)`
  (rc700@bcc9f97) — `-flto` in default CFLAGS.  No-op control: 5905 B
  exact without -flto (the new attributes are size-invariant in the
  mode where they should be no-ops).  With -flto: **5905 → 5890 B
  (-15 B, -0.25 %)**.  MAME boot smoke (mame-test 77-track sweep):
  baseline `DISK=602B ERR=0` and -flto `DISK=5BDD ERR=0` both PASS.
  Signature at offset 0x08 = " RC702" preserved.  `+static-stack`
  idempotent under LTO (no spills, no BSS layout changes).
- The earlier -143 B claim was an illusion caused by boot_header being
  DCE'd from a broken bootloader; real saving is -15 B.
- cpnos PROM1 stays non-LTO: 3-TU cross-file surface too small (±1 B
  noise; not worth the build-flag asymmetry).
- CLAUDE.md BIOS headline updated 5905 → 5890.

**#87 partial** (rc700@6d9de0d):
- 3 symbols marked `static` after 35-symbol audit:
  - `impl_const` (resident.c, same-file inline-asm caller),
  - `snios_sndmsg_force` (snios_c.c, same-file C caller),
  - `disable_interrupts` (transport_pio.c, zero callers — now DCE'd).
- Uncompressed payload **byte-identical** before/after (2016 B
  exact); compressed +2 B = pure ZX0 noise.
- SDCC dual-compile clean.
- cpnos-polypascal-test PASS at 51.25 s.
- 8 single-cross-TU-caller candidates deferred (move-and-static needs
  per-symbol section-attribute work).

**Commits, all pushed:**
- llvm-z80: 978fca2, b5dc3b4 (Tier I row), 65cb811 (rename),
  d953651 (design doc), 6839ebc (POC), …
- rc700-gensmedet: bdd2af2, bcc9f97, 6d9de0d (#87 partial),
  60a2769 (server.py rm), d35fbdc (server.py deps rm),
  68c29b9 (#101 doc fix), 6839ebc, dc7ceb9 (timeline).
- Workspace: 6c149e9 (CLAUDE.md BIOS 5890), afcf18c (#87 bump), and
  intermediate session bumps.

**Rules used / reinforced this session:**
- `[[feedback_no_op_control_measurement]]` — every codegen-touching
  change shipped with a baseline no-op rebuild proving uncompressed
  byte-identity (catches ZX0 compression noise).
- `[[feedback_no_commit_first_version]]` — BIOS LTO + #87 statics both
  gated on MAME oracle (mame-test, polypascal-test) before commit.
- `[[feedback_revalidate_concern_not_filename]]` — drove the rc700
  re-evaluation (file-path drift ≠ concern dead; verified each at
  current source).
- `[[feedback_state_certainty]]` — corrected the -143 B BIOS LTO claim
  to -15 B real after discovering the prior measurement was on a
  broken-bootloader build.
- `[[feedback_dual_compiler_test]]` — every cpnos source change built
  with both clang and SDCC before commit.
- `[[feedback_explain_before_filing]]` — bug 5 v2 reframe + #223
  fork-internal filing all explained in chat before action.
- `[[feedback_avr_density_oracle]]` — bug 3 dropped from upstream queue
  via AVR oracle (no in-tree target sets the threshold to zero).

**Next session hooks** — left ready for the user:
- `tasks/upstream-memset-pattern-issue-body.md` (RFC for llvm-z80/
  llvm-z80, awaiting per-filing go-ahead).
- `tasks/upstream-5bug/draft-bug5-v2.md` (consistency-led reframe,
  awaiting per-filing go-ahead).
- 8 #87 deferred symbols (clear_screen, enable_im2, get_img_base,
  impl_conin, isr_noop, set_i_reg, transport_recv_byte,
  transport_send_byte) — wait for broader cpnos cleanup.
