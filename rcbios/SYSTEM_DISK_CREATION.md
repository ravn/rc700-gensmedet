# RC700 system disk — oprettelse fra blank z88dk-billede

z88dk-appmake kan generere blanke RC700-systemdisketter med korrekt
CP/M-mappestruktur og reserverede boot-spor (0xe5-fyldte):

```
z88dk-appmake +cpmdisk -f rc700-5dd --container=imd -b prog.com -o disk.imd
z88dk-appmake +cpmdisk -f rc700-8dd --container=imd -b prog.com -o disk.imd
z88dk-appmake +cpmdisk -f rc700-8sd --container=imd -b prog.com -o disk.imd
z88dk-appmake +cpmdisk -f rc703-qd  --container=imd -b prog.com -o disk.imd
```

Det reserverede boot-område er tomt. Herunder beskrives hvad der mangler
per format.

---

## 8" DS/DD (rc700-8dd) og RC703 QD (rc703-qd)

Disse formater har **ensartet MFM** på alle spor, så z88dk-billedet er
geometrisk korrekt. Boot-sporene (spor 0–1) skal blot have CCP+BDOS
installeret.

**Metode A — SYSGEN i MAME** (kræver en kørende kilde-diskette):

```
# Boot fra eksisterende systemdiskette i MAME
# Indsæt den blanke diskette i drev B:
A> SYSGEN
Source drive: A
Destination drive: B
```

**Metode B — patch_bios.py** (anbefalet, scriptbart):

```bash
# Byg BIOS-binary
cd rcbios && make rel23-maxi      # 8" maxi

# Stamp BIOS+CCP+BDOS ind på sporet (patch_bios.py håndterer track-layout)
python3 rcbios/patch_bios.py source_system.imd zout/BIOS.cim -o blank.imd

# Tilføj filer med cpmtools
cpmcp -f rc702-8dd blank.imd myprog.com 0:MYPROG.COM
```

---

## 5.25" DS/DD mini (rc700-5dd)

**Spor 0 på en RC700 mini-systemdiskette har mixed-density format:**

- Side 0: 16 sektorer × 128 B **FM** (single density) — autoload boot-kode
- Side 1: 16 sektorer × 256 B **MFM** (double density) — CCP-start

z88dk skriver spor 0 som uniform 9×512 B MFM (ligesom alle andre spor).
Det er geometrisk forkert for boot-sporet og autoload-PROM'en vil ikke
kunne boote fra det.

**Nødvendig efterbehandling:**

```bash
# Trin 1: Generer blank disk med korrekt directory-område
z88dk-appmake +cpmdisk -f rc700-5dd --container=imd -b prog.com -o blank.imd

# Trin 2: Erstat spor 0 med det mixed-density boot-indhold
# (bin2imd.py genererer korrekt FM/MFM-struktur fra raw boot-binary)
python3 rcbios/bin2imd.py raw_system.bin temp_track0.imd

# Trin 3: Transplant spor 0 fra temp_track0.imd ind i blank.imd
# (ingen færdig tool endnu — se TODO nedenfor)
```

**TODO:** Skriv `imd_replace_track0.py` der tager spor 0+1 fra ét IMD
og spor 2+ fra et andet og samler dem til ét gyldigt mini-systemdisk-IMD.
Inputtet til spor 0 er den raw boot-binary genereret af `autoload-in-c/`
via `make clang` eller `make rom_parts`.

---

## 8" SS/SD (rc700-8sd) — IBM 3740-kompatibel

Boot-sporerne (spor 0–1) er FM-formaterede 26×128B sektorer, samme
geometri som resten af disken. z88dk-billedet er derfor geometrisk
korrekt, og SYSGEN kan installere CCP+BDOS direkte.

```
A> SYSGEN
Source drive: A   (kilde: eksisterende 8" SS/SD systemdiskette)
Destination drive: B
```

---

## Diskdefs til cpmtools

Alle fire formater er defineret i `rcbios/diskdefs`:

```
cpmls -f rc702-5dd disk.imd        # liste filer
cpmcp -f rc702-8dd disk.imd fil 0:FIL.COM   # kopier fil ind
```
