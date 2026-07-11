-- bdos_trace.lua -- zero-injection BDOS (CALL 5) call tracer for the RC702.
--
-- Installs a read-tap on the BDOS entry vector at 0x0005.  A CP/M program
-- invokes a BDOS service with `CALL 5`, which lands on the `JP BDOS` at
-- 0x0005; the tap fires on that opcode fetch, at which instant the Z80
-- registers hold the call parameters:
--     C  = BDOS function number
--     DE = the function's argument (address or value)
--     SP -> the return address the CCP/program pushed with `CALL 5`
-- We log C/DE on entry, then arm a one-shot tap at that return address so we
-- can log the EXIT registers (A = 8-bit result, HL = 16-bit result) the
-- moment BDOS returns to the caller.  Output goes to $TRACE_OUT as a linear
-- text stream -- the whole point is to see the exact BDOS sequence (and which
-- call fails to return) without touching the program or the C-BIOS.
--
-- Driving: like the other harness scripts, we wait for the A> prompt, keypost
-- $BDOS_CMD (e.g. "BDOSTST\r"), then trace until $BDOS_SECS elapse.

local CMD      = (os.getenv("BDOS_CMD") or "BDOSTST\r")
local OUT      = os.getenv("TRACE_OUT") or "/tmp/bt/trace.txt"
local RUN_SECS = tonumber(os.getenv("BDOS_SECS") or "40")

local frame, state, done = 0, "boot", false
local pos, delay, wait = 1, 0, 0
local lines = {}
local exit_taps = {}      -- retaddr -> {tap=..., func=..., de=...}
local pending_remove = {} -- taps to remove next frame (safe teardown)
local keep_taps = {}      -- GC-RETENTION: MAME removes a tap if its Lua handle
                          -- is garbage-collected.  Every persistent tap handle
                          -- MUST be stored here or it silently stops firing.
local ncalls = 0

local logf = io.open(OUT, "w")   -- single persistent handle, closed in finish()
local written = 0                -- how many `lines` already written to disk

local function flush()
  -- Append only the not-yet-written lines, then flush to disk.  We never
  -- reopen/truncate: the handle stays open for the whole run and is closed
  -- exactly once in finish().
  for i = written + 1, #lines do logf:write(lines[i] .. "\n") end
  written = #lines
  logf:flush()
end
local function log(s)
  lines[#lines + 1] = s   -- flushed once per frame in register_frame_done (not here:
                          -- file I/O inside the BDOS tap callback perturbs timing)
end

-- Names for the BDOS functions we care about (rest logged numerically).
local FN = {
  [0]="SYSRESET",[1]="CONIN",[2]="CONOUT",[6]="DIRCON",[9]="PRINTSTR",
  [10]="RDBUF",[11]="CONST",[12]="VERSION",[13]="DISKRESET",[14]="SELDSK",
  [15]="OPEN",[16]="CLOSE",[17]="SEARCHF",[18]="SEARCHN",[19]="DELETE",
  [20]="READSEQ",[21]="WRITESEQ",[22]="MAKE",[23]="RENAME",[25]="CURDSK",
  [26]="SETDMA",[32]="USER",[33]="READRND",[34]="WRITERND",[35]="FILESIZE",
  [36]="SETRND",[40]="WRZF",
}

