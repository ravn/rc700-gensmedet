# clang flag sweep — AES-256 corpus

Last run: 2026-06-08  
llvm-z80 HEAD: `05d44629e717`

Reproducible via `make sweep` in this directory. Each row is a
clean rebuild + run-to-HALT in `z88dk-ticks` with verification of
the 35-byte result vector at 0xC000. FAIL means at least one of
the three sentinels (enc=01, dec=01, end=a5) was not set.

Baseline is `01_baseline_Oz` (`-Oz` only, no production knobs).

| Config | flags | bin B | Δbin | aes text B | tstates | Δtstates | verify |
|--------|-------|------:|-----:|-----------:|--------:|---------:|:------:|
| `01_baseline_Oz` | -Oz | 2625 |  | 2243 | 18640472 |  | PASS |
| `02_Os` | -Os | 2871 | +246 | 2488 | 18112302 | -2.8% | PASS |
| `03_O3` | -O3 | 8986 | +6361 | 7759 | 18187151 | -2.4% | PASS |
| `04_O2` | -O2 | 5631 | +3006 | 4540 | 18212607 | -2.3% | PASS |
| `05_Oz_static_stack` | -Oz<br>-Xclang -target-feature<br>-Xclang +static-stack | 2625 | +0 | 2243 | 18640472 | +0.0% | PASS |
| `06_Oz_no_licm_cse` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse | 2625 | +0 | 2243 | 18640472 | +0.0% | PASS |
| `07_Oz_no_lsr` | -Oz<br>-mllvm -disable-lsr | 2924 | +299 | 2256 | 18248779 | -2.1% | PASS |
| `08_Oz_gc_sections` | -Oz<br>-ffunction-sections -fdata-sections | 2606 | -19 | 2243 | 18640472 | +0.0% | PASS |
| `09_Oz_prod_like` | -Oz<br>-Xclang -target-feature<br>-Xclang +static-stack<br>-mllvm -disable-lsr<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 2581 | -44 | 2226 | 18214790 | -2.3% | PASS |
| `10_Oz_no_licm_cse_lsr` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-mllvm -disable-lsr | 2924 | +299 | 2256 | 18248779 | -2.1% | PASS |
| `11_Oz_no_licm_cse_gc` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 2606 | -19 | 2243 | 18640472 | +0.0% | PASS |
| `12_Oz_no_omit_fp` | -Oz -fno-omit-frame-pointer | 2632 | +7 | 2250 | 18638836 | -0.0% | PASS |
| `13_Oz_no_omit_fp_no_licm_cse_gc` | -Oz -fno-omit-frame-pointer<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 2613 | -12 | 2250 | 18638836 | -0.0% | PASS |

## Notes on each finding

See `findings.md` for analysis of why each config wins or loses.
