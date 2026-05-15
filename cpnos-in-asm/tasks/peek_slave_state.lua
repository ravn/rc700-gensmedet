-- peek_slave_state.lua -- MAME Lua observability tool for cpnos-in-asm.
--
-- Periodically samples memory + the SIO-A status register and writes
-- a trace line whenever something changes.  Output goes to
-- /tmp/cpnos_asm_slave_trace.log.
--
-- Use this when serial-port forwarding via the slave's combined loop
-- isn't enough -- e.g. to see what's actually in rx_frame_buf, what
-- the slave's SP is, whether the SIO chip's RR0 status register has
-- pending RX bytes the slave hasn't read yet.  Diagnosed task #66
-- (rx_frame_buf was at 0x2800, which is bank2h PROM-mirror RAM) by
-- watching for changes at that address that never happened.
--
-- Configure the WATCHES table below for what you want to track.
-- Trace lines look like:
--   [  0.123s] sp=0xbffd  rx_frame_buf[0..6]=01 01 ff 00 ff 00 00
--
-- Launch alongside MAME via -autoboot_script $(SHARED)/mame/peek...
-- or copy this file to cpnos-shared/mame/ for reuse.

local LOG_PATH       = "/tmp/cpnos_asm_slave_trace.log"
local SAMPLE_HZ      = 50           -- 50 samples/sec -> 20 ms granularity
local INSTALL_GRACE  = 0.5          -- wait for hardware init before tracing

local f = io.open(LOG_PATH, "w")
f:write("# cpnos-in-asm slave trace\n")

local prog, cpu, state
local installed = false
local last_dump = nil

-- Each entry: { name, base, length }.  Add what you need to see.
local WATCHES = {
    { "rx_frame_buf",   0x3000, 12 },
}

local function regs_str()
    return string.format("sp=0x%04x pc=0x%04x",
        state["SP"].value, state["PC"].value)
end

local function hex_window(base, len)
    local parts = {}
    for i = 0, len - 1 do
        parts[#parts + 1] = string.format("%02x", prog:read_u8(base + i))
    end
    return table.concat(parts, " ")
end

local function snapshot()
    local lines = { regs_str() }
    for _, w in ipairs(WATCHES) do
        lines[#lines + 1] = string.format("%s[0..%d]=%s",
            w[1], w[3] - 1, hex_window(w[2], w[3]))
    end
    return table.concat(lines, "  ")
end

emu.register_periodic(function()
    if not installed then
        cpu = manager.machine.devices[":maincpu"]
        if cpu == nil then return end
        prog = cpu.spaces["program"]
        state = cpu.state
        if prog == nil or state == nil then return end
        installed = true
    end
    if emu.time() < INSTALL_GRACE then return end

    -- Sample every 1/SAMPLE_HZ seconds.  emu.register_periodic fires
    -- every frame; we throttle to the configured rate.
    local now = emu.time()
    if last_dump ~= nil and (now - last_dump) < (1.0 / SAMPLE_HZ) then
        return
    end
    last_dump = now

    local snap = snapshot()
    f:write(string.format("[%9.4fs] %s\n", now, snap))
    f:flush()
end)
