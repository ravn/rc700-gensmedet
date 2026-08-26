---
name: feedback_no_timeout_on_macos
description: macOS has no `timeout(1)`; guard hangable runs (ntvcm) with a perl alarm wrapper
metadata:
  type: feedback
---

The macbook host has **no `timeout(1)`** (GNU coreutils not installed, no brew).
Every `timeout 15 ntvcm ...` line silently fails with "command not found" and the
guard does nothing. The user has flagged this repeatedly — stop reaching for
`timeout`.

**Why:** ntvcm (and other emulators) can hang on exactly the bugs under test
(e.g. issue #22 `fputc` hang). Without a guard, a background Bash job runs
forever and has to be `pkill`ed.

**How to apply:** wrap any potentially-hanging run in a perl alarm exec, which
IS available on macOS:

```sh
perl -e 'alarm shift; exec @ARGV' 15 "$NTVCM" prog.com
```

Exit status 142 (SIGALRM) means it timed out = still hanging. Alternatively use
`z88dk-ticks` which has its own cycle cap. Never run a bare emulator invocation
in a background Bash job without one of these guards.
