-- BIOS-JT entry/exit register-state trace (issue #60 / task #36).
--
-- Captures full Z80 register state on every call into the BIOS jump
-- table and SNIOS jump table, AND on the matching return.  Output is
-- a flat text log diffable between compilers (clang reference vs
-- SDCC test).
--
-- Mechanism: install a read tap on the JT memory ranges; a Z80
-- opcode-fetch reads the JP entry's first byte (C3) at the entry
-- address.  Filter to addresses where (offset - base) % 3 == 0 and
-- data == 0xC3, peek SP for retaddr, install a one-shot exit tap
-- at retaddr.  When that fires, log exit-state + remove.
--
-- Two JT ranges:
--   0xED00..0xED4A  resident JT (BIOS_BOOT..SNIOS_NTWKDN)
--                    BIOS-JT 17 entries 0xED00..0xED32 (51 B)
--                    SNIOS-JT 8 entries 0xED33..0xED4A (24 B)
--   0xCF00..0xCF32  NDOSRL+0x300 = NDOS-patched BIOS-JT copy
--                    NDOS COLDST walks 0xED00 and patches a copy
--                    at 0xCF00; CCP/BDOS call through 0xCF00.
--                    SNIOS isn't copied -- NDOS calls 0xED33 direct.
--
-- Output: /tmp/cpnos_bios_jt_trace.log (overwritten each run)
-- The Makefile target renames it to /tmp/cpnos_bios_jt_trace_<compiler>.log
-- after the run so clang+SDCC traces can be diffed.

local OUT       = "/tmp/cpnos_bios_jt_trace.log"
local TIMEOUT_S = 25.0
local MAX_LINES = 5000

-- name tables -- each table is (offset_from_base) -> name
local bios_names = {
    [0]="BOOT", [3]="WBOOT", [6]="CONST", [9]="CONIN", [12]="CONOUT",
    [15]="LIST", [18]="PUNCH", [21]="READER", [24]="HOME", [27]="SELDSK",
    [30]="SETTRK", [33]="SETSEC", [36]="SETDMA", [39]="READ", [42]="WRITE",
    [45]="LISTST", [48]="SECTRAN",
}
local snios_names = {
    [0]="NTWKIN", [3]="NTWKST", [6]="CNFTBL", [9]="SNDMSG",
    [12]="RCVMSG", [15]="NTWKER", [18]="NTWKBT", [21]="NTWKDN",
}

local cpu, prog, state
local out_f = io.open(OUT, "w")
local line_count = 0
local pending_exits = {}  -- retaddr -> tap object

local function regs_str()
    return string.format(
        "AF=%04X BC=%04X DE=%04X HL=%04X IX=%04X IY=%04X SP=%04X",
        state["AF"].value, state["BC"].value, state["DE"].value,
        state["HL"].value, state["IX"].value, state["IY"].value,
        state["SP"].value)
end

local function log_line(s)
    if line_count >= MAX_LINES then return end
    line_count = line_count + 1
    out_f:write(s)
    out_f:write("\n")
    out_f:flush()
end

local function on_jt_read(jt_label, names_tbl, base)
    return function(offset, data, mask)
        local rel = offset - base
        if rel % 3 ~= 0 then return end
        if data ~= 0xC3 then return end          -- not a JP opcode
        local name = names_tbl[rel]
        if name == nil then return end
        -- Distinguish opcode fetch (PC == offset) from data reads.
        -- NDOS COLDST walks 0xED00..0xED32 to build a patched copy
        -- at 0xCF00; those reads happen with PC pointing at NDOS's
        -- LDIR/LD instruction, not at the JT entry.
        if state["PC"].value ~= offset then return end
        local sp = state["SP"].value
        local ret_lo = prog:read_u8(sp)
        local ret_hi = prog:read_u8(sp + 1)
        local retaddr = ret_lo + ret_hi * 256
        log_line(string.format("[%9.4fs] %-7s %s ENTRY %s ret=%04X",
            emu.time(), jt_label, name, regs_str(), retaddr))

        -- Install one-shot exit tap at retaddr.  If a tap is already
        -- pending at this retaddr (re-entry / shared tail), don't
        -- stack -- the existing tap will log on first ret to that
        -- address; subsequent calls share it.
        if pending_exits[retaddr] == nil then
            local exit_tap
            exit_tap = prog:install_read_tap(retaddr, retaddr,
                string.format("biosjt_exit_%04X", retaddr),
                function(eoff, edata, emask)
                    if state["PC"].value ~= retaddr then return end
                    log_line(string.format("[%9.4fs] %-7s %s EXIT  %s",
                        emu.time(), jt_label, name, regs_str()))
                    -- Remove on first hit.  exit_tap might be nil if
                    -- this fires during install (shouldn't but defend).
                    if exit_tap then
                        pcall(function() exit_tap:remove() end)
                    end
                    pending_exits[retaddr] = nil
                end)
            pending_exits[retaddr] = exit_tap
        end
    end
end

-- Periodic PC ring buffer.  Sampled via emu.register_periodic at the
-- host's frame rate (50 Hz), so this is NOT a literal per-instruction
-- trace -- it's a coarse "recent PC samples" log.  Z80 at 4 MHz
-- executes ~80k instructions per host frame, so each entry represents
-- a 20 ms window's tail PC.  Useful as a "where was code running just
-- before the trap" hint when JP 0 fires.
local PC_HISTORY_SIZE = 256
local pc_history = {}
local pc_history_idx = 0
local pc_seen_zero = false  -- one-shot: log JP-0 trap exactly once

local function log_jp_zero_trap(trigger)
    log_line(string.format("[%9.4fs] === JP 0 TRAP %s ===", emu.time(), trigger))
    log_line(string.format("[%9.4fs] %s ENTRY %s", emu.time(), "JP-0", regs_str()))
    -- Stack chain: 32 bytes from SP showing return-address frames.
    -- Each pushed `call` puts retaddr-low then retaddr-high; the
    -- relocator/NDOS/BDOS path is several frames deep at this point.
    local sp = state["SP"].value
    local chain = {}
    for i = 0, 30, 2 do
        local lo = prog:read_u8((sp + i) % 0x10000)
        local hi = prog:read_u8((sp + i + 1) % 0x10000)
        chain[#chain + 1] = string.format("%04X", lo + hi * 256)
    end
    log_line(string.format("[%9.4fs] stack@SP: %s",
        emu.time(), table.concat(chain, " ")))
    -- PC ring buffer in chronological order (oldest -> newest).
    local hist = {}
    local n = #pc_history
    if n > 0 then
        for i = 0, n - 1 do
            local idx = ((pc_history_idx + i) % n) + 1
            if pc_history[idx] then
                hist[#hist + 1] = string.format("%04X", pc_history[idx])
            end
        end
    end
    log_line(string.format("[%9.4fs] PC history (oldest->newest, %d samples): %s",
        emu.time(), #hist, table.concat(hist, " ")))
    pc_seen_zero = true
end

local installed = false
emu.register_periodic(function()
    if not installed then
        cpu = manager.machine.devices[":maincpu"]
        if cpu == nil then return end
        prog = cpu.spaces["program"]
        state = cpu.state
        if prog == nil then return end

        -- Resident BIOS JT 0xED00..0xED32
        prog:install_read_tap(0xED00, 0xED32, "biosjt_resident_bios",
            on_jt_read("ED-BIOS", bios_names, 0xED00))
        -- Resident SNIOS JT 0xED33..0xED4A
        prog:install_read_tap(0xED33, 0xED4A, "biosjt_resident_snios",
            on_jt_read("ED-SNIO", snios_names, 0xED33))
        -- NDOS-patched JT copy 0xCF00..0xCF32 (BIOS only)
        prog:install_read_tap(0xCF00, 0xCF32, "biosjt_ndos_copy",
            on_jt_read("CF-BIOS", bios_names, 0xCF00))

        -- JP 0 trap: opcode-fetch at PC=0 indicates a JP/CALL through
        -- a zero (uninitialised) function pointer or wild branch.
        -- Common bug-class pattern in CP/NOS: NDOS warm-boots on
        -- error by JPing 0; ALSO surfaces stack underflow (return to
        -- pushed 0).  Filter PC==0 to distinguish opcode fetch from
        -- relocator's read of the reset vector.
        prog:install_read_tap(0x0000, 0x0001, "jp_zero_trap",
            function(offset, data, mask)
                if pc_seen_zero then return end          -- one-shot
                if state["PC"].value ~= 0 then return end -- not a fetch
                if offset ~= 0 then return end
                log_jp_zero_trap("opcode-fetch at PC=0")
            end)

        log_line(string.format("[%9.4fs] === trace start (timeout=%.1fs, max=%d) ===",
            emu.time(), TIMEOUT_S, MAX_LINES))
        installed = true
    end

    -- PC ring buffer sample.  Coarse (~50 Hz) but cheap.
    pc_history_idx = (pc_history_idx % PC_HISTORY_SIZE) + 1
    pc_history[pc_history_idx] = state["PC"].value

    if emu.time() >= TIMEOUT_S then
        log_line(string.format("[%9.4fs] === trace end (timeout) ===", emu.time()))
        out_f:close()
        manager.machine:exit()
    end
end)
