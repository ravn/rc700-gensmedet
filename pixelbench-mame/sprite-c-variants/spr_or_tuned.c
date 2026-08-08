/* spr_or_tuned.c -- pure-C cell-batched spr_or, tuned for llvmz80.
 *
 * Best pure-C variant found empirically (44,632,980 T over 4000x 8x9 ball =
 * 11,158 T/sprite = 5.10x vs generic; byte-identical VRAM). The winning levers,
 * each MEASURED (not guessed) on rc702sem702 -nothrottle, llvmz80 -O3:
 *   - 256-byte rev[] LUT for glyph->mask (no compare/branch chain in the RMW).
 *   - walking cell pointer `cp` + cp++ (no base+ccol0+cc recompute per cell).
 *   - down-counting loop `for(n=wcells;n;n--)` (dec+jnz beats cp+jr up-count).
 *
 * Levers that BACKFIRED on Z80 (kept as a warning -- see PROGRESS.md):
 *   - "branchless" mask via swap2[r>>6]: the r>>6 (rlca/rlca/and) + LUT was
 *     SLOWER than 6 plain bit-test branches (48.9M naive -> 54.7M "tuned").
 *     The branchy mask build below is the fast one on this target.
 *
 * For the last ~13% (down to 6.26x) an asm inner leaf is needed -- see
 * spr_or_leaf.c + blit_band.asm. This file is the fastest 100%-C option.
 */
#include <stdint.h>
static const uint8_t textpixl[64]={
  0x20,0x21,0x22,0x23,0x24,0x25,0x26,0x27,0x28,0x29,0x2A,0x2B,0x2C,0x2D,0x2E,0x2F,
  0x30,0x31,0x32,0x33,0x34,0x35,0x36,0x37,0x38,0x39,0x3A,0x3B,0x3C,0x3D,0x3E,0x3F,
  0x60,0x61,0x62,0x63,0x64,0x65,0x66,0x67,0x68,0x69,0x6A,0x6B,0x6C,0x6D,0x6E,0x6F,
  0x70,0x71,0x72,0x73,0x74,0x75,0x76,0x77,0x78,0x79,0x7A,0x7B,0x7C,0x7D,0x7E,0x7F};
static const uint8_t rev[256]={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
void sprite_or_pc(void*pbv){
  uint8_t*pb=pbv; uint8_t x0=pb[0],y0=pb[1];
  const uint8_t*restrict spr=(const uint8_t*)((uint16_t)pb[2]|((uint16_t)pb[3]<<8));
  uint8_t ccol0=x0>>1,crow=y0/3,wcells=spr[0]>>1,hrem=spr[1];
  const uint8_t*restrict bm=spr+2;
  *(volatile uint8_t*)0xF800=132;
  uint16_t base=0xF800+(uint16_t)crow*80;
  while(hrem){
    uint8_t r0=bm[0],r1=bm[1],r2=bm[2]; bm+=3;
    volatile uint8_t*cp=(volatile uint8_t*)(base+ccol0);
    for(uint8_t n=wcells;n;n--){
      uint8_t mask=0;
      if(r0&0x80)mask|=0x01; if(r0&0x40)mask|=0x02; r0<<=2;
      if(r1&0x80)mask|=0x04; if(r1&0x40)mask|=0x08; r1<<=2;
      if(r2&0x80)mask|=0x10; if(r2&0x40)mask|=0x20; r2<<=2;
      if(mask) *cp=textpixl[rev[*cp]|mask];
      cp++;
    }
    base+=80; hrem-=3;
  }
}
