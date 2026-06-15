# DRI cpnos source audit — what NDOS / CCP / BDOS actually assume

Date: 2026-05-08
Sources audited: `cpnet-z80/dist/src/{cpndos,ndos,ccp}.asm` (DRI 1980-82
sources, no live upstream).  This file replaces several earlier
"NDOS does X" claims in cpnos-rom comments that turned out to be
guesses based on CP/M-2.2 convention rather than verified by reading
the actual DRI source.

Done because the Path 6.1 SP fix (commit `a18f727`) and follow-up
discussion exposed how often I was claiming behavior I hadn't
checked.  Per HARD RULE `feedback_state_certainty.md` and
`feedback_consult_rules_before_acting.md`, this audit lists
claims by evidence tier.

## 1. Verified directly from cpnet-z80/dist/src/cpndos.asm

### NDOS's stack is INSIDE NDOSRL

`cpndos.asm:90-96` declares 32 words of pre-allocated stack space
(`dw 0c7c7h, ...` x 32) terminated by the `stack:` label.  When NDOS
processes a BDOS call, it switches SP to this region:

```asm
;cpndos.asm:218-219 (inside ndose, BDOS dispatch handler)
shld    ustack          ;save caller SP
lxi     sp,stack        ;switch to NDOS internal stack
```

NDOSRL is at 0xD980..0xDD7F (cpnos.sym: `D980 NDOSRL`).  The `stack:`
label sits inside that region (exact offset depends on RMAC layout
of the cpndos module).  **Stomping NDOSRL stomps NDOS's own stack
words, not just data variables.**  This is what made Path 6's
`LD SP, 0xDD80` so destructive — every push by cpnos-rom during
init/netboot/handoff overwrote bytes NDOS would later use as its
own stack.  Confirms why the symptom (CONOUT(0) flood) was the
generic "control flow lost" mode for stack-corrupted NDOS.

### NDOS COLDST execution order

`cpndos.asm:119-185` is the entire COLDST body.  Verified order:

| Line | Action |
|------|--------|
| 119  | `lxi h, bdosds`                |
| 120-124 | clear 61 bytes at `bdosds` (BDOS Data Segment) |
| 125-132 | copy `tdata1` → `idata1` (init NDOS data from CODE template) |
| 133  | `call nios+0` → SNIOS_NTWKIN (first external call) |
| 134-135 | check A; if non-zero → `coldse` error handler |
| 136-138 | `lhld reboot+1` (read **ZP[1..2]**) → save as `orgbio` |
| 139-159 | walk 17 BIOS-JT slots forward (3 bytes each = 51 B) |
| 160  | `call nios+6` → SNIOS_CNFTBL |
| 161  | `inx h; shld contad`           |
| 162-163 | `lhld bdosa+1` (read **ZP[6..7]**) → `bdose` |
| 164-180 | initialize NDOS internal state, install JP-ndos hook in `ndosrl+6..8` |
| 181-184 | `mvi c, versnf; call bdosa` → BDOS function 12 |
| 185  | `jmp nwboot`                   |

### BIOS-JT walk reads only the JP target bytes

The `colds1` loop at `cpndos.asm:141-158` walks each slot reading
slot+1 and slot+2 (the address bytes of the JP), saving them to
`orgbio`-relative storage and overwriting them with new addresses
from the `tlbios` translation table.  The `0xC3` opcode at slot+0
is preserved.  **NDOS never reads memory below BIOS_BASE through
the JT walk.**  My earlier claim of this is now verified, not
guessed.

### `nwboot` resets SP and loads CCP.SPR

`cpndos.asm:453-487`:

```
nwboot: lxi  sp, 0100h           ;hard SP reset
        lxi  h, ndosa
        shld bdosa+1             ;ZP[5..7] now redirects through NDOS
        lhld orgbio
        shld reboot+1            ;ZP[1..2] restored to original BIOS
        ...
        lxi  d, ccpfcb
        lxi  h, ndosrl
        call load                ;load CCP.SPR via BDOS file I/O
        ora  a
        jz   goccp               ;success → start CCP
        mvi  c, printf
        lxi  d, clderr           ;'CCP.SPR ?$'
        call tobdos
        jmp  $                    ;FATAL: infinite loop
```

