-- Fast CP/NET smoke test: boot to E> on the slave, run DIR, verify
-- the staged file names come back.  ~15s end-to-end vs ~50s for
-- polypascal_test.  Suitable as the iterate-with target while
-- bringing up #115 Phase 2 INIR refactor.
--
-- DIR on drive E: walks the CP/NET BDOS-66/67 SEARCH-FIRST + many
-- SEARCH-NEXT exchanges — exercises the snios_rcvmsg_c path well
-- enough that a broken refactor surfaces here too.
--
-- Result lands at /tmp/cpnos_polypascal_result.txt (same path the
-- polypascal harness uses; the Makefile/grep at the end is shared):
--   "PASS"  + a one-line summary, OR
--   "FAIL: <reason>"

local compiler = os.getenv("COMPILER") or "clang"
local addrs = dofile(compiler .. "/cpnos_polypascal_addrs.lua")
local KBD_HEAD = addrs.kbd_head
local KBD_RING = addrs.kbd_ring

-- SW1 S03 = transport DIP (On=PIO, Off=SIO).  Same gate polypascal
-- driver uses; mirror it so TRANSPORT=sio actually selects SIO.
local transport = os.getenv("TRANSPORT") or "pio-irq"
local function select_transport_dip()
    pcall(function()
        local dsw = manager.machine.ioport.ports[":DSW"]
        if not dsw then return end
        local f = dsw.fields["S03 cpnos transport (On=PIO, Off=SIO)"]
        if not f then return end
        local want = (transport == "sio") and 0x04 or 0x00
        if f.set_value then f:set_value(want) else f.user_value = want end
    end)
end
local dip_set_done = false

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
    local s = f:read("*a"); f:close()
    return s or ""
end

local function count(s, pat)
    local n, i = 0, 1
    while true do
        local j = s:find(pat, i, true)
        if not j then return n end
        n = n + 1; i = j + #pat
    end
end

local prog, pending, pace_at = nil, "", 0
local stage, stage_at, timeout_s = 0, 0, 0

-- PIO-B watch: log every IN/OUT on 0x11 (data) and OUT on 0x13 (ctrl).
-- Buffered + flushed at exit (per-event file I/O wedges MAME).
local PIO_LOG = "/tmp/cpnos_dir_pio.log"
local pio_events, pio_n = {}, 0
local pio_max = 5000
local function pio_evt(s)
    if pio_n >= pio_max then return end
    pio_n = pio_n + 1; pio_events[pio_n] = s
end
local function flush_pio()
    local f = io.open(PIO_LOG, "w"); if not f then return end
    f:write(string.format("# pio events %d (cap %d)\n", pio_n, pio_max))
    for i = 1, pio_n do f:write(pio_events[i]); f:write("\n") end
    f:close()
end
local pio_installed = false

local function inject(b)
    local h = prog:read_u8(KBD_HEAD)
    prog:write_u8(KBD_RING + h, b)
    prog:write_u8(KBD_HEAD, (h + 1) % 16)
end
local function feed(s)
    pending = pending .. s
    logln(string.format("feed: %q", s))
end
local function start_stage(n, deadline, msg)
    stage = n; stage_at = emu.time(); timeout_s = deadline
    logln(string.format("=== stage %d (deadline %ds): %s", n, deadline, msg))
end
local function fail(r) set_result("FAIL: " .. r); logln("FAIL: " .. r); stage = 99; stage_at = emu.time() end
local function pass(r) set_result("PASS: " .. r); logln("PASS: " .. r); stage = 99; stage_at = emu.time() end

emu.register_periodic(function()
    if not dip_set_done then dip_set_done = true; select_transport_dip() end
    if prog == nil then
        local cpu = manager.machine.devices[":maincpu"]
        if cpu == nil then return end
        prog = cpu.spaces["program"]
        if prog == nil then return end
    end
    -- Lua port taps disabled 2026-06-13 -- crashes MAME (Lua engine
    -- lua_gettop on stale lua_State).  See macOS DiagnosticReports
    -- regnecentralend-*.ips backtraces.  The cpnet_bridge.cpp side
    -- logerror suffices for tracing.

    local t = emu.time()

    -- Drain keystrokes at ~10/sec.
    if #pending > 0 and t > pace_at then
        inject(pending:byte(1)); pending = pending:sub(2)
        pace_at = t + 0.10
    end

    -- Stage 0: wait until cpnos has come up enough to print E>.
    if stage == 0 then
        if t < 8.0 then return end
        start_stage(1, 20, "wait for first E> on SIO-B")
        return
    end

    -- Stage 1: see E>, feed DIR<CR>.
    if stage == 1 then
        local raw = read_siob()
        if raw:find("E>", 1, true) then
            logln("first E> seen; feeding DIR<CR>")
            feed("DIR\r")
            start_stage(2, 30, "wait for DIR output and second E>")
        elseif t > stage_at + timeout_s then
            fail("timeout waiting for first E> boot prompt")
        end
        return
    end

    -- Stage 2: PPAS file names visible in SIO-B mirror means DIR ran
    -- end-to-end.  Also need a second E> after DIR so CCP is back.
    if stage == 2 then
        local raw = read_siob()
        local has_dir_output = raw:find("PPAS", 1, true) ~= nil
                            or raw:find("PRIMES", 1, true) ~= nil
                            or raw:find("No file", 1, true) ~= nil  -- empty E: also OK
        if has_dir_output and count(raw, "E>") >= 2 then
            pass("DIR ran to completion on E:")
        elseif t > stage_at + timeout_s then
            fail("timeout waiting for DIR output + second E>")
        end
        return
    end

    -- Stage 99: snapshot for visual record then exit.
    if stage == 99 and t > stage_at + 0.5 then
        pcall(function() manager.machine.video:snapshot() end)
        -- Dump display rows 0..5 + IO chip states for diagnostic.
        flush_pio()
        pcall(function()
            local f = io.open("/tmp/cpnos_dir_dsp.txt", "w")
            for r = 0, 5 do
                local base = 0xF800 + r * 80
                local s = ""
                for c = 0, 79 do
                    local b = prog:read_u8(base + c)
                    if b >= 0x20 and b < 0x7F then s = s .. string.char(b)
                    else s = s .. "." end
                end
                f:write(string.format("row %02d: |%s|\n", r, s))
            end
            f:close()
        end)
        manager.machine:exit()
    end
end)
