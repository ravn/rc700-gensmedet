-- Bisect: ONLY io_space port taps.  No prog:install_*_tap.
local compiler   = os.getenv("COMPILER") or "clang"
local inir_addrs = dofile(compiler .. "/cpnos_inir_addrs.lua")

local TRACE_LOG = "/tmp/cpnos_inir_trace.log"
local RESULT_F  = "/tmp/cpnos_polypascal_result.txt"
local MAX_EVENTS = 30000

do local f = io.open(TRACE_LOG, "w") if f then f:close() end end

local events, n_events = {}, 0
local function evt(s)
    if n_events >= MAX_EVENTS then return end
    n_events = n_events + 1; events[n_events] = s
end
local function flush()
    local f = io.open(TRACE_LOG, "w"); if not f then return end
    f:write(string.format("# inir_probe trace, %d events\n", n_events))
    for i = 1, n_events do f:write(events[i]); f:write("\n") end
    f:close()
end

local installed, flushed = false, false
local prog, io_space, state

emu.register_periodic(function()
    if not installed then
        local cpu = manager.machine.devices[":maincpu"]
        if cpu == nil then return end
        prog = cpu.spaces["program"]
        io_space = cpu.spaces["io"]
        state = cpu.state
        if prog == nil or io_space == nil then return end

        io_space:install_read_tap(0x11, 0x11, "piob_data_r",
            function(off, data, mask)
                evt(string.format("[%9.4fs] IN  0x11 -> %02x",
                    emu.time(), data))
            end)
        io_space:install_write_tap(0x11, 0x11, "piob_data_w",
            function(off, data, mask)
                evt(string.format("[%9.4fs] OUT 0x11 <- %02x",
                    emu.time(), data))
            end)
        io_space:install_write_tap(0x13, 0x13, "piob_ctrl_w",
            function(off, data, mask)
                evt(string.format("[%9.4fs] OUT 0x13 <- %02x",
                    emu.time(), data))
            end)
        evt(string.format("[%9.4fs] === io taps installed ===", emu.time()))
        installed = true
    end

    if not flushed and installed then
        local f = io.open(RESULT_F, "r")
        if f then
            local s = f:read("*a"); f:close()
            if s and #s > 0 then
                evt(string.format("[%9.4fs] === result: %s ===",
                    emu.time(), s:gsub("\n", " ")))
                flush(); flushed = true
            end
        end
    end
end)

dofile("../cpnos-shared/mame/polypascal_test.lua")
