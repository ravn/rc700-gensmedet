#!/usr/bin/env bash
# Sweep clang flag combinations for AES-256 size + speed.
#
# Each config builds a clean clang binary, runs it in z88dk-ticks to the
# post-main HALT (via -end <_done addr>), and reports
# {bin size, aes256.c text size, tstates, PASS/FAIL}.
#
# Writes a machine-readable TSV to sweep/results.tsv and a human-
# readable markdown table to clang-flag-sweep.md. Re-running updates
# both — diff against git to catch regressions.
#
# Baseline is "-Oz only" (no production knobs). Each subsequent config
# adds or replaces flags from production cpnos-rom (which has battle-
# tested these for size at the BIOS scale, but on different code shapes).

set -euo pipefail

CLANG=/Users/ravn/z80/llvm-z80/build-macos/bin/clang
LLDLD=/Users/ravn/z80/llvm-z80/build-macos/bin/ld.lld
LLVMNM=/Users/ravn/z80/llvm-z80/build-macos/bin/llvm-nm
LLVMOBJCOPY=/Users/ravn/z80/llvm-z80/build-macos/bin/llvm-objcopy
TICKS=/Users/ravn/z80/z88dk/bin/z88dk-ticks

HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
mkdir -p sweep
cd sweep

# Reuse reset_clang.s and clang.ld from parent build (regenerate if absent).
if [ ! -e reset_clang.s ]; then
  printf '%s\n' '    .section .reset, "ax"' '    .global _start' '_start:' \
    '    di' '    ld sp, 0xFFFE' '    call _main' '_done:' '    halt' '    jp _done' \
    > reset_clang.s
fi
if [ ! -e clang.ld ]; then
  printf '%s\n' 'ENTRY(_start)' 'MEMORY {' '  RAM (rwx) : ORIGIN = 0x0000, LENGTH = 0xC000' '}' \
    'SECTIONS {' '  .text 0x0000 : { *(.reset) *(.text*) } > RAM' \
    '  .rodata : { *(.rodata*) } > RAM' '  .data : { *(.data*) } > RAM' \
    '  .bss : { *(.bss*) *(COMMON) } > RAM' '}' > clang.ld
fi

# TSV header
TSV=results.tsv
printf 'label\tbin\taes_text\ttstates\tverify\tflags\n' > "$TSV"

build_and_measure() {
  local label=$1; shift
  local cflags="$*"
  local prefix="${label}"

  $CLANG --target=z80 -nostdlib -ffreestanding \
    -std=c89 -Wno-deprecated-non-prototype \
    $cflags -c reset_clang.s -o ${prefix}_reset.o 2>/dev/null
  $CLANG --target=z80 -nostdlib -ffreestanding \
    -std=c89 -Wno-deprecated-non-prototype \
    $cflags -c ../aes256.c -o ${prefix}_aes.o 2>/dev/null
  $CLANG --target=z80 -nostdlib -ffreestanding \
    -std=c89 -Wno-deprecated-non-prototype \
    $cflags -c ../test_main.c -o ${prefix}_main.o 2>/dev/null

  local ldextra=""
  if echo "$cflags" | grep -q -- "-ffunction-sections"; then
    ldextra="--gc-sections"
  fi
  $LLDLD -T clang.ld $ldextra -o ${prefix}.elf \
    ${prefix}_reset.o ${prefix}_aes.o ${prefix}_main.o 2>/dev/null
  $LLVMOBJCOPY -O binary ${prefix}.elf ${prefix}.bin

  local bin_size aes_text done_addr tstates verify
  # Note: bin_size is the REAL binary size before fill protection.
  bin_size=$(wc -c < ${prefix}.bin | tr -d ' ')
  aes_text=$($LLVMNM --print-size --size-sort ${prefix}_aes.o 2>/dev/null | \
    python3 -c "import sys; t=sum(int(p[1],16) for p in (l.split() for l in sys.stdin) if len(p)>=4 and p[2] in 'tT'); print(t)")
  done_addr=$($LLVMNM ${prefix}.elf | awk '$3=="_done"{print "0x" $1; exit}')

  # Pre-fill RAM beyond binary with `JP _done` pattern so any escape
  # into uninitialized memory immediately exits ticks via -end. See
  # fill_with_jp_done.py docstring for why this is needed (ticks bug:
  # default -start=0x0000 resets the tstate counter on PC wraparound,
  # so counter-limit never fires on a binary whose miscompile escapes
  # into the NOP-sled). Applied always — no perf cost for PASS configs.
  python3 ../fill_with_jp_done.py ${prefix}.bin ${prefix}.filled.bin "$done_addr"

  # Counter 100M: PASS configs run 14M-66M tstates so 100M is a safety
  # margin. Wallclock cap of 90s (perl alarm) is a fall-through guard;
  # with fill protection above, normal-completion exits in milliseconds.
  # `|| true` because perl-alarm kills ticks with SIGALRM (exit 142),
  # which would otherwise abort the whole sweep under `set -e`.
  tstates=$(perl -e 'alarm 90; exec @ARGV' \
    $TICKS -mz80 -end $done_addr -counter 100000000 \
    -output ${prefix}.ram ${prefix}.filled.bin 2>&1 | tail -1 || true)
  if [ ! -f ${prefix}.ram ]; then
    tstates="TIMEOUT"; verify="TIMEOUT(probable_miscompile)"
  else
    verify=$(python3 -c "d=open('${prefix}.ram','rb').read(); v=d[0xC000:0xC023]; \
      print('PASS' if v[16]==1 and v[33]==1 and v[34]==0xA5 else 'FAIL')")
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$label" "$bin_size" "$aes_text" "${tstates:-?}" "${verify:-?}" "$cflags" >> "$TSV"
  printf '%-32s bin=%5s aes_text=%5s tstates=%10s %s\n' \
    "$label" "$bin_size" "$aes_text" "$tstates" "$verify"
}

