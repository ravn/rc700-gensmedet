# zsdcc flag sweep — AES-256 corpus (ANSI variant)

Last run: 2026-05-20  
z88dk HEAD: `ef747c325e6b`

Reproducible via `make sweep_sdcc` in this directory. Each row is a
clean rebuild + run-to-HALT in `z88dk-ticks` with verification of
the 35-byte result vector at 0xC000.

Baseline (`01_baseline_prod`) = current production cpnos-rom flags.

| Config | flags | bin B | Δbin | aes text B | tstates | Δtstates | verify |
|--------|-------|------:|-----:|-----------:|--------:|---------:|:------:|
| `01_baseline_prod` | -clib=sdcc_iy<br>--opt-code-size<br>-SO3<br>-Cs"--sdcccall 1"<br>-Cs"--disable-warning 296"<br>-Cs"--max-allocs-per-node 25000"<br>-Cs"--fomit-frame-pointer" | 3323 | — | 2680 | 12080289 | — | PASS |
| `02_sdcccall_0` | -clib=sdcc_iy<br>--opt-code-size<br>-SO3<br>-Cs"--max-allocs-per-node 25000"<br>-Cs"--fomit-frame-pointer" | 3682 | +359 | 3011 | 14189740 | +17.5% | PASS |
| `03_sdcccall_1` | -clib=sdcc_iy<br>--opt-code-size<br>-SO3<br>-Cs"--sdcccall 1"<br>-Cs"--disable-warning 296"<br>-Cs"--max-allocs-per-node 25000"<br>-Cs"--fomit-frame-pointer" | 3323 | +0 | 2680 | 12080289 | +0.0% | PASS |
| `04_opt_speed` | -clib=sdcc_iy<br>-SO3<br>-Cs"--sdcccall 1"<br>-Cs"--disable-warning 296"<br>-Cs"--opt-code-speed"<br>-Cs"--max-allocs-per-node 25000"<br>-Cs"--fomit-frame-pointer" | 3335 | +12 | 2700 | 12076406 | -0.0% | PASS |
| `05_SO0` | -clib=sdcc_iy<br>--opt-code-size<br>-SO0<br>-Cs"--sdcccall 1"<br>-Cs"--disable-warning 296"<br>-Cs"--max-allocs-per-node 25000"<br>-Cs"--fomit-frame-pointer" | 3566 | +243 | 2904 | 13526073 | +12.0% | PASS |
| `06_SO2` | -clib=sdcc_iy<br>--opt-code-size<br>-SO2<br>-Cs"--sdcccall 1"<br>-Cs"--disable-warning 296"<br>-Cs"--max-allocs-per-node 25000"<br>-Cs"--fomit-frame-pointer" | 3428 | +105 | 2783 | 12096057 | +0.1% | PASS |
| `07_no_peep` | -clib=sdcc_iy<br>--opt-code-size<br>-SO3<br>-Cs"--sdcccall 1"<br>-Cs"--disable-warning 296"<br>-Cs"--max-allocs-per-node 25000"<br>-Cs"--fomit-frame-pointer"<br>-Cs"--no-peep" | 3323 | +0 | 2680 | 12080289 | +0.0% | PASS |
| `08_nogcse` | -clib=sdcc_iy<br>--opt-code-size<br>-SO3<br>-Cs"--sdcccall 1"<br>-Cs"--disable-warning 296"<br>-Cs"--max-allocs-per-node 25000"<br>-Cs"--fomit-frame-pointer"<br>-Cs"--nogcse" | 3368 | +45 | 2680 | 12083890 | +0.0% | PASS |
| `09_clib_ix` | -clib=sdcc_ix<br>--opt-code-size<br>-SO3<br>-Cs"--sdcccall 1"<br>-Cs"--disable-warning 296"<br>-Cs"--max-allocs-per-node 25000"<br>-Cs"--fomit-frame-pointer" | 4579 | +1256 | 3949 | 12324109 | +2.0% | PASS |
| `10_max_allocs_1000` | -clib=sdcc_iy<br>--opt-code-size<br>-SO3<br>-Cs"--sdcccall 1"<br>-Cs"--disable-warning 296"<br>-Cs"--max-allocs-per-node 1000"<br>-Cs"--fomit-frame-pointer" | 3633 | +310 | 2975 | 13804251 | +14.3% | PASS |
| `11_max_allocs_100000` | -clib=sdcc_iy<br>--opt-code-size<br>-SO3<br>-Cs"--sdcccall 1"<br>-Cs"--disable-warning 296"<br>-Cs"--max-allocs-per-node 100000"<br>-Cs"--fomit-frame-pointer" | 3330 | +7 | 2687 | 12080523 | +0.0% | PASS |
| `12_keep_frame_ptr` | -clib=sdcc_iy<br>--opt-code-size<br>-SO3<br>-Cs"--sdcccall 1"<br>-Cs"--disable-warning 296"<br>-Cs"--max-allocs-per-node 25000" | 3323 | +0 | 2680 | 12080289 | +0.0% | PASS |
| `13_all_callee_saves` | -clib=sdcc_iy<br>--opt-code-size<br>-SO3<br>-Cs"--sdcccall 1"<br>-Cs"--disable-warning 296"<br>-Cs"--max-allocs-per-node 25000"<br>-Cs"--fomit-frame-pointer"<br>-Cs"--all-callee-saves" | 3323 | +0 | 2680 | 12080289 | +0.0% | PASS |
