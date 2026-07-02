# RcComal80 v2.0 (SW1727/I5, Bits:30009625)

RC702 RcComal80 **v2.0** distribution, extracted from the bootable CP/M system
disk [Bits:30009625](https://datamuseum.dk/bits/30009625) (IMD; boots
`RC700 56k CP/M vers.2.2 rel.2.1`, then `COMAL80.COM` = "RcComal80 rev. 2.0").

- `COMAL80.COM`   — the RcComal80 **v2.0** interpreter (runs under CP/M; has
  graphics keywords, e.g. `CIRCLE`).  Newer than the education disk's `rev 1.07`.
- `COMALCNV.COM`  — **format converter**: *"Comal80 til CP/M konvertering"*,
  converts between the **Comal80-native disk format** (the non-standard pseudo-CP/M
  filesystem on the education disk Bits:30003268) and **CP/M format**.  This is the
  key to reading/using the education disk's programs under v2.0.
- `PIP.COM`       — CP/M file-copy utility.
- `COMAL80.ERM`, `GENERRM.CSV` — error-message resources.

This is the external-procedure-capable line the education disk's `.PRG` apps
(RACE/FUTTOG/TEGNGEN) target — see `../../docs/RC702_COMAL_SEM702_CHARSETS.md`.
