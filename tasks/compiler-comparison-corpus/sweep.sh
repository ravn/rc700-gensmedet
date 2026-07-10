#!/usr/bin/env bash
# Compiler-comparison corpus sweep: each benchmark × (llvm-z80, zsdcc, dcc,
# llvm-z88dk, xcc, ez80clang) at production-like flags.  Writes machine-readable
# TSV + markdown summary.  Mirrors aes256-corpus/flag_sweep.sh's harness style.
#
# Per-benchmark each compiler writes a 7-byte sentinel at 0xC000:
#   [0..1] actual, [2..3] expected, [4] match (0/1), [5] reserved, [6] 0xA5.
#
# Verifier requires v[4]==1 (computation correct) AND v[6]==0xA5 (clean halt).
#
# Usage: ./sweep.sh                   # all benchmarks, all compilers
#        BENCH=sieve ./sweep.sh       # filter
#        ONLY=llvm-z80 ./sweep.sh     # one compiler (llvm-z80|zsdcc|dcc|llvm-z88dk|xcc|ez80clang)
#        ONLY=both ./sweep.sh         # the original pair (llvm-z80+zsdcc)
#
# Each (bench, compiler) is measured at TWO optimization modes and the
# results.tsv / printed table show them side by side:
#   SIZE  = clang -Oz  / zsdcc --opt-code-size  / dcc dccpeep OFF
#   SPEED = clang -O2  / zsdcc --opt-code-speed / dcc dccpeep ON
# The only variable between the two cells is the opt level (clang also
# leaves LSR enabled in the SPEED cell); the production memory model
# (+static-stack), section-gc, and --sdcccall 1 are held constant.
# dcc has no -Oz/-O2 axis -- its only knob is the dccpeep peephole pass
# (improves BOTH size and speed), so size=peep-off, speed=peep-on.
#
# dcc caveats (noted because its cells aren't apples-to-apples with the
# freestanding clang/zsdcc binaries): dcc emits a CP/M .COM that BUNDLES
# the CP/M C runtime, so its `bin` bytes include RTL the others link out;
# and its `ts` includes a small fixed CRT-startup cost.  Use dcc numbers
# for trend, not byte-exact parity.

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
mkdir -p sweep
cd sweep

LLVM_Z80=/Users/ravn/z80/llvm-z80/build-macos
CLANG=$LLVM_Z80/bin/clang
LLDLD=$LLVM_Z80/bin/ld.lld
LLVMOBJCOPY=$LLVM_Z80/bin/llvm-objcopy
LLVMNM=$LLVM_Z80/bin/llvm-nm
Z88DK=/Users/ravn/z80/z88dk
TICKS=$Z88DK/bin/z88dk-ticks
ZCC_ENV="ZCCCFG=$Z88DK/lib/config PATH=$Z88DK/bin:$PATH"
ZCC="$Z88DK/bin/zcc"

# dcc (David Lee's CP/M C89 compiler) -- the third "friend".  Built in-tree
# (dcc/m.sh).  The compile step is native; the M80/L80 assemble+link step
# runs inside VirtualCpm.jar (a CP/M emulator) which needs Java 21.  These
# paths are committed macbook-style and sed-rewritten by the sonnyboy runner;
# DCC_JAVA is overridden via env there (system java is too old).  The actual
# build recipe lives in build_dcc_corpus.sh (kept separate because it is a
# multi-stage CP/M toolchain dance).
DCC_DIR=/Users/ravn/z80/dcc
VCPM_JAR=/Users/ravn/z80/cpnet-z80/tools/VirtualCpm.jar
DCC_JAVA="${DCC_JAVA:-java}"   # must be Java 21+ (VirtualCpm.jar is class-file v65)

# xcc (XYZ Suite Z80 C compiler, retro-vault/xyz) -- the FIFTH "friend".
# An independent SDCC-ABI compiler that emits real CP/M .COM; measured via
# the same 64 KB image + ticks 0xC000 sentinel path as the dcc/z88clang
# lanes.  NOT a submodule yet (evaluation) -- staged by setup_xcc.sh at the
# stable XCC_PREFIX symlink.  Recipe + beta libc-workaround: XCC_ORACLE_SETUP.md.
XCC_PREFIX="${XCC_PREFIX:-/Users/ravn/z80/xyz-eval/xcc-current}"

