# CP/NET-over-PIO throughput baseline (pre-INIR)

Captured 2026-06-12 from `make cpnos-polypascal-test COMPILER=clang
TRANSPORT=pio-irq` on commit `a9560b4`.  This is the reference number
the planned [#115] INIR busy-poll refactor (issue documented in
`a37f029`, summarised in `transport_pio.c:113-135`) will be compared
against.

## State at measurement

- Transport: ISR-driven 256 B SPSC ring (`pio_rx_buf` +
  `isr_pio_par`) — the path #115 will retire.
- Slave: clang PROM1 line program, 2033 / 2048 B (15 B free).
- Master: `mpm-net2-1.dsk` rebuilt with the FN 105 / gettod
  `SERVER.RSP` patch (see `cpnet/REBUILDING_MPM_SYS.md`).
- Drive seeding: `stage-drivei-ppas` Makefile target writes
  PPAS.COM + PPAS.ERM + PRIMES.PAS onto
  `disks/library/mpm-net2-drivei.dsk` (slave E:).

## Measurements

```
[ 12.02s] E> seen; feeding PPAS<CR>
[ 24.71s] >> seen; feeding L PRIMES<CR>      <-- PPAS load done
[ 26.13s] post-load >> seen; feeding R<CR>   <-- PRIMES.PAS load done
[ 45.51s] 29989 seen; primes output complete
[ 45.53s] post-Run >> seen; feeding Q<CR>
[ 47.33s] PASS: PPAS PRIMES ran to completion (29989 seen) and Q returned to E>
```

| Phase | Bytes | Time | Throughput |
|---|---:|---:|---:|
| PPAS.COM load over CP/NET (slave E:->master I:)  | 28 416 | 12.69 s | ~2 240 B/s |
| PRIMES.PAS load over CP/NET                       |  1 264 |  1.42 s |   ~890 B/s |
| PRIMES execution (PolyPascal interpreter, local CPU) | n/a | 19.38 s | n/a |
| Total wall clock (cold MAME boot → Q → E>)        | — | 47.33 s | — |

PRIMES.PAS throughput is lower than PPAS.COM's because it pays
several fixed-per-frame costs (LOGIN bookkeeping, OPEN, search)
amortised across far fewer payload bytes.  PPAS.COM is the better
single-number baseline for the transport path.

## Expectation after INIR lands

Per the empirical bench in [`session30-pio-driver-and-speed.md`]:

| Path | Throughput |
|---|---:|
| ISR + ring (current)         | 15 KiB/s   (≈ 15 360 B/s on raw bytes) |
| Inline `INIR` busy-poll      | 148 KiB/s  (≈ 151 552 B/s on raw bytes) |
| Wire-bound limit              | ~150 KiB/s |

That measurement is at the raw-byte level (no SNIOS envelope, no ACK
handshake).  Our PPAS load above measures *with* SNIOS framing, which
adds per-frame ENQ/ACK round-trips, HCS/CKS bookkeeping, and a
128-byte SECTOR_LEN ceiling on `MSG[]`.  Realistic expectation when
INIR lands:

- PPAS.COM load: 12.69 s → **~1.3 s** (~10× speedup; matches the
  `~17 ms ring → ~2 ms INIR` projection in `transport_pio.c:135`).
- Total wall clock: 47.33 s → **~35 s** (the 19.38 s PRIMES
  interpreter run is unchanged).
- Per-byte throughput: ~2 240 B/s → **~22 000 B/s**.

If the post-INIR PPAS.COM load is significantly worse than ~1.3 s,
something other than the ring is dominating (suspect first: SNIOS
ENQ/ACK round-trips; the #115 plan also includes byte-blasting whole
frames with sum-to-zero CKS, but that's a separable second step).

## Reproduction

```bash
cd cpnos-in-c
make cpnos-polypascal-test COMPILER=clang TRANSPORT=pio-irq
# tail of stdout has per-stage timestamps
grep -E "^\[ *[0-9]" /tmp/cpnos_polypascal_log.txt
```

Subtract PPAS-feed timestamp from first-`>>` timestamp to get the
PPAS.COM load time.  Subtract first-`>>` from second-`>>` for
PRIMES.PAS load time.

## See also

- `cpnos-in-c/src/transport_pio.c:113-135` — #115 plan, in-code
- `tasks/session30-pio-driver-and-speed.md` — empirical INIR bench
- `tasks/session32-pio-mpm-comparison.md` — proxy vs direct PIO
  comparison (snios-on-PIO got stuck at LOGIN; the abandoned path)
- `docs/cpnet_pio_speed_results.md` — full PIO throughput report
- `cpnos-shared/docs/CPNET_WIRE_PROTOCOL.md` — wire framing the
  SNIOS path is paying for per frame
