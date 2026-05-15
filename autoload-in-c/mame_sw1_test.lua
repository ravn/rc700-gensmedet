-- mame_sw1_test.lua — verify that autoload stamps a "SW1: ..." status
-- line on display row 1 alongside its boot banner.
--
-- Boot scenario: no floppy, no PROM1 signature -> autoload reaches its
-- "**NO DISKETTE NOR LINEPROG**" halt with the banner + SW1 line still
-- on the CRT.  Dumps rows 0..2 of the display at PROM_DSP = 0x7A00
-- (autoload's framebuffer base) to /tmp/autoload_sw1_dump.txt, then
-- exits.  The Makefile target greps the dump for "SW1: ".

local RESULT_PATH = "/tmp/autoload_sw1_dump.txt"
local PROM_DSP    = 0x7A00
local ROW_BYTES   = 80
local DEADLINE_S  = 4.0

local installed = false
local fired = false
local prog

emu.register_periodic(function()
    if not installed then
        local cpu = manager.machine.devices[":maincpu"]
        if cpu == nil then return end
        prog = cpu.spaces["program"]
        if prog == nil then return end
        installed = true
    end
    if fired then return end
    if emu.time() < DEADLINE_S then return end
    fired = true

    local f = io.open(RESULT_PATH, "w")
    for row = 0, 2 do
        local line = {}
        for col = 0, ROW_BYTES - 1 do
            local b = prog:read_u8(PROM_DSP + row * ROW_BYTES + col)
            if b >= 0x20 and b < 0x7F then
                line[#line + 1] = string.char(b)
            else
                line[#line + 1] = "."
            end
        end
        f:write(string.format("row%02d: %s\n", row, table.concat(line)))
    end
    f:close()

    local screen = manager.machine.screens:at(1)
    if screen ~= nil then screen:snapshot() end

    manager.machine:exit()
end)
