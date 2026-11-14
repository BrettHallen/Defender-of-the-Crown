/*
 * Defender of the Crown (1986) - remake
 * Nov 2026 using Claude Opus 5.5
 * "Guided" by Brett Hallen
 * Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
 * IBM PC versions by Master Designer Software (1987 DOS) and the booter (GAME.DAT)
 *
 * sound.c: the PC speaker, its tunes (AB 9520-96FF) and the Tandy music
 * driver (AC 7444-7C53, as Sound/tandymusic.py), played through SDL3 audio.
 */
#include "sound.h"

#include <SDL3/SDL.h>

#define RATE    44100
#define PIT_HZ  1193182.0
#define CHIP_HZ 3579545.0
#define PC_LEVEL 0.20f
#define SN_LEVEL 0.12f

/* the speaker tunes' player state (the header the int 1Ch handler keeps) */
typedef struct {
    int flags, index, ticks;
} TuneState;

/* the Tandy driver (AC 75F4 and its helpers) */
typedef struct {
    bool     playing;
    int      song;
    int      regs[8];                 /* tone 0-2, noise control, attenuation 0-3 */
    int      latch;
    long     loop_at;                 /* -1: none */
    int      tempo;
    int      inst[4][6];
    bool     has_inst[4];
    int      ptr[4], dur[4], state[4], active[4], vol[4], rel[4], tone[4], vib[4], vsub[4], vph[4];
    int      subtick;
} Tandy;

static struct {
    SDL_AudioStream *stream;
    SDL_Mutex *lock;
    const uint8_t *tunes; size_t tunes_len;
    const uint8_t *bg; size_t bg_len;
    int        tune;                  /* 97h-9Eh, or 0 */
    TuneState  t;                     /* the game's (keeps time) */
    TuneState  aud;                   /* the one heard on the speaker (restarted by Tab) */
    bool       tandy;                 /* the Tandy chip is heard */
    int        tone_div;              /* speaker_tone, or 0 */
    int        click_div, click_left;   /* snd_speaker_click: the divisor, samples left */
    Tandy      sn;
    double     pc_phase, sn_phase[3], noise_phase;
    int        lfsr;
    double     int_acc;               /* the Tandy driver's interrupts, in samples */
    float      hp_x, hp_y;
} S = { .lfsr = 0x4000 };

static int w16(const uint8_t *b, size_t len, size_t o) { return o + 1 < len ? b[o] | (b[o + 1] << 8) : 0; }

/* ------------------------------------------------------------------ the Tandy driver */

static int bgw(size_t o) { return w16(S.bg, S.bg_len, o); }

static void sn_out(Tandy *d, int b)            /* port C0h */
{
    b &= 0xFF;
    if (b & 0x80) {
        d->latch = (b >> 4) & 7;
        int ch = d->latch >> 1, typ = d->latch & 1;
        if (typ) d->regs[4 + ch] = b & 15;
        else if (ch == 3) d->regs[3] = b & 7;
        else d->regs[ch] = (d->regs[ch] & 0x3F0) | (b & 15);
    } else {
        int ch = d->latch >> 1, typ = d->latch & 1;
        if (typ) d->regs[4 + ch] = b & 15;
        else if (ch == 3) d->regs[3] = b & 7;
        else d->regs[ch] = (d->regs[ch] & 15) | ((b & 0x3F) << 4);
    }
}

static void sn_silence(Tandy *d)               /* 7C78 */
{
    sn_out(d, 0x9F); sn_out(d, 0xBF); sn_out(d, 0xDF); sn_out(d, 0xFF);
    for (int v = 0; v < 4; v++) { d->state[v] = 5; d->active[v] = 0; }
}

static void sn_stop(Tandy *d) { sn_silence(d); d->playing = false; }   /* 7C53 */

static void sn_song_at(Tandy *d, long bx)      /* 747A, 74BA */
{
    sn_stop(d);
    if (bgw(bx) == 0xFFFF) return;
    if (bgw(bx) == 0xFFFE) { d->loop_at = bx; bx += 2; }
    d->tempo = bgw(bx);
    for (int v = 0; v < 4; v++) {
        long p = bgw(bx + 2 + 2 * v);
        if (bgw(p) == 0) { d->active[v] = 0; d->has_inst[v] = false; }
        else {
            for (int k = 0; k < 6; k++) d->inst[v][k] = bgw(p + 2 * k);
            d->has_inst[v] = true;
            d->active[v] = 1;
            p += 12;
        }
        d->ptr[v] = (int)p;
        d->vol[v] = 15; d->dur[v] = 1; d->rel[v] = 0; d->tone[v] = 0; d->vib[v] = 0; d->vsub[v] = 0; d->vph[v] = 0;
    }
    d->subtick = 1;
    d->playing = true;
}

