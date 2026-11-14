/*
 * Defender of the Crown (1986) - remake
 * Nov 2026 using Claude Opus 5.5
 * "Guided" by Brett Hallen
 * Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
 * IBM PC versions by Master Designer Software (1987 DOS) and the booter (GAME.DAT)
 *
 * main.c: the window, the keyboard and the command line. The game itself
 * runs on its own thread (sys.h, game.c).
 *
 * Usage: DefenderOfTheCrown [--video=cga1|cga2|ega|tandy] [--log | --log=verbose] [game-folder]
 *   --video: the mode to start in (EGA if not given): cga1 the 1987 DOS version's
 *            CGA, cga2 the booter's CGA, ega, tandy. Tab goes through them in the game.
 *   --log:   a log of each game played (gamelog.h), in the remake's folder under Logs/
 *   game-folder: the folder with your GAME.DAT (and the 1987 version's .LIB files),
 *            also looked for in its ega/ and cga/ subfolders; remembered once found.
 *
 * Keys: the original's (the arrows or the keypad, Enter; keypad + and F1 are
 * Enter too), plus Tab the video mode, F2 4:3 or square pixels,
 * Alt/Cmd+Enter full screen, Cmd+Q quit.
 */
#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>

#include "assets.h"
#include "gfx.h"
#include "sys.h"
#include "sound.h"
#include "game.h"
#include "gamelog.h"

#define APP_ORG  "DefenderOfTheCrown"
#define APP_NAME "Remake"

static struct {
    Assets        a;
    bool          have_assets;
    Mode          mode;
    bool          aspect_43;
    SDL_Window   *win;
    SDL_Renderer *ren;
    SDL_Texture  *tex;
    SDL_Texture  *up;
    int           up_scale;
    uint32_t      rgb[SCREEN_W * SCREEN_H];
    Uint32        ev_folder;
    char          chosen[1024];
    bool          dialog_open;
} App;

/* ------------------------------------------------------------------ the game folder */

static void pref_file(char *out, size_t n)
{
    char *pref = SDL_GetPrefPath(APP_ORG, APP_NAME);
    SDL_snprintf(out, n, "%sgamedir.txt", pref ? pref : "");
    SDL_free(pref);
}

static void save_game_dir(const char *dir)
{
    char path[1100];
    pref_file(path, sizeof path);
    SDL_IOStream *io = SDL_IOFromFile(path, "w");
    if (io) { SDL_WriteIO(io, dir, SDL_strlen(dir)); SDL_CloseIO(io); }
}

static bool saved_game_dir(char *out, size_t n)
{
    char path[1100];
    size_t len = 0;
    pref_file(path, sizeof path);
    char *data = SDL_LoadFile(path, &len);
    if (!data) return false;
    while (len > 0 && (data[len - 1] == '\n' || data[len - 1] == '\r')) len--;
    data[len] = 0;
    SDL_strlcpy(out, data, n);
    SDL_free(data);
    return assets_dir_ok(out);
}

/* the command line, then the remembered folder, then next to the app (game/, ../Original), then the current folder */
static bool find_game_dir(const char *arg, char *out, size_t n)
{
    if (arg) { SDL_strlcpy(out, arg, n); return assets_dir_ok(out); }
    if (saved_game_dir(out, n)) return true;
    const char *base = SDL_GetBasePath();
    if (base) {
        static const char *const TRY[] = { "game", "", "../Original", "../../Original", "../../../Original", "../../../../Original",
                                          "../../../../../Original", "../../../../../../Original" };
        for (size_t i = 0; i < SDL_arraysize(TRY); i++) {
            SDL_snprintf(out, n, "%s%s", base, TRY[i]);
            if (assets_dir_ok(out)) return true;
        }
    }
    SDL_strlcpy(out, ".", n);
    if (assets_dir_ok(out)) return true;
    SDL_strlcpy(out, "../Original", n);
    return assets_dir_ok(out);
}

static void SDLCALL folder_chosen(void *ud, const char *const *list, int filter)
{
    (void)ud; (void)filter;
    App.dialog_open = false;
    if (list && list[0]) {
        SDL_strlcpy(App.chosen, list[0], sizeof App.chosen);
        SDL_Event e;
        SDL_zero(e);
        e.type = App.ev_folder;
        SDL_PushEvent(&e);
    }
}

static void ask_for_folder(void)
{
    if (App.dialog_open) return;
    App.dialog_open = true;
    SDL_ShowOpenFolderDialog(folder_chosen, NULL, App.win, NULL, false);
}

static bool load_from(const char *dir, bool remember)
{
    char err[256] = "";
    if (App.have_assets) return true;   /* the game thread uses them: loaded once */
    App.have_assets = assets_load(&App.a, dir, err, sizeof err);
    if (!App.have_assets) {
        SDL_Log("Could not load the game from %s: %s", dir, err);
        if (App.win)
            SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, "Defender of the Crown",
                                     "That folder doesn't hold a usable copy of Defender of the Crown "
                                     "(GAME.DAT, and the 1987 version's .LIB files for its own CGA pictures).", App.win);
        return false;
    }
    if (remember) save_game_dir(dir);
    SDL_Log("Loaded the game from %s", dir);
    gfx_init(&App.a);
    sound_data(App.a.tunes, App.a.tunes_len, App.a.bg, App.a.bg_len);
    snd_use_tandy(App.mode == MODE_TANDY);
    sys_start(game_main);
    return true;
}

