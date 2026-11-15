/*
 * Defender of the Crown (1986) - remake
 * Nov 2026 using Claude Opus 5.5
 * "Guided" by Brett Hallen
 * Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
 * IBM PC versions by Master Designer Software (1987 DOS) and the booter (GAME.DAT)
 *
 * assets.c: decoding the four modes' pictures and sprites (see assets.h and
 * Analysis/DOTC_file_reference.md).
 */
#include "assets.h"
#include "dat.h"

#include <SDL3/SDL.h>

const char *const MODE_NAMES[MODE_COUNT] = { "CGA (1987)", "CGA", "EGA", "Tandy" };

const uint8_t RGB16[16][3] = {
    { 0, 0, 0 }, { 0, 0, 170 }, { 0, 170, 0 }, { 0, 170, 170 }, { 170, 0, 0 }, { 170, 0, 170 }, { 170, 85, 0 }, { 170, 170, 170 },
    { 85, 85, 85 }, { 85, 85, 255 }, { 85, 255, 85 }, { 85, 255, 255 }, { 255, 85, 85 }, { 255, 85, 255 }, { 255, 255, 85 }, { 255, 255, 255 },
};

bool mode_from_name(const char *s, Mode *m)
{
    static const char *const N[MODE_COUNT] = { "cga1", "cga2", "ega", "tandy" };
    for (int i = 0; i < MODE_COUNT; i++)
        if (SDL_strcasecmp(s, N[i]) == 0) { *m = (Mode)i; return true; }
    return false;
}

static const char *const FILES[3][F_COUNT] = {
    /* CGA (AA) */  { "BA", "BD", "BP", "BT", "BU", "BV", "BW", "Bc", "Bf", "Bg", "Bg" },
    /* EGA (AB) */  { "BB", "BE", "BL", "BJ", "BK", "BN", "BO", "Bd", "Bh", "Bi", "Bi" },
    /* Tandy (AC) */{ "BC", "BF", "BR", "BX", "BY", "Ba", "Bb", "Be", "Bj", "Bk", "Bl" },
};

/* The DOS version's pictures, A-T: (.LIB file, item) */
static const struct { const char *lib; int item; } DOS_PICS[PIC_COUNT] = {
    { "TITLE", 0 }, { "TITLE", 1 }, { "TITLE", 3 }, { "TITLE", 4 }, { "TITLE", 5 }, { "TITLE", 6 },
    { "RAID", 3 }, { "JOUST1", 0 }, { "JOUST2", 1 }, { "JOUST2", 19 }, { "DOCCHARS", 93 }, { "RAID", 4 },
    { "RAID", 2 }, { "RAID", 0 }, { "RAID", 1 }, { "SIEGE", 0 }, { "SIEGE", 1 }, { "LOVE1", 0 },
    { "LOVE2", 0 }, { "LOVE2", 10 },
};

/* ------------------------------------------------------------------ files */

static bool exists(const char *path)
{
    SDL_PathInfo info;
    return SDL_GetPathInfo(path, &info) && info.type == SDL_PATHTYPE_FILE;
}

/* name in dir, dir/ega, dir/cga (any case) */
static bool find_file(const char *dir, const char *name, char *out, size_t n)
{
    static const char *const SUB[] = { "", "ega/", "cga/", "EGA/", "CGA/" };
    for (size_t s = 0; s < SDL_arraysize(SUB); s++) {
        char lower[64];
        SDL_strlcpy(lower, name, sizeof lower);
        for (char *p = lower; *p; p++) *p = (char)SDL_tolower((unsigned char)*p);
        const char *names[2] = { name, lower };
        for (int k = 0; k < 2; k++) {
            SDL_snprintf(out, n, "%s/%s%s", dir, SUB[s], names[k]);
            if (exists(out)) return true;
        }
    }
    return false;
}

bool assets_dir_ok(const char *dir)
{
    char p[1200];
    return find_file(dir, "GAME.DAT", p, sizeof p);
}

/* ------------------------------------------------------------------ images */

