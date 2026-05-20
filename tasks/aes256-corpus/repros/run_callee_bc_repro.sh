#!/usr/bin/env bash
# Run repro_callee_bc_read.c across the 4 PASS/FAIL configs.
set -euo pipefail

Z88DK=/Users/ravn/z80/z88dk
TICKS=$Z88DK/bin/z88dk-ticks
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
mkdir -p build_callee && cd build_callee
cp ../repro_callee_bc_read.c ./prog.c

build_run() {
  local label=$1; shift
  local cflags="$*"

  if ! eval "ZCCCFG=$Z88DK/lib/config PATH=$Z88DK/bin:\$PATH $Z88DK/bin/zcc +z80 -compiler=sdcc $cflags -m -create-app -o ${label} prog.c" >${label}.log 2>&1; then
    printf '%-40s BUILD-FAIL\n' "$label"
    return
  fi

  local done_addr=$(python3 -c "
import re
d = open('${label}.bin', 'rb').read()
m = re.search(b'\\xe5\\xf3\\xe1\\x76', d)
print(f'0x{m.start()+3:04X}' if m else exit(1))
")

  python3 ../../fill_with_jp_done.py ${label}.bin ${label}.filled.bin "$done_addr"
  perl -e 'alarm 30; exec @ARGV' \
    $TICKS -mz80 -end $done_addr -counter 10000000 \
    -output ${label}.ram ${label}.filled.bin >/dev/null 2>&1 || true

  if [ ! -f ${label}.ram ]; then
    printf '%-40s NO-RAM\n' "$label"
    return
  fi
  LABEL="$label" python3 <<'PY'
import os
label = os.environ['LABEL']
d = open(f'{label}.ram', 'rb').read()
k0  = d[0xC800]   # local.key[0]
k31 = d[0xC801]   # local.key[31]
e0  = d[0xC802]   # local.enckey[0]
d31 = d[0xC803]   # local.deckey[31]
dec0  = d[0xC804] # decoy[0]
dec31 = d[0xC805] # decoy[31]
dec63 = d[0xC806] # decoy[63]
dec95 = d[0xC807] # decoy[95]
eoT = d[0xC808]

# PASS: local.key/enckey/deckey all 0x00, decoy still 0xAA, eoT=0xEE
# BUG-DECOY: decoy zeroed instead of local
# Distinguish by which region got zeroed.
local_zeroed = (k0 == 0 and k31 == 0 and e0 == 0 and d31 == 0)
decoy_zeroed = (dec0 == 0 and dec31 == 0 and dec63 == 0 and dec95 == 0)

if local_zeroed and not decoy_zeroed:
    status = "PASS"
elif decoy_zeroed and not local_zeroed:
    status = "BUG-CALLEE-USES-BC"
elif decoy_zeroed and local_zeroed:
    status = "BOTH-ZEROED"
else:
    status = "NEITHER-ZEROED"
print(f'{label:<40s} local=[{k0:02X},{k31:02X},{e0:02X},{d31:02X}] decoy=[{dec0:02X},{dec31:02X},{dec63:02X},{dec95:02X}] eoT={eoT:02X} {status}')
PY
}

echo "Config                                   local.sent decoy[16] eoT  status"
echo "---------------------------------------- ---------- --------- ---  ------"

build_run "01_KR_sdcccall1_default"   '--opt-code-size -SO3 -Cs"--sdcccall 1" -Cs"--disable-warning 296" -Cs"--max-allocs-per-node 25000" -Cs"--fomit-frame-pointer"'
build_run "02_KR_sdcccall1_nogcse"    '--opt-code-size -SO3 -Cs"--sdcccall 1" -Cs"--disable-warning 296" -Cs"--max-allocs-per-node 25000" -Cs"--fomit-frame-pointer" -Cs"--nogcse"'
build_run "03_KR_sdcccall0_nogcse"    '--opt-code-size -SO3 -Cs"--max-allocs-per-node 25000" -Cs"--fomit-frame-pointer" -Cs"--nogcse"'
build_run "04_KR_sdcccall0_default"   '--opt-code-size -SO3 -Cs"--max-allocs-per-node 25000" -Cs"--fomit-frame-pointer"'
