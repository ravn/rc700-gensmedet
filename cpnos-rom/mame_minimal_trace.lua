-- Minimal trace: only watch (a) BDOS entry, (b) SNDMSG/RCVMSG body,
-- (c) NDOS COLDST entry.  Capture A on entry/exit (return value).
-- Filter: only log calls with retaddr inside cpnos.com (0xDD80..0xE9FF)
-- so we exclude netboot's heavy calls and see only NDOS-side activity.
-- No exit taps -- they pile up and perturb timing.
local out_path = "/tmp/cpnos_minimal_trace.log"
local out_f = io.open(out_path, "w")
local TIMEOUT_S = 8.0
local cpu, prog, state
local hit_count = 0

local function log_line(s) out_f:write(s); out_f:write("\n"); out_f:flush() end

local function regs_str()
    local af = state["AF"].value
    return string.format("A=%02X F=%02X BC=%04X DE=%04X HL=%04X SP=%04X",
        (af >> 8) & 0xFF, af & 0xFF,
        state["BC"].value, state["DE"].value,
        state["HL"].value, state["SP"].value)
end

local taps = {
    {0xE716, "BDOS"},        -- cpnos.com BDOS entry
    {0xEDBF, "SNDMSG"},      -- SDCC SNDMSG body
    {0xEE30, "RCVMSG"},      -- SDCC RCVMSG body
    {0xDDFF, "COLDST"},      -- NDOS COLDST entry
    {0xDEA2, "NDOSE"},       -- NDOS BDOS dispatch
    {0xD986, "NDOSA"},       -- NDOS-set BDOS pointer slot
}

local function on_entry(name, addr)
    return function(offset, data, mask)
        if state["PC"].value ~= addr then return end
        local sp = state["SP"].value
        local ret_lo = prog:read_u8(sp)
        local ret_hi = prog:read_u8(sp + 1)
        local retaddr = ret_lo + ret_hi * 256
        -- Filter: log calls FROM cpnos.com (NDOS/BDOS internal) for SNDMSG/RCVMSG;
        -- log every BDOS/COLDST/NDOSE/NDOSA call regardless of caller.
        local from_cpnos = (retaddr >= 0xDD80 and retaddr <= 0xE9FF)
        local is_special = (name == "BDOS" or name == "COLDST"
            or name == "NDOSE" or name == "NDOSA")
        if not is_special and not from_cpnos then return end
        hit_count = hit_count + 1
        log_line(string.format("[%9.4fs] %-7s %s ret=%04X",
            emu.time(), name, regs_str(), retaddr))
    end
end

local installed = false
emu.register_periodic(function()
    if not installed then
        cpu = manager.machine.devices[":maincpu"]
        if cpu == nil then return end
        prog = cpu.spaces["program"]
        state = cpu.state
        if prog == nil then return end
        for _, t in ipairs(taps) do
            local addr, name = t[1], t[2]
            prog:install_read_tap(addr, addr, "min_"..name, on_entry(name, addr))
        end
        log_line(string.format("[%9.4fs] === minimal trace start (timeout=%.1fs) ===",
            emu.time(), TIMEOUT_S))
        installed = true
    end
    if emu.time() >= TIMEOUT_S then
        log_line(string.format("[%9.4fs] === end (hits=%d) ===", emu.time(), hit_count))
        out_f:close()
        manager.machine:exit()
    end
end)
