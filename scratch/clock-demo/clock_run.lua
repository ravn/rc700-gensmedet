-- boot CP/M, run CLOCK, feed Hours+Minutes, snapshot the drawn analog clock.
local TIMEOUT = 50 * 70
local frame, stage, snapped = 0, 0, false
local t_cmd, t_hr, t_min = 0, 0, 0
local function space() return manager.machine.devices[":maincpu"].spaces["program"] end
local function at_prompt()
    local s = space()
    for row = 0, 24 do
        local b = 0xF800 + row * 80
        if s:read_u8(b) == 0x41 and s:read_u8(b+1) == 0x3E then return true end
    end
    return false
end
local function post(str) manager.machine.natkeyboard:post(str) end
emu.register_frame_done(function()
    if snapped then return end
    frame = frame + 1
    if stage == 0 then
        if at_prompt() then
            print("[clock] A> at "..frame..", typing CLOCK"); post("CLOCK\r")
            t_cmd = frame; stage = 1
        end
    elseif stage == 1 and frame > t_cmd + 200 then
        print("[clock] Hours -> 10"); post("10\r"); t_hr = frame; stage = 2
    elseif stage == 2 and frame > t_hr + 150 then
        print("[clock] Minutes -> 10"); post("10\r"); t_min = frame; stage = 3
    elseif stage == 3 and frame > t_min + 400 then
        snapped = true
        manager.machine.video:snapshot()
        print("[clock] snapshot at "..frame); manager.machine:exit()
    end
    if frame > TIMEOUT then print("[clock] TIMEOUT stage="..stage); snapped=true; manager.machine:exit() end
end)
