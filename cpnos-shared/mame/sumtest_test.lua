-- SUMTEST file-I/O regression (target: `make cpnos-sumtest-test`).
--
-- Non-trivial CP/NET file test driven entirely from the slave's E: drive
-- (= master I:, the drive_i tool set + the generated sumtest.asm).  At E> it
-- assembles + links + runs an unrolled sum(1..1000) program:
--     m80 sumtest,=sumtest.asm      (read .asm, write .rel)
--     l80 sumtest,sumtest/n/e       (read .rel, write .com)
--     sumtest                       (execute; prints "CPNET OK A314")
-- Every stage exercises CP/NET OPEN/READ/WRITE against the master.  A correct
-- run prints exactly "CPNET OK A314"; any file-I/O / CCP / BDOS regression
-- corrupts an intermediate and the final string differs or the run crashes.
--
-- PASS when SIO-B shows "CPNET OK A314" after the run; FAIL on timeout or a
-- wrong "CPNET OK" value.  Adapted from todget_test.lua (same kbd inject +
-- stage machinery).

local compiler = os.getenv("COMPILER") or "clang"
local addrs = dofile(compiler .. "/cpnos_polypascal_addrs.lua")
local KBD_HEAD = addrs.kbd_head
local KBD_RING = addrs.kbd_ring
local EXPECT = os.getenv("SUMTEST_EXPECT") or "CPNET OK A314"

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
local RESULT   = "/tmp/cpnos_sumtest_result.txt"
local LOG      = "/tmp/cpnos_sumtest_log.txt"
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
local mark_len = 0   -- SIO-B length captured when a command was fed

local function inject(b)
    local h = prog:read_u8(KBD_HEAD)
    prog:write_u8(KBD_RING + h, b)
    prog:write_u8(KBD_HEAD, (h + 1) % 16)
end
local function feed(s)
    pending = pending .. s
    logln(string.format("feed: %q", s))
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
    stage = 99; stage_at = emu.time()
end
local function pass(reason)
    set_result("PASS: " .. reason)
    logln("PASS: " .. reason)
    stage = 99; stage_at = emu.time()
end

-- Wait for a fresh "E>" prompt to appear in SIO-B after byte offset `mark_len`
-- (i.e. after the command we just fed returned to the CCP).  Returns true once
-- seen.  Ignores the command echo (which never contains "E>").
local function prompt_returned()
    local raw = read_siob()
    return raw:sub(mark_len + 1):find("E>", 1, true) ~= nil
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
        -- 2 s guard past reset, then poll for E> (E> appears ~4 s; the old 12 s
        -- fixed wait idled ~8 s). Stage 1 still gates on the real E> prompt.
        if t < 2.0 then return end
        start_stage(1, 60, "wait for first E> boot prompt")
        return
    end

    -- Stage 1: first E> -> assemble.
    if stage == 1 then
        if read_siob():find("E>", 1, true) then
            mark_len = #read_siob()
            logln("E> seen; feeding m80 assemble")
            feed("m80 sumtest,=sumtest.asm\r")
            start_stage(2, 120, "wait for M80 to finish (E> returns)")
            return
        end
        if t - stage_at > timeout_s then fail("timeout waiting for boot E>") end
        return
    end

    -- Stage 2: M80 done -> link.
    if stage == 2 then
        if prompt_returned() then
            mark_len = #read_siob()
            logln("M80 done (E> back); feeding l80 link")
            feed("l80 sumtest,sumtest/n/e\r")
            start_stage(3, 90, "wait for L80 to finish (E> returns)")
            return
        end
        if t - stage_at > timeout_s then fail("timeout in M80 assemble") end
        return
    end

    -- Stage 3: L80 done -> run.
    if stage == 3 then
        if prompt_returned() then
            mark_len = #read_siob()
            logln("L80 done (E> back); feeding sumtest run")
            feed("sumtest\r")
            start_stage(4, 45, "wait for 'CPNET OK' from the program")
            return
        end
        if t - stage_at > timeout_s then fail("timeout in L80 link") end
        return
    end

    -- Stage 4: program output.
    if stage == 4 then
        local tail = read_siob():sub(mark_len + 1)
        if tail:find(EXPECT, 1, true) then
            pass("SUMTEST assembled+linked+ran, got '" .. EXPECT .. "'")
            return
        end
        -- Wrong "CPNET OK <hex>" = a real miscompute/I-O corruption.
        local got = tail:match("CPNET OK %x%x%x%x")
        if got and got ~= EXPECT then
            fail("wrong result: got '" .. got .. "', want '" .. EXPECT .. "'")
            return
        end
        if t - stage_at > timeout_s then
            fail("no 'CPNET OK' in " .. timeout_s .. "s; tail=" ..
                string.format("%q", tail:sub(-200)))
        end
        return
    end

    if stage == 99 then
        if t - stage_at > 2.0 then manager.machine:exit() end
        return
    end
end)
