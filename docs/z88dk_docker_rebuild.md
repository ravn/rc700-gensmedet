# Rebuilding the z88dk Docker image from local source

All SDCC builds in this project run through a local Docker image tagged
`z88dk:2.4` (the filesystem prebuilt at `rc700-gensmedet/z88dk/` was
**retired 2026-08-10** — see workspace CLAUDE.md). The Makefiles auto-select
Docker whenever no native z88dk with the classic `sdcc_iy/z80.lib` is on disk.

## Obtaining the `z88dk:2.4` image

Two routes produce the `z88dk:2.4` tag the Makefiles expect:

**a) Official Hub image (stock).** Verified byte-identical SDCC codegen to the
retired filesystem prebuilt (same z88dk commit `4d530b6e`):
```bash
docker pull z88dk/z88dk:2.4
docker tag  z88dk/z88dk:2.4 z88dk:2.4
```
Stay pinned to `2.4`: newer official images (`latest`, weekly nightlies) do
**not** ship the linkable `sdcc_iy` target library, so `-clib=sdcc_iy`
silently produces nothing there. Decisive test on `latest`
(v1-5ba9edb1-20260809, verified 2026-08-10) — `zcc +cpm -clib=sdcc_iy` exits
0 **but emits a 0-byte binary**: only `lib/clibs/sdcc_iy/lib/` per-target
source-object dirs exist, no `sdcc_iy/cpm.lib` (contrast `sdcc_ix`, which
ships full `cpm.lib`/`math32.lib`/...). So a green EXIT 0 from `latest` is a
false pass; must use `z88dk/z88dk:2.4`.

**b) Build from the local fork (below)** — needed when zsdcc has a fix in the
local `ravn/z88dk` fork that isn't in the Hub image.

## Command (build from fork)

```bash
cd /Users/ravn/z80/z88dk
docker build -t z88dk:2.4 -f z88dk.Dockerfile .
```

Build time: ~30 minutes on Alpine base.

## To use local changes (not GitHub HEAD)

The default `z88dk.Dockerfile` does `git clone` from GitHub inside the
build. To build from the local checkout with in-progress edits, modify
the Dockerfile to `COPY . /src` (or similar) instead of the `git clone`.
Remember to revert or keep on a branch when done.

## Where

- Local z88dk checkout: `/Users/ravn/z80/z88dk/` (shallow clone of ravn/z88dk)
- Image tag used by all Makefiles in this project: `z88dk:2.4`

## When to rebuild

- After fixing a zsdcc bug in the local fork
- After merging upstream z88dk changes into ravn/z88dk
- If the `sdcc` binary inside the container is crashing on patterns our
  BIOS emits and a workaround exists in the local source
