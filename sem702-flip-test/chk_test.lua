-- Boot rc702sem702, run CHK, snapshot at phase-marker 1 (A: checkerboard) and
-- 2 (B: ROA296 from file).
local frame,stage,done=0,0,false
local prog,installed=nil,false
local inject_at,pending=0,""
local dma={base=nil,msb=false,lo=0}
local taps={}

local function screen_find(str)
    local base=dma.base or 0xF800
    local b={string.byte(str,1,#str)}
    for a=base,base+80*25-#str do
        local ok=true
        for i,v in ipairs(b) do if prog:read_u8(a+i-1)~=v then ok=false break end end
        if ok then return true end
    end
    return false
end

local function snap(name)
    local scr=manager.machine.screens:at(1)
    if scr then pcall(function() scr:snapshot(name) end) end
end

emu.register_frame_done(function()
    frame=frame+1
    if done then return end
    if not installed then
        local cpu=manager.machine.devices[":maincpu"]
        if not cpu then return end
        prog=cpu.spaces["program"]
        local io=cpu.spaces["io"]
        taps[1]=io:install_write_tap(0xFC,0xFC,"c",function() dma.msb=false end)
        taps[2]=io:install_write_tap(0xF4,0xF4,"a",function(_,d)
            if not dma.msb then dma.lo=d;dma.msb=true
            else dma.base=((d<<8)|dma.lo)&0xFFFF;dma.msb=false end end)
        installed=true; return
    end
    if pending~="" and frame>=inject_at then
        local c=pending:sub(1,1); pending=pending:sub(2)
        manager.machine.natkeyboard:post(c); inject_at=frame+4
    end
    local marker = prog:read_u8(0xBF00)
    local progress = prog:read_u8(0xBF01)
    if stage==0 and frame>150 and screen_find("A>") then
        stage=1; pending="CHK\r"
    elseif stage==1 and marker==1 then
        stage=2; snap("sem702_A_checkerboard.png")
        print(string.format("PHASE A snapped, progress=%02x frame=%d", progress, frame))
    elseif stage==2 and marker==2 then
        stage=3; snap("sem702_B_roa296.png")
        print(string.format("PHASE B snapped, progress=%02x frame=%d", progress, frame))
        done=true; manager.machine:exit()
    end
    if frame>12000 then
        print(string.format("TIMEOUT stage=%d marker=%02x progress=%02x", stage, marker, prog:read_u8(0xBF01)))
        done=true; manager.machine:exit()
    end
end)
