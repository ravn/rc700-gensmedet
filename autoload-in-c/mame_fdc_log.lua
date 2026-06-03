-- mame_fdc_log.lua — FDC (µPD765) transaction logger for autoload-in-c boots.
--
-- Purpose: capture, in a recordable + submittable form, every FDC command the
-- boot PROM issues and every result byte MAME's upd765a returns, so the values
-- can be used as upstream bug evidence and compared against datasheet-expected
-- behaviour.
--
-- Mechanism: passive I/O taps (NEVER space:read on I/O — that double-reads and
-- breaks devices; see tasks/memory/feedback_lua_no_port_reads.md).
--   - read-tap  on port 0x04 (FDC main status register, MSR): cached only.
--   - write-tap on port 0x05 (FDC data reg): command + parameter bytes (CPU->FDC).
--   - read-tap  on port 0x05 (FDC data reg): result bytes (FDC->CPU), classified
--     by the cached MSR EXM bit so DMA/execution-phase bytes are not mistaken
--     for result-phase bytes.
--
-- Decodes the µPD765 command set into transactions and flags two known bugs:
--   BUG A: ST1 "No Data" (ND, 0x04) set after a Read Track (0x02) command.
--   BUG B: ST0 head bit (HD, 0x04) set in the Sense Interrupt result after a
--          Seek/Recalibrate (the head address leaks into ST0).
--
-- Output (paths overridable via env):
--   FDC_RAW_LOG     raw event stream                (default /tmp/autoload_fdc_raw.txt)
--   FDC_DECODED_LOG decoded transactions + bug flags (default /tmp/autoload_fdc_decoded.txt)
-- Runs FDC_LOG_SECONDS emulated seconds (default 20), snapshots, then exits.

local RAW_PATH     = os.getenv("FDC_RAW_LOG")     or "/tmp/autoload_fdc_raw.txt"
local DEC_PATH     = os.getenv("FDC_DECODED_LOG") or "/tmp/autoload_fdc_decoded.txt"
local DEADLINE_S   = tonumber(os.getenv("FDC_LOG_SECONDS") or "20")
local LABEL        = os.getenv("FDC_LOG_LABEL")   or "(unlabelled run)"

-- µPD765 command table, keyed by opcode & 0x1F.
-- nparam = parameter bytes after the opcode; nresult = result-phase bytes.
local CMDS = {
    [0x02] = { name = "Read Track",            nparam = 8, nresult = 7 },
    [0x03] = { name = "Specify",               nparam = 2, nresult = 0 },
    [0x04] = { name = "Sense Drive Status",    nparam = 1, nresult = 1 },
    [0x05] = { name = "Write Data",            nparam = 8, nresult = 7 },
    [0x06] = { name = "Read Data",             nparam = 8, nresult = 7 },
    [0x07] = { name = "Recalibrate",           nparam = 1, nresult = 0 },
    [0x08] = { name = "Sense Interrupt Status",nparam = 0, nresult = 2 },
    [0x09] = { name = "Write Deleted Data",    nparam = 8, nresult = 7 },
    [0x0A] = { name = "Read ID",               nparam = 1, nresult = 7 },
    [0x0C] = { name = "Read Deleted Data",     nparam = 8, nresult = 7 },
    [0x0D] = { name = "Format Track",          nparam = 5, nresult = 7 },
    [0x0F] = { name = "Seek",                  nparam = 2, nresult = 0 },
    [0x11] = { name = "Scan Equal",            nparam = 8, nresult = 7 },
    [0x19] = { name = "Scan Low or Equal",     nparam = 8, nresult = 7 },
    [0x1D] = { name = "Scan High or Equal",    nparam = 8, nresult = 7 },
}

local raw   = {}   -- raw event lines
local decoded = {} -- decoded transaction lines
local nbugA, nbugB = 0, 0

local last_msr = 0           -- cached MSR (from 0x04 read-tap)
local cur = nil              -- in-flight command {op, base, info, params, phase, results}
local last_seek_head = nil   -- head from the most recent Seek/Recalibrate
local last_seek_cyl  = nil
local seq = 0

local installed = false
local finished  = false
local prog                   -- program space (for the screen dump only)

