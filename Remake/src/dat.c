/*
 * Defender of the Crown (1986) - remake
 * Nov 2026 using Claude Opus 5.5
 * "Guided" by Brett Hallen
 * Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
 * IBM PC versions by Master Designer Software (1987 DOS) and the booter (GAME.DAT)
 *
 * dat.c: GAME.DAT and the .LIB files (see dat.h).
 */
#include "dat.h"

#include <SDL3/SDL.h>

#define DISK_SIZE 0x5A000   /* a 360K floppy: 40 tracks, 2 sides, 9 sectors of 512 bytes */

bool dat_open(GameDat *g, const char *path)
{
    SDL_zero(*g);
    g->data = SDL_LoadFile(path, &g->size);
    if (!g->data) return false;
    if (g->size < 2 * DISK_SIZE) { dat_close(g); return false; }
    return true;
}

void dat_close(GameDat *g)
{
    SDL_free(g->data);
    SDL_zero(*g);
}

/* Track 0 sector 9 of each disk is its directory: 6-byte entries (two-letter
 * name, first sector, sector count), ended by a 0 byte. */
static bool find(const GameDat *g, const char *name, size_t *start, size_t *bytes)
{
    for (int disk = 0; disk < 2; disk++) {
        const uint8_t *dir = g->data + disk * DISK_SIZE + 8 * 512;
        for (int o = 0; o + 6 <= 512 && dir[o]; o += 6) {
            if (dir[o] != (uint8_t)name[0] || dir[o + 1] != (uint8_t)name[1]) continue;
            size_t s = dir[o + 2] | (dir[o + 3] << 8), c = dir[o + 4] | (dir[o + 5] << 8);
            *start = disk * DISK_SIZE + s * 512;
            *bytes = c * 512;
            if (*start + *bytes > g->size) return false;
            return true;
        }
    }
    return false;
}

uint8_t *dat_lzw(const uint8_t *src, size_t n, size_t *len)
{
    size_t cap = 65536, out_n = 0;
    uint8_t *out = SDL_malloc(cap);
    static uint16_t prefix[4096];
    static uint8_t suffix[4096];
    uint8_t stack[4096];
    if (!out) return NULL;
    size_t bit = 0;
    int width = 9, next = 0x102, limit = 0x200, old = -1, first = 0;
    for (;;) {
        if (bit + (size_t)width > n * 8) break;
        size_t b = bit >> 3;
        uint32_t v = src[b] | (b + 1 < n ? src[b + 1] << 8 : 0) | (b + 2 < n ? src[b + 2] << 16 : 0);
        int c = (int)((v >> (bit & 7)) & ((1u << width) - 1));
        bit += width;
        if (c == 0x101) break;
        if (c == 0x100) {
            width = 9; limit = 0x200; next = 0x102;
            if (bit + (size_t)width > n * 8) break;
            b = bit >> 3;
            v = src[b] | (b + 1 < n ? src[b + 1] << 8 : 0) | (b + 2 < n ? src[b + 2] << 16 : 0);
            c = (int)((v >> (bit & 7)) & ((1u << width) - 1));
            bit += width;
            if (out_n + 1 > cap) { cap *= 2; uint8_t *o2 = SDL_realloc(out, cap); if (!o2) break; out = o2; }
            out[out_n++] = (uint8_t)c;
            old = c; first = c;
            continue;
        }
        if (old < 0) break;
        int sp = 0, cc = c;
        if (c >= next) { stack[sp++] = (uint8_t)first; cc = old; }   /* KwKwK */
        while (cc > 0xFF && sp < 4095) { stack[sp++] = suffix[cc]; cc = prefix[cc]; }
        stack[sp++] = (uint8_t)cc;
        first = cc;
        if (out_n + sp > cap) {
            while (out_n + sp > cap) cap *= 2;
            uint8_t *o2 = SDL_realloc(out, cap);
            if (!o2) break;
            out = o2;
        }
        while (sp) out[out_n++] = stack[--sp];
        if (next < 4096) { prefix[next] = (uint16_t)old; suffix[next] = (uint8_t)first; next++; }
        old = c;
        if (next >= limit && width < 12) { width++; limit <<= 1; }
    }
    *len = out_n;
    return out;
}

