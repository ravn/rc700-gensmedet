-- PolyPascal regression test (target: `make cpnos-polypascal-test`).
--
-- Drives the slave through:
--   E>           type "PPAS PRIMES" + CR    (PPAS = the PolyPascal
--                                            interpreter command)
--   <PPAS loads> watch for ">>" command prompt
--   >>           type "R" (Run)
--   <primes>     watch SIO-B mirror for the last known prime "29989"
--   >>           type "Q" (Quit, returns to CCP)
--   E>           sanity-check the prompt is back, exit
--
-- Direct kbd_ring injection because MAME's natural-keyboard layer
-- doesn't fully cover the RC702 driver (separately tracked).
-- Validation: scrape /tmp/cpnos_siob.raw which captures every byte
-- impl_conout sends (cpnos-rom built with MIRROR_SIOB=1).
--
-- Result lands at /tmp/cpnos_polypascal_result.txt:
--   "PASS"  + a one-line summary, OR
--   "FAIL: <reason>"

-- BSS addresses for kbd_head/kbd_ring are extracted at build time into
-- $(BUILDDIR)/cpnos_polypascal_addrs.lua, where BUILDDIR == COMPILER.
-- Honour COMPILER= so SDCC runs read the SDCC addresses (kbd_ring at
-- 0xEC03 in bss_compiler) instead of clang's (0xF52C in scratch_bss).
-- Issue #58.
local compiler = os.getenv("COMPILER") or "clang"
local addrs = dofile(compiler .. "/cpnos_polypascal_addrs.lua")
local KBD_HEAD = addrs.kbd_head
local KBD_RING = addrs.kbd_ring

-- Tap writes to ROW only (0x4003) so we can see the PC of every
-- cursor-row bump after handoff.  In-memory buffer flushed once at
-- PASS/FAIL — per-write file I/O slowed MAME down enough that the
-- test timed out.
local dot_watch_installed = false
local dot_watch_buf = {}
DOT_WATCH_ENABLED = true   -- always on; flush at stage 2 cutoff
local DOT_LOG = "/tmp/cpnos_dot_watch.log"
local function flush_dot_watch()
    local f = io.open(DOT_LOG, "w")
    if not f then return end
    f:write("# row-state tap (PC, new ROW value)\n")
    for _, line in ipairs(dot_watch_buf) do f:write(line) end
    f:close()
