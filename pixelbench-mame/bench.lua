-- Autoboot: at A> prompt type "<CMD>\r", then poll scratch RAM for the
-- debugscript-written result: flag 0xA5 at 0x7008, u64 T-state delta at 0x7000.
local CMD = os.getenv("BENCH_CMD") or "PIXELBEN"
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
    if stage==0 and frame>150 and screen_find("A>") then
        stage=1; pending=CMD.."\r"
    elseif stage==1 then
        -- wait for the debugscript to poke the completion flag
        if prog:read_u8(0x7008)==0xA5 then
            local d=0
            for i=7,0,-1 do d=d*256+prog:read_u8(0x7000+i) end
            print(string.format("BENCH_RESULT %s %d", CMD, d))
            done=true; manager.machine:exit()
        end
    end
    if frame>200000 then print("BENCH_RESULT "..CMD.." TIMEOUT"); done=true; manager.machine:exit() end
end)
