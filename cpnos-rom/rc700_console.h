/* rc700_console — RC700 display state machine (conout).
 *
 * Consumes bytes from the CP/M CONOUT path, maintains cursor + display
 * RAM at 0xF800, handles the RC700 control-char set (except background-
 * attribute codes) and XY cursor addressing.  Structured so rcbios-in-c
 * can adopt it later; CP/NOS uses it directly.
 */
#ifndef RC700_CONSOLE_H
#define RC700_CONSOLE_H

#include <stdint.h>

void rc700_console_init(void);
void rc700_console_putc(uint8_t c);

#endif
