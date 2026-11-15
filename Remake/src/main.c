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
 * Usage: DefenderOfTheCrown [--video=cga1|cga2|ega|tandy] [--log | --log=verbose] [--rules=booter|dos] [--fix=NAME,...|all] [--catapult-pull=N] [game-folder]
 *   --video: the mode to start in (EGA if not given): cga1 the 1987 DOS version's
 *            CGA, cga2 the booter's CGA, ega, tandy. Tab goes through them in the game.
 *   --log:   a log of each game played (gamelog.h), in the remake's folder under Logs/
 *   --fix:   fixes these flaws of the original (none by default, the game as it was):
 *            viking, hostility, targets, catapult, siege-merge, joust-opponent,
 *            joust-margin, battle-text, siege-sprite, or all (game.h, Remake/README.md)
 *   --rules: booter (the default) or dos, the 1987 DOS version's rules and timing
 *   --catapult-pull: screen refreshes per step of the catapult's pull, 1 (the
 *            original's speed on a fast PC, 0.4 s) to 8; 2 if not given
 *   game-folder: the folder with your GAME.DAT (and the 1987 version's .LIB files),
 *            also looked for in its ega/ and cga/ subfolders; remembered once found.
 * The same settings are read first from DefenderOfTheCrown.ini in the remake's
 * folder (written with the defaults if it is not there); the command line wins
 * for that run. The game folder found or chosen is remembered there.
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
#include "icon.h"
#include "ini.h"

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
    const char   *src[6];          /* where each setting came from (SET_...), for the game log */
    const char   *folder_src;
    Mode          start_mode;      /* the mode the settings asked for */
    const char   *log_name;        /* off, normal, verbose */
} App;

static const char *const MODE_KEYS[MODE_COUNT] = { "cga1", "cga2", "ega", "tandy" };

enum { SET_VIDEO, SET_FIX, SET_PULL, SET_LOG, SET_FOLDER, SET_RULES, SET_COUNT };

/* ------------------------------------------------------------------ the settings file */

#define SETTINGS_FILE "DefenderOfTheCrown.ini"

/* written when there is no settings file: the defaults, as without any option */
static const char DEFAULT_SETTINGS[] =
    "; Defender of the Crown - Remake: settings\n"
    ";\n"
    "; Read at every start. An option given on the command line wins over the same\n"
    "; setting here, for that run only. Delete this file to get the defaults back.\n"
    "\n"
    "[game]\n"
    "; The folder with your GAME.DAT (and the 1987 version's .LIB files). Empty: look\n"
    "; next to the app (game/, ../Original), else ask for it. The remake fills it in\n"
    "; when you choose a folder, or give one on the command line.\n"
    "folder =\n"
    "\n"
    "[display]\n"
    "; The video mode to start in: cga1 (the 1987 DOS version's CGA), cga2 (the\n"
    "; booter's CGA), ega or tandy. Tab goes through them in the game.\n"
    "video = ega\n"
    "\n"
    "[play]\n"
    "; The rules: booter (the self-booting release, as the EGA program plays) or dos\n"
    "; (the 1987 DOS version: its random numbers, its computer lords' odds, and its\n"
    "; waits, which make its scenes slower: the catapult, the joust, the sword fight).\n"
    "rules = booter\n"
    "; Fixes for the original's flaws, by name and separated by commas, or all.\n"
    "; Empty: the game as it was. The names: viking, hostility, targets, catapult,\n"
    "; siege-merge, joust-opponent, joust-margin, battle-text, siege-sprite\n"
    "; (what each one does: the remake's README.md).\n"
    "fix =\n"
    "; Screen refreshes for each step of the catapult's arm as you draw it back:\n"
    "; 1 (the original on a fast PC: 0.4 seconds for a full pull) to 8. 2: 0.8 s.\n"
    "catapult_pull = 2\n"
    "\n"
    "[debug]\n"
    "; A log of each game played, in Logs/ beside this file: off, normal or verbose.\n"
    "log = off\n";

static void settings_path(char *out, size_t n)
{
    char *pref = SDL_GetPrefPath(APP_ORG, APP_NAME);
    SDL_snprintf(out, n, "%s%s", pref ? pref : "", SETTINGS_FILE);
    SDL_free(pref);
}

/* the settings file, written with the defaults first if it is not there */
static void settings_load(Ini *ini)
{
    char path[1100];
    settings_path(path, sizeof path);
    if (ini_load(ini, path)) { SDL_Log("Settings: %s", path); return; }
    ini_text(ini, DEFAULT_SETTINGS);
    if (ini_save(ini, path)) SDL_Log("Settings: %s (new, with the defaults)", path);
    else SDL_Log("Could not write the settings file %s", path);
}

/* ------------------------------------------------------------------ the game folder */

/* the settings file's folder = (read again, so that edits made since the start stay) */
static void save_game_dir(const char *dir)
{
    char path[1100];
    settings_path(path, sizeof path);
    Ini ini;
    if (!ini_load(&ini, path)) ini_text(&ini, DEFAULT_SETTINGS);
    const char *old = ini_get(&ini, "game", "folder");
    if (!old || SDL_strcmp(old, dir) != 0) {
        ini_set(&ini, "game", "folder", dir);
        if (!ini_save(&ini, path)) SDL_Log("Could not write the settings file %s", path);
    }
    ini_free(&ini);
}

