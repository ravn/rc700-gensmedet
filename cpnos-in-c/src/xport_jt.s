; cpnos-rom transport dispatch jump table
;
; SNIOS calls _xport_send_byte / _xport_recv_byte (snios.s).  In the
; legacy single-transport builds the SNIOS references are linker-
; aliased via --defsym to the chosen transport's implementation
; (see TRANSPORT_DEFSYMS in the Makefile).
;
; In the dual-transport PROM1-only build, these symbols are instead
; provided here as 3-byte `jp NN` trampolines whose NN target address
; is patched at cold-init by install_transport() in init.c based on
; SW1 bit 2 (S03):
;
;   bit 2 clear (MAME On, default) -> PIO transport
;   bit 2 set   (MAME Off)         -> SIO transport
;
; Defaults at link time point at the PIO transport so a pre-patch
; access (shouldn't happen) lands somewhere defined.  The trampolines
; preserve all Z80 registers (JP NN has no side effects), matching the
; PRESERVES_REGS_CLANG calling convention the existing transport
; bodies advertise.
;
; The references to _transport_sio_send_byte / _transport_sio_recv_byte
; from init.c's install_transport() are what keeps both transport.o
; files alive under --gc-sections.

; NOT in .resident.jumptable -- the linker script places that section
; first and asserts _snios_jt == 0xED33 (bios_jt + 0x33 = end of the
; 17-entry BIOS table).  Putting the xport JT here too would push
; snios_jt 6 bytes later and trip the ASSERT.  Use plain .resident
; instead, which lands after the SNIOS sections.
    .section .resident, "ax"
    .global _xport_send_byte
    .global _xport_recv_byte

_xport_send_byte:   jp _transport_pio_send_byte
_xport_recv_byte:   jp _transport_pio_recv_byte
