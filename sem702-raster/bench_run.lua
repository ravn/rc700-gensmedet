-- bench_run.lua -- run BENCH.COM, read results, snapshot mid-mode-1, exit.
--
-- BENCH.COM runs Mode 0 (blank) bench + Mode 1 (contended full-screen) bench,
-- writes 4 x 16-bit frame deltas to the result table, settles 2 s, warm-boots.
-- We watch tick_hi/tick_lo, snapshot when contention bench is active (after
-- mode 0 completes -- detect via mode0_b being nonzero), then read all 4
-- results and print them with wait-state inference.

local CMD            = "BENCH"
local TIMEOUT_FRAMES = 50 * 30

-- BSS offsets in BENCH.COM (.cim loads at 0x100; offsets read from
-- zout/bench.lst after build):
local I_REG          = 0x024C
local TICK_LO        = 0x024D
local TICK_HI        = 0x024E
local MODE0_A        = 0x024F
local MODE0_B        = 0x0251
local MODE1_A        = 0x0253
local MODE1_B        = 0x0255

local BENCH_M        = 20000        -- must match bench.asm
local Z80_HZ         = 4000000
local FRAMES_PER_SEC = 50
local T_PER_FRAME    = Z80_HZ / FRAMES_PER_SEC      -- 80000

local frame   = 0
local typed   = false
local snapped = false
local printed = false

local function space()
    return manager.machine.devices[":maincpu"].spaces["program"]
end

local function rd_u16(addr)
    local s = space()
    return s:read_u8(addr) + s:read_u8(addr + 1) * 256
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

emu.register_frame_done(function()
    frame = frame + 1

    if not typed then
        if at_prompt() then
            typed = true
            print(string.format("[bench_run] CCP prompt at frame %d, typing %s",
                                frame, CMD))
            manager.machine.natkeyboard:post(CMD .. "\r")
        end
        return
    end

    -- Snapshot when mode 0 has finished + mode 1 is mid-bench
    -- (mode0_b populated, mode1_b still zero).
    if not snapped then
        local m0b = rd_u16(MODE0_B)
        local m1b = rd_u16(MODE1_B)
        if m0b > 0 and m1b == 0 then
            manager.machine.video:snapshot()
            snapped = true
            print(string.format("[bench_run] mid-mode-1 snapshot at frame %d (m0b=%d, m1b=%d)",
                                frame, m0b, m1b))
        end
    end

    -- Print final results once mode 1 completes.
    if not printed then
        local m1b = rd_u16(MODE1_B)
        if m1b > 0 then
            printed = true
            local m0a = rd_u16(MODE0_A)
            local m0b = rd_u16(MODE0_B)
            local m1a = rd_u16(MODE1_A)
            local m1b_v = rd_u16(MODE1_B)
            local i_reg = space():read_u8(I_REG)

            -- T per OUT (D3) inferred from (B - A) * T_PER_FRAME / M:
            -- The baseline loop runs M iters of [nop nop / dec bc / ld a,b /
            -- or c / jr nz].  Replacing nop nop with [out (D3),a] adds
            -- (OUT_T - 2*NOP_T) per iter = (T_OUT_effective - 8) T.
            local out_t_mode0 = ((m0b - m0a) * T_PER_FRAME / BENCH_M) + 8
            local out_t_mode1 = ((m1b - m1a) * T_PER_FRAME / BENCH_M) + 8

            print(string.format("[bench_run] I=%02X  M=%d  results (frame deltas):", i_reg, BENCH_M))
            print(string.format("[bench_run]   mode0 BLANK:    A=%d  B=%d  -> T/OUT~%.2f  (expected 11.0 no-wait)",
                                m0a, m0b, out_t_mode0))
            print(string.format("[bench_run]   mode1 CONTEND:  A=%d  B=%d  -> T/OUT~%.2f",
                                m1a, m1b_v, out_t_mode1))
            local extra = out_t_mode1 - out_t_mode0
            print(string.format("[bench_run]   wait-state delta under contention: %+.2f T/OUT", extra))
            if math.abs(extra) < 0.3 then
                print("[bench_run]   verdict: MAME shows no contention wait-state (expected; SEM702 board is custom logic).")
            else
                print("[bench_run]   verdict: contention DETECTED in MAME.  Re-verify on real hw.")
            end
            -- Let bench's 2 s settle finish + warm-boot before exit.
            manager.machine:exit()
        end
    end

    if frame > TIMEOUT_FRAMES then
        print(string.format("[bench_run] TIMEOUT after %d frames", frame))
        manager.machine:exit()
    end
end)