# ez80clang (CEdev ez80-clang, CE-Programming/llvm-project) -- the SIXTH
# "friend", a CODE-QUALITY comparison oracle only.  A SelectionDAG eZ80 LLVM
# fork (distinct from ravn/llvm-z80's GlobalISel backend); its `-triple z80`
# sub-target emits genuine 16-bit z80 code, driven by z88dk's own
# `zcc +cpm -compiler=ez80clang` (build_ez80clang_corpus.sh, same .COM +
# ticks 0xC000 sentinel path as the dcc/z88clang/xcc lanes -- bin bundles the
# z88dk RTL, read as trend not parity).  z88dk makes NO changes to clang: you
# copy CEdev/bin/ez80-clang into z88dk/bin (setup_ez80clang.sh symlinks the
# staged CEDEV_PREFIX copy).  CEdev v15.0 needs two clang_rules.1 additions
# (dotted .section, `rb ($$ - $) and N` align) -- see EZ80CLANG_ORACLE_SETUP.md.
CEDEV_PREFIX="${CEDEV_PREFIX:-/Users/ravn/z80/cedev-eval/CEdev}"

# llvm-z80 production flags (matches aes256-corpus 09_Oz_prod_like).
# NOTE the in-tree disablePass(LICM/CSE) is already in effect via the
# Z80 backend — passing `-mllvm -disable-machine-licm/cse` here is
# belt-and-suspenders.  The investigation toggles (#23) use
# `-mllvm -z80-enable-licm` / `-mllvm -z80-enable-cse` which override
# the in-tree disable.  CLANG_EXTRA env var injects extra flags into
# every cell; used by the per-investigation wrapper scripts.
LLVM_FLAGS=(-Oz -Xclang -target-feature -Xclang +static-stack
            -mllvm -disable-lsr
            -ffunction-sections -fdata-sections)
# Speed-optimized counterpart of LLVM_FLAGS: -O2 instead of -Oz, and LSR
# is left ENABLED (the size cell passes -disable-lsr).  Session #75's
# isLegalAddImmediate TTI made LSR a net win, so the speed cell wants it.
# +static-stack and section-gc are the production memory model and are
# orthogonal to size/speed, so they stay identical in both cells.
LLVM_FLAGS_SPEED=(-O2 -Xclang -target-feature -Xclang +static-stack
            -ffunction-sections -fdata-sections)
# Historical belt-and-suspenders flag `-mllvm -disable-machine-licm/cse`
# was here; removed 2026-06-08 because the Z80 backend's in-tree
# disablePass(LICM/CSE) already covers it (Z80PassConfig), and the
# explicit flag would defeat the `-mllvm -z80-enable-licm/-cse`
# investigation toggle.
if [ -n "${CLANG_EXTRA:-}" ]; then
  # split on whitespace into array elements
  read -r -a CLANG_EXTRA_ARR <<< "$CLANG_EXTRA"
  LLVM_FLAGS+=("${CLANG_EXTRA_ARR[@]}")
  LLVM_FLAGS_SPEED+=("${CLANG_EXTRA_ARR[@]}")
fi
# Optional cell-label suffix so cells with different flag sets don't
# clash on prefix names in sweep/.  Default empty.
CELL_TAG="${CELL_TAG:-}"

# zsdcc production flags (matches aes256-corpus 01_baseline_prod)
ZSDCC_FLAGS=(+z80 -compiler=sdcc -clib=sdcc_iy
             --opt-code-size -SO3
             '-Cs--sdcccall 1' '-Cs--disable-warning 296'
             '-Cs--max-allocs-per-node 25000'
             '-Cs--fomit-frame-pointer'
             -create-app)
# Speed-optimized counterpart of ZSDCC_FLAGS: --opt-code-speed instead of
# --opt-code-size; everything else (sdcccall 1, -SO3, alloc budget) held
# constant so the opt objective is the only variable.
ZSDCC_FLAGS_SPEED=(+z80 -compiler=sdcc -clib=sdcc_iy
             --opt-code-speed -SO3
             '-Cs--sdcccall 1' '-Cs--disable-warning 296'
             '-Cs--max-allocs-per-node 25000'
             '-Cs--fomit-frame-pointer'
             -create-app)