local function now() return manager.machine.time:as_double() end
local function hexlist(t)
    local s = {}
    for _, b in ipairs(t) do s[#s + 1] = string.format("%02X", b) end
    return table.concat(s, " ")
end

local function flush_files()
    local f = io.open(RAW_PATH, "w")
    f:write("# FDC raw I/O event stream — " .. LABEL .. "\n")
    f:write("# seq  t(s)      dir port val  msr\n")
    for _, l in ipairs(raw) do f:write(l .. "\n") end
    f:close()

    f = io.open(DEC_PATH, "w")
    f:write("# FDC decoded µPD765 transactions — " .. LABEL .. "\n")
    f:write("# Result bytes for read/write/scan/format/read-id: ST0 ST1 ST2 C H R N\n")
    f:write("# Result bytes for Sense Interrupt: ST0 PCN.  Sense Drive: ST3.\n#\n")
    for _, l in ipairs(decoded) do f:write(l .. "\n") end
    f:write(string.format("#\n# SUMMARY: %d Read-Track ST1-ND hits (bug A), %d Sense-Int ST0-HD hits (bug B)\n",
                          nbugA, nbugB))
    f:close()
end

-- Emit a fully-decoded transaction line, with bug flags.
local function emit(c)
    local line
    if c.info then
        local hdr = string.format("[t=%8.4f] CMD %-22s op=%02X", c.t, c.info.name, c.op)
        if #c.params > 0 then hdr = hdr .. " params=[" .. hexlist(c.params) .. "]" end
        local res = (#c.results > 0) and ("RESULT=[" .. hexlist(c.results) .. "]") or "(no result phase)"
        line = hdr .. "  " .. res
        local flag = ""

        if c.base == 0x0F or c.base == 0x07 then
            -- record head/cyl for the Sense Interrupt that follows
            if c.base == 0x0F and #c.params >= 2 then
                last_seek_head = (c.params[1] >> 2) & 1
                last_seek_cyl  = c.params[2]
            else
                last_seek_head, last_seek_cyl = 0, 0
            end
        end

        if c.base == 0x08 and #c.results >= 1 then
            local st0 = c.results[1]
            local note = (last_seek_head ~= nil)
                and string.format(" (after Seek head=%d cyl=%s)", last_seek_head,
                                   tostring(last_seek_cyl)) or ""
            line = line .. note
            if (st0 & 0x04) ~= 0 then
                nbugB = nbugB + 1
                flag = string.format("   ** BUG B: ST0=%02X has HD bit (0x04) set after Seek/Recal **", st0)
            end
        elseif c.base == 0x02 and #c.results >= 2 then
            local st1 = c.results[2]
            if (st1 & 0x04) ~= 0 then
                nbugA = nbugA + 1
                flag = string.format("   ** BUG A: ST1=%02X has ND bit (0x04) set after Read Track **", st1)
            end
        end
        line = line .. flag
    else
        line = string.format("[t=%8.4f] UNKNOWN op=%02X params=[%s] RESULT=[%s]",
                             c.t, c.op, hexlist(c.params), hexlist(c.results))
    end
    decoded[#decoded + 1] = line
end

local function on_write05(offset, data)
    seq = seq + 1
    raw[#raw + 1] = string.format("%5d %9.4f  W   05  %02X   %02X", seq, now(), data, last_msr)

    if cur == nil or cur.phase == "result" then
        -- starting a new command (or aborting a half-read result phase)
        if cur ~= nil then emit(cur) end
        local base = data & 0x1F
        local info = CMDS[base]
        cur = { op = data, base = base, info = info, params = {}, results = {},
                phase = "cmd", t = now() }
        local np = info and info.nparam or 0
        if np == 0 then
            cur.phase = "result"
            if (info and info.nresult or 0) == 0 then emit(cur); cur = nil end
        end
    else -- collecting parameters
        cur.params[#cur.params + 1] = data
        local np = cur.info and cur.info.nparam or 0
        if #cur.params >= np then
            cur.phase = "result"
            if (cur.info and cur.info.nresult or 0) == 0 then emit(cur); cur = nil end
        end
    end
end

local function on_read05(offset, data)
    seq = seq + 1
    raw[#raw + 1] = string.format("%5d %9.4f  R   05  %02X   %02X", seq, now(), data, last_msr)

    -- EXM (MSR bit 5, 0x20) set => execution-phase byte, not a result byte.
    if (last_msr & 0x20) ~= 0 then return end
    if cur == nil or cur.phase ~= "result" then return end  -- stray read

    cur.results[#cur.results + 1] = data
    local nr = cur.info and cur.info.nresult or 0
    if #cur.results >= nr then emit(cur); cur = nil end
end

emu.register_periodic(function()
    if not installed then
        local cpu = manager.machine.devices[":maincpu"]
        if cpu == nil then return end
        local io = cpu.spaces["io"]
        prog = cpu.spaces["program"]
        if io == nil then return end
        io:install_read_tap (0x04, 0x04, "fdc_msr",   function(o, d) last_msr = d end)
        io:install_write_tap(0x05, 0x05, "fdc_cmd",   function(o, d) on_write05(o, d) end)
        io:install_read_tap (0x05, 0x05, "fdc_result",function(o, d) on_read05(o, d) end)
        installed = true
    end

    if finished then return end
    if now() < DEADLINE_S then return end
    finished = true

    if cur ~= nil then emit(cur) end  -- flush any in-flight command
    flush_files()
    -- pcall + filename: newer MAME's screen:snapshot() requires a name.
    local screen = manager.machine.screens:at(1)
    if screen ~= nil then
        pcall(function() screen:snapshot("autoload_fdc.png") end)
    end
    manager.machine:exit()
end)