If `load` fails (e.g., SNIOS read returns garbage), NDOS prints
"CCP.SPR ?" and infinite-loops — visible on SIO-B mirror.  Since
our SDCC slave DOES NOT show "CCP.SPR ?" in siob.raw, the load
routine isn't returning a clear error — but also isn't reaching
goccp.  That implies the failure is mid-load (control flow lost
before `load`'s `ora a` check).  Consistent with the t=5.3 s
crash transition observed in `probe-results-2026-05-08.md`.

### Zero use of IX, IY, EXX, EX AF

`grep -nE "\b(ix|iy|IX|IY)\b|\bexx\b|ex\s+af" cpnet-z80/dist/src/{cpndos,ndos,ccp}.asm`
returns nothing.  DRI cpnos uses ONLY the 16 main registers.  The
"register-clobber across BIOS call" hypothesis for bug #2 must
therefore involve **A, F, B, C, D, E, H, or L** — not IX/IY/shadow.

The `bios_*_shim` wrappers in `resident.c:405-440` save BC and DE
across the call to `_impl_*`.  AF is not saved (return value
convention).  HL is clobber-OK per CP/M 2.2 standard.  So if a
register is clobbered unexpectedly under SDCC and not under clang,
it's most likely:

  - **HL inside a BIOS-JT call returning a value via HL** (CP/M
    BIOS calls don't return via HL in general, but some BDOS-side
    code may save HL across calls and rely on it surviving)
  - **F (flags) — Z/C/S** — DRI might rely on flag state after a
    BIOS call returning A=0 (for "ok"), and SDCC's compilation
    might leave flags in a different state

This is now the highest-priority hypothesis for bug #2 — not
IX/IY as previously suspected.

## 2. Verified directly from cpnos.sym

Symbols and addresses cpnos.com expects to live at:

| Symbol | Address | Origin |
|--------|---------|--------|
| NDOSRL | 0xD980  | cpnos.com DATA region base (DATA_BASE in cpnos-build) |
| NDOS   | 0xDD80  | cpnos.com CODE region base (CODE_BASE) |
| BDOSDS | 0xDB6A  | BDOS Data Segment (inside NDOSRL) |
| BDOS   | 0xE716  | BDOS dispatch entry (inside cpnos.com CODE) |
| NIOS   | 0xED33  | extern, supplied by cpnos-rom: `_snios_jt` |

All five are read or called at addresses derived from these symbols
in cpnos-build's link.  cpnos-rom must agree on NDOS, BDOSDS, BDOS,
and NIOS values; mismatches break things silently.

## 3. Things I claimed earlier without checking, now corrected

| Claim | Status | Correction |
|-------|--------|------------|
| "NDOS only walks 51 bytes from BIOS-JT-COPY" | TRUE (verified) | OK |
| "NDOS doesn't read memory below BIOS_BASE" | TRUE (verified) | OK |
| "NDOS rewrites slots 1, 2, 3, 4, 5, 15 with NDOS wrappers" | PARTIALLY VERIFIED | The walk visits all 17 slots; which ones get non-zero `tlbios` entries (and hence get rewritten) depends on the `tlbios` table contents — not yet read.  Comment in `resident.c:374-375` claiming "1..5 + 15" is itself unverified and may be wrong. |
| "NDOS sets its own SP at COLDST" | FALSE | NDOS COLDST does NOT set SP at entry.  It runs on the caller's SP (= 0x0100 from `enter_coldst`).  Only `ndose` (BDOS dispatch handler) and `nwboot` (SP=0x0100 reset) explicitly set SP. |
| "BDOS is at NDOS-internal offset" | TRUE | BDOS is inside cpnos.com CODE at 0xE716, called via ZP[5..7]. |
| "NDOSRL is just NDOS variable storage" | INCOMPLETE | NDOSRL contains NDOS's STACK as well as variables.  Was a load-bearing miss for diagnosing Path 6's bug. |
| "Path 6's NDOSRL stomp caused NDOS to read garbage" | TRUE, AND WORSE | NDOS reads garbage AND its `lxi sp, stack` lands on garbage, AND its push/pop interactions go to corrupted bytes.  The bug was deeper than "garbage data". |

## 4. Still unverified (next-session targets if bug #2 chase resumes)

- **`tlbios` translation table contents** (cpndos.asm) — which BIOS-JT
  slots get rewritten with NDOS wrappers; the `1..5 + 15` claim in
  `resident.c` should be verified.
- **`ndose` BDOS dispatch handler full body** (cpndos.asm:226+ in
  ndos.asm, similar pattern in cpndos.asm) — what exactly NDOS does
  on each BDOS call, what register state it expects.
- **`load` routine body** (cpndos.asm:1249+) — the CCP.SPR loader;
  this is where bug #2 likely manifests.
- **CCP entry sequence** (`ccp.asm:476`, `:500`, `:866` set SP=stack) —
  CCP also has its own stack discipline.
- **DRI BDOS source** — not in `cpnet-z80/dist/src/` directly; built
  via cpnos-build's RMAC+LINK from a different location?  Unverified.

## 5. Implications for cpnos-rom design

- **NDOSRL boundary is load-bearing** for SP placement.  This
  invariant must be derived (via `__stack_top = CPNOS_NDOSRL` —
  done in commit `f6ba073`), not chosen by literal.
- **The 51-byte BIOS-JT-COPY at NDOS-0x100 must remain the BIOS-JT-COPY**.
  Anything cpnos-rom writes at 0xDC80..0xDCB2 stomps NDOS's BIOS lookup.
  Currently OK — `resident_handoff` writes exactly these 51 bytes by design.
- **Register preservation across BIOS shims**: `bios_*_shim` saves BC + DE.
  HL/AF clobber-OK by CP/M-2.2 convention.  Bug #2 might involve a
  subtler invariant — flags after specific BIOS calls.
- **No IX/IY worries**: DRI doesn't touch them, so cpnos-rom's
  delete_line / relocate IX usage is irrelevant to the NDOS/CCP path
  (still tracked as code-quality issues #27/#28).

## Methodology note

This audit was triggered by the user pointing out that I'd been
claiming NDOS behavior without grepping the actual source.  The
cpnet-z80 DRI source is in the workspace and freely readable; not
checking it was a process failure, not a tooling limitation.  Per
HARD RULE `feedback_consult_rules_before_acting.md` (saved 2026-05-08),
future bug investigations on cpnos.com behavior MUST start with
direct cpnet-z80/dist/src reads, not with reasoning from CP/M-2.2
conventions.

## Cross-references

- `tasks/probe-results-2026-05-08.md` — runtime behavior trace
- `cpnos-build/d/cpnos.sym` — symbol table (5 symbols, source of
  truth for cpnos.com layout)
- `~/.claude/projects/-Users-ravn-z80/memory/feedback_state_certainty.md`
  — the rule that should have prevented the original guessing
- `~/.claude/projects/-Users-ravn-z80/memory/feedback_consult_rules_before_acting.md`
  — the rule whose violation prompted this audit
