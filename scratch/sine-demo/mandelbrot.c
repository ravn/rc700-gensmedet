/*
 *  RC700 graphics example 2: Mandelbrot set (fixed-point)
 *
 *  Renders the Mandelbrot set into the 160 x 75 semigraphics screen.  A pixel
 *  is plotted when its point c = (cx, cy) stays bounded after MAXIT iterations
 *  of z = z^2 + c, giving the classic filled silhouette (the screen is 1-bit
 *  per subpixel, so there is no colour/escape-time shading).
 *
 *  Everything is Q6.10 fixed-point integer arithmetic with 32-bit (long)
 *  products, so it builds under BOTH the classic compiler and -compiler=llvmz80
 *  with no float runtime.  This is the heaviest of the three examples on the
 *  compiler's integer code generation (nested loops + fixed-point multiplies).
 *
 *  Build (from the z88dk root):
 *    zcc +cpm -subtype=rc700 [-compiler=llvmz80] -O2 -create-app \
 *        -Cz+cpmdisk -Cz-f -Czrc700-8dd -Cz--container=imd \
 *        -o mandel examples/rc700/mandelbrot.c
 *  Produces mandel.com + mandel.imd; run in MAME rc702.  Expect it to be slow.
 */

#include <graphics.h>
#include <stdio.h>

#define FP     10                       /* fractional bits: 1.0 == 1024 */
#define ONE    (1 << FP)
#define FIX(v) ((int)((v) * ONE))

/* Q6.10 * Q6.10 -> Q6.10, via a 32-bit intermediate to avoid overflow. */
static int fmul(int a, int b)
{
    return (int)(((long)a * b) >> FP);
}

#define MAXIT 24
#define ESCAPE FIX(4.0)                 /* |z|^2 > 4 -> escaped */

void main(void)
{
    int w = getmaxx();                  /* 160 */
    int h = getmaxy();                  /*  75 */

    /* Complex-plane window: x in [-2.5, 1.0], y in [-1.15, 1.15]. */
    int x_min = FIX(-2.5);
    int y_min = FIX(-1.15);
    int x_span = FIX(3.5);
    int y_span = FIX(2.3);

    int px, py, i;

    clg();

    for (py = 0; py < h; py++) {
        int cy = y_min + (int)(((long)py * y_span) / h);
        for (px = 0; px < w; px++) {
            int cx = x_min + (int)(((long)px * x_span) / w);
            int zx = 0, zy = 0;

            for (i = 0; i < MAXIT; i++) {
                int x2 = fmul(zx, zx);
                int y2 = fmul(zy, zy);
                if (x2 + y2 > ESCAPE)
                    break;
                int xy = fmul(zx, zy);
                zx = x2 - y2 + cx;
                zy = 2 * xy + cy;
            }

            if (i == MAXIT)             /* point stayed bounded -> in set */
                plot(px, py);
        }
    }

    /* Non-blocking key poll; a blocking getchar() would page the graphics
       plane back out on the RC700 (see sine.c). */
    while (getk() != ' ')
        ;
}