static bool img_alloc(Image *im, int w, int h, bool masked)
{
    im->w = w; im->h = h;
    im->pix = SDL_calloc((size_t)w * h, 1);
    im->mask = masked ? SDL_calloc((size_t)w * h, 1) : NULL;
    return im->pix && (!masked || im->mask);
}

static void img_free(Image *im)
{
    SDL_free(im->pix);
    SDL_free(im->mask);
    SDL_zero(*im);
}

static int word(const uint8_t *d, size_t len, size_t o) { return o + 1 < len ? d[o] | (d[o + 1] << 8) : 0; }

/* pixel x of a row: CGA 4 a byte (high bits first), EGA planes, Tandy 2 a byte (high nibble first) */
static int px_cga(const uint8_t *row, int x)   { return (row[x >> 2] >> (6 - 2 * (x & 3))) & 3; }
static int px_tandy(const uint8_t *row, int x) { return (row[x >> 1] >> ((x & 1) ? 0 : 4)) & 15; }
static int px_bit(const uint8_t *row, int x)   { return (row[x >> 3] >> (7 - (x & 7))) & 1; }

/* A big sprite (word height, word bytes a row, the pixels) or the pixels of a
 * slot sprite's copy (after its mask). EGA: planes 3, 2, 1, 0 one after another. */
static bool decode_pixels(Image *im, Mode m, const uint8_t *d, size_t len, size_t o, int h, int bpr, size_t mask_o)
{
    int w = m == MODE_EGA ? bpr * 8 : m == MODE_TANDY ? bpr * 2 : bpr * 4;
    size_t ps = (size_t)h * bpr;
    size_t need = o + (m == MODE_EGA ? 4 * ps : ps);
    if (h <= 0 || bpr <= 0 || h > 200 || w > 640 || need > len || (mask_o && mask_o + ps > len)) return false;
    if (!img_alloc(im, w, h, mask_o != 0)) return false;
    for (int y = 0; y < h; y++)
        for (int x = 0; x < w; x++) {
            int v;
            size_t k = (size_t)y * bpr;
            if (m == MODE_EGA) {
                v = 0;
                for (int j = 0; j < 4; j++) v |= px_bit(d + o + j * ps + k, x) << (3 - j);
            } else if (m == MODE_TANDY) v = px_tandy(d + o + k, x);
            else v = px_cga(d + o + k, x);
            im->pix[y * w + x] = (uint8_t)v;
            if (mask_o) {
                /* the AND value: the background bits kept (EGA a bit for all four planes) */
                int t = m == MODE_EGA ? (px_bit(d + mask_o + k, x) ? 15 : 0) : m == MODE_TANDY ? px_tandy(d + mask_o + k, x)
                                                                                                 : px_cga(d + mask_o + k, x);
                im->mask[y * w + x] = (uint8_t)t;
            }
        }
    return true;
}

/* The font: EGA word width (in CGA bits: w/2 pixels), word height, 1 bit a
 * pixel (drawn by ANDing: set bits become 0); CGA word width in bits, word
 * height, 2 bits a pixel; Tandy word width, word bytes a row, word height, 4 bits a pixel. */
