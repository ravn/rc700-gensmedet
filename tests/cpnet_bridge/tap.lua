-- license: BSD-3-Clause
--
-- MAME autoboot script — CP/NET fast-link bring-up test tap.
--
-- Watches display memory for the "RC702 CP/NOS v1.2" signon (proof
-- that cpnos-rom finished init_hardware AND netboot AND nos_handoff)
-- and the BSS counter that isr_pio_par increments (proof that bytes
-- sent over the PIO-B bridge actually reach the Z80 ISR).
--
-- BSS addresses come from /tmp/cpnos_bridge_addrs.lua (written by the
-- harness from `llvm-nm cpnos-rom/clang/payload.elf`).

local addrs = dofile("/tmp/cpnos_bridge_addrs.lua")
local PIO_PAR_BYTE_ADDR  = addrs.pio_par_byte
local PIO_PAR_COUNT_ADDR = addrs.pio_par_count
-- Loopback test addresses are optional (set only when cpnos was built
-- with PIO_LOOPBACK_TEST=1 and harness extracted the symbols).  If
-- absent, the loopback watcher below stays a no-op.
local PIO_TEST_DONE_ADDR   = addrs.pio_test_done
local PIO_TEST_RECV_ADDR   = addrs.pio_test_recv
local PIO_TEST_PASSED_ADDR = addrs.pio_test_passed
local PIO_FRAME_LEN        = 10
local DSPSTR             = 0xF800
local SIGNON_ROW1        = 0xF850

local READY_FILE      = "/tmp/cpnos_bridge_ready.txt"
local TAP_LOG         = "/tmp/cpnos_bridge_tap.log"
local LOOPBACK_RESULT = "/tmp/cpnos_loopback_result.txt"
local BOOT_MARKS_FILE = "/tmp/cpnos_boot_marks.txt"
local BOOT_MARKS_LOG  = "/tmp/cpnos_boot_marks.log"

local last_boot_strip = nil

-- Boot-marker strip: 19 chars at row 0 cols 60..78 (0xF83C..0xF84E).
-- Written every poll so the harness can inspect post-mortem which
-- transport probe selected ('P'/'S' at idx 7) and how far init/netboot
-- got.  See hal.h::BOOT_MARK_BASE.
local BOOT_MARK_BASE_VRAM = 0xF800 + 60
local BOOT_MARK_LEN       = 19

do
	local f = io.open(READY_FILE, "w") if f then f:close() end
	local f2 = io.open(TAP_LOG, "w")  if f2 then f2:close() end
	local f3 = io.open(BOOT_MARKS_LOG, "w") if f3 then f3:close() end
	-- Don't truncate LOOPBACK_RESULT here — its absence is the
	-- harness's "not yet" signal.
end

local tap_installed = false
local boot_seen     = false
local loopback_logged = false
local prog          = nil
local last_count    = 0
local isr_hits      = 0

