/*
 * Defender of the Crown (1986) - remake
 * Nov 2026 using Claude Opus 5.5
 * "Guided" by Brett Hallen
 * Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
 * IBM PC versions by Master Designer Software (1987 DOS) and the booter (GAME.DAT)
 *
 * assets.h: the pictures, sprites and fonts of the four video modes, decoded
 * from the player's own files, and the game's data file BH.
 *
 *   MODE_CGA1   the 1987 DOS version (DOC.EXE and its .LIB files), CGA
 *   MODE_CGA2   the booter's CGA program AA (GAME.DAT's Q pictures and BA BD BP ...)
 *   MODE_EGA    the booter's EGA program AB (C pictures, BB BE BL ...)
 *   MODE_TANDY  the booter's Tandy 1000 program AC (C pictures, BC BF BR BS ...)
 *
 * Every image is kept as one byte a pixel: the pixel value the original
 * wrote to video memory (0-3 on CGA, 0-15 on EGA and Tandy), shown through
 * the mode's palette (gfx.h).
 */
#ifndef DOTC_ASSETS_H
#define DOTC_ASSETS_H

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

typedef enum { MODE_CGA1, MODE_CGA2, MODE_EGA, MODE_TANDY, MODE_COUNT } Mode;

#define SCREEN_W 320
#define SCREEN_H 200

typedef struct {
    int      w, h;
    uint8_t *pix;       /* w*h pixel values */
    uint8_t *mask;      /* w*h: the background bits kept (ANDed), 0 = opaque, 3 or 15 = transparent; NULL: drawn whole */
    int      ox, oy;    /* drawn this far from where it is put (the DOS version's sprites where its places differ by a constant) */
} Image;

/* The 20 pictures, A-T (GAME.DAT's C and Q files; the DOS .LIB pictures) */
enum { PIC_SCROLL, PIC_TITLE, PIC_CAST, PIC_INTRO, PIC_CHOOSE, PIC_SHERWOOD, PIC_TRUMPETERS,
       PIC_TOURNAMENT, PIC_LANE, PIC_STANDS, PIC_MAP, PIC_LAND, PIC_PLOTTERS, PIC_NIGHT,
       PIC_HALL, PIC_SIEGE1, PIC_SIEGE2, PIC_LADY, PIC_BEDCHAMBER, PIC_WINDOW, PIC_COUNT };

/* The sprite files by what they hold (EGA / CGA / Tandy names) */
typedef enum {
    F_FONT,       /* BB / BA / BC: the font (20h-7Ah), the box's edges (14h-1Dh, 7Bh-7Eh), the tunes (97h-9Eh) */
    F_CHARS,      /* BE / BD / BF: the character-choice name boxes */
    F_PORTRAITS,  /* BL / BP / BR+BS: territory shapes 1-19, castles, the army, portraits 128-149 */
    F_TOURN,      /* BJ / BT / BX: the tournament from above, the outcome scripts, the stands */
    F_LANE,       /* BK / BU / BY: the opponent charging, the lance */
    F_SWORD,      /* BN / BV / Ba: the sword fight, the battle's knights */
    F_END,        /* BO / BW / Bb: THE END, the strength bars, the sparks */
    F_SIEGE,      /* Bd / Bc / Be: the siege */
    F_LADIES,     /* Bh / Bf / Bj: the ladies */
    F_ROMANCE,    /* Bi / Bg / Bk: the romance */
    F_WINDOW,     /* Bi / Bg / Bl: the romance's last scene, at the window (the Tandy program has it in a file of its own) */
    F_COUNT
} FileId;

#define MAX_ITEMS 256

/* the fire's flames (the CGA and Tandy fonts' items B6h and B7h; the EGA program
 * kept its two in itself, AB 015C and 08B8: put in the same places) */
#define ITEM_FLAME1 0xB6
#define ITEM_FLAME2 0xB7

typedef enum { IT_NONE, IT_BIG, IT_SLOT, IT_MASK, IT_GLYPH } ItemKind;

typedef struct {
    uint8_t *raw;               /* the unpacked file */
    size_t   len;
    int      count;             /* items in the table */
    ItemKind kind[MAX_ITEMS];
    Image    img[MAX_ITEMS];
    int      adv[MAX_ITEMS];    /* glyphs: the width word (the original advances by w/2 + 1) */
    uint16_t colour[MAX_ITEMS]; /* masks: their colour word */
    uint32_t off[MAX_ITEMS];    /* the item's offset in raw (tunes, scripts) */
} SpriteFile;

typedef struct {
    bool       loaded;
    Image      pic[PIC_COUNT];
    uint8_t    pal[PIC_COUNT][16];   /* pixel value -> one of the 16 colours (RGB16) */
    SpriteFile file[F_COUNT];
} AssetSet;

typedef struct {
    AssetSet set[MODE_COUNT];
    uint8_t  bh[65536];          /* BH: the data segment (DS = 1200h) */
    size_t   bh_len;
    uint8_t *bg;                 /* BG: the Tandy music */
    size_t   bg_len;
    uint8_t *tunes;              /* BB: the PC-speaker tunes are items 97h-9Eh */
    size_t   tunes_len;
    char     dir[1024];
    bool     dos_file[F_COUNT];  /* the CGA (1987) set has the DOS version's own sprites for this file (the .LIB files) */
    bool     have_doc;           /* DOC.EXE was found: doc_ds is its data segment */
    uint8_t  doc_ds[65536];
    size_t   doc_ds_len;
} Assets;

/* dir: a folder with GAME.DAT, and/or DOC.EXE's .LIB files (also looked for in
 * subfolders ega/ and cga/). err gets the reason when it fails. */
bool assets_load(Assets *a, const char *dir, char *err, size_t errlen);
void assets_free(Assets *a);
bool assets_dir_ok(const char *dir);

/* an item, or NULL */
const Image *asset_item(const Assets *a, Mode m, FileId f, int item);

extern const char *const MODE_NAMES[MODE_COUNT];   /* "CGA (1987)", "CGA", "EGA", "Tandy" */
bool mode_from_name(const char *s, Mode *m);       /* cga1 cga2 ega tandy */

/* The 16 colours (CGA/EGA/Tandy RGBI) */
extern const uint8_t RGB16[16][3];

#endif
