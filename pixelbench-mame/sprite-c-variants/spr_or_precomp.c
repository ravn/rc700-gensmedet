#include <stdint.h>
static const uint8_t textpixl[64]={
  0x20,0x21,0x22,0x23,0x24,0x25,0x26,0x27,0x28,0x29,0x2A,0x2B,0x2C,0x2D,0x2E,0x2F,
  0x30,0x31,0x32,0x33,0x34,0x35,0x36,0x37,0x38,0x39,0x3A,0x3B,0x3C,0x3D,0x3E,0x3F,
  0x60,0x61,0x62,0x63,0x64,0x65,0x66,0x67,0x68,0x69,0x6A,0x6B,0x6C,0x6D,0x6E,0x6F,
  0x70,0x71,0x72,0x73,0x74,0x75,0x76,0x77,0x78,0x79,0x7A,0x7B,0x7C,0x7D,0x7E,0x7F};
static const uint8_t rev[256]={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};

/* A "compiled" sprite = list of only the NON-EMPTY cells, each carrying a
   precomputed VRAM offset (relative to the top-left cell) and a ready mask.
   Built ONCE from the bitmap; the per-frame draw does no bit-testing and
   never visits an empty cell. */
typedef struct { uint16_t off; uint8_t mask; } CCELL;

/* compile: fill cells[], return count. spr = w,h,data (rowbytes=ceil(w/8)). */
uint8_t spr_compile(const uint8_t *spr, CCELL *cells){
    uint8_t w=spr[0], h=spr[1];
    const uint8_t *bm=spr+2;
    uint8_t rowbytes=(w+7)>>3, wcells=(w+1)>>1;
    uint8_t n=0, crow=0, yb=0;
    while(yb<h){
        uint8_t nrows=h-yb; if(nrows>3) nrows=3;
        const uint8_t *r0=bm,*r1=bm+rowbytes,*r2=bm+2*rowbytes;
        for(uint8_t cc=0; cc<wcells; cc++){
            uint8_t p0=cc<<1,p1=p0+1,b0=p0>>3,sh0=7-(p0&7),sh1=sh0-1,rc=p1<w;
            uint8_t mask=0,c;
            c=r0[b0]; if((c>>sh0)&1)mask|=0x01; if(rc&&((c>>sh1)&1))mask|=0x02;
            if(nrows>1){c=r1[b0]; if((c>>sh0)&1)mask|=0x04; if(rc&&((c>>sh1)&1))mask|=0x08;}
            if(nrows>2){c=r2[b0]; if((c>>sh0)&1)mask|=0x10; if(rc&&((c>>sh1)&1))mask|=0x20;}
            if(mask){ cells[n].off=(uint16_t)crow*80+cc; cells[n].mask=mask; n++; }
        }
        crow++; bm+=nrows*rowbytes; yb+=nrows;
    }
    return n;
}

/* draw: x0 even, y0 mult-3. base = top-left cell address. */
void spr_draw(uint8_t x0,uint8_t y0,const CCELL *cells,uint8_t n){
    *(volatile uint8_t*)0xF800=132;
    uint16_t base=0xF800+(uint16_t)(y0/3)*80+(x0>>1);
    for(uint8_t i=0;i<n;i++){
        volatile uint8_t *cp=(volatile uint8_t*)(base+cells[i].off);
        *cp=textpixl[rev[*cp]|cells[i].mask];
    }
}
