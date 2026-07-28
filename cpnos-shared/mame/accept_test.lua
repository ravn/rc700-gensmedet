-- Combined clang cpnos acceptance in a SINGLE MAME run (target: `make
-- cpnos-accept`).  Boots the slave once, then drives it through all four
-- workloads in sequence at the E: prompt:
--     1. gettod    -- TODGET, FN-105 time-from-master  -> "TODGET: master"
--     2. ppas      -- PPAS PRIMES to 29989             -> "29989"
--     3. sumtest   -- m80 + l80 + run                  -> "CPNET OK A314"
--     4. filecopy  -- FILECOPY.COM read+write          -> "FILECOPY OK"
-- Fault-tolerant: a step that times out is recorded FAIL and the driver moves
-- on to the next.  Per-step + overall PASS/FAIL land in
-- /tmp/cpnos_accept_result.txt; the make target greps it.
--
-- Everything runs from E: (= master I:, the drive_i tool set + generated
-- sumtest.asm), so this needs no A: cramming and no cpnos-rom image.

local compiler = os.getenv("COMPILER") or "clang"
local addrs = dofile(compiler .. "/cpnos_polypascal_addrs.lua")
local KBD_HEAD = addrs.kbd_head
local KBD_RING = addrs.kbd_ring

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
local RESULT   = "/tmp/cpnos_accept_result.txt"
local LOG      = "/tmp/cpnos_accept_log.txt"
do local f = io.open(LOG, "w") if f then f:close() end end
do local f = io.open(RESULT, "w") if f then f:close() end end

local function logln(s)
    local f = io.open(LOG, "a")
    if f then f:write(string.format("[%6.2fs] %s\n", emu.time(), s)) f:close() end
end
local function read_siob()
    local f = io.open(SIOB_RAW, "rb")
    if not f then return "" end
    local s = f:read("*a"); f:close(); return s or ""
end

