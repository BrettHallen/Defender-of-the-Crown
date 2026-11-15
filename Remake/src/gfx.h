/*
 * Defender of the Crown (1986) - remake
 * Nov 2026 using Claude Opus 5.5
 * "Guided" by Brett Hallen
 * Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
 * IBM PC versions by Master Designer Software (1987 DOS) and the booter (GAME.DAT)
 *
 * gfx.h: the screen. The game draws every picture into all four modes at
 * once (each with its own pictures, sprites and the way its program drew
 * them), so Tab can switch modes at any moment. Each mode has the pages the
 * EGA program used: the screen, the back page everything is drawn on
 * (A000:2000), the siege's saved castle (A000:4000) and the map (A000:6000).
 *
 * Positions are the original's: x in 4-pixel units (the CGA program's
 * bytes) unless said otherwise, y in lines. The EGA program put whole
 * bytes of 8 pixels, so its x is rounded down to 8 pixels where it was.
 */
#ifndef DOTC_GFX_H
#define DOTC_GFX_H

#include "assets.h"

#include <SDL3/SDL.h>

enum { PAGE_SCREEN, PAGE_BACK, PAGE_SAVE, PAGE_MAP, PAGE_COUNT };

/* masks of modes, for the few drawings the 1987 DOS version did otherwise */
#define MODES_ALL     ((1u << MODE_COUNT) - 1)
#define MODES_DOS     (1u << MODE_CGA1)
#define MODES_BOOTER  (MODES_ALL & ~MODES_DOS)

#define NUM_SLOTS 12

typedef struct {
    bool     active;
    int      x, y;          /* x in pixels */
    FileId   file;
    int      item;
    int      trim;          /* rows left off the bottom (DS:12A0) */
    int      tandy_dx;      /* pixels added in Tandy mode (the Tandy program placed some sprites elsewhere) */
    int      rows;          /* if > 0, at most this many rows are drawn (the joust's knights behind the barrier) */
    unsigned modes;         /* if not 0, the modes it is drawn in (MODES_...; the romance's per-program frames) */
} Slot;

typedef struct {
    uint8_t  px[MODE_COUNT][PAGE_COUNT][SCREEN_H * SCREEN_W];
    uint8_t  pal_next[MODE_COUNT][16];   /* CS:0103: the palette set_palette will show */
    uint8_t  pal[MODE_COUNT][16];        /* the palette registers */
    uint8_t  pal_slot[MODE_COUNT][4][16];/* CS:E700: kept palettes (slot 0 the map) */
    Slot     slot[NUM_SLOTS];
    /* what each slot covered (sprites_draw saves it, sprites_erase puts it back) */
    uint8_t  saved[MODE_COUNT][NUM_SLOTS][SCREEN_H * SCREEN_W / 2];
    int      sx[MODE_COUNT][NUM_SLOTS], sy[MODE_COUNT][NUM_SLOTS], sw[MODE_COUNT][NUM_SLOTS], sh[MODE_COUNT][NUM_SLOTS];
    bool     saved_ok[MODE_COUNT][NUM_SLOTS];
} Video;

void gfx_init(const Assets *a);
Video *gfx_video(void);
const Assets *gfx_assets(void);

/* the lock the main thread takes to read a finished screen */
void gfx_lock(void);
void gfx_unlock(void);

/* the screen as 0xRRGGBB, for the mode shown */
void gfx_to_rgb(Mode m, uint32_t *out);

/* ---- the original's primitives (AB's names) ---- */
void gfx_show_picture(int pic);                  /* 98C3: palette to CS:0103, the picture to the back page */
void gfx_picture_to(int pic, int page);          /* the picture's planes to a page (9993) */
void gfx_set_palette(void);                      /* 9CA1: show CS:0103 */
void gfx_keep_palette(int pic, int slot);        /* 9C31: a picture's palette to a slot */
void gfx_use_palette(int slot);                  /* 9C5F: a slot to CS:0103 */
void gfx_present(void);                          /* 9902: the back page to the screen */
void gfx_present_bottom(void);                   /* 994A: lines 100-199 */
void gfx_copy_page(int dst, int src);            /* 9A1F */
void gfx_clear_back(int value);                  /* 865F (CGA: the byte; EGA, Tandy: the byte) */
void gfx_fill_rect(int x, int y, int w, int h, int colour);   /* 80EA: the colour word as each program read it */
void gfx_xor_rect(int x, int y, int w, int h, int colour);    /* 8223 */
void gfx_xor_rect3(int x, int y, int w, int h, int cga, int ega, int tandy);   /* the programs passing their own colours */
void gfx_put_sprite(int x, int y, FileId f, int item);        /* 8495: opaque */
void gfx_put_sprite_m(unsigned modes, int x, int y, FileId f, int item);   /* only in those modes */
void gfx_xor_sprite(int x, int y, FileId f, int item);        /* 82D2 */
void gfx_xor_sprite_m(unsigned modes, int x, int y, FileId f, int item);   /* only in those modes */
void gfx_xor_sprite_t(int x, int x_tandy, int y, FileId f, int item);   /* the same, the Tandy program at another x */
void gfx_xor_mask(int x, int y, FileId f, int item);          /* 83E2: a territory's shape (its colour from set_region_colour) */
void gfx_glyph(int xpx, int y, int ch);                       /* 8591: a letter of the font, x in pixels */
int  gfx_glyph_advance(int ch);                               /* the width word / 2 + 1 */
/* the font's pointer for `from` replaced by the one for `to` (-1: put back), as the army tables
 * do with the space (AB 5684, 39C7: 1000:0040 = 1000:007C) */
void gfx_glyph_alias(int from, int to);
void gfx_put_pixel(int page, int xpx, int y, int colour);   /* 87DB/87F8: the colour word as each program wrote it */
void gfx_put_pixel_m(unsigned modes, int page, int xpx, int y, int colour);
int  gfx_get_pixel(Mode m, int page, int xpx, int y);
void gfx_sprites_draw(void);                     /* 88CF */
void gfx_sprites_erase(void);                    /* 8816 */
void gfx_set_region_colour(int item, const int colour[MODE_COUNT]);   /* 9719 */
void gfx_slot_sprite(int xpx, int y, FileId f, int item);     /* a slot sprite drawn once (sprites_draw with nothing to erase) */
/* the fire (AB 18C9, AA 09D2, AC 09FB): EGA and Tandy show flame 1 or 2 (or none: frame 0)
 * at (144, 121) until fire_erase; the CGA program XORs its flame at one of four places
 * (DS:092E, chosen at random: cga_x, cga_y) and leaves it */
void gfx_fire_draw(int frame, int x, int y, int cga_x, int cga_y);
void gfx_fire_erase(void);

#endif
