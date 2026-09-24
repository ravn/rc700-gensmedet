# MAME host-to-RC702 Danish keyboard mapping is broken (deferred)

**Status:** reported 2026-04-17 while running `mame-maxi` with the clang
BIOS on Linux. ASCII keystrokes reach the RC702 PIO correctly; Danish
`æ / ø / å` (and presumably other Latin-1 chars) do not. Not blocking
the BIOS bring-up on real hardware; defer until after the CP/NET /
parallel work.

## Root cause

`mame/src/mame/regnecentralen/rc702.cpp` uses MAME's stock
`generic_keyboard_device`:

```cpp
// rc702.cpp:531-532
generic_keyboard_device &keyboard(GENERIC_KEYBOARD(config, "keyboard", 0));
keyboard.set_keyboard_callback(FUNC(rc702_state::kbd_put));

// rc702.cpp:444
void rc702_state::kbd_put(u8 data) {
    m_kbd_data = data;
    m_pio->strobe_a(0);
    m_pio->strobe_a(1);
}
```

`generic_keyboard` delivers **one byte per callback invocation**. Linux
passes Danish characters as **UTF-8**: `æ = 0xC3 0xA6`, `ø = 0xC3 0xB8`,
`å = 0xC3 0xA5`. Only the lead byte (0xC3) reaches `kbd_put`, or the
device drops non-ASCII entirely. Either way, the RC702 PIO never sees
the intended Latin-1 code, so the BIOS `inconv[]` has nothing to
translate.

ASCII 0x20-0x7E works because those are single-byte in UTF-8 and
pass through untouched — matches the reporter's "works for others"
observation.

## Where the RC702 source comments already call this out

```cpp
// rc702.cpp:20-21
ToDo:
- Keyboard MCU (8048 + 2758) — currently using generic_keyboard
```

The correct long-term fix is to model the real 8048 keyboard MCU + its
2758 ROM so that MAME emits the actual raw scancodes the BIOS
`inconv[]` table expects. That ROM is undumped (per the same file's
top comment: "Keyboard has 8048 and 2758, both undumped").

## Fix options (easiest first)

### 1. UTF-8 → Latin-1 reassembly in `kbd_put` (MAME patch)

Buffer UTF-8 lead bytes in `kbd_put`; emit the assembled Unicode
codepoint to the PIO if it fits in 0x80-0xFF. Requires editing the
MAME source tree (ravn/mame-rc702-rc759-rc750 submodule).

Sketch:

```cpp
void rc702_state::kbd_put(u8 data) {
    static u32 acc = 0;
    static int remaining = 0;
    if (data < 0x80) {
        acc = data; remaining = 0;
    } else if ((data & 0xE0) == 0xC0) {
        acc = data & 0x1F; remaining = 1; return;
    } else if ((data & 0xF0) == 0xE0) {
        acc = data & 0x0F; remaining = 2; return;
    } else if ((data & 0xC0) == 0x80 && remaining > 0) {
        acc = (acc << 6) | (data & 0x3F);
        if (--remaining > 0) return;
    } else {
        remaining = 0; return;   // bogus sequence
    }
    u8 out = (acc <= 0xFF) ? (u8)acc : '?';
    m_kbd_data = out;
    m_pio->strobe_a(0);
    m_pio->strobe_a(1);
}
```

Pros: entirely local to rc702.cpp; minimal diff; restores Danish
(and other Latin-1) input. Cons: still not the "real" RC702 raw
scancode format.

### 2. PORT_CHAR natural-keyboard mapping

Replace `generic_keyboard_device` with a real PORT_CHAR-based input
definition that maps host keys (including `æ / ø / å` as 16-bit
Unicode values via `PORT_CHAR(u'æ')` etc.) to RC702 PIO bytes.
Requires defining the full RC702 key matrix in rc702.cpp.

### 3. Real 8048 keyboard MCU emulation

Dump the 2758 ROM (needs access to a physical RC702 keyboard with
the MCU), add an 8048 CPU core instance with the ROM, route its
output to the PIO strobe. Most faithful; biggest engineering effort;
blocked on a physical ROM dump.

## Workaround in the meantime

For running clang BIOS smoke tests in MAME that don't need Danish
input, stick to ASCII-only commands. All core CP/M workflows (DIR,
PIP, SUBMIT, SYSGEN, etc.) are pure ASCII, so this doesn't block the
existing test loop.

For Danish input on real hardware flashing via `deploy.sh`: the
host-side serial send path (`mk_cpm56.py` + `send_hex_rtscts.py`) is
byte-accurate — Danish chars in disk content transfer correctly. This
bug is MAME-only.

## Related

- `boot_confi.c` `conv_tables[384]` and `locale/danish_tables.h`
  define the BIOS-side Danish character mapping. Unaffected by this
  bug (the PIO simply never receives the right byte).
- `bios.h:66` has the comment about national character sets.
