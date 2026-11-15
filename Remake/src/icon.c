/*
 * Defender of the Crown (1986) - remake
 * Nov 2026 using Claude Opus 5.5
 * "Guided" by Brett Hallen
 * Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
 * IBM PC versions by Master Designer Software (1987 DOS) and the booter (GAME.DAT)
 * * icon.c: the app icon from the player's own copy of the game (see icon.h).
 * Each output pixel is the average of 4 x 4 samples, so the pixel art stays
 * crisp when large and is smoothed, not dropped, when small.
 */
#include "icon.h"

#include <SDL3/SDL.h>

#define SUB 4                     /* samples per pixel, each way */

/* Apple's icon grid: an 824-pixel rounded square in a 1024-pixel icon */
static bool in_body(double x, double y, double body, double r)
{
    if (x < 0 || y < 0 || x >= body || y >= body) return false;
    double cx = x < r ? r : x > body - r ? body - r : x;
    double cy = y < r ? r : y > body - r ? body - r : y;
    double dx = x - cx, dy = y - cy;
    return dx * dx + dy * dy <= r * r;
}

bool icon_render(const Assets *a, int size, uint8_t *rgba)
{
    static const Mode PREFER[3] = { MODE_EGA, MODE_TANDY, MODE_CGA2 };
    const Image *im = NULL;
    const uint8_t *pal = NULL;
    for (int k = 0; k < 3 && !im; k++) {
        const AssetSet *s = &a->set[PREFER[k]];
        if (s->loaded && s->pic[PIC_TITLE].pix && s->pic[PIC_TITLE].w > 0 && s->pic[PIC_TITLE].h > 0) {
            im = &s->pic[PIC_TITLE];
            pal = s->pal[PIC_TITLE];
        }
    }
    if (!im) return false;

    double body = size * 824.0 / 1024.0, margin = (size - body) / 2.0;
    double radius = body * 0.2237;
    double pic_h = body * 3.0 / 4.0;              /* the picture in its 4:3 shape */
    double pic_top = (body - pic_h) / 2.0;        /* black bars above and below */

    for (int y = 0; y < size; y++)
        for (int x = 0; x < size; x++) {
            double r = 0, g = 0, b = 0, n = 0;
            for (int sy = 0; sy < SUB; sy++)
                for (int sx = 0; sx < SUB; sx++) {
                    double u = x + (sx + 0.5) / SUB - margin, v = y + (sy + 0.5) / SUB - margin;
                    if (!in_body(u, v, body, radius)) continue;
                    n += 1;
                    double pv = v - pic_top;
                    if (pv < 0 || pv >= pic_h) continue;  /* black */
                    int px = (int)(u / body * im->w), py = (int)(pv / pic_h * im->h);
                    px = SDL_clamp(px, 0, im->w - 1);
                    py = SDL_clamp(py, 0, im->h - 1);
                    const uint8_t *c = RGB16[pal[im->pix[py * im->w + px] & 15] & 15];
                    r += c[0]; g += c[1]; b += c[2];
                }
            uint8_t *o = &rgba[(y * size + x) * 4];
            if (n > 0) {                                  /* colour over the covered samples */
                o[0] = (uint8_t)(r / n + 0.5);
                o[1] = (uint8_t)(g / n + 0.5);
                o[2] = (uint8_t)(b / n + 0.5);
            } else {
                o[0] = o[1] = o[2] = 0;
            }
            o[3] = (uint8_t)(n * 255.0 / (SUB * SUB) + 0.5);
        }
    return true;
}