static void sn_start(Tandy *d, int song)        /* 7444 */
{
    d->loop_at = -1;
    d->song = song;
    if (!S.bg || 2 * song + 2 > (int)S.bg_len) return;
    sn_song_at(d, bgw(2 * song));
}

static void sn_tone(Tandy *d, int v, int n)    /* 7820 */
{
    n &= 0xFFFF;
    sn_out(d, (n & 15) | (0x80 + 0x20 * v));
    sn_out(d, (n >> 4) & 0xFF);
}

/* 0: go on, 1: the song restarted, 2: stopped */
static int sn_next_event(Tandy *d, int v)
{
    int bx = d->ptr[v];
    int du = bgw(bx);
    d->dur[v] = du;
    if (du == 0xFFFF) {
        int nxt = bgw(bx + 2);
        bool restart = v < 2 ? nxt == 0xFFFE : nxt != 0xFFFE;   /* voices 2 and 3 test the other way round */
        if (restart && d->loop_at >= 0) { sn_song_at(d, d->loop_at); return 1; }
        sn_stop(d);
        return 2;
    }
    bx += 2;
    int n = bgw(bx);
    if (n == 0xFFFA) { d->inst[v][5] = 0xFFFF; bx += 2; }
    if (n == 0) d->state[v] = 4;
    else {
        d->tone[v] = n;
        sn_tone(d, v, n);
        d->state[v] = 1;
        d->vib[v] = d->inst[v][5];
        d->vph[v] = 0;
    }
    d->ptr[v] = bx + 2;
    return 0;
}

static void sn_vibrato(Tandy *d, int v)        /* 7A83 */
{
    d->vib[v] = (d->vib[v] - 1) & 0xFFFF;
    if (d->vib[v] != 0 && d->vib[v] < 0x8000) return;
    d->vib[v] = (d->vib[v] + 1) & 0xFFFF;
    if (d->vsub[v] != 2) { d->vsub[v]++; return; }
    d->vsub[v] = 0;
    d->vph[v]++;
    if (d->vph[v] < 3) d->tone[v]++;
    else {
        if (d->vph[v] == 4) d->vph[v] = 0;
        d->tone[v]--;
    }
    sn_tone(d, v, d->tone[v]);
}

static int clamp15(int x)                      /* 7A6F */
{
    x &= 0xFFFF;
    if (x >= 0x8000) x -= 0x10000;
    return x < 0 ? 0 : x > 15 ? 15 : x;
}

static void sn_interrupt(Tandy *d)             /* 75F4 */
{
    if (!d->playing) return;
    if (--d->subtick == 0) {
        d->subtick = 4;
        for (int v = 0; v < 4; v++) {
            if (!d->playing) break;
            if (!d->active[v]) continue;
            d->dur[v] = (d->dur[v] - 1) & 0xFFFF;
            if (d->dur[v] == 0) { if (sn_next_event(d, v) == 1) return; }
            else if (d->inst[v][5] != 0xFFFF) sn_vibrato(d, v);
        }
        return;
    }
    for (int v = 0; v < 4; v++) {                /* 7870: the envelopes */
        int s = d->state[v];
        if (s == 3 || s == 5) continue;
        int a = d->has_inst[v] ? d->inst[v][0] : 0, dcy = d->has_inst[v] ? d->inst[v][1] : 0;
        int sus = d->has_inst[v] ? d->inst[v][2] : 0, rstep = d->has_inst[v] ? d->inst[v][3] : 0;
        int rint = d->has_inst[v] ? d->inst[v][4] : 0;
        int ax = d->vol[v];
        if (s == 1) {
            ax = clamp15(ax - a); d->vol[v] = ax;
            if (ax == 0) d->state[v] = 2;
        } else if (s == 2) {
            ax += dcy; d->vol[v] = ax; ax = clamp15(ax);
            if (ax >= sus) { ax = sus; d->vol[v] = sus; d->state[v] = 3; }
        } else {
            if (--d->rel[v] > 0) continue;
            d->rel[v] = rint;
            ax += rstep; d->vol[v] = ax; ax = clamp15(ax);
            if (ax >= 15) { d->state[v] = 5; ax = 15; }
        }
        sn_out(d, (ax & 15) | (0x90 + 0x20 * v));
    }
}

