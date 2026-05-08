/* rc700_console — RC700 display state machine for CP/NOS CONOUT.
 *
 * Handles the RC700 control-char set (0x01..0x1F except background-
 * attribute codes 0x13/0x14/0x15) and the 0x06-prefixed XY cursor
 * addressing sequence.  Bytes >= 0x20 go to display RAM at 0xF800.
 *
 * Public entries live in the resident chunk at 0xF200+, called from
 * resident.c's impl_conout.  State is in scratch BSS.
 */
#ifndef RC700_CONSOLE_H
#define RC700_CONSOLE_H

#include <stdint.h>

void rc700_console_init(void);
void rc700_console_putc(uint8_t c);

#endif
