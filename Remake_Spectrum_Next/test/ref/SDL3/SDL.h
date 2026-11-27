/*
 * Defender of the Crown (1986) - Spectrum Next remake
 * Nov 2026 using Claude Opus 5.5
 * "Guided" by Brett Hallen
 *
 * test/ref/SDL3/SDL.h: the little of SDL3 that the Mac remake's game,
 * drawing, asset and sound code use (not main.c, sys.c or icon.c), over the
 * C library, so that code can be built without SDL as the reference the
 * Next's port is checked against (test/ref/ref_sys.c). One thread: the mutex
 * calls do nothing; there is no audio device (the music's state still runs);
 * delays move the virtual clock (ref_sys.c).
 */
#ifndef REF_SDL_H
#define REF_SDL_H

#include <ctype.h>
#include <errno.h>
#include <math.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>

typedef uint8_t Uint8;
typedef int8_t Sint8;
typedef uint16_t Uint16;
typedef int16_t Sint16;
typedef uint32_t Uint32;
typedef int32_t Sint32;
typedef uint64_t Uint64;
typedef int64_t Sint64;

#define SDLCALL
#define SDL_PRINTF_FORMAT_STRING
#define SDL_PRINTF_VARARG_FUNC(n)
#define SDL_NS_PER_SECOND 1000000000ull
#define SDL_NS_PER_MS 1000000ull

#define SDL_memcpy memcpy
#define SDL_memmove memmove
#define SDL_memset memset
#define SDL_memcmp memcmp
#define SDL_zero(x) memset(&(x), 0, sizeof(x))
#define SDL_zeroa(x) memset((x), 0, sizeof(x))
#define SDL_malloc malloc
#define SDL_calloc calloc
#define SDL_realloc realloc
#define SDL_free free
#define SDL_strdup strdup
#define SDL_strlen strlen
#define SDL_strchr strchr
#define SDL_strcmp strcmp
#define SDL_strncmp strncmp
#define SDL_strcasecmp strcasecmp
#define SDL_strncasecmp strncasecmp
#define SDL_strtol strtol
#define SDL_tolower tolower
#define SDL_snprintf snprintf
#define SDL_vsnprintf vsnprintf
#define SDL_powf powf
#define SDL_floor floor
#define SDL_floorf floorf
#define SDL_ceilf ceilf
#define SDL_min(a, b) ((a) < (b) ? (a) : (b))
#define SDL_max(a, b) ((a) > (b) ? (a) : (b))
#define SDL_clamp(x, a, b) ((x) < (a) ? (a) : (x) > (b) ? (b) : (x))
#define SDL_arraysize(a) (sizeof(a) / sizeof((a)[0]))

static inline size_t SDL_strlcpy(char *d, const char *s, size_t n)
{
    size_t l = strlen(s);
    if (n) { size_t c = l < n - 1 ? l : n - 1; memcpy(d, s, c); d[c] = 0; }
    return l;
}

static inline void SDL_Log(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
}
static inline const char *SDL_GetError(void) { return "no SDL here"; }

/* one thread: no locking needed */
typedef struct SDL_Mutex { int unused; } SDL_Mutex;
static inline SDL_Mutex *SDL_CreateMutex(void) { static SDL_Mutex m; return &m; }
static inline void SDL_LockMutex(SDL_Mutex *m) { (void)m; }
static inline void SDL_UnlockMutex(SDL_Mutex *m) { (void)m; }

/* files */
static inline void *SDL_LoadFile(const char *path, size_t *len)
{
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *d = malloc((size_t)n + 1);
    if (d && fread(d, 1, (size_t)n, f) != (size_t)n) { free(d); d = NULL; }
    fclose(f);
    if (d) { d[n] = 0; if (len) *len = (size_t)n; }
    return d;
}
typedef enum { SDL_PATHTYPE_NONE, SDL_PATHTYPE_FILE, SDL_PATHTYPE_DIRECTORY, SDL_PATHTYPE_OTHER } SDL_PathType;
typedef struct { SDL_PathType type; Uint64 size; } SDL_PathInfo;
static inline bool SDL_GetPathInfo(const char *path, SDL_PathInfo *info)
{
    struct stat st;
    if (stat(path, &st) != 0) return false;
    if (info) {
        info->type = S_ISREG(st.st_mode) ? SDL_PATHTYPE_FILE : S_ISDIR(st.st_mode) ? SDL_PATHTYPE_DIRECTORY : SDL_PATHTYPE_OTHER;
        info->size = (Uint64)st.st_size;
    }
    return true;
}
static inline bool SDL_CreateDirectory(const char *path) { return mkdir(path, 0755) == 0 || errno == EEXIST; }
typedef FILE SDL_IOStream;
static inline SDL_IOStream *SDL_IOFromFile(const char *p, const char *m) { return fopen(p, m); }
static inline size_t SDL_WriteIO(SDL_IOStream *f, const void *d, size_t n) { return fwrite(d, 1, n, f); }
static inline bool SDL_FlushIO(SDL_IOStream *f) { return fflush(f) == 0; }
static inline bool SDL_CloseIO(SDL_IOStream *f) { return fclose(f) == 0; }
static inline char *SDL_GetPrefPath(const char *org, const char *app) { (void)org; (void)app; return strdup("/tmp/"); }
static inline char *SDL_GetBasePath(void) { return strdup("./"); }

/* the clock: virtual (ref_sys.c) */
void SDL_DelayNS(Uint64 ns);
static inline void SDL_Delay(Uint32 ms) { SDL_DelayNS((Uint64)ms * 1000000ull); }
Uint64 SDL_GetTicksNS(void);

/* the date, for the game log: always the same */
typedef Sint64 SDL_Time;
typedef struct { int year, month, day, hour, minute, second, nanosecond, day_of_week, utc_offset; } SDL_DateTime;
static inline bool SDL_GetCurrentTime(SDL_Time *t) { *t = 0; return true; }
static inline bool SDL_TimeToDateTime(SDL_Time t, SDL_DateTime *dt, bool local)
{ (void)t; (void)local; memset(dt, 0, sizeof *dt); dt->year = 1987; dt->month = 1; dt->day = 1; return true; }

/* no audio device */
#define SDL_INIT_AUDIO 0x10u
#define SDL_INIT_VIDEO 0x20u
#define SDL_AUDIO_F32 1
#define SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK 0
typedef struct { int format, channels, freq; } SDL_AudioSpec;
typedef struct SDL_AudioStream SDL_AudioStream;
typedef void (*SDL_AudioStreamCallback)(void *, SDL_AudioStream *, int, int);
static inline bool SDL_InitSubSystem(Uint32 f) { (void)f; return false; }
static inline bool SDL_Init(Uint32 f) { (void)f; return true; }
static inline SDL_AudioStream *SDL_OpenAudioDeviceStream(int d, const SDL_AudioSpec *s, SDL_AudioStreamCallback cb, void *u)
{ (void)d; (void)s; (void)cb; (void)u; return NULL; }
static inline bool SDL_ResumeAudioStreamDevice(SDL_AudioStream *s) { (void)s; return false; }
static inline bool SDL_PutAudioStreamData(SDL_AudioStream *s, const void *b, int n) { (void)s; (void)b; (void)n; return false; }
static inline void SDL_DestroyAudioStream(SDL_AudioStream *s) { (void)s; }

#endif
