/* Smallest possible caller — just references the stub entry points
   to force them into the link. */
extern void debug_swbreak(void);
extern void debug_nmi(void);
extern void debug_int(void);
extern void debug_exception(int);

void
__main(void)
{
  /* prevent DCE of the stub entry points */
  debug_swbreak();
  debug_nmi();
  debug_int();
  debug_exception(0);
}
