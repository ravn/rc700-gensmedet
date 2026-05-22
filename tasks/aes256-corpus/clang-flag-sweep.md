# clang flag sweep — AES-256 corpus

Last run: 2026-05-22  
llvm-z80 HEAD: `126148e82358`

Reproducible via `make sweep` in this directory. Each row is a
clean rebuild + run-to-HALT in `z88dk-ticks` with verification of
the 35-byte result vector at 0xC000. FAIL means at least one of
the three sentinels (enc=01, dec=01, end=a5) was not set.

Baseline is `01_baseline_Oz` (`-Oz` only, no production knobs).

| Config | flags | bin B | Δbin | aes text B | tstates | Δtstates | verify |
|--------|-------|------:|-----:|-----------:|--------:|---------:|:------:|
| `01_baseline_Oz` | -Oz | 3710 |  | 3231 | 11478681 |  | PASS |
| `02_Os` | -Os | 3975 | +265 | 3606 | 28 | -100.0% | PASS |
| `03_O3` | -O3 | 12057 | +8347 | 10814 | 11018101 | -4.0% | PASS |
| `04_O2` | -O2 | 8096 | +4386 | 6853 | 28 | -100.0% | PASS |
| `05_Oz_static_stack` | -Oz<br>-Xclang -target-feature<br>-Xclang +static-stack | 2686 | -1024 | 2231 | 11167389 | -2.7% | PASS |
| `06_Oz_no_licm_cse` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse | 3710 | +0 | 3231 | 11478681 | +0.0% | PASS |
| `07_Oz_no_lsr` | -Oz<br>-mllvm -disable-lsr | 3674 | -36 | 3251 | 11047170 | -3.8% | PASS |
| `08_Oz_gc_sections` | -Oz<br>-ffunction-sections -fdata-sections | 3690 | -20 | 3231 | 11478681 | +0.0% | PASS |
| `09_Oz_prod_like` | -Oz<br>-Xclang -target-feature<br>-Xclang +static-stack<br>-mllvm -disable-lsr<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 2606 | -1104 | 2223 | 10747561 | -6.4% | PASS |
| `10_Oz_no_licm_cse_lsr` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-mllvm -disable-lsr | 3674 | -36 | 3251 | 11047170 | -3.8% | PASS |
| `11_Oz_no_licm_cse_gc` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 3690 | -20 | 3231 | 11478681 | +0.0% | PASS |
| `12_Oz_no_omit_fp` | -Oz -fno-omit-frame-pointer | 3254 | -456 | 2775 | 11309729 | -1.5% | PASS |
| `13_Oz_no_omit_fp_no_licm_cse_gc` | -Oz -fno-omit-frame-pointer<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 3234 | -476 | 2775 | 11309729 | -1.5% | PASS |

## Notes on each finding

See `findings.md` for analysis of why each config wins or loses.