BENCHES=(sieve fannkuch pi word_fill licm_pessimize)
# Filtered by env-var BENCH if set
if [ -n "${BENCH:-}" ]; then BENCHES=("$BENCH"); fi
ONLY="${ONLY:-all}"

# want <compiler> -> succeed if this compiler should run under $ONLY.
#   all  = every lane (llvm-z80, zsdcc, dcc, llvm-z88dk, xcc, ez80clang; default)
#   both = the original pair (llvm-z80 + zsdcc), kept for back-compat
#   <name> = just that one (e.g. ONLY=ez80clang)
want() {
  case "$ONLY" in
    all)  return 0 ;;
    both) case "$1" in llvm-z80|zsdcc) return 0 ;; *) return 1 ;; esac ;;
    "$1") return 0 ;;
    *)    return 1 ;;
  esac
}

# Known-failing (bench, compiler) cells -- pre-existing, documented, deferred
# upstream investigation.  See tasks/zsdcc-bench-divergence-2026-06-08.md for
# the per-bench writeup (clang return vs zsdcc return, hypothesis, repro
# strategy, upstream filing prep).  Convention: FAIL -> XFAIL (silent), PASS
# on a known-failing cell -> XPASS (loud -- upstream may have landed a fix).
#
# dcc note (NOT XFAILs): dcc *exits 1* on two benches while still emitting
# CORRECT code -- its parser hits a recoverable diagnostic but recovers and
# compiles the rest.  build_dcc_corpus.sh therefore ignores dcc's exit code
# and gates purely on the 0xC000 sentinel oracle (result == reference):
#   - pi: empty object-like macro (NOINLINE -> nothing) trips dcc's pp, but
#     the computed pi value matches the llvm-z80 reference exactly -> PASS.
#   - licm_pessimize: dcc can't parse the cast-expression lvalue
#     `*(volatile T*)0xC100 = x`; it drops that volatile store (misparses it
#     as a read).  The 0xC000 RESULT is still correct -> PASS, BUT the
#     dropped store means dcc's licm cycle count is NOT a like-for-like
#     pessimization measurement (it elides the optimizer-defeat write the
#     bench relies on).  Read dcc's licm timing with that caveat.
# Cells keyed bench:compiler fail in BOTH modes; bench:compiler:mode fails
# only in that mode.  (fannkuch:llvm-z80:speed WAS an XFAIL for the clang -O2
# branch-folder miscompile ravn/llvm-z80#247 -- FIXED 2026-07-01 by teaching
# MachineOperand MO_MCSymbol isIdenticalTo/hash to compare the offset, so both
# modes are now hard PASS gates.)
#
# xcc note: fannkuch:xcc XFAILs in BOTH modes -- xcc (beta) miscompiles
# fannkuchredux and returns 0x0000 instead of 0x10E4 (ts collapses to ~8.7k,
# the flip loop never runs).  Independent of the llvm-z80#247 fix; a genuine
# xcc beta codegen bug (candidate to file upstream against retro-vault/xyz).
# NOTE: fannkuch:zsdcc + pi:zsdcc are NOT listed here -- they are SKIPPED
# entirely (see SKIP_CELL below), so they never produce an XFAIL row.  Only
# fannkuch:xcc remains as a genuine run-it-and-XFAIL cell.
#
# ez80clang note (CODE-QUALITY oracle, added CEdev v15.0 2026-07-06): all three
# failing ez80clang cells are SKIPPED (see SKIP_CELL), not XFAIL-run -- ez80clang
# is a code-quality oracle, so a cell that can't produce correct code produces
# no useful size/speed datapoint, and two of them hang for the full 300 s ticks
# alarm.  Tracked for fixing in rc700-gensmedet#122.  Reasons:
#   - pi:ez80clang: the 32-bit libcall names (__llmulu / __llshru / __ldivu)
#     are now provided in z88dk's z80 clib (ravn/z88dk@a337eb0c49), so pi LINKS.
#     Remaining blocker is an ez80-clang codegen bug: at clang -O1/-O2/-O3
#     (-triple z80) the IX frame pointer is allocated as a scratch GPR, so a
#     spilled long's (ix - N) slot is stored/reloaded with the wrong base and
#     the value reads as garbage.  Filed upstream CE-Programming/llvm-project#50
#     (see rc700-gensmedet#124).  NOT a z88dk bug; nothing to re-run here.
#   - sieve:ez80clang + fannkuch:ez80clang: CE's z80 sub-target miscompiles
#     non-trivial 16-bit loops -- a codegen cliff (sieve at array size >=~450:
#     the emitted binary SHRINKS yet the program hangs / wild-jumps).  Each
#     hang burns the full 300 s alarm.  Symptom verified; not root-caused.
#   word_fill + licm_pessimize compile to correct code and DO contribute
#   code-quality (size/speed) datapoints.
EXPECTED_FAIL=" fannkuch:xcc "
is_expected_fail() {
  # $1=bench $2=compiler $3=mode(size|speed)
  case "$EXPECTED_FAIL" in
    *" $1:$2:$3 "*) return 0 ;;
    *" $1:$2 "*)    return 0 ;;
    *) return 1 ;;
  esac
}

