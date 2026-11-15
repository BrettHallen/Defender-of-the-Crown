/*
 * Defender of the Crown (1986) - remake
 * Nov 2026 using Claude Opus 5.5
 * "Guided" by Brett Hallen
 * Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
 * IBM PC versions by Master Designer Software (1987 DOS) and the booter (GAME.DAT)
 *
 * gfx.c: the four modes' pages and the original's drawing routines (gfx.h).
 * EGA: AB 8110-9C8A. CGA: AA 70D9-A2D8. Tandy: AC 71B9-9F54.
 */
#include "gfx.h"

static Video V;
static const Assets *A;
static SDL_Mutex *lock;

void gfx_init(const Assets *a)
{
    A = a;
    if (!lock) lock = SDL_CreateMutex();
    SDL_zero(V);
    for (int m = 0; m < MODE_COUNT; m++) {
        static const uint8_t CGA[16] = { 0, 2, 4, 6 };
        for (int i = 0; i < 16; i++)
            V.pal[m][i] = V.pal_next[m][i] = (m == MODE_CGA1 || m == MODE_CGA2) ? CGA[i & 3] : (uint8_t)i;
    }
}

Video *gfx_video(void) { return &V; }
const Assets *gfx_assets(void) { return A; }
void gfx_lock(void)   { if (lock) SDL_LockMutex(lock); }
void gfx_unlock(void) { if (lock) SDL_UnlockMutex(lock); }

static bool is_cga(int m) { return m == MODE_CGA1 || m == MODE_CGA2; }
static uint8_t *page(int m, int p) { return V.px[m][p]; }

void gfx_to_rgb(Mode m, uint32_t *out)
{
    gfx_lock();
    const uint8_t *s = page(m, PAGE_SCREEN);
    uint32_t lut[16];
    for (int i = 0; i < 16; i++) {
        const uint8_t *c = RGB16[V.pal[m][i] & 15];
        lut[i] = ((uint32_t)c[0] << 16) | ((uint32_t)c[1] << 8) | c[2];
    }
    for (int i = 0; i < SCREEN_W * SCREEN_H; i++) out[i] = lut[s[i] & 15];
    gfx_unlock();
}

/* ------------------------------------------------------------------ pictures, pages, palettes */

void gfx_picture_to(int pic, int pg)
{
    gfx_lock();
    for (int m = 0; m < MODE_COUNT; m++) {
        const Image *im = &A->set[m].pic[pic];
        if (im->pix) SDL_memcpy(page(m, pg), im->pix, SCREEN_W * SCREEN_H);
    }
    gfx_unlock();
}

static bool wipe_due;

bool gfx_take_wipe(void) { bool w = wipe_due; wipe_due = false; return w; }
void gfx_no_wipe(void)   { wipe_due = false; }

void gfx_present_rows_m(unsigned modes, int first, int step)
{
    gfx_lock();
    for (int m = 0; m < MODE_COUNT; m++)
        if (modes & (1u << m))
            for (int y = first; y < SCREEN_H; y += step)
                SDL_memcpy(page(m, PAGE_SCREEN) + y * SCREEN_W, page(m, PAGE_BACK) + y * SCREEN_W, SCREEN_W);
    gfx_unlock();
}

void gfx_show_picture(int pic)
{
    wipe_due = true;
    gfx_lock();
    for (int m = 0; m < MODE_COUNT; m++) SDL_memcpy(V.pal_next[m], A->set[m].pal[pic], 16);
    gfx_unlock();
    gfx_picture_to(pic, PAGE_BACK);
}

void gfx_set_palette(void)
{
    gfx_lock();
    SDL_memcpy(V.pal, V.pal_next, sizeof V.pal);
    gfx_unlock();
}

void gfx_keep_palette(int pic, int slot)
{
    gfx_lock();
    for (int m = 0; m < MODE_COUNT; m++) SDL_memcpy(V.pal_slot[m][slot & 3], A->set[m].pal[pic], 16);
    gfx_unlock();
}

void gfx_use_palette(int slot)
{
    gfx_lock();
    for (int m = 0; m < MODE_COUNT; m++) SDL_memcpy(V.pal_next[m], V.pal_slot[m][slot & 3], 16);
    gfx_unlock();
}

void gfx_present(void) { gfx_present_rows_m(MODES_ALL, 0, 1); }

void gfx_present_bottom(void)
{
    gfx_lock();
    for (int m = 0; m < MODE_COUNT; m++)
        SDL_memcpy(page(m, PAGE_SCREEN) + 100 * SCREEN_W, page(m, PAGE_BACK) + 100 * SCREEN_W, 100 * SCREEN_W);
    gfx_unlock();
}