/* ------------------------------------------------------------------ generator */

static float square(double *ph, double hz)
{
    if (hz <= 20.0 || hz > RATE / 2.0) return 0.0f;
    *ph += hz / RATE;
    if (*ph >= 1.0) *ph -= SDL_floor(*ph);
    return *ph < 0.5 ? 1.0f : -1.0f;
}

static float sn_amp(int att) { return att >= 15 ? 0.0f : SN_LEVEL * SDL_powf(10.0f, -(float)att / 10.0f); }

static int speaker_divisor(void)
{
    if (S.tone_div) return S.tone_div;
    if (S.tandy || !S.tune || !S.tunes) return 0;
    if (!(S.aud.flags & 0x8000) || (S.aud.flags & 0x2000) || S.aud.index <= 0) return 0;
    size_t base = (size_t)w16(S.tunes, S.tunes_len, 2 * S.tune);
    return w16(S.tunes, S.tunes_len, base + 4 + 4 * S.aud.index);
}

static void render(float *buf, int n)
{
    SDL_LockMutex(S.lock);
    int div = speaker_divisor();
    double pc_hz = div > 0 ? PIT_HZ / div : 0.0;
    double per_int = S.sn.tempo > 0 ? S.sn.tempo / PIT_HZ * RATE : 0.0;
    for (int i = 0; i < n; i++) {
        float v = 0.0f;
        if (pc_hz > 0.0) v += PC_LEVEL * square(&S.pc_phase, pc_hz);
        else if (S.click_left > 0) { S.click_left--; v += PC_LEVEL * square(&S.pc_phase, PIT_HZ / S.click_div); }
        if (S.tandy && S.sn.playing && per_int > 0.0) {
            S.int_acc += 1.0;
            while (S.int_acc >= per_int) { S.int_acc -= per_int; sn_interrupt(&S.sn); }
        }
        if (S.tandy) {
            for (int c = 0; c < 3; c++) {
                int nn = S.sn.regs[c] ? S.sn.regs[c] : 1024;
                v += sn_amp(S.sn.regs[4 + c]) * square(&S.sn_phase[c], CHIP_HZ / 32.0 / nn);
            }
        }
        float y = 0.997f * (S.hp_y + v - S.hp_x);   /* a high-pass, as the speaker cone */
        S.hp_x = v; S.hp_y = y;
        buf[i] = y;
    }
    SDL_UnlockMutex(S.lock);
}

static void SDLCALL callback(void *ud, SDL_AudioStream *stream, int additional, int total)
{
    (void)ud; (void)total;
    float buf[1024];
    int want = additional / (int)sizeof(float);
    while (want > 0) {
        int k = SDL_min(want, (int)SDL_arraysize(buf));
        render(buf, k);
        SDL_PutAudioStreamData(stream, buf, k * (int)sizeof(float));
        want -= k;
    }
}

bool sound_init(void)
{
    if (!S.lock) S.lock = SDL_CreateMutex();
    S.sn.loop_at = -1;
    sn_silence(&S.sn);
    if (!SDL_InitSubSystem(SDL_INIT_AUDIO)) { SDL_Log("No audio: %s", SDL_GetError()); return false; }
    SDL_AudioSpec spec = { SDL_AUDIO_F32, 1, RATE };
    S.stream = SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, callback, NULL);
    if (!S.stream) { SDL_Log("No audio device: %s", SDL_GetError()); return false; }
    SDL_ResumeAudioStreamDevice(S.stream);
    return true;
}

void sound_quit(void)
{
    if (S.stream) SDL_DestroyAudioStream(S.stream);
    S.stream = NULL;
}

void sound_data(const uint8_t *tunes, size_t tunes_len, const uint8_t *bg, size_t bg_len)
{
    if (!S.lock) S.lock = SDL_CreateMutex();
    SDL_LockMutex(S.lock);
    S.tunes = tunes; S.tunes_len = tunes_len;
    S.bg = bg; S.bg_len = bg_len;
    SDL_UnlockMutex(S.lock);
}