static bool decode_glyph(Image *im, int *adv, Mode m, const uint8_t *d, size_t len, size_t o)
{
    int wb = word(d, len, o);
    *adv = wb;
    if (m == MODE_EGA) {
        int h = word(d, len, o + 2), w = wb / 2, bpr = (w + 7) / 8;
        if (h <= 0 || h > 32 || w <= 0 || o + 4 + (size_t)bpr * h > len) return false;
        if (!img_alloc(im, bpr * 8, h, true)) return false;
        for (int y = 0; y < h; y++)
            for (int x = 0; x < bpr * 8; x++) {
                int b = px_bit(d + o + 4 + (size_t)y * bpr, x);
                im->pix[y * im->w + x] = 0;
                im->mask[y * im->w + x] = (uint8_t)(b ? 0 : 15);
            }
        return true;
    }
    if (m == MODE_TANDY) {   /* AC 73BB ANDs in the NOT of each nibble: kept as a mask, the pixels 0 */
        int bpr = word(d, len, o + 2), h = word(d, len, o + 4);
        if (!decode_pixels(im, m, d, len, o + 6, h, bpr, 0)) return false;
        im->mask = SDL_malloc((size_t)im->w * im->h);
        if (!im->mask) return false;
        for (int i = 0; i < im->w * im->h; i++) { im->mask[i] = (uint8_t)(~im->pix[i] & 15); im->pix[i] = 0; }
        return true;
    }
    /* CGA: AA 727B puts the NOT of the glyph (its letters are 3 on 0) */
    int h = word(d, len, o + 2), bpr = (wb + 7) / 8;
    if (!decode_pixels(im, m, d, len, o + 4, h, bpr, 0)) return false;
    for (int i = 0; i < im->w * im->h; i++) im->pix[i] ^= 3;
    return true;
}

static bool decode_mask(Image *im, uint16_t *colour, Mode m, const uint8_t *d, size_t len, size_t o)
{
    int h = word(d, len, o), bpr = word(d, len, o + 2);
    /* CGA and Tandy: word height, word bytes a row, the pixels (copied whole; set_region_colour
     * recolours them, AA 8359 and AC 943B) */
    if (m != MODE_EGA) { *colour = 0; return decode_pixels(im, m, d, len, o + 4, h, bpr, 0); }
    *colour = (uint16_t)word(d, len, o + 4);
    if (h <= 0 || bpr <= 0 || o + 6 + (size_t)h * bpr > len) return false;
    if (!img_alloc(im, bpr * 8, h, true)) return false;
    for (int y = 0; y < h; y++)
        for (int x = 0; x < bpr * 8; x++) {
            int b = px_bit(d + o + 6 + (size_t)y * bpr, x);
            im->pix[y * im->w + x] = (uint8_t)b;
            im->mask[y * im->w + x] = (uint8_t)(b ? 0 : 15);
        }
    return true;
}

static void file_free(SpriteFile *f)
{
    for (int i = 0; i < MAX_ITEMS; i++) img_free(&f->img[i]);
    SDL_free(f->raw);
    SDL_zero(*f);
}

/* the item table: words up to the first item's data */
static void decode_file(SpriteFile *f, Mode m, FileId id, int first_item, int last_item)
{
    const uint8_t *d = f->raw;
    size_t len = f->len, first = 0;
    int n = 0;
    while ((size_t)(2 * n + 2) <= len && n < MAX_ITEMS && (!first || (size_t)(2 * n) < first)) {
        size_t v = (size_t)word(d, len, 2 * n);
        if (v && (!first || v < first)) first = v;
        n++;
    }
    if (f->count < n) f->count = n;
    Mode dm = m == MODE_CGA1 ? MODE_CGA2 : m;
    for (int i = first_item; i < n && i <= last_item; i++) {
        size_t p = (size_t)word(d, len, 2 * i);
        if (!p || p + 8 > len) continue;
        f->off[i] = (uint32_t)p;
        if (id == F_FONT && i >= 0x97 && i <= 0x9E) continue;   /* the tunes */
        if (id == F_FONT && i >= 0x20 && i <= 0x7A) {
            if (decode_glyph(&f->img[i], &f->adv[i], dm, d, len, p)) f->kind[i] = IT_GLYPH;
            continue;
        }
        if (id == F_PORTRAITS && i >= 1 && i <= 19) {
            if (decode_mask(&f->img[i], &f->colour[i], dm, d, len, p)) f->kind[i] = IT_MASK;
            continue;
        }
        size_t q = (size_t)word(d, len, p);
        bool slot = q >= first && q + 4 < len && d[q] && d[q + 1];
        for (int j = 1; j < 2 && slot; j++) {
            size_t q2 = (size_t)word(d, len, p + 2 * j);
            if (q2 < first || q2 >= len) slot = false;
        }
        if (slot) {
            int h = d[q], bpr = d[q + 1];
            size_t ps = (size_t)word(d, len, q + 2);
            /* the plane size is h * bpr but for one Tandy romance frame (Bk 27): the original draws
             * h rows of bpr bytes, the pixels starting after the stated size */
            if (ps >= (size_t)h * bpr && decode_pixels(&f->img[i], dm, d, len, q + 4 + ps, h, bpr, q + 4)) {
                f->kind[i] = IT_SLOT;
                continue;
            }
        }
        int h = word(d, len, p), bpr = word(d, len, p + 2);
        if (h > 0 && h <= 200 && bpr > 0 && bpr <= 160 && decode_pixels(&f->img[i], dm, d, len, p + 4, h, bpr, 0))
            f->kind[i] = IT_BIG;
    }
}