void gfx_copy_page(int dst, int src)
{
    gfx_lock();
    for (int m = 0; m < MODE_COUNT; m++) SDL_memcpy(page(m, dst), page(m, src), SCREEN_W * SCREEN_H);
    gfx_unlock();
}

/* the byte value: CGA 4 pixels of 2 bits, Tandy 2 of 4 bits, EGA the same on all planes */
static int byte_pixel(int m, int byte, int x)
{
    if (is_cga(m)) return (byte >> (6 - 2 * (x & 3))) & 3;
    if (m == MODE_TANDY) return (byte >> ((x & 1) ? 0 : 4)) & 15;
    return byte ? 15 : 0;
}

void gfx_clear_back(int value)
{
    gfx_lock();
    for (int m = 0; m < MODE_COUNT; m++) {
        uint8_t *p = page(m, PAGE_BACK);
        for (int i = 0; i < SCREEN_W * SCREEN_H; i++) p[i] = (uint8_t)byte_pixel(m, value & 0xFF, i % SCREEN_W);
    }
    gfx_unlock();
}

/* x in 4-pixel units to a pixel: the EGA program wrote whole bytes (x >> 1) */
static int x_px(int m, int x)      { return m == MODE_EGA ? (x >> 1) * 8 : x * 4; }
static int w_px(int m, int w)      { return m == MODE_EGA ? ((w + 1) >> 1) * 8 : w * 4; }

static void hspan(int m, int pg, int x0, int y, int w, int (*fn)(int m, int old, int x, int arg), int arg)
{
    if (y < 0 || y >= SCREEN_H) return;
    uint8_t *row = page(m, pg) + y * SCREEN_W;
    for (int x = x0; x < x0 + w; x++)
        if (x >= 0 && x < SCREEN_W) row[x] = (uint8_t)fn(m, row[x], x, arg);
}

/* fill_rect: EGA the planes from the colour's bits 15-12 (8110), CGA its low byte
 * as a pattern (AA 70D9), Tandy its high byte (AC 71E5) */
static int fill_fn(int m, int old, int x, int c)
{
    (void)old;
    if (m == MODE_EGA) return (c >> 12) & 15;
    if (is_cga(m)) return byte_pixel(m, c & 0xFF, x);
    return byte_pixel(m, (c >> 8) & 0xFF, x);
}

void gfx_fill_rect(int x, int y, int w, int h, int colour)
{
    gfx_lock();
    for (int m = 0; m < MODE_COUNT; m++)
        for (int r = 0; r < h; r++) hspan(m, PAGE_BACK, x_px(m, x), y + r, w_px(m, w), fill_fn, colour);
    gfx_unlock();
}

/* xor_rect: EGA XORs set/reset (low byte) on the planes enabled (high byte) (8249);
 * CGA and Tandy XOR each byte with the low byte */
static int xor_fn(int m, int old, int x, int c)
{
    if (m == MODE_EGA) return old ^ (c & (c >> 8) & 15);
    return old ^ byte_pixel(m, c & 0xFF, x);
}

void gfx_xor_rect3(int x, int y, int w, int h, int cga, int ega, int tandy)
{
    gfx_lock();
    for (int m = 0; m < MODE_COUNT; m++) {
        int c = is_cga(m) ? cga : m == MODE_EGA ? ega : tandy;
        for (int r = 0; r < h; r++) hspan(m, PAGE_BACK, x_px(m, x), y + r, w_px(m, w), xor_fn, c);
    }
    gfx_unlock();
}

void gfx_xor_rect(int x, int y, int w, int h, int colour) { gfx_xor_rect3(x, y, w, h, colour, colour, colour); }

enum { OP_COPY, OP_XOR, OP_MASKED };

static void blit(int m, int pg, int x0, int y0, const Image *im, int op, int rows)
{
    if (!im || !im->pix) return;
    x0 += im->ox;
    y0 += im->oy;
    uint8_t *p = page(m, pg);
    if (rows > im->h) rows = im->h;
    for (int y = 0; y < rows; y++) {
        int sy = y0 + y;
        if (sy < 0 || sy >= SCREEN_H) continue;
        for (int x = 0; x < im->w; x++) {
            int sx = x0 + x;
            if (sx < 0 || sx >= SCREEN_W) continue;
            int k = y * im->w + x, v = im->pix[k];
            uint8_t *d = &p[sy * SCREEN_W + sx];
            if (op == OP_XOR) *d ^= (uint8_t)v;
            else if (op == OP_MASKED && im->mask) *d = (uint8_t)((*d & im->mask[k]) | v);
            else *d = (uint8_t)v;
        }
    }
}