/* ------------------------------------------------------------------ the tunes */

static int tune_count(void)
{
    if (!S.tunes || !S.tune) return 0;
    size_t base = (size_t)w16(S.tunes, S.tunes_len, 2 * S.tune);
    return w16(S.tunes, S.tunes_len, base + 2);
}

static int tune_note_ticks(int index)
{
    size_t base = (size_t)w16(S.tunes, S.tunes_len, 2 * S.tune);
    return w16(S.tunes, S.tunes_len, base + 6 + 4 * index);
}

/* the int 1Ch handler (AB 968A) for one player */
static void tick_player(TuneState *t)
{
    if (!(t->flags & 0x8000)) { t->flags |= 1; return; }   /* stopped: flags = 1 (speaker off) */
    t->ticks--;
    if (t->ticks > 0) return;
    int bx = t->index + 1;
    if (bx > tune_count()) {
        if (!(t->flags & 0x4000)) { t->flags = 1; return; }
        bx = 1;
    }
    t->index = bx;
    t->ticks = tune_note_ticks(bx);
    t->flags &= ~1;
}

static const int TANDY_SONG[8] = { 5, 6, 4, 2, 0, 3, 7, 1 };   /* tunes 97h-9Eh */

static bool audible(const TuneState *t) { return (t->flags & 0x8000) && !(t->flags & 0x2000) && !(t->flags & 1); }

void sound_tick(void)
{
    if (!S.lock) return;
    SDL_LockMutex(S.lock);
    if (S.tune) {
        tick_player(&S.t);
        if (S.t.flags & 1) { S.aud = S.t; }            /* the game's tune ended or stopped: so does the heard one */
        else tick_player(&S.aud);
    }
    SDL_UnlockMutex(S.lock);
}

void snd_play_tune(int tune, int flags)
{
    SDL_LockMutex(S.lock);
    S.tune = tune;
    S.t.index = 0; S.t.ticks = 0; S.t.flags = flags;
    S.aud = S.t;
    if (S.tandy) {
        if (flags & 0x8000) {
            int song = TANDY_SONG[(tune - 0x97) & 7];
            if (!(flags & 0x2000) && !(S.sn.playing && S.sn.song == song)) { sn_start(&S.sn, song); S.int_acc = 0; }
            if (flags & 0x2000) sn_stop(&S.sn);
        } else {
            sn_stop(&S.sn);
        }
    }
    SDL_UnlockMutex(S.lock);
}

int snd_tune_flags(void) { SDL_LockMutex(S.lock); int f = S.t.flags; SDL_UnlockMutex(S.lock); return f; }
int snd_tune_index(void) { SDL_LockMutex(S.lock); int i = S.t.index; SDL_UnlockMutex(S.lock); return i; }

void snd_tune_clear_loop(void)
{
    SDL_LockMutex(S.lock);
    S.t.flags &= ~0x4000;
    S.aud.flags &= ~0x4000;
    SDL_UnlockMutex(S.lock);
}

void snd_speaker_tone(int divisor) { SDL_LockMutex(S.lock); S.tone_div = divisor; SDL_UnlockMutex(S.lock); }
void snd_speaker_off(void)          { SDL_LockMutex(S.lock); S.tone_div = 0; SDL_UnlockMutex(S.lock); }
void snd_speaker_click(int divisor, int ms)
{
    if (divisor <= 0) return;
    SDL_LockMutex(S.lock);
    S.click_div = divisor; S.click_left = RATE * ms / 1000;
    SDL_UnlockMutex(S.lock);
}

void snd_use_tandy(bool tandy)
{
    SDL_LockMutex(S.lock);
    if (tandy != S.tandy) {
        S.tandy = tandy;
        if (tandy) {
            if (S.tune && audible(&S.t)) { sn_start(&S.sn, TANDY_SONG[(S.tune - 0x97) & 7]); S.int_acc = 0; }
        } else {
            sn_stop(&S.sn);
            if (S.tune && audible(&S.t)) { S.aud = S.t; S.aud.index = 0; S.aud.ticks = 0; }   /* from the top */
        }
    }
    SDL_UnlockMutex(S.lock);
}

bool snd_tandy_used(void) { return S.tandy; }
