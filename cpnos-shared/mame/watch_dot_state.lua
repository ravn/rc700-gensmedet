-- watch_dot_state.lua — tap every write to DOT_CURSOR / DOT_COL /
-- DOT_ROW (0x4000..0x4003).  Goal: pin the exact PC that bumps
-- dot_row 15-extra times between CCP's "E>" prompt and PPAS's first
-- character (cursor visibly jumps to row 23 when it should be row 4).
--
-- Output: /tmp/cpnos_dot_watch.log (one line per write).

local OUT = "/tmp/cpnos_dot_watch.log"
local LO, HI = 0x4000, 0x4003
local LIMIT = 5000

local f = io.open(OUT, "w")
f:write(string.format("# dot-state tap %04x..%04x\n", LO, HI))

local prog, state, installed, count = nil, nil, false, 0

emu.register_periodic(function()
    if installed then return end
    local cpu = manager.machine.devices[":maincpu"]
    if cpu == nil then return end
    prog = cpu.spaces["program"]
    state = cpu.state
    if prog == nil or state == nil then return end

    prog:install_write_tap(LO, HI, "dot_watch", function(offs, data, mask)
        count = count + 1
        if count > LIMIT then return end
        local pc = state["PC"].value
        local name = ({ [0]="CURLO", [1]="CURHI", [2]="COL", [3]="ROW" })[offs - LO] or "?"
        f:write(string.format("[%9.4fs] PC=%04x %s=%02x\n",
            emu.time(), pc, name, data))
        f:flush()
    end)
    installed = true
end)