/* ------------------------------------------------------------------ drawing */

static void update_title(void)
{
    char t[160];
    SDL_snprintf(t, sizeof t, "Defender of the Crown - %s%s", App.have_assets ? MODE_NAMES[App.mode] : "choose your game folder",
                 App.aspect_43 ? "" : " (square pixels)");
    SDL_SetWindowTitle(App.win, t);
}

static SDL_FRect dest_rect(int w, int h, bool *integer)
{
    int ow, oh;
    SDL_GetRenderOutputSize(App.ren, &ow, &oh);
    SDL_FRect r;
    if (!App.aspect_43) {
        int k = SDL_min(ow / w, oh / h);
        if (k >= 1) { r.w = (float)(w * k); r.h = (float)(h * k); *integer = true; }
        else { float f = SDL_min((float)ow / w, (float)oh / h); r.w = w * f; r.h = h * f; *integer = false; }
    } else {
        r.h = (float)oh;
        r.w = r.h * 4.0f / 3.0f;
        if (r.w > ow) { r.w = (float)ow; r.h = r.w * 3.0f / 4.0f; }
        *integer = false;
    }
    r.x = SDL_floorf((ow - r.w) / 2);
    r.y = SDL_floorf((oh - r.h) / 2);
    return r;
}

static void render(void)
{
    SDL_SetRenderDrawColor(App.ren, 0, 0, 0, 255);
    SDL_RenderClear(App.ren);
    if (App.have_assets) {
        gfx_to_rgb(App.mode, App.rgb);
        SDL_UpdateTexture(App.tex, NULL, App.rgb, SCREEN_W * 4);
        bool integer;
        SDL_FRect dst = dest_rect(SCREEN_W, SCREEN_H, &integer);
        if (integer) SDL_RenderTexture(App.ren, App.tex, NULL, &dst);
        else {   /* sharp: nearest up to a whole multiple, then smoothly down */
            int k = SDL_clamp((int)SDL_ceilf(SDL_max(dst.w / SCREEN_W, dst.h / SCREEN_H)), 1, 8);
            if (!App.up || App.up_scale != k) {
                SDL_DestroyTexture(App.up);
                App.up = SDL_CreateTexture(App.ren, SDL_PIXELFORMAT_XRGB8888, SDL_TEXTUREACCESS_TARGET, SCREEN_W * k, SCREEN_H * k);
                App.up_scale = k;
                if (App.up) SDL_SetTextureScaleMode(App.up, SDL_SCALEMODE_LINEAR);
            }
            if (App.up) {
                SDL_SetRenderTarget(App.ren, App.up);
                SDL_RenderTexture(App.ren, App.tex, NULL, NULL);
                SDL_SetRenderTarget(App.ren, NULL);
                SDL_RenderTexture(App.ren, App.up, NULL, &dst);
            } else SDL_RenderTexture(App.ren, App.tex, NULL, &dst);
        }
    }
    SDL_RenderPresent(App.ren);
}

static void set_mode(Mode m)
{
    App.mode = m;
    snd_use_tandy(m == MODE_TANDY);   /* the tune being played starts again from the top on the new sound */
    update_title();
}

/* ------------------------------------------------------------------ keys */

static int scan_code(SDL_Keycode k)
{
    switch (k) {
    case SDLK_RETURN: case SDLK_KP_ENTER: return KEY_ENTER;
    case SDLK_ESCAPE: return KEY_ESC;
    case SDLK_SPACE: return KEY_SPACE;
    case SDLK_F1: return KEY_F1;
    case SDLK_HOME: case SDLK_KP_7: return KEY_HOME;
    case SDLK_UP: case SDLK_KP_8: return KEY_UP;
    case SDLK_PAGEUP: case SDLK_KP_9: return KEY_PGUP;
    case SDLK_KP_MINUS: return KEY_KP_MINUS;
    case SDLK_LEFT: case SDLK_KP_4: return KEY_LEFT;
    case SDLK_KP_5: return KEY_KP5;
    case SDLK_RIGHT: case SDLK_KP_6: return KEY_RIGHT;
    case SDLK_KP_PLUS: return KEY_KP_PLUS;
    case SDLK_END: case SDLK_KP_1: return KEY_END;
    case SDLK_DOWN: case SDLK_KP_2: return KEY_DOWN;
    case SDLK_PAGEDOWN: case SDLK_KP_3: return KEY_PGDN;
    default: break;
    }
    if (k >= SDLK_A && k <= SDLK_Z) {   /* the letters' scan codes */
        static const uint8_t SC[26] = { 0x1E, 0x30, 0x2E, 0x20, 0x12, 0x21, 0x22, 0x23, 0x17, 0x24, 0x25, 0x26, 0x32,
                                        0x31, 0x18, 0x19, 0x10, 0x13, 0x1F, 0x14, 0x16, 0x2F, 0x11, 0x2D, 0x15, 0x2C };
        return SC[k - SDLK_A];
    }
    return 0;
}

