/* dump_assets GAME OUTDIR: every picture and sprite file of the four modes as BMPs */
#include "../src/assets.h"
#include <SDL3/SDL.h>
static Assets A;
static void save(const char *path, const Image *im, const uint8_t pal[16], int scale)
{
    SDL_Surface *s = SDL_CreateSurface(im->w * scale, im->h * scale, SDL_PIXELFORMAT_XRGB8888);
    uint32_t *px = s->pixels;
    for (int y = 0; y < im->h * scale; y++)
        for (int x = 0; x < im->w * scale; x++) {
            int k = (y / scale) * im->w + x / scale;
            const uint8_t *c = RGB16[pal[im->pix[k] & 15]];
            uint32_t v = (c[0] << 16) | (c[1] << 8) | c[2];
            if (im->mask && im->mask[k]) v = 0x3C3C5A;
            px[y * (s->pitch / 4) + x] = v;
        }
    SDL_SaveBMP(s, path);
    SDL_DestroySurface(s);
}
int main(int argc, char **argv)
{
    char err[256];
    if (argc < 3 || !assets_load(&A, argv[1], err, sizeof err)) { SDL_Log("%s", argc < 3 ? "usage" : err); return 1; }
    static const char *M[] = { "cga1", "cga2", "ega", "tandy" };
    char path[512];
    for (int m = 0; m < MODE_COUNT; m++) {
        for (int i = 0; i < PIC_COUNT; i++) {
            SDL_snprintf(path, sizeof path, "%s/%s_pic%c.bmp", argv[2], M[m], 'A' + i);
            save(path, &A.set[m].pic[i], A.set[m].pal[i], 1);
        }
        for (int f = 0; f < F_COUNT; f++) {
            int n = 0;
            for (int i = 0; i < MAX_ITEMS; i++) {
                const Image *im = asset_item(&A, (Mode)m, (FileId)f, i);
                if (!im) continue;
                n++;
                if (f == F_FONT && (i < 0x41 || i > 0x43)) continue;
                SDL_snprintf(path, sizeof path, "%s/%s_f%d_%03d.bmp", argv[2], M[m], f, i);
                save(path, im, A.set[m].pal[f == F_SWORD ? 13 : f == F_LANE ? 8 : 0], 2);
            }
            SDL_Log("%s file %d: %d items", M[m], f, n);
        }
    }
    assets_free(&A);
    return 0;
}
