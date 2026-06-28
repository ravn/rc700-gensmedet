-- mame_boot_test.lua — Automated boot test for the RC702 boot PROM.
--
-- PASS: CP/M boots, "A>" appears on the display, and (if EXPECT_BANNER is set)
--       the PROM banner matches.
-- FAIL: error text on the display, timeout, or wrong banner.
--
-- The display buffer base is NOT hardcoded.  It is taken from the Am9517A DMA
-- controller channel-2 address register (I/O port 0xF4), which the firmware
-- (re)programs every frame with the live display base.  This works for any
-- PROM — genuine roa375, autoload-in-c, etc. — which use different bases, and
-- survives CP/M moving the buffer after boot.  Captured via passive write-taps
-- only (never IO reads — see tasks/memory/feedback_lua_no_port_reads.md):
--   - port 0xFC (clear byte-pointer flip-flop) -> next 0xF4 write is low byte
--   - port 0xF4 (ch2 address) low byte then high byte -> 16-bit base
--
-- Set EXPECT_BANNER to require a string in the banner, e.g. "RC700 ROA375 CL".

local SCREEN_COLS = 80
local SCREEN_ROWS = 25
local RESULT_FILE = os.getenv("BOOT_RESULT_FILE") or "/tmp/boot_test_result.txt"
local EXPECT_BANNER = os.getenv("EXPECT_BANNER")

local frame = 0
local done = false
local prog
local installed = false

-- Optional: force SW1 S01 (port 0x14 bit 0 — shared SW1_CONSOLE_BIT) to a known
-- position so the cross-version boot matrix can test both switch states.  Set
-- env SW1_S01=0 (On / clear = SIO-B console+debug) or =1 (Off / set = local
-- console only).  Done via the :DSW ioport field (NOT an I/O read tap — see
-- tasks/memory/feedback_lua_no_port_reads.md).  Unset => leave MAME default.
local SW1_S01 = os.getenv("SW1_S01")
local dsw_done = false
local function set_dsw_s01()
    if dsw_done or SW1_S01 == nil then return end
    local port = manager.machine.ioport.ports[":DSW"]
    if not port then return end
    for _, field in pairs(port.fields) do
        if field.mask == 0x01 then
            field.user_value = (SW1_S01 == "1") and 0x01 or 0x00
            print(string.format("[boot-test] DSW S01 = 0x%02X (%s)",
                field.user_value, (SW1_S01 == "1") and "Off/local" or "On/siob"))
            dsw_done = true
            return
        end
    end
end

-- Live display base, derived from the DMA ch2 address register.
local dma = { base = nil, msb = false, lo = 0 }

-- GC-RETENTION GUARD (do not remove): install_write_tap / install_read_tap
-- return a memory_passthrough_handler userdata.  If that return value is NOT
-- kept alive by a Lua reference, the Lua GC frees it while MAME still holds the
-- tap registered on the address space.  The NEXT bus write to the tapped port
-- then invokes a dangling callback -> native EXC_BAD_ACCESS (code=1) crash deep
-- in lua_topointer, NOT a catchable Lua error.  Symptom seen here: the original
-- roa375 PROM writes ports 0xFC/0xF4 a few frames after the taps install, after
-- a GC cycle, and MAME segfaults; the clang PROM happened to write before the
-- first GC so it masked the bug.  Fix: stash every tap handle in this
-- module-scope table so it lives as long as the script.  See
-- tasks/memory/feedback_lua_retain_tap_handles.md.
local taps = {}

local function install_taps(io)
    taps[#taps + 1] = io:install_write_tap(0xFC, 0xFC, "dma_clbp",
        function() dma.msb = false end)
    taps[#taps + 1] = io:install_write_tap(0xF4, 0xF4, "dma_ch2_addr", function(_, d)
        if not dma.msb then dma.lo = d; dma.msb = true
        else dma.base = ((d << 8) | dma.lo) & 0xFFFF; dma.msb = false end
    end)
end

