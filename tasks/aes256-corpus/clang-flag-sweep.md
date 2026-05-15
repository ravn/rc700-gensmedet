# clang flag sweep — AES-256 corpus

Last run: 2026-05-15  
llvm-z80 HEAD: `da1ac7a33181`

Reproducible via `make sweep` in this directory. Each row is a
clean rebuild + run-to-HALT in `z88dk-ticks` with verification of
the 35-byte result vector at 0xC000. FAIL means at least one of
the three sentinels (enc=01, dec=01, end=a5) was not set.

Baseline is `01_baseline_Oz` (`-Oz` only, no production knobs).

| Config | flags | bin B | Δbin | aes text B | tstates | Δtstates | verify |
|--------|-------|------:|-----:|-----------:|--------:|---------:|:------:|
| `01_baseline_Oz` | -Oz | 4111 |  | 3657 | 15704339 |  | PASS |
| `02_Os` | -Os | 4417 | +306 | 3977 | 15397196 | -2.0% | PASS |
| `03_O3` | -O3 | 12472 | +8361 | 11229 | 15529504 | -1.1% | PASS |
| `04_O2` | -O2 | 8411 | +4300 | 7254 | 15588300 | -0.7% | PASS |
| `05_Oz_static_stack` | -Oz<br>-Xclang -target-feature<br>-Xclang +static-stack | 2830 | -1281 | 2400 | 15259192 | -2.8% | PASS |
| `06_Oz_no_licm_cse` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse | 3815 | -296 | 3411 | 15544679 | -1.0% | PASS |
| `07_Oz_no_lsr` | -Oz<br>-mllvm -disable-lsr | 4477 | +366 | 3713 | 15693777 | -0.1% | PASS |
| `08_Oz_gc_sections` | -Oz<br>-ffunction-sections -fdata-sections | 4091 | -20 | 3657 | 15704339 | +0.0% | PASS |
| `09_Oz_prod_like` | -Oz<br>-Xclang -target-feature<br>-Xclang +static-stack<br>-mllvm -disable-lsr<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 2695 | -1416 | 2335 | 15201006 | -3.2% | PASS |
| `10_Oz_no_licm_cse_lsr` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-mllvm -disable-lsr | 4171 | +60 | 3423 | 15568220 | -0.9% | PASS |
| `11_Oz_no_licm_cse_gc` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 3795 | -316 | 3411 | 15544679 | -1.0% | PASS |
| `12_Oz_no_omit_fp` | -Oz -fno-omit-frame-pointer | 3568 | -543 | 3114 | 15487991 | -1.4% | PASS |
| `13_Oz_no_omit_fp_no_licm_cse_gc` | -Oz -fno-omit-frame-pointer<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 3328 | -783 | 2944 | 15374701 | -2.1% | PASS |

## Notes on each finding

See `findings.md` for analysis of why each config wins or loses.
