# sw1_config.mk -- canonical SW1 DIP-switch configuration shared by all RC702
# firmware components (autoload-in-c, rcbios-in-c, cpnos-in-c).
#
# Single source of truth for the SW1 bit assignments documented in
# docs/SW1_BIT_MAP.md.  Each component Makefile sets its own `?=` default and
# then `-include`s this file, so the value defined HERE wins over the local
# default but a command-line override (`make SW1_CONSOLE_BIT=...`) still wins
# over this file.  The chosen value is passed to every C build as
# -DSW1_CONSOLE_BIT so the source uses one named constant instead of a bare
# magic number, keeping the rcbios console switch and the autoload SIO-B debug
# switch provably identical.

# Bit 0 (S01): joined SIO-B console / SIO-B debug output.
#   bit clear (On, default) = enabled;  bit set (Off) = local console only.
# Used by: rcbios-in-c (bios.c console mode), autoload-in-c (rom.c SIO-B debug), cpnos-in-c.
SW1_CONSOLE_BIT = 0x01

# Bit 1 (S02): PROM1 lineprog enable.
#   bit clear (On, default) = check PROM1 sig at 0x2002 and boot;  bit set (Off) = skip and halt.
# Used by: autoload-in-c (rom.c prom1_if_present).
SW1_LINEPROG_BIT = 0x02

# Bit 2 (S03): CP/NET transport selection.
#   bit clear (On, default) = PIO transport;  bit set (Off) = SIO transport.
# Used by: cpnos-in-c (init.c, xport_jt.c), cpnet/snios.asm.
SW1_TRANSPORT_BIT = 0x04

# Bits 3-6 (S04-S07): reserved / unused switches.
SW1_RESERVED_S04_BIT = 0x08
SW1_RESERVED_S05_BIT = 0x10
SW1_RESERVED_S06_BIT = 0x20
SW1_RESERVED_S07_BIT = 0x40

# Bit 7 (S08): Floppy drive size (original RC702 hardware specification).
#   bit clear (On, default) = 8" maxi (500 kbps);  bit set (Off) = 5.25" mini (250 kbps).
# Used by: autoload-in-c (rom.c), rcbios-in-c (bios.c motor control).
SW1_FLOPPY_MINI_BIT = 0x80