local function screen(sp)
  local L = {}
  for r = 0, 23 do
    local s = ""
    for c = 0, 79 do
      local ch = sp:read_u8(0xF800 + r*80 + c)
      s = s .. ((ch >= 0x20 and ch < 0x7F) and string.char(ch) or " ")
    end
    L[#L+1] = (s:gsub("%s+$", ""))
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

local cpu   = manager.machine.devices[":maincpu"]
local prog  = cpu.spaces["program"]
local st    = cpu.state

local function reg(name) return st[name].value end

local function install_bdos_tap()
  keep_taps[#keep_taps+1] =
  prog:install_read_tap(0x0005, 0x0005, "bdos5_entry", function(offset, data)
    -- Fires on the opcode fetch of the JP at 0x0005 (BDOS entry).
    local bc = reg("BC"); local de = reg("DE"); local sp = reg("SP")
    local func = bc & 0xFF
    local retaddr = prog:read_u8(sp) | (prog:read_u8(sp+1) << 8)
    ncalls = ncalls + 1
    local nm = FN[func] or ("fn"..func)
    -- CCP loader calls return into the BDOS/CCP region (>=0xC000); the program's
    -- own calls return into the TPA (0x0100..0xBFFF).  Tag the latter so the
    -- program's BDOS sequence stands out from the .COM-load traffic.
    local tag = (retaddr >= 0x0100 and retaddr < 0xC000) and "*" or " "
    log(string.format("[%4d]%s ENTER  C=%3d %-9s DE=%04X  (ret->%04X)",
                       ncalls, tag, func, nm, de, retaddr))
    -- Arm a one-shot exit tap at the return address.  Only one BDOS call is
    -- in flight at a time (CP/M BDOS is not reentrant for user code).
    if not exit_taps[retaddr] then
      local t = prog:install_read_tap(retaddr, retaddr, "bdos5_exit", function()
        local a  = (reg("AF") >> 8) & 0xFF
        local hl = reg("HL")
        log(string.format("       EXIT   A=%02X HL=%04X   (<-%s)", a, hl, nm))
        -- Defer removal: don't mutate taps from inside the callback.
        pending_remove[#pending_remove+1] = retaddr
      end)
      exit_taps[retaddr] = t
    end
  end)
  log("== BDOS-5 tracer armed at 0x0005 ==")
  flush()
end

-- BIOS jump-table entry names (offset = 3*index from the BIOS base).
local BIOS = {
  [0]="BOOT",[1]="WBOOT",[2]="CONST",[3]="CONIN",[4]="CONOUT",[5]="LIST",
  [6]="AUXOUT",[7]="AUXIN",[8]="HOME",[9]="SELDSK",[10]="SETTRK",
  [11]="SETSEC",[12]="SETDMA",[13]="READ",[14]="WRITE",[15]="LISTST",
  [16]="SECTRAN",
}

local function install_bios_taps()
  -- 0x0000 is `JP WBOOT`; bytes 1..2 hold the WBOOT address = biosbase + 3.
  local wboot = prog:read_u8(0x0001) | (prog:read_u8(0x0002) << 8)
  local biosbase = wboot - 3
  log(string.format("== BIOS jump table base = %04X (WBOOT=%04X) ==", biosbase, wboot))
  for k = 0, 16 do
    if k == 2 or k == 15 then goto continue end  -- skip CONST/LISTST poll spam
    local addr = biosbase + 3*k
    local nm = BIOS[k] or ("b"..k)
    keep_taps[#keep_taps+1] =
    prog:install_read_tap(addr, addr, "bios_"..nm, function()
      -- Fires on the opcode fetch at a BIOS entry (each is a `JP handler`).
      -- Console/disk BIOS calls carry their arg in C (byte) or BC (SETDMA=BC).
      local bc = reg("BC"); local de = reg("DE")
      local sp = reg("SP")
      local ret = prog:read_u8(sp) | (prog:read_u8(sp+1) << 8)
      local ch = bc & 0xFF
      log(string.format("        BIOS  %-7s C=%02X BC=%04X DE=%04X (ret->%04X)",
                        nm, ch, bc, de, ret))
    end)
    ::continue::
  end
  flush()
end

local function finish(sp, code, tag)
  log("=== " .. tag .. " (frame " .. frame .. ", " .. ncalls .. " BDOS calls) ===")
  log("--- final screen ---")
  log(screen(sp))
  flush()
  logf:close()            -- close the log handle before leaving the emulator
  done = true
  os.exit(code)
end

emu.register_frame_done(function()
  if done then return end
  frame = frame + 1
  flush()   -- persist trace once per frame (cheap, off the tap hot path)

  -- Safe teardown of spent one-shot exit taps.
  if #pending_remove > 0 then
    for _, ra in ipairs(pending_remove) do
      if exit_taps[ra] then exit_taps[ra]:remove(); exit_taps[ra] = nil end
    end
    pending_remove = {}
  end

  local sp = cpu.spaces["program"]
  if state == "boot" then
    if at_prompt(sp) then
      install_bdos_tap()
      install_bios_taps()
      state, pos, delay = "type", 1, 15
    elseif frame > 50*30 then
      finish(sp, 1, "TIMEOUT waiting for A>")
    end
  elseif state == "type" then
    if delay > 0 then delay = delay - 1; return end
    if pos > #CMD then state, wait = "watch", 0; return end
    emu.keypost(string.sub(CMD, pos, pos)); pos = pos + 1; delay = 6
  elseif state == "watch" then
    wait = wait + 1
    if wait % 50 == 0 then flush() end
    if wait > 50 * RUN_SECS then finish(sp, 0, "DONE") end
  end
end)
