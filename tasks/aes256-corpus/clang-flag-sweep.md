# clang flag sweep — AES-256 corpus

Last run: 2026-06-07  
llvm-z80 HEAD: `05d44629e717`

Reproducible via `make sweep` in this directory. Each row is a
clean rebuild + run-to-HALT in `z88dk-ticks` with verification of
the 35-byte result vector at 0xC000. FAIL means at least one of
the three sentinels (enc=01, dec=01, end=a5) was not set.

Baseline is `01_baseline_Oz` (`-Oz` only, no production knobs).

| Config | flags | bin B | Δbin | aes text B | tstates | Δtstates | verify |
|--------|-------|------:|-----:|-----------:|--------:|---------:|:------:|
| `01_baseline_Oz` | -Oz | 2910 |  | 2528 | 18707176 |  | PASS |
| `02_Os` | -Os | 3089 | +179 | 2706 | 18167690 | -2.9% | PASS |
| `03_O3` | -O3 | 9704 | +6794 | 8477 | 18233713 | -2.5% | PASS |
| `04_O2` | -O2 | 6077 | +3167 | 4986 | 18267582 | -2.3% | PASS |
| `05_Oz_static_stack` | -Oz<br>-Xclang -target-feature<br>-Xclang +static-stack | 2910 | +0 | 2528 | 18707176 | +0.0% | PASS |
| `06_Oz_no_licm_cse` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse | 2910 | +0 | 2528 | 18707176 | +0.0% | PASS |
| `07_Oz_no_lsr` | -Oz<br>-mllvm -disable-lsr | 3209 | +299 | 2541 | 18315483 | -2.1% | PASS |
| `08_Oz_gc_sections` | -Oz<br>-ffunction-sections -fdata-sections | 2891 | -19 | 2528 | 18707176 | +0.0% | PASS |
| `09_Oz_prod_like` | -Oz<br>-Xclang -target-feature<br>-Xclang +static-stack<br>-mllvm -disable-lsr<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 2866 | -44 | 2511 | 18281494 | -2.3% | PASS |
| `10_Oz_no_licm_cse_lsr` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-mllvm -disable-lsr | 3209 | +299 | 2541 | 18315483 | -2.1% | PASS |
| `11_Oz_no_licm_cse_gc` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 2891 | -19 | 2528 | 18707176 | +0.0% | PASS |
| `12_Oz_no_omit_fp` | -Oz -fno-omit-frame-pointer | 2871 | -39 | 2489 | 18696920 | -0.1% | PASS |
| `13_Oz_no_omit_fp_no_licm_cse_gc` | -Oz -fno-omit-frame-pointer<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 2852 | -58 | 2489 | 18696920 | -0.1% | PASS |

## Notes on each finding

See `findings.md` for analysis of why each config wins or loses.