void gfx_put_sprite(int x, int y, FileId f, int item) { gfx_put_sprite_m(MODES_ALL, x, y, f, item); }

void gfx_put_sprite_m(unsigned modes, int x, int y, FileId f, int item)
{
    gfx_lock();
    for (int m = 0; m < MODE_COUNT; m++)
        if (modes & (1u << m)) blit(m, PAGE_BACK, x_px(m, x), y, asset_item(A, (Mode)m, f, item), OP_COPY, 999);
    gfx_unlock();
}

void gfx_xor_sprite_t(int x, int x_tandy, int y, FileId f, int item)
{
    gfx_lock();
    for (int m = 0; m < MODE_COUNT; m++)
        blit(m, PAGE_BACK, x_px(m, m == MODE_TANDY ? x_tandy : x), y, asset_item(A, (Mode)m, f, item), OP_XOR, 999);
    gfx_unlock();
}

void gfx_xor_sprite(int x, int y, FileId f, int item) { gfx_xor_sprite_m(MODES_ALL, x, y, f, item); }

void gfx_xor_sprite_m(unsigned modes, int x, int y, FileId f, int item)
{
    gfx_lock();
    for (int m = 0; m < MODE_COUNT; m++)
        if (modes & (1u << m)) blit(m, PAGE_BACK, x_px(m, x), y, asset_item(A, (Mode)m, f, item), OP_XOR, 999);
    gfx_unlock();
}

/* xor_mask. EGA (8405): write mode 0, function XOR, set/reset enabled on the planes in the
 * colour's high byte with the values in its low byte: those planes are XORed with the
 * set/reset value over the whole rectangle, the others with the shape's bits. The CGA
 * and Tandy programs XOR their shape pictures in instead (their redraw_map and
 * flash_territory call xor_sprite: AA 30E4, AC 314F). */
void gfx_xor_mask(int x, int y, FileId f, int item)
{
    gfx_lock();
    for (int m = 0; m < MODE_COUNT; m++) {
        const Image *im = asset_item(A, (Mode)m, f, item);
        if (!im) continue;
        if (m == MODE_EGA) {
            int c = A->set[m].file[f].colour[item];
            int en = (c >> 8) & 15, sr = c & en & 15, data = ~en & 15;
            uint8_t *p = page(m, PAGE_BACK);
            int x0 = x_px(m, x);
            for (int r = 0; r < im->h; r++)
                for (int k = 0; k < im->w; k++) {
                    int sx = x0 + k, sy = y + r;
                    if (sx < 0 || sx >= SCREEN_W || sy < 0 || sy >= SCREEN_H) continue;
                    p[sy * SCREEN_W + sx] ^= (uint8_t)(sr ^ (im->pix[r * im->w + k] ? data : 0));
                }
        } else {
            blit(m, PAGE_BACK, x_px(m, x), y, im, OP_XOR, 999);
        }
    }
    gfx_unlock();
}

/* set_region_colour. EGA (9719): the shape's colour word. CGA (AA 8359): in each byte the
 * pixels that are not 0 are XORed with the colour's high byte, the next row its low byte,
 * and so on (again on every call). Tandy (AC 943B): the pixels that are not 0 become
 * Dh XOR the colour's high byte's nibble (low byte on the next row). */
void gfx_set_region_colour(int item, const int colour[MODE_COUNT])
{
    gfx_lock();
    for (int m = 0; m < MODE_COUNT; m++) {
        SpriteFile *sf = &((Assets *)A)->set[m].file[F_PORTRAITS];
        int c = colour[m] & 0xFFFF;
        if (m == MODE_EGA) { sf->colour[item] = (uint16_t)c; continue; }
        Image *im = &sf->img[item];
        if (!im->pix) continue;
        for (int r = 0; r < im->h; r++) {
            int pat = (r & 1) ? c & 0xFF : (c >> 8) & 0xFF;
            for (int k = 0; k < im->w; k++) {
                uint8_t *v = &im->pix[r * im->w + k];
                if (!*v) continue;
                if (is_cga(m)) *v ^= (uint8_t)byte_pixel(m, pat, k);
                else *v = (uint8_t)(0xD ^ byte_pixel(m, pat, k));
            }
        }
    }
    gfx_unlock();
}

static int alias_from = -1, alias_to = -1;
void gfx_glyph_alias(int from, int to) { alias_from = to < 0 ? -1 : from; alias_to = to; }
static int aliased(int ch) { return ch == alias_from ? alias_to : ch; }

