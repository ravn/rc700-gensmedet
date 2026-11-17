---
name: feedback_mame_screenshot_from_mp4
description: How to reliably extract a usable screenshot from a MAME mame_capture.sh recording of the RC702
metadata:
  type: feedback
---

Use `scripts/mame_capture.sh` WITHOUT `-nothrottle` (realtime speed) so the AVI captures all frames.
Then extract all 50fps frames from the first second of the MP4 with Docker ffmpeg, and pick
the frame with the highest pixel variance (most visual content):

```bash
# 1. Capture at realtime
MAME_CAPTURE=1 scripts/mame_capture.sh <slug> -- rc702 -rompath /Users/ravn/z80/mame/roms \
  -rom1 <prom.ic66> -window -skip_gameinfo -seconds_to_run 10 -sound none

# 2. Extract first-second frames at 50fps
MP4=scratch/mame-videos/<timestamp>_<slug>.mp4
docker run --rm -v /tmp:/tmp -v "$(dirname $MP4):/src" jrottenberg/ffmpeg:7-alpine \
  -i /src/$(basename $MP4) -t 1 -vf fps=50 /tmp/sec1_%03d.png

# 3. Pick highest-variance frame (most structure = screen content)
python3 -c "
import numpy as np; from PIL import Image
scores = [(np.array(Image.open(f'/tmp/sec1_{i:03d}.png'),dtype=float).var(), i) for i in range(1,51)]
print(sorted(scores)[-1])
"
```

**Why:** With nothrottle (>300% speed), MAME drops AVI frames → 14 total for 8 simulated seconds.
The QR/banner content only appears for a brief moment in real time.
With throttle (realtime), all 50 display frames per second are captured.
The autoload QR appears very early (within the first second) because boot with no floppy is fast.

**Why not `screen:snapshot()`:** The Lua `screen:snapshot()` captures at a point where the
8275 display hasn't rendered the frame yet — produces a near-black 1305-byte PNG.

**How to apply:** Any time you need a screenshot of the autoload PROM QR/banner screen.