local function screen_text_at(base)
    local lines = {}
    for row = 0, SCREEN_ROWS - 1 do
        local line = ""
        for col = 0, SCREEN_COLS - 1 do
            local ch = prog:read_u8(base + row * SCREEN_COLS + col)
            line = line .. ((ch >= 0x20 and ch < 0x7F) and string.char(ch) or " ")
        end
        lines[#lines + 1] = line:gsub("%s+$", "")
    end
    return table.concat(lines, "\n")
end

local function screen_text()
    local parts = {}
    if dma.base then
        parts[#parts+1] = string.format("--- DMA-derived 0x%04X ---", dma.base)
        parts[#parts+1] = screen_text_at(dma.base)
    end
    if dma.base ~= 0xF800 then
        parts[#parts+1] = "--- BIOS 0xF800 ---"
        parts[#parts+1] = screen_text_at(0xF800)
    end
    return table.concat(parts, "\n")
end

-- Search the DMA-derived base AND the standard BIOS display base (0xF800).
-- The BIOS reprograms DMA after autoload hands off, but our tap may not
-- always capture the new base cleanly (8237 flip-flop / write order may
-- diverge from autoload's low-then-high pattern), so we also check 0xF800
-- which the RC702 BIOS canonically uses.  See tasks/memory/
-- feedback_display_addr_from_dma.md for the DMA-derivation rationale.
local function screen_find_at(base, str)
    local bytes = {string.byte(str, 1, #str)}
    local n = SCREEN_COLS * SCREEN_ROWS
    for addr = base, base + n - #str do
        local match = true
        for i = 1, #bytes do
            if prog:read_u8(addr + i - 1) ~= bytes[i] then match = false; break end
        end
        if match then return true end
    end
    return false
end

local function screen_find(str)
    if dma.base and screen_find_at(dma.base, str) then return true end
    -- Always also check 0xF800 (canonical BIOS display base) in case BIOS
    -- took over after autoload.
    if dma.base ~= 0xF800 and screen_find_at(0xF800, str) then return true end
    return false
end

local function finish(result)
    local f = io.open(RESULT_FILE, "w")
    f:write(result .. "\n")
    f:write(string.format("frame=%d (%.1fs emulated)\n", frame, frame / 50.0))
    f:write(string.format("display base (DMA ch2) = %s\n",
                          dma.base and string.format("0x%04X", dma.base) or "unset"))
    f:write("\n--- display ---\n" .. screen_text() .. "\n")
    f:close()
    -- Optional screenshot: pcall + filename arg because newer MAME's
    -- screen:snapshot() signature requires a name string (older builds
    -- accepted no-args).  Wrapping with pcall keeps the test result valid
    -- even if the call's signature changes again.
    local screen = manager.machine.screens:at(1)
    if screen ~= nil then
        pcall(function() screen:snapshot("autoload_boot_test.png") end)
    end
    done = true
    manager.machine:exit()
end

emu.register_frame_done(function()
    if done then return end
    set_dsw_s01()
    if not installed then
        local cpu = manager.machine.devices[":maincpu"]
        if cpu == nil then return end
        prog = cpu.spaces["program"]
        local io = cpu.spaces["io"]
        if prog == nil or io == nil then return end
        install_taps(io)
        installed = true
    end

    frame = frame + 1
    if frame % 25 ~= 0 then return end  -- check every 0.5s

    if screen_find("A>") then
        if EXPECT_BANNER and not screen_find(EXPECT_BANNER) then
            finish("FAIL: booted but wrong banner (expected '" .. EXPECT_BANNER .. "')")
        else
            finish("PASS")
        end
        return
    end

    -- Known PROM error/halt messages => fail fast (the normal "RC700" banner
    -- is NOT an error, so we match specific strings, not "any text").
    if frame > 50 * 6 and dma.base then
        local txt = screen_text()
        for _, m in ipairs({"NO SYSTEM", "NO DISK", "NO DISKETTE", "NO LINEPROG", "ERROR"}) do
            if txt:find(m, 1, true) then
                finish("FAIL: PROM error/halt: " .. m)
                return
            end
        end
    end

    if frame > 50 * (tonumber(os.getenv("BOOT_TIMEOUT_S") or "60")) then
        finish("FAIL: timeout — no A> (see display)")
    end
end)
