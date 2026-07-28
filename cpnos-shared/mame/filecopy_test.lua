-- FILECOPY file-I/O regression (target: `make cpnos-filecopy-test`).
--
-- Pure CP/NET file I/O driven from the slave's E: drive (= master I:).
-- FILECOPY.COM (on drive_i) reads SUMTEST.ASM record-by-record via BDOS
-- F_READ and writes each record to SUMTEST.CPY via BDOS F_WRITE, then prints
-- "FILECOPY OK <hex_count>" before warm-boot. No assembler in the timed path.
--
-- PASS when SIO-B shows "FILECOPY OK" after the run; FAIL on timeout.
-- Adapted from sumtest_test.lua / todget_test.lua.

local compiler = os.getenv("COMPILER") or "clang"
local addrs = dofile(compiler .. "/cpnos_polypascal_addrs.lua")
local KBD_HEAD = addrs.kbd_head
local KBD_RING = addrs.kbd_ring
local MARKER = os.getenv("FILECOPY_MARKER") or "FILECOPY OK"

local transport = os.getenv("TRANSPORT") or "pio-irq"
local function select_transport_dip()
    pcall(function()
        local dsw = manager.machine.ioport.ports[":DSW"]
        if not dsw then error(":DSW port not found") end
        local f = dsw.fields["S03 cpnos transport (On=PIO, Off=SIO)"]
        if not f then error("S03 field not found") end
        local want = (transport == "sio") and 0x04 or 0x00
        if f.set_value then f:set_value(want) else f.user_value = want end
    end)
end
local dip_set_done = false

local SIOB_RAW = "/tmp/cpnos_siob.raw"
local RESULT   = "/tmp/cpnos_filecopy_result.txt"
local LOG      = "/tmp/cpnos_filecopy_log.txt"
do local f = io.open(LOG, "w") if f then f:close() end end
do local f = io.open(RESULT, "w") if f then f:close() end end

local function logln(s)
    local f = io.open(LOG, "a")
    if f then f:write(string.format("[%6.2fs] %s\n", emu.time(), s)) f:close() end
end
local function set_result(s)
    local f = io.open(RESULT, "w")
    if f then f:write(s .. "\n") f:close() end
end
local function read_siob()
    local f = io.open(SIOB_RAW, "rb")
    if not f then return "" end
    local s = f:read("*a")
    f:close()
    return s or ""
end

local prog
local pending = ""
local pace_at = 0
local stage = 0
local stage_at = 0
local timeout_s = 0
local mark_len = 0

local function inject(b)
    local h = prog:read_u8(KBD_HEAD)
    prog:write_u8(KBD_RING + h, b)
    prog:write_u8(KBD_HEAD, (h + 1) % 16)
end
local function feed(s) pending = pending .. s; logln(string.format("feed: %q", s)) end
local function start_stage(n, deadline_secs, msg)
    stage = n; stage_at = emu.time(); timeout_s = deadline_secs
    logln(string.format("=== stage %d (deadline %ds): %s", n, deadline_secs, msg))
end
local function fail(reason)
    set_result("FAIL: " .. reason); logln("FAIL: " .. reason)
    stage = 99; stage_at = emu.time()
end
local function pass(reason)
    set_result("PASS: " .. reason); logln("PASS: " .. reason)
    stage = 99; stage_at = emu.time()
end

emu.register_periodic(function()
    if not dip_set_done then dip_set_done = true; select_transport_dip() end
    if prog == nil then
        local cpu = manager.machine.devices[":maincpu"]
        if cpu == nil then return end
        prog = cpu.spaces["program"]
        if prog == nil then return end
    end
    local t = emu.time()

    if #pending > 0 and t > pace_at then
        inject(pending:byte(1)); pending = pending:sub(2)
        pace_at = t + 0.10
    end

    if stage == 0 then
        if t < 12.0 then return end
        start_stage(1, 60, "wait for E> boot prompt")
        return
    end

    -- Stage 1: E> -> run FILECOPY.
    if stage == 1 then
        if read_siob():find("E>", 1, true) then
            mark_len = #read_siob()
            logln("E> seen; feeding filecopy")
            feed("filecopy\r")
            start_stage(2, 120, "wait for 'FILECOPY OK' marker")
            return
        end
        if t - stage_at > timeout_s then fail("timeout waiting for boot E>") end
        return
    end

    -- Stage 2: FILECOPY OK marker.
    if stage == 2 then
        local tail = read_siob():sub(mark_len + 1)
        local m = tail:match(MARKER .. " %x+") or (tail:find(MARKER, 1, true) and MARKER)
        if m then
            pass("FILECOPY read+wrote SUMTEST.ASM -> SUMTEST.CPY ('" .. tostring(m) .. "')")
            return
        end
        if t - stage_at > timeout_s then
            fail("no '" .. MARKER .. "' in " .. timeout_s .. "s; tail=" ..
                string.format("%q", tail:sub(-200)))
        end
        return
    end

    if stage == 99 then
        if t - stage_at > 2.0 then manager.machine:exit() end
        return
    end
end)