const Image *asset_item(const Assets *a, Mode m, FileId f, int item)
{
    if (item < 0 || item >= MAX_ITEMS || f < 0 || f >= F_COUNT) return NULL;
    const SpriteFile *sf = &a->set[m].file[f];
    return sf->kind[item] != IT_NONE ? &sf->img[item] : NULL;
}

/* ------------------------------------------------------------------ pictures */

static bool picture_16(Image *im, uint8_t pal[16], Mode m, const uint8_t *raw, size_t len)
{
    if (len < 32) return false;
    size_t n;
    uint8_t *u = dat_lzw(raw + 16, len - 16, &n);
    if (!u || n < 32000) { SDL_free(u); return false; }
    if (!img_alloc(im, SCREEN_W, SCREEN_H, false)) { SDL_free(u); return false; }
    for (int y = 0; y < SCREEN_H; y++)
        for (int x = 0; x < SCREEN_W; x++) {
            int v = 0;
            for (int pl = 0; pl < 4; pl++) v |= px_bit(u + pl * 8000 + y * 40, x) << pl;
            im->pix[y * SCREEN_W + x] = (uint8_t)v;
        }
    for (int i = 0; i < 16; i++) {
        int v = raw[i];
        /* EGA 200-line modes: bit 4 of a palette register is the intensity; the Tandy build
         * maps the same bytes: v & 0Fh, plus 8 if v & 30h */
        pal[i] = m == MODE_EGA ? (uint8_t)((v & 7) | ((v >> 1) & 8)) : (uint8_t)((v & 15) | ((v & 0x30) ? 8 : 0));
    }
    SDL_free(u);
    return true;
}

static bool picture_cga(Image *im, const uint8_t *rows)
{
    if (!img_alloc(im, SCREEN_W, SCREEN_H, false)) return false;
    for (int y = 0; y < SCREEN_H; y++)
        for (int x = 0; x < SCREEN_W; x++) im->pix[y * SCREEN_W + x] = (uint8_t)px_cga(rows + y * 80, x);
    return true;
}

static const uint8_t CGA_PAL[16] = { 0, 2, 4, 6 };   /* palette 0, low intensity, black background */
static const uint8_t CGA_PAL_HI[16] = { 0, 10, 12, 14 };

/* ------------------------------------------------------------------ loading */

/* The last item of a file can reach past its end (BU's lance, 10 bytes): the
 * original reads on into memory. Zeros stand in. */
static void pad(SpriteFile *sf)
{
    uint8_t *r = SDL_realloc(sf->raw, sf->len + 4096);
    if (!r) return;
    SDL_memset(r + sf->len, 0, 4096);
    sf->raw = r;
    sf->len += 4096;
}

