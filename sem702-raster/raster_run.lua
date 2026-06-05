-- raster_run.lua -- boot CP/M, run RASTER, snapshot mid-animation, exit.
--
-- Waits for the CCP "A>" prompt, posts "RASTER\r" via natkeyboard, watches
-- 0xF800 for the 0x84 field-attribute byte that RASTER writes during init.
-- Once seen, waits SETTLE_FRAMES so the animation is well underway, then
-- snapshots and exits.

local CMD            = "RASTER"
local TIMEOUT_FRAMES = 50 * 30
local SETTLE_FRAMES  = 100        -- ~2 s into the 10 s animation
local SNAPS_TO_TAKE  = 3          -- spread across animation to show motion
local SNAP_INTERVAL  = 100        -- frames between snapshots (~2 s)

local frame      = 0
local typed      = false
local settle     = 0
local snaps_done = 0
local next_snap  = 0

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
    frame = frame + 1

    if not typed then
        if at_prompt() then
            typed = true
            print(string.format("[raster_run] CCP prompt at frame %d, typing %s",
                                frame, CMD))
            manager.machine.natkeyboard:post(CMD .. "\r")
        end
    elseif painted() then
        settle = settle + 1
        if settle == SETTLE_FRAMES then
            next_snap = frame
        end
        -- Diagnostics: print frame_tick + frame_counter + a peek at VRAM(10,30..33)
        if settle % 50 == 1 then
            local s = space()
            local tick = s:read_u8(0x0213)
            local cnt  = s:read_u8(0x0214)
            local v0 = s:read_u8(0xF800 + 10*80 + 30)
            local v1 = s:read_u8(0xF800 + 10*80 + 31)
            local v2 = s:read_u8(0xF800 + 10*80 + 32)
            local v3 = s:read_u8(0xF800 + 10*80 + 33)
            local i_reg = s:read_u8(0x0212)   -- i_reg_save
            local saved_lo = s:read_u8(0x020E)
            local saved_hi = s:read_u8(0x020F)
            local ivt_slot_lo = s:read_u8(i_reg * 256 + 0x04)
            local ivt_slot_hi = s:read_u8(i_reg * 256 + 0x05)
            print(string.format("[raster_run] frame=%d settle=%d tick=%d cnt=%d I=%02X saved=%04X ivt[%02X04]=%04X vram=[%d %d %d %d]",
                                frame, settle, tick, cnt, i_reg,
                                saved_hi * 256 + saved_lo,
                                i_reg, ivt_slot_hi * 256 + ivt_slot_lo,
                                v0, v1, v2, v3))
        end
        if settle >= SETTLE_FRAMES and frame >= next_snap and snaps_done < SNAPS_TO_TAKE then
            manager.machine.video:snapshot()
            snaps_done = snaps_done + 1
            next_snap = frame + SNAP_INTERVAL
            print(string.format("[raster_run] snapshot %d/%d at frame %d",
                                snaps_done, SNAPS_TO_TAKE, frame))
            -- MAME overwrites snap/raster.png each call; rename to keep all 3.
            os.execute(string.format("cp snap/raster.png snap/raster_%d.png", snaps_done))
            if snaps_done >= SNAPS_TO_TAKE then
                manager.machine:exit()
            end
        end
    end

    if frame > TIMEOUT_FRAMES then
        print(string.format("[raster_run] TIMEOUT after %d frames; typed=%s painted=%s",
                            frame, tostring(typed), tostring(painted())))
        manager.machine:exit()
    end
end)
