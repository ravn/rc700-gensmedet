# RC759 GSX-86 driver — initial RE findings (session 1, 2026-10-31)

## Målsætning
Reverse-engineere `dd759h1.sys` (og de 11 varianter) til kommenteret
disassembly så vi kan vurdere om vi vil skrive en forbedret driver.

## Filer og organisation

- `bin/dd759*.sys` — 12 drivervarianter (`h/hd/hm/m/md/mm` × `1/4`).
  "1" = 1 plan (mono), "4" = 4 planer (farve). Suffikser er sandsynligvis
  medie-/skærmvarianter — skal bekræftes mod GKONFIG eller rc759-manual.
- `docs/` — GSX-86 manualer fra bitsavers.
- `disasm/disasm.py` — Capstone-baseret 8086 linear-sweep disassembler.
- `disasm/dd759h1.a86` — rå disassembly (3666 linjer).

## Filformat

8576 bytes flad binær. Struktur:

| Offset | Størrelse | Indhold |
|--------|-----------|---------|
| 0x0000 | 0x80      | GSX parameter-tabel (DEVID + default workstation state) |
| 0x0080 | ~0x80     | GIOS entry-dispatcher |
| 0x0100 | variabel  | Jump-tabel over GIOS-funktioner |
| ~0x146 | ...       | Funktionsimplementationer + data |

### Header-felter (0x00–0x1F som 16-bit LE words)

| Offset | Værdi    | Formodet betydning                        |
|-------:|---------:|-------------------------------------------|
| 0x00   | 0x0401   | DEVID (muligvis workstation ID 1025 el. 1,4) |
| 0x02   | 0x0001   | ?                                         |
| 0x04   | 0x0400   | ?                                         |
| 0x06   | 0x0001   | antal planer? (1 for `h1`-varianten)      |
| 0x08   | 0x0200   | ?                                         |
| 0x0A   | 0x00C4   | 196 — ?                                   |
| 0x0E   | 0x00C4   | 196 — gentaget                            |
| 0x10   | 0x1000   | BSS/stack-størrelse?                      |
| 0x12   | 0x3E03   | formodet segmentreference                 |
| 0x16   | 0x3E00   | formodet segmentreference                 |
| 0x18   | 0x0002   | ?                                         |

Enkeltbytes: `0x7D=0x42`, `0x7F=0x80` — betydning uafklaret.

Felterne skal krydstjekkes mod GSX manual (vi har PDF nu) og mod andre
`dd*.sys` drivere i mappen (`dd604*.sys` = Partner CRT osv.) for at se
hvilke felter varierer.

## GIOS entry-dispatcher (0x80–0xCD)

Rå flow:

```asm
0080:  mov ax, sp              ; gem callers SS:SP
0082:  mov bx, ss
0084:  mov cx, 0
0087:  mov ss, cx              ; SS = 0 (CP/M-86 relokeres? eller fast 0)
0089:  mov sp, 0x791           ; drivers egen stak
008c:  push bx                 ; (SS, SP) på egen stak
008d:  push ax
008e:  push ds                 ; gem callers DS
008f:  mov si, dx              ; DX = pointer til parameter-blok
0091:  add si, 0x12
0094:  mov cx, 10
0097:  std
0098:  lodsw                   ; kopier 10 words (intin[0..9]) på stakken
0099:  push ax                 ; (nedad fra [DX+0x12])
009a:  loop 0x98
009c:  push bp
009d:  mov bp, sp
009f:  mov ax, 0               ; <-- CP/M-86 relokering: patches til driver-segment
00a2:  mov ds, ax              ; DS = driver-data-segment
00a4:  cld
00a5:  les di, [bp+2]          ; ES:DI = GSX contrl[]-array (far ptr)
00a8:  mov [es:di+4], 0        ; contrl[2] = nptsout = 0
00ae:  mov [es:di+8], 0        ; contrl[4] = nintout = 0
00b4:  mov bx, [es:di]         ; BX = contrl[0] = GIOS opcode
00b7:  cmp bx, 0x22            ; range-check (0..34)
00ba:  ja 0xc2                 ; out-of-range -> fall through til exit
00bc:  shl bx, 1
00be:  call [bx + 0x100]       ; dispatch via tabel i driverens eget segment
00c2:  pop bp
00c3:  add sp, 0x14            ; drop de 10 intin-words
00c6:  pop ds
00c7:  pop ax
00c8:  pop bx
00c9:  mov ss, bx              ; genskab callers stak
00cb:  mov sp, ax
00cd:  retf                    ; far return
```

