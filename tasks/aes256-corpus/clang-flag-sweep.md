# clang flag sweep — AES-256 corpus

Last run: 2026-05-15  
llvm-z80 HEAD: `3d296f439645`

Reproducible via `make sweep` in this directory. Each row is a
clean rebuild + run-to-HALT in `z88dk-ticks` with verification of
the 35-byte result vector at 0xC000. FAIL means at least one of
the three sentinels (enc=01, dec=01, end=a5) was not set.

Baseline is `01_baseline_Oz` (`-Oz` only, no production knobs).

| Config | flags | bin B | Δbin | aes text B | tstates | Δtstates | verify |
|--------|-------|------:|-----:|-----------:|--------:|---------:|:------:|
| `01_baseline_Oz` | -Oz | 4330 |  | 3876 | 65832659 |  | PASS |
| `02_Os` | -Os | 4605 | +275 | 4165 | 65506913 | -0.5% | PASS |
| `03_O3` | -O3 | 12688 | +8358 | 11445 | 65564499 | -0.4% | PASS |
| `04_O2` | -O2 | 8654 | +4324 | 7497 | 65648107 | -0.3% | PASS |
| `05_Oz_static_stack` | -Oz<br>-Xclang -target-feature<br>-Xclang +static-stack | 2911 | -1419 | 2481 | 33491701 | -49.1% | PASS |
| `06_Oz_no_licm_cse` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse | 3867 | -463 | 3463 | 31249853 | -52.5% | PASS |
| `07_Oz_no_lsr` | -Oz<br>-mllvm -disable-lsr | 4696 | +366 | 3932 | 65822097 | -0.0% | PASS |
| `08_Oz_gc_sections` | -Oz<br>-ffunction-sections -fdata-sections | 4310 | -20 | 3876 | 65832659 | +0.0% | PASS |
| `09_Oz_prod_like` | -Oz<br>-Xclang -target-feature<br>-Xclang +static-stack<br>-mllvm -disable-lsr<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 2721 | -1609 | 2361 | 22551771 | -65.7% | PASS |
| `10_Oz_no_licm_cse_lsr` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-mllvm -disable-lsr | 4223 | -107 | 3475 | 31273394 | -52.5% | PASS |
| `11_Oz_no_licm_cse_gc` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 3847 | -483 | 3463 | 31249853 | -52.5% | PASS |
| `12_Oz_no_omit_fp` | -Oz -fno-omit-frame-pointer | 3691 | -639 | 3237 | 41646858 | -36.7% | PASS |
| `13_Oz_no_omit_fp_no_licm_cse_gc` | -Oz -fno-omit-frame-pointer<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 3373 | -957 | 2989 | 25325660 | -61.5% | PASS |

## Notes on each finding

See `findings.md` for analysis of why each config wins or loses.