static bool load_set(Assets *a, const GameDat *g, Mode m, char *err, size_t errlen)
{
    AssetSet *s = &a->set[m];
    int b = m == MODE_EGA ? 1 : m == MODE_TANDY ? 2 : 0;
    for (int f = 0; f < F_COUNT; f++) {
        SpriteFile *sf = &s->file[f];
        sf->raw = dat_file(g, FILES[b][f], false, &sf->len);
        if (!sf->raw) { SDL_snprintf(err, errlen, "GAME.DAT has no %s", FILES[b][f]); return false; }
        pad(sf);
        decode_file(sf, m, (FileId)f, 0, m == MODE_TANDY && f == F_PORTRAITS ? 127 : MAX_ITEMS - 1);
    }
    if (m == MODE_TANDY) {   /* the Tandy build keeps the portraits (128-149) in BS */
        SpriteFile bs;
        SDL_zero(bs);
        bs.raw = dat_file(g, "BS", false, &bs.len);
        if (bs.raw) {
            pad(&bs);
            decode_file(&bs, m, F_PORTRAITS, 128, MAX_ITEMS - 1);
            SpriteFile *p = &s->file[F_PORTRAITS];
            for (int i = 128; i < MAX_ITEMS; i++) {
                p->kind[i] = bs.kind[i]; p->img[i] = bs.img[i]; SDL_zero(bs.img[i]);
            }
            if (p->count < bs.count) p->count = bs.count;
            file_free(&bs);
        }
    }
    if (m == MODE_EGA) {   /* the flames inside the EGA program (AB 015C, 08B8: file offset - 100h) */
        size_t n;
        uint8_t *ab = dat_file(g, "AB", false, &n);
        static const size_t AT[2] = { 0x15C - 0x100, 0x8B8 - 0x100 };
        SpriteFile *ff = &s->file[F_FONT];
        for (int k = 0; ab && k < 2; k++) {
            size_t o = AT[k];
            if (o + 4 > n) continue;
            int h = ab[o], bpr = ab[o + 1];
            size_t ps = (size_t)(ab[o + 2] | (ab[o + 3] << 8));
            img_free(&ff->img[ITEM_FLAME1 + k]);
            ff->kind[ITEM_FLAME1 + k] = decode_pixels(&ff->img[ITEM_FLAME1 + k], MODE_EGA, ab, n, o + 4 + ps, h, bpr, o + 4)
                                        ? IT_SLOT : IT_NONE;
        }
        SDL_free(ab);
    }
    for (int i = 0; i < PIC_COUNT; i++) {
        char name[3] = { (char)(m == MODE_CGA2 || m == MODE_CGA1 ? 'Q' : 'C'), (char)('A' + i), 0 };
        size_t len;
        uint8_t *raw = dat_file(g, name, true, &len);
        bool ok = false;
        if (raw && (m == MODE_CGA2 || m == MODE_CGA1)) {
            size_t n;
            uint8_t *u = dat_lzw(raw, len, &n);
            if (u && n >= 16000) { ok = picture_cga(&s->pic[i], u); SDL_memcpy(s->pal[i], CGA_PAL, 16); }
            SDL_free(u);
        } else if (raw) {
            ok = picture_16(&s->pic[i], s->pal[i], m, raw, len);
        }
        SDL_free(raw);
        if (!ok) { SDL_snprintf(err, errlen, "GAME.DAT's picture %s could not be read", name); return false; }
    }
    s->loaded = true;
    return true;
}

/* DOS .LIB sprites into a file of the CGA (1987) set: LIB item j (DOC.EXE's
 * 1-based number j + 1, as the booter's tables count) becomes item j + 1, for j in
 * first..last; with clear, the booter's items of that file are dropped first. They
 * are put whole (no mask) unless dos_mask and the others below give them one. */
static bool dos_sprites(Assets *a, const char *lib, FileId f, int first, int last, bool clear)
{
    char path[1200];
    LibFile l;
    if (!find_file(a->dir, lib, path, sizeof path) || !lib_open(&l, path)) return false;
    SpriteFile *sf = &a->set[MODE_CGA1].file[f];
    if (clear)
        for (int i = 0; i < MAX_ITEMS; i++) { img_free(&sf->img[i]); sf->kind[i] = IT_NONE; }
    int n = 0;
    for (int j = first; j <= last && j < l.count && j + 1 < MAX_ITEMS; j++) {
        Image t;
        SDL_zero(t);
        if (lib_sprite(l.item[j], l.item_len[j], &t.w, &t.h, &t.pix)) {
            img_free(&sf->img[j + 1]);
            sf->img[j + 1] = t;
            sf->kind[j + 1] = IT_BIG;
            n++;
        }
    }
    lib_close(&l);
    if (n) a->dos_file[f] = true;
    return n > 0;
}

