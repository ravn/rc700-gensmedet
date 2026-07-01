-- mame_qr_test.lua -- verify autoload draws the QR code on the no-diskette
-- error screen.
--
-- Boot scenario (identical to mame_sw1_test): no floppy, no PROM1 signature ->
-- autoload reaches its "**NO DISKETTE NOR LINEPROG**" halt with the banner and
-- the QR code still on the CRT.  The QR is a 13x9 block of ROA327 sextant codes
-- at rows 15..23, cols 2..14, preceded by an 8275 field attribute 0x84
-- (GPA0=1 -> select ROA327/SEM702) at row 15, col 1.  See rom.c draw_qr().
--
-- Dumps to /tmp/autoload_qr_dump.txt:
--   attr: XX             -- the field-attribute byte at (15,1); must be 84
--   qrNN: <13 hex bytes> -- QR rows 15..23, cols 2..14
--   errNN: <text>        -- rows 0..3 (banner + halt error message)
-- The Makefile qr-test target checks the attribute, byte-matches the QR region
-- against qr_data.h, and confirms an error message is on screen.
--
-- Display base is taken from the Am9517A DMA ch2 address register via passive
-- write-taps (never IO reads) -- see mame_sw1_test.lua for the rationale and the
-- feedback_lua_* memory notes.

local RESULT_PATH = "/tmp/autoload_qr_dump.txt"
local ROW_BYTES   = 80
local DEADLINE_S  = 4.0
local QR_TOP, QR_LEFT, QR_COLS, QR_ROWS = 15, 2, 13, 9

local installed = false
-- Retain tap handles or Lua GC frees them and the next tapped access segfaults.
local _ktaps = {}
local fired = false
local prog
local dma = { base = nil, msb = false, lo = 0 }

emu.register_periodic(function()
    if not installed then
        local cpu = manager.machine.devices[":maincpu"]
        if cpu == nil then return end
        prog = cpu.spaces["program"]
        local io = cpu.spaces["io"]
        if prog == nil or io == nil then return end
        _ktaps[#_ktaps+1] = io:install_write_tap(0xFC, 0xFC, "dma_clbp", function() dma.msb = false end)
        _ktaps[#_ktaps+1] = io:install_write_tap(0xF4, 0xF4, "dma_ch2_addr", function(_, d)
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
        -- field attribute cell (row QR_TOP, col QR_LEFT-1)
        local attr = prog:read_u8(dma.base + QR_TOP * ROW_BYTES + (QR_LEFT - 1))
        f:write(string.format("attr: %02X\n", attr))
        -- QR region, hex
        for r = 0, QR_ROWS - 1 do
            local hex = {}
            for c = 0, QR_COLS - 1 do
                local b = prog:read_u8(dma.base + (QR_TOP + r) * ROW_BYTES + QR_LEFT + c)
                hex[#hex + 1] = string.format("%02X", b)
            end
            f:write(string.format("qr%02d: %s\n", r, table.concat(hex, " ")))
        end
        -- rows 0..3 as text (banner + halt error message)
        for row = 0, 3 do
            local line = {}
            for col = 0, ROW_BYTES - 1 do
                local b = prog:read_u8(dma.base + row * ROW_BYTES + col)
                line[#line + 1] = (b >= 0x20 and b < 0x7F) and string.char(b) or "."
            end
            f:write(string.format("err%02d: %s\n", row, table.concat(line)))
        end
    end
    f:close()

    local screen = manager.machine.screens:at(1)
    if screen ~= nil then
        pcall(function() screen:snapshot("autoload_qr.png") end)
    end
    manager.machine:exit()
end)
