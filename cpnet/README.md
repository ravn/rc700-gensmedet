# RC702 CP/NET Implementation & Tools

This directory contains the CP/NET 1.2 client stack for the Regnecentralen RC702 running CP/M 2.2 with `rcbios`.

---

## Architecture & SNIOS Variants

CP/NET loads `SNIOS.SPR` (Slave Network I/O System) and `NDOS.SPR` (Network DOS) below the CP/M BIOS using `CPNETLDR.COM`.
`CPNETLDR` allocates SNIOS in whole 256-byte pages (`ceil(total_len / 256)`). To maximize the Transient Program Area (TPA) available to applications (such as PolyPascal), SNIOS is split into two lean, dedicated variants:

| Variant | Binary | Code Size | Loader Pages | SNIOS Range | NDOS Range | Resulting TPA | Notes |
|:---|:---|:---:|:---:|:---:|:---:|:---:|:---|
| **SIO** | `SNIOSSIO.SPR` | 722 B (0x02D2) | **3 pages (768 B)** | `0xC900..0xCBFF` | `0xBD00..0xC8FF` | **48,128 B (47.00 KB)** | Uses BIOS `rxbuf_a` in high RAM; 0 buffer bytes in SNIOS. +512 B TPA gain. |
| **PIO** | `SNIOSPIO.SPR` | 907 B (0x038B) | **4 pages (1024 B)** | `0xC800..0xCBFF` | `0xBC00..0xC7FF` | **47,872 B (46.75 KB)** | Uses 64-byte internal `PIO_RING` buffer. +256 B TPA gain. |
| **Default** | `SNIOS.SPR` | — | — | — | — | — | Byte-identical copy of `SNIOSSIO.SPR` for standard `CPNETLDR`. |

### Startup Banner
On `NTWKIN` (network initialization), SNIOS prints a banner to the console via BIOS `B$CONOUT`:
```text
RC702 SNIOS (<variant>) <YYYY-MM-DD HH:MM> <git-sha>
```
*Note: `HL` is explicitly saved/restored with `PUSH HL` / `POP HL` around `B$CONOUT`, as the C-compiled BIOS CONOUT clobbers `HL`.*

---

## Building SNIOS

To build all SPR variants using `zmac`:
```bash
python3 build_snios.py
```
This automatically:
1. Samples the current git short commit hash and timestamp into `zout/buildinfo.inc`.
2. Assembles `snios.asm` at ORG `0x0000` and `0x0100` with `TRANSPORT_SIO` to build the relocation bitmap, outputting `zout/SNIOSSIO.SPR`.
3. Assembles `snios.asm` with `TRANSPORT_PIO` (with `PIO_RING_SIZE EQU 64`), outputting `zout/SNIOSPIO.SPR`.
4. Copies `SNIOSSIO.SPR` to `SNIOS.SPR`.

---

## Automated Disk Preparation

`prepare_interactive_disk.py` builds an end-to-end bootable MFI diskette ready for MAME:
```bash
python3 prepare_interactive_disk.py
```
It handles:
1. Copying the clean base CP/M 2.2 floppy image (`IMG_MAXI` / `SW1711-I8.imd`).
2. Patching the latest C BIOS (`bios.clang.cim`).
3. Injecting `SNIOS.SPR`, `SNIOSSIO.SPR`, `SNIOSPIO.SPR`, `NDOS.SPR`, and CP/NET client tools (`CPNETLDR`, `LOGIN`, `NETWORK`, `PIPNET`, etc.).
4. **Boot Auto-Execution (`0:$$$.SUB`)**:
   - In CP/M 2.2, `$$$.SUB` is a **binary** file of 128-byte records read in **reverse order** by the CCP.
   - Byte 0 holds the length of the uppercase command, followed by ASCII bytes and `0x00` padding.
   - Injects the auto-login sequence:
     ```text
     CPNETLDR
     LOGIN PASSWORD
     NETWORK H:=I:
     H:
     DIR
     ```
5. **Text Script (`0:AUTO.SUB`)**: Plain ASCII text file with CR+LF line endings for manual inspection or execution via `SUBMIT AUTO`.
6. Output: `zout/interactive/disk.imd` and `zout/interactive/disk.mfi`.

---

## Testing & Verification

### Automated Round-Trip Integrity Test
`chksum_roundtrip_test.sh` executes an end-to-end verification against MP/M II:
```bash
./chksum_roundtrip_test.sh
```
1. Generates a deterministic 2048-byte binary test fixture (`0x00..0xFF` repeated 8 times).
2. Boots MAME headlessly connected to MP/M II on port 4002.
3. Automatically runs:
   - `CPNETLDR`
   - `LOGIN PASSWORD`
   - `NETWORK H:=B:`
   - `PIPNET H:FIXT.DAT=A:FIXT.DAT` (push to server)
   - `PIPNET A:BACK.DAT=H:FIXT.DAT` (pull back from server)
   - `CHKSUM A:FIXT.DAT`, `CHKSUM A:BACK.DAT`, `CHKSUM H:FIXT.DAT`
4. Validates that all three checksums match `0xFC00`.

### Interactive MAME Session
To run interactively with the graphical MAME window and network drives mapped:
1. Ensure the MP/M server is running:
   ```bash
   make -C ../cpnos-in-c _kill-mpm && (cd ../z80pack/cpmsim && screen -dmS mpm ./mpm-net2 && sleep 1)
   ```
2. Launch MAME:
   ```bash
   /Users/ravn/z80/mame/regnecentralend rc702 -rompath /Users/ravn/z80/mame/roms \
     -rom1 /Users/ravn/z80/rc700-gensmedet/autoload-in-c/clang/prom0.ic66 \
     -flop1 /Users/ravn/z80/rc700-gensmedet/cpnet/zout/interactive/disk.mfi \
     -rs232a null_modem -bitb1 socket.127.0.0.1:4002 \
     -skip_gameinfo -window -resolution 1100x720
   ```
The machine will boot, display the SNIOS banner, log in, map the PolyPascal drive `I:` to `H:`, switch to `H:`, and list the directory.