emu.register_periodic(function ()
	if prog == nil then
		local cpu = manager.machine.devices[":maincpu"]
		if cpu == nil then return end
		prog = cpu.spaces["program"]
		if prog == nil then return end
	end

	-- Banner watch — write READY once cpnos-rom prints
	-- "RC702 CP/NOS v1.2" (cpnos_main.c::nos_handoff signon, runs
	-- after netboot completes and just before EI/JP NDOS COLDST).
	if not boot_seen then
		if  prog:read_u8(SIGNON_ROW1 + 0) == 0x52  -- 'R'
		and prog:read_u8(SIGNON_ROW1 + 1) == 0x43  -- 'C'
		and prog:read_u8(SIGNON_ROW1 + 2) == 0x37  -- '7'
		and prog:read_u8(SIGNON_ROW1 + 3) == 0x30  -- '0'
		and prog:read_u8(SIGNON_ROW1 + 4) == 0x32  -- '2'
		then
			boot_seen = true
			local f = io.open(READY_FILE, "w")
			if f then f:write("READY\n") f:close() end
		end
	end

	-- Boot-marker strip snapshot — overwritten each poll.  Cheap: 19
	-- byte reads + one file rewrite.  Lets the harness see which
	-- transport probe selected without parsing display memory itself.
	-- Also append to BOOT_MARKS_LOG with wall timestamps each time the
	-- strip changes — so the harness can time per-marker boot phases.
	do
		local s = ""
		for i = 0, BOOT_MARK_LEN - 1 do
			local b = prog:read_u8(BOOT_MARK_BASE_VRAM + i)
			if b >= 0x20 and b < 0x7F then
				s = s .. string.char(b)
			else
				s = s .. "."
			end
		end
		local f = io.open(BOOT_MARKS_FILE, "w")
		if f then f:write(s .. "\n") f:close() end
		if s ~= last_boot_strip then
			last_boot_strip = s
			local g = io.open(BOOT_MARKS_LOG, "a")
			if g then
				-- machine.time is an attotime in emulated Z80-clock
				-- seconds, regardless of MAME throttle setting.
				-- attotime has .seconds (int part) and .attoseconds.
				local at = manager.machine.time
				local t = at.seconds + at.attoseconds * 1e-18
				g:write(string.format("%.6f %s\n", t, s))
				g:close()
			end
		end
	end

	-- Polled count + cross-check.  No memory taps installed:
	-- earlier experiments showed install_read_tap and
	-- install_write_tap on 0xEA38-area / 0xEF8E broke the IM2 IRQ
	-- chain in MAME's emulation (symptom: crt_ticks counter at
	-- 0xFFFC stayed at uninitialized BSS, never incrementing) so
	-- both CRT VRTC and PIO-B IRQs stopped firing.  Pure polling
	-- has no such side effect.
	local cur = prog:read_u8(PIO_PAR_COUNT_ADDR)
	if cur ~= last_count then
		local byte = prog:read_u8(PIO_PAR_BYTE_ADDR)
		-- 32-bit CRT frame counter at 0xFFFC..0xFFFF (low byte first).
		local crt_ticks = prog:read_u8(0xFFFC)
		local f = io.open(TAP_LOG, "a")
		if f then
			f:write(string.format("count=%d byte=0x%02X crt_ticks=%d\n",
				cur, byte, crt_ticks))
			f:close()
		end
		last_count = cur
	end

	-- Loopback test watch: when cpnos_main's pio_loopback_test sets
	-- pio_test_done = 1, snapshot pio_test_recv (10-byte CP/NET
	-- frame) + pio_test_passed to LOOPBACK_RESULT.  Speed-test build
	-- has only pio_test_done (no recv/passed); skip the frame-shape
	-- branch then but still snapshot the screen on completion.
	if PIO_TEST_DONE_ADDR ~= nil
	   and not loopback_logged
	   and prog:read_u8(PIO_TEST_DONE_ADDR) ~= 0 then
		local body
		if PIO_TEST_RECV_ADDR ~= nil then
			-- Loopback (frame): emit recv hex + passed flag.
			local hex = ""
			for i = 0, PIO_FRAME_LEN - 1 do
				hex = hex .. string.format("%02X",
					prog:read_u8(PIO_TEST_RECV_ADDR + i))
			end
			local passed = (PIO_TEST_PASSED_ADDR ~= nil)
				and prog:read_u8(PIO_TEST_PASSED_ADDR) or 0
			body = string.format("%s passed=%d", hex, passed)
		else
			-- Speed-rx (no recv buffer): just emit a marker so the
			-- harness can detect completion.
			body = "done"
		end
		local f = io.open(LOOPBACK_RESULT, "w")
		if f then f:write(body .. "\n") f:close() end
		-- Capture screen state so we can verify visually that boot
		-- completed cleanly + boot markers are in upper-right corner.
		manager.machine.video:snapshot()
		loopback_logged = true
	end
end)