/* the settings file's folder; else gamedir.txt, where earlier builds kept it (moved
 * into the settings file) */
static bool saved_game_dir(const char *setting, char *out, size_t n)
{
    if (setting && *setting) {
        SDL_strlcpy(out, setting, n);
        if (assets_dir_ok(out)) return true;
        SDL_Log("The settings file's game folder %s has no usable GAME.DAT", setting);
    }
    char path[1100];
    size_t len = 0;
    char *pref = SDL_GetPrefPath(APP_ORG, APP_NAME);
    SDL_snprintf(path, sizeof path, "%sgamedir.txt", pref ? pref : "");
    SDL_free(pref);
    char *data = SDL_LoadFile(path, &len);
    if (!data) return false;
    while (len > 0 && (data[len - 1] == '\n' || data[len - 1] == '\r')) len--;
    data[len] = 0;
    SDL_strlcpy(out, data, n);
    SDL_free(data);
    if (!assets_dir_ok(out)) return false;
    save_game_dir(out);
    return true;
}

/* the command line, then the remembered folder, then next to the app (game/, ../Original), then the current folder */
static bool find_game_dir(const char *arg, const char *setting, char *out, size_t n)
{
    if (arg) { SDL_strlcpy(out, arg, n); return assets_dir_ok(out); }
    if (saved_game_dir(setting, out, n)) return true;
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

/* The window's icon (the Dock icon on macOS): the title picture of the
 * player's own game files, as in the app bundle's icon (tools/make_icon.c). */
static void set_window_icon(void)
{
    enum { N = 256 };
    uint8_t *px = SDL_malloc(N * N * 4);
    if (px && App.win && icon_render(&App.a, N, px)) {
        SDL_Surface *s = SDL_CreateSurfaceFrom(N, N, SDL_PIXELFORMAT_RGBA32, px, N * 4);
        if (s) { SDL_SetWindowIcon(App.win, s); SDL_DestroySurface(s); }
    }
    SDL_free(px);
}

static void log_settings(const char *folder);

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
    log_settings(dir);
    gamelog_display(MODE_NAMES[App.mode], App.aspect_43);
    set_window_icon();
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
    gamelog_display(MODE_NAMES[m], App.aspect_43);
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

/* the settings, from the settings file or the command line (from: where, for the messages) */
static const char *source(const char *from) { return SDL_strncmp(from, "--", 2) == 0 ? "the command line" : "the settings file"; }

/* the settings in effect, for the game log's start */
static void log_settings(const char *folder)
{
    char path[1100], t[4096];
    settings_path(path, sizeof path);
    char fx[256] = "";
    for (int i = 0; i < FIX_COUNT; i++)
        if (fixed((Fix)i)) SDL_snprintf(fx + SDL_strlen(fx), sizeof fx - SDL_strlen(fx), "%s%s", *fx ? "," : "", FIX_NAMES[i]);
    SDL_snprintf(t, sizeof t,
                 "Settings (the settings file %s, then the command line):\n"
                 "  folder = %s (%s)\n"
                 "  video = %s at the start (%s)\n"
                 "  rules = %s (%s)\n"
                 "  fix = %s (%s)\n"
                 "  catapult_pull = %d (%s)\n"
                 "  log = %s (%s)\n",
                 path, folder, App.folder_src ? App.folder_src : "found",
                 MODE_KEYS[App.start_mode], App.src[SET_VIDEO] ? App.src[SET_VIDEO] : "the default",
                 g_dos_rules ? "dos" : "booter", App.src[SET_RULES] ? App.src[SET_RULES] : "the default",
                 *fx ? fx : "none, the game as it was", App.src[SET_FIX] ? App.src[SET_FIX] : "the default",
                 g_catapult_pull, App.src[SET_PULL] ? App.src[SET_PULL] : "the default",
                 App.log_name, App.src[SET_LOG] ? App.src[SET_LOG] : "the default");
    gamelog_settings(t);
}
static void set_video(const char *v, const char *from)
{
    if (!mode_from_name(v, &App.mode)) SDL_Log("%s=%s: use cga1, cga2, ega or tandy", from, v);
    else App.src[SET_VIDEO] = source(from);
}

static void set_fixes(const char *v, const char *from)
{
    char err[128];
    if (fixes_parse(v, err, sizeof err)) App.src[SET_FIX] = source(from);
    else SDL_Log("%s: %s; use viking, hostility, targets, catapult, siege-merge, joust-opponent, joust-margin, "
                "battle-text, siege-sprite or all, separated by commas", from, err);
}

static void set_catapult_pull(const char *v, const char *from)
{
    char *end;
    long n = SDL_strtol(v, &end, 10);
    if (end != v && !*end && n >= 1 && n <= 8) { g_catapult_pull = (int)n; App.src[SET_PULL] = source(from); }
    else SDL_Log("%s=%s: use 1 (the original's speed) to 8", from, v);
}

static void set_rules(const char *v, const char *from)
{
    if (SDL_strcasecmp(v, "booter") == 0) set_dos_rules(false);
    else if (SDL_strcasecmp(v, "dos") == 0) set_dos_rules(true);
    else { SDL_Log("%s=%s: use booter or dos", from, v); return; }
    App.src[SET_RULES] = source(from);
}

static void set_log(const char *v, GameLogLevel *level, const char *from)
{
    if (SDL_strcasecmp(v, "off") == 0 || !*v) *level = GLOG_OFF;
    else if (SDL_strcasecmp(v, "normal") == 0 || SDL_strcasecmp(v, "on") == 0) *level = GLOG_NORMAL;
    else if (SDL_strcasecmp(v, "verbose") == 0) *level = GLOG_VERBOSE;
    else { SDL_Log("%s=%s: use off, normal or verbose", from, v); return; }
    App.src[SET_LOG] = source(from);
}

int main(int argc, char **argv)
{
    const char *dir_arg = NULL;
    GameLogLevel log_level = GLOG_OFF;
    App.mode = MODE_EGA;
    App.aspect_43 = true;

    Ini settings;
    settings_load(&settings);
    const char *v;
    if ((v = ini_get(&settings, "display", "video")) && *v) set_video(v, SETTINGS_FILE " video");
    if ((v = ini_get(&settings, "play", "rules")) && *v) set_rules(v, SETTINGS_FILE " rules");
    if ((v = ini_get(&settings, "play", "fix"))) set_fixes(v, SETTINGS_FILE " fix");
    if ((v = ini_get(&settings, "play", "catapult_pull")) && *v) set_catapult_pull(v, SETTINGS_FILE " catapult_pull");
    if ((v = ini_get(&settings, "debug", "log"))) set_log(v, &log_level, SETTINGS_FILE " log");
    char folder_setting[1024] = "";
    if ((v = ini_get(&settings, "game", "folder"))) SDL_strlcpy(folder_setting, v, sizeof folder_setting);
    ini_free(&settings);

    for (int i = 1; i < argc; i++) {
        if (SDL_strncmp(argv[i], "--video=", 8) == 0 || SDL_strncmp(argv[i], "video=", 6) == 0) {
            set_video(SDL_strchr(argv[i], '=') + 1, "--video");
        } else if (SDL_strcmp(argv[i], "--video") == 0 && i + 1 < argc) {
            set_video(argv[++i], "--video");
        } else if (SDL_strncmp(argv[i], "--rules=", 8) == 0) {
            set_rules(argv[i] + 8, "--rules");
        } else if (SDL_strncmp(argv[i], "--fix=", 6) == 0) {
            set_fixes(argv[i] + 6, "--fix");
        } else if (SDL_strncmp(argv[i], "--catapult-pull=", 16) == 0) {
            set_catapult_pull(argv[i] + 16, "--catapult-pull");
        } else if (SDL_strncmp(argv[i], "--log=", 6) == 0) {
            set_log(argv[i] + 6, &log_level, "--log");
        } else if (SDL_strcmp(argv[i], "--log") == 0) {
            set_log("normal", &log_level, "--log");
            if (i + 1 < argc && SDL_strcmp(argv[i + 1], "verbose") == 0) { log_level = GLOG_VERBOSE; i++; }
        } else if (argv[i][0] != '-') dir_arg = argv[i];
    }
    App.start_mode = App.mode;
    App.log_name = log_level == GLOG_VERBOSE ? "verbose" : log_level == GLOG_NORMAL ? "normal" : "off";

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
    if (find_game_dir(dir_arg, folder_setting, dir, sizeof dir)) {
        App.folder_src = dir_arg ? "the command line" : SDL_strcmp(dir, folder_setting) == 0 ? "the settings file" : "found";
        load_from(dir, dir_arg != NULL);
    }
    if (!App.have_assets) ask_for_folder();
    update_title();

    bool running = true;
    while (running) {
        SDL_Event e;
        while (SDL_PollEvent(&e)) {
            if (e.type == SDL_EVENT_QUIT) running = false;
            else if (e.type == App.ev_folder) {
                App.folder_src = "chosen";
                if (!load_from(App.chosen, true)) ask_for_folder();
                update_title();
            }
            else if (e.type == SDL_EVENT_KEY_DOWN) {
                SDL_Keycode k = e.key.key;
                bool mod = (e.key.mod & (SDL_KMOD_ALT | SDL_KMOD_GUI)) != 0;
                if (k == SDLK_Q && (e.key.mod & SDL_KMOD_GUI)) running = false;
                else if ((k == SDLK_RETURN || k == SDLK_KP_ENTER) && mod) {
                    bool full = (SDL_GetWindowFlags(App.win) & SDL_WINDOW_FULLSCREEN) != 0;
                    SDL_SetWindowFullscreen(App.win, !full);
                }
                else if (k == SDLK_TAB) set_mode((Mode)((App.mode + 1) % MODE_COUNT));
                else if (k == SDLK_F2) {
                    App.aspect_43 = !App.aspect_43;
                    gamelog_display(MODE_NAMES[App.mode], App.aspect_43);
                    update_title();
                }
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