# Cells to SKIP ENTIRELY (not even attempted) -- distinct from EXPECTED_FAIL,
# which still RUNS the cell and records XFAIL.  Use this when a cell fails for
# a known, characterised reason that adds no signal to re-run every sweep.
#
# fannkuch:zsdcc + pi:zsdcc: the zsdcc lane builds --sdcccall 1 (register ABI)
# but links z88dk's default-convention (--sdcccall 0) stdlib, whose signed
# div/mod runtime helpers (__modsint for fannkuch; __divulong/__modulong for
# pi) return in a register the --sdcccall 1 caller never reads -> silent 0.
# z88dk warns about exactly this (warning 296, suppressed by sweep).  Root
# cause CONFIRMED + red-green validated (see zsdcc-bench-divergence-2026-06-08.md
# and zsdcc-repro/modsint_sdcccall1.c); it's a build-config/stdlib-ABI mismatch,
# NOT a compiler bug, so there's nothing to catch by re-running -> skip.
SKIP_CELL=" fannkuch:zsdcc pi:zsdcc sieve:ez80clang fannkuch:ez80clang pi:ez80clang "
is_skipped() {
  # $1=bench $2=compiler
  case "$SKIP_CELL" in
    *" $1:$2 "*) return 0 ;;
    *) return 1 ;;
  esac
}
classify_verify() {
  # $1=bench $2=compiler $3=rc (ticks exit code) $4=mode(size|speed)
  local b=$1 c=$2 rc=$3 mode=${4:-}
  if is_expected_fail "$b" "$c" "$mode"; then
    case "$rc" in
      0) printf 'XPASS(unexpected_pass)' ;;
      *) printf 'XFAIL(exit=%s)' "$rc" ;;
    esac
  else
    case "$rc" in
      0) printf 'PASS' ;;
      *) printf 'FAIL(exit=%s)' "$rc" ;;
    esac
  fi
}

TSV="results.tsv"
printf 'bench\tcompiler\tsize_bin\tsize_text\tsize_ts\tsize_verify\tspeed_bin\tspeed_text\tspeed_ts\tspeed_verify\n' > "$TSV"

[ -f reset_clang.s ] || ln -sf ../sweep/reset_clang.s reset_clang.s 2>/dev/null || true
[ -f clang.ld ] || ln -sf ../sweep/clang.ld clang.ld 2>/dev/null || true

