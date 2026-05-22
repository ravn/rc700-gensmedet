# clang flag sweep — AES-256 corpus

Last run: 2026-05-22  
llvm-z80 HEAD: `a0a3777fb6b7`

Reproducible via `make sweep` in this directory. Each row is a
clean rebuild + run-to-HALT in `z88dk-ticks` with verification of
the 35-byte result vector at 0xC000. FAIL means at least one of
the three sentinels (enc=01, dec=01, end=a5) was not set.

Baseline is `01_baseline_Oz` (`-Oz` only, no production knobs).

| Config | flags | bin B | Δbin | aes text B | tstates | Δtstates | verify |
|--------|-------|------:|-----:|-----------:|--------:|---------:|:------:|
| `01_baseline_Oz` | -Oz | 3703 |  | 3299 | 11502249 |  | PASS |
| `02_Os` | -Os | 4200 | +497 | 3783 | 11027332 | -4.1% | PASS |
| `03_O3` | -O3 | 12057 | +8354 | 10814 | 11018101 | -4.2% | PASS |
| `04_O2` | -O2 | 8032 | +4329 | 6927 | 11057461 | -3.9% | PASS |
| `05_Oz_static_stack` | -Oz<br>-Xclang -target-feature<br>-Xclang +static-stack | 2630 | -1073 | 2250 | 11165884 | -2.9% | PASS |
| `06_Oz_no_licm_cse` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse | 3703 | +0 | 3299 | 11502249 | +0.0% | PASS |
| `07_Oz_no_lsr` | -Oz<br>-mllvm -disable-lsr | 4036 | +333 | 3288 | 11095056 | -3.5% | PASS |
| `08_Oz_gc_sections` | -Oz<br>-ffunction-sections -fdata-sections | 3683 | -20 | 3299 | 11502249 | +0.0% | PASS |
| `09_Oz_prod_like` | -Oz<br>-Xclang -target-feature<br>-Xclang +static-stack<br>-mllvm -disable-lsr<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 2562 | -1141 | 2204 | 10737538 | -6.6% | PASS |
| `10_Oz_no_licm_cse_lsr` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-mllvm -disable-lsr | 4036 | +333 | 3288 | 11095056 | -3.5% | PASS |
| `11_Oz_no_licm_cse_gc` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 3683 | -20 | 3299 | 11502249 | +0.0% | PASS |
| `12_Oz_no_omit_fp` | -Oz -fno-omit-frame-pointer | 3244 | -459 | 2840 | 11337419 | -1.4% | PASS |
| `13_Oz_no_omit_fp_no_licm_cse_gc` | -Oz -fno-omit-frame-pointer<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 3224 | -479 | 2840 | 11337419 | -1.4% | PASS |

## Notes on each finding

See `findings.md` for analysis of why each config wins or loses.
