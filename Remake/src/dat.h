/*
 * Defender of the Crown (1986) - remake
 * Nov 2026 using Claude Opus 5.5
 * "Guided" by Brett Hallen
 * Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
 * IBM PC versions by Master Designer Software (1987 DOS) and the booter (GAME.DAT)
 *
 * dat.h: the original files. GAME.DAT (the booter's two floppy images: a
 * directory on each disk, LZW-packed files) and the 1987 DOS version's .LIB
 * files (BSAVE images with COMPRESS pictures and 2-bit sprites).
 * See Analysis/DOTC_file_reference.md.
 */
#ifndef DOTC_DAT_H
#define DOTC_DAT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct {
    uint8_t *data;      /* the whole of GAME.DAT */
    size_t   size;
} GameDat;

bool     dat_open(GameDat *g, const char *path);
void     dat_close(GameDat *g);
/* a file by its two-letter name ("BH", "Bd" ...), unpacked (LZW) unless raw;
 * C pictures are raw: 16 palette bytes, then LZW. Caller frees with SDL_free. */
uint8_t *dat_file(const GameDat *g, const char *name, bool raw, size_t *len);
/* LZW as GameSYS 065D and AB 9ABB: 9-12 bit codes, LSB first, 100h clear, 101h end */
uint8_t *dat_lzw(const uint8_t *src, size_t n, size_t *len);

/* A DOS .LIB file: items (NULL for empty ones) */
typedef struct {
    uint8_t *data;      /* the BSAVE body */
    size_t   size;
    int      count;
    const uint8_t *item[256];
    size_t   item_len[256];
} LibFile;

bool lib_open(LibFile *l, const char *path);
void lib_close(LibFile *l);
/* a COMPRESS picture to 200 rows of 80 bytes (CGA 2 bits a pixel); false if not one */
bool lib_picture(const uint8_t *item, size_t n, uint8_t out[16000]);

#endif