Observationer:

1. **CP/M-86 relokering på `MOV AX, 0` ved 0x9F**: imm16 bliver patchet af
   loader til driverens dataseg. Så `[0x100]` i dispatcher-kaldet læser
   fra driverens eget segment, offset 0x100 — dvs. jump-tabellen i filen.
2. **`contrl` layout** (standard GSX): word[0]=opcode, word[1]=n_ptsin,
   word[2]=n_ptsout, word[3]=n_intin, word[4]=n_intout, word[5]=funct_id,
   word[6..]=device-handle. Driveren nulstiller nptsout/nintout op front,
   så enhver handler kan sætte dem hvis den har output.
3. **`intin`-parametre kopieres på stakken** (10 words = 20 bytes) via
   `STD; LODSW; PUSH; LOOP` — klassisk GSX ABI.
4. **Range-check 0x22 = 34**: GSX GIOS har standardfunktioner 1..11 og
   udvidelsesopcodes (set-attributes-subfunctions) der mapper til højere
   interne numre. En range på 35 passer med dette.

## Jump-tabel ved 0x100 (34 slots)

| op | mål     | kommentar                                   |
|---:|--------:|---------------------------------------------|
|  0 | 0x0e89  | handler                                     |
|  1 | 0x03e4  | lille stub (nær "return feature off")       |
|  2 | 0x1689  | handler (deler kode med op 4)               |
|  3 | 0x03e0  | lille stub                                  |
|  4 | 0x1689  | handler (= op 2)                            |
|  5 | 0x03e6  | lille stub                                  |
|  6 | 0x08b8  | handler                                     |
| 7+ | *       | pegerværdier ser ud som kode-bytes (0xd100, 0xd1e0, 0xa3e0…) — tabellen stopper reelt her, selvom dispatcheren accepterer op til 0x22 |

**Mulige hypoteser for "op 7+":**

A. Dispatcher-rangecheck er bare generøs; GSX kalder aldrig med op > 6
   på denne devicetype (fx hvis det er en printer/plotter mode uden tekst).
B. Jeg misforstår dispatcher-opsætningen og tabellen ligger et andet sted;
   `BX+0x100` kunne være i et andet segment end jeg antager.
C. Driveren leverer færre funktioner end andre GSX-devices og "op 7+"-
   slottene er bare uinitialiseret padding genbrugt som kode.

Dette skal afklares med:
- Opslag i GSX programmer manual: hvilke opcodes er obligatoriske for
  en skærmdriver vs. en printer.
- Sammenligning med `dd604h.sys` (Partner skærm) som har kendt opførsel.
- Dynamisk tracing i MAME/emulator.

## Næste skridt (foreslået prioritering)

1. **Læs GSX programmer manual** (`docs/5000-2024_…pdf`) kapitel om
   GIOS interface + funktionsnumre + parameter-formater.
2. **Diff header 0x00–0x7F** på tværs af alle 12 varianter — se hvad der
   adskiller `h` fra `m` fra `hd` osv.
3. **Annoter dispatcher + handlers for ops 0–6** med manuel symbol-navne.
4. **Identificer rc759 I/O-porte** i handler-koden (OUT instruktioner til
   grafikkontrolleren) — det er dét vi faktisk ønsker at forstå.
5. **Byg en symbol-fil** (`dd759h1.sym`) som disasm-scriptet kan læse
   til at påføre navne i output.

Først når ovenstående er på plads, kan vi beslutte om vi vil (a) kommentere
den eksisterende binær færdig, eller (b) reimplementere i asm86 fra bunden.
