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
# Used by: rcbios-in-c (bios.c console mode), autoload-in-c (rom.c SIO-B debug).
SW1_CONSOLE_BIT = 0x01
