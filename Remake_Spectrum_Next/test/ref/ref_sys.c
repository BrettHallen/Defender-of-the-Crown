/*
 * Defender of the Crown (1986) - Spectrum Next remake
 * Nov 2026 using Claude Opus 5.5
 * "Guided" by Brett Hallen
 *
 * test/ref/ref_sys.c: the reference. The Mac remake's own game, drawing,
 * asset and sound code (Remake/src, all but main.c, sys.c and icon.c), built
 * with test/ref/SDL3/SDL.h and this file in place of sys.c: the same waits
 * and keys as sys.c, but on one thread and a virtual clock, so a run is the
 * same every time. Every screen the game presents in Tandy mode is recorded,
 * so the Next's port can be checked against it.
 *
 *   ref GAME-FOLDER OUT.REC SECONDS [t:KEY ...]
 *
 * runs the game from the start for SECONDS of game time, pressing each KEY
 * (a PC scan code in hex) at t seconds. OUT.REC gets one record for each
 * change of the Tandy screen: "DREC", then for each: the time (u64, ns), the
 * 16 palette registers (Tandy colours 0-15), the 320x200 pixels (one byte a
 * pixel).
 */
#include "../../../Remake/src/assets.h"
#include "../../../Remake/src/gfx.h"
#include "../../../Remake/src/sys.h"
#include "../../../Remake/src/sound.h"
#include "../../../Remake/src/game.h"
#include <SDL3/SDL.h>

#define TICK_NS 54925416ull   /* 65536 / 1193182 s: the BIOS clock */
#define RETRACE_NS (SDL_NS_PER_SECOND / 60)

static Uint64 vt;                  /* the virtual clock, ns */
static Uint64 limit;
static uint32_t ticks_done;
static jmp_buf out, *skip_to;
static bool skip_armed, skip_hit;
static struct { Uint64 t; int key; } script[256];
static int script_n, script_i;
static int keys[64], khead, kcount;
static FILE *rec;
static uint8_t last_px[SCREEN_W * SCREEN_H], last_pal[16];
static bool have_last;
static unsigned frames, records;

Uint64 SDL_GetTicksNS(void) { return vt; }

static void keys_due(void)
{
    while (script_i < script_n && script[script_i].t <= vt) {
        int k = script[script_i++].key;
        if (k == KEY_SKIP && skip_armed) { skip_hit = true; continue; }
        if (kcount < 64) { keys[(khead + kcount) % 64] = k; kcount++; }
    }
}

void SDL_DelayNS(Uint64 ns)
{
    vt += ns;
    while (ticks_done < vt / TICK_NS) { ticks_done++; sound_tick(); }
    keys_due();
}

/* the BIOS count since midnight, as sys.c: here always from noon, so the
 * game's random numbers (seeded from it) are the same every run */
#define TICKS_AT_START 786520u

uint32_t sys_ticks(void) { return TICKS_AT_START + (uint32_t)(vt / TICK_NS); }

void sys_check(void)
{
    if (vt >= limit) longjmp(out, 1);
    if (skip_hit && skip_to) {
        jmp_buf *to = skip_to;
        sys_skip_disarm();
        longjmp(*to, 1);
    }
}

void sys_skip_arm(jmp_buf *to) { skip_to = to; skip_hit = false; skip_armed = true; }
void sys_skip_disarm(void) { skip_armed = false; skip_hit = false; skip_to = NULL; }

void sys_frame_done(void)
{
    frames++;
    const Video *v = gfx_video();
    const uint8_t *px = v->px[MODE_TANDY][PAGE_SCREEN];
    const uint8_t *pal = v->pal[MODE_TANDY];
    if (have_last && !memcmp(px, last_px, sizeof last_px) && !memcmp(pal, last_pal, 16)) return;
    memcpy(last_px, px, sizeof last_px);
    memcpy(last_pal, pal, 16);
    have_last = true;
    fwrite(&vt, 8, 1, rec);
    fwrite(pal, 1, 16, rec);
    fwrite(px, 1, sizeof last_px, rec);
    records++;
}

/* the rest of sys.h, as sys.c */
void sys_start(void (*game)(void)) { (void)game; }
void sys_stop(void) {}
bool sys_running(void) { return true; }
void sys_key(int scan) { (void)scan; }
uint32_t sys_frames(void) { return frames; }
void sys_set_speed(double s) { (void)s; }

int bios_key(void)
{
    sys_check();
    keys_due();
    int k = 0;
    if (kcount) { k = keys[khead]; khead = (khead + 1) % 64; kcount--; }
    if (!k) SDL_DelayNS(200000);
    return k;
}

static int translate(int k)
{
    k &= 0xFF;
    if (k == KEY_KP_PLUS || k == KEY_F1) k = KEY_ENTER;
    return k;
}

int get_key(void) { return translate(bios_key()); }
int wait_key(void) { int k; while (!(k = bios_key())) {} return translate(k); }
void flush_keys(void) { while (get_key()) {} }
void sys_dos_ticks(bool on) { (void)on; }

int wait_ticks(int n)
{
    uint32_t last = sys_ticks() + 1;
    int k = 0;
    while (n) {
        k = get_key();
        uint32_t t = sys_ticks();
        if (t != last) { last = t; n--; }
    }
    return k;
}

void delay_ticks(int n)
{
    uint32_t last = sys_ticks() + 1;
    while (n) {
        sys_check();
        uint32_t t = sys_ticks();
        if (t != last) { last = t; n--; }
        else SDL_DelayNS(500000);
    }
}

void sys_retrace(void)
{
    sys_check();
    SDL_DelayNS((vt / RETRACE_NS + 1) * RETRACE_NS - vt);
}

static Assets A;

int main(int argc, char **argv)
{
    char err[256];
    if (argc < 4) { fprintf(stderr, "usage: ref GAME-FOLDER OUT.REC SECONDS [t:KEY ...]\n"); return 1; }
    if (!assets_load(&A, argv[1], err, sizeof err)) { fprintf(stderr, "%s\n", err); return 1; }
    limit = (Uint64)(atof(argv[3]) * 1e9);
    for (int i = 4; i < argc && script_n < 256; i++) {
        script[script_n].t = (Uint64)(atof(argv[i]) * 1e9);
        script[script_n].key = (int)strtol(strchr(argv[i], ':') + 1, NULL, 16);
        script_n++;
    }
    rec = fopen(argv[2], "wb");
    if (!rec) { perror(argv[2]); return 1; }
    fwrite("DREC", 1, 4, rec);
    gfx_init(&A);
    sound_data(A.tunes, A.tunes_len, A.bg, A.bg_len);
    if (setjmp(out) == 0) game_main();
    fclose(rec);
    fprintf(stderr, "%u frames presented, %u screens recorded, %.1f s\n", frames, records, vt / 1e9);
    assets_free(&A);
    return 0;
}
