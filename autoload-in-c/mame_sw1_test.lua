-- mame_sw1_test.lua — verify that autoload stamps a "SW1: ..." status
-- line on the display alongside its boot banner.
--
-- Boot scenario: no floppy, no PROM1 signature -> autoload reaches its
-- "**NO DISKETTE NOR LINEPROG**" halt with the banner + SW1 line still
-- on the CRT.  Dumps rows 0..3 of the display to /tmp/autoload_sw1_dump.txt,
-- then exits.  The Makefile target greps the dump for "SW1: ".
--
-- The display base is NOT hardcoded: it is taken from the Am9517A DMA
-- channel-2 address register (the i8275 CRTC's source), captured via passive
-- write-taps (never IO reads — see tasks/memory/feedback_lua_no_port_reads.md
-- and tasks/memory/feedback_display_addr_from_dma.md):
--   - port 0xFC (clear byte-pointer flip-flop) -> next 0xF4 write is low byte
--   - port 0xF4 (ch2 address) low byte then high byte -> 16-bit base

local RESULT_PATH = "/tmp/autoload_sw1_dump.txt"
local ROW_BYTES   = 80
local DEADLINE_S  = 4.0

local installed = false
local fired = false
local prog

-- Live display base, derived from the DMA ch2 address register.
local dma = { base = nil, msb = false, lo = 0 }

emu.register_periodic(function()
    if not installed then
        local cpu = manager.machine.devices[":maincpu"]
        if cpu == nil then return end
        prog = cpu.spaces["program"]
        local io = cpu.spaces["io"]
        if prog == nil or io == nil then return end
        io:install_write_tap(0xFC, 0xFC, "dma_clbp", function() dma.msb = false end)
        io:install_write_tap(0xF4, 0xF4, "dma_ch2_addr", function(_, d)
            if not dma.msb then dma.lo = d; dma.msb = true
            else dma.base = ((d << 8) | dma.lo) & 0xFFFF; dma.msb = false end
        end)
        installed = true
    end
    if fired then return end
    if emu.time() < DEADLINE_S then return end
    fired = true

    local f = io.open(RESULT_PATH, "w")
    if not dma.base then
        f:write("(display base not yet programmed by DMA ch2)\n")
    else
        f:write(string.format("# display base (DMA ch2) = 0x%04X\n", dma.base))
        for row = 0, 3 do
            local line = {}
            for col = 0, ROW_BYTES - 1 do
                local b = prog:read_u8(dma.base + row * ROW_BYTES + col)
                if b >= 0x20 and b < 0x7F then
                    line[#line + 1] = string.char(b)
                else
                    line[#line + 1] = "."
                end
            end
            f:write(string.format("row%02d: %s\n", row, table.concat(line)))
        end
    end
    f:close()

    -- pcall + filename: newer MAME's screen:snapshot() requires a name.
    local screen = manager.machine.screens:at(1)
    if screen ~= nil then
        pcall(function() screen:snapshot("autoload_sw1.png") end)
    end

    manager.machine:exit()
end)
