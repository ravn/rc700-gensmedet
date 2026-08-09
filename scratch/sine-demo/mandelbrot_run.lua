-- mandelbrot_run.lua — boot rc702, type B:GFXTEST, then snapshot once the
-- number of DRAWN graphics cells stops growing (draw complete).  Robust to the
-- long, compiler-dependent compute time and to the blank post-clg() phase:
-- a blank screen has zero drawn cells, so it can never satisfy the "done" test.
local frame, stage, snapped = 0, 0, false
local typed_at = 0
local last_count, stable, last_check = -1, 0, 0

local function sp() return manager.machine.devices[":maincpu"].spaces["program"] end

-- "A>" prompt detector: 0x41 0x3E at the start of any of the 25 screen rows.
local function at_prompt()
  local s = sp()
  for r = 0, 24 do
    local b = 0xF800 + r * 80
    if s:read_u8(b) == 0x41 and s:read_u8(b + 1) == 0x3E then return true end
  end
  return false
end

-- Count non-blank cells: a cleared RC700 screen is all 0x20 (space), so a blank
-- or just-cleared screen counts ~0 (only the tiny command echo).  As mandelbrot
-- plots sextant glyphs the count climbs into the hundreds, then plateaus.
local function drawn_cells()
  local s = sp()
  local n = 0
  for a = 0xF800, 0xF800 + 80 * 25 - 1 do
    if s:read_u8(a) ~= 0x20 then n = n + 1 end
  end
  return n
end

emu.register_frame_done(function()
  if snapped then return end
  frame = frame + 1

  if stage == 0 then
    if at_prompt() then
      manager.machine.natkeyboard:post("B:GFXTEST\r")
      typed_at = frame; stage = 1
      print("[mandel] typed at frame " .. frame)
    end

  elseif stage == 1 then
    if frame - last_check >= 60 then
      last_check = frame
      local n = drawn_cells()
      -- Require a substantially drawn screen (mandelbrot fills a big region)
      -- AND no growth for 4 consecutive windows (~5 emu-seconds) => complete.
      -- NB: one text cell = 6 sextant subpixels, so the cell count saturates
      -- and briefly plateaus (~1-2s) while the heavy middle rows fill subpixels
      -- into already-lit cells.  Require a LONG static window (~24 emu-seconds)
      -- so only the finished, held image (static forever) qualifies.
      if n == last_count and n >= 200 then
        stable = stable + 1
        if stable >= 20 then
          snapped = true
          manager.machine.video:snapshot()
          print("[mandel] complete: " .. n .. " cells, snapped at frame " .. frame)
          manager.machine:exit()
        end
      else
        stable = 0
      end
      print("[mandel] frame " .. frame .. " cells=" .. n .. " stable=" .. stable)
      last_count = n
    end
  end

  -- Hard cap so a stuck run still snapshots+exits, deliberately BELOW the
  -- MAME -seconds_to_run cap (run with SECONDS >= 520) so the lua owns exit.
  if frame > 90000 then
    snapped = true
    print("[mandel] hard cap at frame " .. frame .. " cells=" .. drawn_cells())
    manager.machine.video:snapshot()
    manager.machine:exit()
  end
end)
