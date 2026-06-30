# clang flag sweep — AES-256 corpus

Last run: 2026-06-28  
llvm-z80 HEAD: `d2c8eac68245`

Reproducible via `make sweep` in this directory. Each row is a
clean rebuild + run-to-HALT in `z88dk-ticks` with verification of
the 35-byte result vector at 0xC000. FAIL means at least one of
the three sentinels (enc=01, dec=01, end=a5) was not set.

Baseline is `01_baseline_Oz` (`-Oz` only, no production knobs).

| Config | flags | bin B | Δbin | aes text B | tstates | Δtstates | verify |
|--------|-------|------:|-----:|-----------:|--------:|---------:|:------:|
| `01_baseline_Oz` | -Oz | 2635 |  | 2253 | 17023254 |  | PASS |
| `02_Os` | -Os | 2832 | +197 | 2449 | 16454599 | -3.3% | PASS |
| `03_O3` | -O3 | 8885 | +6250 | 7658 | 16430309 | -3.5% | PASS |
| `04_O2` | -O2 | 5577 | +2942 | 4486 | 16468568 | -3.3% | PASS |
| `05_Oz_static_stack` | -Oz<br>-Xclang -target-feature<br>-Xclang +static-stack | 2635 | +0 | 2253 | 17023254 | +0.0% | PASS |
| `06_Oz_no_licm_cse` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse | 2621 | -14 | 2239 | 18639120 | +9.5% | PASS |
| `07_Oz_no_lsr` | -Oz<br>-mllvm -disable-lsr | 2927 | +292 | 2264 | 16603817 | -2.5% | PASS |
| `08_Oz_gc_sections` | -Oz<br>-ffunction-sections -fdata-sections | 2616 | -19 | 2253 | 17023254 | +0.0% | PASS |
| `09_Oz_prod_like` | -Oz<br>-Xclang -target-feature<br>-Xclang +static-stack<br>-mllvm -disable-lsr<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 2579 | -56 | 2222 | 18213004 | +7.0% | PASS |
| `10_Oz_no_licm_cse_lsr` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-mllvm -disable-lsr | 2915 | +280 | 2252 | 18246355 | +7.2% | PASS |
| `11_Oz_no_licm_cse_gc` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 2602 | -33 | 2239 | 18639120 | +9.5% | PASS |
| `12_Oz_no_omit_fp` | -Oz -fno-omit-frame-pointer | 2634 | -1 | 2252 | 17020134 | -0.0% | PASS |
| `13_Oz_no_omit_fp_no_licm_cse_gc` | -Oz -fno-omit-frame-pointer<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 2601 | -34 | 2238 | 18636000 | +9.5% | PASS |

## Notes on each finding

See `findings.md` for analysis of why each config wins or loses.
