/* Minimum-effort glue for size measurement only.
   Real implementation would talk to SIO ch A. */

int
getDebugChar (void)
{
  /* Blocking read from SIO ch A data port (0x09 on RC700). */
  unsigned char c;
  __asm
    in a, (0x09)
    ld c, a
  __endasm;
  return c;
}

void
putDebugChar (int ch)
{
  /* Blocking write to SIO ch A data port. */
  (void)ch;
  __asm
    ld a, l
    out (0x09), a
  __endasm;
}
