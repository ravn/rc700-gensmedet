/* copy.com -- minimal CP/M transient that exercises the canonical
 * file-write path via z88dk's stdio (which drives BDOS under the
 * hood).  Letting the stdlib handle FCB setup dodges the FCB1/FCB2
 * page-zero overlap that bit the hand-rolled ASM version.
 *
 * Usage:  A>COPY dest src
 */
#include <stdio.h>

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("usage: copy dest src\n");
        return 1;
    }

    FILE *fi = fopen(argv[2], "rb");
    if (!fi) {
        printf("COPY FAILED (cannot open %s)\n", argv[2]);
        return 1;
    }

    FILE *fo = fopen(argv[1], "wb");
    if (!fo) {
        printf("COPY FAILED (cannot create %s)\n", argv[1]);
        fclose(fi);
        return 1;
    }

    unsigned char buf[128];
    size_t n;
    while ((n = fread(buf, 1, sizeof(buf), fi)) > 0) {
        if (fwrite(buf, 1, n, fo) != n) {
            printf("COPY FAILED (write error)\n");
            fclose(fi);
            fclose(fo);
            return 1;
        }
    }

    fclose(fi);
    fclose(fo);
    printf("COPIED\n");
    return 0;
}
