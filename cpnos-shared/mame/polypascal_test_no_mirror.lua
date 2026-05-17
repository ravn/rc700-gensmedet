-- PolyPascal regression test, NO-MIRROR variant.
--
-- Twin of polypascal_test.lua but reads prompts + completion markers
-- from the slave's 25x80 display RAM at 0xF800..0xFFCF instead of
-- /tmp/cpnos_siob.raw.  Used with cpnos-rom built MIRROR_SIOB=0 so the
-- slave's impl_conout does not busy-wait on SIO-B TX after every char
-- (saves ~1 ms/char at 9600 baud * thousands of chars).
--
-- Caveats:
--   * Display memory scrolls when the cursor passes row 24; the
--     interesting markers (>>, E>, 29989) can disappear if we don't
--     check often enough.  We poll every frame (50 Hz).
--   * "29989" might be in row 23, then scroll up to row 22, then 21,
--     ... while we're checking.  We snapshot the whole screen text on
--     each poll so any frame catches it as long as it's on-screen.
--   * No history buffer (unlike SIO-B raw which is append-only), so a
--     marker that flashes on for one row and scrolls off in less than
--     one poll interval (20 ms) could be missed.  PRIMES prints to
--     CONOUT one prime per call -- each call takes >> 20 ms even
--     without MIRROR_SIOB, so we're safe.

local compiler = os.getenv("COMPILER") or "clang"
local addrs = dofile(compiler .. "/cpnos_polypascal_addrs.lua")
local KBD_HEAD = addrs.kbd_head
local KBD_RING = addrs.kbd_ring

local RESULT = "/tmp/cpnos_polypascal_result.txt"
local LOG    = "/tmp/cpnos_polypascal_log.txt"
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

local prog
local pending = ""
local pace_at = 0
local stage = 0
local stage_at = 0
local timeout_s = 0
-- Persistent "ever-seen" flags for content that we care about across
-- the test.  E> and 29989 we latch on first sight (they can scroll off
-- but we still want to remember).  ">>" prompts have to be edge-
-- detected because PRIMES prints thousands of lines and scrolls every
-- earlier ">>" off the screen -- absolute counts collapse to 0..1
-- during heavy output.
local seen_e_prompt    = false
local seen_29989       = false
local seen_e_back      = false
-- Per-stage ">>" baseline.  When entering a stage that waits for a
-- new ">>", capture the count at that moment and trip when count
-- increases beyond it (or any positive count appears after scroll
-- erased the baseline).
local pp_baseline      = 0

local function read_screen()
    local lines = {}
    for r = 0, 24 do
        local chars = {}
        local base = 0xF800 + r * 80
        for c = 0, 79 do
            local b = prog:read_u8(base + c)
            chars[#chars+1] = (b >= 0x20 and b < 0x7F) and string.char(b) or " "
        end
        lines[#lines+1] = table.concat(chars)
    end
    return table.concat(lines, "\n")
end

local function count(s, pat)
    local n, i = 0, 1
    while true do
        local j = s:find(pat, i, true)
        if not j then return n end
        n = n + 1
        i = j + #pat
    end
end

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
end
local function pass(reason)
    set_result("PASS: " .. reason)
    logln("PASS: " .. reason)
    stage = 99
end

emu.register_periodic(function()
    if prog == nil then
        local cpu = manager.machine.devices[":maincpu"]
        if cpu == nil then return end
        prog = cpu.spaces["program"]
        if prog == nil then return end
    end
    local t = emu.time()

    -- Pace key injection at ~10/sec.
    if #pending > 0 and t > pace_at then
        inject(pending:byte(1)); pending = pending:sub(2)
        pace_at = t + 0.10
    end

    -- Sample the screen text once per tick.  Latch E> + 29989 on
    -- first sight; ">>" detection is edge-triggered per stage via
    -- pp_baseline (since scrolling erases the baseline mid-stage).
    local screen, pp_now
    if prog and stage ~= 99 then
        screen = read_screen()
        pp_now = count(screen, ">>")
        if not seen_e_prompt and screen:find("E>",    1, true) then seen_e_prompt = true end
        if not seen_29989    and screen:find("29989", 1, true) then seen_29989    = true end
        if stage >= 5 and screen:find("E>", 1, true) then seen_e_back = true end
    end

    -- Stage 0: wait until boot is well past banner+netboot dots+stamp.
    if stage == 0 then
        if t < 12.0 then return end
        start_stage(1, 30, "wait for E> on display; type PPAS<CR>")
        return
    end

    if stage == 1 then
        if seen_e_prompt then
            logln("E> seen on display; feeding PPAS<CR>")
            feed("PPAS\r")
            pp_baseline = pp_now or 0
            start_stage(2, 60, "wait for PPAS '>>' prompt (initial)")
        elseif t > stage_at + timeout_s then
            fail("timeout waiting for E> boot prompt")
        end
        return
    end

    if stage == 2 then
        if pp_now and pp_now > pp_baseline then
            logln(">> seen; feeding L PRIMES<CR>")
            feed("L PRIMES\r")
            pp_baseline = pp_now
            start_stage(25, 60, "wait for second '>>' (load complete)")
        elseif t > stage_at + timeout_s then
            fail("timeout waiting for initial PPAS >>")
        end
        return
    end

    if stage == 25 then
        if pp_now and pp_now > pp_baseline then
            logln("post-load >> seen; feeding R<CR>")
            feed("R\r")
            pp_baseline = pp_now    -- snapshot before primes scrolling
            start_stage(3, 180, "wait for primes output (29989)")
        elseif t > stage_at + timeout_s then
            fail("timeout waiting for post-load PPAS >>")
        end
        return
    end

    if stage == 3 then
        if seen_29989 then
            logln("29989 seen; primes output complete")
            -- During primes output, scrolling collapsed the visible
            -- ">>" count to ~0.  Re-baseline now so stage 4 detects
            -- the new prompt that appears once PRIMES returns to PPAS.
            pp_baseline = pp_now or 0
            start_stage(4, 30, "wait for post-Run >> prompt")
        elseif t > stage_at + timeout_s then
            fail("timeout waiting for primes output 29989")
        end
        return
    end

    if stage == 4 then
        if pp_now and pp_now > pp_baseline then
            logln("post-Run >> seen; feeding Q<CR>")
            feed("Q\r")
            start_stage(5, 30, "wait for return to E> prompt")
        elseif t > stage_at + timeout_s then
            fail("timeout waiting for post-Run PPAS >>")
        end
        return
    end

    if stage == 5 then
        if seen_e_back then
            pass("PPAS PRIMES ran to completion (29989 seen) and Q returned to E>")
            manager.machine:exit()
        elseif t > stage_at + timeout_s then
            fail("timeout waiting for return to E> after Q")
            manager.machine:exit()
        end
        return
    end
end)
