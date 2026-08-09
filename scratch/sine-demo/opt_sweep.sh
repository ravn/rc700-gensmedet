#!/bin/bash
# Build mandelbrot.c under llvmz80 at each opt level, run in MAME rc702, record
# .com size + draw time + pixel-match vs the sccz80 oracle (snap/gfxtest-sccz80.png).
set -u
cd "$(dirname "$0")"

Z80ROOT=/Users/ravn/z80
TOOLS="$(pwd)/.tools"
Z88DK_BIN="$Z80ROOT/z88dk/bin"
export ZCCCFG="$Z80ROOT/z88dk/lib/config"
CPM_BIN="$HOME/.local/bin"
MAME="$Z80ROOT/mame/regnecentralend"
ROMS="$Z80ROOT/mame/roms"
BASE="$Z80ROOT/rc700-gensmedet/autoload-in-c/test-disks/SW1711-I8.imd"
ORACLE=snap/gfxtest-sccz80.png
RESULT=opt_sweep_results.txt

mkdir -p "$TOOLS"; ln -sf "$Z80ROOT/llvm-z80/build-macos/bin/clang" "$TOOLS/llvmz80-clang"
: > "$RESULT"
printf "%-6s %-14s %8s %8s %10s %10s %s\n" opt "clang-opt" size frame draw_s onpix match | tee -a "$RESULT"

# tag:zcc-flags  (clang opt shown in output)
declare -a ROWS=(
  "o0:-O0:-O0"
  "o1:-O1:-O1"
  "o2:-O2:-O2"
  "o3:-O3:-O3"
  "os:-O2 -Cg-Os:-Os"
)

for row in "${ROWS[@]}"; do
  tag="${row%%:*}"; rest="${row#*:}"; flags="${rest%%:*}"; copt="${rest##*:}"
  com="mandel-$tag.com"; disk="mandel-$tag-B.imd"; png="snap/mandel-$tag.png"

  # 1. compile
  PATH="$TOOLS:$Z88DK_BIN:$PATH" zcc +cpm -subtype=rc700 -compiler=llvmz80 $flags \
      -o "mandel-$tag" mandelbrot.c >/dev/null 2>&1
  cp -f "mandel-$tag" "$com"
  size=$(stat -f%z "$com" 2>/dev/null)

  # 2. inject onto a copy of the system disk as GFXTEST.COM
  cp -f "$BASE" "$disk"
  PATH="$CPM_BIN:$PATH" cpmcp -f rc702-8dd "$disk" "$com" 0:GFXTEST.COM >/dev/null 2>&1

  # 3. run MAME, capture completion frame
  rm -rf snap/rc702
  log=$(mktemp)
  "$MAME" rc702 -rompath "$ROMS" -nothrottle -video none -sound none -skip_gameinfo \
     -flop1 "$BASE" -flop2 "$(pwd)/$disk" -autoboot_script mandelbrot_run.lua \
     -snapshot_directory snap -seconds_to_run 2000 >"$log" 2>&1
  frame=$(grep -oE "snapped at frame [0-9]+" "$log" | grep -oE "[0-9]+" | tail -1)
  [ -z "$frame" ] && frame=$(grep -oE "hard cap at frame [0-9]+" "$log" | grep -oE "[0-9]+" | tail -1)
  cp -f snap/rc702/0000.png "$png" 2>/dev/null
  rm -f "$log"

  # draw seconds ~= (frame - typed(166) - stable-window(1200)) / 50 fps
  draw_s=$(awk "BEGIN{printf \"%.1f\", ($frame-166-1200)/50}")

  # 4. pixel-match vs oracle
  read onpix match < <(python3 - "$png" "$ORACLE" <<'PY'
import sys
from PIL import Image
a=Image.open(sys.argv[1]).convert("RGB"); b=Image.open(sys.argv[2]).convert("RGB")
on=lambda p:sum(p)>300
pa=list(a.getdata()); pb=list(b.getdata())
na=sum(on(p) for p in pa)
diff=sum(1 for x,y in zip(pa,pb) if on(x)!=on(y))
print(na, "IDENTICAL" if diff==0 else f"DIFF({diff})")
PY
)
  printf "%-6s %-14s %8s %8s %10s %10s %s\n" "$tag" "$copt" "$size" "$frame" "$draw_s" "$onpix" "$match" | tee -a "$RESULT"
done
echo "=== done -> $RESULT ==="
