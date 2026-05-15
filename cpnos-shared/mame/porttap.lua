-- Sumtest workload tap (port-based detection).  Drives smoke_inject
-- via SIO-B as before, but ALSO installs I/O write taps on:
--   port 0x80 -- sumtest writes here at end-of-run (deterministic
--                "sumtest finished OK" signal, value = 0x55)
--   port 0x81 -- impl_wboot in resident BIOS writes here on every
--                CP/M warm boot (program exit via JP 0).  Value = 0x57.
--                Generic "Nth program exited" counter for harnesses
--                that need to wait for non-sumtest programs (m80, l80,
--                or future workloads).
-- Both ports live in RC702's unmapped 0x20-0xEF range (rc702.cpp:155-163).

local marks_path  = "/tmp/cpnos_boot_marks.txt"
local result_path = "/tmp/cpnos_boot_result.txt"
local wboot_path  = "/tmp/cpnos_wboot.txt"
do for _, p in ipairs({result_path, wboot_path}) do
    local f = io.open(p, "w") if f then f:close() end
end end

local prog
local io_space
local tap_installed = false
local wboot_count = 0

emu.register_periodic(function ()
    if prog == nil then
        local cpu = manager.machine.devices[":maincpu"]
        if cpu == nil then return end
        prog = cpu.spaces["program"]
        io_space = cpu.spaces["io"]
        if prog == nil or io_space == nil then return end
    end

    if not tap_installed then
        local diag = io.open("/tmp/cpnos_porttap_diag.txt", "w")
        if diag then diag:write("[install] starting\n") diag:close() end
        local ok1, err1 = pcall(function()
            io_space:install_write_tap(0x80, 0x80, "sumtest_done",
                function(offset, data, mask)
                    local t = emu.time()
                    local f = io.open(result_path, "w")
                    if f then
                        f:write(string.format("OK port=0x80 data=0x%02x t=%.3fs\n",
                            data, t))
                        f:close()
                    end
                end)
        end)
        local ok2, err2 = pcall(function()
            io_space:install_write_tap(0x81, 0x81, "wboot",
                function(offset, data, mask)
                    wboot_count = wboot_count + 1
                    local t = emu.time()
                    local f = io.open(wboot_path, "w")
                    if f then
                        f:write(string.format("count=%d data=0x%02x t=%.3fs\n",
                            wboot_count, data, t))
                        f:close()
                    end
                end)
        end)
        local diag2 = io.open("/tmp/cpnos_porttap_diag.txt", "a")
        if diag2 then
            diag2:write(string.format("[install] tap-0x80 ok=%s err=%s\n",
                tostring(ok1), tostring(err1)))
            diag2:write(string.format("[install] tap-0x81 ok=%s err=%s\n",
                tostring(ok2), tostring(err2)))
            diag2:close()
        end
        tap_installed = true
    end

    -- Mirror boot strip for the bash harness (no detection logic here).
    local s = ""
    for i = 0, 18 do
        local b = prog:read_u8(0xF800 + 60 + i)
        if b == 0 or b == 0x20 then s = s .. " "
        else s = s .. string.char(b) end
    end
    local f = io.open(marks_path, "w")
    if f then f:write(s) f:close() end

    -- Auto-exit when smoke_inject reports the bench marker.  Without
    -- this MAME runs to -seconds_to_run (1200s) after the workload
    -- finishes, blocking the make target.  smoke_inject writes a
    -- "[marker] CPNET OK found (bench=Xs)" line on completion; a
    -- presence-check is enough — we don't reparse the timing.
    local log = io.open("/tmp/cpnos_smoke_inject.log", "r")
    if log then
        local content = log:read("*a")
        log:close()
        if content and content:find("[marker] CPNET OK found", 1, true) then
            -- Give CCP one more periodic to drain the trailing E>
            -- prompt onto SIO-B (so /tmp/cpnos_siob.raw is complete).
            if exit_after == nil then
                exit_after = emu.time() + 0.5
            elseif emu.time() >= exit_after then
                manager.machine:exit()
            end
        end
    end
end)
