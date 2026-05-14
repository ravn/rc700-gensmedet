# zsdcc flag sweep — AES-256 corpus

Last run: 2026-05-14  
z88dk HEAD: `a7031ad3c864`

Reproducible via `make sweep_sdcc` in this directory. Each row is a
clean rebuild + run-to-HALT in `z88dk-ticks` with verification of
the 35-byte result vector at 0xC000.

Baseline (`01_baseline_prod`) = current production cpnos-rom flags.

| Config | flags | bin B | Δbin | aes text B | tstates | Δtstates | verify |
|--------|-------|------:|-----:|-----------:|--------:|---------:|:------:|
| `01_baseline_prod` | -clib=sdcc_iy<br>--opt-code-size<br>-SO3<br>-Cs"--sdcccall 1"<br>-Cs"--disable-warning 296"<br>-Cs"--max-allocs-per-node 25000"<br>-Cs"--fomit-frame-pointer" | 3604 | — | 2961 | 14185104 | — | PASS |
| `02_sdcccall_0` | -clib=sdcc_iy<br>--opt-code-size<br>-SO3<br>-Cs"--max-allocs-per-node 25000"<br>-Cs"--fomit-frame-pointer" | 3682 | +78 | 3011 | 14189740 | +0.0% | PASS |
| `03_sdcccall_1` | -clib=sdcc_iy<br>--opt-code-size<br>-SO3<br>-Cs"--sdcccall 1"<br>-Cs"--disable-warning 296"<br>-Cs"--max-allocs-per-node 25000"<br>-Cs"--fomit-frame-pointer" | 3604 | +0 | 2961 | 14185104 | +0.0% | PASS |
| `04_opt_speed` | -clib=sdcc_iy<br>-SO3<br>-Cs"--sdcccall 1"<br>-Cs"--disable-warning 296"<br>-Cs"--opt-code-speed"<br>-Cs"--max-allocs-per-node 25000"<br>-Cs"--fomit-frame-pointer" | 3685 | +81 | 3050 | 14008310 | -1.2% | PASS |
| `05_SO0` | -clib=sdcc_iy<br>--opt-code-size<br>-SO0<br>-Cs"--sdcccall 1"<br>-Cs"--disable-warning 296"<br>-Cs"--max-allocs-per-node 25000"<br>-Cs"--fomit-frame-pointer" | 3802 | +198 | 3140 | 15370797 | +8.4% | PASS |
| `06_SO2` | -clib=sdcc_iy<br>--opt-code-size<br>-SO2<br>-Cs"--sdcccall 1"<br>-Cs"--disable-warning 296"<br>-Cs"--max-allocs-per-node 25000"<br>-Cs"--fomit-frame-pointer" | 3651 | +47 | 3006 | 14207875 | +0.2% | PASS |
| `07_no_peep` | -clib=sdcc_iy<br>--opt-code-size<br>-SO3<br>-Cs"--sdcccall 1"<br>-Cs"--disable-warning 296"<br>-Cs"--max-allocs-per-node 25000"<br>-Cs"--fomit-frame-pointer"<br>-Cs"--no-peep" | 3604 | +0 | 2961 | 14185104 | +0.0% | PASS |
| `08_nogcse` | -clib=sdcc_iy<br>--opt-code-size<br>-SO3<br>-Cs"--sdcccall 1"<br>-Cs"--disable-warning 296"<br>-Cs"--max-allocs-per-node 25000"<br>-Cs"--fomit-frame-pointer"<br>-Cs"--nogcse" | 3711 | +107 | 3023 | 14196433 | +0.1% | FAIL |
| `09_clib_ix` | -clib=sdcc_ix<br>--opt-code-size<br>-SO3<br>-Cs"--sdcccall 1"<br>-Cs"--disable-warning 296"<br>-Cs"--max-allocs-per-node 25000"<br>-Cs"--fomit-frame-pointer" | 4793 | +1189 | 4163 | 31895119 | +124.8% | FAIL |
| `10_max_allocs_1000` | -clib=sdcc_iy<br>--opt-code-size<br>-SO3<br>-Cs"--sdcccall 1"<br>-Cs"--disable-warning 296"<br>-Cs"--max-allocs-per-node 1000"<br>-Cs"--fomit-frame-pointer" | 3758 | +154 | 3100 | 14229105 | +0.3% | PASS |
| `11_max_allocs_100000` | -clib=sdcc_iy<br>--opt-code-size<br>-SO3<br>-Cs"--sdcccall 1"<br>-Cs"--disable-warning 296"<br>-Cs"--max-allocs-per-node 100000"<br>-Cs"--fomit-frame-pointer" | 3589 | -15 | 2946 | 14178600 | -0.0% | PASS |
| `12_keep_frame_ptr` | -clib=sdcc_iy<br>--opt-code-size<br>-SO3<br>-Cs"--sdcccall 1"<br>-Cs"--disable-warning 296"<br>-Cs"--max-allocs-per-node 25000" | 3604 | +0 | 2961 | 14185104 | +0.0% | PASS |
| `13_all_callee_saves` | -clib=sdcc_iy<br>--opt-code-size<br>-SO3<br>-Cs"--sdcccall 1"<br>-Cs"--disable-warning 296"<br>-Cs"--max-allocs-per-node 25000"<br>-Cs"--fomit-frame-pointer"<br>-Cs"--all-callee-saves" | 3604 | +0 | 2961 | 14185104 | +0.0% | PASS |
