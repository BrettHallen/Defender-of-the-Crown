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

/* a loop that only reads the clock (flash_territory's: while (sys_ticks() == t0)
 * sys_check()) waits in real time in sys.c: here the virtual clock moves on
 * 50 us at each read after 64 at the same moment */
uint32_t sys_ticks(void)
{
    static Uint64 last_vt;
    static int same;
    if (vt != last_vt) { last_vt = vt; same = 0; }
    else if (++same > 64) { SDL_DelayNS(50000); last_vt = vt; same = 0; }
    return TICKS_AT_START + (uint32_t)(vt / TICK_NS);
}

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

/* REF_POKE=seconds:addr=word,addr=word,... (hex): words written to the data
 * segment once the clock passes then (the same state for the Next's test).
 * REF_POLL=seconds: from then on, keys read for 1 s without one (polls less
 * than 0.1 s apart) get Enter (its time written to REF_MARKS too), or the
 * next of REF_POLL_KEYS. */
static void pokes_due(void)
{
    static const char *p;
    static int done;
    if (!p) p = getenv("REF_POKE") ? getenv("REF_POKE") : "";
    if (done || !*p || vt < (Uint64)(atof(p) * 1e9)) return;
    done = 1;
    for (const char *s = strchr(p, ':'); s && *s; s = strchr(s, ',')) {
        unsigned a, w;
        if (sscanf(s + 1, "%x=%x", &a, &w) == 2) { ds[a] = w & 0xFF; ds[a + 1] = w >> 8; }
        s++;
    }
}

static void mark(void)
{
    static int n;
    const char *mf = getenv("REF_MARKS");
    FILE *f = mf ? fopen(mf, n++ ? "a" : "w") : NULL;
    if (f) { fprintf(f, "%.6f\n", vt / 1e9); fclose(f); }
}

int bios_key(void)
{
    sys_check();
    keys_due();
    pokes_due();
    int k = 0;
    if (kcount) { k = keys[khead]; khead = (khead + 1) % 64; kcount--; }
    static const char *pf;
    static double since = -1, last = -1;
    if (!pf) pf = getenv("REF_POLL") ? getenv("REF_POLL") : "";
    if (!k && *pf) {
        double t = vt / 1e9;
        if (t - last > 0.1) since = t;
        last = t;
        if (t >= atof(pf) && t - since >= 1.0) {
            static const char *pk;      /* REF_POLL_KEYS=1C,50,...: these first (hex scan codes), then Enter */
            if (!pk) pk = getenv("REF_POLL_KEYS") ? getenv("REF_POLL_KEYS") : "";
            k = KEY_ENTER;
            if (*pk) { k = (int)strtol(pk, NULL, 16); pk = strchr(pk, ','); pk = pk ? pk + 1 : ""; }
            since = t;
            mark();
        }
    }
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
/* REF_AUTO=seconds (to REF_AUTO_END, if set): from then on, a wait for a key
 * (wait_key: the menus) gets Enter after 1 s (its time written to REF_MARKS); REF_DS_AT=n: the data
 * segment to REF_DS at the n-th such Enter (before it), and the run ends there */
static int auto_n;
int wait_key(void)
{
    static const char *af, *dn;
    if (!af) { af = getenv("REF_AUTO") ? getenv("REF_AUTO") : ""; dn = getenv("REF_DS_AT") ? getenv("REF_DS_AT") : ""; }
    Uint64 t0 = vt;
    int k;
    while (!(k = bios_key())) {
        static const char *ae;
        if (!ae) ae = getenv("REF_AUTO_END") ? getenv("REF_AUTO_END") : "";
        if (*af && vt >= (Uint64)(atof(af) * 1e9) && (!*ae || vt < (Uint64)(atof(ae) * 1e9)) && vt - t0 >= 1000000000u) {
            auto_n++;
            if (*dn && auto_n == atoi(dn)) {
                const char *dsf = getenv("REF_DS");
                FILE *f = dsf ? fopen(dsf, "wb") : NULL;
                if (f) { fwrite(ds, 1, 0x6000, f); fclose(f); }
                fprintf(stderr, "the data segment at Enter %d, %.3f s\n", auto_n, vt / 1e9);
                longjmp(out, 1);
            }
            mark();                 /* each such Enter's time, to time the screens between them */
            return KEY_ENTER;
        }
    }
    return translate(k);
}
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
    const char *dsf = getenv("REF_DS");   /* the data segment at the end, to compare the game's state */
    if (dsf && !getenv("REF_DS_AT")) {
        FILE *f = fopen(dsf, "wb");
        if (f) { fwrite(ds, 1, 0x6000, f); fclose(f); }
    }
    fprintf(stderr, "%u frames presented, %u screens recorded, %.1f s\n", frames, records, vt / 1e9);
    assets_free(&A);
    return 0;
}