echo "Config                          bin_size aes_text  tstates    verify"
echo "------------------------------- -------- -------- ---------- ------"

build_and_measure "01_baseline_Oz"            -Oz
build_and_measure "02_Os"                     -Os
build_and_measure "03_O3"                     -O3
build_and_measure "04_O2"                     -O2
build_and_measure "05_Oz_static_stack"        -Oz -Xclang -target-feature -Xclang +static-stack
build_and_measure "06_Oz_no_licm_cse"         -Oz -mllvm -disable-machine-licm -mllvm -disable-machine-cse
build_and_measure "07_Oz_no_lsr"              -Oz -mllvm -disable-lsr
build_and_measure "08_Oz_gc_sections"         -Oz -ffunction-sections -fdata-sections
build_and_measure "09_Oz_prod_like"           -Oz -Xclang -target-feature -Xclang +static-stack \
                                              -mllvm -disable-lsr \
                                              -mllvm -disable-machine-licm \
                                              -mllvm -disable-machine-cse \
                                              -ffunction-sections -fdata-sections
build_and_measure "10_Oz_no_licm_cse_lsr"     -Oz -mllvm -disable-machine-licm \
                                              -mllvm -disable-machine-cse \
                                              -mllvm -disable-lsr
build_and_measure "11_Oz_no_licm_cse_gc"      -Oz -mllvm -disable-machine-licm \
                                              -mllvm -disable-machine-cse \
                                              -ffunction-sections -fdata-sections
# Closes ravn/llvm-z80#157: forces hasFP=true so spill slots use
# IX-relative (3B/access) instead of SP-relative recompute (5B/access).
build_and_measure "12_Oz_no_omit_fp"          -Oz -fno-omit-frame-pointer
build_and_measure "13_Oz_no_omit_fp_no_licm_cse_gc" \
                                              -Oz -fno-omit-frame-pointer \
                                              -mllvm -disable-machine-licm \
                                              -mllvm -disable-machine-cse \
                                              -ffunction-sections -fdata-sections

# Generate the markdown table.
cd ..
python3 <<'PY' > clang-flag-sweep.md
import csv, datetime, subprocess

rows = []
with open('sweep/results.tsv') as f:
    r = csv.DictReader(f, delimiter='\t')
    for row in r:
        rows.append(row)

baseline = {r['label']: r for r in rows}.get('01_baseline_Oz', None)
base_bin = int(baseline['bin']) if baseline else None
base_tstates = int(baseline['tstates']) if baseline else None

llvm_z80_head = subprocess.run(
    ['git', '-C', '/Users/ravn/z80/llvm-z80', 'rev-parse', '--short=12', 'HEAD'],
    capture_output=True, text=True).stdout.strip()

print('# clang flag sweep — AES-256 corpus')
print()
print(f'Last run: {datetime.date.today().isoformat()}  ')
print(f'llvm-z80 HEAD: `{llvm_z80_head}`')
print()
print('Reproducible via `make sweep` in this directory. Each row is a')
print('clean rebuild + run-to-HALT in `z88dk-ticks` with verification of')
print('the 35-byte result vector at 0xC000. FAIL means at least one of')
print('the three sentinels (enc=01, dec=01, end=a5) was not set.')
print()
print('Baseline is `01_baseline_Oz` (`-Oz` only, no production knobs).')
print()
print('| Config | flags | bin B | Δbin | aes text B | tstates | Δtstates | verify |')
print('|--------|-------|------:|-----:|-----------:|--------:|---------:|:------:|')
for row in rows:
    bin_b = int(row['bin'])
    tstates = int(row['tstates'])
    dbin = f"{bin_b - base_bin:+d}" if baseline and row != baseline else ''
    dts = f"{(tstates - base_tstates) / base_tstates * 100:+.1f}%" if baseline and row != baseline else ''
    flags = row['flags'].strip()
    # Wrap long flag lists at boundaries
    flags = flags.replace(' -mllvm ', '<br>-mllvm ').replace(' -Xclang ', '<br>-Xclang ').replace(' -ffunction-sections', '<br>-ffunction-sections')
    print(f"| `{row['label']}` | {flags} | {row['bin']} | {dbin} | {row['aes_text']} | {row['tstates']} | {dts} | {row['verify']} |")

print()
print('## Notes on each finding')
print()
print('See `findings.md` for analysis of why each config wins or loses.')
PY

echo
echo "Wrote clang-flag-sweep.md"