end
local function maybe_install_dot_watch()
    if dot_watch_installed then return end
    local cpu = manager.machine.devices[":maincpu"]
    if cpu == nil then return end
    local prog = cpu.spaces["program"]
    local cpu_state = cpu.state
    if prog == nil or cpu_state == nil then return end
    -- Wider tap covering DOT_CURSOR + DOT_COL + DOT_ROW (0x4000..0x4003).
    -- Stays installed for whole boot; arm/disarm via DOT_WATCH_ENABLED.
    prog:install_write_tap(0x4000, 0x4003, "dot_watch", function(offs, data)
        if not DOT_WATCH_ENABLED then return end
        if #dot_watch_buf > 5000 then return end
        local pc = cpu_state["PC"].value
        local name = ({ [0]="CURLO", [1]="CURHI", [2]="COL", [3]="ROW" })[offs - 0x4000] or "?"
        dot_watch_buf[#dot_watch_buf+1] =
            string.format("[%9.4fs] PC=%04x %s=%02x\n",
                emu.time(), pc, name, data)
    end)
    dot_watch_installed = true
end

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

-- Read everything in the SIO-B raw file; returns "" if missing.
local function read_siob()
    local f = io.open(SIOB_RAW, "rb")
    if not f then return "" end
    local s = f:read("*a")
    f:close()
    return s or ""
end

-- Number of times `pat` (literal) appears in s.
local function count(s, pat)
    local n, i = 0, 1
    while true do
        local j = s:find(pat, i, true)
        if not j then return n end
        n = n + 1
        i = j + #pat
    end
end

local prog
local pending = ""
local pace_at = 0
local stage = 0
local stage_at = 0
local timeout_s = 0     -- per-stage deadline

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

    -- (dot_watch disabled: tap callback overhead slowed MAME below
    -- realtime and stalled the test.)
    -- Stage 0: wait for E> boot prompt.
    if stage == 0 then
        if t < 12.0 then return end
        start_stage(1, 30, "wait for E> on SIO-B; type WS launch")
        return
    end

    -- Stage 1: see "E>" on SIO-B, then snap the CRT (pre-PPAS-launch
    -- visual state — checked for boot-residue / scroll-init bugs).
    -- Snap landed at -snapname target path; rename out of the way so
    -- the final-stage snap doesn't overwrite it.
    if stage == 1 then
        local raw = read_siob()
        if raw:find("E>", 1, true) then
            -- Arm the row-watch from now on; pre-handoff banner/dots
            -- are uninteresting and just fill the buffer.
            DOT_WATCH_ENABLED = true
            -- Dump DOT_* state at E>-seen moment.
            pcall(function()
                local cpu = manager.machine.devices[":maincpu"]
                local prog = cpu.spaces["program"]
                local f = io.open("/tmp/cpnos_dsp_at_eprompt.txt", "w")
                f:write(string.format("DOT_COL=%02x DOT_ROW=%02x DOT_CURSOR=%04x\n",
                    prog:read_u8(0x4002), prog:read_u8(0x4003),
                    prog:read_u16(0x4000)))
                f:close()
            end)
            pcall(function() manager.machine.video:snapshot() end)
            -- best-effort rename so the pre-launch snap survives the
            -- final-stage overwrite at stage 99.
            pcall(function()
                os.execute("for f in snap/cpnos_*_ppas.png; do " ..
                    "[ -f \"$f\" ] && mv \"$f\" \"${f%.png}_preppas.png\"; done")
            end)
            logln("E> seen; feeding PPAS<CR>")
            feed("PPAS\r")
            start_stage(2, 60, "wait for PPAS '>>' prompt (initial)")
        elseif t > stage_at + timeout_s then
            fail("timeout waiting for E> boot prompt")
        end
        return
    end

    -- Stage 2: wait for the FIRST ">>" (PPAS startup done), then send
    -- the load command.  Delay-then-feed avoids the keystroke being
    -- queued during PPAS's CP/NET load of PPAS.ERM (which apparently
    -- consumes / drops chars in some path).
    if stage == 2 then
        local raw = read_siob()
        if count(raw, ">>") >= 1 then
            -- Disarm row-watch and flush; we have enough data now.
            DOT_WATCH_ENABLED = false
            flush_dot_watch()
            -- Snap before feeding load command so the CRT state at the
            -- moment PPAS just finished its banner output is captured
            -- (debug: CP/NOS banner row 0 should still be visible).
            pcall(function() manager.machine.video:snapshot() end)
            pcall(function()
                os.execute("for f in snap/cpnos_*_ppas.png; do " ..
                    "[ -f \"$f\" ] && mv \"$f\" \"${f%.png}_ppasstart.png\"; done")
            end)
            -- Dump current DOT_COL/DOT_ROW + first 4 display rows so we
            -- can see where the slave THINKS it's writing vs what the
            -- chip's actually showing.
            pcall(function()
                local cpu = manager.machine.devices[":maincpu"]
                local prog = cpu.spaces["program"]
                local f = io.open("/tmp/cpnos_dsp_at_ppasstart.txt", "w")
                f:write(string.format("DOT_COL=%02x DOT_ROW=%02x DOT_CURSOR=%04x\n",
                    prog:read_u8(0x4002), prog:read_u8(0x4003),
                    prog:read_u16(0x4000)))
                for r = 0, 23 do
                    local base = 0xF800 + r * 80
                    local parts = {}
                    for c = 0, 79 do
                        local b = prog:read_u8(base + c)
                        if b >= 0x20 and b < 0x7F then
                            parts[#parts+1] = string.char(b)
                        else
                            parts[#parts+1] = "."
                        end
                    end
                    f:write(string.format("row %02d: |%s|\n", r, table.concat(parts)))
                end
                f:close()
            end)
            logln(">> seen; feeding L PRIMES<CR>")
            feed("L PRIMES\r")
            start_stage(25, 60, "wait for second '>>' (load complete)")
        elseif t > stage_at + timeout_s then
            fail("timeout waiting for PPAS >> prompt (initial)")
        end
        return
    end

    -- Stage 25: load completed; PPAS prints another ">>".
    if stage == 25 then
        local raw = read_siob()
        if count(raw, ">>") >= 2 then
            logln("post-load >> seen; feeding R<CR>")
            feed("R\r")
            start_stage(3, 120, "wait for primes output to complete")
        elseif t > stage_at + timeout_s then
            fail("timeout waiting for PPAS >> after L PRIMES")
        end
        return
    end

    -- Stage 3: wait for primes output.  PRIMES.PAS prints primes
    -- 1..29989 separated by 8-col fields.  29989 is the largest prime
    -- below 30000.  Once we see it, the program is essentially done.
    if stage == 3 then
        local raw = read_siob()
        if raw:find("29989", 1, true) then
            logln("29989 seen; primes output complete")
            -- Wait briefly for the final >> to come back, then send Q.
            start_stage(4, 30, "wait for post-Run >> prompt")
        elseif t > stage_at + timeout_s then
            fail("timeout waiting for last prime '29989' in output")
        end
        return
    end

    -- Stage 4: PPAS returns to >> after Run finishes.  Need >= 3
    -- occurrences of ">>" (initial PPAS, post-load, post-Run).
    if stage == 4 then
        local raw = read_siob()
        if count(raw, ">>") >= 3 then
            logln("post-Run >> seen; feeding Q<CR>")
            feed("Q\r")        -- PPAS commands need CR to execute
            start_stage(5, 30, "wait for return to E> prompt")
        elseif t > stage_at + timeout_s then
            fail("timeout waiting for post-Run >> prompt")
        end
        return
    end

    -- Stage 5: PPAS quits; CCP echoes "E>" again.  We need >= 2
    -- E>'s in the SIO-B mirror (boot prompt + post-quit prompt).
    if stage == 5 then
        local raw = read_siob()
        if count(raw, "E>") >= 2 then
            pass("PPAS PRIMES ran to completion (29989 seen) and Q returned to E>")
        elseif t > stage_at + timeout_s then
            fail("timeout waiting for E> after Q")
        end
        return
    end

    -- Stage 99: snapshot the CRT for visual verification (HARD rule
    -- feedback_screenshot_to_verify.md -- PASS log lines aren't enough),
    -- pause one second so the result file fully flushes, then exit.
    if stage == 99 and t > stage_at + 1.0 then
        pcall(function() manager.machine.video:snapshot() end)
        -- Dump JIFFY (0xF406..0xF409) and LAST_CURSOR (0xF404..0xF405)
        -- so we can see whether the 50 Hz CTC-CH2 ISR is firing and
        -- whether the cursor-sync path ran.  Non-zero JIFFY == ISR live.
        pcall(function()
            local cpu = manager.machine.devices[":maincpu"]
            local prog = cpu.spaces["program"]
            local f = io.open("/tmp/cpnos_isr_check.txt", "w")
            f:write(string.format("JIFFY = %02x %02x %02x %02x (LE)\n",
                prog:read_u8(0xF406), prog:read_u8(0xF407),
                prog:read_u8(0xF408), prog:read_u8(0xF409)))
            f:write(string.format("LAST_CURSOR = col=%02x row=%02x\n",
                prog:read_u8(0xF404), prog:read_u8(0xF405)))
            f:write(string.format("DOT_COL = %02x DOT_ROW = %02x DOT_CURSOR = %04x\n",
                prog:read_u8(0xF402), prog:read_u8(0xF403),
                prog:read_u16(0xF400)))
            f:write("0xED00..0xED10:\n  ")
            for i = 0, 15 do
                f:write(string.format("%02x ", prog:read_u8(0xED00 + i)))
            end
            f:write("\n")
            local s = cpu.state
            f:write(string.format("Z80 I = %02x, IFF1 = %s, IM = %s\n",
                s["I"].value,
                tostring(s["IFF1"] and s["IFF1"].value),
                tostring(s["IM"] and s["IM"].value)))
            f:write("IVT bytes at 0xF500..0xF51F:\n  ")
            for i = 0, 31 do
                f:write(string.format("%02x ", prog:read_u8(0xF500 + i)))
            end
            f:write("\n")
            f:close()
        end)
        manager.machine:exit()
    end
end)
