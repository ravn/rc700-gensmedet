# clang flag sweep — AES-256 corpus

Last run: 2026-05-15  
llvm-z80 HEAD: `a6a7edf02b8d`

Reproducible via `make sweep` in this directory. Each row is a
clean rebuild + run-to-HALT in `z88dk-ticks` with verification of
the 35-byte result vector at 0xC000. FAIL means at least one of
the three sentinels (enc=01, dec=01, end=a5) was not set.

Baseline is `01_baseline_Oz` (`-Oz` only, no production knobs).

| Config | flags | bin B | Δbin | aes text B | tstates | Δtstates | verify |
|--------|-------|------:|-----:|-----------:|--------:|---------:|:------:|
| `01_baseline_Oz` | -Oz | 4205 |  | 3751 | 15742481 |  | PASS |
| `02_Os` | -Os | 4480 | +275 | 4040 | 15416735 | -2.1% | PASS |
| `03_O3` | -O3 | 12559 | +8354 | 11316 | 15536121 | -1.3% | PASS |
| `04_O2` | -O2 | 8529 | +4324 | 7372 | 15611713 | -0.8% | PASS |
| `05_Oz_static_stack` | -Oz<br>-Xclang -target-feature<br>-Xclang +static-stack | 2855 | -1350 | 2425 | 15265068 | -3.0% | PASS |
| `06_Oz_no_licm_cse` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse | 3815 | -390 | 3411 | 15544679 | -1.3% | PASS |
| `07_Oz_no_lsr` | -Oz<br>-mllvm -disable-lsr | 4571 | +366 | 3807 | 15731919 | -0.1% | PASS |
| `08_Oz_gc_sections` | -Oz<br>-ffunction-sections -fdata-sections | 4185 | -20 | 3751 | 15742481 | +0.0% | PASS |
| `09_Oz_prod_like` | -Oz<br>-Xclang -target-feature<br>-Xclang +static-stack<br>-mllvm -disable-lsr<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 2695 | -1510 | 2335 | 15201006 | -3.4% | PASS |
| `10_Oz_no_licm_cse_lsr` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-mllvm -disable-lsr | 4171 | -34 | 3423 | 15568220 | -1.1% | PASS |
| `11_Oz_no_licm_cse_gc` | -Oz<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 3795 | -410 | 3411 | 15544679 | -1.3% | PASS |
| `12_Oz_no_omit_fp` | -Oz -fno-omit-frame-pointer | 3606 | -599 | 3152 | 15501043 | -1.5% | PASS |
| `13_Oz_no_omit_fp_no_licm_cse_gc` | -Oz -fno-omit-frame-pointer<br>-mllvm -disable-machine-licm<br>-mllvm -disable-machine-cse<br>-ffunction-sections -fdata-sections | 3328 | -877 | 2944 | 15374701 | -2.3% | PASS |

## Notes on each finding

See `findings.md` for analysis of why each config wins or loses.
