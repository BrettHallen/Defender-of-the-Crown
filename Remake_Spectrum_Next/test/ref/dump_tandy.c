/*
 * Defender of the Crown (1986) - Spectrum Next remake
 * Nov 2026 using Claude Opus 5.5
 * "Guided" by Brett Hallen
 *
 * test/ref/dump_tandy.c: the Mac remake's own decoding of the Tandy sprite
 * files (Remake/src/assets.c), dumped so the converter's (tools/convert.py)
 * can be checked against it, item by item.
 *
 *   dump_tandy GAME-FOLDER OUT.BIN
 *
 * OUT.BIN: "DSPR", then for each file (F_FONT ... F_WINDOW) and item 0-255 that
 * has an image: the file, the item, the kind (bytes), w, h, ox, oy, adv
 * (int16 each), a byte 1 if it has a mask, the w*h pixels, the w*h mask bytes.
 */
#include "../../../Remake/src/assets.h"
#include <SDL3/SDL.h>

static Assets A;

void SDL_DelayNS(Uint64 ns) { (void)ns; }
Uint64 SDL_GetTicksNS(void) { return 0; }

int main(int argc, char **argv)
{
    char err[256];
    if (argc < 3) { fprintf(stderr, "usage: dump_tandy GAME-FOLDER OUT.BIN\n"); return 1; }
    if (!assets_load(&A, argv[1], err, sizeof err)) { fprintf(stderr, "%s\n", err); return 1; }
    FILE *o = fopen(argv[2], "wb");
    if (!o) { perror(argv[2]); return 1; }
    fwrite("DSPR", 1, 4, o);
    int n = 0;
    for (int f = 0; f < F_COUNT; f++) {
        const SpriteFile *sf = &A.set[MODE_TANDY].file[f];
        for (int i = 0; i < MAX_ITEMS; i++) {
            if (sf->kind[i] == IT_NONE) continue;
            const Image *im = &sf->img[i];
            uint8_t hd[3] = { (uint8_t)f, (uint8_t)i, (uint8_t)sf->kind[i] };
            int16_t v[5] = { (int16_t)im->w, (int16_t)im->h, (int16_t)im->ox, (int16_t)im->oy, (int16_t)sf->adv[i] };
            uint8_t hm = im->mask != NULL;
            fwrite(hd, 1, 3, o);
            fwrite(v, 2, 5, o);
            fwrite(&hm, 1, 1, o);
            fwrite(im->pix, 1, (size_t)im->w * im->h, o);
            if (hm) fwrite(im->mask, 1, (size_t)im->w * im->h, o);
            n++;
        }
    }
    fclose(o);
    fprintf(stderr, "%d images\n", n);
    assets_free(&A);
    return 0;
}