uint8_t *dat_file(const GameDat *g, const char *name, bool raw, size_t *len)
{
    size_t start, bytes;
    if (!g->data || !find(g, name, &start, &bytes)) return NULL;
    const uint8_t *p = g->data + start;
    if (raw || ((p[0] | (p[1] << 8)) & 0x1FF) != 0x100) {   /* not LZW: as it is */
        uint8_t *out = SDL_malloc(bytes);
        if (out) SDL_memcpy(out, p, bytes);
        *len = bytes;
        return out;
    }
    return dat_lzw(p, bytes, len);
}

/* ------------------------------------------------------------------ .LIB */

bool lib_open(LibFile *l, const char *path)
{
    SDL_zero(*l);
    size_t n;
    uint8_t *d = SDL_LoadFile(path, &n);
    if (!d) return false;
    if (n < 9 || d[0] != 0xFD) { SDL_free(d); return false; }
    size_t ln = d[5] | (d[6] << 8);
    if (7 + ln > n) ln = n - 7;
    l->data = d;
    l->size = ln;
    const uint8_t *p = d + 7;
    int cnt = p[0] | (p[1] << 8);
    if (cnt > 256) cnt = 256;
    l->count = cnt;
    /* item offsets are in words from the data's start; an item ends where the next one starts */
    for (int i = 0; i < cnt; i++) {
        size_t o = (size_t)(p[2 + 2 * i] | (p[3 + 2 * i] << 8)) * 2;
        if (!o || o >= ln) continue;
        size_t e = ln;
        for (int j = 0; j < cnt; j++) {
            size_t o2 = (size_t)(p[2 + 2 * j] | (p[3 + 2 * j] << 8)) * 2;
            if (o2 > o && o2 < e) e = o2;
        }
        l->item[i] = p + o;
        l->item_len[i] = e - o;
    }
    return true;
}

void lib_close(LibFile *l)
{
    SDL_free(l->data);
    SDL_zero(*l);
}

/* DOC.EXE 0946:0000. c < 80h: c+1 literal pixels, 2 bits at a time from literal
 * bytes (a partly used byte carries over); c >= 80h: a run of colour c & 3,
 * count (c >> 2) & 0Fh (with bit 6: * 256 + the next byte), + 1 pixels. */
bool lib_sprite(const uint8_t *item, size_t n, int *w, int *h, uint8_t **pix)
{
    if (!item || n < 4 || (n >= 8 && SDL_memcmp(item, "COMPRESS", 8) == 0)) return false;
    int wb = item[0] | (item[1] << 8), hh = item[2] | (item[3] << 8);
    int bpr = wb / 8, wp = bpr * 4;
    if (bpr <= 0 || hh <= 0 || hh > 200 || wp > 320 || 4 + (size_t)bpr * hh > n) return false;
    uint8_t *p = SDL_malloc((size_t)wp * hh);
    if (!p) return false;
    for (int y = 0; y < hh; y++)
        for (int x = 0; x < wp; x++) p[y * wp + x] = (item[4 + y * bpr + (x >> 2)] >> (6 - 2 * (x & 3))) & 3;
    *w = wp; *h = hh; *pix = p;
    return true;
}

bool lib_picture(const uint8_t *item, size_t n, uint8_t out[16000])
{
    if (!item || n < 8 || SDL_memcmp(item, "COMPRESS", 8) != 0) return false;
    size_t si = 8;
    int npx = 0, acc = 0, lit = 0, left = 0;
    SDL_memset(out, 0, 16000);
    while (npx < 64000 && si < n) {
        int c = item[si++];
        if (c < 0x80) {
            for (int k = 0; k <= c && npx < 64000; k++) {
                if (!left) { if (si >= n) return true; lit = item[si++]; left = 4; }
                left--;
                acc = ((acc << 2) | ((lit >> (2 * left)) & 3)) & 0xFF;
                if (++npx % 4 == 0) out[npx / 4 - 1] = (uint8_t)acc;
            }
        } else {
            int col = c & 3, cnt = (c >> 2) & 0x0F;
            if (c & 0x40) { if (si >= n) return true; cnt = cnt * 256 + item[si++]; }
            for (int k = 0; k <= cnt && npx < 64000; k++) {
                acc = ((acc << 2) | col) & 0xFF;
                if (++npx % 4 == 0) out[npx / 4 - 1] = (uint8_t)acc;
            }
        }
    }
    return true;
}
