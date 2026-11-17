-- login_trace.lua -- trace SIO-A IO and emulated time during CPNETLDR + LOGIN.
-- Writes /tmp/login_trace.csv: time_ms,op,port,value
-- Exits after EXIT_SECS of emulated time.

local OUT = os.getenv("LOGIN_TRACE_LOG") or "/tmp/login_trace.csv"
local EXIT_SECS = tonumber(os.getenv("LOGIN_TRACE_SECS") or "45")

local frame = 0
local done = false
local dumped_mid = false
local io_space, prog_space
local tap_r, tap_w

local f = io.open(OUT, "w")
f:write("time_ms,op,port,value\n")

local function now_ms()
    local t = manager.machine.time
    return t.seconds * 1000.0 + t.attoseconds / 1e15
end

local function log(op, port, value)
    f:write(string.format("%.3f,%s,0x%02x,0x%02x\n", now_ms(), op, port, value))
end

local function screen_dump(tag)
    f:write(string.format("# screen (%s)\n", tag))
    for row = 0, 24 do
        local line = ""
        for col = 0, 79 do
            local ch = prog_space:read_u8(0xF800 + row * 80 + col)
            line = line .. (ch >= 0x20 and ch < 0x7F and string.char(ch) or ".")
        end
        line = line:gsub("%s+$", "")
        if #line > 0 then f:write(string.format("#  %2d: %s\n", row, line)) end
    end
end

emu.register_frame_done(function()
    if done then return end
    frame = frame + 1

    if not io_space then
        io_space   = manager.machine.devices[":maincpu"].spaces["io"]
        prog_space = manager.machine.devices[":maincpu"].spaces["program"]
        tap_r = io_space:install_read_tap(0x08, 0x0B, "sioa_r",
            function(offset, data, mask) log("R", offset, data) end)
        tap_w = io_space:install_write_tap(0x08, 0x0B, "sioa_w",
            function(offset, data, mask) log("W", offset, data) end)
        f:write(string.format("# tap installed at frame 1 (t=%.3f ms)\n", now_ms()))
    end

    if not dumped_mid and now_ms() / 1000.0 >= 18.0 then
        screen_dump("cpnetldr")
        dumped_mid = true
    end

    if now_ms() / 1000.0 >= EXIT_SECS then
        screen_dump("final")
        f:close()
        done = true
        manager.machine:exit()
    end
end)
