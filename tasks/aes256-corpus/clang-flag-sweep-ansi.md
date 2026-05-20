# clang flag sweep — AES-256 corpus (ANSI variant)

Last run: 2026-05-20  
llvm-z80 HEAD: `0cf4034d8635`

Reproducible via `make sweep` in this directory. Each row is a
clean rebuild + run-to-HALT in `z88dk-ticks` with verification of
the 35-byte result vector at 0xC000. FAIL means at least one of
the three sentinels (enc=01, dec=01, end=a5) was not set.

Baseline is `01_baseline_Oz` (`-Oz` only, no production knobs).

| Config | flags | bin B | Δbin | aes text B | tstates | Δtstates | verify |
|--------|-------|------:|-----:|-----------:|--------:|---------:|:------:|
| `01_baseline_Oz` | -Oz | 4047 |  | 3593 | 16021371 |  | PASS |
| `02_Os` | -Os | 4462 | +415 | 4022 | 15385588 | -4.0% | PASS |
| `03_O3` | -O3 | 12190 | +8143 | 10947 | 15347966 | -4.2% | PASS |
| `04_O2` | -O2 | 8129 | +4082 | 6972 | 15406762 | -3.8% | PASS |
| `05_Oz_static_stack` | -Oz<br>-Xclang -target-feature<br>-Xclang +static-stack | 2766 | -1281 | 2336 | 15576224 | -2.8% | PASS |
| `06_Oz_no_licm_cse` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse | 3745 | -302 | 3341 | 15849619 | -1.1% | PASS |
| `07_Oz_no_lsr` | -Oz<br>-mllvm -disable-lsr | 4413 | +366 | 3649 | 16010809 | -0.1% | PASS |
| `08_Oz_gc_sections` | -Oz<br>-ffunction-sections -fdata-sections | 4034 | -13 | 3593 | 16021371 | +0.0% | PASS |
| `09_Oz_prod_like` | -Oz<br>-Xclang -target-feature<br>-Xclang +static-stack<br>-mllvm -disable-lsr<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 2636 | -1411 | 2269 | 15515354 | -3.2% | PASS |
| `10_Oz_no_licm_cse_lsr` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-mllvm -disable-lsr | 4105 | +58 | 3357 | 15882568 | -0.9% | PASS |
| `11_Oz_no_licm_cse_gc` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 3732 | -315 | 3341 | 15849619 | -1.1% | PASS |
| `12_Oz_no_omit_fp` | -Oz -fno-omit-frame-pointer | 3504 | -543 | 3050 | 15805023 | -1.4% | PASS |
| `13_Oz_no_omit_fp_no_licm_cse_gc` | -Oz -fno-omit-frame-pointer<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 3269 | -778 | 2878 | 15689049 | -2.1% | PASS |

## Notes on each finding

See `findings.md` for analysis of why each config wins or loses.