-- ordered per-step results
local results = {}
local function record(name, ok, note)
    results[#results + 1] = { name = name, ok = ok, note = note or "" }
    logln(string.format("RESULT %-9s %s %s", name, ok and "PASS" or "FAIL", note or ""))
end
local function write_results()
    local f = io.open(RESULT, "w"); if not f then return end
    -- Per-step lines are INDENTED so they never match the reused
    -- cpnos-polypascal-test `grep -q '^PASS'` gate; only the overall line
    -- starts at column 0 with PASS:/FAIL:.
    local all = true
    local failed = {}
    for _, r in ipairs(results) do
        f:write(string.format("  %-9s %s  %s\n", r.name, r.ok and "PASS" or "FAIL", r.note))
        all = all and r.ok
        if not r.ok then failed[#failed + 1] = r.name end
    end
    if all then
        f:write("PASS: all four cpnos workloads (gettod ppas sumtest filecopy)\n")
    else
        f:write("FAIL: " .. table.concat(failed, " ") .. "\n")
    end
    f:close()
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
local function goto_stage(n, deadline, msg)
    stage = n; stage_at = emu.time(); timeout_s = deadline
    logln(string.format("=== stage %d (deadline %ds): %s", n, deadline, msg))
end
local function tail() return read_siob():sub(mark_len + 1) end
local function mark() mark_len = #read_siob() end
-- true once a fresh E> appears after the last mark() (command returned to CCP)
local function prompt_back() return tail():find("E>", 1, true) ~= nil end

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
        inject(pending:byte(1)); pending = pending:sub(2); pace_at = t + 0.10
    end

    -- 0: brief guard past reset, then poll for E> (was a fixed 12 s wait that
    -- idled ~8 s after E> already appeared at ~4 s; stage 1 gates on real E>).
    if stage == 0 then
        if t < 2.0 then return end
        goto_stage(1, 60, "wait for first E> boot prompt")
        return
    end
    if stage == 1 then
        if read_siob():find("E>", 1, true) then
            mark(); logln("E> seen; starting gettod"); feed("TODGET\r")
            goto_stage(10, 30, "gettod: wait TODGET master time")
        elseif t - stage_at > timeout_s then
            -- never booted: everything fails.
            record("gettod", false, "no boot E>"); record("ppas", false, "no boot E>")
            record("sumtest", false, "no boot E>"); record("filecopy", false, "no boot E>")
            goto_stage(90, 2, "no boot")
        end
        return
    end

    -- === 1. gettod (CHECK THE CLOCK IS CORRECT: master date == host today) ===
    if stage == 10 then
        local d, tm = tail():match("master.-(%d%d%d%d%-%d%d%-%d%d)%s+(%d%d:%d%d:%d%d)")
        if d then
            local today = os.date("%Y-%m-%d")
            if d == today then
                record("gettod", true, "clock correct " .. d .. " " .. tm)
            else
                record("gettod", false, "clock WRONG " .. d .. " != host " .. today)
            end
            goto_stage(11, 15, "gettod: wait E> back")
        elseif t - stage_at > timeout_s then
            record("gettod", false, "no valid master time (gettod garbage?)")
            goto_stage(11, 15, "gettod->ppas")
        end
        return
    end
    if stage == 11 then
        if prompt_back() then
            mark(); feed("PPAS\r"); goto_stage(20, 45, "ppas: wait first >>")
        elseif t - stage_at > timeout_s then
            mark(); feed("PPAS\r"); goto_stage(20, 45, "ppas: wait first >> (forced)")
        end
        return
    end

    -- === 2. ppas primes ===
    if stage == 20 then
        if tail():find(">>", 1, true) then
            mark(); feed("L PRIMES\r"); goto_stage(21, 45, "ppas: wait post-load >>")
        elseif t - stage_at > timeout_s then
            record("ppas", false, "no PPAS >> prompt"); goto_stage(30, 10, "ppas->sumtest skip")
        end
        return
    end
    if stage == 21 then
        if tail():find(">>", 1, true) then
            mark(); feed("R\r"); goto_stage(22, 90, "ppas: wait 29989")
        elseif t - stage_at > timeout_s then
            record("ppas", false, "no load >>"); goto_stage(30, 10, "ppas->sumtest skip")
        end
        return
    end
    if stage == 22 then
        if tail():find("29989", 1, true) then
            mark(); goto_stage(23, 30, "ppas: wait post-run >>")
        elseif t - stage_at > timeout_s then
            record("ppas", false, "primes did not reach 29989"); goto_stage(30, 10, "skip")
        end
        return
    end
    if stage == 23 then
        if tail():find(">>", 1, true) then
            mark(); feed("Q\r"); goto_stage(24, 30, "ppas: wait E> back")
        elseif t - stage_at > timeout_s then
            record("ppas", true, "29989 seen (no post >>)"); goto_stage(30, 10, "ppas->sumtest")
        end
        return
    end
    if stage == 24 then
        if prompt_back() then
            record("ppas", true, "primes to 29989, Q->E>")
            mark(); feed("m80 sumtest,=sumtest.asm\r"); goto_stage(30, 240, "sumtest: wait M80 E>")
        elseif t - stage_at > timeout_s then
            record("ppas", true, "29989 seen")
            mark(); feed("m80 sumtest,=sumtest.asm\r"); goto_stage(30, 240, "sumtest: wait M80 (forced)")
        end
        return
    end

    -- === 3. sumtest (m80 + l80 + run) ===
    if stage == 30 then
        if prompt_back() then
            mark(); feed("l80 sumtest,sumtest/n/e\r"); goto_stage(31, 90, "sumtest: wait L80 E>")
        elseif t - stage_at > timeout_s then
            record("sumtest", false, "M80 assemble timeout"); goto_stage(40, 10, "sumtest->filecopy skip")
        end
        return
    end
    if stage == 31 then
        if prompt_back() then
            mark(); feed("sumtest\r"); goto_stage(32, 45, "sumtest: wait CPNET OK")
        elseif t - stage_at > timeout_s then
            record("sumtest", false, "L80 link timeout"); goto_stage(40, 10, "sumtest->filecopy skip")
        end
        return
    end
    if stage == 32 then
        local ta = tail()
        if ta:find("CPNET OK A314", 1, true) then
            record("sumtest", true, "CPNET OK A314")
            goto_stage(33, 15, "sumtest: wait E> back")
        elseif ta:match("CPNET OK %x%x%x%x") then
            record("sumtest", false, "wrong: " .. ta:match("CPNET OK %x%x%x%x"))
            goto_stage(33, 15, "sumtest->filecopy")
        elseif t - stage_at > timeout_s then
            record("sumtest", false, "no CPNET OK"); goto_stage(40, 10, "sumtest->filecopy")
        end
        return
    end
    if stage == 33 then
        if prompt_back() then
            mark(); feed("filecopy\r"); goto_stage(40, 120, "filecopy: wait FILECOPY OK")
        elseif t - stage_at > timeout_s then
            mark(); feed("filecopy\r"); goto_stage(40, 120, "filecopy (forced)")
        end
        return
    end

    -- === 4. filecopy ===
    if stage == 40 then
        local m = tail():match("FILECOPY OK %x+") or (tail():find("FILECOPY OK", 1, true) and "FILECOPY OK")
        if m then
            record("filecopy", true, tostring(m)); goto_stage(90, 2, "all done")
        elseif t - stage_at > timeout_s then
            record("filecopy", false, "no FILECOPY OK marker"); goto_stage(90, 2, "done (filecopy fail)")
        end
        return
    end

    -- 90: write results and exit.
    if stage == 90 then
        write_results()
        if t - stage_at > 2.0 then manager.machine:exit() end
        return
    end
end)
