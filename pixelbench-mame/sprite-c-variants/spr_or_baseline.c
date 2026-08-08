#include <stdint.h>
/* Self-contained pure-C cell-batched spr_or (no extern asm symbols), for an
   honest "how close does C get" measurement vs the hand-asm sprite_or. */
static const uint8_t textpixl[64]={
  0x20,0x21,0x22,0x23,0x24,0x25,0x26,0x27,0x28,0x29,0x2A,0x2B,0x2C,0x2D,0x2E,0x2F,
  0x30,0x31,0x32,0x33,0x34,0x35,0x36,0x37,0x38,0x39,0x3A,0x3B,0x3C,0x3D,0x3E,0x3F,
  0x60,0x61,0x62,0x63,0x64,0x65,0x66,0x67,0x68,0x69,0x6A,0x6B,0x6C,0x6D,0x6E,0x6F,
  0x70,0x71,0x72,0x73,0x74,0x75,0x76,0x77,0x78,0x79,0x7A,0x7B,0x7C,0x7D,0x7E,0x7F};

static uint8_t revmap(uint8_t ch){
    if(ch>=0x20 && ch<=0x3F) return ch-0x20;
    if(ch>=0x60 && ch<=0x7F) return ch-0x40;
    return 0;
}
void sprite_or_c(void *pbv){
    uint8_t *pb=(uint8_t*)pbv;
    uint8_t  x0=pb[0], y0=pb[1];
    uint8_t *spr=(uint8_t*)((uint16_t)pb[2] | ((uint16_t)pb[3]<<8));
    uint8_t  ccol0=x0>>1, crow=y0/3;
    uint8_t  wcells=spr[0]>>1, hrem=spr[1];
    uint8_t *bm=spr+2;
    *(volatile uint8_t*)0xF800 = 132;                 /* GFXMODE assert, once  */
    uint16_t base = 0xF800 + (uint16_t)crow*80;        /* running band base     */
    while(hrem){
        uint8_t r0=bm[0], r1=bm[1], r2=bm[2]; bm+=3;
        for(uint8_t cc=0; cc<wcells; cc++){
            uint8_t mask=0;
            if(r0&0x80) mask|=0x01; if(r0&0x40) mask|=0x02; r0<<=2;
            if(r1&0x80) mask|=0x04; if(r1&0x40) mask|=0x08; r1<<=2;
            if(r2&0x80) mask|=0x10; if(r2&0x40) mask|=0x20; r2<<=2;
            if(mask){
                volatile uint8_t *cell=(volatile uint8_t*)(base+ccol0+cc);
                *cell = textpixl[ revmap(*cell) | mask ];
            }
        }
        base += 80;
        hrem -= 3;
    }
}