/* ------------------------------------------------------------------ main */

int main(int argc, char **argv)
{
    const char *dir_arg = NULL;
    GameLogLevel log_level = GLOG_OFF;
    App.mode = MODE_EGA;
    App.aspect_43 = true;
    for (int i = 1; i < argc; i++) {
        if (SDL_strncmp(argv[i], "--video=", 8) == 0 || SDL_strncmp(argv[i], "video=", 6) == 0) {
            const char *v = SDL_strchr(argv[i], '=') + 1;
            if (!mode_from_name(v, &App.mode)) SDL_Log("--video=%s: use cga1, cga2, ega or tandy", v);
        } else if (SDL_strcmp(argv[i], "--video") == 0 && i + 1 < argc) {
            if (!mode_from_name(argv[++i], &App.mode)) SDL_Log("--video %s: use cga1, cga2, ega or tandy", argv[i]);
        } else if (SDL_strcmp(argv[i], "--log=verbose") == 0) log_level = GLOG_VERBOSE;
        else if (SDL_strcmp(argv[i], "--log") == 0 || SDL_strcmp(argv[i], "--log=normal") == 0) {
            log_level = GLOG_NORMAL;
            if (i + 1 < argc && SDL_strcmp(argv[i + 1], "verbose") == 0) { log_level = GLOG_VERBOSE; i++; }
        } else if (argv[i][0] != '-') dir_arg = argv[i];
    }

    if (!SDL_Init(SDL_INIT_VIDEO)) { SDL_Log("SDL_Init failed: %s", SDL_GetError()); return 1; }
    if (!SDL_CreateWindowAndRenderer("Defender of the Crown", 1280, 960, SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY,
                                     &App.win, &App.ren)) {
        SDL_Log("Could not create the window: %s", SDL_GetError());
        SDL_Quit();
        return 1;
    }
    SDL_SetRenderVSync(App.ren, 1);
    App.tex = SDL_CreateTexture(App.ren, SDL_PIXELFORMAT_XRGB8888, SDL_TEXTUREACCESS_STREAMING, SCREEN_W, SCREEN_H);
    SDL_SetTextureScaleMode(App.tex, SDL_SCALEMODE_NEAREST);
    App.ev_folder = SDL_RegisterEvents(1);
    sound_init();
    if (log_level != GLOG_OFF) {
        char *pref = SDL_GetPrefPath(APP_ORG, APP_NAME);
        char logs[1100];
        SDL_snprintf(logs, sizeof logs, "%sLogs/", pref ? pref : "");
        SDL_free(pref);
        gamelog_setup(log_level, logs);
        SDL_Log("Game logs (%s) go to %s", log_level == GLOG_VERBOSE ? "verbose" : "normal", logs);
    }

    char dir[1024];
    if (find_game_dir(dir_arg, dir, sizeof dir)) load_from(dir, dir_arg != NULL);
    if (!App.have_assets) ask_for_folder();
    update_title();

    bool running = true;
    while (running) {
        SDL_Event e;
        while (SDL_PollEvent(&e)) {
            if (e.type == SDL_EVENT_QUIT) running = false;
            else if (e.type == App.ev_folder) { if (!load_from(App.chosen, true)) ask_for_folder(); update_title(); }
            else if (e.type == SDL_EVENT_KEY_DOWN) {
                SDL_Keycode k = e.key.key;
                bool mod = (e.key.mod & (SDL_KMOD_ALT | SDL_KMOD_GUI)) != 0;
                if (k == SDLK_Q && (e.key.mod & SDL_KMOD_GUI)) running = false;
                else if ((k == SDLK_RETURN || k == SDLK_KP_ENTER) && mod) {
                    bool full = (SDL_GetWindowFlags(App.win) & SDL_WINDOW_FULLSCREEN) != 0;
                    SDL_SetWindowFullscreen(App.win, !full);
                }
                else if (k == SDLK_TAB) set_mode((Mode)((App.mode + 1) % MODE_COUNT));
                else if (k == SDLK_F2) { App.aspect_43 = !App.aspect_43; update_title(); }
                else if (!App.have_assets && k == SDLK_O) ask_for_folder();
                else { int sc = scan_code(k); if (sc) sys_key(sc); }
            }
        }
        if (App.have_assets && !sys_running()) running = false;   /* the game ended (End Present Game, or No to play again) */
        render();
        if (!App.have_assets) SDL_Delay(50);
    }

    sys_stop();
    gamelog_end("The remake was closed");
    sound_quit();
    if (App.have_assets) assets_free(&App.a);
    SDL_DestroyTexture(App.up);
    SDL_DestroyTexture(App.tex);
    SDL_DestroyRenderer(App.ren);
    SDL_DestroyWindow(App.win);
    SDL_Quit();
    return 0;
}