# Compile + link + measure ONE llvm-z80 cell at a given opt mode.
# $1=bench  $2=opt(size|speed).  Echoes "bin<TAB>text<TAB>tstates<TAB>verify"
# (no trailing newline).  Aborts under set -e on a clang/link failure, the
# same as the original single-mode path did.
measure_llvm_z80() {
  local bench=$1 opt=$2
  local src=../bench_${bench}.c
  local main=../test_main.c
  local prefix=llvm_z80_${opt}_${bench}
  local -a flags
  if [ "$opt" = speed ]; then flags=("${LLVM_FLAGS_SPEED[@]}"); else flags=("${LLVM_FLAGS[@]}"); fi
  rm -f ${prefix}_*.o ${prefix}.elf ${prefix}.bin ${prefix}.filled.bin ${prefix}.ram 2>/dev/null || true

  $CLANG --target=z80 -nostdlib -ffreestanding -std=c89 -Wno-deprecated-non-prototype \
    "${flags[@]}" -c ../sweep/reset_clang.s -o ${prefix}_reset.o
  $CLANG --target=z80 -nostdlib -ffreestanding -std=c89 -Wno-deprecated-non-prototype \
    "${flags[@]}" -c "$src" -o ${prefix}_bench.o
  $CLANG --target=z80 -nostdlib -ffreestanding -std=c89 -Wno-deprecated-non-prototype \
    "${flags[@]}" -c "$main" -o ${prefix}_main.o
  $LLDLD -T ../sweep/clang.ld --gc-sections -o ${prefix}.elf \
    ${prefix}_reset.o ${prefix}_bench.o ${prefix}_main.o \
    $LLVM_Z80/lib/z80/z80_rt.a
  $LLVMOBJCOPY -O binary ${prefix}.elf ${prefix}.bin

  local bin text tstates verify rc out
  bin=$(wc -c < ${prefix}.bin | tr -d ' ')
  text=$($LLVMNM --print-size --size-sort ${prefix}_bench.o 2>/dev/null | \
    python3 -c "import sys; t=sum(int(p[1],16) for p in (l.split() for l in sys.stdin) if len(p)>=4 and p[2] in 'tT'); print(t)")
  # test_main.c traps to ticks via ED FE after writing the sentinel; ticks
  # prints "Ticks: <N>" to stdout and exits with L (Unix: 0=PASS, 1=FAIL).
  # `|| rc=$?` shields set -e from non-zero (FAIL) exits.
  rc=0
  out=$(perl -e 'alarm 90; exec @ARGV' \
    $TICKS -mz80 -counter 200000000 ${prefix}.bin 2>&1) || rc=$?
  tstates=$(printf '%s\n' "$out" | awk '/^Ticks:/{ts=$2} END{print ts}')
  verify=$(classify_verify "$bench" llvm-z80 "$rc" "$opt")
  : "${tstates:=?}"
  printf '%s\t%s\t%s\t%s' "$bin" "$text" "$tstates" "$verify"
}

run_llvm_z80() {
  local bench=$1
  local sres pres sbin stext sts sver pbin ptext pts pver
  sres=$(measure_llvm_z80 "$bench" size)
  pres=$(measure_llvm_z80 "$bench" speed)
  IFS=$'\t' read -r sbin stext sts sver <<< "$sres"
  IFS=$'\t' read -r pbin ptext pts pver <<< "$pres"
  printf '%s\tllvm-z80\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$bench" "$sbin" "$stext" "$sts" "$sver" "$pbin" "$ptext" "$pts" "$pver" >> "$TSV"
  printf '%-15s llvm-z80  size[bin=%5s ts=%10s %s]  speed[bin=%5s ts=%10s %s]\n' \
    "$bench" "$sbin" "$sts" "$sver" "$pbin" "$pts" "$pver"
}

# Compile + measure ONE zsdcc cell at a given opt mode.  Compile failures are
# non-fatal (guarded with `|| true`): a missing .bin yields a COMPILE_ERROR
# tuple so the other mode / compiler still runs.
measure_zsdcc() {
  local bench=$1 opt=$2
  local src=../bench_${bench}.c
  local main=../test_main.c
  local prefix=zsdcc_${opt}_${bench}
  local -a flags
  if [ "$opt" = speed ]; then flags=("${ZSDCC_FLAGS_SPEED[@]}"); else flags=("${ZSDCC_FLAGS[@]}"); fi
  rm -f ${prefix}* 2>/dev/null || true

  env $ZCC_ENV $ZCC "${flags[@]}" -o $prefix "$src" "$main" >/dev/null 2>&1 || true
  if [ ! -f ${prefix}.bin ]; then
    printf 'FAIL\tn/a\t-\tCOMPILE_ERROR'
    return
  fi

  local bin tstates verify rc out
  bin=$(wc -c < ${prefix}.bin | tr -d ' ')
  # text size not extracted for SDCC (different map format); see word_fill
  # baseline doc for the manual counting approach when needed.
  rc=0
  out=$(perl -e 'alarm 90; exec @ARGV' \
    $TICKS -mz80 -counter 200000000 ${prefix}.bin 2>&1) || rc=$?
  tstates=$(printf '%s\n' "$out" | awk '/^Ticks:/{ts=$2} END{print ts}')
  verify=$(classify_verify "$bench" zsdcc "$rc" "$opt")
  : "${tstates:=?}"
  printf '%s\tn/a\t%s\t%s' "$bin" "$tstates" "$verify"
}

