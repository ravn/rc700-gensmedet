-- qrtest_run.lua -- boot CP/M, type the command in /tmp/qrtest_cmd.txt,
-- wait until the .COM paints 0x84 at 0xF800, snapshot, exit.
--
-- The Makefile writes the command (e.g. "QRTEST1") to /tmp/qrtest_cmd.txt
-- before each `mame ...` invocation so this single autoboot script can
-- drive any sextant-painting .COM on the floppy.

local CMD_PATH       = "/tmp/qrtest_cmd.txt"
local TIMEOUT_FRAMES = 50 * 30
local SETTLE_FRAMES  = 12

local frame   = 0
local typed   = false
local settle  = 0
local snapped = false
local cmd     = "QRTEST1"   -- safe default

do
    local fh = io.open(CMD_PATH, "r")
    if fh then
        local line = fh:read("*l")
        if line and #line > 0 then cmd = line end
        fh:close()
    end
end

local function space()
    return manager.machine.devices[":maincpu"].spaces["program"]
end

local function at_prompt()
    local s = space()
    for row = 0, 24 do
        local base = 0xF800 + row * 80
        if s:read_u8(base) == 0x41 and s:read_u8(base + 1) == 0x3E then
            return true
        end
    end
    return false
end

local function painted()
    return space():read_u8(0xF800) == 0x84
end

emu.register_frame_done(function()
    if snapped then return end
    frame = frame + 1

    if not typed then
        if at_prompt() then
            typed = true
            print(string.format("[qrtest_run] CCP prompt at frame %d, typing %s", frame, cmd))
            manager.machine.natkeyboard:post(cmd .. "\r")
        end
    elseif painted() then
        settle = settle + 1
        if settle >= SETTLE_FRAMES then
            snapped = true
            manager.machine.video:snapshot()
            print(string.format("[qrtest_run] snapshot at frame %d (cmd=%s)", frame, cmd))
            manager.machine:popmessage("snapshot taken: " .. cmd)
            manager.machine:exit()
        end
    end

    if frame > TIMEOUT_FRAMES then
        print(string.format("[qrtest_run] TIMEOUT after %d frames; typed=%s painted=%s",
                            frame, tostring(typed), tostring(painted())))
        snapped = true
        manager.machine:exit()
    end
end)
