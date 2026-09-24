# Session 16b Summary (2026-04-12)

## BIOS deploy via dual serial — end-to-end working

Built an automated test that deploys a new BIOS over serial in MAME:
boots with SDCC BIOS, transfers clang BIOS hex, installs via SYSGEN,
hard resets, and verifies the banner changed from `C-bios/sdcc` to
`C-bios/clang`.

### Final workflow (deploy-serial Makefile target)

1. Build both clang and SDCC BIOS
2. Patch SDCC BIOS onto disk image, add MLOAD.COM + BDOSCCP.COM via cpmcp
3. Convert IMD → MFI (writable format)
4. Boot MAME, verify SDCC banner
5. PIP CPM56.HEX=RDR: — transfer 390 records (17KB) BIOS-only hex via SIO-A
6. MLOAD CPM56.COM=BDOSCCP.COM,CPM56.HEX — overlay BIOS onto CCP+BDOS base
7. CPM56 — run checksum validator (prints OK/FAIL)
8. SYSGEN CPM56.COM — write new system to track 0
9. Hard reset → verify clang banner on CRT

Total: ~76 seconds emulated time at ~340% speed.

### Bugs found and fixed

| Problem | Root Cause | Fix |
|---------|-----------|-----|
| Garbled hex data on SIO-A | Stale cfg: RS232_STOPBITS=0 (zero!) | Delete cfg/rc702.cfg before runs |
| Truncated transfer (430/468 records) | null_modem FLOW_CONTROL=0 (RTS ignored) | Set FLOW_CONTROL=0x01 in MAME driver |
| SIO-A missing DCD handler | Never wired in rc702.cpp | Added dcd_handler for dcda_w |
| SYSGEN writes lost on reset | IMD images read-only in MAME | Convert to MFI via floptool |
| Incorrect .COM from LOAD | LOAD can't merge base + hex overlay | Use MLOAD instead |
| Lua crash on hard_reset | CPU spaces nil during reset | pcall wrapper in mem_read |

### MAME driver changes (ravn/mame-rc702-rc759-rc750)

- `rc702.cpp`: SIO-A defaults changed to 38400 8N1 with RTS flow control
- `rc702.cpp`: SIO-B defaults added (38400 8N1, null_modem)
- `rc702.cpp`: DCD handler wired for both SIO channels
- `null_modem.cpp`: Comment fix (replaced TODO with explanation)

### New files

- `cpm-utils/mload/mload.asm` — MLOAD v2.5 source (assembles with zmac -8)
- `rcbios/diskdefs` — cpmtools disk format definitions for RC702

### Key infrastructure

- `cpmcp -f rc702-8dd` for injecting files onto IMD disk images
- `floptool flopconvert auto mfi` for writable MAME disk format
- MLOAD.COM assembled from source (zmac -8 --dri)
- BDOSCCP.COM extracted from cpm56_original.com (first 0x4400 bytes)
