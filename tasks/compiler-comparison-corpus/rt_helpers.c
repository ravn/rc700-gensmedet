/* Minimal 32-bit runtime builtins for the z88dk-bridge hybrid path.
 * Compiled by the SAME clang -> libcall ABI matches the call sites.
 * No variable shifts (avoids cascading __ashlsi3/__lshrsi3 libcalls). */
typedef unsigned long u32;

u32 __mulsi3(u32 a, u32 b) {
    u32 r = 0;
    while (b) { if (b & 1u) r += a; a <<= 1; b >>= 1; }   /* const shifts */
    return r;
}

u32 __udivmodsi4(u32 n, u32 d, u32 *rem) {
    u32 q = 0, r = 0, nmask = 0x80000000u;
    int i;
    for (i = 0; i < 32; i++) {
        r = (r << 1) | ((n & nmask) ? 1u : 0u);           /* const shift */
        nmask >>= 1;                                       /* const shift */
        q <<= 1;                                           /* const shift */
        if (r >= d) { r -= d; q |= 1u; }
    }
    if (rem) *rem = r;
    return q;
}