int gfx_glyph_advance(int ch)
{
    ch = aliased(ch);
    const SpriteFile *f = &A->set[MODE_EGA].file[F_FONT];
    if (ch < 0 || ch >= MAX_ITEMS || f->kind[ch] != IT_GLYPH) return 0;
    return (f->adv[ch] >> 1) + 1;
}

/* EGA and Tandy: the letter ANDed in, shifted to the pixel (AB 85B4, AC 73BB);
 * CGA: put whole, w/2 pixels wide (AA 727B) */
void gfx_glyph(int xpx, int y, int ch)
{
    ch = aliased(ch);
    gfx_lock();
    for (int m = 0; m < MODE_COUNT; m++) {
        const SpriteFile *f = &A->set[m].file[F_FONT];
        if (ch < 0 || ch >= MAX_ITEMS || f->kind[ch] != IT_GLYPH) continue;
        const Image *im = &f->img[ch];
        if (m == MODE_EGA || m == MODE_TANDY) { blit(m, PAGE_BACK, xpx, y, im, OP_MASKED, 999); continue; }
        Image part = *im;
        int w = f->adv[ch] / 2;
        uint8_t *p = page(m, PAGE_BACK);
        for (int r = 0; r < part.h; r++)
            for (int k = 0; k < w && k < part.w; k++) {
                int sx = xpx + k, sy = y + r;
                if (sx >= 0 && sx < SCREEN_W && sy >= 0 && sy < SCREEN_H) p[sy * SCREEN_W + sx] = part.pix[r * part.w + k];
            }
    }
    gfx_unlock();
}

/* EGA: write mode 2, the colour's low 4 bits (86BA). Tandy: the nibble (AC 7E72).
 * CGA: the byte is turned so the pixel is in bits 1-0, ANDed with FCh and ORed with
 * the colour's low byte (AA 73FC): colour 0Fh also sets the pixel on its left in
 * the same byte (the title's sparkles leave a few such pixels behind). */
void gfx_put_pixel(int pg, int xpx, int y, int colour) { gfx_put_pixel_m(MODES_ALL, pg, xpx, y, colour); }

void gfx_put_pixel_m(unsigned modes, int pg, int xpx, int y, int colour)
{
    if (xpx < 0 || xpx >= SCREEN_W || y < 0 || y >= SCREEN_H) return;
    gfx_lock();
    for (int m = 0; m < MODE_COUNT; m++) {
        if (!(modes & (1u << m))) continue;
        uint8_t *p = page(m, pg) + y * SCREEN_W;
        if (is_cga(m)) {
            int b0 = xpx & ~3, k = xpx & 3, cl = (3 - k) * 2, byte = 0;
            for (int i = 0; i < 4; i++) byte |= (p[b0 + i] & 3) << (6 - 2 * i);
            byte = ((byte >> cl) | (byte << (8 - cl))) & 0xFF;
            byte = (byte & 0xFC) | (colour & 0xFF);
            byte = ((byte << cl) | (byte >> (8 - cl))) & 0xFF;
            for (int i = 0; i < 4; i++) p[b0 + i] = (uint8_t)((byte >> (6 - 2 * i)) & 3);
        } else {
            p[xpx] = (uint8_t)(colour & 15);
        }
    }
    gfx_unlock();
}

int gfx_get_pixel(Mode m, int pg, int xpx, int y)
{
    if (xpx < 0 || xpx >= SCREEN_W || y < 0 || y >= SCREEN_H) return 0;
    return page(m, pg)[y * SCREEN_W + xpx];
}

/* ------------------------------------------------------------------ the sprite slots */

/* The EGA program's pre-shifted copies are all the same, so a sprite lands on a
 * whole byte of 8 pixels; the CGA program's on 4 pixels; the Tandy program's
 * two copies place it to the pixel. */
static int slot_x(int m, int x) { return m == MODE_EGA ? x & ~7 : is_cga(m) ? x & ~3 : x; }

