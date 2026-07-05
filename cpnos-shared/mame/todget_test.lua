-- TODGET regression test (target: `make cpnos-todget-test`).
--
-- Boots cpnos, waits for the E> prompt, types `TODGET<CR>`, and
-- waits ~20 seconds for the FN 105 round-trip to complete.  Captures
-- everything via the SIO-B mirror at /tmp/cpnos_siob.raw — that file
-- carries the cpnos banner, READ-SEQ dots, build stamp, the E> prompt,
-- and the TODGET output (BDOS-version line + payload hex + ASCII).
--
-- Result lands at /tmp/cpnos_todget_result.txt as PASS or FAIL.
-- We declare PASS when the SIO-B contains "TODGET:" lines after the
-- E> prompt (since the slave's CCP prints what TODGET prints).
-- FAIL on timeout or missing TODGET output.
--
-- Adapted from polypascal_test.lua — same kbd_ring inject + stage
-- machinery, less of it.

local compiler = os.getenv("COMPILER") or "clang"
local addrs = dofile(compiler .. "/cpnos_polypascal_addrs.lua")
local KBD_HEAD = addrs.kbd_head
local KBD_RING = addrs.kbd_ring

-- Default S03 to PIO (same as polypascal_test.lua) so the runtime
-- transport matches what the harness expects.
local transport = os.getenv("TRANSPORT") or "pio-irq"
local function select_transport_dip()
    local ok, err = pcall(function()
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
local RESULT   = "/tmp/cpnos_todget_result.txt"
local LOG      = "/tmp/cpnos_todget_log.txt"
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
local e_prompt_at = 0       -- emu.time() when we first saw E>
local e_prompt_siob_len = 0 -- SIO-B length at that moment

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
    if not dip_set_done then dip_set_done = true; select_transport_dip() end
    if prog == nil then
        local cpu = manager.machine.devices[":maincpu"]
        if cpu == nil then return end
        prog = cpu.spaces["program"]
        if prog == nil then return end
    end
    local t = emu.time()

    -- Drain queued keystrokes into kbd_ring at ~10/sec.
    if #pending > 0 and t > pace_at then
        inject(pending:byte(1)); pending = pending:sub(2)
        pace_at = t + 0.10
    end

    -- Stage 0: wait for the boot to settle.
    if stage == 0 then
        if t < 12.0 then return end
        start_stage(1, 60, "wait for E> on SIO-B")
        return
    end

    -- Stage 1: see E>, feed TODGET<CR>.
    if stage == 1 then
        local raw = read_siob()
        if raw:find("E>", 1, true) then
            e_prompt_at = t
            e_prompt_siob_len = #raw
            logln(string.format("E> seen at %.2fs (SIO-B len=%d); feeding TODGET<CR>",
                t, e_prompt_siob_len))
            feed("TODGET\r")
            start_stage(2, 30, "wait for TODGET output")
            return
        end
        if t - stage_at > timeout_s then
            fail("timeout waiting for E> boot prompt")
        end
        return
    end

    -- Stage 2: TODGET prints multi-line output starting "TODGET: ...".
    -- Wait for at least one such line to appear after the E> prompt.
    if stage == 2 then
        local raw = read_siob()
        local tail = raw:sub(e_prompt_siob_len + 1)
        if tail:find("TODGET:", 1, true) then
            -- Give it a couple more seconds to print the full payload.
            if t - stage_at > 8.0 then
                pass(string.format("TODGET ran; %d bytes after E> (see siob.raw)",
                    #tail))
            end
            return
        end
        if t - stage_at > timeout_s then
            fail(string.format("no TODGET: output in %d s after E>; tail=%q",
                timeout_s, tail:sub(1, 200)))
        end
        return
    end

    -- Stage 99: post-mortem.  Wait a couple seconds, then exit.
    if stage == 99 then
        if t - stage_at > 2.0 then
            manager.machine:exit()
        end
        return
    end
end)
