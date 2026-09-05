# i80186 internal DMA + a fast source-synchronised FDC: how should this be modelled?

A neutral problem statement for experienced MAME developers. It states observed
behaviour and experiment outcomes only; it does **not** assert a root cause or a
preferred fix.

## Symptom (observed)

On drivers that use the i80186's **internal** DMA to service a floppy controller
(WD/uPD family) in a **source-synchronised** transfer, the FDC completes the read
with its **LOST DATA** status bit set (WD2797 status 0x04), and the guest OS then
fails to load programs from disk.

## Where the transfer is serviced today (code references, no interpretation)

- `i186.h`: `drq0_w`/`drq1_w` only latch the request:
  `void drq0_w(int state) { m_dma[0].drq_state = state; }`
- `i186.cpp` `execute_run()` (approx. lines 200-228): DMA is performed at the top
  of the CPU loop, one byte per loop iteration, gated on `!m_dma_latency`;
  the serviced channel does `m_icount--` before `drq_callback()`.
- `i186.cpp` (approx. lines 2041-2073): `m_dma_latency = 8` is set on DMA
  register writes. An existing comment (approx. lines 204-207) notes that `mpc60`
  runs a continuous RAM→RAM transfer on channel 0 and relies on this latency so a
  transfer does not fire between an IRQ handler's two address-register writes.

## Concrete reproduction

- Machine: `rc759` (regnecentralen), on a fork bringing the driver up.
- `I80186(config, m_maincpu, 6'000'000)`; `WD2797(config, m_fdc, 2'000'000)`;
  `m_fdc->drq_wr_callback().set(maincpu, drq0_w)`; transfer is source-synchronised
  on channel 0. Disk format: 5.25" DSHD MFM, 8 sectors/track, 1024 B/sector.
- With stock `drq0_w`, post-boot program loads fail and the WD2797 read carries
  LOST DATA.

## Experiments and outcomes (data)

| Change applied | Observed outcome |
|---|---|
| none (stock `drq0_w`) | LOST DATA set; guest program load fails |
| `config.set_perfect_quantum(m_maincpu)` in the driver | no change; byte-for-byte identical failure |
| `drq0_w` calls `drq_callback(0)` inline when the channel is started + source/dest-synchronised + `m_dma_latency == 0` | reads succeed; guest boots. Reverting **only** this change reproduces the exact failure (A/B). |

Neutral observations about the inline-service experiment:
- It does **not** decrement `m_icount` (the `execute_run` path does, ~line 220).
- It calls `drq_callback()` from the FDC's line-write callback context. An existing
  helper `dma_sync_req()` (`i186.h`) does the same and is commented "This a hack,
  only use if there are sync problems with another cpu".

## Scope: this is the shared i80186 core

`drq0_w`/`drq1_w` are in the shared `i80186_cpu_device` (~53 i80186/i80188
machines). Survey of i80186 + FDC drivers by DMA channel and status:

| Channel + source | Machines | Status |
|---|---|---|
| drq0 + FDC | lb186, slicer, compis (iSBX) | working |
| drq1 + FDC | digilog320, ngen, pcd, mpc60, yes, pwrview | all `MACHINE_NOT_WORKING` |
| drq1 + non-FDC | leland_a (PIT/audio), mikromikko2 (MPSC/serial), compis (iSBX) | working |

## Question for MAME developers

What is the accepted way to model **prompt servicing of a source-synchronised
i80186 internal DMA transfer**, such that it is:
1. general (applies to both channels / all affected machines, not one driver),
2. compatible with the existing `m_dma_latency` behaviour that `mpc60` relies on,
3. correct with respect to stolen bus cycles (`m_icount`) and the call context?

Is servicing on the DREQ line the right approach, or should prompt servicing be
achieved elsewhere (execute_run scheduling, quantum, bus arbitration, or another
mechanism)? Pointers to a driver/core that already does this correctly would help.
