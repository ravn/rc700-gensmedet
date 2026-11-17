# Plan: Bring SDCC CP/NOS PROM under 2 KB PROM-grænsen

**Dato**: 2026-11-17  
**Mål**: Gøre `make prom1-lineprog COMPILER=sdcc` i stand til at bygge en valid 2 KB EPROM-binær (`prom1-lineprog.bin` <= 2048 bytes) med automatisk hard build-gate (svarende til Clang), opdatere build-systemet fra 4 KB MAME-padding til 2 KB production cap, og verificere med MAME + MP/M PolyPascal integrationstest.

---

## 1. Målinger & Nuværende Status

### Historisk baseline (Maj 2026) vs. Måling (17. nov 2026)

| Komponent | Maj 2026 (dokumenteret) | Måling 17. nov 2026 (native z88dk) | Delta | Grænse (PROM 1) |
| :--- | :--- | :--- | :--- | :--- |
| `init_code.bin` (rå) | 689 B | **562 B** | −127 B | Decompresses til RAM 0xC000 |
| `init.zx0` (komprimeret) | 585 B | **486 B** | −99 B | I PROM1 |
| `payload.bin` (rå resident) | 2.192 B | **1.944 B** | −248 B | Decompresses til RAM 0xED00 |
| `payload.zx0` (komprimeret) | 1.559 B | **1.389 B** | −170 B | I PROM1 |
| Bootstrap + header + dzx0 | ~102 B | **102 B** | 0 B | I PROM1 |
| **Samlet rå PROM1 binær** | **2.246 B** (+198 B over cap) | **1.977 B** (71 B fri) | **−269 B** | **2.048 B hard cap** |

### Vigtig opdagelse
Med native `z88dk` v4.6.0 og nyere opdateringer er SDCC's rå binære størrelse (`sdcc/cpnos_lp_LINEPROG_HEADER.bin`) **allerede faldet til 1.977 bytes**, hvilket er **71 bytes under den fysiske 2.048 bytes grænse**.

Årsagen til, at SDCC stadig blev anset for at være 4 KB, var:
1. `cpnos-in-c/Makefile` linje 182 søgte kun efter z88dk's ældre lib-sti (`libsrc/_DEVELOPMENT/lib/sdcc_iy/z80.lib`), hvilket fejlagtigt triggede et fallback til Docker.
2. `cpnos-in-c/Makefile` linje 2279 hardcodede `PAD=4096;` som en rest fra maj 2026, hvor SDCC fyldte 2.246 B.
3. `src/init.c` indeholdt en gcc/clang-specifik `register void *hl __asm__("hl")` inline assembly-konstruktion ved IVT-initialisering, som fejlede under zsdcc.

---

## 2. Handlingsplan

```
[Fase 1: Standardiser Makefile til 2 KB cap & ret z88dk-detektion]
                             ↓
[Fase 2: Ret init.c til dual-compiler kompatibilitet]
                             ↓
[Fase 3: Indfør hard 2048 B size-gate i Makefile for SDCC]
                             ↓
[Fase 4: Tilføj __preserves_regs for ekstra margin (headroom)]
                             ↓
[Fase 5: Kør cpnos-polypascal-test COMPILER=sdcc & verificer end-to-end]
                             ↓
[Fase 6: Opdater dokumentation i sdcc-prom1lineprog/README.md og timeline]
```

### Fase 1: Standardiser Makefile
- Ret `SDCC_LIB` i `cpnos-in-c/Makefile` til at detektere både `lib/clibs/sdcc_ix/z80.lib` og udviklingsstien.
- Skift `PAD=4096` til `PAD=2048` i `prom1-lineprog` reglen for SDCC.
- Indfør `HARD=2048` og tjek `$$SZ -gt $$HARD` så overskridelse fejler bygget øjeblikkeligt.
- Opdater `help` målet i `Makefile` fra `[4 KB, MAME-only]` til `[2 KB cap]`.

### Fase 2: Dual-compiler kompatibilitet i `init.c`
- Bevar Clang's ldir-loop under `#ifdef __clang__`.
- Under `#else` (SDCC): Anvend den bærbare C-løkke (`for (uint8_t n = IVT_ENTRIES; n; --n)`), som ZSDCC kompilerer til en kompakt 18-byte tæller-løkke.

### Fase 3: Øg sikkerhedsmarginen med `__preserves_regs`
- Tilføj `__preserves_regs` (2-linjers format med `#ifdef __SDCC`) på ofte kaldte interne hjælpefunktioner i `cpnos-in-c`:
  - `console_putc`
  - `pio_b_set_output` / `pio_b_set_input`
  - `transport_pio_send_byte`
- Forventet gevinst: 20–40 bytes ukomprimeret / 10–20 bytes post-ZX0, hvilket øger headroom fra 71 bytes til ~85–90 bytes fri plads.

### Fase 4: End-to-end verifikation
- Kør `make prom1-lineprog COMPILER=sdcc`: Bekræft at output er nøjagtig 2.048 bytes (padded) med >= 71 bytes fri plads.
- Kør `make cpnos-polypascal-test COMPILER=sdcc`: Bekræft at MAME booter mod MP/M master, viser `E>`, kører PolyPascal PRIMES til 29989 og returnerer fejlfrit til prompten.

### Fase 5: Dokumentation
- Opdater `sdcc-prom1lineprog/README.md` med de nye tal og bekræftelsen af 2 KB support.
- Tilføj sektion i `tasks/timeline.md`.
