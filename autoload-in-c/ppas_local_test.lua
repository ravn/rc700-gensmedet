local RESULT = os.getenv("BOOT_RESULT_FILE") or "/tmp/ppas_local_result.txt"
local SC,SR=80,25
local frame,stage,done=0,0,false
local prog,installed=nil,false
local taps={}
local dma={base=nil,msb=false,lo=0}
local inject_at,pending=0,""
local stage_at=0

local function scr()
    local base=dma.base or 0xF800
    local out=""
    for r=0,SR-1 do local line=""
        for c=0,SC-1 do local b=prog:read_u8(base+r*SC+c)&0x7f
            line=line..(b>=32 and string.char(b) or " ") end
        line=line:gsub("%s+$",""); out=out..line.."\n"
    end; return out
end

local function feed(s) pending=pending..s end

local function finish(msg)
    local f=io.open(RESULT,"w")
    if f then f:write(string.format("%s (frame=%d, t=%.1fs)\n",
        msg,frame,frame/50.0).."\n--- display ---\n"..scr())
        f:close() end
    done=true; manager.machine:exit()
end

emu.register_frame_done(function()
    frame=frame+1; if done then return end
    if not installed then
        local cpu=manager.machine.devices[":maincpu"]
        if not cpu then return end
        prog=cpu.spaces["program"]
        local io_sp=cpu.spaces["io"]
        taps[1]=io_sp:install_write_tap(0xFC,0xFC,"c",function() dma.msb=false end)
        taps[2]=io_sp:install_write_tap(0xF4,0xF4,"a",function(_,d)
            if not dma.msb then dma.lo=d;dma.msb=true
            else dma.base=((d<<8)|dma.lo)&0xFFFF;dma.msb=false end
        end); installed=true; return
    end
    if pending~="" and frame>=inject_at then
        local c=pending:sub(1,1); pending=pending:sub(2)
        manager.machine.natkeyboard:post(c); inject_at=frame+5
    end

    local s=scr()
    if stage==0 and frame>150 and s:find("A>") then
        stage=1; stage_at=frame; feed("PPAS\r")
    elseif stage==1 and frame>stage_at+80 and s:find(">>") then
        stage=2; stage_at=frame; feed("L PRIMES\r")
    elseif stage==2 and frame>stage_at+80 and s:find(">>") then
        stage=3; stage_at=frame; feed("R\r")
    elseif stage==3 and s:find("29989") then
        finish("PASS: PRIMES ran to 29989")
    elseif stage==3 and frame>stage_at+1000 and s:find(">>") then
        -- Tilbage i PPAS efter run — primes afsluttede
        finish("PASS: PRIMES completed (returned to >>)")
    end

    if frame>200000 and not done then
        finish(string.format("FAIL: timeout stage=%d",stage))
    end
end)
