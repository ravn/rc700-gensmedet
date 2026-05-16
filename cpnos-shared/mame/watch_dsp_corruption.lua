-- watch_dsp_corruption.lua -- Lua write-tap that logs every write into
-- display memory 0xF800..0xF8FF (rows 0..3) along with PC + new value.
-- Used to identify the source of the "garbage on row 0 / blocks on row 1"
-- corruption seen pre-PPAS-launch.
--
-- Output: /tmp/cpnos_dsp_watch.log (one line per write).
-- Each line: [time] PC=xxxx ADDR=xxxx VAL=xx
--
-- Run alongside polypascal_test.lua via second -autoboot_script, OR
-- standalone for boot-only traces.

local OUT = "/tmp/cpnos_dsp_watch.log"
local LO  = 0xF800
local HI  = 0xF8FF      -- rows 0..3 inclusive (80 cols x 4 rows = 320 B)
local LIMIT = 5000      -- stop logging after this many writes (avoid runaway)

local f = io.open(OUT, "w")
f:write(string.format("# dsp write-tap on 0x%04x..0x%04x\n", LO, HI))

local prog, state, installed, count = nil, nil, false, 0

emu.register_periodic(function()
    if installed then return end
    local cpu = manager.machine.devices[":maincpu"]
    if cpu == nil then return end
    prog = cpu.spaces["program"]
    state = cpu.state
    if prog == nil or state == nil then return end

    prog:install_write_tap(LO, HI, "dsp_watch", function(offs, data, mask)
        count = count + 1
        if count > LIMIT then return end
        local pc = state["PC"].value
        f:write(string.format("[%9.4fs] PC=%04x ADDR=%04x VAL=%02x\n",
            emu.time(), pc, offs, data))
        f:flush()
    end)
    installed = true
    f:write("# tap installed\n"); f:flush()
end)
