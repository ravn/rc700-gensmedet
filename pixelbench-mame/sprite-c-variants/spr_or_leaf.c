#include <stdint.h>
/* C-outer + asm-leaf sprite blit.  All the readable structure is here in C;
   the register-pressure-critical inner cell loop (mask build + A+HL RMW) is the
   tiny asm leaf blit_band().  Goal: full hand-asm speed with clear C code. */

extern void blit_band(void *blk) __attribute__((z80_fastcall));

void sprite_or_leaf(void *pbv){
    uint8_t *pb = (uint8_t*)pbv;
    uint8_t  x0 = pb[0], y0 = pb[1];
    uint8_t *spr = (uint8_t*)((uint16_t)pb[2] | ((uint16_t)pb[3]<<8));
    uint8_t  ccol0  = x0>>1;
    uint8_t  crow   = y0/3;
    uint8_t  wcells = spr[0]>>1;
    uint8_t  hrem   = spr[1];
    uint8_t *bm     = spr+2;

    *(volatile uint8_t*)0xF800 = 132;                 /* gfx page, once        */
    uint16_t base = 0xF800 + (uint16_t)crow*80;        /* running band base     */

    uint8_t blk[6];
    blk[3] = wcells;
    while(hrem){
        uint16_t addr = base + ccol0;
        blk[0] = bm[0]; blk[1] = bm[1]; blk[2] = bm[2]; bm += 3;
        blk[4] = (uint8_t)addr;
        blk[5] = (uint8_t)(addr>>8);
        blit_band(blk);                                /* asm inner cell loop   */
        base += 80;
        hrem -= 3;
    }
}
