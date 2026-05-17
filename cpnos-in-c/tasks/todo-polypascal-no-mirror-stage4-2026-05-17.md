# polypascal-test-no-mirror: stage 4 ">>" detection fails

**Status:** TODO -- experiment partially complete; primary
polypascal-test (MIRROR_SIOB=1) is fine.

## Symptom

`make cpnos-polypascal-test-no-mirror` runs a MIRROR_SIOB=0 build
through `cpnos-shared/mame/polypascal_test_no_mirror.lua` which polls
the slave's 25x80 display RAM at 0xF800 instead of /tmp/cpnos_siob.raw
for stage markers.  Reaches "29989 seen; primes output complete" at
~48 s (similar to MIRROR_SIOB=1 baseline of ~50 s), then FAILs at
stage 4: "timeout waiting for post-Run PPAS >>".

## Cause

The lua uses edge-triggered `pp_now > pp_baseline` detection because
absolute ">>" counts collapse to 0..1 during PRIMES output (thousands
of lines scroll the screen, erasing earlier ">>" prompts).  Stage 3
re-baselines pp_baseline = pp_now after seeing "29989", expecting
stage 4 to trip when a new ">>" appears.

Hypothesis: the post-Run ">>" prompt either:
  a) Appears on the same screen frame as the last prime, so pp_now
     was already 1 when stage 3 transitioned and pp_baseline = 1; then
     stage 4 waits for pp_now > 1 which never happens.
  b) Scrolls off-screen between frame polls (50 Hz polling, slow
     PPAS prompt rendering); the polling window misses the
     transient prompt.

Likely (a) -- PRIMES likely prints "29989\n>>" in quick succession
before the slave hits idle.

## Fix attempt

Option 1: stage 4 just looks for `pp_now >= 1` instead of `> baseline`
since by stage 4 we know primes is done and any ">>" must be the
post-Run one.

Option 2: after seeing "29989", wait N frames (~1 s) before
re-baselining, so the post-Run ">>" has a chance to land.

Option 3: capture writes to 0xF800 region via memory tap (instead of
polling) -- append every byte to a chronological buffer like the
SIO-B raw does.  More work, equivalent to MIRROR_SIOB but slave-side
zero-cost.

## Cost class

Small.  Half-hour iteration loop.  Not blocking primary polypascal-
test (MIRROR_SIOB=1 path PASSes).

## Why pursued at all

The no-mirror variant tests the hypothesis "is MIRROR_SIOB the
bottleneck on PRIMES execution time?"  Measurement so far:
  * MIRROR_SIOB=1: 29989 seen at 48.49 s after MAME start
  * MIRROR_SIOB=0: 29989 seen at 47.95 s after MAME start
Difference: -0.54 s (~1.1% faster).  Smaller than expected -- the
SIO-B busy-wait dominates only at low baud rates; at MAME's
no-throttle speed the wait is short.

So the answer to the user's question is: removing MIRROR_SIOB does
NOT significantly speed up the test.  The stage 4 bug doesn't affect
that measurement.  Fixing the bug is just hygiene for a future
no-mirror test path.