run_zsdcc() {
  local bench=$1
  local sres pres sbin stext sts sver pbin ptext pts pver
  sres=$(measure_zsdcc "$bench" size)
  pres=$(measure_zsdcc "$bench" speed)
  IFS=$'\t' read -r sbin stext sts sver <<< "$sres"
  IFS=$'\t' read -r pbin ptext pts pver <<< "$pres"
  printf '%s\tzsdcc\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$bench" "$sbin" "$stext" "$sts" "$sver" "$pbin" "$ptext" "$pts" "$pver" >> "$TSV"
  printf '%-15s zsdcc     size[bin=%5s ts=%10s %s]  speed[bin=%5s ts=%10s %s]\n' \
    "$bench" "$sbin" "$sts" "$sver" "$pbin" "$pts" "$pver"
}

# Compile + measure ONE dcc cell at a given opt mode by delegating to
# build_dcc_corpus.sh (which drives dcc -> M80/L80 under VirtualCpm.jar and
# then z88dk-ticks).  size=dccpeep OFF, speed=dccpeep ON.  build_dcc_corpus.sh
# emits a `bin<TAB>text<TAB>ts<TAB>{PASS|FAIL|COMPILE_ERROR}` tuple; we map
# that verdict to an rc (PASS=0, COMPILE_ERROR=2, else 1) and re-run it
# through classify_verify so the XFAIL bookkeeping matches the other two
# compilers.  The DCC_*/JAVA env are exported so the sed-rewritten sweep.sh
# paths (and the sonnyboy Java-21 override) propagate into the child script.
measure_dcc() {
  local bench=$1 opt=$2
  local raw bin text ts verify rc
  raw=$(DCC_DIR="$DCC_DIR" VCPM_JAR="$VCPM_JAR" Z88DK="$Z88DK" TICKS="$TICKS" \
        JAVA="$DCC_JAVA" "$HERE/build_dcc_corpus.sh" "$bench" "$opt" 2>/dev/null) || true
  IFS=$'\t' read -r bin text ts verify <<< "$raw"
  case "$verify" in
    PASS)          rc=0 ;;
    COMPILE_ERROR) rc=2 ;;
    *)             rc=1 ;;   # FAIL, crash, or empty output
  esac
  verify=$(classify_verify "$bench" dcc "$rc" "$opt")
  : "${bin:=FAIL}"; : "${text:=n/a}"; : "${ts:=-}"
  printf '%s\t%s\t%s\t%s' "$bin" "$text" "$ts" "$verify"
}

run_dcc() {
  local bench=$1
  local sres pres sbin stext sts sver pbin ptext pts pver
  sres=$(measure_dcc "$bench" size)
  pres=$(measure_dcc "$bench" speed)
  IFS=$'\t' read -r sbin stext sts sver <<< "$sres"
  IFS=$'\t' read -r pbin ptext pts pver <<< "$pres"
  printf '%s\tdcc\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$bench" "$sbin" "$stext" "$sts" "$sver" "$pbin" "$ptext" "$pts" "$pver" >> "$TSV"
  printf '%-15s dcc       size[bin=%5s ts=%10s %s]  speed[bin=%5s ts=%10s %s]\n' \
    "$bench" "$sbin" "$sts" "$sver" "$pbin" "$pts" "$pver"
}

# The FOURTH friend: ravn/llvm-z80 clang linked against z88dk's CP/M runtime
# via the copt bridge (build_z88clang_corpus.sh).  Like dcc it emits a real
# CP/M .COM that bundles the RTL and verifies via the 0xC000 sentinel from a
# ticks RAM dump, so bin/text are not byte-comparable to the freestanding
# llvm-z80 cell -- read it as a "does the z88dk-clib path work + its cost"
# trend, not size parity.  size=-Oz / speed=-O2 (mirrors the llvm-z80 cell).
measure_z88clang() {
  local bench=$1 opt=$2
  local raw bin text ts verify rc
  raw=$(LLVM_Z80="$LLVM_Z80" CLANG="$CLANG" Z88DK="$Z88DK" TICKS="$TICKS" \
        "$HERE/build_z88clang_corpus.sh" "$bench" "$opt" 2>/dev/null) || true
  IFS=$'\t' read -r bin text ts verify <<< "$raw"
  case "$verify" in
    PASS)          rc=0 ;;
    COMPILE_ERROR) rc=2 ;;
    *)             rc=1 ;;
  esac
  verify=$(classify_verify "$bench" llvm-z88dk "$rc" "$opt")
  : "${bin:=FAIL}"; : "${text:=n/a}"; : "${ts:=-}"
  printf '%s\t%s\t%s\t%s' "$bin" "$text" "$ts" "$verify"
}

