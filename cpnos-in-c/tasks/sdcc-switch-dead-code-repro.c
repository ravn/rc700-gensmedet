/* Minimal repro for SDCC switch dead-code bug.
 * Build: zsdcc +zx -SO3 specc_repro.c
 *
 * Expected: ~25 B of generated asm for the switch.
 * Observed: ~50+ B with duplicate dispatch + dead jr after each jp.
 */
extern void a(void);
extern void b(void);
extern void c(void);
extern void d(void);

void f(unsigned char x) {
    switch (x) {
    case 0x01: a(); break;
    case 0x02: b(); break;
    case 0x03: c(); break;
    case 0x04: d(); break;
    }
}
