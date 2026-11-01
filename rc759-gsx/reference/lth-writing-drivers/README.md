# Historical DRI GIOS skeleton guides

Retrieved 2026-10-31 from the user-supplied
[Lund University archive](https://www.df.lth.se/~pi/compis/cpm-manualer/gsx/writing_drivers/).
Files are retained as downloaded, including original formatting/control bytes.
They are documentation, not new driver sources or build inputs.

| Local file | Document |
|---|---|
| [monmmskc.html](monmmskc.html), [monmmskc.pdf](monmmskc.pdf) | Monochrome Memory Mapped Screen GIOS Skeleton Configuration Guide, CP/M-86 & CCP/M-86, September 17, 1983 |
| [colrskel.html](colrskel.html) | Color Memory Mapped Screen GIOS Skeleton Configuration Guide, CP/M-86 & CCP/M-86, Digital Research, November 9, 1983 |
| [tstsuite.html](tstsuite.html), [tstsuite.pdf](tstsuite.pdf) | GIOS Test Suite Documentation, November 1, 1983 |

Download URLs use the directory above plus the local filename. PDF versions
are retained for the monochrome guide and test suite; the latter references
illustrated expected displays. No test binaries or skeleton A86/OBJ files
were found in the inspected directory or its GSX parent index.

The subsequent search found source packages on Retroarchive, retained in
[`../dri-skeleton/`](../dri-skeleton/README.md).

The CP/M guide names `BWMMSKCP.A86`, `MONOMMRE.A86`, `MONOMMOB.OBJ`,
and `FONT.OBJ` as the skeleton package (`monmmskc.html:85-95`).
The MS-DOS guide at the same site instead names `BWMMSKMS.A86`.
The color guide names `COLMMSK.A86`, `COLMMRE.A86`, `COLMMOB1.OBJ`,
and `FONT.OBJ` (`colrskel.html:120-146`).
These are now verified search targets, not files we already possess.
The archive's 2003 conversion dates are not the documents' publication dates.

| File | SHA-256 |
|---|---|
| colrskel.html | `5015e4150caa0dab9f2b07a8fce4ef1bb4e62972bef4b7dde0b727ff5dbc925d` |
| monmmskc.html | `a586fdccd1406226a8486baf63dc99c7b21a6a91f146c8a16c6d9ba2801b0222` |
| monmmskc.pdf | `b185218e15fc1574dcb02f5eec2c96c2e26c364c0c452794cb965b9b009e1e8d` |
| tstsuite.html | `38eae9ab37253b3936c70a119253e5bf2d7bd4883955196f3d361b6f3c6401e3` |
| tstsuite.pdf | `35b6f768742c9104d4fe9edfc261be1207ee29b6d573311d6181a33b83c08acf` |

See [the H1 comparison and naming map](../../notes/05-dri-skeleton-guides.md).
