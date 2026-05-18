# PPAS-in-SUB needs TCP proxy to pass; direct connection fails

Date: 2026-05-19
Status: open; documented inline in commit 86ab3b8, not blocking.

## Observation

Two MAME wirings, same SNIOS.SPR, same rcbios BIOS (both clang and
SDCC builds verified):

| MAME wiring (PIO-B socket)                  | PPAS-in-SUB result      |
| ------------------------------------------- | ----------------------- |
| `-bitb3 socket.127.0.0.1:4002` (direct mpm) | FAIL: stops at `H>PPAS` |
| `-bitb3 socket.127.0.0.1:4003` (TCP proxy)  | PASS: PolyPascal launches normally |

The TCP proxy (`/tmp/cpnet_tap.py`, a Python relay between :4003 ->
:4002) is just `socket.recv(64)` -> log -> `sendall(data)`.  It
introduces chunk-boundaries and serialises writes through the
proxy's buffering.  No protocol logic.

Same SUB file (`PPAS` is the bottom-up-first record), same workload
(slave loads PPAS.COM from master's A: via H:), same byte stream on
the wire by spec.  Only the TCP delivery characteristic differs.

## Why this matters

The PPAS load over CP/NET is a multi-frame BDOS read chain.  Each
sector read = one CP/NET round-trip = many bytes back and forth.
That the proxy fixes it means MAME's cpnet_bridge byte-timing on
the direct path can deadlock the load — quietly, with no
slave-side error indication.

The same class of timing dependence could surface for *any* heavy
CP/NET workload that follows a SELDSK transition (e.g., post-`H:`
PIP copies, big-file reads, M80 assembly of remote sources).  We
just don't routinely test those, and the polypascal-pio test is
the first workload that triggers it visibly.

## Hypotheses (in priority order)

1. **TCP_NODELAY / Nagle interaction.**  MAME's `bitbanger` writes
   bytes one-at-a-time as the PIO chip strobes them.  Without
   `TCP_NODELAY`, the OS may delay-coalesce, but write timing on
   our localhost socket should be sub-ms.  Worth confirming the
   actual TCP settings.

2. **cpnet_bridge's input() poll cadence vs. mpm-net2's TX cadence.**
   The bridge polls `m_stream->input()` at 1 ms ticks; mpm-net2
   sends in TCP-batch.  When the slave drains the ring fast (rapid
   BDOS reads), the bridge may underflow and signal "no byte" on a
   poll-tick where master has actually sent.  The proxy adds a
   recv(64) buffer that smooths this.

3. **Slave ISR latency under heavy CP/NET load.**  Each post-handoff
   BDOS call does send-frame + recv-frame.  If the ISR gap between
   send and recv lets the master's first response byte arrive
   before the chip is back in INPUT mode (PIO_TO_INPUT pio_b_dir
   transition), the byte is dropped at the chip level.  Test by
   adding a small delay after `transport_pio_send_byte` last-byte
   before `pio_b_set_input` — but this is a slave-side hypothesis
   that contradicts hypothesis 2 (which says it's a bridge issue,
   not a slave issue).

## Reproduction

```sh
cd /Users/ravn/z80/rc700-gensmedet
# Prime test disk WITH PPAS in $$$.SUB (not via injector):
cp ~/Downloads/SW1711-I8.imd /tmp/cpnet_diag.imd
make -C rcbios-in-c bios COMPILER=clang --no-print-directory > /dev/null
python3 rcbios/patch_bios.py /tmp/cpnet_diag.imd rcbios-in-c/clang/bios.clang.cim > /dev/null
FORMAT=rc702-8dd
cpmcp -f $FORMAT /tmp/cpnet_diag.imd cpnet/zout/SNIOS.SPR 0:SNIOS.SPR
for f in ~/git/cpnet-z80/dist/*.com ~/git/cpnet-z80/dist/*.spr; do
    NAME=$(basename "$f" | tr a-z A-Z); cpmcp -f $FORMAT /tmp/cpnet_diag.imd "$f" "0:$NAME"
done
python3 -c "
def rec(c):
    b=c.encode('ascii'); return bytes([len(b)])+b+bytes(127-len(b))
data=rec('PPAS')+rec('H:')+rec('NETWORK H:=A:')+rec('LOGIN PASSWORD')+rec('CPNETLDR')
open('/tmp/sub.tmp','wb').write(data)"
cpmcp -f $FORMAT /tmp/cpnet_diag.imd /tmp/sub.tmp '0:$$$.SUB'

# Direct run (FAIL):
pkill -9 -f cpmsim; sleep 4
cd z80pack/cpmsim && screen -dmS mpm ./mpm-net2 && cd -
sleep 4
perl -e 'alarm 100; exec @ARGV' /Users/ravn/z80/mame/regnecentralend rc702 \
    -rompath /Users/ravn/z80/mame/roms -flop1 /tmp/cpnet_diag.imd \
    -nothrottle -window -skip_gameinfo -seconds_to_run 90 \
    -rs232b null_modem -bitb2 /tmp/siob_direct.raw \
    -piob cpnet_bridge -bitb3 socket.127.0.0.1:4002
# -> tail of siob_direct.raw ends at "H>PPAS"

# Proxy run (PASS):
pkill -9 -f cpmsim; sleep 4
cd z80pack/cpmsim && screen -dmS mpm ./mpm-net2 && cd -
sleep 4
python3 /tmp/cpnet_tap.py &
perl -e 'alarm 100; exec @ARGV' /Users/ravn/z80/mame/regnecentralend rc702 \
    -rompath /Users/ravn/z80/mame/roms -flop1 /tmp/cpnet_diag.imd \
    -nothrottle -window -skip_gameinfo -seconds_to_run 90 \
    -rs232b null_modem -bitb2 /tmp/siob_proxy.raw \
    -piob cpnet_bridge -bitb3 socket.127.0.0.1:4003
# -> tail of siob_proxy.raw shows full PolyPascal session
```

## Next steps (when time permits)

1. **A/B with TCP_NODELAY** on MAME's bitbanger socket (would
   require a MAME-side patch); compare wire byte cadence with/
   without.  Quickest test of hypothesis 1.

2. **Read MAME cpnet_bridge poll_tick and verify the BRDY-gate
   really matches the chip's RDY signal under rapid back-to-back
   send/recv.**  Direct-run wire log should be inspected at
   millisecond resolution around the PPAS-load failure point.

3. **Add a per-frame delay in `try_send_frame` -> `try_recv_frame`
   transition** (slave side, ~1 ms) and see if that lets the
   direct path pass.  If yes, hypothesis 3.  If no, the bug is
   in the bridge.

4. **File at ravn/mame** if conclusively a cpnet_bridge bug; the
   wire-log + proxy-vs-direct comparison is enough evidence to
   open a clear issue.

## Not blocking

The polypascal-PIO test passes today via the injector pattern
(commit `86ab3b8`).  This investigation is to understand the
underlying timing and either fix it at the MAME side or accept
the proxy-required pattern as a known limitation.
