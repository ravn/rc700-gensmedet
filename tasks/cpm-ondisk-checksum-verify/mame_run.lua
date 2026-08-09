-- MAME autoboot: boot the rc700-8dd disk, type "PROG"<CR> to run the checksum
-- tool on A:, wait for it to finish, dump the 80x25 text screen to
-- /tmp/screen.txt, then exit. (ravn/z88dk#36 on-disk checksum verification.)
--
-- We drive PROG via simulated keystrokes because the SW1711 AUTOEXEC on-disk
-- auto-start byte-patch does NOT apply to this system's CCP build (the running
-- CCP loads at D5F8, not CPMB=CC00, and byte +7 is executable init code
-- `LD A,01`, not the command-length slot the AUTOEXEC model assumes).
--
-- The screen dump reads the RC700 BIOS text buffer at program-space 0xF800
-- (80 cols x 25 rows). The wait is deliberately long (~200 s of simulated
-- time): reading a ~48 KB multi-extent file record-by-record through the
-- emulated uPD765 floppy with accurate rotational timing takes ~3 minutes of
-- simulated time. Run with -seconds_to_run 220 (or more) as a safety bound.

local chars = {0x50, 0x52, 0x4F, 0x47, 0x0D}  -- P R O G CR
local frame = 0
local nk = manager.machine.natkeyboard

emu.register_frame_done(function()
    frame = frame + 1
    -- start typing at ~16 s (frame 800 @ 50 fps), one char per 0.3 s
    for i = 1, #chars do
        if frame == 800 + (i - 1) * 15 then
            pcall(function() nk:post_coded(string.char(chars[i])) end)
        end
    end
    if frame >= 10000 then  -- ~200 s: boot + type + read + checksum
        local space = manager.machine.devices[":maincpu"].spaces["program"]
        local f = io.open("/tmp/screen.txt", "w")
        for row = 0, 24 do
            local line = ""
            for col = 0, 79 do
                local ch = space:read_u8(0xF800 + row * 80 + col)
                line = line .. ((ch >= 0x20 and ch < 0x7F) and string.char(ch) or " ")
            end
            f:write(line .. "\n")
        end
        f:close()
        manager.machine:exit()
    end
end)
