# clang flag sweep — AES-256 corpus

Last run: 2026-06-22  
llvm-z80 HEAD: `91c5607ad292`

Reproducible via `make sweep` in this directory. Each row is a
clean rebuild + run-to-HALT in `z88dk-ticks` with verification of
the 35-byte result vector at 0xC000. FAIL means at least one of
the three sentinels (enc=01, dec=01, end=a5) was not set.

Baseline is `01_baseline_Oz` (`-Oz` only, no production knobs).

| Config | flags | bin B | Δbin | aes text B | tstates | Δtstates | verify |
|--------|-------|------:|-----:|-----------:|--------:|---------:|:------:|
| `01_baseline_Oz` | -Oz | 2639 |  | 2257 | 17024606 |  | PASS |
| `02_Os` | -Os | 2834 | +195 | 2451 | 16454607 | -3.3% | PASS |
| `03_O3` | -O3 | 8887 | +6248 | 7660 | 16430317 | -3.5% | PASS |
| `04_O2` | -O2 | 5579 | +2940 | 4488 | 16468576 | -3.3% | PASS |
| `05_Oz_static_stack` | -Oz<br>-Xclang -target-feature<br>-Xclang +static-stack | 2639 | +0 | 2257 | 17024606 | +0.0% | PASS |
| `06_Oz_no_licm_cse` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse | 2625 | -14 | 2243 | 18640472 | +9.5% | PASS |
| `07_Oz_no_lsr` | -Oz<br>-mllvm -disable-lsr | 2936 | +297 | 2268 | 16606241 | -2.5% | PASS |
| `08_Oz_gc_sections` | -Oz<br>-ffunction-sections -fdata-sections | 2620 | -19 | 2257 | 17024606 | +0.0% | PASS |
| `09_Oz_prod_like` | -Oz<br>-Xclang -target-feature<br>-Xclang +static-stack<br>-mllvm -disable-lsr<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 2583 | -56 | 2226 | 18214356 | +7.0% | PASS |
| `10_Oz_no_licm_cse_lsr` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-mllvm -disable-lsr | 2924 | +285 | 2256 | 18248779 | +7.2% | PASS |
| `11_Oz_no_licm_cse_gc` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 2606 | -33 | 2243 | 18640472 | +9.5% | PASS |
| `12_Oz_no_omit_fp` | -Oz -fno-omit-frame-pointer | 2638 | -1 | 2256 | 17021486 | -0.0% | PASS |
| `13_Oz_no_omit_fp_no_licm_cse_gc` | -Oz -fno-omit-frame-pointer<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 2605 | -34 | 2242 | 18637352 | +9.5% | PASS |

## Notes on each finding

See `findings.md` for analysis of why each config wins or loses.
