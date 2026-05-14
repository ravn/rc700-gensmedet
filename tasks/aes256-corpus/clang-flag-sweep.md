# clang flag sweep — AES-256 corpus

Last run: 2026-05-14  
llvm-z80 HEAD: `0dd6f9e47330`

Reproducible via `make sweep` in this directory. Each row is a
clean rebuild + run-to-HALT in `z88dk-ticks` with verification of
the 35-byte result vector at 0xC000. FAIL means at least one of
the three sentinels (enc=01, dec=01, end=a5) was not set.

Baseline is `01_baseline_Oz` (`-Oz` only, no production knobs).

| Config | flags | bin B | Δbin | aes text B | tstates | Δtstates | verify |
|--------|-------|------:|-----:|-----------:|--------:|---------:|:------:|
| `01_baseline_Oz` | -Oz | 5114 |  | 4660 | 66121724 |  | PASS |
| `02_Os` | -Os | 5375 | +261 | 4935 | 65789933 | -0.5% | PASS |
| `03_O3` | -O3 | 15212 | +10098 | 13969 | 65711280 | -0.6% | PASS |
| `04_O2` | -O2 | 9956 | +4842 | 8799 | 65791270 | -0.5% | PASS |
| `05_Oz_static_stack` | -Oz<br>-Xclang -target-feature<br>-Xclang +static-stack | 3355 | -1759 | 2925 | 100000003 | +51.2% | FAIL |
| `06_Oz_no_licm_cse` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse | 4733 | -381 | 4329 | 31575735 | -52.2% | PASS |
| `07_Oz_no_lsr` | -Oz<br>-mllvm -disable-lsr | 5480 | +366 | 4716 | 66111162 | -0.0% | PASS |
| `08_Oz_gc_sections` | -Oz<br>-ffunction-sections -fdata-sections | 5063 | -51 | 4660 | 66121724 | +0.0% | PASS |
| `09_Oz_prod_like` | -Oz<br>-Xclang -target-feature<br>-Xclang +static-stack<br>-mllvm -disable-lsr<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 3156 | -1958 | 2808 | 58127 | -99.9% | FAIL |
| `10_Oz_no_licm_cse_lsr` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-mllvm -disable-lsr | 5089 | -25 | 4341 | 31599276 | -52.2% | PASS |
| `11_Oz_no_licm_cse_gc` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 4682 | -432 | 4329 | 31575735 | -52.2% | PASS |

## Notes on each finding

See `findings.md` for analysis of why each config wins or loses.