/* DOC.EXE draws most of its sprites as a pair: the mask ANDed in (0952:000E),
 * then the picture ORed (096B:0000). Item `item` gets item `mask`'s pixels as its
 * mask (the same size, or nothing is done). */
static void dos_mask(Assets *a, FileId f, int item, int mask)
{
    SpriteFile *sf = &a->set[MODE_CGA1].file[f];
    Image *im = &sf->img[item], *mk = &sf->img[mask];
    if (!im->pix || !mk->pix || im->w != mk->w || im->h != mk->h) return;
    SDL_free(im->mask);
    im->mask = SDL_malloc((size_t)im->w * im->h);
    if (im->mask) SDL_memcpy(im->mask, mk->pix, (size_t)im->w * im->h);
}

/* ORed alone (096B:0000): every background bit kept */
static void dos_or(Assets *a, FileId f, int first, int last)
{
    SpriteFile *sf = &a->set[MODE_CGA1].file[f];
    for (int i = first; i <= last && i < MAX_ITEMS; i++) {
        Image *im = &sf->img[i];
        if (!im->pix) continue;
        SDL_free(im->mask);
        im->mask = SDL_malloc((size_t)im->w * im->h);
        if (im->mask) SDL_memset(im->mask, 3, (size_t)im->w * im->h);
    }
}

/* 08F4:000D (the siege's sprites): colour 0 transparent, the others XORed with 1
 * (through the table at CS:0084: each byte XOR 55h, its 01 pixels kept from the
 * screen) */
static void dos_offset(Assets *a, FileId f, int first, int last, int ox, int oy)
{
    SpriteFile *sf = &a->set[MODE_CGA1].file[f];
    for (int i = first; i <= last && i < MAX_ITEMS; i++) { sf->img[i].ox = ox; sf->img[i].oy = oy; }
}

/* LIB item j into item `to` of a file (where the numbers differ from the booter's) */
static void dos_move(Assets *a, FileId f, int to, int from)
{
    SpriteFile *sf = &a->set[MODE_CGA1].file[f];
    if (to == from || !sf->img[from].pix) return;
    img_free(&sf->img[to]);
    sf->img[to] = sf->img[from];
    sf->kind[to] = sf->kind[from];
    SDL_zero(sf->img[from]);
    sf->kind[from] = IT_NONE;
}

static void dos_key1(Assets *a, FileId f, int first, int last)
{
    SpriteFile *sf = &a->set[MODE_CGA1].file[f];
    for (int i = first; i <= last && i < MAX_ITEMS; i++) {
        Image *im = &sf->img[i];
        if (!im->pix) continue;
        SDL_free(im->mask);
        im->mask = SDL_malloc((size_t)im->w * im->h);
        if (im->mask)
            for (int k = 0; k < im->w * im->h; k++) {
                im->mask[k] = im->pix[k] ? 0 : 3;
                if (im->pix[k]) im->pix[k] ^= 1;
            }
    }
}

/* colour 0 transparent (0894:0003, the message boxes' edges) */
static void dos_key0(Assets *a, FileId f, int first, int last)
{
    SpriteFile *sf = &a->set[MODE_CGA1].file[f];
    for (int i = first; i <= last && i < MAX_ITEMS; i++) {
        Image *im = &sf->img[i];
        if (!im->pix) continue;
        SDL_free(im->mask);
        im->mask = SDL_malloc((size_t)im->w * im->h);
        if (im->mask)
            for (int k = 0; k < im->w * im->h; k++) im->mask[k] = im->pix[k] ? 0 : 3;
    }
}

/* the font (0910:0003 puts the NOT of a glyph's bytes, as the booter's CGA program
 * does): glyphs for characters first..last, advancing width / 2 + 1 */
