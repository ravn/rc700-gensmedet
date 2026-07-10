#!/usr/bin/env bash
# iso.sh -- write/read isolation for the clang CP/M file bug.
#
# Builds writer.c with clang (+shims) and reader.c with sccz80 (known-good),
# puts both .COMs on ONE disk, boots the RC702 once, types "WRITER" then
# "READER", and captures the console.  The sccz80 reader's output is a
# shim-free oracle for what clang actually wrote to disk.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
WORKSPACE="$(cd "$ROOT/.." && pwd)"

Z88DK="${Z88DK:-$WORKSPACE/z88dk}"
MAME_DIR="${MAME_DIR:-$WORKSPACE/mame}"
IMG="${IMG:-$ROOT/autoload-in-c/test-disks/SW1711-I8.imd}"
DISKDEFS="${DISKDEFS:-$ROOT/rcbios/diskdefs}"
DEF=rc702-8dd

export PATH="$Z88DK/bin:$PATH"
export ZCCCFG="${ZCCCFG:-$Z88DK/lib/config}"
CPMCP="${CPMCP:-cpmcp}"

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

echo "=== 1. build WRITER.COM (writer.c) ==="
WCC="${WCC:-llvmz80}"   # writer compiler; override to sccz80 for the control
WSHIM=""
[ "$WCC" = "llvmz80" ] && WSHIM="$HERE/cpm_bdos_clang.asm $HERE/cpm_stdio_clang.asm"
( cd "$HERE" && zcc +cpm -compiler=$WCC --opt-code-size writer.c \
      $WSHIM \
      -o "$W/wr" -create-app -pragma-define:CLIB_OPEN_MAX=8 )
echo "  writer compiler: $WCC"
WCOM="$W/$(ls "$W" | grep -i '^wr\.com$' | head -1)"
echo "  $(basename "$WCOM"): $(wc -c < "$WCOM" | tr -d ' ') bytes"

echo "=== 2. build READER.COM (sccz80, known-good) from reader.c ==="
( cd "$HERE" && zcc +cpm -compiler=sccz80 --opt-code-size reader.c \
      -o "$W/rd" -create-app -pragma-define:CLIB_OPEN_MAX=8 )
RCOM="$W/$(ls "$W" | grep -i '^rd\.com$' | head -1)"
echo "  $(basename "$RCOM"): $(wc -c < "$RCOM" | tr -d ' ') bytes"

echo "=== 3. build rcbios BIOS + disk image ==="
( cd "$ROOT/rcbios-in-c" && env -u COMPILER make bios >/dev/null )
BIOS="$ROOT/rcbios-in-c/clang/bios.clang.cim"
cp "$IMG" "$W/work.imd"
python3 "$ROOT/rcbios/patch_bios.py" "$W/work.imd" "$BIOS" >/dev/null
DISKDEFS="$DISKDEFS" "$CPMCP" -f "$DEF" "$W/work.imd" "$WCOM" 0:WRITER.COM
DISKDEFS="$DISKDEFS" "$CPMCP" -f "$DEF" "$W/work.imd" "$RCOM" 0:READER.COM
rm -f "$W/work.mfi"
"$MAME_DIR/floptool" flopconvert auto mfi "$W/work.imd" "$W/work.mfi" >/dev/null 2>&1

echo "=== 4. run in MAME (type WRITER then READER) ==="
LUA="$W/iso.lua"
cat > "$LUA" <<'LUA'
local frame, done = 0, false
local cmds = {"WRITER\r", "READER\r"}
local ci, pos, delay, state, wait = 1, 1, 0, "boot", 0
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
    if at_prompt(sp) then state, pos, delay = "type", 1, 20
    elseif frame > 50*30 then snap(sp, "TIMEOUT boot"); done=true; os.exit(1) end
  elseif state == "type" then
    if delay > 0 then delay = delay - 1; return end
    local cmd = cmds[ci]
    if pos > #cmd then state, wait = "run", 0; return end
    emu.keypost(string.sub(cmd, pos, pos)); pos = pos + 1; delay = 6
  elseif state == "run" then
    wait = wait + 1
    if wait % 50 == 0 then snap(sp, "after cmd "..ci.." t="..(wait//50).."s") end
    -- when the program has returned to the A> prompt, advance to next command
    if wait > 50*2 and at_prompt(sp) then
      if ci < #cmds then ci, pos, delay, state = ci+1, 1, 15, "type"
      else snap(sp, "final"); done = true; os.exit(0) end
    elseif wait > 50*25 then snap(sp, "final-timeout"); done = true; os.exit(0) end
  end
end)
LUA

SCREEN="$W/screen.txt"; rm -f "$SCREEN"
SCREEN_OUT="$SCREEN" "$MAME_DIR/regnecentralen" rc702 -rompath "$MAME_DIR/roms" \
    -flop1 "$W/work.mfi" -skip_gameinfo -window -resolution 1100x720 \
    -nothrottle -autoboot_script "$LUA" >/dev/null 2>&1 &
MPID=$!
for _ in $(seq 1 140); do kill -0 "$MPID" 2>/dev/null || break; sleep 1; done
kill -0 "$MPID" 2>/dev/null && kill -9 "$MPID" 2>/dev/null || true
wait "$MPID" 2>/dev/null || true

echo "=== 5. console ==="
cat "$SCREEN" 2>/dev/null || echo "(no screen captured)"
