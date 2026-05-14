# clang flag sweep — AES-256 corpus

Last run: 2026-05-14  
llvm-z80 HEAD: `6fdfe4817f8e`

Reproducible via `make sweep` in this directory. Each row is a
clean rebuild + run-to-HALT in `z88dk-ticks` with verification of
the 35-byte result vector at 0xC000. FAIL means at least one of
the three sentinels (enc=01, dec=01, end=a5) was not set.

Baseline is `01_baseline_Oz` (`-Oz` only, no production knobs).

| Config | flags | bin B | Δbin | aes text B | tstates | Δtstates | verify |
|--------|-------|------:|-----:|-----------:|--------:|---------:|:------:|
| `01_baseline_Oz` | -Oz | 4450 |  | 3996 | 65979155 |  | PASS |
| `02_Os` | -Os | 4725 | +275 | 4285 | 65653409 | -0.5% | PASS |
| `03_O3` | -O3 | 12688 | +8238 | 11445 | 65564499 | -0.6% | PASS |
| `04_O2` | -O2 | 8654 | +4204 | 7497 | 65648107 | -0.5% | PASS |
| `05_Oz_static_stack` | -Oz<br>-Xclang -target-feature<br>-Xclang +static-stack | 2991 | -1459 | 2561 | 100000003 | +51.6% | FAIL |
| `06_Oz_no_licm_cse` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse | 3988 | -462 | 3584 | 31403069 | -52.4% | PASS |
| `07_Oz_no_lsr` | -Oz<br>-mllvm -disable-lsr | 4816 | +366 | 4052 | 65968593 | -0.0% | PASS |
| `08_Oz_gc_sections` | -Oz<br>-ffunction-sections -fdata-sections | 4430 | -20 | 3996 | 65979155 | +0.0% | PASS |
| `09_Oz_prod_like` | -Oz<br>-Xclang -target-feature<br>-Xclang +static-stack<br>-mllvm -disable-lsr<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 2802 | -1648 | 2442 | 58131 | -99.9% | FAIL |
| `10_Oz_no_licm_cse_lsr` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-mllvm -disable-lsr | 4344 | -106 | 3596 | 31426610 | -52.4% | PASS |
| `11_Oz_no_licm_cse_gc` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 3968 | -482 | 3584 | 31403069 | -52.4% | PASS |

## Notes on each finding

See `findings.md` for analysis of why each config wins or loses.
