#include <stdio.h>
#include <stdlib.h>
#include <zstd.h>

int main(int argc, char *argv[]) {
    if (argc != 2) { fprintf(stderr, "usage: zstd_decompress <file>\n"); return 1; }
    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror("open"); return 1; }
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    void *src = malloc(sz);
    fread(src, 1, sz, f);
    fclose(f);
    unsigned long long dsz = ZSTD_getFrameContentSize(src, sz);
    if (dsz == ZSTD_CONTENTSIZE_ERROR || dsz == ZSTD_CONTENTSIZE_UNKNOWN) {
        dsz = sz * 10;
    }
    void *dst = malloc(dsz);
    size_t ret = ZSTD_decompress(dst, dsz, src, sz);
    if (ZSTD_isError(ret)) { fprintf(stderr, "zstd: %s\n", ZSTD_getErrorName(ret)); free(src); free(dst); return 1; }
    fwrite(dst, 1, ret, stdout);
    free(src);
    free(dst);
    return 0;
}
