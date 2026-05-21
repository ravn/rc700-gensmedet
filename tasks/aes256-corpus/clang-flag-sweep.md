# clang flag sweep — AES-256 corpus

Last run: 2026-05-21  
llvm-z80 HEAD: `bbcc6f6047c3`

Reproducible via `make sweep` in this directory. Each row is a
clean rebuild + run-to-HALT in `z88dk-ticks` with verification of
the 35-byte result vector at 0xC000. FAIL means at least one of
the three sentinels (enc=01, dec=01, end=a5) was not set.

Baseline is `01_baseline_Oz` (`-Oz` only, no production knobs).

| Config | flags | bin B | Δbin | aes text B | tstates | Δtstates | verify |
|--------|-------|------:|-----:|-----------:|--------:|---------:|:------:|
| `01_baseline_Oz` | -Oz | 4109 |  | 3655 | 15049927 |  | PASS |
| `02_Os` | -Os | 4414 | +305 | 3974 | 14408449 | -4.3% | PASS |
| `03_O3` | -O3 | 12419 | +8310 | 11176 | 13522924 | -10.1% | PASS |
| `04_O2` | -O2 | 8372 | +4263 | 7215 | 13904770 | -7.6% | PASS |
| `05_Oz_static_stack` | -Oz<br>-Xclang -target-feature<br>-Xclang +static-stack | 2830 | -1279 | 2400 | 14604468 | -3.0% | PASS |
| `06_Oz_no_licm_cse` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse | 3790 | -319 | 3386 | 14884274 | -1.1% | PASS |
| `07_Oz_no_lsr` | -Oz<br>-mllvm -disable-lsr | 4328 | +219 | 3564 | 15251381 | +1.3% | PASS |
| `08_Oz_gc_sections` | -Oz<br>-ffunction-sections -fdata-sections | 4089 | -20 | 3655 | 15049927 | +0.0% | PASS |
| `09_Oz_prod_like` | -Oz<br>-Xclang -target-feature<br>-Xclang +static-stack<br>-mllvm -disable-lsr<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 2667 | -1442 | 2307 | 14887472 | -1.1% | PASS |
| `10_Oz_no_licm_cse_lsr` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-mllvm -disable-lsr | 4125 | +16 | 3377 | 15237013 | +1.2% | PASS |
| `11_Oz_no_licm_cse_gc` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 3770 | -339 | 3386 | 14884274 | -1.1% | PASS |
| `12_Oz_no_omit_fp` | -Oz -fno-omit-frame-pointer | 3552 | -557 | 3098 | 14828015 | -1.5% | PASS |
| `13_Oz_no_omit_fp_no_licm_cse_gc` | -Oz -fno-omit-frame-pointer<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 3310 | -799 | 2926 | 14714309 | -2.2% | PASS |

## Notes on each finding

See `findings.md` for analysis of why each config wins or loses.