static void dos_glyphs(Assets *a, int first, int last)
{
    SpriteFile *sf = &a->set[MODE_CGA1].file[F_FONT];
    for (int c = first; c <= last && c < MAX_ITEMS; c++) {
        Image *im = &sf->img[c];
        if (!im->pix) continue;
        sf->adv[c] = im->w * 2;
        for (int k = 0; k < im->w * im->h; k++) im->pix[k] ^= 3;
        sf->kind[c] = IT_GLYPH;
    }
}

/* DOC.EXE's data segment (DGROUP 0BCE), for its own tables */
static void load_doc_ds(Assets *a)
{
    char path[1200];
    if (!find_file(a->dir, "DOC.EXE", path, sizeof path)) return;
    size_t n;
    uint8_t *d = SDL_LoadFile(path, &n);
    if (!d) return;
    size_t hdr = n >= 10 ? (size_t)(d[8] | (d[9] << 8)) * 16 : 0, o = hdr + 0xBCE * 16;
    if (n > o && d[0] == 'M' && d[1] == 'Z') {
        a->doc_ds_len = SDL_min(n - o, sizeof a->doc_ds);
        SDL_memcpy(a->doc_ds, d + o, a->doc_ds_len);
        a->have_doc = true;
    }
    SDL_free(d);
}

/* The 1987 DOS version: its own pictures (the .LIB files) and the romance's
 * sprites; its other sprites and its font are not decoded yet, so the booter's CGA
 * ones stand in. */
static void load_dos(Assets *a, const GameDat *g)
{
    AssetSet *s = &a->set[MODE_CGA1];
    char err[64];
    char path[1200];
    if (!load_set(a, g, MODE_CGA1, err, sizeof err)) { SDL_Log("CGA (1987): %s", err); return; }
    /* load_set filled the booter's pictures: replace them with the DOS ones where the files are there */
    uint8_t rows[16000];
    int found = 0;
    for (int i = 0; i < PIC_COUNT; i++) {
        char name[32];
        SDL_snprintf(name, sizeof name, "%s.LIB", DOS_PICS[i].lib);
        LibFile l;
        if (!find_file(a->dir, name, path, sizeof path) || !lib_open(&l, path)) continue;
        int it = DOS_PICS[i].item;
        if (it < l.count && lib_picture(l.item[it], l.item_len[it], rows)) {
            img_free(&s->pic[i]);
            if (picture_cga(&s->pic[i], rows)) found++;
            /* DOC.EXE turns the intensity on for the bedchamber (050E:0626) */
            SDL_memcpy(s->pal[i], i == PIC_BEDCHAMBER ? CGA_PAL_HI : CGA_PAL, 16);
        }
        lib_close(&l);
    }
    if (found < PIC_COUNT) SDL_Log("CGA (1987): %d of the DOS pictures found; the booter's CGA pictures stand in for the rest", found);
    /* the romance (DOC 050E:03BE-0733): the ladies and their eyes; the couple
     * (whole figures, 1-9); the couple at the window (11-20) */
    dos_sprites(a, "LOVE1.LIB", F_LADIES, 1, 24, true);
    dos_sprites(a, "LOVE2.LIB", F_ROMANCE, 1, 9, true);
    dos_sprites(a, "LOVE2.LIB", F_WINDOW, 11, 20, true);
    load_doc_ds(a);
    /* DOCCHARS.LIB holds what the booter split into its font (BA), its map and
     * portraits (BP) and its sword fight (BV), each item at the booter's number */
    if (a->have_doc && dos_sprites(a, "DOCCHARS.LIB", F_FONT, 0, 181, true)) {
        dos_glyphs(a, 0x21, 0x7A);
        dos_key0(a, F_FONT, 0x14, 0x1D);            /* the boxes' edges */
        dos_key0(a, F_FONT, 0x7B, 0x7E);            /* and corners */
        dos_sprites(a, "DOCCHARS.LIB", F_PORTRAITS, 0, 181, true);
        dos_mask(a, F_PORTRAITS, 30, 31);           /* the castles (0423:0384) */
        dos_mask(a, F_PORTRAITS, 35, 36);
        dos_mask(a, F_PORTRAITS, 127, 37);          /* the campaign army */
        dos_sprites(a, "DOCCHARS.LIB", F_SWORD, 0, 181, true);
        dos_or(a, F_SWORD, 160, 179);               /* the fighters, ORed over the hall (050E:0960) */
    }
    if (a->have_doc) dos_sprites(a, "TITLE.LIB", F_CHARS, 7, 11, true);   /* the name plates, the crown */
    /* the tournament: the knights riding in (JOUST1 1-34, put whole, 02D3:0737, at
     * the DOS version's own places and steps: tourney.c), and over the stands (JOUST2 20-39: the
     * booter's BJ 41-60, put as the siege's sprites, 02D3:0BA7); down the lane, the
     * opponent (JOUST2 2-18, put whole, a line higher, 02D3:0A16) and the lance
     * (JOUST1 35, ORed: the booter's BK 20) */
    if (a->have_doc && dos_sprites(a, "JOUST2.LIB", F_TOURN, 20, 39, true)) {
        for (int i = 40; i >= 21; i--) dos_move(a, F_TOURN, i + 20, i);
        dos_key1(a, F_TOURN, 41, 60);
        dos_sprites(a, "JOUST1.LIB", F_TOURN, 1, 34, false);
        dos_sprites(a, "JOUST2.LIB", F_LANE, 2, 18, true);
        dos_offset(a, F_LANE, 3, 19, 0, -1);
        dos_sprites(a, "JOUST1.LIB", F_LANE, 35, 35, false);
        dos_move(a, F_LANE, 20, 36);
        dos_or(a, F_LANE, 20, 20);
    }
    if (a->have_doc) dos_sprites(a, "RAID.LIB", F_END, 5, 9, true);   /* THE END (put whole), the bars, the sparks (XORed) */
    if (a->have_doc && dos_sprites(a, "SIEGE.LIB", F_SIEGE, 2, 51, true))
        dos_key1(a, F_SIEGE, 3, 51);   /* 52, the Greek Fire's flame, is XORed */
}

