# SDL3 Cmd-Q / `SDL_EVENT_QUIT` semantics on macOS — measured data

Investigation of how macOS "Quit" gestures reach MAME under SDL3, to determine
whether the SDL2-era `SDL_QUIT` handling concerns still apply, and to establish
the correct fix for the default macOS build (`OSD=sdl3`).

## Why this matters

On the default macOS build (`OSD=sdl3`), **Cmd-Q does nothing**: MAME does not
quit and the `q` is delivered to the emulated machine as a keystroke. The SDL2
path (`OSD=sdl`, not the macOS default) is a separate code file. MAME historically
did not special-case `SDL_QUIT` on macOS because under SDL2 choosing "Quit"
produced a window-close event *followed by* `SDL_QUIT`, which was awkward to
handle. The open question was whether SDL3 changes those semantics.

## Setup

- MAME built with `OSD=sdl3` (the macOS default) against `SDL3.xcframework`.
- `src/osd/sdl3/osdsdl.cpp::process_events()` instrumented to log every
  `event.type` (plus keycode / scancode / mod for key events); mouse-motion
  (`0x0400`) filtered out to reduce noise.
- Machine: `rc702`, tested windowed and fullscreen.
- Each quit action isolated in its own run: the QUIT / close handler exits MAME,
  so the final event cluster before exit is exactly that action.

## Event-type reference (SDL3)

| Code | Event |
|---|---|
| `0x0100` | `SDL_EVENT_QUIT` |
| `0x0210` | `SDL_EVENT_WINDOW_CLOSE_REQUESTED` |
| `0x0217` | `SDL_EVENT_WINDOW_ENTER_FULLSCREEN` |
| `0x0300` / `0x0301` | `SDL_EVENT_KEY_DOWN` / `SDL_EVENT_KEY_UP` |
| `0x020c`–`0x020f` | window mouse-enter / mouse-leave / focus-gained / focus-lost |

Key values: `key=0x400000e3` = `SDLK_LGUI` (left Cmd); `key=0x71` = `q`;
`mod=0x0400` = `SDL_KMOD_LGUI`.

## Summary

| Action | Final event sequence | `q` leaks to guest? |
|---|---|---|
| **Cmd-Q (windowed)** | `KEY_DOWN Cmd` → `KEY_DOWN q` → **`QUIT`** | Yes |
| **Cmd-Q (fullscreen)** | `KEY_DOWN Cmd` → `KEY_DOWN q` → **`QUIT`** (identical) | Yes |
| **App menu → Quit** | **`QUIT`** alone | No |
| **Red close button** | **`WINDOW_CLOSE_REQUESTED`** → `QUIT` | No |

## Conclusions

1. **The SDL2 "window-close followed by `SDL_QUIT`" behaviour does NOT occur in
   SDL3.** Quit (Cmd-Q or the app menu) produces a standalone `SDL_EVENT_QUIT`
   with no preceding window-close event.
2. **Quit and window-close are cleanly distinguishable under SDL3:**
   - Quit → bare `SDL_EVENT_QUIT` (no `WINDOW_CLOSE_REQUESTED`).
   - Window close (red button) → `WINDOW_CLOSE_REQUESTED` first, then a trailing
     `QUIT` (SDL posts QUIT when the last window closes).
3. Cmd-Q and app-menu Quit are equivalent (both bare `QUIT`), windowed and
   fullscreen.
4. **Caveat:** Cmd-Q additionally delivers `KEY_DOWN 'q'` (mod=Cmd) to the guest —
   a one-frame keystroke leak before exit. App-menu Quit does not leak.

## The fix (verified)

Handling `SDL_EVENT_QUIT` in `src/osd/sdl3/osdsdl.cpp` makes Cmd-Q quit MAME:

```cpp
#if defined(__APPLE__) && defined(__MACH__)
        case SDL_EVENT_QUIT:
            machine().schedule_exit();
            break;
#endif
```

macOS-gated because on Linux `SDL_QUIT` is generated for Ctrl+C in the controlling
terminal, so leaving it universal would change that behaviour.

**Exit-immediacy:** launched with a machine on the command line (`rc702`), Cmd-Q
with this fix exits the MAME process immediately (clean shutdown, exit code 0) —
it does not return to an internal menu. (The launcher-mode case — MAME started
with no machine, machine chosen from the internal system-selection menu — is
governed by MAME's general `schedule_exit()` behaviour and was not measured here.)

Fork branch: `osd-sdl3-cmdq` (github.com/ravn/mame).

## Raw data

Instrumented `EVT type=...` log tails, one run per action (last events before exit):

### Cmd-Q (windowed)
```
EVT type=0x020e
EVT type=0x0204
EVT type=0x020c
EVT type=0x0300 key=0x400000e3 scancode=227 mod=0x0400   ; KEY_DOWN Cmd
EVT type=0x0300 key=0x00000071 scancode=20  mod=0x0400   ; KEY_DOWN 'q' (Cmd held)
EVT type=0x0100                                          ; QUIT
```

### Red close button
```
EVT type=0x020c
EVT type=0x020d
EVT type=0x0210                                          ; WINDOW_CLOSE_REQUESTED
EVT type=0x0100                                          ; QUIT (trailing, last-window-close)
```

### App menu → Quit
```
EVT type=0x0204
EVT type=0x020c
EVT type=0x020d
EVT type=0x0100                                          ; QUIT (no key, no window-close)
```

### Cmd-Q (fullscreen)
```
EVT type=0x0215
EVT type=0x0204
EVT type=0x0300 key=0x400000e3 scancode=227 mod=0x0400   ; KEY_DOWN Cmd
EVT type=0x0300 key=0x00000071 scancode=20  mod=0x0400   ; KEY_DOWN 'q' (Cmd held)
EVT type=0x0100                                          ; QUIT
```
(`SDL_EVENT_WINDOW_ENTER_FULLSCREEN 0x0217` appeared earlier in the same run.)
