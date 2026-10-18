-- MAME autoboot script for BIOS-in-C boot/disk test.
-- Waits for a marker string in screen buffer, dumps screen, exits.
-- Marker: "A>" (CP/M prompt) or "DISK=" (disk test) or timeout.

local frame = 0
local max_frames = tonumber(os.getenv("MAX_FRAMES")) or (50 * 15)
local done = false

-- Search for a string in screen memory
local function screen_find(space, str)
    local bytes = {string.byte(str, 1, #str)}
    for addr = 0xF800, 0xF800 + 2000 - #str do
        local match = true
        for i = 1, #bytes do
            if space:read_u8(addr + i - 1) ~= bytes[i] then
                match = false
                break
            end
        end
        if match then return true end
    end
    return false
end

emu.register_frame_done(function()
    if done then return end
    frame = frame + 1

    if frame % 50 == 0 or frame >= max_frames then
        local cpu = manager.machine.devices[":maincpu"]
        local space = cpu.spaces["program"]
        local pc = cpu.state["PC"].value
        local bytes_str = ""
        for i = 0, 7 do
            bytes_str = bytes_str .. string.format("%02X ", space:read_u8((pc + i) & 0xFFFF))
        end
        print(string.format("[mame_disk_test] frame=%d PC=0x%04X SP=0x%04X: %s", frame, pc, cpu.state["SP"].value, bytes_str))

        if screen_find(space, "A>") or screen_find(space, "DISK=")
           or screen_find(space, "error") or frame >= max_frames then
            local screen_file = os.getenv("SCREEN_FILE") or "screen.txt"
            local f = io.open(screen_file, "w")
            for row = 0, 24 do
                local line = ""
                for col = 0, 79 do
                    local ch = space:read_u8(0xF800 + row * 80 + col)
                    if ch >= 0x20 and ch < 0x7F then
                        line = line .. string.char(ch)
                    else
                        line = line .. string.format("\\x%02X", ch)
                    end
                end
                f:write(line .. "\n")
            end
            f:close()
            done = true
            -- Use manager.machine:exit(); os.exit() does not terminate
            -- the host MAME process, leaving it running.  See
            -- feedback_bench_must_self_terminate memory rule.
            manager.machine:exit()
        end
    end
end)
