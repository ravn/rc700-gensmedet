#!/usr/bin/env bash
# Sweep zsdcc / sdcc flag combinations for AES-256 size + speed.
#
# Mirror of flag_sweep.sh for clang. Writes sweep/results_sdcc.tsv +
# sdcc-flag-sweep.md.
#
# Baseline is "current cpnos-rom production" flags (validated for the
# RC700 BIOS/PROM workloads). Other configs deviate to test ABI choices,
# peephole levels, regalloc effort, and frame-pointer reservation.

set -euo pipefail

Z88DK=/Users/ravn/z80/z88dk
TICKS=$Z88DK/bin/z88dk-ticks
ZCC_ENV="ZCCCFG=$Z88DK/lib/config PATH=$Z88DK/bin:$PATH"
ZCC="$Z88DK/bin/zcc"

HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
mkdir -p sweep
cd sweep

TSV=results_sdcc.tsv
printf 'label\tbin\taes_text\ttstates\tverify\tflags\n' > "$TSV"

build_and_measure() {
  local label=$1; shift
  local cflags="$*"
  local prefix="${label}"

  # zcc wants source files in cwd; copy from parent.
  cp ../aes256.c ../test_main.c .
  rm -f ${prefix}_*.map ${prefix}.bin ${prefix}.map ${prefix}.ram \
        ${prefix}_BSS.bin ${prefix}_CODE.bin ${prefix}_DATA.bin

  if ! eval "$ZCC_ENV $ZCC +z80 -compiler=sdcc $cflags -m -create-app \
       -o ${prefix} aes256.c test_main.c" >${prefix}.buildlog 2>&1; then
    printf '%-32s %s\n' "$label" "BUILD-FAIL" >&2
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$label" "-" "-" "-" "BUILD-FAIL" "$cflags" >> "$TSV"
    printf '%-32s bin=%5s aes_text=%5s tstates=%10s %s\n' \
      "$label" "-" "-" "-" "BUILD-FAIL"
    return
  fi

  local bin_size aes_text done_addr tstates verify
  bin_size=$(wc -c < ${prefix}.bin | tr -d ' ')

  # Extract aes256.c text size from the .map: sum (next-addr − this-addr)
  # for all aes256_c-section symbols in source order. Quoted-EOF heredoc
  # so bash doesn't interpret \$([0-9...]) as command substitution.
  aes_text=$(MAPFILE="${prefix}.map" python3 - <<'PY'
import os, re
syms = []
for line in open(os.environ["MAPFILE"]):
    m = re.match(r'^(_\S+)\s+=\s+\$([0-9A-Fa-f]+)\s+;.*aes256_c', line)
    if m: syms.append((int(m.group(2), 16), m.group(1)))
    m = re.match(r'^(_main)\s+=\s+\$([0-9A-Fa-f]+)', line)
    if m: syms.append((int(m.group(2), 16), m.group(1)))
syms.sort()
total = 0
for i, (addr, name) in enumerate(syms[:-1]):
    if 'aes' in name or 'gf_' in name or 'rj_' in name:
        total += syms[i+1][0] - addr
print(total)
PY
)

  # Find post-main HALT address by byte-pattern scan: e5 f3 e1 76
  # (push hl; di; pop hl; halt) in z88dk +z80 crt0. The HALT itself is
  # at pattern_start + 3.
  done_addr=$(python3 -c "
import re
d = open('${prefix}.bin', 'rb').read()
m = re.search(b'\\xe5\\xf3\\xe1\\x76', d)
print(f'0x{m.start()+3:04X}' if m else exit(1))
")
  if [ -z "$done_addr" ]; then
    printf '%-32s %s\n' "$label" "NO-HALT-PATTERN"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$label" "$bin_size" "$aes_text" "-" "NO-HALT-PATTERN" "$cflags" >> "$TSV"
    return
  fi

  # Pre-fill RAM beyond binary with `JP done_addr` pattern (per
  # fill_with_jp_done.py docstring) so any escape into uninit memory
  # immediately exits ticks via -end. Applies always.
  python3 ../fill_with_jp_done.py ${prefix}.bin ${prefix}.filled.bin "$done_addr"

  # 90s wallclock cap is a fall-through guard. `|| true` because
  # perl-alarm kills ticks with SIGALRM (exit 142), which would
  # otherwise abort the sweep under `set -e`.
  tstates=$(perl -e 'alarm 90; exec @ARGV' \
    $TICKS -mz80 -end $done_addr -counter 100000000 \
    -output ${prefix}.ram ${prefix}.filled.bin 2>&1 | tail -1 || true)
  if [ ! -f ${prefix}.ram ]; then
    tstates="TIMEOUT"; verify="TIMEOUT(probable_miscompile)"
  else
    verify=$(python3 -c "d=open('${prefix}.ram','rb').read(); v=d[0xC000:0xC023]; \
      print('PASS' if v[16]==1 and v[33]==1 and v[34]==0xA5 else 'FAIL')")
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$label" "$bin_size" "$aes_text" "$tstates" "$verify" "$cflags" >> "$TSV"
  printf '%-32s bin=%5s aes_text=%5s tstates=%10s %s\n' \
    "$label" "$bin_size" "$aes_text" "$tstates" "$verify"
}

echo "Config                          bin_size aes_text  tstates    verify"
echo "------------------------------- -------- -------- ---------- ------"

# 1. Baseline = current production cpnos-rom flag set
PROD='-clib=sdcc_iy --opt-code-size -SO3 -Cs"--sdcccall 1" -Cs"--disable-warning 296" -Cs"--max-allocs-per-node 25000" -Cs"--fomit-frame-pointer"'
build_and_measure "01_baseline_prod"          $PROD

# 2-3. ABI choice (sdcccall 0 = stack, sdcccall 1 = register).
build_and_measure "02_sdcccall_0"             '-clib=sdcc_iy --opt-code-size -SO3 -Cs"--max-allocs-per-node 25000" -Cs"--fomit-frame-pointer"'
build_and_measure "03_sdcccall_1"             $PROD  # alias for baseline; uncomment if want explicit row

# 4. Optimize for speed instead of size.
build_and_measure "04_opt_speed"              '-clib=sdcc_iy -SO3 -Cs"--sdcccall 1" -Cs"--disable-warning 296" -Cs"--opt-code-speed" -Cs"--max-allocs-per-node 25000" -Cs"--fomit-frame-pointer"'

# 5-7. Peephole level (-SO0 / -SO2; default already covers -SO1).
build_and_measure "05_SO0"                    '-clib=sdcc_iy --opt-code-size -SO0 -Cs"--sdcccall 1" -Cs"--disable-warning 296" -Cs"--max-allocs-per-node 25000" -Cs"--fomit-frame-pointer"'
build_and_measure "06_SO2"                    '-clib=sdcc_iy --opt-code-size -SO2 -Cs"--sdcccall 1" -Cs"--disable-warning 296" -Cs"--max-allocs-per-node 25000" -Cs"--fomit-frame-pointer"'

# 8. SDCC-side peephole disabled.
build_and_measure "07_no_peep"                '-clib=sdcc_iy --opt-code-size -SO3 -Cs"--sdcccall 1" -Cs"--disable-warning 296" -Cs"--max-allocs-per-node 25000" -Cs"--fomit-frame-pointer" -Cs"--no-peep"'

# 9. SDCC GCSE disabled (analogous to clang's -disable-machine-cse).
build_and_measure "08_nogcse"                 '-clib=sdcc_iy --opt-code-size -SO3 -Cs"--sdcccall 1" -Cs"--disable-warning 296" -Cs"--max-allocs-per-node 25000" -Cs"--fomit-frame-pointer" -Cs"--nogcse"'

# 10. IX as frame pointer instead of IY.
build_and_measure "09_clib_ix"                '-clib=sdcc_ix --opt-code-size -SO3 -Cs"--sdcccall 1" -Cs"--disable-warning 296" -Cs"--max-allocs-per-node 25000" -Cs"--fomit-frame-pointer"'

# 11-12. Regalloc effort sweep (default ~3000, prod 25000).
build_and_measure "10_max_allocs_1000"        '-clib=sdcc_iy --opt-code-size -SO3 -Cs"--sdcccall 1" -Cs"--disable-warning 296" -Cs"--max-allocs-per-node 1000" -Cs"--fomit-frame-pointer"'
build_and_measure "11_max_allocs_100000"      '-clib=sdcc_iy --opt-code-size -SO3 -Cs"--sdcccall 1" -Cs"--disable-warning 296" -Cs"--max-allocs-per-node 100000" -Cs"--fomit-frame-pointer"'

# 13. Keep frame pointer (DROP --fomit-frame-pointer). Note this conflicts
#    with sdcc_iy by SDCC's rule (--reserve-regs-iy is incompatible with
#    --fomit-frame-pointer; reserving IY = keeping frame ptr in IY).
build_and_measure "12_keep_frame_ptr"         '-clib=sdcc_iy --opt-code-size -SO3 -Cs"--sdcccall 1" -Cs"--disable-warning 296" -Cs"--max-allocs-per-node 25000"'

# 14. All-callee-saves (caller doesn't need to save anything around CALL).
build_and_measure "13_all_callee_saves"       '-clib=sdcc_iy --opt-code-size -SO3 -Cs"--sdcccall 1" -Cs"--disable-warning 296" -Cs"--max-allocs-per-node 25000" -Cs"--fomit-frame-pointer" -Cs"--all-callee-saves"'

# Generate markdown table.
cd ..
python3 <<'PY' > sdcc-flag-sweep.md
import csv, datetime, subprocess

rows = []
with open('sweep/results_sdcc.tsv') as f:
    r = csv.DictReader(f, delimiter='\t')
    for row in r:
        rows.append(row)

baseline = {r['label']: r for r in rows}.get('01_baseline_prod', None)

def n(s):
    return int(s) if s.strip().isdigit() else None

base_bin     = n(baseline['bin']) if baseline else None
base_tstates = n(baseline['tstates']) if baseline else None

z88dk_head = subprocess.run(
    ['git', '-C', '/Users/ravn/z80/z88dk', 'rev-parse', '--short=12', 'HEAD'],
    capture_output=True, text=True).stdout.strip() or '(unknown)'

print('# zsdcc flag sweep — AES-256 corpus')
print()
print(f'Last run: {datetime.date.today().isoformat()}  ')
print(f'z88dk HEAD: `{z88dk_head}`')
print()
print('Reproducible via `make sweep_sdcc` in this directory. Each row is a')
print('clean rebuild + run-to-HALT in `z88dk-ticks` with verification of')
print('the 35-byte result vector at 0xC000.')
print()
print('Baseline (`01_baseline_prod`) = current production cpnos-rom flags.')
print()
print('| Config | flags | bin B | Δbin | aes text B | tstates | Δtstates | verify |')
print('|--------|-------|------:|-----:|-----------:|--------:|---------:|:------:|')
for row in rows:
    bin_b = n(row['bin']); tstates = n(row['tstates'])
    if bin_b is not None and base_bin is not None and row is not baseline:
        dbin = f"{bin_b - base_bin:+d}"
    elif row is baseline:
        dbin = '—'
    else:
        dbin = '?'
    if tstates is not None and base_tstates and row is not baseline:
        dts = f"{(tstates - base_tstates) / base_tstates * 100:+.1f}%"
    elif row is baseline:
        dts = '—'
    else:
        dts = '?'
    flags = row['flags'].strip()
    flags = flags.replace(' -Cs', '<br>-Cs').replace(' --opt-code', '<br>--opt-code').replace(' -SO', '<br>-SO')
    print(f"| `{row['label']}` | {flags} | {row['bin']} | {dbin} | {row['aes_text']} | {row['tstates']} | {dts} | {row['verify']} |")
PY

echo
echo "Wrote sdcc-flag-sweep.md"
