/*
 * Defender of the Crown (1986) - remake
 * Nov 2026 using Claude Opus 5.5
 * "Guided" by Brett Hallen
 * Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
 * IBM PC versions by Master Designer Software (1987 DOS) and the booter (GAME.DAT)
 *
 * sys.c: the game thread, the timer and the keyboard (sys.h).
 */
#include "sys.h"
#include "sound.h"

#include <SDL3/SDL.h>
#include <setjmp.h>

#define TICK_NS 54925416ull   /* 65536 / 1193182 s: the BIOS clock */
#define RETRACE_NS (SDL_NS_PER_SECOND / 60)

static struct {
    SDL_Thread  *thread;
    SDL_Mutex   *lock;
    SDL_AtomicInt stop, running, frames;
    SDL_TimerID  timer;
    void       (*game)(void);
    jmp_buf      out;
    Uint64       t0;              /* SDL ns at tick 0 */
    uint32_t     base;            /* the BIOS count at start: ticks since midnight */
    SDL_AtomicInt done_ticks;     /* ticks given to the sound so far */
    int          keys[64];
    int          head, count;
    jmp_buf     *skip_to;         /* sys_skip_arm: where Enter jumps */
    SDL_AtomicInt skip_armed, skip_hit;
} Y;

/* ------------------------------------------------------------------ the timer */

static double speed = 1.0;   /* tests run the game faster */
void sys_set_speed(double s) { speed = s > 0 ? s : 1.0; }

static Uint64 now_ns(void) { return (Uint64)((double)(SDL_GetTicksNS() - Y.t0) * speed); }

uint32_t sys_ticks(void)
{
    return Y.base + (uint32_t)(now_ns() / TICK_NS);
}

/* every millisecond: the int 1Ch handler for each tick that has passed */
static Uint64 SDLCALL timer_cb(void *ud, SDL_TimerID id, Uint64 interval)
{
    (void)ud; (void)id;
    int now = (int)(now_ns() / TICK_NS);
    while (SDL_GetAtomicInt(&Y.done_ticks) < now) {
        SDL_AddAtomicInt(&Y.done_ticks, 1);
        sound_tick();
    }
    return interval;
}

/* ------------------------------------------------------------------ the thread */

void sys_check(void)
{
    if (SDL_GetAtomicInt(&Y.stop)) longjmp(Y.out, 1);
    if (SDL_GetAtomicInt(&Y.skip_hit) && Y.skip_to) {
        jmp_buf *to = Y.skip_to;
        sys_skip_disarm();
        longjmp(*to, 1);
    }
}

void sys_skip_arm(jmp_buf *to)
{
    Y.skip_to = to;
    SDL_SetAtomicInt(&Y.skip_hit, 0);
    SDL_SetAtomicInt(&Y.skip_armed, 1);
}

void sys_skip_disarm(void)
{
    SDL_SetAtomicInt(&Y.skip_armed, 0);
    SDL_SetAtomicInt(&Y.skip_hit, 0);
    Y.skip_to = NULL;
}

static int SDLCALL thread_main(void *ud)
{
    (void)ud;
    if (setjmp(Y.out) == 0) Y.game();
    SDL_SetAtomicInt(&Y.running, 0);
    return 0;
}

void sys_start(void (*game)(void))
{
    if (!Y.lock) Y.lock = SDL_CreateMutex();
    Y.game = game;
    Y.t0 = SDL_GetTicksNS();
    SDL_Time now;
    SDL_DateTime dt;
    if (SDL_GetCurrentTime(&now) && SDL_TimeToDateTime(now, &dt, true))
        Y.base = (uint32_t)(((dt.hour * 60 + dt.minute) * 60 + dt.second) * 18.2065);
    SDL_SetAtomicInt(&Y.stop, 0);
    SDL_SetAtomicInt(&Y.running, 1);
    SDL_SetAtomicInt(&Y.done_ticks, 0);
    if (!Y.timer) Y.timer = SDL_AddTimerNS(SDL_NS_PER_MS, timer_cb, NULL);
    Y.thread = SDL_CreateThread(thread_main, "game", NULL);
}

void sys_stop(void)
{
    SDL_SetAtomicInt(&Y.stop, 1);
    if (Y.thread) SDL_WaitThread(Y.thread, NULL);
    Y.thread = NULL;
    if (Y.timer) SDL_RemoveTimer(Y.timer);
    Y.timer = 0;
}

bool sys_running(void) { return SDL_GetAtomicInt(&Y.running) != 0; }
uint32_t sys_frames(void) { return (uint32_t)SDL_GetAtomicInt(&Y.frames); }
void sys_frame_done(void) { SDL_AddAtomicInt(&Y.frames, 1); }

/* ------------------------------------------------------------------ keys */

void sys_key(int scan)
{
    if (!Y.lock) return;
    if (scan == KEY_ENTER && SDL_GetAtomicInt(&Y.skip_armed)) {   /* skips, and is not kept */
        SDL_SetAtomicInt(&Y.skip_hit, 1);
        return;
    }
    SDL_LockMutex(Y.lock);
    if (Y.count < (int)SDL_arraysize(Y.keys)) {   /* the BIOS buffer held 15; a few more do no harm */
        Y.keys[(Y.head + Y.count) % SDL_arraysize(Y.keys)] = scan;
        Y.count++;
    }
    SDL_UnlockMutex(Y.lock);
}

int bios_key(void)
{
    sys_check();
    int k = 0;
    SDL_LockMutex(Y.lock);
    if (Y.count) {
        k = Y.keys[Y.head];
        Y.head = (Y.head + 1) % SDL_arraysize(Y.keys);
        Y.count--;
    }
    SDL_UnlockMutex(Y.lock);
    if (!k) SDL_DelayNS(200000);   /* the original spun here; give the CPU back */
    return k;
}

static int translate(int k)
{
    k &= 0xFF;
    if (k == KEY_KP_PLUS || k == KEY_F1) k = KEY_ENTER;   /* 7F76: keypad + and F1 are Enter */
    return k;
}

int get_key(void) { return translate(bios_key()); }

int wait_key(void)
{
    int k;
    while (!(k = bios_key())) {}
    return translate(k);
}

void flush_keys(void) { while (get_key()) {} }

/* 7EF2: counts n changes of the tick count, reading (and dropping) keys meanwhile.
 * Its first comparison is with whatever was on the stack, so the first change
 * counts at once: n - 1 whole ticks and part of one. */
int wait_ticks(int n)
{
    uint32_t last = sys_ticks() + 1;   /* never equal at first */
    int k = 0;
    while (n) {
        k = get_key();
        uint32_t t = sys_ticks();
        if (t != last) { last = t; n--; }
    }
    return k;
}

/* 9CAF: as wait_ticks, without reading the keys */
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
    Uint64 now = now_ns();
    Uint64 next = (now / RETRACE_NS + 1) * RETRACE_NS;
    SDL_DelayPrecise((Uint64)((double)(next - now) / speed));
}