void gfx_sprites_draw(void)
{
    gfx_lock();
    for (int m = 0; m < MODE_COUNT; m++)
        for (int i = NUM_SLOTS - 1; i >= 0; i--) {
            Slot *s = &V.slot[i];
            V.saved_ok[m][i] = false;
            if (!s->active || (s->modes && !(s->modes & (1u << m)))) continue;
            const Image *im = asset_item(A, (Mode)m, s->file, s->item);
            if (!im) continue;
            int x0 = slot_x(m, s->x + (m == MODE_TANDY ? s->tandy_dx : 0)), rows = im->h - s->trim;
            if (s->rows > 0 && s->rows < rows) rows = s->rows;
            if (rows <= 0) continue;
            /* save what is under it */
            int w = im->w, h = rows;
            if ((size_t)w * h > sizeof V.saved[m][i]) continue;
            uint8_t *p = page(m, PAGE_BACK);
            for (int r = 0; r < h; r++)
                for (int k = 0; k < w; k++) {
                    int sx = x0 + k, sy = s->y + r;
                    V.saved[m][i][r * w + k] = (sx >= 0 && sx < SCREEN_W && sy >= 0 && sy < SCREEN_H) ? p[sy * SCREEN_W + sx] : 0;
                }
            V.sx[m][i] = x0; V.sy[m][i] = s->y; V.sw[m][i] = w; V.sh[m][i] = h;
            V.saved_ok[m][i] = true;
            blit(m, PAGE_BACK, x0, s->y, im, OP_MASKED, rows);
        }
    gfx_unlock();
}

void gfx_sprites_erase(void)
{
    gfx_lock();
    for (int m = 0; m < MODE_COUNT; m++)
        for (int i = 0; i < NUM_SLOTS; i++) {
            if (!V.slot[i].active || !V.saved_ok[m][i]) continue;
            uint8_t *p = page(m, PAGE_BACK);
            int w = V.sw[m][i], h = V.sh[m][i];
            for (int r = 0; r < h; r++)
                for (int k = 0; k < w; k++) {
                    int sx = V.sx[m][i] + k, sy = V.sy[m][i] + r;
                    if (sx >= 0 && sx < SCREEN_W && sy >= 0 && sy < SCREEN_H) p[sy * SCREEN_W + sx] = V.saved[m][i][r * w + k];
                }
            V.saved_ok[m][i] = false;
        }
    gfx_unlock();
}

void gfx_slot_sprite(int xpx, int y, FileId f, int item) { gfx_slot_sprite_m(MODES_ALL, xpx, y, f, item); }

void gfx_slot_sprite_m(unsigned modes, int xpx, int y, FileId f, int item)
{
    gfx_lock();
    for (int m = 0; m < MODE_COUNT; m++)
        if (modes & (1u << m)) blit(m, PAGE_BACK, slot_x(m, xpx), y, asset_item(A, (Mode)m, f, item), OP_MASKED, 999);
    gfx_unlock();
}

static uint8_t fire_saved[MODE_COUNT][64 * 64];
static int fire_w[MODE_COUNT], fire_h[MODE_COUNT], fire_x[MODE_COUNT], fire_y[MODE_COUNT];

void gfx_fire_draw(int frame, int x, int y, int cga_x, int cga_y)
{
    gfx_lock();
    for (int m = 0; m < MODE_COUNT; m++) {
        fire_w[m] = 0;
        if (is_cga(m)) {
            blit(m, PAGE_BACK, x_px(m, cga_x), cga_y, asset_item(A, (Mode)m, F_FONT, ITEM_FLAME1), OP_XOR, 999);
            continue;
        }
        if (!frame) continue;
        const Image *im = asset_item(A, (Mode)m, F_FONT, frame == 1 ? ITEM_FLAME1 : ITEM_FLAME2);
        if (!im || (size_t)im->w * im->h > sizeof fire_saved[m]) continue;
        int x0 = slot_x(m, x);
        uint8_t *p = page(m, PAGE_BACK);
        for (int r = 0; r < im->h; r++)
            for (int k = 0; k < im->w; k++) {
                int sx = x0 + k, sy = y + r;
                fire_saved[m][r * im->w + k] = (sx < SCREEN_W && sy < SCREEN_H && sx >= 0 && sy >= 0) ? p[sy * SCREEN_W + sx] : 0;
            }
        fire_w[m] = im->w; fire_h[m] = im->h; fire_x[m] = x0; fire_y[m] = y;
        blit(m, PAGE_BACK, x0, y, im, OP_MASKED, 999);
    }
    gfx_unlock();
}

void gfx_fire_erase(void)
{
    gfx_lock();
    for (int m = 0; m < MODE_COUNT; m++) {
        if (!fire_w[m]) continue;
        uint8_t *p = page(m, PAGE_BACK);
        for (int r = 0; r < fire_h[m]; r++)
            for (int k = 0; k < fire_w[m]; k++) {
                int sx = fire_x[m] + k, sy = fire_y[m] + r;
                if (sx < SCREEN_W && sy < SCREEN_H && sx >= 0 && sy >= 0) p[sy * SCREEN_W + sx] = fire_saved[m][r * fire_w[m] + k];
            }
        fire_w[m] = 0;
    }
    gfx_unlock();
}
