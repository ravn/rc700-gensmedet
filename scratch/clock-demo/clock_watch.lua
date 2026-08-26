-- boot CP/M, run CLOCK, feed Hours+Minutes, then just let it run (no exit).
local frame, stage = 0, 0
local t_cmd, t_hr = 0, 0
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
    frame = frame + 1
    if stage == 0 then
        if at_prompt() then post("CLOCK\r"); t_cmd = frame; stage = 1
            print("[clock_watch] typed CLOCK") end
    elseif stage == 1 and frame > t_cmd + 200 then post("10\r"); t_hr = frame; stage = 2
    elseif stage == 2 and frame > t_hr + 150 then post("10\r"); stage = 3
        print("[clock_watch] time set; running free at full speed")
    end
end)
