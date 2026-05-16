-- conotest_test.lua -- CP/NOS slave + CONOTEST.COM display-control
-- code stress test.  Drives the slave through:
--
--   E>           type "CONOTEST" + CR
--   CONOTEST.COM runs:
--                clear screen + XY position + insert/delete line +
--                LF-at-bottom scroll, etc.  Final printf either
--                "PASS: ALL CONOUT TESTS PASSED" or "FAIL: see above".
--   ...          test spins after final printf.
--
-- Validation: scrape /tmp/cpnos_siob.raw for "PASS:" / "FAIL:".  The
-- slave's impl_conout mirrors every byte to SIO-B so the printf
-- output is visible there in addition to the CRT.
--
-- Result -> /tmp/cpnos_polypascal_result.txt (we reuse the file
-- the existing polypascal-test plumbing watches).
--
-- BSS addresses for kbd_head/kbd_ring come from
-- $(BUILDDIR)/cpnos_polypascal_addrs.lua just like polypascal_test.lua.

local compiler = os.getenv("COMPILER") or "clang"
local addrs = dofile(compiler .. "/cpnos_polypascal_addrs.lua")
local KBD_HEAD = addrs.kbd_head
local KBD_RING = addrs.kbd_ring

local SIOB_RAW = "/tmp/cpnos_siob.raw"
local RESULT   = "/tmp/cpnos_polypascal_result.txt"
local LOG      = "/tmp/cpnos_polypascal_log.txt"
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

local prog, state, pending, pace_at, stage, stage_at, timeout_s
pending = ""
pace_at = 0
stage = 0
stage_at = 0
timeout_s = 0

local function inject(c)
    if prog == nil then
        local cpu = manager.machine.devices[":maincpu"]
        if cpu == nil then return end
        prog = cpu.spaces["program"]
        state = cpu.state
    end
    if prog == nil then return end
    local head = prog:read_u8(KBD_HEAD)
    prog:write_u8(KBD_RING + head, c)
    prog:write_u8(KBD_HEAD, head + 1)
end

local function feed(s)
    pending = pending .. s
    logln("feed: " .. string.format("%q", s))
end

local function start_stage(n, deadline_secs, msg)
    stage = n
    stage_at = emu.time()
    timeout_s = deadline_secs
    logln(string.format("=== stage %d (deadline %ds): %s", n, deadline_secs, msg))
end
local function fail(reason)
    set_result("FAIL: " .. reason)
    logln("FAIL: " .. reason)
    stage = 99
    stage_at = emu.time()
end
local function pass(reason)
    set_result("PASS: " .. reason)
    logln("PASS: " .. reason)
    stage = 99
    stage_at = emu.time()
end

emu.register_periodic(function()
    local t = emu.time()

    if #pending > 0 and t > pace_at then
        inject(pending:byte(1)); pending = pending:sub(2)
        pace_at = t + 0.10
    end

    -- Stage 0: wait for E> boot prompt.
    if stage == 0 then
        if t < 12.0 then return end
        start_stage(1, 30, "wait for E> on SIO-B; type CONOTEST")
        return
    end

    -- Stage 1: see "E>" on SIO-B, then run CONOTEST.
    if stage == 1 then
        local raw = read_siob()
        if raw:find("E>", 1, true) then
            logln("E> seen; feeding CONOTEST<CR>")
            feed("CONOTEST\r")
            start_stage(2, 60, "wait for PASS:/FAIL: from CONOTEST")
            return
        elseif t > stage_at + timeout_s then
            fail("timeout waiting for E> boot prompt")
        end
        return
    end

    -- Stage 2: CONOTEST runs the 4 sub-tests and prints PASS:/FAIL:.
    if stage == 2 then
        local raw = read_siob()
        if raw:find("PASS: ALL CONOUT TESTS PASSED", 1, true) then
            pass("CONOTEST: all 4 sub-tests green (T1 position, T2 scroll, T3 ins, T4 del)")
            return
        elseif raw:find("FAIL: see above", 1, true) then
            fail("CONOTEST reported FAIL -- check siob.raw for which sub-test")
            return
        elseif t > stage_at + timeout_s then
            fail("timeout waiting for CONOTEST verdict on SIO-B")
        end
        return
    end

    -- Stage 99: snapshot + exit.
    if stage == 99 and t > stage_at + 1.0 then
        pcall(function() manager.machine.video:snapshot() end)
        manager.machine:exit()
    end
end)
