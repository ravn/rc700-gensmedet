# Parallel port as high-throughput host link — REJECTED

> **REJECTED 2026-04-25.** This investigation plan targeted PIO
> Channel A (J4) with the `KBDPORT=B` keyboard relocation. Both
> assumptions are dead:
>
> - PIO-A / J4 cannot carry the host link in production (2026-04-25
>   keyboard-on-J4 constraint).
> - `KBDPORT=B` is retired — keyboard stays on PIO-A.
> - The Linux-PC-with-LPT host approach is replaced by Pi 4B + Pi
>   Pico over USB-CDC.
>
> Current design lives in
> [`../../docs/cpnet_fast_link.md`](../../docs/cpnet_fast_link.md)
> (Option P, PIO-B half-duplex via J3). The motivation, hardware
> sketch, and follow-up investigation list that used to live here
> are preserved in git history (latest: `97cc565^`).