bool assets_load(Assets *a, const char *dir, char *err, size_t errlen)
{
    SDL_zero(*a);
    SDL_strlcpy(a->dir, dir, sizeof a->dir);
    char path[1200];
    GameDat g;
    if (!find_file(dir, "GAME.DAT", path, sizeof path) || !dat_open(&g, path)) {
        SDL_snprintf(err, errlen, "no GAME.DAT in %s", dir);
        return false;
    }
    size_t n;
    uint8_t *bh = dat_file(&g, "BH", false, &n);
    if (!bh) { SDL_snprintf(err, errlen, "GAME.DAT has no BH"); dat_close(&g); return false; }
    a->bh_len = SDL_min(n, sizeof a->bh);
    SDL_memcpy(a->bh, bh, a->bh_len);
    SDL_free(bh);
    a->bg = dat_file(&g, "BG", false, &a->bg_len);
    bool ok = load_set(a, &g, MODE_EGA, err, errlen) && load_set(a, &g, MODE_CGA2, err, errlen) &&
              load_set(a, &g, MODE_TANDY, err, errlen);
    if (ok) {
        load_dos(a, &g);
        a->tunes = a->set[MODE_EGA].file[F_FONT].raw;     /* the speaker tunes, BB 97h-9Eh */
        a->tunes_len = a->set[MODE_EGA].file[F_FONT].len;
    }
    dat_close(&g);
    if (!ok) assets_free(a);
    return ok;
}

void assets_free(Assets *a)
{
    for (int m = 0; m < MODE_COUNT; m++) {
        for (int i = 0; i < PIC_COUNT; i++) img_free(&a->set[m].pic[i]);
        for (int f = 0; f < F_COUNT; f++) file_free(&a->set[m].file[f]);
    }
    SDL_free(a->bg);
    a->bg = NULL;
    a->tunes = NULL;
}
