/* run_script GAME OUTDIR SPEED [t:key|t:shot:NAME|t:tab ...]
 * Runs the game headless at SPEED times its pace; at each time t (game seconds)
 * presses a key (scan code in hex), or writes the screen of all four modes as
 * OUTDIR/NAME_<mode>.bmp. t:w:ADDR:VALUE waits (from t) until the word at DS:ADDR
 * (hex) is VALUE (decimal); the times after it count from then. DOTC_FIX=list
 * as --fix=list. */
#include "../src/assets.h"
#include "../src/gfx.h"
#include "../src/sys.h"
#include "../src/sound.h"
#include "../src/game.h"
#include "../src/gamelog.h"
#include <SDL3/SDL.h>
static Assets A;
static void shot(const char *dir, const char *name)
{
    static const char *M[] = { "cga1", "cga2", "ega", "tandy" };
    static uint32_t rgb[SCREEN_W * SCREEN_H];
    for (int m = 0; m < MODE_COUNT; m++) {
        gfx_to_rgb((Mode)m, rgb);
        SDL_Surface *s = SDL_CreateSurfaceFrom(SCREEN_W, SCREEN_H, SDL_PIXELFORMAT_XRGB8888, rgb, SCREEN_W * 4);
        char path[600];
        SDL_snprintf(path, sizeof path, "%s/%s_%s.bmp", dir, name, M[m]);
        SDL_SaveBMP(s, path);
        SDL_DestroySurface(s);
    }
}
int main(int argc, char **argv)
{
    char err[256];
    if (argc < 4) { SDL_Log("usage"); return 1; }
    SDL_Init(0);
    if (!assets_load(&A, argv[1], err, sizeof err)) { SDL_Log("%s", err); return 1; }
    double speed = SDL_atof(argv[3]);
    gfx_init(&A);
    sound_data(A.tunes, A.tunes_len, A.bg, A.bg_len);
    const char *logdir = SDL_getenv("DOTC_LOG");
    if (logdir) gamelog_setup(GLOG_VERBOSE, logdir);
    if (SDL_getenv("DOTC_FIX")) {   /* as --fix= */
        char err[128];
        if (!fixes_parse(SDL_getenv("DOTC_FIX"), err, sizeof err)) { SDL_Log("DOTC_FIX: %s", err); return 1; }
    }
    sys_set_speed(speed);
    sys_start(game_main);
    Uint64 t0 = SDL_GetTicksNS();
    for (int i = 4; i < argc; i++) {
        double t = SDL_atof(argv[i]);
        const char *what = SDL_strchr(argv[i], ':') + 1;
        while ((double)(SDL_GetTicksNS() - t0) * speed / 1e9 < t) {
            if (!sys_running()) { SDL_Log("the game ended at %s", argv[i]); goto done; }
            SDL_Delay(1);
        }
        if (SDL_strncmp(what, "shot:", 5) == 0) shot(argv[2], what + 5);
        else if (SDL_strncmp(what, "w:", 2) == 0) {
            char *e;
            int addr = (int)SDL_strtol(what + 2, &e, 16), val = SDL_atoi(e + 1);
            while (W(addr) != val) {
                if (!sys_running()) { SDL_Log("the game ended waiting at %s", argv[i]); goto done; }
                SDL_Delay(1);
            }
            t0 = SDL_GetTicksNS() - (Uint64)(t * 1e9 / speed);
        }
        else sys_key((int)SDL_strtol(what, NULL, 16));
    }
done:
    sys_stop();
    gamelog_end("test over");
    assets_free(&A);
    return 0;
}
