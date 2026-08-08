#!/bin/bash
# run_bench.sh <name> <main_hex> <getk_hex>
# Builds a work disk with <name>.com, boots rc702sem702, brackets _main->_getk
# via the debugger's totalcycles, pokes the delta to scratch RAM for bench.lua.
set -e
NAME=$1; MAIN=$2; GETK=$3
HERE="$(cd "$(dirname "$0")" && pwd)"
W=${W:-/tmp/pxbench}
MAME=${MAME:-/Users/ravn/z80/mame}
BASE=${BASE:-/Users/ravn/z80/rc700-gensmedet/autoload-in-c/test-disks/SW1711-I8.imd}
CPMCP=${CPMCP:-/Users/ravn/.local/bin/cpmcp}
LUA=${LUA:-$HERE/bench.lua}

# CP/M 8.3 upper-case command name (max 8 chars)
COMNAME=$(echo "$NAME" | tr 'a-z' 'A-Z' | cut -c1-8)

cp "$BASE" "$W/work.imd"
"$CPMCP" -f rc702-8dd "$W/work.imd" "$W/$NAME.com" "0:$COMNAME.COM"

# debugscript: capture totalcycles at _main, delta at first _getk -> 0x7000,
# flag 0xA5 -> 0x7008. temp2 guards the getk poll loop to the first hit.
cat > "$W/bench.dbg" <<EOF
temp2=0
bpset 0x$MAIN,1,{temp0=totalcycles;temp2=1;g}
bpset 0x$GETK,temp2==1,{temp2=0;q@0x7000=totalcycles-temp0;b@0x7008=0xA5;g}
g
EOF

cd "$MAME"
BENCH_CMD="$COMNAME" ./mame rc702sem702 -rompath roms -flop1 "$W/work.imd" \
  -window -nothrottle -skip_gameinfo -seconds_to_run 6000 \
  -debug -debugger none -debugscript "$W/bench.dbg" \
  -autoboot_script "$LUA" 2>/dev/null | grep "BENCH_RESULT"
