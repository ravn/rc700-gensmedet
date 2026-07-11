#!/usr/bin/env bash
# run.sh -- build bdostst.c with llvm-z88dk, run it on the RC702 in MAME,
# and report the BDOS/clib test results.
#
# Pipeline (mirrors tools/test_gfxshow.sh):
#   1. zcc +cpm -compiler=llvmz80 -> BDOSTST.COM
#   2. build rcbios-in-c C-BIOS (renders console to 0xF800)
#   3. patch BIOS + inject BDOSTST.COM onto a copy of SW1711-I8.imd
#   4. floptool imd->mfi, boot rc702 in MAME with an autoboot lua that
#      types "BDOSTST", waits, and dumps the 0xF800 screen
#   5. extract BDOSTST.LOG from the disk (durable, scroll-proof) and print it
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"          # rc700-gensmedet
WORKSPACE="$(cd "$ROOT/.." && pwd)"        # /Users/ravn/z80

Z88DK="${Z88DK:-$WORKSPACE/z88dk}"
MAME_DIR="${MAME_DIR:-$WORKSPACE/mame}"
IMG="${IMG:-$ROOT/autoload-in-c/test-disks/SW1711-I8.imd}"
DISKDEFS="${DISKDEFS:-$ROOT/rcbios/diskdefs}"
DEF=rc702-8dd

export PATH="$Z88DK/bin:$PATH"
export ZCCCFG="${ZCCCFG:-$Z88DK/lib/config}"
CPMCP="${CPMCP:-cpmcp}"
CPMLS="${CPMLS:-cpmls}"

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

SRC="${SRC:-bdostst.c}"
APP="${APP:-BDOSTST}"           # .COM base name (uppercase) + typed command
echo "=== 1. build $APP.COM (llvm-z88dk) from $SRC ==="
# Link the interim clang-ABI bdos shim (z88dk#20) when present.
COMPILER="${COMPILER:-llvmz80}"
SHIM=""
if [ "$COMPILER" = "llvmz80" ]; then
    [ -f "$HERE/cpm_bdos_clang.asm" ]  && SHIM="$SHIM $HERE/cpm_bdos_clang.asm"
    [ -f "$HERE/cpm_stdio_clang.asm" ] && SHIM="$SHIM $HERE/cpm_stdio_clang.asm"
fi
( cd "$HERE" && zcc +cpm -compiler="$COMPILER" --opt-code-size "$SRC" $SHIM \
      -o "$W/app" -create-app -pragma-define:CLIB_OPEN_MAX=8 )
# zcc emits <APP>.COM (uppercased) in the -o directory
COM="$(ls "$W"/*.COM "$W"/app.com 2>/dev/null | head -1)"
echo "  $(basename "$COM"): $(wc -c < "$COM" | tr -d ' ') bytes"

echo "=== 2. build rcbios-in-c BIOS ==="
( cd "$ROOT/rcbios-in-c" && env -u COMPILER make bios >/dev/null )
BIOS="$ROOT/rcbios-in-c/clang/bios.clang.cim"

echo "=== 3. build disk image ==="
cp "$IMG" "$W/work.imd"
python3 "$ROOT/rcbios/patch_bios.py" "$W/work.imd" "$BIOS" >/dev/null
DISKDEFS="$DISKDEFS" "$CPMCP" -f "$DEF" "$W/work.imd" "$COM" 0:$APP.COM
DISKDEFS="$DISKDEFS" "$CPMLS" -f "$DEF" "$W/work.imd" | grep -i "$APP" || true
rm -f "$W/work.mfi"
"$MAME_DIR/floptool" flopconvert auto mfi "$W/work.imd" "$W/work.mfi" >/dev/null 2>&1

echo "=== 4. run in MAME ==="
LUA="$W/test.lua"
cat > "$LUA" <<'LUA'
local frame, done, state = 0, false, "boot"
local cmd, pos, delay, wait = (os.getenv("TYPE_CMD") or "BDOSTST").."\r", 1, 0, 0
local function dump(sp)
  local L = {}
  for r = 0, 23 do
    local s = ""
    for c = 0, 79 do
      local ch = sp:read_u8(0xF800 + r*80 + c)
      s = s .. ((ch >= 0x20 and ch < 0x7F) and string.char(ch) or " ")
    end
    L[#L+1] = (s:gsub("%s+$",""))
  end
  return table.concat(L, "\n")
end
local function at_prompt(sp)
  for r = 0, 23 do
    local a = 0xF800 + r*80
    if sp:read_u8(a) == 0x41 and sp:read_u8(a+1) == 0x3E then
      if sp:read_u8(0xFFD4) == r then return true end
    end
  end
  return false
end
local snaps = {}
local function write_all()
  local f = io.open(os.getenv("SCREEN_OUT"), "w")
  for _, s in ipairs(snaps) do f:write(s .. "\n") end
  f:close()
end
local function snap(sp, tag)
  snaps[#snaps+1] = "=== "..tag.." (frame "..frame..") ===\n"..dump(sp)
  write_all()
end
emu.register_frame_done(function()
  if done then return end
  frame = frame + 1
  local sp = manager.machine.devices[":maincpu"].spaces["program"]
  if state == "boot" then
    if at_prompt(sp) then state, pos, delay = "type", 1, 15
    elseif frame > 50*30 then snap(sp, "TIMEOUT boot"); done=true; os.exit(1) end
  elseif state == "type" then
    if delay > 0 then delay = delay - 1; return end
    if pos > #cmd then state, wait = "watch", 0; return end
    emu.keypost(string.sub(cmd, pos, pos)); pos = pos + 1; delay = 6
  elseif state == "watch" then
    -- snapshot every ~1 s for 40 s to capture the full (slow) run + verdict
    wait = wait + 1
    if wait % 50 == 0 then snap(sp, "t="..(wait//50).."s") end
    if wait > 50*40 then done = true; os.exit(0) end
  end
end)
LUA

SCREEN="$W/screen.txt"
rm -f "$SCREEN"
SCREEN_OUT="$SCREEN" TYPE_CMD="$APP" "$MAME_DIR/regnecentralen" rc702 -rompath "$MAME_DIR/roms" \
    -flop1 "$W/work.mfi" -skip_gameinfo -window -resolution 1100x720 \
    -nothrottle -autoboot_script "$LUA" >/dev/null 2>&1 &
MPID=$!
for _ in $(seq 1 130); do
    kill -0 "$MPID" 2>/dev/null || break
    sleep 1
done
kill -0 "$MPID" 2>/dev/null && kill -9 "$MPID" 2>/dev/null || true
wait "$MPID" 2>/dev/null || true

echo "=== 5. results ==="
echo "--- final screen ---"
cat "$SCREEN" 2>/dev/null || echo "(no screen captured)"
echo
echo "--- BDOSTST.LOG (extracted from disk) ---"
if DISKDEFS="$DISKDEFS" "$CPMCP" -f "$DEF" "$W/work.imd" 0:BDOSTST.LOG "$W/BDOSTST.LOG" 2>/dev/null; then
    cat "$W/BDOSTST.LOG"
else
    echo "(BDOSTST.LOG not found on disk -- file writing may have failed)"
fi

echo
if grep -q "VERDICT:.* fails: (none)" "$SCREEN" 2>/dev/null \
   || grep -q "VERDICT:.* fails: (none)" "$W/BDOSTST.LOG" 2>/dev/null; then
    echo "OVERALL: PASS"
else
    echo "OVERALL: FAIL (see failing check ids above)"
    exit 1
fi
