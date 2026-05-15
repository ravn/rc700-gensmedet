-- cpnos-in-asm phase 1 value oracle: read display memory after a
-- short boot window, write the banner row to a result file, and
-- exit MAME so the Makefile can grep the file for the expected
-- string.
--
-- Display memory: 0xF800 (row 0 col 0) .. 0xFFCF (row 24 col 79).
-- Phase 1 stamps the banner at row 0.

local RESULT_PATH = "/tmp/cpnos_asm_banner.txt"
-- CP/M-canonical display address.  cpnos-in-asm relocates the CRT
-- DMA source from autoload's 0x7A00 to 0xF800 before stamping the
-- banner, freeing 0x7A00..0x81CF for TPA.  cpnos-in-c also uses
-- 0xF800.  See project_rc702_ivt_page_constraint memory.
local DISPLAY_ADDR = 0xF800
local ROW_BYTES    = 80
local DEADLINE_S   = 3.0

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
            local b = prog:read_u8(DISPLAY_ADDR + row * ROW_BYTES + col)
            if b >= 0x20 and b < 0x7F then
                line[#line + 1] = string.char(b)
            else
                line[#line + 1] = "."
            end
        end
        f:write(string.format("row%02d: %s\n", row, table.concat(line)))
    end
    f:close()

    -- Capture a screenshot of the CRT so the operator (and PRs) have
    -- a visual record of phase 1 alongside the byte dump.
    local screen = manager.machine.screens:at(1)
    if screen ~= nil then screen:snapshot() end

    manager.machine:exit()
end)
