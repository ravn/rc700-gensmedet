GSX-86 1.1: Video Drivers
~~~~~~~~~~~~~~~~~~~~~~~~~

  This file contains disassembled source for the GSX 1.1 video drivers, plus
quick and simple ports for four more modern video modes.

  All the drivers in this package (bar DDCSA1) consist of a large chunk of 
common code written in a high-level language (likely RATFOR) followed by 
a reasonably small machine-specific section that handles setting the video 
mode and plotting / unplotting pixels. This can't help performance, though 
on today's fast computers that's less of a concern.

  The original drivers attempt to set the video mode by directly manipulating
the hardware. Consequently they will only work properly on hardware of that
type -- the CGA drivers require a genuine CGA, and won't work correctly on 
EGA-compatible or VGA-compatible hardware.

  DDCSA1 is the odd driver out, because it's written for a NEC 7220 GDC rather 
than a raster framebuffer. It is the only driver in the set that doesn't 
support filled areas.

  Drivers included here are five DRI / GSS originals:

DDCSA1: Computer Systems Artist I, 1024x768, 16 colour.
DDIBM:	CGA 640x200, mono.
DDIBMC:	CGA 320x200, 4 colour.
DDORCH: Orchid Graphics Adapter 720x335, mono.
DDPLUS: Plantronics ColorPlus 640x200, 4 colour.

  Plus four more hastily adapted from the IBM source:

DDMCGA:   MCGA / VGA 320x200, 16 colour. 
DDPSMONO: MCGA / VGA 640x480, mono.
DDVGA:    VGA 640x480, 16 colour.
DDVESA:   VESA 800x600, 16 colour.

(The mode used by DDMCGA is actually a 256-colour mode, but the Digital 
Research GSX test suite crashes if it encounters a 256-colour driver, so 
DDMCGA reports itself as 16-colour).

Although these drivers support arbitrary palettes, vs_color and vq_color have
not been implemented, to avoid cluttering up the original DRI/GSS code.

Support for other video modes (such as VESA 1024x768 or EGA 640x350) would 
be reasonably straightforward, based on this code. 

  The build environment is DOS, using Digital Research's RASM86 and LINKCMD.
