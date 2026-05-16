-- dump_ndos_state.lua -- snapshot key CP/NOS memory structures after
-- the slave settles in CCP / NDOS error state.
--
-- Dumps:
--   ZP[0..7]               -- JMP WBOOT, IOBYTE, drive/user, JMP BDOS
--   BIOS JT  @ 0xED00      -- 51 B (resident, post-NDOS-patch)
--   BIOS JT  @ 0xDC80      -- 51 B (NDOSRL+0x300 copy, NDOS-patched here too)
--   cfgtbl   @ runtime     -- netst, slaveid, drive table -- address comes
--                            from $COMPILER/cpnos_polypascal_addrs.lua if
--                            cfgtbl is defined there; else looks at 0xEF7E
--                            (asm slave) and 0xF52E (clang slave) -- pass
--                            via NDOS_DUMP_CFGTBL env override.
--   NDOSRL header @ 0xD980 -- first 256 bytes of NDOS data area
--
-- Output: /tmp/cpnos_ndos_state.txt (one snapshot per timer fire).
-- Fires at t = 15 / 30 / 60 s by default (NDOS Err 04 typically
-- visible by t=10).
--
-- Run alongside polypascal_test.lua via a second -autoboot_script,
-- OR standalone to capture a steady-state slave snapshot.

local OUT = "/tmp/cpnos_ndos_state.txt"
local SAMPLE_TIMES = { 15, 30, 60 }
local cfgtbl_addr  = tonumber(os.getenv("NDOS_CFGTBL") or "") or 0xEF7E

local f = io.open(OUT, "w")
f:write(string.format("# ndos-state dump; cfgtbl=0x%04x\n", cfgtbl_addr))

local prog, idx = nil, 1

local function hex(base, len)
    local parts = {}
    for i = 0, len - 1 do
        parts[#parts + 1] = string.format("%02x", prog:read_u8(base + i))
        if (i + 1) % 16 == 0 then parts[#parts + 1] = "\n  " end
    end
    return table.concat(parts, " ")
end

local function dump(t)
    f:write(string.format("\n=== t=%.1fs ===\n", t))
    f:write(string.format("ZP[0..7]:\n  %s\n", hex(0x0000, 8)))
    f:write(string.format("BIOS_JT @ 0xED00 (resident, 51 B):\n  %s\n",
        hex(0xED00, 51)))
    f:write(string.format("BIOS_JT @ 0xDC80 (NDOSRL+0x300 copy, 51 B):\n  %s\n",
        hex(0xDC80, 51)))
    f:write(string.format("cfgtbl @ 0x%04x (first 64 B):\n  %s\n",
        cfgtbl_addr, hex(cfgtbl_addr, 64)))
    f:write(string.format("NDOSRL @ 0xD980 (first 64 B):\n  %s\n",
        hex(0xD980, 64)))
    f:write(string.format("DSP row 0 (0xF800, 80 B):\n  %s\n",
        hex(0xF800, 80)))
    f:write(string.format("DSP row 1 (0xF850, 80 B):\n  %s\n",
        hex(0xF850, 80)))
    f:write(string.format("DSP row 2 (0xF8A0, 80 B):\n  %s\n",
        hex(0xF8A0, 80)))
    f:write(string.format("DSP row 3 (0xF8F0, 80 B):\n  %s\n",
        hex(0xF8F0, 80)))
    f:flush()
end

emu.register_periodic(function()
    if prog == nil then
        local cpu = manager.machine.devices[":maincpu"]
        if cpu then prog = cpu.spaces["program"] end
        if prog == nil then return end
    end
    if idx > #SAMPLE_TIMES then return end
    if emu.time() >= SAMPLE_TIMES[idx] then
        dump(emu.time())
        idx = idx + 1
    end
end)
