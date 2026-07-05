/* #87/#73: At -Oz, an 8-byte __builtin_memcpy unrolls to ~28-40 B of
 * inline stores instead of dispatching to the LDIR runtime stub
 * (~13 B per call site, single LDIR invocation). */
#include <stdint.h>

extern uint8_t dst[];
extern const uint8_t src[8];

void copy8_const_src(void) {
    __builtin_memcpy(dst, src, 8);
}

void copy7(void) {
    __builtin_memcpy(dst, src, 7);
}

void copy16(void) {
    __builtin_memcpy(dst, src, 16);
}

void copy_arbitrary(uint8_t n) {
    __builtin_memcpy(dst, src, 13);
}
