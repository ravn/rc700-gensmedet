# RC702 CONFI.COM configuration block

The RC700/RC702 system disks carry a **640-byte configuration block** at the
very start of the system tracks (disk offset `0x000`–`0x280`), *before* the CP/M
BIOS (which begins at `0x280`).  This block is what the **CONFI.COM** utility
edits: it holds the CRT/port setup and the output + keyboard character-set
mappings that the BIOS reads at cold boot.

Analysed 2026-07-02 across several RC702 disks (rel.2.1 disks 30003310/30003048
have **byte-identical** blocks = the standard/default config; the RC702E rel.1.7
disk 30003291 differs in the CRT/port and national-charset regions).

## Block layout

| Offset | Contents |
|--------|----------|
| `0x000` | 16-bit word = **`0x0280`** — the BIOS boot-entry offset (= size of this block; where the BIOS begins).  This is the word `extracted_bios` reads to locate each BIOS. |
| `0x008` | **`" RC702"`** — machine-type signature. |
| `0x00F–0x09F` | reserved (zero on the disks seen). |
| `0x0A0` | **Intel 8275 CRT reset parameters** — `4F 98 7A 4D`: `4F`=80 chars/row, `98`=25 rows (V=2), **`7A`=underline line 7 + 11 lines/char**, `4D`=field-attr/cursor/hrtc.  Note `7A` keeps underline **< 8**, so the 8275 does NOT blank the first/last scan line of each row — i.e. CONFI.COM systems ship with the semigraphics-friendly setting (unlike the ROA375 autoload PROM, which used underline 9; see `autoload-in-c` QR notes). |
| `0x0A4–0x0AF` | DMA/timing config (`03 03 df 28 …`) — differs per config. |
| `0x0B0–0x0C3` | **Port-setup / init-value table** — bytes OUT'd to configure the I/O chips (`18/08 … FF FF` separators); differs per machine config. |
| `0x0C4–0x0D3` | **Config vector table** — RAM pointers (e.g. `E9BF EA0C EA93 EAA1 EB31 EB79` on rel.1.7) to config-specific handlers; differs per config. |
| `0x120–0x1FF` | **Output character-set mapping** — a translation table for display output.  The standard/US config is the identity `0x20–0x7F`; a national config **remaps** the ASCII bracket/brace codes.  On the Danish rel.1.7 disk: `[ \ ]` (0x5B–0x5D) → `0x0B 0x0C 0x0D` and `{ | } ~` (0x7B–0x7E) → `0x1B 0x1C 0x1D 0x0F`, i.e. **Æ Ø Å / æ ø å** — exactly the substitution the rcbios `KBLANG` mechanism performs. |
| `0x200–0x27F` | **Keyboard translation table** — 128-byte scan/character map plus numeric-keypad rows (`20 31…39 …`, `30 31…39 …`) and national-character variants (high-bit codes). |

## What CONFI.COM configures (per the user)

The pre-BIOS block is exactly the area CONFI.COM lets the operator change:
1. **Output character-set mapping** (`0x120–0x1FF`) — the display glyph
   translation, incl. the national (e.g. Danish ÆØÅ) substitutions.
2. **Keyboard mapping** (`0x200–0x27F`) — key → character translation.
3. **Port setup** (`0x0A0–0x0D3`) — the 8275 CRT parameters, DMA/timing, I/O-port
   init values, and config vectors.

## Cross-references

- The **8275 params** here (`4F 98 7A 4D`) are the same class of values written by
  `autoload-in-c/rom.c` `init_crt()`; the `underline < 8` choice matches the QR /
  semigraphics fix documented there.
- The **national charset remap** is the on-disk form of the `KBLANG`
  (DANISH/SWEDISH/…) tables in `rcbios/`.
- The block's leading `0x0280` word is the boot-entry pointer described in
  `rcbios/extracted_bios/README.md`; on the RC702E rel.1.7 disk (Bits:30003291)
  the BIOS proper sits at `0x280`, "after the CONFI.COM area".
