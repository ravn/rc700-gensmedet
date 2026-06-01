# clang flag sweep — AES-256 corpus

Last run: 2026-05-31  
llvm-z80 HEAD: `82c062a9df0d`

Reproducible via `make sweep` in this directory. Each row is a
clean rebuild + run-to-HALT in `z88dk-ticks` with verification of
the 35-byte result vector at 0xC000. FAIL means at least one of
the three sentinels (enc=01, dec=01, end=a5) was not set.

Baseline is `01_baseline_Oz` (`-Oz` only, no production knobs).

| Config | flags | bin B | Δbin | aes text B | tstates | Δtstates | verify |
|--------|-------|------:|-----:|-----------:|--------:|---------:|:------:|
| `01_baseline_Oz` | -Oz | 2599 |  | 2217 | 11149008 |  | PASS |
| `02_Os` | -Os | 2845 | +246 | 2462 | 10620838 | -4.7% | PASS |
| `03_O3` | -O3 | 8960 | +6361 | 7733 | 10695687 | -4.1% | PASS |
| `04_O2` | -O2 | 5605 | +3006 | 4514 | 10721143 | -3.8% | PASS |
| `05_Oz_static_stack` | -Oz<br>-Xclang -target-feature<br>-Xclang +static-stack | 2599 | +0 | 2217 | 11149008 | +0.0% | PASS |
| `06_Oz_no_licm_cse` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse | 2599 | +0 | 2217 | 11149008 | +0.0% | PASS |
| `07_Oz_no_lsr` | -Oz<br>-mllvm -disable-lsr | 2898 | +299 | 2230 | 10757315 | -3.5% | PASS |
| `08_Oz_gc_sections` | -Oz<br>-ffunction-sections -fdata-sections | 2580 | -19 | 2217 | 11149008 | +0.0% | PASS |
| `09_Oz_prod_like` | -Oz<br>-Xclang -target-feature<br>-Xclang +static-stack<br>-mllvm -disable-lsr<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 2555 | -44 | 2200 | 10723326 | -3.8% | PASS |
| `10_Oz_no_licm_cse_lsr` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-mllvm -disable-lsr | 2898 | +299 | 2230 | 10757315 | -3.5% | PASS |
| `11_Oz_no_licm_cse_gc` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 2580 | -19 | 2217 | 11149008 | +0.0% | PASS |
| `12_Oz_no_omit_fp` | -Oz -fno-omit-frame-pointer | 2606 | +7 | 2224 | 11147372 | -0.0% | PASS |
| `13_Oz_no_omit_fp_no_licm_cse_gc` | -Oz -fno-omit-frame-pointer<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 2587 | -12 | 2224 | 11147372 | -0.0% | PASS |

## Notes on each finding

See `findings.md` for analysis of why each config wins or loses.