run_z88clang() {
  local bench=$1
  local sres pres sbin stext sts sver pbin ptext pts pver
  sres=$(measure_z88clang "$bench" size)
  pres=$(measure_z88clang "$bench" speed)
  IFS=$'\t' read -r sbin stext sts sver <<< "$sres"
  IFS=$'\t' read -r pbin ptext pts pver <<< "$pres"
  printf '%s\tllvm-z88dk\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$bench" "$sbin" "$stext" "$sts" "$sver" "$pbin" "$ptext" "$pts" "$pver" >> "$TSV"
  printf '%-15s llvm-z88dk size[bin=%5s ts=%10s %s]  speed[bin=%5s ts=%10s %s]\n' \
    "$bench" "$sbin" "$sts" "$sver" "$pbin" "$pts" "$pver"
}

# The FIFTH friend: xcc (XYZ Suite, retro-vault/xyz), an independent SDCC-ABI
# Z80 C compiler.  Emits a real CP/M .COM linked against its own libc/CP/M
# runtime, measured via the SAME 64 KB image + ticks 0xC000 sentinel path as
# the dcc/z88clang lanes (build_xcc_corpus.sh), so bin bundles the RTL and is
# NOT byte-comparable to the freestanding llvm-z80 cell -- read as a trend.
# size=-Os / speed=-Of.  Requires setup_xcc.sh (see XCC_ORACLE_SETUP.md).
measure_xcc() {
  local bench=$1 opt=$2
  local raw bin text ts verify rc
  raw=$(XCC_PREFIX="$XCC_PREFIX" Z88DK="$Z88DK" TICKS="$TICKS" \
        "$HERE/build_xcc_corpus.sh" "$bench" "$opt" 2>/dev/null) || true
  IFS=$'\t' read -r bin text ts verify <<< "$raw"
  case "$verify" in
    PASS)          rc=0 ;;
    COMPILE_ERROR) rc=2 ;;
    *)             rc=1 ;;
  esac
  verify=$(classify_verify "$bench" xcc "$rc" "$opt")
  : "${bin:=FAIL}"; : "${text:=n/a}"; : "${ts:=-}"
  printf '%s\t%s\t%s\t%s' "$bin" "$text" "$ts" "$verify"
}

run_xcc() {
  local bench=$1
  local sres pres sbin stext sts sver pbin ptext pts pver
  sres=$(measure_xcc "$bench" size)
  pres=$(measure_xcc "$bench" speed)
  IFS=$'\t' read -r sbin stext sts sver <<< "$sres"
  IFS=$'\t' read -r pbin ptext pts pver <<< "$pres"
  printf '%s\txcc\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$bench" "$sbin" "$stext" "$sts" "$sver" "$pbin" "$ptext" "$pts" "$pver" >> "$TSV"
  printf '%-15s xcc       size[bin=%5s ts=%10s %s]  speed[bin=%5s ts=%10s %s]\n' \
    "$bench" "$sbin" "$sts" "$sver" "$pbin" "$pts" "$pver"
}

