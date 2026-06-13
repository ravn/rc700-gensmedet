# INIR refactor instrumentation probe — GDB-stub variant.
#
# Watchpoints only.  An earlier version also set function breakpoints
# at isr_pio_par / transport_pio_recv_byte / snios_rcvmsg_c, but GDB
# software breakpoints patch the target code byte with RST 0x08
# (0xCF), and that patch is lost when cpnos's PROM1 decompresses its
# payload INTO the resident region at boot — the patched byte gets
# overwritten by the real code byte, and the breakpoints become dead
# AND the saved-original gets corrupted.  GDB then emits "Program
# received signal SIGTRAP" at a `?? ()` location when execution
# wanders into a now-meaningless leftover patch.  Hardware breakpoints
# would avoid this but MAME's stub doesn't expose CPU-side execution
# breakpoints.
#
# Watchpoints (the `watch` family) are MAME-emulated by intercepting
# every memory access; they survive memory writes, so the head/tail
# watchpoints remain live across cpnos load and into PPAS RX.
#
# Output: /trace/cpnos_inir_trace.log (mounted host path).

set arch z80
set pagination off
set print address off
set confirm off

file /elf/payload.elf

target remote host.docker.internal:23946

# Filter out spurious SIGTRAPs.  MAME's gdbstub signals the initial
# halt via SIGTRAP, and possibly more during execution; `pass` would
# make GDB try to forward the signal to the inferior but MAME's stub
# doesn't accept signals ("Can't send signals to this remote
# system.").  `nopass` makes GDB absorb the signal cleanly and
# continue without bothering the stub.
handle SIGTRAP nostop noprint nopass

set logging file /trace/cpnos_inir_trace.log
set logging overwrite on
set logging redirect on
set logging enabled on

printf "# inir_gdb trace start\n"
printf "# pio_rx_head=%p pio_rx_tail=%p\n", &pio_rx_head, &pio_rx_tail
printf "# isr_pio_par=%p transport_pio_recv_byte=%p\n", \
       isr_pio_par, transport_pio_recv_byte
printf "# snios_rcvmsg_c=%p\n", snios_rcvmsg_c

# pio_rx_head writes — fired by isr_pio_par every time the ISR pushes
# a received byte.  $pc at that moment is the body of isr_pio_par.
watch *(unsigned char *)&pio_rx_head
commands
  silent
  printf "HEAD %02x by PC=%04x tail=%02x\n", \
         *(unsigned char *)&pio_rx_head, $pc, \
         *(unsigned char *)&pio_rx_tail
  continue
end

# pio_rx_tail writes — fired by transport_pio_recv_byte every time
# the mainline pops a byte from the ring.
watch *(unsigned char *)&pio_rx_tail
commands
  silent
  printf "TAIL %02x by PC=%04x head=%02x\n", \
         *(unsigned char *)&pio_rx_tail, $pc, \
         *(unsigned char *)&pio_rx_head
  continue
end

printf "# watchpoints armed, continuing\n"
continue

# When MAME exits, the remote disconnects.  Fall through.
printf "# inir_gdb trace end\n"
set logging enabled off
quit
