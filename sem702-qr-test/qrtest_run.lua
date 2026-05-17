-- qrtest_run.lua -- boot CP/M, run QRTEST, snapshot when painted, exit.
--
-- Waits for the CCP "A>" prompt, posts "QRTEST\r" via natkeyboard,
-- then watches 0xF800 for the 0x84 field-attribute byte that QRTEST
-- writes at the start of its paint sequence.  Once seen, settle a
-- few frames so the rest of the screen lands, then snapshot + exit.

local CMD            = "QRTEST"
local TIMEOUT_FRAMES = 50 * 30
local SETTLE_FRAMES  = 12

local frame   = 0
local typed   = false
local settle  = 0
local snapped = false

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
            print(string.format("[qrtest_run] CCP prompt at frame %d, typing %s", frame, CMD))
            manager.machine.natkeyboard:post(CMD .. "\r")
        end
    elseif painted() then
        settle = settle + 1
        if settle >= SETTLE_FRAMES then
            snapped = true
            manager.machine.video:snapshot()
            print(string.format("[qrtest_run] snapshot at frame %d", frame))
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