# The SIXTH friend: ez80clang (CEdev ez80-clang, CODE-QUALITY oracle only).
# Same .COM + ticks 0xC000 sentinel path as the dcc/z88clang/xcc lanes
# (build_ez80clang_corpus.sh); bin bundles the z88dk RTL, read as trend.
# size=--opt-code-size (-Oz) / speed=default (-O3).  Requires ez80-clang on
# PATH (setup_ez80clang.sh); see EZ80CLANG_ORACLE_SETUP.md.
measure_ez80clang() {
  local bench=$1 opt=$2
  local raw bin text ts verify rc
  raw=$(Z88DK="$Z88DK" TICKS="$TICKS" \
        "$HERE/build_ez80clang_corpus.sh" "$bench" "$opt" 2>/dev/null) || true
  IFS=$'\t' read -r bin text ts verify <<< "$raw"
  case "$verify" in
    PASS)          rc=0 ;;
    COMPILE_ERROR) rc=2 ;;
    *)             rc=1 ;;
  esac
  verify=$(classify_verify "$bench" ez80clang "$rc" "$opt")
  : "${bin:=FAIL}"; : "${text:=n/a}"; : "${ts:=-}"
  printf '%s\t%s\t%s\t%s' "$bin" "$text" "$ts" "$verify"
}

run_ez80clang() {
  local bench=$1
  local sres pres sbin stext sts sver pbin ptext pts pver
  sres=$(measure_ez80clang "$bench" size)
  pres=$(measure_ez80clang "$bench" speed)
  IFS=$'\t' read -r sbin stext sts sver <<< "$sres"
  IFS=$'\t' read -r pbin ptext pts pver <<< "$pres"
  printf '%s\tez80clang\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$bench" "$sbin" "$stext" "$sts" "$sver" "$pbin" "$ptext" "$pts" "$pver" >> "$TSV"
  printf '%-15s ez80clang size[bin=%5s ts=%10s %s]  speed[bin=%5s ts=%10s %s]\n' \
    "$bench" "$sbin" "$sts" "$sver" "$pbin" "$pts" "$pver"
}

echo "Each (bench, compiler) is measured twice: SIZE (clang -Oz / zsdcc"
echo "--opt-code-size / dcc dccpeep-off) and SPEED (clang -O2 / zsdcc"
echo "--opt-code-speed / dcc dccpeep-on)."
echo "bin = binary bytes, ts = z80 t-states (lower is faster)."
echo "Note: dcc .COM bundles the CP/M RTL (bin not byte-comparable) and its"
echo "ts includes a small fixed CRT-startup cost; read dcc as trend, not parity."
echo
# xcc is optional (evaluation, not a submodule).  Skip its lane with a single
# hint if the toolchain isn't staged, rather than emitting 10 COMPILE_ERROR
# rows.  setup_xcc.sh installs it; XCC_ORACLE_SETUP.md has the details.
XCC_OK=1
if want xcc && [ ! -x "$XCC_PREFIX/bin/xcc" ]; then
  XCC_OK=0
  echo "Note: xcc not found at $XCC_PREFIX/bin/xcc -- skipping the xcc lane."
  echo "      Run ./setup_xcc.sh to add it (see XCC_ORACLE_SETUP.md)."
  echo
fi
# ez80clang is a code-quality oracle (evaluation, not a submodule).  Skip its
# lane with one hint if ez80-clang isn't on PATH.  setup_ez80clang.sh stages
# it; EZ80CLANG_ORACLE_SETUP.md has the details.
EZ80CLANG_OK=1
if want ez80clang && ! command -v ez80-clang >/dev/null 2>&1 \
   && [ ! -x "$Z88DK/bin/ez80-clang" ]; then
  EZ80CLANG_OK=0
  echo "Note: ez80-clang not found (PATH or $Z88DK/bin) -- skipping the ez80clang lane."
  echo "      Run ./setup_ez80clang.sh to add it (see EZ80CLANG_ORACLE_SETUP.md)."
  echo
fi
for b in "${BENCHES[@]}"; do
  want llvm-z80   && ! is_skipped "$b" llvm-z80   && run_llvm_z80 "$b"
  want zsdcc      && ! is_skipped "$b" zsdcc      && run_zsdcc "$b"
  want dcc        && ! is_skipped "$b" dcc        && run_dcc "$b"
  want llvm-z88dk && ! is_skipped "$b" llvm-z88dk && run_z88clang "$b"
  want xcc        && [ "$XCC_OK" = 1 ] && ! is_skipped "$b" xcc && run_xcc "$b"
  want ez80clang  && [ "$EZ80CLANG_OK" = 1 ] && ! is_skipped "$b" ez80clang && run_ez80clang "$b"
done

echo
echo "Wrote sweep/$TSV"
python3 "$HERE/gen_results_html.py" || echo "warn: results.html not regenerated" >&2
